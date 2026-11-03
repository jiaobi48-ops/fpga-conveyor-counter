`timescale 1ns/1ps
module tb_configuration_contract;
 reg clk=0;always #(1000.0/150.0) clk=~clk;
 reg display_clk=0;always #20 display_clk=~display_clk;
 reg reset_n=0;reg [31:0] request=0;wire [31:0] response;
 wire ready;wire [23:0] rgb;wire valid,sof,eol;wire [1023:0] packet;wire [15:0] projection;
 vision_system_bridge #(.WIDTH(128),.HEIGHT(96),.SOURCE_WIDTH(136),.SOURCE_HEIGHT(100),.CROP_X(4),.CROP_Y(2),.FRAME_GAP(12000),.ROM_FILE("../../../fpga/data/black_32x24.hex")) dut(
 .clk(clk),.reset_n(reset_n),.s_axis_tdata(24'd0),.s_axis_tvalid(1'b0),.s_axis_tready(ready),.s_axis_tuser(1'b0),.s_axis_tlast(1'b0),
 .m_axis_tdata(rgb),.m_axis_tvalid(valid),.m_axis_tready(1'b1),.m_axis_tuser(sof),.m_axis_tlast(eol),
 .request(request),.response(response),.display_clk(display_clk),.display_tick(1'b0),.display_packet(packet),.projection_address(10'd0),.projection_value(projection));
 integer age,checks=0;reg token=0;
 task cmd(input [6:0] op,input [23:0] data,input expected_error);
  @(negedge clk);token=~token;request={token,op,data};age=0;
  do begin @(negedge clk);age++;if(age>20000)$fatal(1,"FAIL CONFIG GPIO timeout");end while(response[31]!=token || response[29:24]!=op);
  if(response[30]!==expected_error)$fatal(1,"FAIL CONFIG response op=%0d data=%h expected_error=%b got=%h",op,data,expected_error,response);
  checks++;
 endtask
 task put(input integer index,input reg [31:0] value);
  cmd(1,{8'(index),value[15:0]},0);cmd(2,{8'(index),value[31:16]},0);
 endtask
 task get(input integer index,input reg [31:0] expected);
  reg [31:0] got;
  cmd(4,index,0);got[15:0]=response[15:0];cmd(5,index,0);got[31:16]=response[15:0];
  if(got!==expected)$fatal(1,"FAIL CONFIG readback index=%0d expected=%h got=%h",index,expected,got);
 endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;repeat(20)@(negedge clk);
  cmd(0,0,0);get(dut.C_cfg_mean_offset,-24);
  get(dut.C_cfg_source_timeout_cycles,7500000);
  if(dut.live[14]!==32'd75000000)$fatal(1,"FAIL CONFIG algorithm clock readback");
  put(dut.C_cfg_speed_enable,2);cmd(3,0,1);get(dut.C_cfg_speed_enable,1);
  put(dut.C_cfg_speed_enable,1);cmd(3,0,0);
  put(dut.C_cfg_mean_offset,256);cmd(3,0,1);get(dut.C_cfg_mean_offset,-24);
  put(dut.C_cfg_mean_offset,-256);cmd(3,0,0);get(dut.C_cfg_mean_offset,-256);
  put(dut.C_cfg_mean_offset,-24);cmd(3,0,0);get(dut.C_cfg_mean_offset,-24);
  put(dut.C_cfg_hysteresis,65538);cmd(3,0,1);get(dut.C_cfg_hysteresis,2);
  put(dut.C_cfg_hysteresis,2);cmd(3,0,0);
  put(dut.C_cfg_bist_seed,32'h89abcdef);cmd(3,0,0);get(dut.C_cfg_bist_seed,32'h89abcdef);
  put(dut.C_cfg_auto_threshold,0);put(dut.C_cfg_threshold,255);cmd(3,0,0);get(dut.C_cfg_threshold,255);
  put(dut.C_cfg_guard_dark_on,256);cmd(3,0,0);get(dut.C_cfg_guard_dark_on,256);
  put(dut.C_cfg_guard_dark_on,512);cmd(3,0,1);get(dut.C_cfg_guard_dark_on,256);
  put(dut.C_cfg_guard_dark_on,256);put(dut.C_sys_dip_bits,255);cmd(3,0,0);get(dut.C_sys_dip_bits,255);
  cmd(4,77,1);cmd(1,{8'd77,16'd0},1);cmd(7,303,1);cmd(12,128,1);cmd(14,384,1);
  $display("PASS CONFIG checks=%0d typed_shadow/signed9/u16/u32/u9/bool/invalid_half/atomic_reject/repair/range",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"FAIL CONFIG watchdog");end
endmodule
