/* C v8.7: ROI, threshold and guard calibration for ABC v1.4. */
(function(root){
  'use strict';
  const VERSION='C-v8.7-ABC-v1.4';
  const clone=x=>JSON.parse(JSON.stringify(x));
  const int=(x,a,b)=>Number.isInteger(x)&&x>=a&&x<=b;
  const fail=(code,details={})=>({schema:'C-offline-calibration-v1',version:VERSION,status:'REJECTED',reasons:[code],details,
    profile:null,automatic_apply:false,requires_human_confirmation:true,hardware_verified:false});
  const area=r=>(r[2]-r[0])*(r[3]-r[1]);
  const inside=(x,y,r)=>x>=r[0]&&x<r[2]&&y>=r[1]&&y<r[3];
  const overlap=(a,b)=>a[0]<b[2]&&b[0]<a[2]&&a[1]<b[3]&&b[1]<a[3];
  const gray=(r,g,b)=>(77*r+150*g+29*b+128)>>8;
  const warm=(r,g,b)=>r>80&&r>g+12&&r>b+16;
  function validateBase(p){
    const errors=[];
    if(!p||typeof p!=='object'||Array.isArray(p))return ['base_type'];
    const allowed=['schema_version','model','algorithm_size','roi','guard','guard_enabled','direction','threshold','invert','scene_epoch','mapping','policy','motion','calibrated','note'];
    if(Object.keys(p).some(k=>!allowed.includes(k)))errors.push('unsupported_base_field');
    if(p.schema_version!==1||p.model!=='B')errors.push('requires_B_v013_profile');
    const size=p.algorithm_size;
    if(!Array.isArray(size)||size.length!==2||!size.every(v=>int(v,32,4096))||size[0]*size[1]>4194304)errors.push('algorithm_size');
    const rect=r=>Array.isArray(r)&&r.length===4&&r.every(v=>int(v,0,65535))&&r[0]<r[2]&&r[1]<r[3]&&r[2]<=size?.[0]&&r[3]<=size?.[1];
    if(!rect(p.roi)||!rect(p.guard))errors.push('base_geometry');
    if(p.guard_enabled!==true)errors.push('guard_must_remain_enabled');
    if(typeof p.invert!=='boolean'||p.calibrated!==false)errors.push('base_must_be_uncalibrated');
    if(p.direction!=='right_to_left'||!int(p.scene_epoch,0,0xffffffff)||!int(p.threshold,0,255))errors.push('base_version_or_direction');
    const policy=p.policy,m=p.motion;
    if(policy&&Object.keys(policy).some(k=>!['dark_on','dark_off','warm_on','warm_off','empty_ratio','normal_frames','empty_frames','timeout_cycles'].includes(k)))errors.push('unsupported_policy_field');
    if(m&&Object.keys(m).some(k=>!['line_a','line_b','hysteresis','max_step','width_delta','min_hits','max_missed'].includes(k)))errors.push('unsupported_motion_field');
    if(!policy||!['dark','warm'].every(k=>int(policy[k+'_off'],0,255)&&int(policy[k+'_on'],1,256)&&policy[k+'_off']<policy[k+'_on'])||!int(policy?.empty_ratio,0,255)||!int(policy?.normal_frames,1,255)||!int(policy?.empty_frames,1,255)||!int(policy?.timeout_cycles,1,0xffffffff))errors.push('base_policy');
    if(!m||!int(m.hysteresis,0,65535)||!int(m.max_step,1,65535)||!int(m.width_delta,0,65535)||!int(m.min_hits,1,255)||!int(m.max_missed,0,255)||!int(m.line_a,0,65535)||!int(m.line_b,0,65535))errors.push('base_motion');
    const mapping=p.mapping;
    if(!mapping||!Array.isArray(mapping.scale_xy)||!Array.isArray(mapping.offset_xy)||mapping.scale_xy.length!==2||mapping.offset_xy.length!==2||![...mapping.scale_xy,...mapping.offset_xy].every(x=>typeof x==='number'&&Number.isFinite(x))||!mapping.scale_xy.every(x=>x>0))errors.push('base_mapping');
    if(m&&rect(p.roi)&&!(m.line_b>=m.hysteresis+2&&m.line_a+m.hysteresis<=size[0]-3&&m.line_a>m.line_b+2*m.hysteresis&&p.roi[0]<m.line_b&&m.line_a<p.roi[2]))errors.push('base_motion_lines');
    return errors;
  }
  function prepare(f,size,labelled){
    if(!f||f.width!==size[0]||f.height!==size[1]||!f.rgb||f.rgb.length!==size[0]*size[1]*3)throw Error('image_size_or_rgb');
    const n=f.width*f.height;
    if(!(f.rgb instanceof Uint8Array)&&!(f.rgb instanceof Uint8ClampedArray))throw Error('rgb_requires_uint8');
    if(labelled&&(!f.mask||f.mask.length!==n))throw Error('missing_object_mask');
    const y=new Uint8Array(n),w=new Uint8Array(n);let count=0;
    const box=[f.width,f.height,0,0];
    for(let i=0;i<n;i++){
      const r=f.rgb[3*i],g=f.rgb[3*i+1],b=f.rgb[3*i+2];y[i]=gray(r,g,b);w[i]=+warm(r,g,b);
      if(labelled){
        if(f.mask[i]!==0&&f.mask[i]!==1)throw Error('mask_must_be_binary');
        if(f.mask[i]){const x=i%f.width,yy=Math.floor(i/f.width);count++;box[0]=Math.min(box[0],x);box[1]=Math.min(box[1],yy);box[2]=Math.max(box[2],x+1);box[3]=Math.max(box[3],yy+1);}
      }
    }
    if(labelled&&!count)throw Error('empty_object_mask');
    return {...f,y,w,count,box};
  }
  function samePixels(a,b){
    if(a.rgb.length!==b.rgb.length)return false;
    for(let i=0;i<a.rgb.length;i++)if(a.rgb[i]!==b.rgb[i])return false;
    return true;
  }
  function hist(f,roi){
    const all=new Uint32Array(256),positive=new Uint32Array(256);let target=0;
    for(let yy=roi[1];yy<roi[3];yy++)for(let x=roi[0];x<roi[2];x++){
      const i=yy*f.width+x;all[f.y[i]]++;if(f.mask?.[i]){positive[f.y[i]]++;target++;}
    }
    return {all,positive,target,total:area(roi)};
  }
  function fgCount(h,t,invert){let low=0;for(let y=0;y<t;y++)low+=h[y];return invert?low:h.reduce((a,b)=>a+b,0)-low;}
  function thresholdStats(empty,objects,t,invert){
    let maxBackground=0,minOccupied=Infinity,minRecall=1;
    for(const h of empty)maxBackground=Math.max(maxBackground,fgCount(h.all,t,invert)/h.total);
    for(const h of objects){
      const fg=fgCount(h.all,t,invert),tp=fgCount(h.positive,t,invert);
      minRecall=Math.min(minRecall,tp/h.target);minOccupied=Math.min(minOccupied,fg/h.total);
      maxBackground=Math.max(maxBackground,(fg-tp)/Math.max(1,h.total-h.target));
    }
    // One q/256 of spare occupancy above observed noise, with a strict target gap.
    const q=Math.ceil(maxBackground*256)+1;
    const maxQ=Math.ceil(minOccupied*256)-1;
    return {ok:minRecall>=0.8&&q<=maxQ&&q<=255,q,minRecall,maxBackground,minOccupied,maxQ};
  }
  function integrals(f,t){
    const stride=f.width+1,n=stride*(f.height+1),d=new Uint32Array(n),w=new Uint32Array(n),g=new Uint32Array(n);
    for(let yy=0;yy<f.height;yy++){
      let sd=0,sw=0,sg=0;
      for(let x=0;x<f.width;x++){
        const i=yy*f.width+x,k=(yy+1)*stride+x+1;
        sd+=f.y[i]<t;sw+=f.w[i];sg+=f.y[i];
        d[k]=d[k-stride]+sd;w[k]=w[k-stride]+sw;g[k]=g[k-stride]+sg;
      }
    }
    const sum=(a,r)=>a[r[3]*stride+r[2]]-a[r[1]*stride+r[2]]-a[r[3]*stride+r[0]]+a[r[1]*stride+r[0]];
    return r=>({dark:sum(d,r),warm:sum(w,r),gray:sum(g,r)});
  }
  function findGuard(normals,roi,t){
    const {width:w,height:h}=normals[0],pw=Math.max(8,Math.floor(w/8)),ph=Math.max(4,Math.floor(h/10));
    const candidates=[];
    for(let yy=2;yy+ph<=h-2;yy+=Math.max(2,Math.floor(ph/2)))for(let x=2;x+pw<=w-2;x+=Math.max(4,Math.floor(pw/2))){
      const r=[x,yy,x+pw,yy+ph];if(!overlap(r,roi))candidates.push({r,maxD:0,maxW:0,minY:255,maxY:0});
    }
    for(const f of normals){
      const sum=integrals(f,t);
      for(const c of candidates){const s=sum(c.r),a=area(c.r);c.maxD=Math.max(c.maxD,s.dark/a);c.maxW=Math.max(c.maxW,s.warm/a);c.minY=Math.min(c.minY,s.gray/a);c.maxY=Math.max(c.maxY,s.gray/a);}
    }
    const possible=candidates.map(c=>({...c,doff:Math.ceil(c.maxD*256)+8,woff:Math.ceil(c.maxW*256)+8}))
      .filter(c=>c.doff+16<=256&&c.woff+16<=256&&c.maxY-c.minY<=12);
    possible.sort((a,b)=>(a.maxD+a.maxW)-(b.maxD+b.maxW)||(a.maxY-a.minY)-(b.maxY-b.minY)||a.r[1]-b.r[1]||a.r[0]-b.r[0]);
    return possible[0]||null;
  }
  function statistics(f,p){
    let foreground=0,dark=0,w=0,graySum=0,target=0,tp=0,outside=0;
    for(let i=0;i<f.width*f.height;i++){
      const x=i%f.width,yy=Math.floor(i/f.width),fg=(f.y[i]>=p.threshold)!==p.invert;
      if(inside(x,yy,p.roi)){foreground+=+fg;graySum+=f.y[i];if(f.mask?.[i]){target++;tp+=+fg;}}
      else if(f.mask?.[i])outside++;
      if(inside(x,yy,p.guard)){dark+=+(f.y[i]<p.threshold);w+=f.w[i];}
    }
    const pixels=area(p.roi),guardPixels=area(p.guard);
    return {id:f.id||'',roi_pixels:pixels,foreground_pixels:foreground,guard_pixels:guardPixels,guard_dark:dark,guard_warm:w,roi_gray_sum:graySum,
      object_recall:target?tp/(target+outside):null,object_outside_roi:outside,
      non_object_foreground:target?foreground-tp:null,
      empty:foreground*256<=pixels*p.policy.empty_ratio,
      guard_can_release:dark*256<=guardPixels*p.policy.dark_off&&w*256<=guardPixels*p.policy.warm_off,
      dark_enters:dark*256>=guardPixels*p.policy.dark_on,warm_enters:w*256>=guardPixels*p.policy.warm_on};
  }
  function checkNormal(f,p,isObject){
    const s=statistics(f,p),reasons=[];
    if(!s.guard_can_release)reasons.push('background_guard_unsuitable');
    if(isObject){
      if(s.object_outside_roi)reasons.push('object_outside_roi');
      if(s.object_recall<0.8)reasons.push('object_not_separated');
      if(s.empty)reasons.push('object_indistinguishable_from_empty');
      if(s.non_object_foreground*256>(s.roi_pixels-f.count)*p.policy.empty_ratio)reasons.push('unlabelled_foreground');
      for(let yy=p.guard[1];yy<p.guard[3];yy++)for(let x=p.guard[0];x<p.guard[2];x++)if(f.mask[yy*f.width+x]){reasons.push('object_enters_guard');yy=p.guard[3];break;}
    }else if(!s.empty)reasons.push('background_occupied');
    return {ok:reasons.length===0,reasons:[...new Set(reasons)],...s};
  }
  function propose(data){
    try{
      const errors=validateBase(data?.base);if(errors.length)return fail('invalid_base_profile',{errors});
      const base=data.base,size=base.algorithm_size;
      for(const key of ['trainEmpty','trainObjects','validationEmpty','validationObjects','blockedDark','blockedWarm'])if(data[key]!==undefined&&!Array.isArray(data[key]))return fail('sample_list_type',{key});
      const te=data.trainEmpty||[],to=data.trainObjects||[],ve=data.validationEmpty||[],vo=data.validationObjects||[],bd=data.blockedDark||[],bw=data.blockedWarm||[];
      if(te.length<2||to.length<2)return fail('need_two_training_empty_and_object_frames');
      if(te.length+to.length+ve.length+vo.length+bd.length+bw.length>20)return fail('too_many_samples');
      const E=te.map(f=>prepare(f,size,false)),O=to.map(f=>prepare(f,size,true)),VE=ve.map(f=>prepare(f,size,false)),VO=vo.map(f=>prepare(f,size,true)),D=bd.map(f=>prepare(f,size,false)),W=bw.map(f=>prepare(f,size,false));
      if(E.every(f=>samePixels(f,E[0]))||O.every(f=>samePixels(f,O[0])))return fail('training_frames_not_distinct');
      if([...VE,...VO,...D,...W].some(f=>[...E,...O].some(t=>samePixels(f,t))))return fail('validation_reuses_training_image');
      for(const f of [...O,...VO]){
        if(f.box[0]<2||f.box[1]<2||f.box[2]>size[0]-2||f.box[3]>size[1]-2)return fail('target_touches_image_edge',{id:f.id});
        if(f.box[2]-f.box[0]<5||f.box[3]-f.box[1]<5)return fail('target_too_small_for_declared_margin',{id:f.id});
      }
      const box=O.reduce((b,f)=>[Math.min(b[0],f.box[0]),Math.min(b[1],f.box[1]),Math.max(b[2],f.box[2]),Math.max(b[3],f.box[3])],[size[0],size[1],0,0]);
      const roi=[Math.max(2,box[0]-8),Math.max(2,box[1]-8),Math.min(size[0]-2,box[2]+8),Math.min(size[1]-2,box[3]+8)];
      const hy=base.motion.hysteresis;
      const b=Math.max(hy+2,roi[0]+Math.floor((roi[2]-roi[0])/3)),a=Math.min(size[0]-3-hy,roi[0]+Math.floor(2*(roi[2]-roi[0])/3));
      if(!(roi[0]<b&&b<a&&a<roi[2]&&a>b+2*hy))return fail('roi_too_small_for_motion_lines');
      const EH=E.map(f=>hist(f,roi)),OH=O.map(f=>hist(f,roi)),bands=[];
      for(const invert of [false,true]){
        let band=[];
        for(let t=16;t<=240;t+=4){const s=thresholdStats(EH,OH,t,invert);if(s.ok)band.push({t,invert,...s});else if(band.length){bands.push(band);band=[];}}
        if(band.length)bands.push(band);
      }
      if(!bands.length)return fail('no_separable_threshold_in_search_grid');
      bands.sort((a,b)=>b.length-a.length||Number(b[0].invert===base.invert)-Number(a[0].invert===base.invert)||a[0].t-b[0].t);
      // Fit the threshold on training frames, then evaluate held-out frames.
      const band=bands[0],chosen=band[Math.floor(band.length/2)],guard=findGuard([...E,...O],roi,chosen.t);
      if(!guard)return fail('no_stable_guard_outside_observed_target_path');
      const p=clone(base);p.roi=roi;p.guard=guard.r;p.threshold=chosen.t;p.invert=chosen.invert;
      p.policy.empty_ratio=chosen.q;p.policy.dark_off=guard.doff;p.policy.dark_on=guard.doff+16;
      p.policy.warm_off=guard.woff;p.policy.warm_on=guard.woff+16;
      p.motion.line_a=a;p.motion.line_b=b;p.scene_epoch=(base.scene_epoch+1)>>>0;p.calibrated=false;
      p.note='ROI、阈值与遮挡保护参数候选；映射、恢复节拍和轨迹关联参数沿用基础配置。';
      const training=[...E.map(f=>checkNormal(f,p,false)),...O.map(f=>checkNormal(f,p,true))];
      if(training.some(x=>!x.ok))return fail('training_candidate_recheck_failed',{training});
      const validation=[...VE.map(f=>checkNormal(f,p,false)),...VO.map(f=>checkNormal(f,p,true))];
      const controls=[...D.map(f=>({kind:'dark',...statistics(f,p)})),...W.map(f=>({kind:'warm',...statistics(f,p)}))];
      const reasons=[];
      if(!VE.length||!VO.length)reasons.push('missing_held_out_empty_or_object');
      if(validation.some(x=>!x.ok))reasons.push('held_out_validation_failed');
      if(!D.length||!W.length)reasons.push('missing_dark_or_warm_positive_control');
      if(controls.some(x=>x.kind==='dark'?!x.dark_enters:!x.warm_enters))reasons.push('guard_positive_control_not_detected');
      const rejected=reasons.includes('held_out_validation_failed')||reasons.includes('guard_positive_control_not_detected');
      const result={schema:'C-offline-calibration-v1',version:VERSION,status:rejected?'REJECTED':reasons.length?'NEEDS_EVIDENCE':'CANDIDATE_READY_FOR_REVIEW',reasons,
        profile:p,automatic_apply:false,requires_human_confirmation:true,hardware_verified:false,source_mapping_confirmed:false,motion_validated:false,
        threshold_search:{step:4,range:[16,240],selected_band:[band[0].t,band[band.length-1].t],threshold:chosen.t,invert:chosen.invert,training_only:true},
        evidence:{training,validation,controls,guard_mean_range:[guard.minY,guard.maxY],guard_candidates_search:'fixed size axis-aligned grid outside training-mask bounding ROI'},
        sample_counts:{train_empty:E.length,train_objects:O.length,validation_empty:VE.length,validation_objects:VO.length,dark_controls:D.length,warm_controls:W.length},
        model_scope:['labelled ROI','weighted-gray threshold','guard hysteresis','empty-frame occupancy']};
      return result;
    }catch(error){return fail(error.message||'invalid_input');}
  }
  const api={VERSION,gray,warm,validateBase,propose,prepare,statistics,checkNormal};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.OfflineCalibration=api;
})(typeof globalThis!=='undefined'?globalThis:this);
