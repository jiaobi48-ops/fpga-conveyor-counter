`timescale 1ns/1ps
// Native raster admission. Metadata is sampled at SOF, never inferred from LCD VSYNC.
module camera_frame_identity (
    input wire clk,rst_n,ce,enable,in_valid,in_sof,in_eol,
    input wire [23:0] in_rgb,
    input wire [31:0] in_frame_id,in_generation,in_timestamp,
    output wire out_valid,out_sof,out_eol,
    output wire [23:0] out_rgb,
    output wire [31:0] out_frame_id,out_generation,out_timestamp,
    output reg discontinuity,
    output reg [31:0] duplicate_frames,stale_frames,accepted_frames
);
    reg seen,admitted;
    reg [31:0] last_id,last_generation,held_id,held_generation,held_timestamp;
    wire [31:0] distance=in_frame_id-last_id;
    wire new_generation=!seen||in_generation!=last_generation;
    wire forward=(distance!=0)&&!distance[31];
    wire admit=!enable||new_generation||forward;
    assign out_valid=in_valid&&(in_sof?admit:admitted);
    assign out_sof=in_sof&&out_valid;
    assign out_eol=in_eol&&out_valid;
    assign out_rgb=in_rgb;
    assign out_frame_id=in_sof?in_frame_id:held_id;
    assign out_generation=in_sof?in_generation:held_generation;
    assign out_timestamp=in_sof?in_timestamp:held_timestamp;
    always @(posedge clk) begin
        if(!rst_n) begin
            seen<=0;admitted<=0;last_id<=0;last_generation<=0;
            held_id<=0;held_generation<=0;held_timestamp<=0;
            discontinuity<=0;duplicate_frames<=0;stale_frames<=0;accepted_frames<=0;
        end else begin
            discontinuity<=0;
            if(ce&&in_valid&&in_sof) begin
                admitted<=admit;
                if(admit) begin
                    if(enable&&seen&&(new_generation||distance!=1))discontinuity<=1;
                    seen<=1;last_id<=in_frame_id;last_generation<=in_generation;
                    held_id<=in_frame_id;held_generation<=in_generation;held_timestamp<=in_timestamp;
                    accepted_frames<=accepted_frames+1'b1;
                end else if(distance==0)duplicate_frames<=duplicate_frames+1'b1;
                else begin stale_frames<=stale_frames+1'b1;discontinuity<=1;end
            end
        end
    end
endmodule
