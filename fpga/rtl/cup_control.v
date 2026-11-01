`timescale 1ns/1ps
// One outstanding GPIO request. PS holds payload/token until matching response.
// Shadow edits do not affect pixels. Commit waits for VSYNC or unlocked video.
module cup_control #(
 parameter integer WIDTH=800,HEIGHT=480,AX0=416,BX0=376,GW=4,Y0=96,Y1=128
)(
 input wire pixel_clk,axi_clk,reset_n,
 input wire [31:0] request,
 output reg [31:0] response,
 input wire frame_tick,frame_sample,video_locked,
 input wire [383:0] snapshot_source,
 output wire [15:0] ax0,bx0,gate_width,y0,y1,on_pixels,off_pixels,warm_limit,
 output wire [7:0] threshold,
 output wire enabled,show_mask,manual_mode,manual_block,
 output reg rearm,clear_count,
 output reg [23:0] cfg_epoch,session,
 output reg cfg_rejected
);
 (* ASYNC_REG="TRUE" *) reg [31:0] req_meta,req_sync;
 reg [31:0] candidate;reg [1:0] stable;
 reg seen_token,pending_commit,pending_snapshot,pending_token;
 reg [31:0] reply;
 (* ASYNC_REG="TRUE" *) reg [31:0] reply_meta,reply_sync;
 reg [31:0] reply_candidate;reg [1:0] reply_stable;
 reg [15:0] shadow[0:9],active[0:9];
 reg [383:0] frozen;
 reg frozen_valid;
 wire [6:0] op=candidate[30:24];
 wire [23:0] data=candidate[23:0];
 wire [31:0] area=({16'd0,shadow[2]})*({16'd0,shadow[4]}-{16'd0,shadow[3]});
 wire config_ok=shadow[0]>=2 && shadow[1]>=2 && shadow[2]>=1 && shadow[2]<=32 &&
    {1'b0,shadow[0]}+{1'b0,shadow[2]}<=WIDTH-2 &&
    {1'b0,shadow[1]}+{1'b0,shadow[2]}<{1'b0,shadow[0]} &&
    shadow[3]>=54 && shadow[4]<=HEIGHT-2 && shadow[4]>=shadow[3]+8 &&
    {1'b0,shadow[4]}-{1'b0,shadow[3]}<=128 &&
    shadow[5]>=32 && shadow[5]<=224 && shadow[6]>shadow[7] &&
    shadow[6]<=area && shadow[8]>=1 && shadow[8]<=area && shadow[9]<=15 && (!shadow[9][3] || shadow[9][2]);
 assign ax0=active[0],bx0=active[1],gate_width=active[2],y0=active[3],y1=active[4];
 assign threshold=active[5][7:0],on_pixels=active[6],off_pixels=active[7],warm_limit=active[8];
 assign enabled=active[9][0],show_mask=active[9][1],manual_mode=active[9][2],manual_block=active[9][3];
 integer i;
 integer j;reg algorithm_changed;
 always @* begin
  algorithm_changed=(shadow[9][0]!=active[9][0] || shadow[9][3:2]!=active[9][3:2]);
  for(j=0;j<9;j=j+1)if(shadow[j]!=active[j])algorithm_changed=1;
 end
 // These are held bundles with acknowledged ownership, not freely changing buses.
 // Qualifying the complete word also prevents exposing a new ack with stale payload.
 always @(posedge axi_clk or negedge reset_n)begin
  if(!reset_n)begin reply_meta<=0;reply_sync<=0;reply_candidate<=0;reply_stable<=0;response<=0;end
  else begin
   reply_meta<=reply;reply_sync<=reply_meta;
   if(reply_sync!=reply_candidate)begin reply_candidate<=reply_sync;reply_stable<=0;end
   else if(reply_stable!=3)reply_stable<=reply_stable+1'b1;
   else response<=reply_candidate;
  end
 end
 always @(posedge pixel_clk)begin
  rearm<=0;clear_count<=0;
  if(!reset_n)begin
   req_meta<=0;req_sync<=0;candidate<=0;stable<=0;seen_token<=0;reply<=0;
   pending_commit<=0;pending_snapshot<=0;pending_token<=0;
   frozen<=0;frozen_valid<=0;cfg_epoch<=0;session<=0;cfg_rejected<=0;
   shadow[0]<=AX0;shadow[1]<=BX0;shadow[2]<=GW;shadow[3]<=Y0;shadow[4]<=Y1;
   shadow[5]<=144;shadow[6]<=52;shadow[7]<=25;shadow[8]<=32;shadow[9]<=0;
   active[0]<=AX0;active[1]<=BX0;active[2]<=GW;active[3]<=Y0;active[4]<=Y1;
   active[5]<=144;active[6]<=52;active[7]<=25;active[8]<=32;active[9]<=0;
  end else begin
   req_meta<=request;req_sync<=req_meta;
   if(req_sync!=candidate)begin candidate<=req_sync;stable<=0;end
   else if(stable!=3)stable<=stable+1'b1;
   if(pending_commit)begin
    if(frame_tick || !video_locked)begin
     for(i=0;i<10;i=i+1)active[i]<=shadow[i];
     cfg_epoch<=cfg_epoch+1'b1;rearm<=algorithm_changed;pending_commit<=0;
     reply<={pending_token,1'b0,6'd11,cfg_epoch+24'd1};
    end
   end else if(pending_snapshot)begin
    if(frame_sample || !video_locked)begin
     frozen<=snapshot_source;frozen_valid<=1;pending_snapshot<=0;
     reply<={pending_token,1'b0,6'd13,snapshot_source[2*24+:24]};
    end
   end else if(stable==3 && candidate[31]!=seen_token)begin
    seen_token<=candidate[31];pending_token<=candidate[31];
    reply<={candidate[31],1'b0,op[5:0],24'd0};
    if(op==0)reply<={candidate[31],1'b0,6'd0,24'hC30401};
    else if(op>=1 && op<=10)begin
     if(data[23:16]!=0)reply<={candidate[31],1'b1,op[5:0],24'd1};
     else shadow[op-1]<=data[15:0];
    end else if(op==11)begin
     if(config_ok)begin pending_commit<=1;reply<=reply;end
     else begin cfg_rejected<=1;reply<={candidate[31],1'b1,6'd11,24'd2};end
    end else if(op==12)begin
     clear_count<=1;session<=session+1'b1;frozen_valid<=0;
     reply<={candidate[31],1'b0,6'd12,session+24'd1};
    end else if(op==13)begin pending_snapshot<=1;reply<=reply;end
    else if(op==14)begin
     if(data<16 && frozen_valid)reply<={candidate[31],1'b0,6'd14,frozen[data*24+:24]};
     else reply<={candidate[31],1'b1,6'd14,24'd3};
    end else if(op==15)begin
     if(data<10)reply<={candidate[31],1'b0,6'd15,8'd0,active[data]};
     else reply<={candidate[31],1'b1,6'd15,24'd4};
    end else reply<={candidate[31],1'b1,op[5:0],24'd5};
   end
  end
 end
endmodule
