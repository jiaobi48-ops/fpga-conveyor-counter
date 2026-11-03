'use strict';
/* Page controls, image input and JSON download tests. */
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const M=require('../model.js'),Demo=require('../demo.js'),ABC=require('../abc_adapter.js');
function start(){
  const elements={},blobs=[],downloads=[];
  function element(tag='div'){
    const e={tag,children:[],files:[],disabled:false,textContent:'',className:'',value:'trainEmpty',events:{},width:640,height:480,
      addEventListener(name,fn){this.events[name]=fn;},append(...x){this.children.push(...x);},replaceChildren(){this.children=[];},click(){if(tag==='a')downloads.push(this.download);},
      async fire(name){return this.events[name]?.();}};
    e.getContext=()=>({createImageData:(w,h)=>({data:new Uint8ClampedArray(w*h*4)}),putImageData(){},clearRect(){},strokeRect(){},beginPath(){},moveTo(){},lineTo(){},stroke(){},
      drawImage(b){e.bitmap=b;},getImageData(){return {data:e.bitmap.pixels};}});return e;
  }
  const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
  for(const match of html.matchAll(/id="([^"]+)"/g))elements[match[1]]=element();
  const context={OfflineCalibration:M,CalibrationDemo:Demo,ABCCalibration:ABC,document:{getElementById:id=>{assert.ok(elements[id],id);return elements[id];},createElement:element},
    Blob,Uint8Array,Uint8ClampedArray,Date,Promise,JSON,console,URL:{createObjectURL:b=>{blobs.push(b);return 'blob:unit-test';},revokeObjectURL(){}},
    setTimeout:fn=>{queueMicrotask(fn);return 1;},createImageBitmap:async f=>({width:f.width,height:f.height,pixels:f.pixels,close(){}})};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../app.js'),'utf8'),context);
  return {elements,blobs,downloads};
}
function png({name='sample.png',width=96,height=64,value=240,alpha=255}={}){
  const pixels=new Uint8ClampedArray(width*height*4);
  for(let i=0;i<width*height;i++)pixels.set([value,value,value,alpha],4*i);
  return {name,width,height,pixels,size:100,arrayBuffer:async()=>new Uint8Array([137,80,78,71,13,10,26,10]).buffer};
}
async function base(s,p=Demo.create().base){s.elements.baseFile.files=[{size:100,text:async()=>JSON.stringify(p)}];await s.elements.baseFile.fire('change');}
async function result(s){return JSON.parse(s.elements.result.textContent);}
test('demo updates candidate preview and status; all data are synthetic',async()=>{const s=start();await s.elements.demo.fire('click');const r=await result(s);assert.equal(r.status,'CANDIDATE_READY_FOR_REVIEW');assert.equal(s.elements.sampleCount.textContent,'8 张');assert.equal(r.profile.calibrated,false);assert.equal(s.elements.preview.width,96);assert.equal(s.elements.run.disabled,false);});
test('report export contains candidate and sample provenance',async()=>{const s=start();await s.elements.demo.fire('click');await s.elements.export.fire('click');const x=JSON.parse(await s.blobs[0].text());assert.equal(x.sample_manifest.length,8);assert.equal(x.contains_original_RGB,false);assert.equal(x.board_connected,false);assert.equal(x.commands_sent,false);assert.equal(x.profile.calibrated,false);assert.ok(x.sample_manifest.every(f=>f.provenance.synthetic));assert.equal(s.downloads.length,1);});
test('removing a sample invalidates stale export',async()=>{const s=start();await s.elements.demo.fire('click');await s.elements.samples.children[0].children[1].fire('click');assert.equal(s.elements.export.disabled,true);assert.equal(s.elements.sampleCount.textContent,'7 张');assert.equal(s.elements.result.textContent,'');});
test('clear and rerun refresh the exported sample status',async()=>{const s=start();await s.elements.demo.fire('click');await s.elements.clear.fire('click');assert.equal(s.elements.export.disabled,true);await s.elements.run.fire('click');assert.equal((await result(s)).status,'REJECTED');assert.equal(s.elements.status.className,'error');});
test('loading a new base resets samples and old result',async()=>{const s=start();await s.elements.demo.fire('click');await base(s);assert.equal(s.elements.sampleCount.textContent,'0 张');assert.equal(s.elements.export.disabled,true);assert.equal(s.elements.result.textContent,'');});
test('wrong schema import is shown as not loaded',async()=>{const s=start(),p=Demo.create().base;p.model='V3';await base(s,p);assert.match(s.elements.status.textContent,/配置未载入/);assert.equal(s.elements.status.className,'error');});
test('opaque PNG adapter can add an empty sample and preserves literal filename',async()=>{const s=start();await base(s);s.elements.rgbFile.files=[png({name:'<script>sample</script>.png'})];await s.elements.add.fire('click');assert.equal(s.elements.sampleCount.textContent,'1 张');assert.match(s.elements.samples.children[0].children[0].textContent,/<script>sample/);assert.equal(s.elements.add.disabled,false);});
test('transparent PNG adapter is rejected without adding sample',async()=>{const s=start();await base(s);s.elements.rgbFile.files=[png({alpha:0})];await s.elements.add.fire('click');assert.match(s.elements.status.textContent,/不能透明/);assert.equal(s.elements.sampleCount.textContent,'0 张');});
test('image dimensions are rejected instead of resized',async()=>{const s=start();await base(s);s.elements.rgbFile.files=[png({width:48})];await s.elements.add.fire('click');assert.match(s.elements.status.textContent,/尺寸完全一致/);});
test('a non-PNG file is rejected before image decoding',async()=>{const s=start();await base(s);s.elements.rgbFile.files=[{name:'renamed.png',size:20,arrayBuffer:async()=>new Uint8Array([255,216,255,0]).buffer}];await s.elements.add.fire('click');assert.match(s.elements.status.textContent,/仅接受原始PNG/);});
test('object mask must be pure black and white',async()=>{const s=start();await base(s);s.elements.role.value='trainObjects';s.elements.rgbFile.files=[png()];s.elements.maskFile.files=[png({value:128})];await s.elements.add.fire('click');assert.match(s.elements.status.textContent,/纯黑与纯白/);assert.equal(s.elements.sampleCount.textContent,'0 张');});

test('current-version button loads 800x480 base and clears samples',async()=>{const s=start();await s.elements.currentBase.fire('click');assert.match(s.elements.baseInfo.textContent,/800/);assert.equal(s.elements.sampleCount.textContent,'0 张');assert.equal(s.elements.exportABC.disabled,true);});
test('small demonstration keeps current-console scene export disabled',async()=>{const s=start();await s.elements.demo.fire('click');assert.equal(s.elements.exportABC.disabled,true);assert.equal(s.elements.export.disabled,false);});
