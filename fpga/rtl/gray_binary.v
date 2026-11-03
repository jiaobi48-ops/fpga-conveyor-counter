`timescale 1ns/1ps
// Pure pixel logic. All state freezes when ce=0; invalid enabled cycles are bubbles.
// RGB layout: [23:16]=R, [15:8]=G, [7:0]=B. White foreground is 1.
module gray_binary (
    input wire clk,
    input wire rst_n,
    input wire ce,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [23:0] in_rgb,
    input wire [7:0] cfg_threshold,
    input wire cfg_invert,
    output reg out_valid,
    output reg out_sof,
    output reg out_eol,
    output reg [7:0] out_gray,
    output reg out_binary
);
    reg [15:0] sum_s1;
    reg valid_s1, sof_s1, eol_s1;
    reg [7:0] threshold_active, threshold_s1;
    reg invert_active, invert_s1;

    always @(posedge clk) begin
        if (!rst_n) begin
            sum_s1 <= 0;
            valid_s1 <= 0; sof_s1 <= 0; eol_s1 <= 0;
            threshold_active <= 8'd128; threshold_s1 <= 8'd128;
            invert_active <= 0; invert_s1 <= 0;
            out_valid <= 0; out_sof <= 0; out_eol <= 0;
            out_gray <= 0; out_binary <= 0;
        end else if (ce) begin
            valid_s1 <= in_valid;
            sof_s1 <= in_valid && in_sof;
            eol_s1 <= in_valid && in_eol;
            if (in_valid) begin
                // Maximum is 255*256+128=65408, safely inside 16 bits.
                sum_s1 <= 16'd77 * {8'd0, in_rgb[23:16]}
                        + 16'd150 * {8'd0, in_rgb[15:8]}
                        + 16'd29 * {8'd0, in_rgb[7:0]} + 16'd128;
                // Apply configuration atomically at the first pixel of a frame.
                threshold_s1 <= in_sof ? cfg_threshold : threshold_active;
                invert_s1 <= in_sof ? cfg_invert : invert_active;
                if (in_sof) begin
                    threshold_active <= cfg_threshold;
                    invert_active <= cfg_invert;
                end
            end
            out_valid <= valid_s1;
            out_sof <= valid_s1 && sof_s1;
            out_eol <= valid_s1 && eol_s1;
            if (valid_s1) begin
                out_gray <= sum_s1[15:8];
                out_binary <= (sum_s1[15:8] >= threshold_s1) ^ invert_s1;
            end
        end
    end
endmodule

