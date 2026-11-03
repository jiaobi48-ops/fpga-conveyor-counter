`timescale 1ns/1ps

// Native-clock scanner for projection_accumulator's tagged read port.
// Sole owner of the port; no AXI, no video ce. One request/response per clock.
module projection_count_scanner #(
    parameter integer WIDTH=640,
    parameter integer TIMEOUT_CYCLES=4*WIDTH+32
) (
    input wire clk,rst_n,
    input wire snapshot_valid,
    input wire [31:0] snapshot_frame_id,
    input wire [1:0] snapshot_mode,
    input wire [15:0] cfg_high,cfg_low,cfg_min_width,cfg_gap,
    output wire rd_req,
    output wire [15:0] rd_addr,
    input wire rd_ready,rd_valid,rd_error,
    input wire [15:0] rd_resp_addr,rd_data,
    input wire [31:0] rd_frame_id,
    output reg busy,result_valid,result_update,scan_abort,
    // abort_reason: 1 config, 2 snapshot lost/changed, 3 bad response, 4 timeout
    output reg [2:0] abort_reason,
    output reg [31:0] aborted_scans,result_frame_id,
    output reg [15:0] result_count,
    output reg [1:0] result_mode,
    output reg [15:0] result_high,result_low,result_min_width,result_gap,
    // Verified projection samples; useful to store/visualize the actual curve.
    // Samples already emitted by a subsequently aborted scan must be discarded.
    output wire sample_valid,
    output wire [15:0] sample_x,sample_value,
    output wire [31:0] sample_frame_id
);
    reg seen_valid;
    reg [31:0] seen_id,scan_id;
    reg [1:0] scan_mode;
    reg [15:0] high_latched,low_latched,min_latched,gap_latched;
    reg [16:0] issued,received;
    reg [31:0] age;
    reg inside_segment;
    reg [15:0] span,gaps,count;

    wire same_snapshot=snapshot_valid&&(snapshot_frame_id==scan_id);
    wire expired=age>=TIMEOUT_CYCLES-1;
    // received < issued rejects unsolicited responses, even with a matching tag.
    wire response_ok=!rd_error&&(rd_frame_id==scan_id)&&
                     (rd_resp_addr==received[15:0])&&(received<issued);
    assign rd_req=busy&&same_snapshot&&!expired&&(issued<WIDTH)&&
                  (!rd_valid||response_ok);
    assign rd_addr=issued[15:0];
    assign sample_valid=busy&&same_snapshot&&!expired&&rd_valid&&response_ok;
    assign sample_x=rd_resp_addr;
    assign sample_value=rd_data;
    assign sample_frame_id=scan_id;

    // Definition: span is first high column -> last column strictly above low.
    // Short internal gaps are included; trailing low columns are excluded.
    reg inside_next;
    reg [15:0] span_next,gaps_next,count_next;
    always @* begin
        inside_next=inside_segment;span_next=span;gaps_next=gaps;count_next=count;
        if(!inside_segment) begin
            if(rd_data>=high_latched) begin
                inside_next=1;span_next=1;gaps_next=0;
            end
        end else if(rd_data>low_latched) begin
            span_next=span+gaps+1'b1;gaps_next=0;
        end else if(gaps+17'd1>=gap_latched) begin
            if(span>=min_latched) count_next=count+1'b1;
            inside_next=0;span_next=0;gaps_next=0;
        end else gaps_next=gaps+1'b1;
        // Flush exactly once at the final column, including an active last peak.
        if(received==WIDTH-1&&inside_next) begin
            if(span_next>=min_latched) count_next=count_next+1'b1;
            inside_next=0;span_next=0;gaps_next=0;
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            busy<=0;seen_valid<=0;seen_id<=0;scan_id<=0;scan_mode<=0;
            high_latched<=0;low_latched<=0;min_latched<=0;gap_latched<=0;
            issued<=0;received<=0;age<=0;inside_segment<=0;span<=0;gaps<=0;count<=0;
            result_valid<=0;result_update<=0;scan_abort<=0;abort_reason<=0;
            aborted_scans<=0;result_frame_id<=0;result_count<=0;result_mode<=0;
            result_high<=0;result_low<=0;result_min_width<=0;result_gap<=0;
        end else begin
            result_update<=0;scan_abort<=0;
            if(!busy) begin
                if(snapshot_valid&&(!seen_valid||snapshot_frame_id!=seen_id)) begin
                    seen_valid<=1;seen_id<=snapshot_frame_id;
                    if(cfg_high<=cfg_low||cfg_min_width==0||cfg_min_width>WIDTH||
                       cfg_gap==0||cfg_gap>WIDTH) begin
                        scan_abort<=1;abort_reason<=1;aborted_scans<=aborted_scans+1'b1;
                    end else begin
                        busy<=1;scan_id<=snapshot_frame_id;scan_mode<=snapshot_mode;
                        high_latched<=cfg_high;low_latched<=cfg_low;
                        min_latched<=cfg_min_width;gap_latched<=cfg_gap;
                        issued<=0;received<=0;age<=0;
                        inside_segment<=0;span<=0;gaps<=0;count<=0;
                    end
                end
            end else begin
                age<=age+1'b1;
                if(!same_snapshot||expired||(rd_valid&&!response_ok)) begin
                    busy<=0;scan_abort<=1;aborted_scans<=aborted_scans+1'b1;
                    abort_reason<=!same_snapshot ? 3'd2 : expired ? 3'd4 : 3'd3;
                end else begin
                    if(rd_req&&rd_ready) issued<=issued+1'b1;
                    if(sample_valid) begin
                        received<=received+1'b1;
                        inside_segment<=inside_next;span<=span_next;gaps<=gaps_next;count<=count_next;
                        if(received==WIDTH-1) begin
                            busy<=0;result_valid<=1;result_update<=1;
                            result_count<=count_next;result_frame_id<=scan_id;result_mode<=scan_mode;
                            result_high<=high_latched;result_low<=low_latched;
                            result_min_width<=min_latched;result_gap<=gap_latched;
                        end
                    end
                end
            end
        end
    end
endmodule
