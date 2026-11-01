`timescale 1ns/1ps
// A=right, B=left. Independent entry pairing, not simultaneous empty rearming.
module cup_passage #(
 parameter integer ON_PIXELS=52,OFF_PIXELS=25,MAX_COUNT=999999,MAX_PENDING=8
)(
 input wire clk,reset_n,enable,clear_count,frame_tick,frame_good,reject_frame,
 input wire [15:0] a_pixels,b_pixels,
 output reg [19:0] count,count_gray,
 output reg [23:0] count_bcd,
 output reg gate_a,gate_b,
 output reg [1:0] phase,
 output reg saturated,frame_toggle,veto_seen,queue_overflow,
 output reg [3:0] pending
);
 reg waiting,reverse_block,b_counted;
 reg [1:0] clear_frames;
 wire an=(a_pixels>=ON_PIXELS)?1'b1:(a_pixels<=OFF_PIXELS)?1'b0:gate_a;
 wire bn=(b_pixels>=ON_PIXELS)?1'b1:(b_pixels<=OFF_PIXELS)?1'b0:gate_b;
 wire ain=an && !gate_a;
 wire bin=bn && !gate_b;
 reg [4:0] next_pending;
 function [23:0] increment_bcd;
  input [23:0] v;
  integer i;reg carry;reg [23:0] t;
  begin
   t=v;carry=1;
   for(i=0;i<6;i=i+1)if(carry)begin
    if(t[4*i+:4]==9)t[4*i+:4]=0;
    else begin t[4*i+:4]=t[4*i+:4]+1'b1;carry=0;end
   end
   increment_bcd=t;
  end
 endfunction
 always @* begin
  next_pending={1'b0,pending};
  if(ain)next_pending=next_pending+1'b1;
  if(bin && pending!=0)next_pending=next_pending-1'b1;
 end
 always @(posedge clk)begin
  if(!reset_n || clear_count)begin
   count<=0;count_gray<=0;count_bcd<=0;saturated<=0;
   frame_toggle<=0;veto_seen<=0;queue_overflow<=0;
   gate_a<=0;gate_b<=0;phase<=0;pending<=0;
   waiting<=1;reverse_block<=0;b_counted<=0;clear_frames<=0;
  end else if(!enable)begin
   gate_a<=0;gate_b<=0;phase<=0;pending<=0;
   waiting<=1;reverse_block<=0;b_counted<=0;clear_frames<=0;
  end else if(frame_tick)begin
   frame_toggle<=~frame_toggle;
   if(!frame_good || reject_frame)begin
    if(reject_frame)veto_seen<=1;
    gate_a<=0;gate_b<=0;pending<=0;waiting<=1;
    reverse_block<=0;b_counted<=0;clear_frames<=0;
    phase<=reject_frame?3:0;
   end else begin
    gate_a<=an;gate_b<=bn;
    if(waiting || reverse_block)begin
     pending<=0;b_counted<=0;phase<=reverse_block?3:0;
     if(!an && !bn)begin
      if(clear_frames==1)begin
       waiting<=0;reverse_block<=0;clear_frames<=0;phase<=1;
      end else clear_frames<=clear_frames+1'b1;
     end else clear_frames<=0;
    end else if(bin && pending==0)begin
     // B-first/simultaneous arrival has no previously observed A token.
     pending<=0;reverse_block<=1;b_counted<=0;phase<=3;clear_frames<=0;
    end else if(ain && bn && !b_counted && !bin)begin
     pending<=0;reverse_block<=1;b_counted<=0;phase<=3;clear_frames<=0;
    end else if(next_pending>MAX_PENDING)begin
     queue_overflow<=1;pending<=0;waiting<=1;
     b_counted<=0;phase<=3;clear_frames<=0;
    end else begin
     if(!bn)b_counted<=0;
     if(bin && pending!=0)begin
      b_counted<=1;
      if(count<MAX_COUNT)begin
       count<=count+1'b1;
       count_gray<=((count+20'd1)>>1)^(count+20'd1);
       count_bcd<=increment_bcd(count_bcd);
      end else saturated<=1;
     end
     pending<=next_pending[3:0];phase<=next_pending!=0?2:1;
     // Abort a retreat/missed approach, but never time out a stopped cup.
     if(!an && !bn)begin pending<=0;b_counted<=0;phase<=1;end
    end
   end
  end
 end
endmodule
