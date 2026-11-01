`timescale 1ns/1ps
module tb_follow_capture;
 reg clk=0;always #5 clk=~clk;
 reg rn=0,valid=0,ready=1,sof=0,eol=0,tok=0;
 reg [23:0] rgb=0;reg [31:0] req=0;wire [31:0] resp;wire active,hold;
 integer x,y,n,checks=0;reg [23:0] value,saved;
 follow_capture #(.WIDTH(48),.HEIGHT(32),.STEP(4),.LEASE_CYCLES(5000)) dut(clk,rn,rgb,valid,ready,sof,eol,req,resp,active,hold);
 task cmd;input integer op,d,err;
 begin
  @(negedge clk);tok=~tok;req={tok,7'(op),24'(d)};
  n=0;while(n<30)begin @(negedge clk);if(resp[31]===tok&&resp[29:24]===op[5:0])break;n=n+1;end
  if(n==30||resp[30]!==1'(err))$fatal(1,"capture ack op%0d %h",op,resp);
  value=resp[23:0];checks=checks+1;
 end endtask
 task frame;input integer offset,badline;
 begin
  for(y=0;y<32;y++)for(x=0;x<48;x++)begin
   @(negedge clk);valid=1;sof=(x==0&&y==0);eol=(x==47 || (badline==1&&y==2&&x==40) || (badline==2&&x==0&&y==0));
   rgb={3{8'(offset+x+y)}};
   if(x==13&&y==4)begin
    ready=0;repeat(4)@(negedge clk);ready=1;
   end
  end
  @(negedge clk);valid=0;sof=0;eol=0;repeat(5)@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rn=1;cmd(0,0,0);if(value!=24'hf10401)$fatal(1,"capture version");
  cmd(3,0,1);cmd(6,1,0);if(!hold||!active)$fatal(1,"must start held");
  cmd(1,0,0);frame(0,0);cmd(2,0,0);if(value!=1)$fatal(1,"complete frame not published %h",value);
  cmd(4,0,0);if(value!=1)$fatal(1,"physical source identity");
  cmd(3,0,0);if(value!=24'h0c0804)$fatal(1,"thumbnail samples %h",value);saved=value;
  frame(50,0);cmd(3,0,0);if(value!=saved)$fatal(1,"frozen RAM overwritten");
  cmd(7,1,0);repeat(3)@(negedge clk);if(hold)$fatal(1,"lease not granted");
  cmd(7,1,1); // Re-reading one old source cannot renew the lease.
  repeat(4000)@(negedge clk);if(!hold||dut.lease==0)$fatal(1,"source-age watchdog must precede lease expiry");
  repeat(1010)@(negedge clk);if(!hold)$fatal(1,"stale source did not expire lease");
  cmd(1,0,0);frame(20,1);cmd(2,0,0);if(!value[1])$fatal(1,"bad line accepted");cmd(3,0,1);
  cmd(1,0,0);frame(25,2);cmd(2,0,0);if(!value[1])$fatal(1,"SOF with early EOL accepted");
  cmd(1,0,0);frame(30,0);cmd(2,0,0);if(value!=1)$fatal(1,"recovery frame");
  cmd(3,32,1);cmd(4,0,0);if(value!=5)$fatal(1,"SOF IDs must include unrequested frames");
  cmd(7,1,0);cmd(7,0,0);if(!hold)$fatal(1,"software hold");
  cmd(6,0,0);if(active||hold)$fatal(1,"manual mode off");
  $display("PASS FOLLOW CAPTURE checks=%0d full-source/accepted-pixels/backpressure/frozen-ownership/packing/bad-EOL/IDs/stale-lease/no-old-renew",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"capture watchdog");end
endmodule
