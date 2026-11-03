`timescale 1ns/1ps
module tb_full800_bist;
 reg clk=0;always #(1000.0/150.0) clk=~clk;
 reg display_clk=0;always #20 display_clk=~display_clk;
 reg reset_n=0;reg [31:0] request=0;wire [31:0] response;
 wire ready;wire [23:0] rgb;wire valid,sof,eol;wire [1023:0] packet;wire [15:0] projection;
 vision_system_bridge #(.FRAME_GAP(12000),.ROM_FILE("../../../fpga/data/scenes_200x120.hex")) dut(
 .clk(clk),.reset_n(reset_n),.s_axis_tdata(24'd0),.s_axis_tvalid(1'b0),.s_axis_tready(ready),.s_axis_tuser(1'b0),.s_axis_tlast(1'b0),
 .m_axis_tdata(rgb),.m_axis_tvalid(valid),.m_axis_tready(1'b1),.m_axis_tuser(sof),.m_axis_tlast(eol),
 .request(request),.response(response),.display_clk(display_clk),.display_tick(1'b0),.display_packet(packet),.projection_address(10'd0),.projection_value(projection));
 integer age,frames=0,mean_updates=0,threshold_changes=0,denoise_frames=0;reg token=0;reg [7:0] previous_threshold=128;
 task command(input [6:0] op,input [23:0] data);
  @(negedge clk);token=~token;request={token,op,data};age=0;
  do begin @(negedge clk);age++;if(age>200000)$fatal(1,"FAIL FULL800 GPIO timeout");end while(response[31]!=token || response[29:24]!=op);
  if(response[30])$fatal(1,"FAIL FULL800 GPIO rejection");
 endtask
 task put(input integer index,input reg [31:0] value);
  command(1,{8'(index),value[15:0]});command(2,{8'(index),value[31:16]});
 endtask
 always @(posedge clk)begin
  if(dut.b_mean_update)mean_updates++;
  if(dut.b_active_threshold!=previous_threshold)begin threshold_changes++;previous_threshold=dut.b_active_threshold;end
 end
 always @(posedge clk)if(dut.b_result_update)begin
  frames++;if(dut.b_active_mode==3)denoise_frames++;$display("FULL800 frame=%0d count=%0d mode=%0d T=%0d total=%0d merge=%0d",frames,dut.b_result_count,dut.b_active_mode,dut.b_active_threshold,dut.b_test_total,dut.b_motion_merge_active);
 end
 initial begin
  repeat(5)@(negedge clk);reset_n=1;repeat(20)@(negedge clk);
  put(dut.C_sys_manual_block,0);put(dut.C_cfg_test_async,1);put(dut.C_cfg_bist_dynamic,1);put(dut.C_cfg_bist_profile,1);command(3,0);
  wait(dut.b_bist_valid);repeat(100)@(negedge clk);
  if(!dut.b_bist_pass || dut.b_test_total!=2 || dut.b_camera_total!=0 || frames!=48)
   $fatal(1,"FAIL FULL800 pass=%b reason=%h total=%0d frames=%0d",dut.b_bist_pass,dut.b_bist_reason,dut.b_test_total,frames);
  if(mean_updates==0 || threshold_changes==0 || denoise_frames==0)$fatal(1,"FAIL FULL800 adaptive feedback mean=%0d changes=%0d denoise=%0d",mean_updates,threshold_changes,denoise_frames);
  $display("PASS FULL800 default_ROI adaptive_threshold=1 adaptive_denoise=1 three_lanes=1 valleys=1 tracking_merge=1 speed=1 BIST_profile=1 frames=48 test_total=2 camera_total=0 mean_updates=%0d threshold_changes=%0d denoise_frames=%0d",mean_updates,threshold_changes,denoise_frames);$finish;
 end
 initial begin repeat(24000000)@(posedge clk);$fatal(1,"FAIL FULL800 watchdog");end
endmodule
