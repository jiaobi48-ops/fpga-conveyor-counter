`timescale 1ns / 1ps
// Right-to-left, single-lane interval tracker. All work runs on physical clk.
// A whole detection batch is validated before committing tracks/totals. Events
// belonging to that atomic commit are then serialized, even if flush arrives.
module conveyor_track_counter #(
    parameter integer MAX_TRACKS = 8,
    parameter integer MAX_OBJECTS = MAX_TRACKS
)(
    input wire clk, input wire rst_n, input wire flush, input wire clear_totals,
    input wire batch_valid, output wire batch_ready,
    input wire [31:0] batch_frame_id,
    input wire [127:0] batch_context,
    input wire batch_is_test,
    input wire [7:0] batch_count,
    input wire [MAX_OBJECTS*16-1:0] batch_lefts,
    input wire [MAX_OBJECTS*16-1:0] batch_rights,
    input wire [15:0] cfg_line_a, cfg_line_b, cfg_hysteresis,
    input wire [15:0] cfg_max_step, cfg_width_delta,
    input wire [7:0] cfg_max_missed, cfg_min_hits,
    output wire busy,
    output reg frame_update, output reg frame_rejected,
    output reg [31:0] output_frame_id,
    output reg [127:0] output_context,
    output reg output_is_test,
    output reg [7:0] delta_count,
    output reg [31:0] camera_total, test_total,
    output reg event_valid,
    output reg [31:0] event_track_id, event_frame_id,
    output reg [127:0] event_context,
    output reg event_is_test,
    output reg [31:0] event_seq,
    output reg fault_sticky,
    output reg [15:0] fault_reasons,
    output reg [31:0] rejected_batches, duplicate_batches, uncertain_tracks,
    output reg [7:0] live_tracks,
    output reg debug_valid,
    output reg [31:0] debug_track_id, debug_frame_id,
    output reg [15:0] debug_left, debug_right, debug_center,
    output reg [1:0] debug_phase,
    output reg debug_counted, debug_eligible
);
    localparam [4:0] IDLE=0, CHECK=1, INTERVAL=2, PREP=3, SEARCH=4,
        ASSOC=5, BIRTH=6, AGE=7, ORDER=8, COMMIT=9, EMIT=10,
        DEBUG=11, REJECT=12;
    localparam [15:0] R_CFG=16'h0001, R_CAPACITY=16'h0002,
        R_INTERVAL=16'h0004, R_ASSOC=16'h0008, R_WIDTH=16'h0010,
        R_ORDER=16'h0020, R_LATE=16'h0040, R_UNCERTAIN=16'h0080,
        R_ID=16'h0100, R_TOTAL=16'h0200, R_GAP=16'h0800,
        R_DUP=16'h1000;
    reg [4:0] state;
    assign batch_ready=(state==IDLE)&&!flush&&!clear_totals;
    assign busy=(state!=IDLE);

    reg valid[0:MAX_TRACKS-1], counted[0:MAX_TRACKS-1], eligible[0:MAX_TRACKS-1];
    reg [31:0] identity[0:MAX_TRACKS-1];
    reg [15:0] left_x[0:MAX_TRACKS-1], right_x[0:MAX_TRACKS-1], center_x[0:MAX_TRACKS-1];
    reg [16:0] width_x[0:MAX_TRACKS-1];
    reg [7:0] hits[0:MAX_TRACKS-1], missed[0:MAX_TRACKS-1];
    reg [1:0] phase[0:MAX_TRACKS-1];
    // Candidate arrays are discarded on any pre-commit rejection or flush.
    reg tv[0:MAX_TRACKS-1], tc[0:MAX_TRACKS-1], te[0:MAX_TRACKS-1];
    reg original[0:MAX_TRACKS-1], matched[0:MAX_TRACKS-1];
    reg [31:0] ti[0:MAX_TRACKS-1];
    reg [15:0] tl[0:MAX_TRACKS-1], tr[0:MAX_TRACKS-1], tx[0:MAX_TRACKS-1];
    reg [16:0] tw[0:MAX_TRACKS-1];
    reg [7:0] th[0:MAX_TRACKS-1], tm[0:MAX_TRACKS-1];
    reg [1:0] tp[0:MAX_TRACKS-1];
    reg [7:0] order_rank[0:MAX_TRACKS-1];
    reg ordered_mode;
    reg [15:0] dl[0:MAX_OBJECTS-1], dr[0:MAX_OBJECTS-1];
    reg [31:0] pending_events[0:MAX_TRACKS-1];
    reg [31:0] next_id, candidate_next_id;
    reg last_valid, last_test;
    reg [31:0] last_frame;
    reg [127:0] last_context;
    reg [31:0] fid;
    reg [127:0] context_tag;
    reg source_test;
    reg [7:0] object_count;
    reg [15:0] line_a, line_b, hysteresis, max_step, width_delta;
    reg [7:0] max_missed, min_hits;
    reg [15:0] reject_reason, candidate_reasons;
    reg [7:0] candidate_uncertain, event_count;
    reg [15:0] object_center;
    reg [16:0] object_width;
    integer di, si, candidate_slot, candidates, nearby, age_index;
    integer rank_slot, selected_slot;
    reg rank_found;
    integer oi, oj, emit_index, debug_index;
    integer i, j, rank_value, original_count;
    reg [31:0] frame_distance;
    reg [16:0] distance_x, distance_w;
    reg [8:0] next_hits;
    reg [7:0] valid_count;
    reg [7:0] gap_uncertain;

    function [31:0] add_sat;
        input [31:0] a; input [31:0] b;
        reg [32:0] s;
        begin s={1'b0,a}+{1'b0,b}; add_sat=s[32]?32'hffffffff:s[31:0]; end
    endfunction

    always @(posedge clk) begin
        frame_update<=0; frame_rejected<=0; event_valid<=0; debug_valid<=0;
        if(!rst_n || clear_totals) begin
            state<=IDLE; last_valid<=0; next_id<=1;
            camera_total<=0; test_total<=0; event_seq<=0;
            frame_update<=0; frame_rejected<=0; event_valid<=0; debug_valid<=0;
            output_frame_id<=0; output_context<=0; output_is_test<=0; delta_count<=0;
            event_track_id<=0; event_frame_id<=0; event_context<=0; event_is_test<=0;
            fault_sticky<=0; fault_reasons<=0; rejected_batches<=0;
            duplicate_batches<=0; uncertain_tracks<=0; live_tracks<=0;
            debug_track_id<=0; debug_frame_id<=0; debug_left<=0;
            debug_right<=0; debug_center<=0; debug_phase<=0;
            debug_counted<=0; debug_eligible<=0;
            last_frame<=0; last_context<=0; last_test<=0;
            for(i=0;i<MAX_TRACKS;i=i+1) begin
                valid[i]<=0; counted[i]<=0; eligible[i]<=0;
                identity[i]<=0; left_x[i]<=0; right_x[i]<=0; center_x[i]<=0;
                width_x[i]<=0; hits[i]<=0; missed[i]<=0; phase[i]<=0;
                tv[i]<=0; tc[i]<=0; te[i]<=0; original[i]<=0; matched[i]<=0;
                ti[i]<=0; tl[i]<=0; tr[i]<=0; tx[i]<=0; tw[i]<=0;
                th[i]<=0; tm[i]<=0; tp[i]<=0; pending_events[i]<=0;
            end
        end else begin
            if(flush) begin
                last_valid<=0; live_tracks<=0;
                for(i=0;i<MAX_TRACKS;i=i+1) begin
                    valid[i]<=0; counted[i]<=0; eligible[i]<=0;
                end
                if(state!=EMIT && state!=DEBUG) begin state<=IDLE; delta_count<=0; end
            end
            // A committed event list is a historical packet and must finish.
            if(!flush || state==EMIT || state==DEBUG) begin
                case(state)
                IDLE: if(batch_valid && batch_ready) begin
                    fid<=batch_frame_id; context_tag<=batch_context;
                    source_test<=batch_is_test; object_count<=batch_count;
                    line_a<=cfg_line_a; line_b<=cfg_line_b;
                    hysteresis<=cfg_hysteresis; max_step<=cfg_max_step;
                    width_delta<=cfg_width_delta; max_missed<=cfg_max_missed;
                    min_hits<=cfg_min_hits; event_count<=0;
                    candidate_uncertain<=0; candidate_reasons<=0;
                    candidate_next_id<=next_id;
                    for(i=0;i<MAX_OBJECTS;i=i+1) begin
                        dl[i]<=batch_lefts[16*i+:16]; dr[i]<=batch_rights[16*i+:16];
                    end
                    state<=CHECK;
                end
                CHECK: begin
                    frame_distance=fid-last_frame;
                    if(MAX_TRACKS<1 || MAX_TRACKS>255 || MAX_OBJECTS<1 ||
                       MAX_OBJECTS>MAX_TRACKS || min_hits==0 || max_step==0 ||
                       {1'b0,line_b}<{1'b0,hysteresis} ||
                       ({1'b0,line_a}+{1'b0,hysteresis})>17'd65535 ||
                       {2'b0,line_a}<=({2'b0,line_b}+({2'b0,hysteresis}<<1))) begin
                        reject_reason<=R_CFG; state<=REJECT;
                    end else if(object_count>MAX_OBJECTS) begin
                        reject_reason<=R_CAPACITY; state<=REJECT;
                    end else if(last_valid && context_tag==last_context && source_test==last_test && frame_distance==0) begin
                        reject_reason<=R_DUP; state<=REJECT;
                    end else if(last_valid && context_tag==last_context && source_test==last_test && frame_distance[31]) begin
                        reject_reason<=R_LATE; state<=REJECT;
                    end else begin
                        original_count=0; gap_uncertain=0;
                        for(i=0;i<MAX_TRACKS;i=i+1) begin
                            // Once the previous grace frames are exhausted, an
                            // absent downstream ghost must not compete with a
                            // following target before AGE gets a chance to run.
                            tv[i]<=valid[i] && last_valid && context_tag==last_context && source_test==last_test &&
                                !(missed[i]!=0 && missed[i]>=max_missed);
                            original[i]<=valid[i] && last_valid && context_tag==last_context && source_test==last_test &&
                                !(missed[i]!=0 && missed[i]>=max_missed);
                            matched[i]<=0;
                            tc[i]<=counted[i]; ti[i]<=identity[i];
                            tl[i]<=left_x[i]; tr[i]<=right_x[i]; tx[i]<=center_x[i];
                            tw[i]<=width_x[i]; th[i]<=hits[i]; tm[i]<=missed[i]; tp[i]<=phase[i];
                            te[i]<=eligible[i] && !(missed[i]!=0 && missed[i]>=max_missed);
                            rank_value=0;
                            for(j=0;j<MAX_TRACKS;j=j+1)
                                if(valid[j] && !(missed[j]!=0 && missed[j]>=max_missed) && (center_x[j]<center_x[i] ||
                                   (center_x[j]==center_x[i] && j<i))) rank_value=rank_value+1;
                            order_rank[i]<=rank_value;
                            if(valid[i] && last_valid && context_tag==last_context && source_test==last_test &&
                               !(missed[i]!=0 && missed[i]>=max_missed))
                                original_count=original_count+1;
                            if(valid[i] && last_valid && context_tag==last_context && source_test==last_test &&
                               missed[i]!=0 && missed[i]>=max_missed && eligible[i] && !counted[i])
                                gap_uncertain=gap_uncertain+1'b1;
                            if(last_valid && context_tag==last_context && source_test==last_test && frame_distance>1) begin
                                te[i]<=0;
                                if(valid[i] && !(missed[i]!=0 && missed[i]>=max_missed) && eligible[i] && !counted[i])
                                    gap_uncertain=gap_uncertain+1'b1;
                            end
                        end
                        ordered_mode<=(original_count==object_count && original_count!=0);
                        candidate_uncertain<=gap_uncertain;
                        if(last_valid && context_tag==last_context && source_test==last_test && frame_distance>1)
                            candidate_reasons<=R_GAP|(gap_uncertain!=0?R_UNCERTAIN:16'b0);
                        else if(gap_uncertain!=0) candidate_reasons<=R_UNCERTAIN;
                        di<=0;
                        if(object_count==0) begin age_index<=0; state<=AGE; end
                        else state<=INTERVAL;
                    end
                end
                INTERVAL: begin
                    if(dl[di]>dr[di] || (di>0 && dl[di]<=dr[di-1])) begin
                        reject_reason<=R_INTERVAL; state<=REJECT;
                    end else if(di+1>=object_count) begin di<=0; state<=PREP; end
                    else di<=di+1;
                end
                PREP: begin
                    object_center<=({1'b0,dl[di]}+{1'b0,dr[di]})>>1;
                    object_width<={1'b0,dr[di]}-{1'b0,dl[di]}+1'b1;
                    si<=0; candidates<=0; nearby<=0; candidate_slot<=0;
                    rank_found<=0; rank_slot<=0;
                    state<=SEARCH;
                end
                SEARCH: begin
                    if(original[si]) begin
                        distance_x=object_center>=center_x[si] ?
                            {1'b0,object_center}-{1'b0,center_x[si]} :
                            {1'b0,center_x[si]}-{1'b0,object_center};
                        distance_w=object_width>=width_x[si] ? object_width-width_x[si] : width_x[si]-object_width;
                        if(distance_x<={1'b0,max_step} ||
                           (dl[di]<=right_x[si] && dr[di]>=left_x[si])) nearby<=nearby+1;
                        if(distance_x<={1'b0,max_step} && distance_w<={1'b0,width_delta}) begin
                            candidates<=candidates+1; candidate_slot<=si;
                            if(ordered_mode && order_rank[si]==di) begin rank_found<=1;rank_slot<=si;end
                        end
                    end
                    if(si+1>=MAX_TRACKS) state<=ASSOC;
                    else si<=si+1;
                end
                ASSOC: begin
                    // Prefer a gated monotone rank pair. When an exit and an
                    // entry occur together, rank can shift; a unique gated pair
                    // or a clean upstream birth is still admissible.
                    selected_slot=rank_found?rank_slot:candidate_slot;
                    if((!rank_found && candidates>1) ||
                       (!rank_found && candidates==1 && nearby>1) ||
                       (candidates!=0 && matched[selected_slot])) begin
                        reject_reason<=R_ASSOC; state<=REJECT;
                    end else if(candidates==0 && nearby>0) begin
                        // Possible merge or excessive size change: keep old locks.
                        reject_reason<=R_WIDTH; state<=REJECT;
                    end else if(candidates==0) begin si<=0; state<=BIRTH; end
                    else begin
                        matched[selected_slot]<=1;
                        tl[selected_slot]<=dl[di]; tr[selected_slot]<=dr[di];
                        tx[selected_slot]<=object_center; tw[selected_slot]<=object_width;
                        next_hits={1'b0,hits[selected_slot]}+1'b1;
                        th[selected_slot]<=next_hits[8]?8'hff:next_hits[7:0]; tm[selected_slot]<=0;
                        if(!tc[selected_slot] && te[selected_slot]) begin
                            if(tp[selected_slot]==0 && object_center<=line_a-hysteresis) begin
                                if(missed[selected_slot]!=0 || object_center<=line_b-hysteresis) begin
                                    te[selected_slot]<=0; candidate_uncertain<=candidate_uncertain+1'b1;
                                    candidate_reasons<=candidate_reasons|R_UNCERTAIN;
                                end else tp[selected_slot]<=1;
                            end else if(tp[selected_slot]==1) begin
                                if(object_center>=line_a+hysteresis) tp[selected_slot]<=0;
                                else if(object_center<=line_b-hysteresis) begin
                                    if(missed[selected_slot]!=0 || next_hits<min_hits) begin
                                        te[selected_slot]<=0; candidate_uncertain<=candidate_uncertain+1'b1;
                                        candidate_reasons<=candidate_reasons|R_UNCERTAIN;
                                    end else begin
                                        tc[selected_slot]<=1; tp[selected_slot]<=2;
                                        pending_events[event_count]<=ti[selected_slot];
                                        event_count<=event_count+1'b1;
                                    end
                                end
                            end
                        end
                        if(di+1>=object_count) begin age_index<=0; state<=AGE; end
                        else begin di<=di+1; state<=PREP; end
                    end
                end
                BIRTH: begin
                    if(!tv[si]) begin
                        if(candidate_next_id==0) begin reject_reason<=R_ID; state<=REJECT; end
                        else begin
                            tv[si]<=1; original[si]<=0; matched[si]<=1;
                            ti[si]<=candidate_next_id; candidate_next_id<=candidate_next_id+1'b1;
                            tl[si]<=dl[di]; tr[si]<=dr[di]; tx[si]<=object_center; tw[si]<=object_width;
                            th[si]<=1; tm[si]<=0; tp[si]<=0; tc[si]<=0;
                            te[si]<=object_center>=line_a+hysteresis;
                            if(di+1>=object_count) begin age_index<=0; state<=AGE; end
                            else begin di<=di+1; state<=PREP; end
                        end
                    end else if(si+1>=MAX_TRACKS) begin reject_reason<=R_CAPACITY; state<=REJECT; end
                    else si<=si+1;
                end
                AGE: begin
                    if(original[age_index] && !matched[age_index]) begin
                        th[age_index]<=0;
                        if({1'b0,missed[age_index]}+9'd1>{1'b0,max_missed}) begin
                            tv[age_index]<=0;
                            if(te[age_index] && !tc[age_index]) begin
                                candidate_uncertain<=candidate_uncertain+1'b1;
                                candidate_reasons<=candidate_reasons|R_UNCERTAIN;
                            end
                        end else tm[age_index]<=missed[age_index]+1'b1;
                    end
                    if(age_index+1>=MAX_TRACKS) begin oi<=0; oj<=0; state<=ORDER; end
                    else age_index<=age_index+1;
                end
                ORDER: begin
                    if(oi<oj && original[oi] && original[oj] && matched[oi] && matched[oj] &&
                       ((center_x[oi]<center_x[oj] && tx[oi]>=tx[oj]) ||
                        (center_x[oi]>center_x[oj] && tx[oi]<=tx[oj]))) begin
                        reject_reason<=R_ORDER; state<=REJECT;
                    end else if(oj+1>=MAX_TRACKS) begin
                        oj<=0;
                        if(oi+1>=MAX_TRACKS) state<=COMMIT; else oi<=oi+1;
                    end else oj<=oj+1;
                end
                COMMIT: begin
                    if((source_test && {1'b0,test_total}+event_count>33'h0ffffffff) ||
                       (!source_test && {1'b0,camera_total}+event_count>33'h0ffffffff)) begin
                        reject_reason<=R_TOTAL; state<=REJECT;
                    end else begin
                        valid_count=0;
                        for(i=0;i<MAX_TRACKS;i=i+1) begin
                            valid[i]<=tv[i]; counted[i]<=tc[i]; eligible[i]<=te[i]; identity[i]<=ti[i];
                            left_x[i]<=tl[i]; right_x[i]<=tr[i]; center_x[i]<=tx[i]; width_x[i]<=tw[i];
                            hits[i]<=th[i]; missed[i]<=tm[i]; phase[i]<=tp[i];
                            if(tv[i]) valid_count=valid_count+1'b1;
                        end
                        live_tracks<=valid_count; next_id<=candidate_next_id;
                        last_valid<=1; last_frame<=fid; last_context<=context_tag; last_test<=source_test;
                        output_frame_id<=fid; output_context<=context_tag; output_is_test<=source_test;
                        delta_count<=event_count; frame_update<=1;
                        if(source_test) test_total<=test_total+event_count;
                        else camera_total<=camera_total+event_count;
                        uncertain_tracks<=add_sat(uncertain_tracks,{24'b0,candidate_uncertain});
                        if(candidate_reasons!=0) begin fault_sticky<=1; fault_reasons<=fault_reasons|candidate_reasons; end
                        emit_index<=0; debug_index<=0;
                        if(event_count!=0) state<=EMIT; else state<=DEBUG;
                    end
                end
                EMIT: begin
                    event_valid<=1; event_track_id<=pending_events[emit_index];
                    event_frame_id<=output_frame_id; event_context<=output_context;
                    event_is_test<=output_is_test; event_seq<=event_seq+1'b1;
                    if(emit_index+1>=event_count) state<=DEBUG; else emit_index<=emit_index+1;
                end
                DEBUG: begin
                    if(tv[debug_index]) begin
                        debug_valid<=1; debug_track_id<=ti[debug_index]; debug_frame_id<=output_frame_id;
                        debug_left<=tl[debug_index]; debug_right<=tr[debug_index]; debug_center<=tx[debug_index];
                        debug_phase<=tp[debug_index]; debug_counted<=tc[debug_index]; debug_eligible<=te[debug_index];
                    end
                    if(debug_index+1>=MAX_TRACKS) state<=IDLE; else debug_index<=debug_index+1;
                end
                REJECT: begin
                    frame_rejected<=1; output_frame_id<=fid; output_context<=context_tag;
                    output_is_test<=source_test; delta_count<=0;
                    rejected_batches<=add_sat(rejected_batches,1);
                    if(reject_reason==R_DUP) duplicate_batches<=add_sat(duplicate_batches,1);
                    else fault_sticky<=1;
                    fault_reasons<=fault_reasons|reject_reason; state<=IDLE;
                end
                default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
