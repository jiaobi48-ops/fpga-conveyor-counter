'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const M=require('../model.js'),A=require('../abc_adapter.js'),D=require('../demo.js');
function frames(){
  const d=D.create(),f=8;
  const out={base:A.base()};
  for(const role of ['trainEmpty','trainObjects','validationEmpty','validationObjects','blockedDark','blockedWarm']){
    out[role]=d[role].map(old=>{
      const width=800,height=480,rgb=new Uint8Array(width*height*3),mask=old.mask?new Uint8Array(width*height):undefined;
      for(let y=0;y<height;y++)for(let x=0;x<width;x++){
        const ox=Math.min(95,Math.floor(x/f)),oy=Math.min(63,Math.floor(y/f)),i=y*width+x,j=oy*96+ox;
        rgb.set(old.rgb.subarray(j*3,j*3+3),i*3);if(mask)mask[i]=old.mask[j];
      }
      return {id:old.id,width,height,rgb,...(mask?{mask}:{})};
    });
  }
  return out;
}
test('current base uses actual dimensions, clock-derived timeout and tracking limits',()=>{
  const b=A.base();assert.deepEqual(M.validateBase(b),[]);assert.deepEqual(b.algorithm_size,[800,480]);
  assert.equal(b.policy.timeout_cycles,7500000);assert.equal(b.motion.max_step,120);
  b.roi[0]=20;assert.equal(A.base().roi[0],2);
});
test('800x480 complete model exports paused native scene with calibrated threshold range',()=>{
  const r=M.propose(frames());assert.equal(r.status,'CANDIDATE_READY_FOR_REVIEW',JSON.stringify(r));
  const s=A.scene(r),c=s.configuration;assert.equal(s.schema,'ABC-1.4');
  assert.equal(c.sys_manual_block,1);assert.equal(c.sys_manual_mode,1);assert.equal(c.cfg_guard_enable,1);
  assert.equal(c.cfg_line_a,r.profile.motion.line_a);assert.equal(c.cfg_safety_roi_x1,r.profile.roi[2]);
  assert.equal(c.cfg_threshold_min,r.threshold_search.selected_band[0]);
  assert.equal(c.cfg_threshold_max,r.threshold_search.selected_band[1]);
  assert.ok(c.cfg_mean_offset>=-256&&c.cfg_mean_offset<=255);
  assert.equal(c.cfg_auto_threshold,undefined);assert.equal(c.cfg_auto_denoise,undefined);
  assert.equal(c.cfg_parallel_enable,undefined);assert.equal(c.cfg_merge_enable,undefined);
  const fs=require('node:fs');if(process.env.ABC_SCENE_OUTPUT)fs.writeFileSync(process.env.ABC_SCENE_OUTPUT,JSON.stringify(s,null,2));
});
test('smaller demonstration and incomplete or rejected samples retain report export',()=>{
  assert.throws(()=>A.scene(M.propose(D.create())),/800/);
  assert.throws(()=>A.scene({status:'NEEDS_EVIDENCE'}),/样本检查/);
  assert.throws(()=>A.scene({status:'REJECTED'}),/样本检查/);
});
