`timescale 1ns/1ps

// Stage 3: RGB -> morphology -> column projection. No AXI protocol logic.
module vision_projection_frontend #(
    parameter integer WIDTH=640,
    parameter integer HEIGHT=480
) (
    input wire clk,rst_n,ce,
    input wire in_valid,in_sof,in_eol,
    input wire [23:0] in_rgb,
    input wire [7:0] cfg_threshold,
    input wire cfg_invert,
    input wire [1:0] cfg_mode,
    output wire out_valid,out_sof,out_eol,out_binary,analysis_valid,
    output wire [15:0] out_x,out_y,out_source_x,out_source_y,
    output wire [1:0] out_mode,
    output wire clear_busy,snapshot_valid,snapshot_update,frame_done,frame_drop,
    output wire [31:0] snapshot_frame_id,snapshot_white_pixels,snapshot_roi_pixels,
    output wire [1:0] snapshot_mode,
    output wire [31:0] dropped_frames,done_frame_id,
    output wire error_sticky,
    input wire rd_req,
    input wire [15:0] rd_addr,
    output wire rd_ready,rd_valid,rd_error,
    output wire [15:0] rd_resp_addr,rd_data,
    output wire [31:0] rd_frame_id
);
    wire raw_pixel,eroded_pixel,dilated_pixel,opened_pixel;
    morphology_frontend #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) pixels (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),.in_rgb(in_rgb),
        .cfg_threshold(cfg_threshold),.cfg_invert(cfg_invert),.cfg_mode(cfg_mode),
        .out_valid(out_valid),.out_sof(out_sof),.out_eol(out_eol),
        .out_x(out_x),.out_y(out_y),.out_source_x(out_source_x),.out_source_y(out_source_y),
        .analysis_valid(analysis_valid),.out_mode(out_mode),.out_binary(out_binary),
        .out_raw(raw_pixel),.out_eroded(eroded_pixel),.out_dilated(dilated_pixel),.out_opened(opened_pixel)
    );
    projection_accumulator #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) projection (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(out_valid),.in_sof(out_sof),.in_eol(out_eol),
        .in_x(out_x),.in_y(out_y),.in_source_x(out_source_x),
        .in_analysis_valid(analysis_valid),.in_binary(out_binary),.in_mode(out_mode),
        .clear_busy(clear_busy),.snapshot_valid(snapshot_valid),.snapshot_update(snapshot_update),
        .frame_done(frame_done),.frame_drop(frame_drop),.done_frame_id(done_frame_id),
        .snapshot_frame_id(snapshot_frame_id),.snapshot_white_pixels(snapshot_white_pixels),
        .snapshot_roi_pixels(snapshot_roi_pixels),.snapshot_mode(snapshot_mode),
        .dropped_frames(dropped_frames),.error_sticky(error_sticky),
        .rd_req(rd_req),.rd_addr(rd_addr),.rd_ready(rd_ready),
        .rd_valid(rd_valid),.rd_error(rd_error),.rd_resp_addr(rd_resp_addr),
        .rd_data(rd_data),.rd_frame_id(rd_frame_id)
    );
endmodule
