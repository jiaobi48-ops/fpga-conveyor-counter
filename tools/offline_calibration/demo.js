/* Deterministic sample images for the interactive calibration demonstration. */
(function(root){
  function create(){
    const width=96,height=64;
    const base={schema_version:1,model:'B',algorithm_size:[width,height],roi:[2,12,94,60],guard:[2,2,14,8],guard_enabled:true,direction:'right_to_left',threshold:128,invert:false,scene_epoch:9,
      mapping:{scale_xy:[1,1],offset_xy:[0,0]},policy:{dark_on:128,dark_off:96,warm_on:32,warm_off:16,empty_ratio:4,normal_frames:3,empty_frames:2,timeout_cycles:10000000},
      motion:{line_a:64,line_b:32,hysteresis:2,max_step:16,width_delta:16,min_hits:3,max_missed:2},calibrated:false,note:'96x64 synthetic samples with identity algorithm-coordinate mapping.'};
    function frame(id,color,box,target){
      const rgb=new Uint8Array(width*height*3),mask=box?new Uint8Array(width*height):undefined;
      for(let y=0;y<height;y++)for(let x=0;x<width;x++){
        const i=y*width+x;let c=color;
        if(box&&x>=box[0]&&x<box[2]&&y>=box[1]&&y<box[3]){c=target||[35,35,35];mask[i]=1;}
        rgb.set(c,3*i);
      }
      return {id,width,height,rgb,...(mask?{mask}:{})};
    }
    return {base,trainEmpty:[frame('合成训练空带1',[238,238,238]),frame('合成训练空带2',[242,242,242])],
      trainObjects:[frame('合成训练目标1',[239,239,239],[24,26,36,42]),frame('合成训练目标2',[241,241,241],[60,26,76,42])],
      validationEmpty:[frame('合成独立空带',[240,240,240])],validationObjects:[frame('合成独立目标',[243,243,243],[43,27,56,41])],
      blockedDark:[frame('合成暗遮挡',[0,0,0])],blockedWarm:[frame('合成暖遮挡',[230,100,30])]};
  }
  if(typeof module!=='undefined'&&module.exports)module.exports={create};else root.CalibrationDemo={create};
})(typeof globalThis!=='undefined'?globalThis:this);
