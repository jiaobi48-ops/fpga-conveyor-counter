`timescale 1ns/1ps
module tb_cup_passage;
 reg clk=0;always #5 clk=~clk;
 reg rn=0,en=1,clr=0,tick=0,good=1,reject=0;
 reg [15:0] a=0,b=0;
 wire [19:0] count,gray;wire [23:0] bcd;
 wire ga,gb,sat,ft,seen,overflow;wire [1:0] phase;wire [3:0] pending;
 integer i;reg [19:0] prev=0;reg gray_check=0;
 cup_passage #(.MAX_COUNT(12)) dut(clk,rn,en,clr,tick,good,reject,a,b,count,gray,bcd,ga,gb,phase,sat,ft,seen,overflow,pending);
 task frame;
  input integer ap,bp,valid,veto;
  begin @(negedge clk);a=ap;b=bp;good=valid;reject=veto;tick=1;@(negedge clk);tick=0;end
 endtask
 task empty;begin frame(0,0,1,0);frame(0,0,1,0);end endtask
 task cup;begin empty();frame(128,0,1,0);frame(128,128,1,0);frame(0,128,1,0);empty();end endtask
 task expected;input integer n;begin if(count!==n)$fatal(1,"count%0d expected%0d pending%0d phase%0d",count,n,pending,phase);end endtask
 always @(negedge clk)if(gray_check && rn && !clr)begin
  if(((gray^prev)&((gray^prev)-1'b1))!=0)$fatal(1,"Gray multi bit jump");
  if(gray!==((count>>1)^count))$fatal(1,"Gray mismatch");prev=gray;
 end
 initial begin
  repeat(3)@(negedge clk);rn=1;gray_check=1;
  frame(128,128,1,0);frame(0,128,1,0);expected(0);empty();
  frame(128,0,1,0);repeat(100)frame(128,0,1,0);expected(0);
  frame(128,128,1,0);expected(1);
  repeat(50)frame(128,128,1,0);expected(1);
  // Next right entry happens while previous cup still occupies left band.
  // Both bands never become empty through these next three cups.
  for(i=0;i<3;i=i+1)begin
   frame(0,128,1,0);frame(128,128,1,0);expected(i+1);
   frame(128,0,1,0);frame(128,128,1,0);expected(i+2);
  end
  expected(4);empty();
  // Reverse and simultaneous new A/B do not manufacture an A-first token.
  frame(0,128,1,0);frame(128,128,1,0);frame(128,0,1,0);empty();expected(4);
  frame(128,128,1,0);empty();expected(4);
  // A retreat or invalid frame breaks the approach history.
  frame(128,0,1,0);empty();frame(0,128,1,0);empty();expected(4);
  frame(128,0,1,0);frame(128,0,0,0);frame(0,128,1,0);empty();expected(4);
  // Hand at B cannot count an outstanding A token. Its tail cannot count.
  frame(128,0,1,0);frame(128,128,1,1);expected(4);
  frame(128,128,1,0);frame(0,128,1,0);expected(4);empty();
  if(!seen)$fatal(1,"veto diagnostic not retained");
  // Disable/resume also breaks partial passage without resetting the total.
  frame(128,0,1,0);@(negedge clk);en=0;@(negedge clk);en=1;
  frame(0,128,1,0);empty();expected(4);
  // Hysteresis holds occupancy through intermediate pixel totals.
  frame(128,0,1,0);frame(40,0,1,0);frame(40,128,1,0);expected(5);empty();
  for(i=0;i<5;i=i+1)cup();expected(10);
  if(bcd!==24'h000010)$fatal(1,"BCD carry");
  cup();cup();cup();expected(12);if(!sat || bcd!==24'h000012)$fatal(1,"saturation");
  gray_check=0;@(negedge clk);clr=1;@(negedge clk);clr=0;expected(0);
  if(seen||overflow||bcd!==0||gray!==0)$fatal(1,"reset diagnostics");
  // Overflow must not silently wrap or generate B events.
  empty();frame(128,0,1,0);frame(128,128,1,0);expected(1);
  for(i=0;i<10;i=i+1)begin frame(0,128,1,0);frame(128,128,1,0);end
  expected(1);if(!overflow)$fatal(1,"overflow not flagged");
  $display("PASS V2 passage: dense cups without simultaneous empty, pause, repeated frames, reverse, startup, invalid/disable/hand rebaseline, hysteresis, BCD, saturation, queue overflow");
  $finish;
 end
endmodule
