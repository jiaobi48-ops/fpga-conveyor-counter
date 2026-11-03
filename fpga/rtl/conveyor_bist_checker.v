`timescale 1ns/1ps
// Physical-clock run oracle. Counts real algorithm events and committed deltas,
// validates identity/continuity, and compares the final Test-total increment.
// Accepted SOF and algorithm packets are inputs, not predictions from RGB data.
module conveyor_bist_checker #(
    parameter integer TIMEOUT_CYCLES=400000000,SETTLE_CYCLES=24,MAX_EVENTS=8
)(
    input wire clk,rst_n,run_start,frame_accept,
    input wire [31:0] source_generation,session_id,
    input wire source_is_test,source_dynamic,
    input wire [1:0] source_profile,
    input wire [31:0] expected_total,
    input wire [15:0] expected_frames,
    input wire motion_update,motion_rejected,motion_is_test,
    input wire [31:0] motion_frame_id,
    input wire [127:0] motion_context,
    input wire [7:0] motion_delta,
    input wire [31:0] test_total,
    input wire event_valid,event_is_test,
    input wire [31:0] event_track_id,event_seq,event_generation,
    input wire pipeline_fault,
    output reg busy,valid,done,passed,aborted,
    output reg [31:0] reason,run_generation,run_session,expected_count,actual_count,event_count,
    output reg [1:0] run_profile,
    output reg [15:0] accepted_frames,motion_frames,
    output reg [31:0] passed_runs,failed_runs,aborted_runs
);
    // Reason bits: 0 timeout; 1 identity/context; 2 frame order/count;
    // 3 pipeline/rejection; 4 duplicate event; 5 event capacity/sequence;
    // 6 total/delta/events mismatch; 7 invalid oracle parameters;
    // 8 source left run; 9 explicit accumulation clear/session change.
    reg [31:0] base_total,delta_sum,timer,last_seq;
    reg [15:0] frames_required;
    reg context_seen,pending,sequence_seen;
    reg [127:0] bound_context;
    reg [31:0] identities[0:MAX_EVENTS-1];
    reg [31:0] settle;
    reg duplicate_id;
    reg [31:0] frame_reasons;
    integer i;
    wire [31:0] observed=test_total-base_total;
    wire current_motion=motion_is_test&&motion_context[127:96]==run_generation;
    wire current_event=event_is_test&&event_generation==run_generation;
    wire interrupted=source_generation!=run_generation||!source_is_test||!source_dynamic;
    task finish;
        input cancel;
        input [31:0] extra_reason;
        begin
            busy<=0;valid<=1;done<=1;aborted<=cancel;
            reason<=frame_reasons|extra_reason;actual_count<=test_total>=base_total ? observed:32'd0;
            passed<=!cancel&&(frame_reasons|extra_reason)==0;
            if(cancel) aborted_runs<=aborted_runs+1'b1;
            else if((frame_reasons|extra_reason)==0) passed_runs<=passed_runs+1'b1;
            else failed_runs<=failed_runs+1'b1;
        end
    endtask
    always @(posedge clk) begin
        done<=0;
        if(!rst_n) begin
            busy<=0;valid<=0;done<=0;passed<=0;aborted<=0;reason<=0;
            run_generation<=0;run_session<=0;run_profile<=0;
            expected_count<=0;actual_count<=0;event_count<=0;
            accepted_frames<=0;motion_frames<=0;passed_runs<=0;failed_runs<=0;aborted_runs<=0;
            base_total<=0;delta_sum<=0;timer<=0;frames_required<=0;
            context_seen<=0;bound_context<=0;pending<=0;settle<=0;last_seq<=0;sequence_seen<=0;
            for(i=0;i<MAX_EVENTS;i=i+1) identities[i]<=0;
        end else if(run_start) begin
            if(busy) aborted_runs<=aborted_runs+1'b1;
            busy<=1;valid<=0;passed<=0;aborted<=0;pending<=0;settle<=0;
            run_generation<=source_generation;run_session<=session_id;run_profile<=source_profile;
            expected_count<=expected_total;frames_required<=expected_frames;
            actual_count<=0;event_count<=0;delta_sum<=0;base_total<=test_total;timer<=0;
            accepted_frames<=frame_accept ? 1:0;motion_frames<=0;context_seen<=0;bound_context<=0;
            last_seq<=0;sequence_seen<=0;
            reason<=expected_frames==0||expected_total>MAX_EVENTS||TIMEOUT_CYCLES<1||
                    SETTLE_CYCLES<1||!source_is_test||!source_dynamic ? 32'h80 : 32'd0;
            for(i=0;i<MAX_EVENTS;i=i+1) identities[i]<=0;
        end else if(busy) begin
            frame_reasons=reason;timer<=timer+1'b1;actual_count<=test_total>=base_total ? observed:32'd0;
            if(session_id!=run_session) finish(1,32'h200);
            else if(interrupted) finish(1,32'h100);
            else if(timer>=TIMEOUT_CYCLES-1) finish(0,32'h1);
            else begin
                if(frame_accept) begin
                    if(accepted_frames>=frames_required) frame_reasons=frame_reasons|32'h4;
                    else accepted_frames<=accepted_frames+1'b1;
                end
                if(pipeline_fault||(motion_rejected&&current_motion)) frame_reasons=frame_reasons|32'h8;
                if(motion_update&&current_motion) begin
                    if(motion_frame_id!={16'd0,motion_frames}+1'b1||motion_frames>=frames_required)
                        frame_reasons=frame_reasons|32'h4;
                    if(context_seen&&motion_context!=bound_context) frame_reasons=frame_reasons|32'h2;
                    context_seen<=1;bound_context<=motion_context;
                    motion_frames<=motion_frames+1'b1;
                    delta_sum<=delta_sum+motion_delta;
                    if(motion_frame_id==frames_required) begin pending<=1;settle<=0;end
                end
                if(event_valid&&current_event) begin
                    duplicate_id=0;
                    for(i=0;i<MAX_EVENTS;i=i+1)
                        if(i<event_count&&identities[i]==event_track_id) duplicate_id=1;
                    if(duplicate_id) frame_reasons=frame_reasons|32'h10;
                    if(event_count>=MAX_EVENTS||(sequence_seen&&event_seq!=last_seq+1'b1)||event_track_id==0)
                        frame_reasons=frame_reasons|32'h20;
                    if(event_count<MAX_EVENTS) identities[event_count]<=event_track_id;
                    event_count<=event_count+1'b1;last_seq<=event_seq;sequence_seen<=1;
                end
                reason<=frame_reasons;
                if(pending) begin
                    if((event_valid&&current_event)||(motion_update&&current_motion)||frame_accept) settle<=0;
                    else if(settle>=SETTLE_CYCLES-1) begin
                        finish(0,((accepted_frames!=frames_required||motion_frames!=frames_required)?32'h4:32'd0)|
                            ((observed!=expected_count||delta_sum!=expected_count||event_count!=expected_count||test_total<base_total)?32'h40:32'd0)|
                            (pipeline_fault?32'h8:32'd0));
                    end else settle<=settle+1'b1;
                end
            end
        end
    end
endmodule
