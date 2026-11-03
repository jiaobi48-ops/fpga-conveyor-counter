`timescale 1ns/1ps
module tb_noise_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,stats_update=0,cfg_auto=0;
 reg [31:0] stats_frame_id=0,stats_epoch=0,stats_foreground=0,stats_isolated=0;
 reg [7:0] cfg_on=0,cfg_off=0,cfg_confirm=0;
 reg [15:0] cfg_min_foreground=0;
 wire rv,pv;wire [1:0] rm,pm;wire [31:0] re,pe,rf,pf;
 noise_policy_reference #(.PIXEL_BITS(19)) reference_policy(
 .clk(clk),.rst_n(rst_n),.stats_update(stats_update),.stats_frame_id(stats_frame_id),.stats_epoch(stats_epoch),
 .stats_foreground(stats_foreground),.stats_isolated(stats_isolated),.cfg_auto(cfg_auto),.cfg_on(cfg_on),.cfg_off(cfg_off),
 .cfg_confirm(cfg_confirm),.cfg_min_foreground(cfg_min_foreground),.mode_valid(rv),.suggested_mode(rm),.mode_epoch(re),.mode_frame_id(rf));
 dynamic_noise_policy #(.PIXEL_BITS(19),.PIPELINED_PRODUCTS(1)) pipelined_policy(
 .clk(clk),.rst_n(rst_n),.stats_update(stats_update),.stats_frame_id(stats_frame_id),.stats_epoch(stats_epoch),
 .stats_foreground(stats_foreground),.stats_isolated(stats_isolated),.cfg_auto(cfg_auto),.cfg_on(cfg_on),.cfg_off(cfg_off),
 .cfg_confirm(cfg_confirm),.cfg_min_foreground(cfg_min_foreground),.mode_valid(pv),.suggested_mode(pm),.mode_epoch(pe),.mode_frame_id(pf));
 reg [66:0] expected=0;integer checks=0,seed=32'h12345,i;reg [31:0] random_word;
 initial begin
  for(i=0;i<30000;i=i+1)begin
   @(negedge clk);
   rst_n=i>2 && i%509!=0;random_word=$random(seed);
   stats_update=(random_word[1:0]!=0);cfg_auto=random_word[4:2]!=0;
   stats_frame_id=stats_frame_id+(random_word[8:7]==0?2:1);
   if(i%97==0)stats_epoch=stats_epoch+1;
   stats_foreground=random_word%384001;
   stats_isolated=i%64<32 ? stats_foreground>>2 : 0;
   cfg_on=64;cfg_off=16;cfg_confirm=3;cfg_min_foreground=16;
   if(i%7==0)begin cfg_on=random_word[23:16];cfg_off=random_word[15:8];cfg_confirm=random_word[11:4];cfg_min_foreground=random_word[31:16];end
   @(posedge clk);#1;
   if(!rst_n)begin expected=0;if({pv,pm,pe,pf}!==67'd0)$fatal(1,"reset cancellation");end
   else begin
    if({pv,pm,pe,pf}!==expected)$fatal(1,"noise mismatch cycle=%0d actual=%h expected=%h",i,{pv,pm,pe,pf},expected);
    checks=checks+1;expected={rv,rm,re,rf};
   end
  end
  $display("PASS NOISE_PIPELINE cycles=30000 checks=%0d coherent_products/thresholds/history/epoch/gaps/invalid_config/reset",checks);$finish;
 end
endmodule
