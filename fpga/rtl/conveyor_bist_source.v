`timescale 1ns/1ps
// One-shot, synthesizable native RGB pattern source. No stored output counts
// are routed into the image algorithm. The oracle is separate run metadata.
// Geometry: WIDTH=128*S, HEIGHT=96*S, S>=1. Single pixel/ce clock.
// Profiles: 0 separated pair; 1 touching/noisy/light ramp; 2 stop/jitter single;
// 3 reverse-only separated pair. Each run is 48 frames, ending in eight blanks.
module conveyor_bist_source #(
    parameter integer WIDTH=640,HEIGHT=480,FRAME_GAP_CYCLES=3026133
)(
    input wire clk,rst_n,ce,enable,restart,
    input wire [1:0] cfg_profile,
    input wire [31:0] cfg_seed,
    output reg out_valid,out_sof,out_eol,
    output reg [23:0] out_rgb,
    output reg [15:0] out_x,out_y,
    output reg [31:0] out_frame_id,
    output reg [1:0] active_profile,
    output wire [31:0] expected_total,
    output reg frame_done,finished,
    output wire configuration_error
);
    localparam integer S=HEIGHT/96;
    assign configuration_error=(S<1)||(WIDTH<128*S)||(HEIGHT!=96*S)||
        (WIDTH>65535)||(HEIGHT>65535)||(FRAME_GAP_CYCLES<0);
    // These constants express independent generated item identities/passages,
    // not a replacement for algorithm output. Profiles are immutable per run.
    assign expected_total=active_profile==2 ? 32'd1 : active_profile==3 ? 32'd0 : 32'd2;
    reg [15:0] x,y;
    reg [5:0] frame_index;
    reg [31:0] gap_left,lfsr;
    reg [15:0] center;
    reg [7:0] background,foreground;
    reg shape,noise;
    wire visible=frame_index<40;
    wire noisy=active_profile==1&&(frame_index<10||(frame_index>=19&&frame_index<=30));
    function [15:0] position;
        input [5:0] f;
        input reverse_motion;
        reg [15:0] p;
        begin
            if(f<6) p=94;
            else if(f<=30) p=109-3*f;
            else case(f)
                31:p=19;32:p=21;33:p=19;34:p=22;35:p=19;
                36:p=21;37:p=18;default:p=19;
            endcase
            position=(reverse_motion ? 113-p : p)*S;
        end
    endfunction
    // Frame geometry is registered independently of pixel CE. Immediately
    // after a frame change only (0,0) can be emitted before this register is
    // refreshed; that pixel is outside every shape/noise band. Thus the exact
    // RGB sequence, including zero-gap frames and CE pauses, is preserved.
    always @(posedge clk) center<=position(frame_index,active_profile==3);
    always @* begin
        background=32;foreground=220;
        if(active_profile==1) begin
            background=frame_index<=30 ? 32+2*frame_index : 92-3*(frame_index-30);
            foreground=220-(frame_index>>1);
        end
        shape=0;
        if(visible) begin
            if(y>=32*S&&y<62*S&&x>=center-6*S&&x<center+7*S) shape=1;
            if(active_profile!=2&&y>=32*S&&y<62*S&&x>=center+16*S&&x<center+29*S) shape=1;
            if(active_profile==1&&y>=46*S&&y<49*S&&x>=center+7*S&&x<center+16*S) shape=1;
        end
        // A sparse pseudo-random mask on a 4-pixel grid preserves single-pixel
        // isolation at every scale. ce pauses also freeze the LFSR sequence.
        noise=noisy&&x>=4&&x<WIDTH-4&&x[1:0]==2&&y[1:0]==2&&lfsr[3:0]!=0&&
            ((y>=8*S&&y<24*S)||(y>=76*S&&y<92*S))&&
            (!visible||x<center-11*S||x>=center+34*S);
    end
    always @(posedge clk) begin
        frame_done<=0;
        if(!rst_n) begin
            x<=0;y<=0;frame_index<=0;gap_left<=0;lfsr<=1;active_profile<=0;
            out_valid<=0;out_sof<=0;out_eol<=0;out_rgb<=0;
            out_x<=0;out_y<=0;out_frame_id<=0;frame_done<=0;finished<=0;
        end else if(!enable||restart) begin
            x<=0;y<=0;frame_index<=0;gap_left<=0;
            lfsr<=cfg_seed==0 ? 32'd1 : cfg_seed;active_profile<=cfg_profile;
            out_valid<=0;out_sof<=0;out_eol<=0;out_rgb<=0;
            out_x<=0;out_y<=0;out_frame_id<=0;finished<=0;
        end else if(ce) begin
            out_valid<=0;out_sof<=0;out_eol<=0;
            if(!finished&&!configuration_error) begin
                if(gap_left!=0) gap_left<=gap_left-1'b1;
                else begin
                    out_valid<=1;out_sof<=x==0&&y==0;out_eol<=x==WIDTH-1;
                    out_x<=x;out_y<=y;out_frame_id<={26'd0,frame_index}+1'b1;
                    out_rgb<=shape||noise ? {foreground,foreground,foreground} : {background,background,background};
                    lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                    if(x==WIDTH-1) begin
                        x<=0;
                        if(y==HEIGHT-1) begin
                            y<=0;frame_done<=1;
                            if(frame_index==47) finished<=1;
                            else begin frame_index<=frame_index+1'b1;gap_left<=FRAME_GAP_CYCLES;end
                        end else y<=y+1'b1;
                    end else x<=x+1'b1;
                end
            end
        end
    end
endmodule
