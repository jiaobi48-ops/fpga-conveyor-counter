`timescale 1ns/1ps
module tb_cup_v3_video;
 reg pc=0,ac=0;always #20 pc=~pc;always #5 ac=~ac;
 reg fa=0,fh=0;
 reg rn=0,lock=0,de=0,vs=0,token=0;reg [31:0] request=0;
 reg [23:0] rgb=24'he0e0e0;
 wire [31:0] response;wire [23:0] out_rgb;wire od,hs,vso,bl,cl,rst,hr;
 integer x,y,t,a,b,shape_y=80,hand=0,both_empty=0,n,checks=0;
 integer dark_upper=0,short_line=0,blocked_before;
 reg [23:0] value;
 lcd_video_bridge dut(pc,ac,rn,lock,rgb,de,vs,request,response,out_rgb,od,hs,vso,bl,cl,rst,hr,fa,fh);
 task boundary;begin @(negedge pc);vs=1;repeat(2)@(negedge pc);vs=0;repeat(4)@(negedge pc);end endtask
 task frame;input integer ca,cb;
 begin
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<800-((short_line&&y==479)?1:0);x=x+1)begin
    @(negedge pc);de=1;rgb=24'he0e0e0;
    if(y>=shape_y && y<shape_y+52 && ((x>=ca&&x<ca+80)||(x>=cb&&x<cb+80)))rgb=24'h607080;
    if(y>=shape_y-8 && y<shape_y && ((x>=ca-8&&x<ca+88)||(x>=cb-8&&x<cb+88)))rgb=24'h607080;
    if(hand && y<150 && x>=300&&x<600)rgb=24'hff9860;
    if(dark_upper && y>=8 && y<48 && x>=320 && x<480)rgb=24'h303030;
    if(x==100&&y==300)begin @(posedge pc);#1;if(out_rgb!==rgb||!od)$fatal(1,"raw LCD altered");end
    if(x==360&&y==18)begin @(posedge pc);#1;
     if(out_rgb!==(dut.manual_mode?24'h80dfff:24'h000000))$fatal(1,"mode glyph pixel");end
   end
   @(negedge pc);de=0;repeat(3)@(negedge pc);
  end
  boundary();
  if(dut.count==1&&!dut.gate_a&&!dut.gate_b)both_empty=both_empty+1;
 end endtask
 task cmd;input integer op,v,err;
 begin
  @(negedge ac);token=~token;request={token,7'(op),24'(v)};
  if(op==11)begin repeat(20)@(negedge pc);boundary();end
  if(op==13)frame(900,1000);
  n=0;while(n<1000)begin @(negedge ac);if(response[31]===token && response[29:24]===op[5:0])break;n=n+1;end
  if(n==1000||response[30]!==1'(err))$fatal(1,"video response op%0d %h",op,response);
  value=response[23:0];checks=checks+1;
 end endtask
 initial begin
  repeat(4)@(negedge pc);rn=1;repeat(30)@(negedge pc);
  cmd(0,0,0);cmd(10,1,0);cmd(11,0,0);
  lock=1;boundary();frame(900,1000);frame(900,1000);
  for(t=0;t<36;t=t+1)frame(430-8*t,526-8*t);
  if(dut.count!==2||both_empty!=0||dut.queue_overflow)$fatal(1,"dense count%0d both_empty%0d",dut.count,both_empty);
  hand=1;frame(900,1000);frame(900,1000);hand=0;
  if(dut.count!==2||!dut.veto_seen)$fatal(1,"hand increments/not vetoed");
  frame(900,1000);frame(900,1000);
  frame(410,900);repeat(3)frame(410,900);if(dut.count!==2)$fatal(1,"stop increments");
  frame(370,900);frame(320,900);frame(200,900);if(dut.count!==3)$fatal(1,"post hand recovery");
  cmd(13,0,0);cmd(14,0,0);if((value&24'h0fffff)!=3)$fatal(1,"snapshot count");
  cmd(14,1,0);if(!value[3]||!value[2])$fatal(1,"snapshot valid flags");
  frame(410,900);cmd(14,5,0);if(value!=0)$fatal(1,"snapshot updated during page reads");
  // Move/resize while an A token is pending: count preserved, token cancelled.
  cmd(1,500,0);cmd(2,460,0);cmd(3,8,0);cmd(4,180,0);cmd(5,212,0);
  cmd(7,104,0);cmd(8,50,0);cmd(9,64,0);
  if(dut.ax0!=416||dut.y0!=96)$fatal(1,"active partial ROI write");
  cmd(11,0,0);if(dut.count!==3||dut.pending!=0)$fatal(1,"commit count/history");
  shape_y=164;frame(900,1000);frame(900,1000);
  frame(495,900);frame(455,900);frame(400,900);frame(300,900);
  if(dut.count!==4)$fatal(1,"resized/moved geometry count%0d",dut.count);
  cmd(1,10,0);cmd(11,0,1);if(dut.ax0!=500||dut.count!=4)$fatal(1,"bad ROI accepted");
  // A dark background in the fixed upper region triggers AUTO, even without a hand.
  cmd(1,500,0);dark_upper=1;frame(900,1000);
  if(!dut.upper_veto||!dut.effective_blocked)$fatal(1,"AUTO dark background must veto");
  frame(495,900);frame(455,900);frame(300,900);if(dut.count!=4)$fatal(1,"AUTO veto failed");
  // Manual clear bypasses the color/upper veto only. Raw diagnostics remain visible.
  cmd(10,5,0);cmd(11,0,0);frame(900,1000);frame(900,1000);
  if(!dut.manual_mode||dut.manual_block||dut.effective_blocked||!dut.upper_veto)$fatal(1,"manual clear/raw veto");
  blocked_before=dut.blocked_frames;
  frame(495,900);frame(455,900);frame(300,900);
  if(dut.count!=5||dut.blocked_frames!=blocked_before)$fatal(1,"manual count under dark background");
  cmd(13,0,0);cmd(14,1,0);
  if(!value[10]||value[11]||value[12]||!value[8]||!value[3])$fatal(1,"manual snapshot flags");
  // A mode switch cancels an incomplete A event, but never resets accumulated count.
  frame(495,900);if(dut.pending==0)$fatal(1,"missing pending event for switch test");
  cmd(10,13,0);cmd(11,0,0);frame(455,900);frame(300,900);
  if(dut.count!=5||dut.pending!=0||!dut.effective_blocked)$fatal(1,"manual hold count/history");
  cmd(13,0,0);cmd(14,1,0);if(!value[10]||!value[11]||!value[12])$fatal(1,"hold snapshot flags");
  // Release while occupied: no tail is counted; empty gates are required to rearm.
  cmd(10,5,0);cmd(11,0,0);frame(455,900);frame(300,900);
  if(dut.count!=5)$fatal(1,"release phantom tail");
  frame(900,1000);frame(900,1000);
  frame(495,900);short_line=1;frame(455,900);short_line=0;frame(300,900);
  if(dut.count!=5)$fatal(1,"manual mode bypassed frame integrity");
  frame(900,1000);frame(900,1000);frame(495,900);
  lock=0;repeat(20)@(negedge pc);if(dut.pending!=0||dut.count!=5||od)$fatal(1,"manual lock guard");
  lock=1;boundary();frame(455,900);frame(300,900);
  if(dut.count!=5)$fatal(1,"unlock phantom tail");
  frame(900,1000);frame(900,1000);frame(495,900);frame(455,900);frame(300,900);
  if(dut.count!=6)$fatal(1,"manual recovery valid cup");
  cmd(10,1,0);cmd(11,0,0);frame(900,1000);
  if(dut.manual_mode||!dut.effective_blocked||dut.count!=6)$fatal(1,"AUTO restore veto/total");
  // A separate follow inhibit must not be bypassed by manual U.
  cmd(10,5,0);cmd(11,0,0);dark_upper=0;frame(900,1000);frame(900,1000);
  frame(495,900);fa=1;fh=1;repeat(10)@(negedge pc);
  frame(455,900);frame(300,900);if(dut.count!=6||dut.pending!=0)$fatal(1,"follow hold bypassed by U");
  fh=0;frame(455,900);frame(300,900);if(dut.count!=6)$fatal(1,"follow release phantom");
  frame(900,1000);frame(900,1000);frame(495,900);frame(455,900);frame(300,900);
  if(dut.count!=7)$fatal(1,"follow release recovery");
  // Moving a gate across a stopped cup while following is held must not count.
  frame(495,900);fh=1;repeat(10)@(negedge pc);
  cmd(1,540,0);cmd(2,500,0);cmd(11,0,0);repeat(3)frame(495,900);
  fh=0;repeat(3)frame(495,900);if(dut.count!=7)$fatal(1,"stationary cup counted by moving gates");
  frame(900,1000);frame(900,1000);frame(535,900);frame(495,900);frame(400,900);
  if(dut.count!=8)$fatal(1,"post-relocation count recovery");
  cmd(12,0,0);repeat(20)@(negedge pc);if(dut.count!=0)$fatal(1,"clear pulse");
  $display("PASS V3M VIDEO checks=%0d dense/hand/ROI/manual_clear/hold/no_phantom/retained_total/raw_flags/AUTO_restore/frame_integrity/lock/mode_glyph",checks);
  $finish;
 end
 initial begin #2000000000;$fatal(1,"video watchdog");end
endmodule
