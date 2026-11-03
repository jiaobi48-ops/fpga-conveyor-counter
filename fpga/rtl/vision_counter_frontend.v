`timescale 1ns/1ps

// RGB -> morphology -> projection -> dual-threshold segment count.
// The scanner owns the snapshot read port. Legacy raw read top remains available.
module vision_counter_frontend #(
    parameter integer WIDTH=640,
    parameter integer HEIGHT=480,
    parameter integer SCAN_TIMEOUT=4*WIDTH+32
) (
    input wire clk,rst_n,ce,
    input wire in_valid,in_sof,in_eol,
    input wire [23:0] in_rgb,
    input wire [7:0] cfg_threshold,
    input wire cfg_invert,
    input wire [1:0] cfg_mode,
    input wire [15:0] cfg_high,cfg_low,cfg_min_width,cfg_gap,
    output wire out_valid,out_sof,out_eol,out_binary,analysis_valid,
    output wire [15:0] out_x,out_y,out_source_x,out_source_y,
    output wire [1:0] out_mode,
    output wire clear_busy,snapshot_valid,snapshot_update,frame_done,frame_drop,
    output wire [31:0] snapshot_frame_id,snapshot_white_pixels,snapshot_roi_pixels,
    output wire [1:0] snapshot_mode,
    output wire [31:0] dropped_frames,done_frame_id,
    output wire error_sticky,
    output wire busy,result_valid,result_update,scan_abort,
    output wire [2:0] abort_reason,
    output wire [31:0] aborted_scans,result_frame_id,
    output wire [15:0] result_count,
    output wire [1:0] result_mode,
    output wire [15:0] result_high,result_low,result_min_width,result_gap,
    output wire sample_valid,
    output wire [15:0] sample_x,sample_value,
    output wire [31:0] sample_frame_id
);
    wire req,ready,valid,error;
    wire [15:0] addr,resp_addr,data;
    wire [31:0] read_id;
    vision_projection_frontend #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) frontend (
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(in_valid),.in_sof(in_sof),
        .in_eol(in_eol),.in_rgb(in_rgb),.cfg_threshold(cfg_threshold),
        .cfg_invert(cfg_invert),.cfg_mode(cfg_mode),
        .out_valid(out_valid),.out_sof(out_sof),.out_eol(out_eol),.out_binary(out_binary),
        .analysis_valid(analysis_valid),.out_x(out_x),.out_y(out_y),
        .out_source_x(out_source_x),.out_source_y(out_source_y),.out_mode(out_mode),
        .clear_busy(clear_busy),.snapshot_valid(snapshot_valid),.snapshot_update(snapshot_update),
        .frame_done(frame_done),.frame_drop(frame_drop),.snapshot_frame_id(snapshot_frame_id),
        .snapshot_white_pixels(snapshot_white_pixels),.snapshot_roi_pixels(snapshot_roi_pixels),
        .snapshot_mode(snapshot_mode),.dropped_frames(dropped_frames),.done_frame_id(done_frame_id),
        .error_sticky(error_sticky),.rd_req(req),.rd_addr(addr),.rd_ready(ready),
        .rd_valid(valid),.rd_error(error),.rd_resp_addr(resp_addr),.rd_data(data),.rd_frame_id(read_id)
    );
    projection_count_scanner #(.WIDTH(WIDTH),.TIMEOUT_CYCLES(SCAN_TIMEOUT)) scanner (
        .clk(clk),.rst_n(rst_n),.snapshot_valid(snapshot_valid),
        .snapshot_frame_id(snapshot_frame_id),.snapshot_mode(snapshot_mode),
        .cfg_high(cfg_high),.cfg_low(cfg_low),.cfg_min_width(cfg_min_width),.cfg_gap(cfg_gap),
        .rd_req(req),.rd_addr(addr),.rd_ready(ready),.rd_valid(valid),.rd_error(error),
        .rd_resp_addr(resp_addr),.rd_data(data),.rd_frame_id(read_id),
        .busy(busy),.result_valid(result_valid),.result_update(result_update),
        .scan_abort(scan_abort),.abort_reason(abort_reason),.aborted_scans(aborted_scans),
        .result_frame_id(result_frame_id),.result_count(result_count),.result_mode(result_mode),
        .result_high(result_high),.result_low(result_low),
        .result_min_width(result_min_width),.result_gap(result_gap),
        .sample_valid(sample_valid),.sample_x(sample_x),.sample_value(sample_value),
        .sample_frame_id(sample_frame_id)
    );
endmodule
