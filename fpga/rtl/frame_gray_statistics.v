`timescale 1ns/1ps
// Complete raster statistics only. Events use the physical clock; pixels use ce.
module frame_gray_statistics #(
    parameter integer WIDTH=640, HEIGHT=480
) (
    input wire clk,rst_n,ce,in_valid,in_sof,in_eol,
    input wire [7:0] in_gray,
    output reg stats_update,stats_reject,
    output reg [31:0] stats_frame_id,stats_sum,stats_pixels,rejected_frames
);
    reg active,bad;
    reg [15:0] x,y;
    reg [31:0] sequence_id,frame_id,total,pixels;
    wire [15:0] sx=in_sof ? 16'd0 : x;
    wire [15:0] sy=in_sof ? 16'd0 : y;
    wire [31:0] id=in_sof ? sequence_id+1'b1 : frame_id;
    wire legal=(in_sof||active)&&(sx<WIDTH)&&(sy<HEIGHT)&&
               (in_eol==(sx==WIDTH-1));
    wire fault=!legal||(in_sof&&active)||(!in_sof&&bad);
    wire last=(sx==WIDTH-1)&&(sy==HEIGHT-1);
    wire [32:0] sum_next={1'b0,(in_sof ? 32'd0 : total)}+in_gray;
    wire [31:0] pixels_next=(in_sof ? 32'd0 : pixels)+1'b1;
    always @(posedge clk) begin
        if(!rst_n) begin
            active<=0;bad<=0;x<=0;y<=0;sequence_id<=0;frame_id<=0;
            total<=0;pixels<=0;stats_update<=0;stats_reject<=0;
            stats_frame_id<=0;stats_sum<=0;stats_pixels<=0;rejected_frames<=0;
        end else begin
            stats_update<=0;stats_reject<=0;
            if(ce&&in_valid) begin
                if(in_sof) begin
                    sequence_id<=id;frame_id<=id;active<=1;
                    if(active) begin
                        stats_reject<=1;stats_frame_id<=frame_id;
                        rejected_frames<=rejected_frames+1'b1;
                    end
                end
                bad<=fault||sum_next[32];total<=sum_next[31:0];pixels<=pixels_next;
                // Advance by accepted samples, not erroneous EOL, to bound recovery.
                if(sx==WIDTH-1) begin x<=0;y<=sy+1'b1;end
                else begin x<=sx+1'b1;y<=sy;end
                if(last) begin
                    active<=0;stats_frame_id<=id;
                    if(fault||sum_next[32]||pixels_next!=WIDTH*HEIGHT) begin
                        stats_reject<=1;rejected_frames<=rejected_frames+1'b1;
                    end else begin
                        stats_sum<=sum_next[31:0];stats_pixels<=pixels_next;stats_update<=1;
                    end
                end
            end
        end
    end
endmodule
