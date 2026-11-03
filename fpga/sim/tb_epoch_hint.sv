`timescale 1ns/1ps
module tb_epoch_hint;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,frame_start=0,seen=0;
reg [31:0] policy_epoch=32'hfffffff8,version=0,previous_version=0;
wire frame_context_changed=frame_start&&(!seen||version!=previous_version);
wire [31:0] frame_epoch=frame_context_changed?policy_epoch+32'd1:policy_epoch;
always @(posedge clk)begin
 if(!rst_n)begin policy_epoch<=32'hfffffff8;seen<=0;previous_version<=0;end
 else if(frame_start)begin policy_epoch<=frame_epoch;seen<=1;previous_version<=version;end
end
reg [0:0] cfg_auto=0;
reg [7:0] cfg_manual=0;
reg [7:0] cfg_min=0;
reg [7:0] cfg_max=0;
reg [7:0] cfg_step=0;
reg [0:0] stats_update=0;
reg [31:0] stats_sum=0;
reg [31:0] stats_pixels=0;
reg [31:0] stats_frame_id=0;
reg [31:0] stats_epoch=0;
reg [0:0] stats_auto=0;
reg [7:0] stats_min=0;
reg [7:0] stats_max=0;
reg [8:0] stats_offset=0;
reg [0:0] hold_adaptation=0;
wire [7:0] r_selected_threshold;
wire [7:0] r_active_threshold;
wire [0:0] r_busy;
wire [0:0] r_mean_update;
wire [7:0] r_mean_gray;
wire [7:0] r_target_threshold;
wire [31:0] r_mean_frame_id;
wire [31:0] r_target_frame_id;
wire [31:0] r_target_epoch;
wire [31:0] r_skipped_statistics;
wire [0:0] r_target_valid;
wire [7:0] n_selected_threshold;
wire [7:0] n_active_threshold;
wire [0:0] n_busy;
wire [0:0] n_mean_update;
wire [7:0] n_mean_gray;
wire [7:0] n_target_threshold;
wire [31:0] n_mean_frame_id;
wire [31:0] n_target_frame_id;
wire [31:0] n_target_epoch;
wire [31:0] n_skipped_statistics;
wire [0:0] n_target_valid;
threshold_epoch_reference  r_dut(
.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_epoch(frame_epoch),
.cfg_auto(cfg_auto),
.cfg_manual(cfg_manual),
.cfg_min(cfg_min),
.cfg_max(cfg_max),
.cfg_step(cfg_step),
.stats_update(stats_update),
.stats_sum(stats_sum),
.stats_pixels(stats_pixels),
.stats_frame_id(stats_frame_id),
.stats_epoch(stats_epoch),
.stats_auto(stats_auto),
.stats_min(stats_min),
.stats_max(stats_max),
.stats_offset(stats_offset),
.hold_adaptation(hold_adaptation),
.selected_threshold(r_selected_threshold),
.active_threshold(r_active_threshold),
.busy(r_busy),
.mean_update(r_mean_update),
.mean_gray(r_mean_gray),
.target_threshold(r_target_threshold),
.mean_frame_id(r_mean_frame_id),
.target_frame_id(r_target_frame_id),
.target_epoch(r_target_epoch),
.skipped_statistics(r_skipped_statistics),
.target_valid(r_target_valid)
);
guarded_adaptive_threshold #(.FRAME_EPOCH_HINT(1)) n_dut(
.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_epoch(frame_epoch),
 .frame_context_changed(frame_context_changed),
.cfg_auto(cfg_auto),
.cfg_manual(cfg_manual),
.cfg_min(cfg_min),
.cfg_max(cfg_max),
.cfg_step(cfg_step),
.stats_update(stats_update),
.stats_sum(stats_sum),
.stats_pixels(stats_pixels),
.stats_frame_id(stats_frame_id),
.stats_epoch(stats_epoch),
.stats_auto(stats_auto),
.stats_min(stats_min),
.stats_max(stats_max),
.stats_offset(stats_offset),
.hold_adaptation(hold_adaptation),
.selected_threshold(n_selected_threshold),
.active_threshold(n_active_threshold),
.busy(n_busy),
.mean_update(n_mean_update),
.mean_gray(n_mean_gray),
.target_threshold(n_target_threshold),
.mean_frame_id(n_mean_frame_id),
.target_frame_id(n_target_frame_id),
.target_epoch(n_target_epoch),
.skipped_statistics(n_skipped_statistics),
.target_valid(n_target_valid)
);
integer seed=32'h1badcafe,i,checks=0;reg [31:0] random_word;
task compare;begin
if(r_selected_threshold!==n_selected_threshold)$fatal(1,"epoch equivalence cycle=%0d field=selected_threshold ref=%h actual=%h",i,r_selected_threshold,n_selected_threshold);
if(r_active_threshold!==n_active_threshold)$fatal(1,"epoch equivalence cycle=%0d field=active_threshold ref=%h actual=%h",i,r_active_threshold,n_active_threshold);
if(r_busy!==n_busy)$fatal(1,"epoch equivalence cycle=%0d field=busy ref=%h actual=%h",i,r_busy,n_busy);
if(r_mean_update!==n_mean_update)$fatal(1,"epoch equivalence cycle=%0d field=mean_update ref=%h actual=%h",i,r_mean_update,n_mean_update);
if(r_mean_gray!==n_mean_gray)$fatal(1,"epoch equivalence cycle=%0d field=mean_gray ref=%h actual=%h",i,r_mean_gray,n_mean_gray);
if(r_target_threshold!==n_target_threshold)$fatal(1,"epoch equivalence cycle=%0d field=target_threshold ref=%h actual=%h",i,r_target_threshold,n_target_threshold);
if(r_mean_frame_id!==n_mean_frame_id)$fatal(1,"epoch equivalence cycle=%0d field=mean_frame_id ref=%h actual=%h",i,r_mean_frame_id,n_mean_frame_id);
if(r_target_frame_id!==n_target_frame_id)$fatal(1,"epoch equivalence cycle=%0d field=target_frame_id ref=%h actual=%h",i,r_target_frame_id,n_target_frame_id);
if(r_target_epoch!==n_target_epoch)$fatal(1,"epoch equivalence cycle=%0d field=target_epoch ref=%h actual=%h",i,r_target_epoch,n_target_epoch);
if(r_skipped_statistics!==n_skipped_statistics)$fatal(1,"epoch equivalence cycle=%0d field=skipped_statistics ref=%h actual=%h",i,r_skipped_statistics,n_skipped_statistics);
if(r_target_valid!==n_target_valid)$fatal(1,"epoch equivalence cycle=%0d field=target_valid ref=%h actual=%h",i,r_target_valid,n_target_valid);
checks=checks+1;end endtask
initial begin
 for(i=0;i<30000;i=i+1)begin
  @(negedge clk);random_word=$random(seed);
  rst_n=i>2 && i%1973!=0;frame_start=(random_word[2:0]==0);
  if(frame_start&&random_word[4])version=version+1;
  cfg_auto=random_word[3];cfg_manual=random_word[15:8];cfg_step=random_word[23:16];
  cfg_min=random_word[31:24];cfg_max=random_word[7:0];
  stats_update=(i%39==0);stats_pixels=i%13==0?0:(i%1000)+1;
  stats_sum=stats_pixels*random_word[15:8];stats_frame_id=i;
  stats_epoch=i%5==0?policy_epoch-1:policy_epoch;
  stats_auto=1;stats_min=32;stats_max=224;stats_offset=random_word[24:16];
  hold_adaptation=(random_word[8:4]==0);
  #1;if(rst_n)compare;
  @(posedge clk);#1;compare;
 end
 $display("PASS EPOCH_HINT cycles=30000 checks=%0d SOF/version_wrap/statistics/hold/clamps/slew/reset",checks);$finish;
end
endmodule
