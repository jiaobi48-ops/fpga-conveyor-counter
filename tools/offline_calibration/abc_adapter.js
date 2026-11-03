/* ABC v1.4: 800x480 algorithm coordinates, 75 MHz timers and native scene export. */
(function(root){
  'use strict';
  const baseProfile={schema_version:1,model:'B',algorithm_size:[800,480],
    roi:[2,2,798,478],guard:[320,8,480,48],guard_enabled:true,
    direction:'right_to_left',threshold:128,invert:true,scene_epoch:1,
    mapping:{scale_xy:[1,1],offset_xy:[0,0]},
    policy:{dark_on:192,dark_off:96,warm_on:48,warm_off:16,empty_ratio:12,
      normal_frames:3,empty_frames:2,timeout_cycles:7500000},
    motion:{line_a:410,line_b:220,hysteresis:10,max_step:120,width_delta:30,min_hits:2,max_missed:2},
    calibrated:false,note:'ABC v1.4 800x480算法与LCD坐标，75MHz算法时钟。'};
  function base(){return JSON.parse(JSON.stringify(baseProfile));}
  function scene(report){
    if(report?.status!=='CANDIDATE_READY_FOR_REVIEW'||!report.profile)
      throw Error('请完成训练、独立样本和遮挡样本检查后导出。');
    const p=report.profile;
    if(p.model!=='B'||JSON.stringify(p.algorithm_size)!=='[800,480]')
      throw Error('控制台场景使用800×480算法图像，请载入当前版本基础配置。');
    if(JSON.stringify(p.mapping?.scale_xy)!=='[1,1]'||JSON.stringify(p.mapping?.offset_xy)!=='[0,0]')
      throw Error('控制台场景使用算法图像的原始坐标映射。');
    const c={cfg_threshold:p.threshold,cfg_invert:+p.invert,
      cfg_safety_roi_x0:p.roi[0],cfg_safety_roi_y0:p.roi[1],
      cfg_safety_roi_x1:p.roi[2],cfg_safety_roi_y1:p.roi[3],
      cfg_guard_x0:p.guard[0],cfg_guard_y0:p.guard[1],
      cfg_guard_x1:p.guard[2],cfg_guard_y1:p.guard[3],
      cfg_guard_dark_on:p.policy.dark_on,cfg_guard_dark_off:p.policy.dark_off,
      cfg_guard_warm_on:p.policy.warm_on,cfg_guard_warm_off:p.policy.warm_off,
      cfg_empty_ratio:p.policy.empty_ratio,
      cfg_recovery_normal_frames:p.policy.normal_frames,
      cfg_recovery_empty_frames:p.policy.empty_frames,
      cfg_source_timeout_cycles:p.policy.timeout_cycles,
      cfg_line_a:p.motion.line_a,cfg_line_b:p.motion.line_b,
      cfg_hysteresis:p.motion.hysteresis,cfg_max_step:p.motion.max_step,
      cfg_width_delta:p.motion.width_delta,cfg_min_hits:p.motion.min_hits,
      cfg_max_missed:p.motion.max_missed,
      cfg_safety_enable:1,cfg_scene_valid:1,cfg_guard_enable:1,
      cfg_test_async:0,sys_dip_override:0,sys_count_enable:1,
      sys_manual_mode:1,sys_manual_block:1};
    const band=report.threshold_search?.selected_band;
    if(band){c.cfg_threshold_min=band[0];c.cfg_threshold_max=band[1];}
    const empties=(report.evidence?.training||[]).slice(0,report.sample_counts?.train_empty||0);
    const pixels=empties.reduce((s,f)=>s+f.roi_pixels,0);
    if(pixels){
      const background=empties.reduce((s,f)=>s+f.roi_gray_sum,0)/pixels;
      c.cfg_mean_offset=Math.max(-256,Math.min(255,Math.round(p.threshold-background)));
    }
    return {schema:'ABC-1.4',configuration:c,
      calibration:{tool:'C-v8.7-ABC-v1.4',algorithm_size:[800,480],clock_hz:75000000,
        direction:'right_to_left',roi_coordinates:'half-open algorithm/LCD pixels',
        status:report.status,sample_counts:report.sample_counts,
        threshold_band:band,load_mode:'manual_paused'}};
  }
  const api={base,scene};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ABCCalibration=api;
})(typeof globalThis!=='undefined'?globalThis:this);
