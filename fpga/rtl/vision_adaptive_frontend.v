`timescale 1ns/1ps
// Stage 6: frame-atomic adaptive policies and tagged temporal stabilization.
// Legacy stage-5 module is unchanged. This module contains no AXI protocol.
module vision_adaptive_frontend #(
    parameter integer WIDTH=640, HEIGHT=480, SCAN_TIMEOUT=4*WIDTH+32
) (
    input wire clk,
    input wire rst_n,
    input wire ce,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [23:0] in_rgb,
    input wire [7:0] cfg_threshold,
    input wire cfg_invert,
    input wire [1:0] cfg_mode,
    input wire [15:0] cfg_high,
    input wire [15:0] cfg_low,
    input wire [15:0] cfg_min_width,
    input wire [15:0] cfg_gap,
    input wire cfg_valley_enable,
    input wire [7:0] cfg_valley_ratio,
    input wire [15:0] cfg_valley_depth,
    input wire [15:0] cfg_valley_width,
    input wire [15:0] cfg_peak_distance,
    input wire [15:0] cfg_peak_support,
    output wire out_valid,
    output wire out_sof,
    output wire out_eol,
    output wire out_binary,
    output wire analysis_valid,
    output wire [15:0] out_x,
    output wire [15:0] out_y,
    output wire [15:0] out_source_x,
    output wire [15:0] out_source_y,
    output wire [1:0] out_mode,
    output wire clear_busy,
    output wire snapshot_valid,
    output wire snapshot_update,
    output wire frame_done,
    output wire frame_drop,
    output wire [31:0] snapshot_frame_id,
    output wire [31:0] snapshot_white_pixels,
    output wire [31:0] snapshot_roi_pixels,
    output wire [1:0] snapshot_mode,
    output wire [31:0] dropped_frames,
    output wire [31:0] done_frame_id,
    output wire error_sticky,
    output wire busy,
    output reg result_valid,
    output reg result_update,
    output wire scan_abort,
    output wire [2:0] abort_reason,
    output wire [31:0] aborted_scans,
    output reg [31:0] result_frame_id,
    output reg [15:0] result_count,
    output reg [15:0] result_cut_count,
    output reg [1:0] result_mode,
    output reg [15:0] result_high,
    output reg [15:0] result_low,
    output reg [15:0] result_min_width,
    output reg [15:0] result_gap,
    output reg result_valley_enable,
    output reg [7:0] result_valley_ratio,
    output reg [15:0] result_valley_depth,
    output reg [15:0] result_valley_width,
    output reg [15:0] result_peak_distance,
    output reg [15:0] result_peak_support,
    output wire cut_update,
    output wire [15:0] cut_x,
    output wire [31:0] cut_frame_id,
    output wire sample_valid,
    output wire [15:0] sample_x,
    output wire [15:0] sample_value,
    output wire [31:0] sample_frame_id,
    input wire cfg_auto_threshold,
    input wire [7:0] cfg_threshold_min,
    input wire [7:0] cfg_threshold_max,
    input wire signed [8:0] cfg_mean_offset,
    input wire [7:0] cfg_threshold_step,
    input wire cfg_auto_denoise,
    input wire [7:0] cfg_noise_on,
    input wire [7:0] cfg_noise_off,
    input wire [7:0] cfg_noise_confirm,
    input wire [15:0] cfg_noise_min_foreground,
    input wire [1:0] cfg_stable_mode,
    input wire [7:0] cfg_stable_confirm,
    input wire [31:0] cfg_config_version,
    output wire [7:0] active_threshold,
    output reg [1:0] active_mode,
    output reg [31:0] policy_epoch,
    output reg configuration_error,
    output wire gray_stats_update,
    output wire gray_stats_reject,
    output wire [31:0] gray_stats_frame_id,
    output wire [31:0] gray_stats_sum,
    output wire [31:0] gray_stats_pixels,
    output wire [31:0] gray_rejected_frames,
    output wire mean_busy,
    output wire mean_update,
    output wire [7:0] mean_gray,
    output wire [31:0] mean_frame_id,
    output wire [7:0] target_threshold,
    output wire [31:0] target_frame_id,
    output wire target_valid,
    output wire [31:0] threshold_skipped_statistics,
    output wire noise_stats_update,
    output wire [31:0] noise_stats_frame_id,
    output wire [31:0] noise_stats_windows,
    output wire [31:0] noise_stats_foreground,
    output wire [31:0] noise_stats_isolated,
    output wire [31:0] noise_rejected_frames,
    output wire auto_mode_valid,
    output wire [1:0] auto_mode,
    output wire [31:0] auto_mode_frame_id,
    output reg [7:0] result_threshold,
    output reg result_invert,
    output reg [31:0] result_config_version,
    output reg [31:0] result_policy_epoch,
    output wire stable_valid,
    output wire stable_update,
    output wire stable_changed,
    output wire [15:0] stable_count,
    output wire [31:0] stable_frame_id,
    output wire [31:0] stable_epoch,
    output wire [7:0] stable_history_fill,
    output wire [31:0] stable_duplicate_results,
    output wire [31:0] stable_stale_results,
    output wire [31:0] stable_gap_resets,
    input wire upstream_frame_drop,
    output reg [31:0] history_epoch,
    output reg [31:0] result_history_epoch,
    output wire [31:0] stable_history_epoch,
    output wire stable_current_confirmed,
    output wire stable_pending
);
    localparam integer CONFIG_BITS=265;
    wire frame_start=ce&&in_valid&&in_sof;
    wire [CONFIG_BITS-1:0] config_word={cfg_threshold,cfg_invert,cfg_mode,cfg_high,cfg_low,cfg_min_width,cfg_gap,cfg_valley_enable,cfg_valley_ratio,cfg_valley_depth,cfg_valley_width,cfg_peak_distance,cfg_peak_support,cfg_auto_threshold,cfg_threshold_min,cfg_threshold_max,cfg_mean_offset,cfg_threshold_step,cfg_auto_denoise,cfg_noise_on,cfg_noise_off,cfg_noise_confirm,cfg_noise_min_foreground,cfg_stable_mode,cfg_stable_confirm,cfg_config_version};
    reg config_seen;reg [CONFIG_BITS-1:0] previous_config;
    reg [31:0] source_sequence;
    wire changed=frame_start&&(!config_seen||config_word!=previous_config);
    wire [31:0] frame_epoch=changed ? policy_epoch+1'b1 : policy_epoch;
    wire [31:0] next_id=source_sequence+1'b1;
    reg [CONFIG_BITS-1:0] meta_config[0:3];
    reg [31:0] meta_id[0:3],meta_epoch[0:3];
    reg [31:0] meta_history_epoch[0:3];
    wire [31:0] frame_history_epoch=upstream_frame_drop ? history_epoch+1'b1 : history_epoch;
    reg [7:0] meta_threshold[0:3];reg [1:0] meta_mode[0:3];reg [3:0] meta_valid;
    wire [7:0] selected_threshold;
    wire [31:0] target_epoch,auto_mode_epoch;
    wire noise_config_ok=cfg_noise_on>cfg_noise_off&&cfg_noise_confirm!=0&&cfg_noise_min_foreground!=0;
    wire [1:0] selected_mode=cfg_auto_denoise&&noise_config_ok&&auto_mode_valid&&auto_mode_epoch==frame_epoch ? auto_mode : cfg_mode;
    wire gray_meta_ok=meta_valid[gray_stats_frame_id[1:0]]&&meta_id[gray_stats_frame_id[1:0]]==gray_stats_frame_id;
    wire noise_meta_ok=meta_valid[noise_stats_frame_id[1:0]]&&meta_id[noise_stats_frame_id[1:0]]==noise_stats_frame_id;
    wire snapshot_meta_ok=meta_valid[snapshot_frame_id[1:0]]&&
                          meta_id[snapshot_frame_id[1:0]]==snapshot_frame_id&&
                          meta_mode[snapshot_frame_id[1:0]]==snapshot_mode;
    wire [CONFIG_BITS-1:0] gray_config=meta_config[gray_stats_frame_id[1:0]];
    wire [CONFIG_BITS-1:0] noise_config=meta_config[noise_stats_frame_id[1:0]];
    wire [CONFIG_BITS-1:0] scan_config=meta_config[snapshot_frame_id[1:0]];
    wire projection_error,late_metadata_error;reg metadata_error;
    assign error_sticky=projection_error||metadata_error||configuration_error||
                        (gray_rejected_frames!=0)||(noise_rejected_frames!=0);
    integer i;
    always @(posedge clk) begin
        if(!rst_n) begin
            config_seen<=0;previous_config<=0;source_sequence<=0;policy_epoch<=0;
            active_mode<=0;meta_valid<=0;configuration_error<=0;metadata_error<=0;history_epoch<=0;
            for(i=0;i<4;i=i+1) begin meta_config[i]<=0;meta_id[i]<=0;meta_epoch[i]<=0;meta_history_epoch[i]<=0;meta_threshold[i]<=128;meta_mode[i]<=0;end
        end else begin
            if(upstream_frame_drop) history_epoch<=history_epoch+1'b1;
            if((gray_stats_update&&!gray_meta_ok)||(noise_stats_update&&!noise_meta_ok)||
               (snapshot_update&&!snapshot_meta_ok)||late_metadata_error) metadata_error<=1;
            if(frame_start) begin
                config_seen<=1;previous_config<=config_word;source_sequence<=next_id;policy_epoch<=frame_epoch;active_mode<=selected_mode;
                meta_valid[next_id[1:0]]<=1;meta_id[next_id[1:0]]<=next_id;meta_epoch[next_id[1:0]]<=frame_epoch;
                meta_history_epoch[next_id[1:0]]<=frame_history_epoch;
                meta_config[next_id[1:0]]<=config_word;meta_threshold[next_id[1:0]]<=selected_threshold;meta_mode[next_id[1:0]]<=selected_mode;
                if((cfg_auto_threshold&&cfg_threshold_min>cfg_threshold_max)||(cfg_auto_denoise&&!noise_config_ok)||cfg_stable_mode==3||(cfg_stable_mode==2&&cfg_stable_confirm==0)) configuration_error<=1;
            end
        end
    end
    adaptive_threshold threshold_policy(
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_epoch(frame_epoch),
        .cfg_auto(cfg_auto_threshold),.cfg_manual(cfg_threshold),.cfg_min(cfg_threshold_min),.cfg_max(cfg_threshold_max),.cfg_step(cfg_threshold_step),
        .stats_update(gray_stats_update&&gray_meta_ok),.stats_sum(gray_stats_sum),.stats_pixels(gray_stats_pixels),.stats_frame_id(gray_stats_frame_id),
        .stats_epoch(meta_epoch[gray_stats_frame_id[1:0]]),
        .stats_auto(gray_config[116 +: 1]),.stats_min(gray_config[108 +: 8]),.stats_max(gray_config[100 +: 8]),
        .stats_offset(gray_config[91 +: 9]),.selected_threshold(selected_threshold),.active_threshold(active_threshold),
        .busy(mean_busy),.mean_update(mean_update),.mean_gray(mean_gray),.target_threshold(target_threshold),
        .mean_frame_id(mean_frame_id),.target_frame_id(target_frame_id),.target_epoch(target_epoch),
        .skipped_statistics(threshold_skipped_statistics),.target_valid(target_valid)
    );
    dynamic_noise_policy noise_policy(
        .clk(clk),.rst_n(rst_n),.stats_update(noise_stats_update&&noise_meta_ok),.stats_frame_id(noise_stats_frame_id),
        .stats_epoch(meta_epoch[noise_stats_frame_id[1:0]]),.stats_foreground(noise_stats_foreground),.stats_isolated(noise_stats_isolated),
        .cfg_auto(noise_config[82 +: 1]),.cfg_on(noise_config[74 +: 8]),.cfg_off(noise_config[66 +: 8]),
        .cfg_confirm(noise_config[58 +: 8]),.cfg_min_foreground(noise_config[42 +: 16]),
        .mode_valid(auto_mode_valid),.suggested_mode(auto_mode),.mode_epoch(auto_mode_epoch),.mode_frame_id(auto_mode_frame_id)
    );
    wire gv,gs,ge,gb;wire [7:0] gray;reg [1:0] mode_s1,mode_s2;
    always @(posedge clk) begin
        if(!rst_n) begin mode_s1<=0;mode_s2<=0;end
        else if(ce) begin mode_s1<=frame_start ? selected_mode : active_mode;mode_s2<=mode_s1;end
    end
    gray_binary gray_stage(.clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),
        .in_rgb(in_rgb),.cfg_threshold(selected_threshold),.cfg_invert(cfg_invert),
        .out_valid(gv),.out_sof(gs),.out_eol(ge),.out_gray(gray),.out_binary(gb));
    frame_gray_statistics #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) gray_statistics(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(gv),.in_sof(gs),.in_eol(ge),.in_gray(gray),
        .stats_update(gray_stats_update),.stats_reject(gray_stats_reject),.stats_frame_id(gray_stats_frame_id),
        .stats_sum(gray_stats_sum),.stats_pixels(gray_stats_pixels),.rejected_frames(gray_rejected_frames));
    frame_noise_statistics #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) noise_statistics(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(gv),.in_sof(gs),.in_eol(ge),.in_binary(gb),
        .stats_update(noise_stats_update),.stats_frame_id(noise_stats_frame_id),.stats_windows(noise_stats_windows),
        .stats_foreground(noise_stats_foreground),.stats_isolated(noise_stats_isolated),.rejected_frames(noise_rejected_frames));
    morphology_filter #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) morphology(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(gv),.in_sof(gs),.in_eol(ge),.in_binary(gb),.cfg_mode(mode_s2),
        .out_valid(out_valid),.out_sof(out_sof),.out_eol(out_eol),.out_x(out_x),.out_y(out_y),
        .out_source_x(out_source_x),.out_source_y(out_source_y),.analysis_valid(analysis_valid),.out_mode(out_mode),
        .out_binary(out_binary),.out_raw(),.out_eroded(),.out_dilated(),.out_opened());
    wire req,ready,rv,re;wire [15:0] addr,resp_addr,data;wire [31:0] read_id;
    projection_accumulator #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) projection(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(out_valid),.in_sof(out_sof),.in_eol(out_eol),
        .in_x(out_x),.in_y(out_y),.in_source_x(out_source_x),.in_analysis_valid(analysis_valid),.in_binary(out_binary),.in_mode(out_mode),
        .clear_busy(clear_busy),.snapshot_valid(snapshot_valid),.snapshot_update(snapshot_update),.frame_done(frame_done),.frame_drop(frame_drop),
        .snapshot_frame_id(snapshot_frame_id),.snapshot_white_pixels(snapshot_white_pixels),.snapshot_roi_pixels(snapshot_roi_pixels),
        .snapshot_mode(snapshot_mode),.dropped_frames(dropped_frames),.done_frame_id(done_frame_id),.error_sticky(projection_error),
        .rd_req(req),.rd_addr(addr),.rd_ready(ready),.rd_valid(rv),.rd_error(re),.rd_resp_addr(resp_addr),.rd_data(data),.rd_frame_id(read_id));
    wire raw_result_valid;
    wire raw_result_update;
    wire [31:0] raw_result_frame_id;
    wire [15:0] raw_result_count;
    wire [15:0] raw_result_cut_count;
    wire [1:0] raw_result_mode;
    wire [15:0] raw_result_high;
    wire [15:0] raw_result_low;
    wire [15:0] raw_result_min_width;
    wire [15:0] raw_result_gap;
    wire raw_result_valley_enable;
    wire [7:0] raw_result_valley_ratio;
    wire [15:0] raw_result_valley_depth;
    wire [15:0] raw_result_valley_width;
    wire [15:0] raw_result_peak_distance;
    wire [15:0] raw_result_peak_support;
    projection_valley_scanner #(.WIDTH(WIDTH),.TIMEOUT_CYCLES(SCAN_TIMEOUT)) scanner(
        .clk(clk),.rst_n(rst_n),.snapshot_valid(snapshot_valid&&snapshot_meta_ok),.snapshot_frame_id(snapshot_frame_id),.snapshot_mode(snapshot_mode),
        .cfg_high(scan_config[238 +: 16]),
        .cfg_low(scan_config[222 +: 16]),
        .cfg_min_width(scan_config[206 +: 16]),
        .cfg_gap(scan_config[190 +: 16]),
        .cfg_valley_enable(scan_config[189 +: 1]),
        .cfg_valley_ratio(scan_config[181 +: 8]),
        .cfg_valley_depth(scan_config[165 +: 16]),
        .cfg_valley_width(scan_config[149 +: 16]),
        .cfg_peak_distance(scan_config[133 +: 16]),
        .cfg_peak_support(scan_config[117 +: 16]),
        .rd_req(req),.rd_addr(addr),.rd_ready(ready),.rd_valid(rv),.rd_error(re),.rd_resp_addr(resp_addr),.rd_data(data),.rd_frame_id(read_id),
        .busy(busy),.scan_abort(scan_abort),.abort_reason(abort_reason),.aborted_scans(aborted_scans),
        .result_valid(raw_result_valid),
        .result_update(raw_result_update),
        .result_frame_id(raw_result_frame_id),
        .result_count(raw_result_count),
        .result_cut_count(raw_result_cut_count),
        .result_mode(raw_result_mode),
        .result_high(raw_result_high),
        .result_low(raw_result_low),
        .result_min_width(raw_result_min_width),
        .result_gap(raw_result_gap),
        .result_valley_enable(raw_result_valley_enable),
        .result_valley_ratio(raw_result_valley_ratio),
        .result_valley_depth(raw_result_valley_depth),
        .result_valley_width(raw_result_valley_width),
        .result_peak_distance(raw_result_peak_distance),
        .result_peak_support(raw_result_peak_support),
        .sample_valid(sample_valid),.sample_x(sample_x),.sample_value(sample_value),.sample_frame_id(sample_frame_id),
        .cut_update(cut_update),.cut_x(cut_x),.cut_frame_id(cut_frame_id));
    wire result_meta_ok=meta_valid[raw_result_frame_id[1:0]]&&meta_id[raw_result_frame_id[1:0]]==raw_result_frame_id;
    assign late_metadata_error=raw_result_update&&!result_meta_ok;
    wire [CONFIG_BITS-1:0] result_config=meta_config[raw_result_frame_id[1:0]];
    always @(posedge clk) begin
        if(!rst_n) begin
            result_valid<=0;
            result_update<=0;
            result_frame_id<=0;
            result_count<=0;
            result_cut_count<=0;
            result_mode<=0;
            result_high<=0;
            result_low<=0;
            result_min_width<=0;
            result_gap<=0;
            result_valley_enable<=0;
            result_valley_ratio<=0;
            result_valley_depth<=0;
            result_valley_width<=0;
            result_peak_distance<=0;
            result_peak_support<=0;
            result_threshold<=0;result_invert<=0;result_config_version<=0;result_policy_epoch<=0;result_history_epoch<=0;
        end else begin
            result_update<=0;
            if(raw_result_update&&result_meta_ok) begin
                result_valid<=raw_result_valid;
                result_update<=raw_result_update;
                result_frame_id<=raw_result_frame_id;
                result_count<=raw_result_count;
                result_cut_count<=raw_result_cut_count;
                result_mode<=raw_result_mode;
                result_high<=raw_result_high;
                result_low<=raw_result_low;
                result_min_width<=raw_result_min_width;
                result_gap<=raw_result_gap;
                result_valley_enable<=raw_result_valley_enable;
                result_valley_ratio<=raw_result_valley_ratio;
                result_valley_depth<=raw_result_valley_depth;
                result_valley_width<=raw_result_valley_width;
                result_peak_distance<=raw_result_peak_distance;
                result_peak_support<=raw_result_peak_support;
                result_threshold<=meta_threshold[raw_result_frame_id[1:0]];
                result_invert<=result_config[256 +: 1];result_config_version<=result_config[0 +: 32];
                result_policy_epoch<=meta_epoch[raw_result_frame_id[1:0]];
                result_history_epoch<=meta_history_epoch[raw_result_frame_id[1:0]];
            end
        end
    end
    wire stabilize_flush=upstream_frame_drop||changed||frame_drop||scan_abort||gray_stats_reject||
                         (snapshot_update&&!snapshot_meta_ok)||(raw_result_update&&!result_meta_ok);
    count_stabilizer stable_stage(.clk(clk),.rst_n(rst_n),.flush(stabilize_flush),
        .in_update(raw_result_update&&result_meta_ok&&meta_epoch[raw_result_frame_id[1:0]]==policy_epoch&&
                   meta_history_epoch[raw_result_frame_id[1:0]]==history_epoch),
        .in_frame_id(raw_result_frame_id),.in_epoch(meta_epoch[raw_result_frame_id[1:0]]),.in_count(raw_result_count),
        .in_history_epoch(meta_history_epoch[raw_result_frame_id[1:0]]),
        .cfg_mode(result_config[40 +: 2]),.cfg_confirm(result_config[32 +: 8]),
        .stable_valid(stable_valid),.stable_update(stable_update),.stable_changed(stable_changed),.stable_count(stable_count),
        .stable_frame_id(stable_frame_id),.stable_epoch(stable_epoch),.history_fill(stable_history_fill),
        .duplicate_results(stable_duplicate_results),.stale_results(stable_stale_results),.gap_resets(stable_gap_resets),
        .stable_history_epoch(stable_history_epoch),.stable_current_confirmed(stable_current_confirmed),.stable_pending(stable_pending));
    // synthesis translate_off
    initial begin
        if(WIDTH<5||HEIGHT<5||WIDTH>65535||HEIGHT>65535||WIDTH*1.0*HEIGHT>16777216)
            $fatal(1,"Invalid stage-6 dimensions (32-bit grayscale sum)");
    end
    // synthesis translate_on
endmodule
