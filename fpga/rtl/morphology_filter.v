`timescale 1ns/1ps
// Full-raster output with a common VALID interior for all modes.
// A result at raster (x,y) describes source (x-2,y-2); valid only x>=4,y>=4.
// Source border radius 2 is excluded, and every excluded output is zero.
// 0=bypass within valid ROI, 1=erosion, 2=dilation, 3=opening.
module morphology_filter #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480
) (
    input wire clk, rst_n, ce,
    input wire in_valid, in_sof, in_eol, in_binary,
    input wire [1:0] cfg_mode,
    output reg out_valid, out_sof, out_eol,
    output reg [15:0] out_x, out_y, out_source_x, out_source_y,
    output reg analysis_valid,
    output reg [1:0] out_mode,
    output reg out_binary, out_raw, out_eroded, out_dilated, out_opened
);
    reg [1:0] mode_active;
    wire [1:0] mode_token = in_sof ? cfg_mode : mode_active;
    always @(posedge clk) begin
        if (!rst_n) mode_active <= 0;
        else if (ce && in_valid && in_sof) mode_active <= cfg_mode;
    end

    wire a_valid, a_sof, a_eol, a_wvalid;
    wire [15:0] a_x, a_y;
    wire [2:0] a_pixel;
    wire [26:0] a_window;
    // Carry the mode on the actual stream; a newly accepted SOF must not alter
    // the mode of older frame pixels still travelling through either buffer.
    line_buffer_3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DATA_WIDTH(3)) first_rows (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),
        .in_pixel({mode_token,in_binary}),
        .out_valid(a_valid),.out_sof(a_sof),.out_eol(a_eol),
        .out_x(a_x),.out_y(a_y),.out_pixel(a_pixel),
        .window_valid(a_wvalid),.out_window(a_window)
    );
    wire [8:0] first_binary_window;
    genvar i;
    generate
        for (i=0;i<9;i=i+1) begin: first_bits
            assign first_binary_window[i] = a_window[3*i];
        end
    endgenerate

    wire k_valid, k_sof, k_eol;
    wire [15:0] k_x, k_y;
    wire [1:0] k_mode;
    wire k_center, k_eroded, k_dilated;
    morphology_3x3 first_ops (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(a_valid),.in_sof(a_sof),.in_eol(a_eol),
        .in_window_valid(a_wvalid),.in_x(a_x),.in_y(a_y),
        .in_window(first_binary_window),.in_mode(a_pixel[2:1]),
        .out_valid(k_valid),.out_sof(k_sof),.out_eol(k_eol),
        .out_x(k_x),.out_y(k_y),.out_mode(k_mode),
        .out_center(k_center),.out_eroded(k_eroded),.out_dilated(k_dilated)
    );

    wire b_valid, b_sof, b_eol, b_wvalid;
    wire [15:0] b_x, b_y;
    wire [4:0] b_pixel;
    wire [44:0] b_window;
    line_buffer_3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DATA_WIDTH(5)) second_rows (
        .clk(clk),.rst_n(rst_n),.ce(ce),
        .in_valid(k_valid),.in_sof(k_sof),.in_eol(k_eol),
        .in_pixel({k_mode,k_dilated,k_eroded,k_center}),
        .out_valid(b_valid),.out_sof(b_sof),.out_eol(b_eol),
        .out_x(b_x),.out_y(b_y),.out_pixel(b_pixel),
        .window_valid(b_wvalid),.out_window(b_window)
    );
    wire [8:0] erosion_window;
    generate
        for (i=0;i<9;i=i+1) begin: second_bits
            assign erosion_window[i] = b_window[5*i+1];
        end
    endgenerate
    // Center word p11 occupies [24:20]. Center paths align with opening.
    wire raw_center = b_window[20];
    wire eroded_center = b_window[21];
    wire dilated_center = b_window[22];
    wire opened_center = |erosion_window;
    wire interior = b_wvalid && (b_x >= 4) && (b_y >= 4);
    reg selected;
    always @* begin
        case (b_pixel[4:3])
            2'd0: selected = raw_center;
            2'd1: selected = eroded_center;
            2'd2: selected = dilated_center;
            2'd3: selected = opened_center;
            default: selected = 1'b0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 0; out_sof <= 0; out_eol <= 0;
            out_x <= 0; out_y <= 0; out_source_x <= 0; out_source_y <= 0;
            analysis_valid <= 0; out_mode <= 0; out_binary <= 0;
            out_raw <= 0; out_eroded <= 0; out_dilated <= 0; out_opened <= 0;
        end else if (ce) begin
            out_valid <= b_valid;
            out_sof <= b_valid && b_sof;
            out_eol <= b_valid && b_eol;
            analysis_valid <= b_valid && interior;
            if (b_valid) begin
                out_x <= b_x; out_y <= b_y; out_mode <= b_pixel[4:3];
                out_source_x <= interior ? b_x - 16'd2 : 16'd0;
                out_source_y <= interior ? b_y - 16'd2 : 16'd0;
                out_binary <= interior ? selected : 1'b0;
                out_raw <= interior ? raw_center : 1'b0;
                out_eroded <= interior ? eroded_center : 1'b0;
                out_dilated <= interior ? dilated_center : 1'b0;
                out_opened <= interior ? opened_center : 1'b0;
            end
        end
    end
endmodule
