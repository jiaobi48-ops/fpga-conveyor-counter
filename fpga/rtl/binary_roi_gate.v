`timescale 1ns/1ps
// Zero-latency binary mask; raster/valid timing passes unchanged. SOF-bound geometry.
module binary_roi_gate #(
    parameter integer WIDTH=640,HEIGHT=480
)(
    input wire clk,rst_n,ce,in_valid,in_sof,in_eol,in_binary,
    input wire cfg_enable,
    input wire [15:0] cfg_x0,cfg_y0,cfg_x1,cfg_y1,
    output wire out_binary,inside_roi
);
    reg enabled;
    reg [15:0] x,y,x0,y0,x1,y1;
    wire [15:0] sx=in_sof?16'd0:x,sy=in_sof?16'd0:y;
    wire en=in_sof?cfg_enable:enabled;
    wire in_region=in_sof ? (sx>=cfg_x0&&sx<cfg_x1&&sy>=cfg_y0&&sy<cfg_y1) :
        (sx>=x0&&sx<x1&&sy>=y0&&sy<y1);
    assign inside_roi=!en||in_region;
    assign out_binary=in_binary&&inside_roi;
    always @(posedge clk)begin
        if(!rst_n)begin enabled<=0;x<=0;y<=0;x0<=0;y0<=0;x1<=0;y1<=0;end
        else if(ce&&in_valid)begin
            if(in_sof)begin enabled<=cfg_enable;x0<=cfg_x0;y0<=cfg_y0;x1<=cfg_x1;y1<=cfg_y1;end
            if(sx==WIDTH-1)begin x<=0;y<=sy+1'b1;end else begin x<=sx+1'b1;y<=sy;end
        end
    end
endmodule
