`timescale 1ns/1ps
// Three rotating row banks with synchronous reads. No RAM initialization/reset.
// Keeps every raster pixel; window_valid marks only complete 3x3 windows.
// out_x/out_y identify the bottom-right input pixel of the window.
module line_buffer_3x3 #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer DATA_WIDTH = 1
) (
    input wire clk,
    input wire rst_n,
    input wire ce,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [DATA_WIDTH-1:0] in_pixel,
    output reg out_valid,
    output reg out_sof,
    output reg out_eol,
    output reg [15:0] out_x,
    output reg [15:0] out_y,
    output reg [DATA_WIDTH-1:0] out_pixel,
    output reg window_valid,
    // MSB to LSB: p00,p01,p02,p10,p11,p12,p20,p21,p22.
    output reg [9*DATA_WIDTH-1:0] out_window
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] row0 [0:WIDTH-1];
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] row1 [0:WIDTH-1];
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] row2 [0:WIDTH-1];
    reg [DATA_WIDTH-1:0] q0, q1, q2;
    reg [15:0] x_pos, y_pos;
    reg [1:0] bank;
    wire [15:0] sample_x = in_sof ? 16'd0 : x_pos;
    wire [15:0] sample_y = in_sof ? 16'd0 : y_pos;
    wire [1:0] sample_bank = in_sof ? 2'd0 : bank;

    // Reads from the bank being written are unused; previous rows never collide.
    always @(posedge clk) begin
        if (rst_n && ce && in_valid) begin
            q0 <= row0[sample_x];
            q1 <= row1[sample_x];
            q2 <= row2[sample_x];
            if (sample_bank == 0) row0[sample_x] <= in_pixel;
            if (sample_bank == 1) row1[sample_x] <= in_pixel;
            if (sample_bank == 2) row2[sample_x] <= in_pixel;
        end
    end

    reg valid_s1, sof_s1, eol_s1;
    reg [15:0] x_s1, y_s1;
    reg [1:0] bank_s1;
    reg [DATA_WIDTH-1:0] pixel_s1;
    reg [DATA_WIDTH-1:0] top_l, top_m, mid_l, mid_m, bot_l, bot_m;
    wire [DATA_WIDTH-1:0] top_now = (bank_s1 == 0) ? q1 :
                                                 (bank_s1 == 1) ? q2 : q0;
    wire [DATA_WIDTH-1:0] mid_now = (bank_s1 == 0) ? q2 :
                                                 (bank_s1 == 1) ? q0 : q1;

    always @(posedge clk) begin
        if (!rst_n) begin
            x_pos <= 0; y_pos <= 0; bank <= 0;
            valid_s1 <= 0; sof_s1 <= 0; eol_s1 <= 0;
            x_s1 <= 0; y_s1 <= 0; bank_s1 <= 0; pixel_s1 <= 0;
            top_l <= 0; top_m <= 0; mid_l <= 0; mid_m <= 0;
            bot_l <= 0; bot_m <= 0;
            out_valid <= 0; out_sof <= 0; out_eol <= 0;
            out_x <= 0; out_y <= 0; out_pixel <= 0;
            window_valid <= 0; out_window <= 0;
        end else if (ce) begin
            valid_s1 <= in_valid;
            sof_s1 <= in_valid && in_sof;
            eol_s1 <= in_valid && in_eol;
            if (in_valid) begin
                x_s1 <= sample_x; y_s1 <= sample_y;
                bank_s1 <= sample_bank; pixel_s1 <= in_pixel;
                if (in_eol) begin
                    x_pos <= 0;
                    if (sample_y == HEIGHT-1) begin
                        y_pos <= 0; bank <= 0;
                    end else begin
                        y_pos <= sample_y + 1'b1;
                        bank <= (sample_bank == 2) ? 2'd0 : sample_bank + 1'b1;
                    end
                end else begin
                    x_pos <= sample_x + 1'b1;
                    y_pos <= sample_y; bank <= sample_bank;
                end
            end
            out_valid <= valid_s1;
            out_sof <= valid_s1 && sof_s1;
            out_eol <= valid_s1 && eol_s1;
            window_valid <= valid_s1 && (x_s1 >= 2) && (y_s1 >= 2);
            if (valid_s1) begin
                out_x <= x_s1; out_y <= y_s1; out_pixel <= pixel_s1;
                if (x_s1 == 0) begin
                    top_l <= 0; top_m <= top_now;
                    mid_l <= 0; mid_m <= mid_now;
                    bot_l <= 0; bot_m <= pixel_s1;
                end else begin
                    top_l <= top_m; top_m <= top_now;
                    mid_l <= mid_m; mid_m <= mid_now;
                    bot_l <= bot_m; bot_m <= pixel_s1;
                end
                if ((x_s1 >= 2) && (y_s1 >= 2))
                    out_window <= {top_l,top_m,top_now,
                                   mid_l,mid_m,mid_now,
                                   bot_l,bot_m,pixel_s1};
                else out_window <= 0;
            end
        end
    end
endmodule

