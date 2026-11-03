`timescale 1ns/1ps
// Measures raw binary 3x3 windows before morphology. Center ROI has radius one.
module frame_noise_statistics #(
    parameter integer WIDTH=640, HEIGHT=480
) (
    input wire clk,rst_n,ce,in_valid,in_sof,in_eol,in_binary,
    output reg stats_update,
    output reg [31:0] stats_frame_id,stats_windows,stats_foreground,stats_isolated,
    output reg [31:0] rejected_frames
);
    wire valid,sof,eol,wvalid;
    wire [15:0] wx,wy;
    wire [8:0] window;
    line_buffer_3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) rows(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(in_valid),.in_sof(in_sof),
        .in_eol(in_eol),.in_pixel(in_binary),.out_valid(valid),.out_sof(sof),
        .out_eol(eol),.out_x(wx),.out_y(wy),.out_pixel(),
        .window_valid(wvalid),.out_window(window)
    );
    reg active,bad;
    reg [15:0] x,y;
    reg [31:0] sequence_id,frame_id,windows,foreground,isolated,pixels;
    wire [15:0] sx=sof ? 16'd0 : x;
    wire [15:0] sy=sof ? 16'd0 : y;
    wire [31:0] id=sof ? sequence_id+1'b1 : frame_id;
    wire fault=!(sof||active)||(wx!=sx)||(wy!=sy)||
               (eol!=(sx==WIDTH-1))||(sof&&active)||(!sof&&bad);
    wire center=wvalid&&window[4];
    wire single=center&&((window&9'b111101111)==0);
    wire [31:0] nw=(sof ? 32'd0 : windows)+wvalid;
    wire [31:0] nf=(sof ? 32'd0 : foreground)+center;
    wire [31:0] ni=(sof ? 32'd0 : isolated)+single;
    wire [31:0] np=(sof ? 32'd0 : pixels)+1'b1;
    always @(posedge clk) begin
        if(!rst_n) begin
            active<=0;bad<=0;x<=0;y<=0;sequence_id<=0;frame_id<=0;
            windows<=0;foreground<=0;isolated<=0;pixels<=0;stats_update<=0;
            stats_frame_id<=0;stats_windows<=0;stats_foreground<=0;
            stats_isolated<=0;rejected_frames<=0;
        end else begin
            stats_update<=0;
            if(ce&&valid) begin
                if(sof) begin
                    sequence_id<=id;frame_id<=id;active<=1;
                    if(active) rejected_frames<=rejected_frames+1'b1;
                end
                bad<=fault;windows<=nw;foreground<=nf;isolated<=ni;pixels<=np;
                if(sx==WIDTH-1) begin x<=0;y<=sy+1'b1;end
                else begin x<=sx+1'b1;y<=sy;end
                if(sx==WIDTH-1&&sy==HEIGHT-1) begin
                    active<=0;stats_frame_id<=id;
                    if(fault||np!=WIDTH*HEIGHT||nw!=(WIDTH-2)*(HEIGHT-2))
                        rejected_frames<=rejected_frames+1'b1;
                    else begin
                        stats_update<=1;stats_windows<=nw;
                        stats_foreground<=nf;stats_isolated<=ni;
                    end
                end
            end
        end
    end
endmodule
