`timescale 1ns/1ps
module tb_vision_system;
 localparam W=128,H=96,SW=136,SH=100,CX=4,CY=2;
 reg clk=0,display_clk=0;always #(1000.0/150.0) clk=~clk;always #20 display_clk=~display_clk;
 reg rn=0,iv=0,sof=0,eol=0,ready=1,display_tick=0;
 reg [23:0] rgb=0;reg [31:0] request=0;wire [31:0] response;
 wire ir,ov,os,oe;wire [23:0] pixel;wire [1023:0] display_packet;wire [15:0] projection_value;
 vision_system_bridge #(.WIDTH(W),.HEIGHT(H),.SOURCE_WIDTH(SW),.SOURCE_HEIGHT(SH),.CROP_X(CX),.CROP_Y(CY),
  .FRAME_GAP(3000),.ROM_FILE("../../../fpga/data/black_32x24.hex")) dut(
  .clk(clk),.reset_n(rn),.s_axis_tdata(rgb),.s_axis_tvalid(iv),.s_axis_tuser(sof),.s_axis_tlast(eol),.s_axis_tready(ir),
  .m_axis_tdata(pixel),.m_axis_tvalid(ov),.m_axis_tuser(os),.m_axis_tlast(oe),.m_axis_tready(ready),
  .request(request),.response(response),.display_clk(display_clk),.display_tick(display_tick),
  .display_packet(display_packet),.projection_address(10'd40),.projection_value(projection_value));
 reg [23:0] images[0:56*W*H-1];
 integer cycles=0,frames=0,results=0,low_results=0,high_results=0,events=0,cuts=0,speeds=0,modes=0,restores=0;
 integer ox=0,oy=0,pixels=0,checks=0,mean_updates=0,threshold_changes=0;
 reg [7:0] previous_threshold=128;
 reg held=0;reg [25:0] held_pixel;
 reg token=0;reg [31:0] answer;
 string image_file;
 always @(negedge clk)begin
  if(rn)ready=(cycles%137<130);
 end
 always @(posedge clk)begin
  cycles++;
  if(rn)begin
   if(held && {os,oe,pixel}!==held_pixel)$fatal(1,"FAIL INTEGRATION AXIS changed during backpressure");
   held=ov && !ready;held_pixel={os,oe,pixel};
   if(ov && ready)begin
    if(os)begin
     if(pixels!=0 && pixels!=W*H)$fatal(1,"FAIL INTEGRATION short selected frame pixels=%0d",pixels);
     ox=0;oy=0;pixels=0;frames++;
    end
    if(oe!=(ox==W-1))$fatal(1,"FAIL INTEGRATION EOL x=%0d y=%0d",ox,oy);
    if(!dut.b_active_source)begin
     if(dut.crop_id<1 || dut.crop_id>56)$fatal(1,"FAIL INTEGRATION capture identity");
     if(pixel!==(24'hffffff-images[(dut.crop_id-1)*W*H+oy*W+ox]))
      $fatal(1,"FAIL INTEGRATION crop pixel source=%0d x=%0d y=%0d actual=%h",dut.crop_id,ox,oy,pixel);
     checks++;
    end
    pixels++;if(oe)begin ox=0;oy++;end else ox++;
   end
   if(dut.b_mean_update)mean_updates++;
   if(dut.b_active_threshold!=previous_threshold)begin threshold_changes++;previous_threshold=dut.b_active_threshold;end
   if(dut.b_result_update)begin
    results++;cuts+=dut.b_result_cut_count;
    $display("TRACE FRAME id=%0d count=%0d threshold=%0d mode=%0d state=%0d reason=%h fg=%0d permit=%b rejected=%0d",dut.b_result_frame_id,dut.b_result_count,dut.b_active_threshold,dut.b_active_mode,dut.b_safety_state,dut.b_safety_reason,dut.b_safety_foreground_pixels,dut.permit_count,dut.b_motion_rejected_frames);
   end
   if(dut.b_parallel_low_result_update)low_results++;
   if(dut.b_parallel_high_result_update)high_results++;
   if(dut.b_motion_event_valid)events++;
   if(dut.b_speed_update && dut.b_speed_valid)speeds++;
   if(dut.b_active_mode==3)modes++;
   if(dut.b_motion_merge_recovered)restores++;
   if(dut.b_configuration_error || dut.b_source_metadata_error || dut.b_error_sticky || dut.b_parallel_fault_sticky)
    $fatal(1,"FAIL INTEGRATION core fault cfg=%b meta=%b error=%b parallel=%b source=%d",dut.b_configuration_error,dut.b_source_metadata_error,dut.b_error_sticky,dut.b_parallel_fault_sticky,dut.crop_id);
  end
 end
 task command(input integer op,input reg [23:0] data);
  integer n;
  begin
   @(negedge clk);token=~token;request={token,7'(op),data};
   n=0;
   do begin @(negedge clk);n++;if(n>100000)$fatal(1,"FAIL INTEGRATION command timeout op=%0d",op);end
    while(response[31]!=token || response[29:24]!=op);
   if(response[30])$fatal(1,"FAIL INTEGRATION rejected op=%0d reason=%0d",op,response[23:0]);
   answer=response;
  end
 endtask
 task put(input integer index,input reg [31:0] value);
  command(1,{8'(index),value[15:0]});command(2,{8'(index),value[31:16]});
 endtask
 task image(input integer frame);
  integer x,y;reg [23:0] value;
  begin
   for(y=0;y<SH;y++)for(x=0;x<SW;x++)begin
    @(negedge clk);iv=1;sof=x==0&&y==0;eol=x==SW-1;value=24'h123456;
    if(x>=CX && x<CX+W && y>=CY && y<CY+H)value=24'hffffff-images[frame*W*H+(y-CY)*W+x-CX];
    rgb=value;
    do @(posedge clk);while(!ir);
   end
   @(negedge clk);iv=0;sof=0;eol=0;repeat(3500)@(negedge clk);
  end
 endtask
 initial begin
  if(!$value$plusargs("INPUT=%s",image_file))$fatal(1,"FAIL INTEGRATION missing input");
  $readmemh(image_file,images);
  repeat(5)@(negedge clk);rn=1;repeat(20)@(negedge clk);
  command(0,0);if(answer[23:0]!=24'hC31401)$fatal(1,"FAIL INTEGRATION ID");
  put(dut.C_sys_manual_block,0);put(dut.C_cfg_safety_roi_y0,26);command(3,0);
  for(integer f=0;f<56;f++)image(f);
  repeat(5000)@(negedge clk);
  if(dut.b_camera_total!=2 || events!=2)$fatal(1,"FAIL INTEGRATION motion total=%0d events=%0d",dut.b_camera_total,events);
  if(mean_updates==0 || threshold_changes==0)$fatal(1,"FAIL INTEGRATION adaptive feedback mean=%0d changes=%0d",mean_updates,threshold_changes);
  if(results!=56 || low_results!=56 || high_results!=56 || checks!=56*W*H || cuts==0 || speeds==0 || modes==0 || restores==0)
   $fatal(1,"FAIL INTEGRATION features result=%0d/%0d/%0d pixels=%0d cuts=%0d speed=%0d mode=%0d restores=%0d",results,low_results,high_results,checks,cuts,speeds,modes,restores);
  command(6,0);command(7,24'd9);if(answer[15:0]!=2)$fatal(1,"FAIL INTEGRATION GPIO snapshot total");
  // Assert source isolation, no preset count injection, and the actual 48-frame BIST oracle.
  put(dut.C_cfg_test_async,1);put(dut.C_cfg_bist_dynamic,1);command(3,0);
  wait(dut.b_bist_valid);repeat(100)@(negedge clk);
  if(!dut.b_bist_pass || dut.b_test_total!=2 || dut.b_camera_total!=2 || dut.b_bist_actual_count!=2)
   $fatal(1,"FAIL INTEGRATION BIST pass=%b reason=%h test=%0d camera=%0d",dut.b_bist_pass,dut.b_bist_reason,dut.b_test_total,dut.b_camera_total);
  for(integer profile=1;profile<4;profile++)begin
   put(dut.C_cfg_test_async,0);command(3,0);
   wait(!dut.b_active_source && !dut.b_switch_busy);repeat(20)@(negedge clk);
   put(dut.C_cfg_bist_profile,profile);put(dut.C_cfg_test_async,1);command(3,0);
   wait(dut.b_bist_busy);wait(dut.b_bist_valid);repeat(100)@(negedge clk);
   if(!dut.b_bist_pass || dut.b_camera_total!=2 || dut.b_bist_actual_count!=(profile==2?1:profile==3?0:2))
    $fatal(1,"FAIL INTEGRATION BIST profile=%0d reason=%h actual=%0d",profile,dut.b_bist_reason,dut.b_bist_actual_count);
   $display("PASS INTEGRATION BIST_PROFILE profile=%0d expected=%0d actual=%0d",profile,dut.b_bist_expected_count,dut.b_bist_actual_count);
  end
  command(14,24'd12);if(answer[15:0]!=1)$fatal(1,"FAIL INTEGRATION event journal");
  @(negedge display_clk);display_tick=1;@(negedge display_clk);display_tick=0;
  repeat(12)@(negedge display_clk);
  if(display_packet[31:0]!=5 || !display_packet[96+5] || !display_packet[96+11] || display_packet[22*32+:40]!=40'h5)$fatal(1,"FAIL INTEGRATION display CDC/decimal");
  $display("PASS INTEGRATION camera=2 test=5 pixels=%0d three_lane_frames=56 dynamic_denoise=1 valley_cuts=%0d speeds=%0d restored=%0d GPIO=1 BIST_profiles=4 display_CDC=PASS decimal=PASS mean_updates=%0d threshold_changes=%0d",checks,cuts,speeds,restores,mean_updates,threshold_changes);
  $finish;
 end
 initial begin repeat(5000000)@(posedge clk);$fatal(1,"FAIL INTEGRATION watchdog");end
endmodule
