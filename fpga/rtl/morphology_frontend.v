`timescale 1ns/1ps
// Gray/threshold -> fixed-latency morphology, eight register stages.
// cfg_mode is delayed with the gray stage, then frame-latched by the filter.
module morphology_frontend #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480
) (
    input wire clk, rst_n, ce,
    input wire in_valid, in_sof, in_eol,
    input wire [23:0] in_rgb,
    input wire [7:0] cfg_threshold,
    input wire cfg_invert,
    input wire [1:0] cfg_mode,
    output wire out_valid, out_sof, out_eol,
    output wire [15:0] out_x, out_y, out_source_x, out_source_y,
    output wire analysis_valid,
    output wire [1:0] out_mode,
    output wire out_binary, out_raw, out_eroded, out_dilated, out_opened
);
    wire g_valid, g_sof, g_eol, g_binary;
    wire [7:0] g_gray;
    reg [1:0] mode_s1, mode_s2;
    always @(posedge clk) begin
        if (!rst_n) begin mode_s1 <= 0; mode_s2 <= 0; end
        else if (ce) begin mode_s1 <= cfg_mode; mode_s2 <= mode_s1; end
    end
    gray_binary gray_stage (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),
        .in_rgb(in_rgb),.cfg_threshold(cfg_threshold),.cfg_invert(cfg_invert),
        .out_valid(g_valid),.out_sof(g_sof),.out_eol(g_eol),
        .out_gray(g_gray),.out_binary(g_binary)
    );
    morphology_filter #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) filter_stage (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(g_valid),.in_sof(g_sof),.in_eol(g_eol),.in_binary(g_binary),
        .cfg_mode(mode_s2),
        .out_valid(out_valid),.out_sof(out_sof),.out_eol(out_eol),
        .out_x(out_x),.out_y(out_y),.out_source_x(out_source_x),.out_source_y(out_source_y),
        .analysis_valid(analysis_valid),.out_mode(out_mode),
        .out_binary(out_binary),.out_raw(out_raw),
        .out_eroded(out_eroded),.out_dilated(out_dilated),.out_opened(out_opened)
    );
endmodule
