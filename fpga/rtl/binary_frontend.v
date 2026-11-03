`timescale 1ns/1ps
// Stage-1 integration top. One shared ce must freeze the entire chain.
module binary_frontend #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480
) (
    input wire clk, rst_n, ce,
    input wire in_valid, in_sof, in_eol,
    input wire [23:0] in_rgb,
    input wire [7:0] cfg_threshold,
    input wire cfg_invert,
    output wire out_valid, out_sof, out_eol,
    output wire [15:0] out_x, out_y,
    output wire out_binary,
    output wire window_valid,
    output wire [8:0] out_window
);
    wire g_valid, g_sof, g_eol, g_binary;
    wire [7:0] g_gray;
    gray_binary u_gray (
        .clk(clk), .rst_n(rst_n), .ce(ce),
        .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol),
        .in_rgb(in_rgb), .cfg_threshold(cfg_threshold), .cfg_invert(cfg_invert),
        .out_valid(g_valid), .out_sof(g_sof), .out_eol(g_eol),
        .out_gray(g_gray), .out_binary(g_binary)
    );
    line_buffer_3x3 #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .DATA_WIDTH(1)) u_window (
        .clk(clk), .rst_n(rst_n), .ce(ce),
        .in_valid(g_valid), .in_sof(g_sof), .in_eol(g_eol), .in_pixel(g_binary),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol),
        .out_x(out_x), .out_y(out_y), .out_pixel(out_binary),
        .window_valid(window_valid), .out_window(out_window)
    );
endmodule
