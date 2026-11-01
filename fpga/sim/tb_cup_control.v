`timescale 1ns/1ps
module tb_cup_control;
 reg pc=0,ac=0;always #17 pc=~pc;always #5 ac=~ac;
 reg rn=0,ft=0,fs=0,lock=0;reg [31:0] req=0;wire [31:0] resp;
 reg [383:0] data=0;
 wire [15:0] ax,bx,gw,y0,y1,onp,offp,wp;
 wire [7:0] th;wire en,mask,mm,mb,rearm,clear,rej;wire [23:0] epoch,session;
 reg token=0;integer n,checks=0;reg [23:0] value;
 integer rearms=0;
 always @(negedge pc)if(rearm)rearms=rearms+1;
 cup_control dut(pc,ac,rn,req,resp,ft,fs,lock,data,ax,bx,gw,y0,y1,onp,offp,wp,th,en,mask,mm,mb,rearm,clear,epoch,session,rej);
 task send;input integer op,v;
  begin @(negedge ac);token=~token;req={token,7'(op),24'(v)};end
 endtask
 task automatic ack;input integer op,err;
  integer cycles;reg matched;
  begin
   matched=0;
   for(cycles=0;cycles<500;cycles=cycles+1)begin
    @(negedge ac);
    if(resp[31]===token && resp[29:24]===op[5:0])begin matched=1;cycles=500;end
   end
   if(!matched||resp[30]!==err[0])$fatal(1,"response op=%0d err%0d got%h",op,err,resp);
   value=resp[23:0];checks=checks+1;
  end
 endtask
 task cmd;input integer op,v,err;begin send(op,v);ack(op,err);end endtask
 task boundary;begin @(negedge pc);ft=1;@(negedge pc);ft=0;fs=1;@(negedge pc);fs=0;end endtask
 initial begin
  repeat(4)@(negedge pc);rn=1;repeat(20)@(negedge pc);
  cmd(0,0,0);if(value!=24'hc30401)$fatal(1,"version");
  cmd(1,500,0);if(ax!=416)$fatal(1,"shadow leaked");
  cmd(2,600,0);cmd(11,0,1);if(ax!=416||epoch!=0)$fatal(1,"invalid changed active");
  cmd(2,460,0);cmd(3,8,0);cmd(7,104,0);cmd(8,50,0);cmd(9,64,0);cmd(10,1,0);
  lock=1;send(11,0);repeat(30)@(negedge pc);
  if(ax!=416||resp[31]===token)$fatal(1,"commit before boundary/early ack");
  boundary();ack(11,0);
  if(ax!=500||bx!=460||gw!=8||epoch!=1||!en||onp!=104)$fatal(1,"commit bundle");
  cmd(1,24'h10001,1);cmd(15,0,0);if(value!=500)$fatal(1,"truncated shadow write");
  data[23:0]=24'd7;data[2*24+:24]=24'd123;
  send(13,0);repeat(25)@(negedge pc);if(resp[31]===token)$fatal(1,"snapshot early ack");
  boundary();ack(13,0);data[23:0]=24'd99;data[2*24+:24]=24'd456;
  cmd(14,0,0);if(value!=7)$fatal(1,"snapshot not frozen");
  cmd(14,2,0);if(value!=123)$fatal(1,"torn snapshot");
  cmd(12,0,0);if(value!=1)$fatal(1,"clear session");cmd(14,0,1);
  lock=0;cmd(13,0,0);cmd(14,0,0);if(value!=99)$fatal(1,"unlocked snapshot");
  cmd(14,16,1);cmd(31,0,1);
  n=rearms;cmd(10,5,0);cmd(11,0,0);
  if(!mm||mb||!en||mask||rearms!=n+1||session!=1)$fatal(1,"manual clear commit/rearm/session");
  n=rearms;cmd(10,7,0);cmd(11,0,0);
  if(!mm||mb||!mask||rearms!=n)$fatal(1,"mask must retain manual/no rearm");
  cmd(10,15,0);cmd(11,0,0);
  if(!mm||!mb||!en||!mask||rearms!=n+1)$fatal(1,"manual block");
  n=rearms;cmd(10,15,0);cmd(11,0,0);if(rearms!=n)$fatal(1,"idempotent mode rearmed");
  cmd(10,9,0);cmd(11,0,1);if(!mm||!mb||!mask)$fatal(1,"invalid mode modified active");
  cmd(10,3,0);cmd(11,0,0);if(mm||mb||!mask||!en||session!=1)$fatal(1,"AUTO restore");
  $display("PASS V3M CONTROL checks=%0d async/shadow/atomic/frozen/session/manual_flags/rearm/idempotence/invalid_mode",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"control watchdog");end
endmodule
