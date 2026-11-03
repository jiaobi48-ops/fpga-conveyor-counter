`timescale 1ns/1ps
module tb_threshold_equivalence;
 reg clk=0,frame_start=0,cfg_auto=0,hold_t=0;
 reg [7:0] manual_t=0,lo=0,hi=255,step_t=0,active_t=0,target_t=0;
 reg [31:0] frame_epoch=0,active_e=0,target_e=0;
 reg target_v=0;wire [7:0] current_selected,reference_selected;
 guarded_adaptive_threshold current_dut(.clk(clk),.rst_n(1'b1),.frame_start(frame_start),.frame_epoch(frame_epoch),.cfg_auto(cfg_auto),.cfg_manual(manual_t),.cfg_min(lo),.cfg_max(hi),.cfg_step(step_t),.stats_update(1'b0),.stats_sum(32'd0),.stats_pixels(32'd0),.stats_frame_id(32'd0),.stats_epoch(32'd0),.stats_auto(1'b0),.stats_min(8'd0),.stats_max(8'd255),.stats_offset(9'sd0),.hold_adaptation(hold_t),.selected_threshold(current_selected));
 reference_guarded_adaptive_threshold reference_dut(.clk(clk),.rst_n(1'b1),.frame_start(frame_start),.frame_epoch(frame_epoch),.cfg_auto(cfg_auto),.cfg_manual(manual_t),.cfg_min(lo),.cfg_max(hi),.cfg_step(step_t),.stats_update(1'b0),.stats_sum(32'd0),.stats_pixels(32'd0),.stats_frame_id(32'd0),.stats_epoch(32'd0),.stats_auto(1'b0),.stats_min(8'd0),.stats_max(8'd255),.stats_offset(9'sd0),.hold_adaptation(hold_t),.selected_threshold(reference_selected));
 initial begin
  force current_dut.active_threshold=active_t;
  force reference_dut.active_threshold=active_t;
  force current_dut.active_epoch=active_e;
  force reference_dut.active_epoch=active_e;
  force current_dut.target_threshold=target_t;
  force reference_dut.target_threshold=target_t;
  force current_dut.target_epoch=target_e;
  force reference_dut.target_epoch=target_e;
  force current_dut.target_valid=target_v;
  force reference_dut.target_valid=target_v;
  for(integer i=0;i<30000;i++)begin
   frame_start=$urandom;cfg_auto=$urandom;hold_t=$urandom;target_v=$urandom;
   manual_t=$urandom;lo=$urandom;hi=$urandom;step_t=$urandom;active_t=$urandom;target_t=$urandom;
   active_e=$urandom;frame_epoch=(i%3)?active_e:$urandom;target_e=(i%4)?frame_epoch:$urandom;
   #1;if(current_selected!==reference_selected)$fatal(1,"FAIL THRESHOLD equivalence sample=%0d got=%d expected=%d",i,current_selected,reference_selected);
  end
  $display("PASS THRESHOLD EQUIVALENCE vectors=30000 epoch/auto/manual/hold/slew/clamp/invalid_bounds");$finish;
 end
endmodule
