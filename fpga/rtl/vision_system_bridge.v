`timescale 1ns/1ps
// Native raster integration. AXI transport and CDC FIFOs are AMD IP in system.bd.
module vision_system_bridge #(
 parameter integer WIDTH=800,HEIGHT=480,SOURCE_WIDTH=1280,SOURCE_HEIGHT=720,
 parameter integer CROP_X=240,CROP_Y=120,FRAME_GAP=2116000,
 parameter ROM_FILE="scenes_200x120.hex"
)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK" *)
 (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME clk, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET reset_n, FREQ_HZ 75000000" *) input wire clk,
 (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 reset_n RST" *)
 (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME reset_n, POLARITY ACTIVE_LOW" *) input wire reset_n,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input wire [23:0] s_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input wire s_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output wire s_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TUSER" *) input wire s_axis_tuser,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input wire s_axis_tlast,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output wire [23:0] m_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TUSER" *) output wire m_axis_tuser,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast,
 input wire [31:0] request,output reg [31:0] response,
 input wire display_clk,display_tick,
 output reg [1023:0] display_packet,
 input wire [9:0] projection_address,output reg [15:0] projection_value
);
 reg [31:0] active[0:76],shadow[0:76],defaults[0:76];
 reg [76:0] bad_low,bad_high;
 reg mean_high_sign;
 reg [31:0] live[0:302],frozen[0:302];
 reg [31:0] snapshot_seq,source_frames,raw_errors,physical_ticks;
 reg [15:0] rx,ry;
 reg source_seen,source_bad;
 reg crop_valid,crop_sof,crop_eol,crop_fault;
 reg [23:0] crop_rgb;
 reg [31:0] crop_id,crop_stamp,source_stamp;
 reg clear_pulse,rearm_pulse;
 reg [31:0] pulse_seen;
 reg [15:0] video_y;
 reg [3:0] cut_count;
 reg [15:0] cuts[0:7];
 reg [31:0] bcd_input,bcd_shift,last_bcd_total;
 reg [39:0] bcd_work,bcd_total;
 reg [5:0] bcd_steps;
 reg bcd_running;
 reg [39:0] bcd_adjusted;
 wire link_fault;
 `include "vision_bindings.vh"
 assign link_fault=active[C_sys_manual_mode][0] && active[C_sys_manual_block][0];

 assign s_axis_tready=native_ce;
 assign m_axis_tdata=b_selected_rgb;
 assign m_axis_tvalid=b_selected_valid;
 assign m_axis_tuser=b_selected_sof;
 assign m_axis_tlast=b_selected_eol;
 wire [15:0] px=s_axis_tuser?16'd0:rx;
 wire [15:0] py=s_axis_tuser?16'd0:ry;
 wire source_take=s_axis_tvalid && s_axis_tready;
 wire raw_bad=(s_axis_tlast!=(px==SOURCE_WIDTH-1)) || px>=SOURCE_WIDTH || py>=SOURCE_HEIGHT;
 always @(posedge clk)begin
  if(!reset_n)begin
   physical_ticks<=0;source_frames<=0;raw_errors<=0;rx<=0;ry<=0;source_seen<=0;source_bad<=0;
   crop_valid<=0;crop_sof<=0;crop_eol<=0;crop_fault<=0;crop_rgb<=0;crop_id<=0;crop_stamp<=0;source_stamp<=0;
  end else begin
   physical_ticks<=physical_ticks+1'b1;crop_fault<=0;
   if(native_ce)begin
    crop_valid<=0;crop_sof<=0;crop_eol<=0;
    if(source_take)begin
     if(s_axis_tuser)begin
      source_seen<=1;source_bad<=raw_bad;source_frames<=source_frames+1'b1;source_stamp<=physical_ticks;
     end else if(raw_bad)source_bad<=1;
     if(raw_bad && (!source_bad || s_axis_tuser))begin raw_errors<=raw_errors+1'b1;crop_fault<=1;end
     if(s_axis_tlast)begin rx<=0;ry<=py+1'b1;end else begin rx<=px+1'b1;ry<=py;end
     if((source_seen || s_axis_tuser) && (!source_bad || s_axis_tuser) && !raw_bad &&
        px>=CROP_X && px<CROP_X+WIDTH && py>=CROP_Y && py<CROP_Y+HEIGHT)begin
      crop_valid<=1;crop_sof<=px==CROP_X && py==CROP_Y;crop_eol<=px==CROP_X+WIDTH-1;
      crop_rgb<=s_axis_tdata;
      if(px==CROP_X && py==CROP_Y)begin
       crop_id<=s_axis_tuser?source_frames+1'b1:source_frames;
       crop_stamp<=s_axis_tuser?physical_ticks:source_stamp;
      end
     end
    end
   end
  end
 end

 always @* begin
  bcd_adjusted=bcd_work;
  for(integer digit=0;digit<10;digit=digit+1)
   if(bcd_work[digit*4+:4]>=5)bcd_adjusted[digit*4+:4]=bcd_work[digit*4+:4]+4'd3;
 end
 always @(posedge clk)begin
  if(!reset_n)begin
   bcd_input<=0;bcd_shift<=0;last_bcd_total<=32'hffffffff;bcd_work<=0;bcd_total<=0;bcd_steps<=0;bcd_running<=0;
   cut_count<=0;for(integer c=0;c<8;c=c+1)cuts[c]<=0;
  end else begin
   if(b_sample_valid && b_sample_x==0)cut_count<=0;
   if(b_cut_update && cut_count<8)begin cuts[cut_count]<=b_cut_x;cut_count<=cut_count+1'b1;end
   if(!bcd_running && last_bcd_total!=(b_active_source?b_test_total:b_camera_total))begin
    bcd_input<=b_active_source?b_test_total:b_camera_total;bcd_shift<=b_active_source?b_test_total:b_camera_total;
    bcd_work<=0;bcd_steps<=0;bcd_running<=1;
   end else if(bcd_running)begin
    bcd_work<={bcd_adjusted[38:0],bcd_shift[31]};bcd_shift<={bcd_shift[30:0],1'b0};bcd_steps<=bcd_steps+1'b1;
    if(bcd_steps==31)begin bcd_total<={bcd_adjusted[38:0],bcd_shift[31]};last_bcd_total<=bcd_input;bcd_running<=0;end
   end
  end
 end

function config_half_ok;
 input integer index;input high_half;input [15:0] value;
 begin case(index)
  0:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  1:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  2:config_half_ok=high_half ? (value==16'd0) : (value<=16'd3);
  3:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  4:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  5:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  6:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  7:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  8:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  9:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  10:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  11:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  12:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  13:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  14:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  15:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  16:config_half_ok=high_half ? (value==16'd0||value==16'hffff) : (value[15:9]=={7{value[8]}});
  17:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  18:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  19:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  20:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  21:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  22:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  23:config_half_ok=high_half ? (value==16'd0) : (value<=16'd3);
  24:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  25:config_half_ok=high_half ? (1'b1) : (1'b1);
  26:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  27:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  28:config_half_ok=high_half ? (value==16'd0) : (value<=16'd3);
  29:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  30:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  31:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  32:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  33:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  34:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  35:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  36:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  37:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  38:config_half_ok=high_half ? (value==16'd0) : (value<=16'd3);
  39:config_half_ok=high_half ? (1'b1) : (1'b1);
  40:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  41:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  42:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  43:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  44:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  45:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  46:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  47:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  48:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  49:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  50:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  51:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  52:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  53:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  54:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  55:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  56:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  57:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  58:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  59:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  60:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  61:config_half_ok=high_half ? (value==16'd0) : (1'b1);
  62:config_half_ok=high_half ? (value==16'd0) : (value<=16'd511);
  63:config_half_ok=high_half ? (value==16'd0) : (value<=16'd511);
  64:config_half_ok=high_half ? (value==16'd0) : (value<=16'd511);
  65:config_half_ok=high_half ? (value==16'd0) : (value<=16'd511);
  66:config_half_ok=high_half ? (value==16'd0) : (value<=16'd511);
  67:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  68:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  69:config_half_ok=high_half ? (1'b1) : (1'b1);
  70:config_half_ok=high_half ? (1'b1) : (1'b1);
  71:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  72:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  73:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  74:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  75:config_half_ok=high_half ? (value==16'd0) : (value<=16'd1);
  76:config_half_ok=high_half ? (value==16'd0) : (value<=16'd255);
  default:config_half_ok=0;
 endcase end
endfunction
 reg frame_open;
 reg seen_token,pending_commit,commit_token;
 wire [6:0] op=request[30:24];
 wire [23:0] data=request[23:0];
 wire [7:0] cfg_index=data[23:16];
 wire idle_boundary=!frame_open && !(native_ce && b_selected_valid && b_selected_sof) &&
   !b_busy && !b_mean_busy && !b_speed_busy && !b_motion_busy;
 reg config_ok;
 integer ci;
 always @* begin
  config_ok=config_width_ok && !(|bad_low) && !(|bad_high) && mean_high_sign==shadow[C_cfg_mean_offset][8] && shadow[C_cfg_threshold_min]<=shadow[C_cfg_threshold_max] &&
    shadow[C_cfg_high]>shadow[C_cfg_low] && shadow[C_cfg_min_width]>0 && shadow[C_cfg_min_width]<=WIDTH &&
    shadow[C_cfg_gap]>0 && shadow[C_cfg_gap]<=WIDTH && shadow[C_cfg_noise_on]>shadow[C_cfg_noise_off] &&
    (!shadow[C_cfg_valley_enable] || (shadow[C_cfg_valley_ratio]>0 && shadow[C_cfg_valley_depth]>0 && shadow[C_cfg_valley_width]>0 && shadow[C_cfg_valley_width]<=WIDTH && shadow[C_cfg_peak_distance]>0 && shadow[C_cfg_peak_distance]<=WIDTH && shadow[C_cfg_peak_support]>0 && shadow[C_cfg_peak_support]<=WIDTH)) &&
    (!shadow[C_cfg_guard_enable] || (shadow[C_cfg_guard_x0]<shadow[C_cfg_guard_x1] && shadow[C_cfg_guard_x1]<=WIDTH && shadow[C_cfg_guard_y0]<shadow[C_cfg_guard_y1] && shadow[C_cfg_guard_y1]<=HEIGHT)) &&
    shadow[C_cfg_noise_confirm]>0 && shadow[C_cfg_noise_min_foreground]>0 && shadow[C_cfg_stable_mode]<=2 &&
    (shadow[C_cfg_stable_mode]!=2 || shadow[C_cfg_stable_confirm]>0) &&
    shadow[C_cfg_line_a]>shadow[C_cfg_line_b] && shadow[C_cfg_line_a]<WIDTH && shadow[C_cfg_line_b]<WIDTH &&
    shadow[C_cfg_max_step]>0 && shadow[C_cfg_min_hits]>=2 && shadow[C_cfg_merge_confirm_frames]>=2 &&
    shadow[C_cfg_merge_max_frames]>shadow[C_cfg_merge_confirm_frames] &&
    shadow[C_cfg_safety_roi_x0]<shadow[C_cfg_safety_roi_x1] && shadow[C_cfg_safety_roi_x1]<=WIDTH &&
    shadow[C_cfg_safety_roi_y0]<shadow[C_cfg_safety_roi_y1] && shadow[C_cfg_safety_roi_y1]<=HEIGHT &&
    shadow[C_cfg_guard_dark_off]<shadow[C_cfg_guard_dark_on] && shadow[C_cfg_guard_dark_on]<=256 &&
    shadow[C_cfg_guard_warm_off]<shadow[C_cfg_guard_warm_on] && shadow[C_cfg_guard_warm_on]<=256 &&
    shadow[C_cfg_empty_ratio]<=256 && shadow[C_cfg_recovery_normal_frames]>0 && shadow[C_cfg_recovery_empty_frames]>0 &&
    shadow[C_cfg_source_timeout_cycles]>WIDTH*HEIGHT;
 end
 (* ram_style="block" *) reg [383:0] events[0:31];
 reg [383:0] event_read;
 reg [1:0] event_reply_pending;
 reg event_reply_token;
 reg [4:0] event_address;
 reg [3:0] event_reply_word;
 reg event_reply_high;
 (* ram_style="block" *) reg [15:0] projection[0:WIDTH-1];
 (* ram_style="block" *) reg [15:0] projection_ps[0:WIDTH-1];
 reg [1:0] projection_reply_pending;
 reg projection_reply_token;
 reg [$clog2(WIDTH)-1:0] projection_command_address;
 reg [15:0] projection_read;
 always @(posedge clk)begin
  if(b_sample_valid && b_sample_x<WIDTH)begin
   projection[b_sample_x]<=b_sample_value;
   projection_ps[b_sample_x]<=b_sample_value;
  end
  projection_read<=projection_ps[projection_command_address];
  event_read<=events[event_address];
  if(b_motion_event_valid)events[b_motion_event_seq[4:0]]<={b_motion_session_id,active[C_cfg_config_version],
    b_test_total,b_camera_total,b_motion_event_context,b_motion_event_is_test,31'd0,
    b_motion_event_frame_id,b_motion_event_track_id,b_motion_event_seq};
 end
 // True dual-clock projection RAM: producer port at 75 MHz, LCD read port at 25 MHz.
 always @(posedge display_clk)begin
  if(projection_address<WIDTH)projection_value<=projection[projection_address];else projection_value<=0;
 end
 always @(posedge clk)begin
  clear_pulse<=0;rearm_pulse<=0;
  if(!reset_n)begin
   for(integer c=0;c<CONFIG_COUNT;c=c+1)begin active[c]<=defaults[c];shadow[c]<=defaults[c];end
   bad_low<=0;bad_high<=0;mean_high_sign<=defaults[C_cfg_mean_offset][31];
   for(integer s=0;s<RESULT_WORDS;s=s+1)frozen[s]<=0;
   seen_token<=0;pending_commit<=0;commit_token<=0;response<=0;snapshot_seq<=0;
   frame_open<=0;pulse_seen<=0;event_reply_pending<=0;projection_reply_pending<=0;
   event_address<=0;event_reply_word<=0;event_reply_token<=0;event_reply_high<=0;projection_command_address<=0;projection_reply_token<=0;
  end else begin
   if(!b_pipeline_rst_n)frame_open<=0;
   if(native_ce && b_selected_valid)begin
    if(b_selected_sof)frame_open<=1;
    if(b_selected_eol && video_y==HEIGHT-1)frame_open<=0;
   end
   if(b_result_update)pulse_seen[0]<=1;
   if(b_parallel_low_result_update)pulse_seen[1]<=1;
   if(b_parallel_high_result_update)pulse_seen[2]<=1;
   if(b_mean_update)pulse_seen[3]<=1;
   if(b_noise_stats_update)pulse_seen[4]<=1;
   if(b_active_mode==3)pulse_seen[5]<=1;
   if(b_motion_objects_update)pulse_seen[6]<=1;
   if(b_motion_event_valid)pulse_seen[7]<=1;
   if(b_speed_update && b_speed_valid)pulse_seen[8]<=1;
   if(b_result_cut_count!=0 && b_result_update)pulse_seen[9]<=1;
   if(b_motion_merge_active)pulse_seen[10]<=1;
   if(b_motion_merge_recovered)pulse_seen[11]<=1;
   if(b_stable_update)pulse_seen[12]<=1;
   if(b_safety_report_update)pulse_seen[13]<=1;
   if(b_bist_done)pulse_seen[14]<=1;
   if(b_active_source)pulse_seen[15]<=1;
   if(event_reply_pending==2)event_reply_pending<=1;
   else if(event_reply_pending==1)begin
    response<={event_reply_token,1'b0,(event_reply_high?6'd15:6'd14),8'd0,event_read[event_reply_word*32+(event_reply_high?16:0)+:16]};
    event_reply_pending<=0;
   end else if(projection_reply_pending==2)projection_reply_pending<=1;
   else if(projection_reply_pending==1)begin
    response<={projection_reply_token,1'b0,6'd12,8'd0,projection_read};projection_reply_pending<=0;
   end else if(pending_commit)begin
    if(idle_boundary)begin
     for(integer c=0;c<CONFIG_COUNT;c=c+1)active[c]<=canonical_config(c,shadow[c]);
     active[C_cfg_config_version]<=active[C_cfg_config_version]+1'b1;
     active[C_cfg_scene_epoch]<=active[C_cfg_scene_epoch]+1'b1;
     shadow[C_cfg_config_version]<=active[C_cfg_config_version]+1'b1;
     shadow[C_cfg_scene_epoch]<=active[C_cfg_scene_epoch]+1'b1;
     rearm_pulse<=1;pending_commit<=0;
     response<={commit_token,1'b0,6'd3,(active[C_cfg_config_version][23:0]+24'd1)};
    end
   end else if(request[31]!=seen_token)begin
    seen_token<=request[31];response<={request[31],1'b0,op[5:0],24'd0};
    case(op)
     0:response<={request[31],1'b0,6'd0,24'hC31401};
     1,2:if(cfg_index<CONFIG_COUNT)begin
      for(integer c=0;c<CONFIG_COUNT;c=c+1)if(cfg_index==c)begin
       if(op==1)begin
        shadow[c]<=canonical_config(c,{shadow[c][31:16],data[15:0]});bad_low[c]<=!config_half_ok(c,1'b0,data[15:0]);
       end else begin
        shadow[c]<=canonical_config(c,{data[15:0],shadow[c][15:0]});bad_high[c]<=!config_half_ok(c,1'b1,data[15:0]);
        if(c==C_cfg_mean_offset)mean_high_sign<=data[15];
       end
      end
     end else response<={request[31],1'b1,op[5:0],24'd1};
     3:if(config_ok)begin pending_commit<=1;commit_token<=request[31];response<=response;end
       else response<={request[31],1'b1,6'd3,24'd2};
     4,5:if(data<CONFIG_COUNT)response<={request[31],1'b0,op[5:0],8'd0,(op==4?active[data[6:0]][15:0]:active[data[6:0]][31:16])};
       else response<={request[31],1'b1,op[5:0],24'd1};
     6:begin
      for(integer s=0;s<RESULT_WORDS;s=s+1)frozen[s]<=live[s];
      snapshot_seq<=snapshot_seq+1'b1;frozen[1]<=snapshot_seq+1'b1;
      response<={request[31],1'b0,6'd6,snapshot_seq[23:0]+24'd1};
     end
     7,8:if(data<RESULT_WORDS)response<={request[31],1'b0,op[5:0],8'd0,(op==7?frozen[data[8:0]][15:0]:frozen[data[8:0]][31:16])};
       else response<={request[31],1'b1,op[5:0],24'd3};
     9:clear_pulse<=1;
     10:rearm_pulse<=1;
     12:if(data<WIDTH)begin projection_command_address<=data;projection_reply_pending<=2;projection_reply_token<=request[31];response<=response;end
        else response<={request[31],1'b1,6'd12,24'd3};
     14,15:if(data<384)begin
      event_address<=data[8:0]/9'd12;event_reply_word<=data[8:0]%9'd12;event_reply_high<=op==15;
      event_reply_pending<=2;event_reply_token<=request[31];response<=response;
     end else response<={request[31],1'b1,op[5:0],24'd3};
     default:response<={request[31],1'b1,op[5:0],24'd4};
    endcase
   end
  end
 end

 reg display_request;
 (* ASYNC_REG="TRUE" *) reg [1:0] display_req_sync,display_ack_sync;
 reg display_ack;
 reg [1023:0] held_display;
 reg [1023:0] current_display;
 always @(posedge clk)begin
  if(!reset_n)begin video_y<=0;display_req_sync<=0;display_ack<=0;held_display<=0;end
  else begin
   display_req_sync<={display_req_sync[0],display_request};
   if(!b_pipeline_rst_n)video_y<=0;
   if(native_ce && b_selected_valid)begin
    if(b_selected_sof)video_y<=0;
    else if(b_selected_eol)video_y<=video_y+1'b1;
   end
   if(display_req_sync[1]!=display_ack)begin held_display<=current_display;display_ack<=display_req_sync[1];end
  end
 end
 always @* begin
  current_display=0;
  current_display[0*32+:32]=b_active_source?b_test_total:b_camera_total;
  current_display[1*32+:32]={16'd0,b_stable_count};
  current_display[2*32+:32]={6'd0,b_active_mode,b_parallel_threshold_high,b_active_threshold,b_parallel_threshold_low};
  current_display[3*32+:32]={20'd0,b_bist_pass,b_bist_valid,b_bist_busy,b_motion_merge_blocked,b_motion_merge_active,b_speed_valid,
    b_active_source,b_safety_state,b_safety_blocked,permit_count};
  current_display[4*32+:32]={b_safety_reason,b_result_count};
  current_display[5*32+:32]={{16{b_speed_dx[15]}},b_speed_dx};
  current_display[6*32+:32]=b_speed_cycles_per_frame;
  current_display[7*32+:32]={b_parallel_high_result_count,b_parallel_low_result_count};
  current_display[8*32+:32]=active[C_cfg_line_a];current_display[9*32+:32]=active[C_cfg_line_b];
  current_display[10*32+:32]=active[C_cfg_safety_roi_y0];current_display[11*32+:32]=active[C_cfg_safety_roi_y1];
  current_display[12*32+:32]=active[C_sys_mask];current_display[13*32+:32]=pulse_seen;
  current_display[14*32+:32]=active[C_cfg_config_version];current_display[15*32+:32]=b_motion_event_seq;
  current_display[16*32+:32]={31'd0,eff_cfg_invert};current_display[17*32+:32]={28'd0,cut_count};
  for(integer c=0;c<8;c=c+1)current_display[18*32+c*16+:16]=cuts[c];
  current_display[22*32+:40]=bcd_total;
 end
 always @(posedge display_clk or negedge reset_n)begin
  if(!reset_n)begin display_request<=0;display_ack_sync<=0;display_packet<=0;end
  else begin
   display_ack_sync<={display_ack_sync[0],display_ack};
   if(display_tick && display_ack_sync[1]==display_request)display_request<=~display_request;
   if(display_ack_sync[1]==display_request)display_packet<=held_display;
  end
 end
endmodule
