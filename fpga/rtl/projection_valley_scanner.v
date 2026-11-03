`timescale 1ns/1ps

// New stage-5 interface. The stage-4 scanner/top remain unchanged.
module projection_valley_scanner #(
    parameter integer WIDTH=640, PIPELINED=0,
    parameter integer TIMEOUT_CYCLES=4*WIDTH+32
) (
    input wire clk,rst_n,snapshot_valid,
    input wire [31:0] snapshot_frame_id,
    input wire [1:0] snapshot_mode,
    input wire [15:0] cfg_high,cfg_low,cfg_min_width,cfg_gap,
    input wire cfg_valley_enable,
    input wire [7:0] cfg_valley_ratio,
    input wire [15:0] cfg_valley_depth,cfg_valley_width,cfg_peak_distance,cfg_peak_support,
    output wire rd_req,
    output wire [15:0] rd_addr,
    input wire rd_ready,rd_valid,rd_error,
    input wire [15:0] rd_resp_addr,rd_data,
    input wire [31:0] rd_frame_id,
    output reg busy,result_valid,result_update,scan_abort,
    output reg [2:0] abort_reason,
    output reg [31:0] aborted_scans,result_frame_id,
    output reg [15:0] result_count,result_cut_count,
    output reg [1:0] result_mode,
    output reg [15:0] result_high,result_low,result_min_width,result_gap,
    output reg result_valley_enable,
    output reg [7:0] result_valley_ratio,
    output reg [15:0] result_valley_depth,result_valley_width,result_peak_distance,result_peak_support,
    output wire sample_valid,
    output wire [15:0] sample_x,sample_value,
    output wire [31:0] sample_frame_id,
    output wire cut_update,
    output wire [15:0] cut_x,
    output wire [31:0] cut_frame_id
);
    localparam integer EFFECTIVE_TIMEOUT=PIPELINED?2*TIMEOUT_CYCLES:TIMEOUT_CYCLES;
    reg [1:0] column_cooldown;
    reg seen_valid,finishing;
    reg [31:0] seen_id,scan_id,age;
    reg [1:0] scan_mode;
    reg [16:0] issued,received;
    reg [15:0] high_t,low_t,min_t,gap_t,depth_t,vwidth_t,distance_t,support_t;
    reg enable_t;
    reg [7:0] ratio_t;
    wire base_bad=(cfg_high<=cfg_low)||(cfg_min_width==0)||(cfg_min_width>WIDTH)||
                  (cfg_gap==0)||(cfg_gap>WIDTH);
    wire valley_bad=cfg_valley_enable&&((cfg_valley_ratio==0)||(cfg_valley_depth==0)||
                  (cfg_valley_width==0)||(cfg_valley_width>WIDTH)||
                  (cfg_peak_distance==0)||(cfg_peak_distance>WIDTH)||
                  (cfg_peak_support==0)||(cfg_peak_support>WIDTH));
    wire start=!busy&&snapshot_valid&&(!seen_valid||snapshot_frame_id!=seen_id);
    wire same_snapshot=snapshot_valid&&(snapshot_frame_id==scan_id);
    wire expired=age>=EFFECTIVE_TIMEOUT-1;
    wire response_ok=!rd_error&&(rd_frame_id==scan_id)&&
                     (rd_resp_addr==received[15:0])&&(received<issued);
    assign rd_req=busy&&!finishing&&same_snapshot&&!expired&&(issued<WIDTH)&&
                  (!rd_valid||response_ok)&&(!PIPELINED||(issued==received&&column_cooldown==0));
    assign rd_addr=issued[15:0];
    assign sample_valid=busy&&!finishing&&same_snapshot&&!expired&&rd_valid&&response_ok;
    assign sample_x=rd_resp_addr;
    assign sample_value=rd_data;
    assign sample_frame_id=scan_id;
    assign cut_frame_id=scan_id;
    wire core_done;
    wire [15:0] core_count,core_cuts;
    projection_valley_counter #(.PIPELINED(PIPELINED)) reducer (
        .clk(clk),.rst_n(rst_n),.start(start&&!base_bad&&!valley_bad),
        .sample_valid(sample_valid),.sample_x(rd_resp_addr),.sample_value(rd_data),
        .sample_last(received==WIDTH-1),
        .cfg_high(cfg_high),.cfg_low(cfg_low),.cfg_min_width(cfg_min_width),.cfg_gap(cfg_gap),
        .cfg_valley_enable(cfg_valley_enable),.cfg_valley_ratio(cfg_valley_ratio),
        .cfg_valley_depth(cfg_valley_depth),.cfg_valley_width(cfg_valley_width),
        .cfg_peak_distance(cfg_peak_distance),.cfg_peak_support(cfg_peak_support),
        .done(core_done),.count(core_count),.cut_count(core_cuts),.cut_update(cut_update),.cut_x(cut_x)
    );
    always @(posedge clk) begin
        if(!rst_n||start||!busy)column_cooldown<=0;
        else if(sample_valid)column_cooldown<=3;
        else if(column_cooldown!=0)column_cooldown<=column_cooldown-1'b1;
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            busy<=0;seen_valid<=0;seen_id<=0;scan_id<=0;age<=0;scan_mode<=0;
            finishing<=0;issued<=0;received<=0;
            high_t<=0;low_t<=0;min_t<=0;gap_t<=0;enable_t<=0;ratio_t<=0;
            depth_t<=0;vwidth_t<=0;distance_t<=0;support_t<=0;
            result_valid<=0;result_update<=0;scan_abort<=0;abort_reason<=0;
            aborted_scans<=0;result_frame_id<=0;result_count<=0;result_cut_count<=0;result_mode<=0;
            result_high<=0;result_low<=0;result_min_width<=0;result_gap<=0;
            result_valley_enable<=0;result_valley_ratio<=0;result_valley_depth<=0;
            result_valley_width<=0;result_peak_distance<=0;result_peak_support<=0;
        end else begin
            result_update<=0;scan_abort<=0;
            if(start) begin
                seen_valid<=1;seen_id<=snapshot_frame_id;
                if(base_bad||valley_bad) begin
                    scan_abort<=1;abort_reason<=1;aborted_scans<=aborted_scans+1'b1;
                end else begin
                    busy<=1;finishing<=0;scan_id<=snapshot_frame_id;scan_mode<=snapshot_mode;
                    issued<=0;received<=0;age<=0;
                    high_t<=cfg_high;low_t<=cfg_low;min_t<=cfg_min_width;gap_t<=cfg_gap;
                    enable_t<=cfg_valley_enable;ratio_t<=cfg_valley_ratio;depth_t<=cfg_valley_depth;
                    vwidth_t<=cfg_valley_width;distance_t<=cfg_peak_distance;support_t<=cfg_peak_support;
                end
            end else if(busy) begin
                // All columns were already validated. A new snapshot cannot
                // invalidate a completed reduction during its one commit clock.
                if(finishing&&core_done) begin
                    busy<=0;finishing<=0;result_valid<=1;result_update<=1;
                    result_frame_id<=scan_id;result_mode<=scan_mode;
                    result_count<=core_count;result_cut_count<=core_cuts;
                    result_high<=high_t;result_low<=low_t;result_min_width<=min_t;result_gap<=gap_t;
                    result_valley_enable<=enable_t;result_valley_ratio<=ratio_t;
                    result_valley_depth<=depth_t;result_valley_width<=vwidth_t;
                    result_peak_distance<=distance_t;result_peak_support<=support_t;
                end else if((!finishing&&!same_snapshot)||expired||(rd_valid&&!response_ok)) begin
                    busy<=0;finishing<=0;scan_abort<=1;aborted_scans<=aborted_scans+1'b1;
                    abort_reason<=!same_snapshot ? 3'd2 : expired ? 3'd4 : 3'd3;
                end else begin
                    age<=age+1'b1;
                    if(rd_req&&rd_ready) issued<=issued+1'b1;
                    if(sample_valid) begin
                        received<=received+1'b1;
                        if(received==WIDTH-1) finishing<=1;
                    end
                end
            end
        end
    end
endmodule
