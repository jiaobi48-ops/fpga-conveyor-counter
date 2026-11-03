`timescale 1ns/1ps
// Optional right-to-left conveyor sidecar; all legacy outputs are forwarded unchanged.
module vision_conveyor_frontend #(
    parameter integer WIDTH=640, HEIGHT=480, SCAN_TIMEOUT=4*WIDTH+32,
    parameter integer ROM_WIDTH=160, ROM_HEIGHT=120, SCALE=4,
    parameter integer HOLD_FRAMES=60, FRAME_GAP_CYCLES=3026133,
    parameter integer DEBOUNCE_CYCLES=1000000, DRAIN_CYCLES=WIDTH+80,
    parameter integer FRAME_TIMEOUT_CYCLES=10000000, DRAIN_TIMEOUT_CYCLES=20000000,
    parameter integer MAX_TRACKS=8,
    parameter ROM_FILE="fixtures/selftest/scenes_160x120.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire ce,
    input wire cam_valid,
    input wire cam_sof,
    input wire cam_eol,
    input wire [23:0] cam_rgb,
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
    output wire result_valid,
    output wire result_update,
    output wire scan_abort,
    output wire [2:0] abort_reason,
    output wire [31:0] aborted_scans,
    output wire [31:0] result_frame_id,
    output wire [15:0] result_count,
    output wire [15:0] result_cut_count,
    output wire [1:0] result_mode,
    output wire [15:0] result_high,
    output wire [15:0] result_low,
    output wire [15:0] result_min_width,
    output wire [15:0] result_gap,
    output wire result_valley_enable,
    output wire [7:0] result_valley_ratio,
    output wire [15:0] result_valley_depth,
    output wire [15:0] result_valley_width,
    output wire [15:0] result_peak_distance,
    output wire [15:0] result_peak_support,
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
    output wire [1:0] active_mode,
    output wire [31:0] policy_epoch,
    output wire configuration_error,
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
    output wire [7:0] result_threshold,
    output wire result_invert,
    output wire [31:0] result_config_version,
    output wire [31:0] result_policy_epoch,
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
    input wire cfg_test_async,
    input wire cfg_scene_auto,
    input wire [1:0] cfg_scene,
    output wire selected_valid, selected_sof, selected_eol,
    output wire [23:0] selected_rgb,
    output wire pipeline_rst_n,
    output wire active_source, requested_source, switch_busy, waiting_for_sof,
    output wire switch_done, switch_fault, source_fault_sticky,
    output wire [31:0] source_generation, switch_count, source_recoveries, discarded_camera_pixels,
    output wire [1:0] test_scene,
    output wire result_is_test, stable_is_test,
    output wire [1:0] result_scene, stable_scene,
    output wire [31:0] result_generation, stable_generation,
    output wire source_metadata_error,
    input wire cam_frame_drop,
    output wire [31:0] camera_drop_events,
    output wire [31:0] history_epoch,
    output wire [31:0] result_history_epoch,
    output wire [31:0] stable_history_epoch,
    output wire stable_current_confirmed,
    output wire stable_pending,
    input wire cfg_motion_enable,
    input wire [15:0] cfg_line_a,cfg_line_b,cfg_hysteresis,cfg_max_step,cfg_width_delta,
    input wire [7:0] cfg_max_missed,cfg_min_hits,
    input wire motion_clear_totals,
    output wire motion_busy,motion_frame_update,motion_frame_rejected,
    output wire [31:0] motion_frame_id,
    output wire [127:0] motion_context,
    output wire motion_is_test,
    output wire [7:0] motion_delta,
    output wire [31:0] camera_total,test_total,
    output wire motion_event_valid,
    output wire [31:0] motion_event_track_id,motion_event_frame_id,motion_event_seq,
    output wire [127:0] motion_event_context,
    output wire motion_event_is_test,
    output wire motion_fault_sticky,
    output wire [31:0] motion_fault_reasons,motion_rejected_frames,motion_extractor_faults,motion_duplicate_frames,motion_uncertain_tracks,
    output wire [7:0] motion_live_tracks,
    output reg [31:0] motion_session_id,
    output reg motion_objects_valid,motion_objects_update,
    output reg [7:0] motion_objects_count,
    output reg [MAX_TRACKS*16-1:0] motion_objects_lefts,motion_objects_rights,
    output reg [31:0] motion_objects_frame_id,
    output reg [127:0] motion_objects_context,
    output reg motion_objects_is_test,
    output wire motion_debug_valid,
    output wire [31:0] motion_debug_track_id,motion_debug_frame_id,
    output wire [15:0] motion_debug_left,motion_debug_right,motion_debug_center,
    output wire [1:0] motion_debug_phase,
    output wire motion_debug_counted,motion_debug_eligible,
    output wire [127:0] motion_debug_context,
    output wire motion_debug_is_test
);
    vision_selftest_frontend #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .SCAN_TIMEOUT(SCAN_TIMEOUT),
        .ROM_WIDTH(ROM_WIDTH),
        .ROM_HEIGHT(ROM_HEIGHT),
        .SCALE(SCALE),
        .HOLD_FRAMES(HOLD_FRAMES),
        .FRAME_GAP_CYCLES(FRAME_GAP_CYCLES),
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .DRAIN_CYCLES(DRAIN_CYCLES),
        .FRAME_TIMEOUT_CYCLES(FRAME_TIMEOUT_CYCLES),
        .DRAIN_TIMEOUT_CYCLES(DRAIN_TIMEOUT_CYCLES),
        .ROM_FILE(ROM_FILE)
    ) legacy (
        .clk(clk),
        .rst_n(rst_n),
        .ce(ce),
        .cam_valid(cam_valid),
        .cam_sof(cam_sof),
        .cam_eol(cam_eol),
        .cam_rgb(cam_rgb),
        .cfg_threshold(cfg_threshold),
        .cfg_invert(cfg_invert),
        .cfg_mode(cfg_mode),
        .cfg_high(cfg_high),
        .cfg_low(cfg_low),
        .cfg_min_width(cfg_min_width),
        .cfg_gap(cfg_gap),
        .cfg_valley_enable(cfg_valley_enable),
        .cfg_valley_ratio(cfg_valley_ratio),
        .cfg_valley_depth(cfg_valley_depth),
        .cfg_valley_width(cfg_valley_width),
        .cfg_peak_distance(cfg_peak_distance),
        .cfg_peak_support(cfg_peak_support),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol),
        .out_binary(out_binary),
        .analysis_valid(analysis_valid),
        .out_x(out_x),
        .out_y(out_y),
        .out_source_x(out_source_x),
        .out_source_y(out_source_y),
        .out_mode(out_mode),
        .clear_busy(clear_busy),
        .snapshot_valid(snapshot_valid),
        .snapshot_update(snapshot_update),
        .frame_done(frame_done),
        .frame_drop(frame_drop),
        .snapshot_frame_id(snapshot_frame_id),
        .snapshot_white_pixels(snapshot_white_pixels),
        .snapshot_roi_pixels(snapshot_roi_pixels),
        .snapshot_mode(snapshot_mode),
        .dropped_frames(dropped_frames),
        .done_frame_id(done_frame_id),
        .error_sticky(error_sticky),
        .busy(busy),
        .result_valid(result_valid),
        .result_update(result_update),
        .scan_abort(scan_abort),
        .abort_reason(abort_reason),
        .aborted_scans(aborted_scans),
        .result_frame_id(result_frame_id),
        .result_count(result_count),
        .result_cut_count(result_cut_count),
        .result_mode(result_mode),
        .result_high(result_high),
        .result_low(result_low),
        .result_min_width(result_min_width),
        .result_gap(result_gap),
        .result_valley_enable(result_valley_enable),
        .result_valley_ratio(result_valley_ratio),
        .result_valley_depth(result_valley_depth),
        .result_valley_width(result_valley_width),
        .result_peak_distance(result_peak_distance),
        .result_peak_support(result_peak_support),
        .cut_update(cut_update),
        .cut_x(cut_x),
        .cut_frame_id(cut_frame_id),
        .sample_valid(sample_valid),
        .sample_x(sample_x),
        .sample_value(sample_value),
        .sample_frame_id(sample_frame_id),
        .cfg_auto_threshold(cfg_auto_threshold),
        .cfg_threshold_min(cfg_threshold_min),
        .cfg_threshold_max(cfg_threshold_max),
        .cfg_mean_offset(cfg_mean_offset),
        .cfg_threshold_step(cfg_threshold_step),
        .cfg_auto_denoise(cfg_auto_denoise),
        .cfg_noise_on(cfg_noise_on),
        .cfg_noise_off(cfg_noise_off),
        .cfg_noise_confirm(cfg_noise_confirm),
        .cfg_noise_min_foreground(cfg_noise_min_foreground),
        .cfg_stable_mode(cfg_stable_mode),
        .cfg_stable_confirm(cfg_stable_confirm),
        .cfg_config_version(cfg_config_version),
        .active_threshold(active_threshold),
        .active_mode(active_mode),
        .policy_epoch(policy_epoch),
        .configuration_error(configuration_error),
        .gray_stats_update(gray_stats_update),
        .gray_stats_reject(gray_stats_reject),
        .gray_stats_frame_id(gray_stats_frame_id),
        .gray_stats_sum(gray_stats_sum),
        .gray_stats_pixels(gray_stats_pixels),
        .gray_rejected_frames(gray_rejected_frames),
        .mean_busy(mean_busy),
        .mean_update(mean_update),
        .mean_gray(mean_gray),
        .mean_frame_id(mean_frame_id),
        .target_threshold(target_threshold),
        .target_frame_id(target_frame_id),
        .target_valid(target_valid),
        .threshold_skipped_statistics(threshold_skipped_statistics),
        .noise_stats_update(noise_stats_update),
        .noise_stats_frame_id(noise_stats_frame_id),
        .noise_stats_windows(noise_stats_windows),
        .noise_stats_foreground(noise_stats_foreground),
        .noise_stats_isolated(noise_stats_isolated),
        .noise_rejected_frames(noise_rejected_frames),
        .auto_mode_valid(auto_mode_valid),
        .auto_mode(auto_mode),
        .auto_mode_frame_id(auto_mode_frame_id),
        .result_threshold(result_threshold),
        .result_invert(result_invert),
        .result_config_version(result_config_version),
        .result_policy_epoch(result_policy_epoch),
        .stable_valid(stable_valid),
        .stable_update(stable_update),
        .stable_changed(stable_changed),
        .stable_count(stable_count),
        .stable_frame_id(stable_frame_id),
        .stable_epoch(stable_epoch),
        .stable_history_fill(stable_history_fill),
        .stable_duplicate_results(stable_duplicate_results),
        .stable_stale_results(stable_stale_results),
        .stable_gap_resets(stable_gap_resets),
        .cfg_test_async(cfg_test_async),
        .cfg_scene_auto(cfg_scene_auto),
        .cfg_scene(cfg_scene),
        .selected_valid(selected_valid),
        .selected_sof(selected_sof),
        .selected_eol(selected_eol),
        .selected_rgb(selected_rgb),
        .pipeline_rst_n(pipeline_rst_n),
        .active_source(active_source),
        .requested_source(requested_source),
        .switch_busy(switch_busy),
        .waiting_for_sof(waiting_for_sof),
        .switch_done(switch_done),
        .switch_fault(switch_fault),
        .source_fault_sticky(source_fault_sticky),
        .source_generation(source_generation),
        .switch_count(switch_count),
        .source_recoveries(source_recoveries),
        .discarded_camera_pixels(discarded_camera_pixels),
        .test_scene(test_scene),
        .result_is_test(result_is_test),
        .stable_is_test(stable_is_test),
        .result_scene(result_scene),
        .stable_scene(stable_scene),
        .result_generation(result_generation),
        .stable_generation(stable_generation),
        .source_metadata_error(source_metadata_error),
        .cam_frame_drop(cam_frame_drop),
        .camera_drop_events(camera_drop_events),
        .history_epoch(history_epoch),
        .result_history_epoch(result_history_epoch),
        .stable_history_epoch(stable_history_epoch),
        .stable_current_confirmed(stable_current_confirmed),
        .stable_pending(stable_pending)
    );

    // SOF-bound motion configuration. The old top/interface is not changed.
    // Tag low161={is_test,generation,history,algorithm_policy,motion_policy,frame_id}.
    localparam integer MOTION_CFG_BITS=97;
    wire [MOTION_CFG_BITS-1:0] requested_motion_cfg={cfg_motion_enable,cfg_line_a,cfg_line_b,
        cfg_hysteresis,cfg_max_step,cfg_width_delta,cfg_max_missed,cfg_min_hits};
    reg [MOTION_CFG_BITS-1:0] active_motion_cfg,previous_motion_cfg;
    reg motion_cfg_seen;
    reg [31:0] motion_policy_epoch,motion_input_seq;
    reg [3:0] motion_meta_valid;
    reg [31:0] motion_meta_id[0:3],motion_meta_generation[0:3],motion_meta_epoch[0:3];
    reg [MOTION_CFG_BITS-1:0] motion_meta_cfg[0:3];
    wire motion_sof=ce&&selected_valid&&selected_sof;
    wire motion_cfg_changed=motion_sof&&(!motion_cfg_seen||requested_motion_cfg!=previous_motion_cfg);
    wire [31:0] next_motion_id=motion_input_seq+1'b1;
    wire [31:0] frame_motion_epoch=(motion_cfg_changed||motion_clear_totals) ? motion_policy_epoch+1'b1 : motion_policy_epoch;
    integer m;
    always @(posedge clk) begin
        if(!rst_n) motion_session_id<=0;
        else if(motion_clear_totals) motion_session_id<=motion_session_id+1'b1;
        if(!rst_n||!pipeline_rst_n) begin
            active_motion_cfg<=0;previous_motion_cfg<=0;motion_cfg_seen<=0;
            motion_policy_epoch<=0;motion_input_seq<=0;motion_meta_valid<=0;
            for(m=0;m<4;m=m+1) begin
                motion_meta_id[m]<=0;motion_meta_generation[m]<=0;
                motion_meta_epoch[m]<=0;motion_meta_cfg[m]<=0;
            end
        end else begin
          if(motion_clear_totals) motion_policy_epoch<=motion_policy_epoch+1'b1;
          if(motion_sof) begin
            active_motion_cfg<=requested_motion_cfg;previous_motion_cfg<=requested_motion_cfg;
            motion_cfg_seen<=1;motion_policy_epoch<=frame_motion_epoch;motion_input_seq<=next_motion_id;
            motion_meta_valid[next_motion_id[1:0]]<=1;
            motion_meta_id[next_motion_id[1:0]]<=next_motion_id;
            motion_meta_generation[next_motion_id[1:0]]<=source_generation;
            motion_meta_epoch[next_motion_id[1:0]]<=frame_motion_epoch;
            motion_meta_cfg[next_motion_id[1:0]]<=requested_motion_cfg;
          end
        end
    end
    wire motion_enabled=active_motion_cfg[96];
    wire [16:0] motion_gate_upper={1'b0,active_motion_cfg[95:80]}+{1'b0,active_motion_cfg[63:48]};
    wire [16:0] motion_gate_lower_margin={1'b0,active_motion_cfg[63:48]}+17'd2;
    wire motion_geometry_bad=motion_gate_upper>WIDTH-3||
        {1'b0,active_motion_cfg[79:64]}<motion_gate_lower_margin;
    wire [127:0] live_motion_context={source_generation,history_epoch,policy_epoch,motion_policy_epoch};
    reg live_context_seen;
    reg [127:0] previous_motion_context;
    wire live_context_changed=!live_context_seen||previous_motion_context!=live_motion_context;
    always @(posedge clk) begin
        if(!rst_n) begin live_context_seen<=0;previous_motion_context<=0;end
        else begin live_context_seen<=1;previous_motion_context<=live_motion_context;end
    end
    reg previous_source_metadata_error;
    always @(posedge clk) begin
        if(!rst_n) previous_source_metadata_error<=0;
        else previous_source_metadata_error<=source_metadata_error;
    end
    wire motion_metadata_reject;
    wire base_motion_flush=!pipeline_rst_n||!motion_enabled||live_context_changed||
        frame_drop||scan_abort||gray_stats_reject||motion_clear_totals||motion_metadata_reject||
        (source_metadata_error&&!previous_source_metadata_error)||(motion_enabled&&motion_geometry_bad);
    wire result_motion_meta_ok=motion_meta_valid[result_frame_id[1:0]]&&
        motion_meta_id[result_frame_id[1:0]]==result_frame_id&&
        motion_meta_generation[result_frame_id[1:0]]==result_generation;
    wire result_motion_current=result_generation==source_generation&&
        result_history_epoch==history_epoch&&result_policy_epoch==policy_epoch&&
        result_motion_meta_ok&&motion_meta_epoch[result_frame_id[1:0]]==motion_policy_epoch&&
        result_is_test==active_source;
    assign motion_metadata_reject=result_update&&motion_enabled&&pipeline_rst_n&&!result_motion_meta_ok;
    wire motion_commit=result_update&&result_valid&&motion_enabled&&!base_motion_flush&&result_motion_current;
    // After a context break, ignore an old scan's remaining nonzero columns.
    // Its later historical raw packet cancels collection without a false fault.
    wire cancel_historical=result_update&&motion_enabled&&pipeline_rst_n&&
        result_motion_meta_ok&&!result_motion_current;
    reg capture_armed;
    reg [31:0] capture_frame_id;
    wire capture_start=sample_valid&&sample_x==0;
    wire accept_projection_sample=sample_valid&&(capture_armed||capture_start)&&
        motion_enabled&&!base_motion_flush&&!cancel_historical;
    wire accept_projection_cut=cut_update&&capture_armed&&cut_frame_id==capture_frame_id&&
        motion_enabled&&!base_motion_flush&&!cancel_historical;
    always @(posedge clk) begin
        if(!rst_n||base_motion_flush||cancel_historical) begin capture_armed<=0;capture_frame_id<=0;end
        else begin
            if(result_update) capture_armed<=0;
            if(capture_start&&motion_enabled) begin capture_armed<=1;capture_frame_id<=sample_frame_id;end
        end
    end
    reg metadata_fault,geometry_fault;
    reg [31:0] metadata_rejections;
    always @(posedge clk) begin
        if(!rst_n) begin metadata_fault<=0;geometry_fault<=0;metadata_rejections<=0;end
        else if(result_update&&motion_enabled&&pipeline_rst_n&&(!result_motion_meta_ok||motion_geometry_bad)) begin
            if(!result_motion_meta_ok) metadata_fault<=1;
            if(motion_geometry_bad) geometry_fault<=1;
            metadata_rejections<=metadata_rejections+1'b1;
        end
    end
    wire [257:0] commit_motion_tag={motion_meta_cfg[result_frame_id[1:0]],result_is_test,
        result_generation,result_history_epoch,result_policy_epoch,
        motion_meta_epoch[result_frame_id[1:0]],result_frame_id};
    wire extract_valid,extract_ready,extract_busy,extract_fault,extract_fault_sticky;
    wire [7:0] extract_reason,extract_count;
    wire [31:0] extract_rejections;
    wire [257:0] extract_tag;
    wire [MAX_TRACKS*16-1:0] extract_lefts,extract_rights;
    projection_object_extractor #(.WIDTH(WIDTH),.MAX_OBJECTS(MAX_TRACKS),.TAG_WIDTH(258)) extractor (
        .clk(clk),.rst_n(rst_n),.flush(base_motion_flush||cancel_historical),
        .sample_valid(accept_projection_sample),
        .sample_x(sample_x),.sample_value(sample_value),.sample_frame_id(sample_frame_id),
        .cut_valid(accept_projection_cut),.cut_x(cut_x),.cut_frame_id(cut_frame_id),
        .commit_valid(motion_commit),.commit_frame_id(result_frame_id),.commit_tag(commit_motion_tag),
        .commit_count(result_count),.commit_cut_count(result_cut_count),
        .commit_high(result_high),.commit_low(result_low),.commit_min_width(result_min_width),.commit_gap(result_gap),
        .batch_valid(extract_valid),.batch_ready(extract_ready),.batch_tag(extract_tag),.batch_count(extract_count),
        .batch_lefts(extract_lefts),.batch_rights(extract_rights),.busy(extract_busy),
        .fault(extract_fault),.fault_sticky(extract_fault_sticky),.fault_reason(extract_reason),.fault_count(extract_rejections));
    wire tracker_ready,tracker_busy,tracker_fault_sticky;
    wire [15:0] tracker_reasons;
    wire [31:0] tracker_rejections;
    wire batch_current=extract_tag[159:32]==live_motion_context&&extract_tag[160]==active_source;
    wire tracker_valid=extract_valid&&batch_current&&!base_motion_flush&&!extract_fault;
    assign extract_ready=tracker_ready&&batch_current&&!base_motion_flush&&!extract_fault;
    wire [96:0] batch_cfg=extract_tag[257:161];
    conveyor_track_counter #(.MAX_TRACKS(MAX_TRACKS),.MAX_OBJECTS(MAX_TRACKS)) tracker (
        .clk(clk),.rst_n(rst_n),.flush(base_motion_flush||extract_fault),.clear_totals(motion_clear_totals),
        .batch_valid(tracker_valid),.batch_ready(tracker_ready),
        .batch_frame_id(extract_tag[31:0]),.batch_context(extract_tag[159:32]),.batch_is_test(extract_tag[160]),
        .batch_count(extract_count),.batch_lefts(extract_lefts),.batch_rights(extract_rights),
        .cfg_line_a(batch_cfg[95:80]),.cfg_line_b(batch_cfg[79:64]),.cfg_hysteresis(batch_cfg[63:48]),
        .cfg_max_step(batch_cfg[47:32]),.cfg_width_delta(batch_cfg[31:16]),
        .cfg_max_missed(batch_cfg[15:8]),.cfg_min_hits(batch_cfg[7:0]),
        .busy(tracker_busy),.frame_update(motion_frame_update),.frame_rejected(motion_frame_rejected),
        .output_frame_id(motion_frame_id),.output_context(motion_context),.output_is_test(motion_is_test),
        .delta_count(motion_delta),.camera_total(camera_total),.test_total(test_total),
        .event_valid(motion_event_valid),.event_track_id(motion_event_track_id),
        .event_frame_id(motion_event_frame_id),.event_context(motion_event_context),
        .event_is_test(motion_event_is_test),.event_seq(motion_event_seq),
        .fault_sticky(tracker_fault_sticky),.fault_reasons(tracker_reasons),.rejected_batches(tracker_rejections),
        .duplicate_batches(motion_duplicate_frames),.uncertain_tracks(motion_uncertain_tracks),.live_tracks(motion_live_tracks),
        .debug_valid(motion_debug_valid),.debug_track_id(motion_debug_track_id),
        .debug_left(motion_debug_left),.debug_right(motion_debug_right),.debug_center(motion_debug_center),
        .debug_phase(motion_debug_phase),.debug_counted(motion_debug_counted),.debug_eligible(motion_debug_eligible),
        .debug_frame_id(motion_debug_frame_id));
    assign motion_debug_context=motion_context;
    assign motion_debug_is_test=motion_is_test;
    assign motion_busy=extract_busy||tracker_busy;
    assign motion_fault_sticky=extract_fault_sticky||tracker_fault_sticky||metadata_fault||geometry_fault;
    assign motion_fault_reasons={metadata_fault,geometry_fault,6'd0,extract_reason,tracker_reasons};
    assign motion_rejected_frames=tracker_rejections+metadata_rejections;
    assign motion_extractor_faults=extract_rejections;
    always @(posedge clk) begin
        if(!rst_n) begin
            motion_objects_valid<=0;motion_objects_update<=0;motion_objects_count<=0;
            motion_objects_lefts<=0;motion_objects_rights<=0;motion_objects_frame_id<=0;
            motion_objects_context<=0;motion_objects_is_test<=0;
        end else begin
            motion_objects_update<=0;
            if(base_motion_flush||extract_fault) motion_objects_valid<=0;
            else if(tracker_valid&&tracker_ready) begin
                motion_objects_valid<=1;motion_objects_update<=1;motion_objects_count<=extract_count;
                motion_objects_lefts<=extract_lefts;motion_objects_rights<=extract_rights;
                motion_objects_frame_id<=extract_tag[31:0];motion_objects_context<=extract_tag[159:32];
                motion_objects_is_test<=extract_tag[160];
            end
        end
    end
endmodule
