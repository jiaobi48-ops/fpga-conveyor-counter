`timescale 1ns/1ps
// Registered 3x3 binary operators. Metadata and mode travel with each pixel.
// window[8:0] = p00,p01,p02,p10,p11,p12,p20,p21,p22.
module morphology_3x3 (
    input wire clk, rst_n, ce,
    input wire in_valid, in_sof, in_eol, in_window_valid,
    input wire [15:0] in_x, in_y,
    input wire [8:0] in_window,
    input wire [1:0] in_mode,
    output reg out_valid, out_sof, out_eol,
    output reg [15:0] out_x, out_y,
    output reg [1:0] out_mode,
    output reg out_center, out_eroded, out_dilated
);
    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 0; out_sof <= 0; out_eol <= 0;
            out_x <= 0; out_y <= 0; out_mode <= 0;
            out_center <= 0; out_eroded <= 0; out_dilated <= 0;
        end else if (ce) begin
            out_valid <= in_valid;
            out_sof <= in_valid && in_sof;
            out_eol <= in_valid && in_eol;
            if (in_valid) begin
                out_x <= in_x; out_y <= in_y; out_mode <= in_mode;
                out_center <= in_window_valid ? in_window[4] : 1'b0;
                out_eroded <= in_window_valid ? (&in_window) : 1'b0;
                out_dilated <= in_window_valid ? (|in_window) : 1'b0;
            end
        end
    end
endmodule
