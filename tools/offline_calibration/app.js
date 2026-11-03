(function(){
  'use strict';
  const M=OfflineCalibration,A=ABCCalibration,$=id=>document.getElementById(id);
  const roles={trainEmpty:'训练空带',trainObjects:'训练物体',validationEmpty:'验证空带',validationObjects:'验证物体',blockedDark:'暗遮挡验证',blockedWarm:'暖遮挡验证'};
  let base=null,samples=[],last=null,busy=false,serial=0;
  const labels={CANDIDATE_READY_FOR_REVIEW:'样本检查通过，标定参数已生成。',NEEDS_EVIDENCE:'候选已生成，请补充列表中的样本。',REJECTED:'样本检查未通过，请查看具体原因。'};
  const reasons={invalid_base_profile:'基础配置格式或约束不符合B模式',need_two_training_empty_and_object_frames:'至少需要2张训练空带和2张带掩膜的训练物体图',training_frames_not_distinct:'训练帧完全相同，缺少不同样本',validation_reuses_training_image:'验证图像重复使用了训练图像',target_touches_image_edge:'目标太靠近画面边界，请保留两像素处理边缘',target_too_small_for_declared_margin:'标注目标小于5像素宽高要求',roi_too_small_for_motion_lines:'候选ROI无法容纳当前运动线和滞回间距',no_separable_threshold_in_search_grid:'所搜索阈值无法同时分开背景、目标和空场',no_stable_guard_outside_observed_target_path:'观测目标路径外找不到合适的稳定保护区',held_out_validation_failed:'独立验证样本检查失败',missing_held_out_empty_or_object:'缺少独立验证空带或物体图',missing_dark_or_warm_positive_control:'缺少暗色或暖色遮挡验证图',guard_positive_control_not_detected:'候选保护区未检出给定遮挡样本',image_size_or_rgb:'图像尺寸或RGB数据不匹配',missing_object_mask:'物体图缺少对应掩膜',mask_must_be_binary:'掩膜必须为严格黑白',empty_object_mask:'物体掩膜没有白色目标',training_candidate_recheck_failed:'训练候选复核失败'};
  function message(text,error=false){$('status').textContent=text;$('status').className=error?'error':'';}
  function invalidate(){last=null;$('export').disabled=true;$('exportABC').disabled=true;$('result').textContent='';$('summary').textContent='输入已变化，请重新生成。';}
  function lock(on){busy=on;for(const id of ['currentBase','demo','add','clear','run','baseFile','role','rgbFile','maskFile'])$(id).disabled=on;$('export').disabled=on||!last;$('exportABC').disabled=on||!last||last.status!=='CANDIDATE_READY_FOR_REVIEW'||last.profile?.algorithm_size?.join('x')!=='800x480';}
  function renderSamples(){
    $('sampleCount').textContent=samples.length+' 张';$('samples').replaceChildren();
    for(const s of samples){const row=document.createElement('div'),text=document.createElement('span'),button=document.createElement('button');row.className='sample';text.textContent=roles[s.role]+' · '+s.frame.id;button.textContent='移除';button.type='button';button.disabled=busy;button.addEventListener('click',()=>{samples=samples.filter(x=>x.key!==s.key);invalidate();renderSamples();preview();});row.append(text,button);$('samples').append(row);}
  }
  function preview(){
    const f=samples.find(x=>x.role==='validationObjects')?.frame||samples.find(x=>x.role==='trainObjects')?.frame||samples[0]?.frame;
    const canvas=$('preview'),ctx=canvas.getContext('2d');
    if(!f){ctx.clearRect(0,0,canvas.width,canvas.height);return;}
    canvas.width=f.width;canvas.height=f.height;const data=ctx.createImageData(f.width,f.height);
    for(let i=0;i<f.width*f.height;i++){data.data[4*i]=f.rgb[3*i];data.data[4*i+1]=f.rgb[3*i+1];data.data[4*i+2]=f.rgb[3*i+2];data.data[4*i+3]=255;if(f.mask?.[i]){data.data[4*i]=Math.round(data.data[4*i]*.55);data.data[4*i+1]=Math.round(data.data[4*i+1]*.55+115);data.data[4*i+2]=Math.round(data.data[4*i+2]*.55);}}
    ctx.putImageData(data,0,0);const p=last?.profile;if(!p)return;
    ctx.lineWidth=Math.max(1,f.width/400);
    for(const [r,color] of [[p.roi,'#1479df'],[p.guard,'#ed8612']]){ctx.strokeStyle=color;ctx.strokeRect(r[0]+.5,r[1]+.5,r[2]-r[0]-1,r[3]-r[1]-1);}
    ctx.strokeStyle='#aa3abd';for(const x of [p.motion.line_a,p.motion.line_b]){ctx.beginPath();ctx.moveTo(x,p.roi[1]);ctx.lineTo(x,p.roi[3]);ctx.stroke();}
  }
  function show(result){
    last=result;$('export').disabled=false;message(labels[result.status]||result.status,result.status==='REJECTED');if(result.status==='CANDIDATE_READY_FOR_REVIEW')$('status').className='ready';
    const p=result.profile;
    $('summary').textContent=(p?`算法尺寸：${p.algorithm_size.join(' × ')}\nROI：${p.roi.join(', ')}\n保护区：${p.guard.join(', ')}\n阈值：${p.threshold}；invert：${p.invert}\n空场比例：${p.policy.empty_ratio}/256\n暗色on/off：${p.policy.dark_on}/${p.policy.dark_off}\n暖色on/off：${p.policy.warm_on}/${p.policy.warm_off}\nscene_epoch：${p.scene_epoch}\ncalibrated：false\n`:'')+(result.reasons.length?'\n'+result.reasons.map(x=>reasons[x]||x).join('\n'):'\n训练、独立样本和遮挡检查通过。800×480结果可导出为控制台算法场景。');
    $('result').textContent=JSON.stringify(result,null,2);preview();
  }
  function data(){const x={base};for(const key of Object.keys(roles))x[key]=samples.filter(s=>s.role===key).map(s=>s.frame);return x;}
  async function run(){if(busy)return;invalidate();lock(true);message('正在计算离线候选…');try{await new Promise(resolve=>setTimeout(resolve,30));show(M.propose(data()));}catch(e){message(e.message,true);}finally{lock(false);}}
  async function png(file,isMask){
    if(!file||file.size>20*1024*1024)throw Error('请选择20MB以内的PNG。');
    const bytes=new Uint8Array(await file.arrayBuffer());if(![137,80,78,71,13,10,26,10].every((x,i)=>bytes[i]===x))throw Error('仅接受原始PNG格式。');
    const bitmap=await createImageBitmap(file,{colorSpaceConversion:'none'});
    try{
      if(!base||bitmap.width!==base.algorithm_size[0]||bitmap.height!==base.algorithm_size[1])throw Error('图片必须与基础配置的算法尺寸完全一致；不自动缩放。');
      const canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;const ctx=canvas.getContext('2d',{willReadFrequently:true});ctx.drawImage(bitmap,0,0);const rgba=ctx.getImageData(0,0,canvas.width,canvas.height).data;
      const rgb=new Uint8Array(bitmap.width*bitmap.height*3),mask=isMask?new Uint8Array(bitmap.width*bitmap.height):null;
      for(let i=0;i<bitmap.width*bitmap.height;i++){
        if(rgba[4*i+3]!==255)throw Error('PNG不能透明，避免显示背景混入像素统计。');
        rgb.set(rgba.subarray(4*i,4*i+3),3*i);
        if(isMask){const r=rgba[4*i],g=rgba[4*i+1],b=rgba[4*i+2];if(r!==g||r!==b||(r!==0&&r!==255))throw Error('掩膜必须为纯黑与纯白，不含灰色抗锯齿。');mask[i]=r===255?1:0;}
      }
      const hash=globalThis.crypto?.subtle?Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join(''):null;
      return {id:file.name,width:bitmap.width,height:bitmap.height,rgb,mask,provenance:{filename:file.name,file_sha256:hash,source_frame_id:null,source_generation:null,source_timestamp:null}};
    }finally{bitmap.close();}
  }
  $('baseFile').addEventListener('change',async()=>{if(busy)return;try{const file=$('baseFile').files[0];if(!file||file.size>100000)throw Error('JSON缺失或过大。');const p=JSON.parse((await file.text()).replace(/^\uFEFF/,'')),errors=M.validateBase(p);if(errors.length)throw Error(errors.join('；'));base=p;samples=[];invalidate();renderSamples();preview();$('baseInfo').textContent=`B模式，${p.algorithm_size.join(' × ')}；scene_epoch=${p.scene_epoch}。基础配置已载入。`;message('基础配置已载入，请添加样本。');}catch(e){message('配置未载入：'+e.message,true);}});
  $('add').addEventListener('click',async()=>{if(busy)return;if(!base)return message('请先导入基础配置。',true);lock(true);try{const role=$('role').value;if(samples.length>=20)throw Error('每次最多20张RGB样本。');const frame=await png($('rgbFile').files[0],false);if(role==='trainObjects'||role==='validationObjects'){const m=await png($('maskFile').files[0],true);frame.mask=m.mask;frame.mask_provenance=m.provenance;}samples.push({key:++serial,role,frame});invalidate();renderSamples();preview();message('样本已添加。');}catch(e){message(e.message,true);}finally{lock(false);renderSamples();}});
  $('clear').addEventListener('click',()=>{samples=[];invalidate();renderSamples();preview();message('样本已清空，基础配置保留。');});
  $('run').addEventListener('click',run);
  $('currentBase').addEventListener('click',()=>{base=A.base();samples=[];invalidate();renderSamples();preview();$('baseInfo').textContent='ABC v1.4：800 × 480，算法与LCD坐标一致；75 MHz。';message('当前版本基础配置已载入，请添加相机原图样本。');});
  $('demo').addEventListener('click',async()=>{if(busy)return;const demo=CalibrationDemo.create();base=demo.base;samples=[];for(const role of Object.keys(roles))for(const frame of demo[role])samples.push({key:++serial,role,frame});$('baseInfo').textContent='合成演示：96 × 64，8张图像，用于演示标定操作。';renderSamples();preview();await run();});
  $('exportABC').addEventListener('click',()=>{if(!last||busy)return;try{const scene=A.scene(last),url=URL.createObjectURL(new Blob([JSON.stringify(scene,null,2)+'\n'],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='ABC_v14_标定算法场景.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);message('场景已导出；在控制台的FPGA算法页点击“载入算法场景”。');}catch(e){message(e.message,true);}});
  $('export').addEventListener('click',()=>{if(!last||busy)return;const record={...last,exported_at:new Date().toISOString(),input_base:base,sample_manifest:samples.map(s=>({role:s.role,id:s.frame.id,provenance:s.frame.provenance||{synthetic:true},mask_provenance:s.frame.mask_provenance||null})),contains_original_RGB:false,board_connected:false,commands_sent:false};const url=URL.createObjectURL(new Blob([JSON.stringify(record,null,2)+'\n'],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='C_v87_离线标定检查记录.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
})();
