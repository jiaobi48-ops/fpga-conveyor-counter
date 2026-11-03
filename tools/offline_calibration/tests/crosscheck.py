"""PNG/CLI roundtrip and crosscheck candidates/pixel counts against original B."""
from pathlib import Path
from hashlib import sha256
import argparse,base64,copy,importlib.util,json,subprocess,sys
from contextlib import nullcontext
import numpy as np
from PIL import Image

HERE=Path(__file__).resolve().parents[1]
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
B=load(HERE/'reference/b_scene_reference.py','received_b_scene')
CLI=load(HERE/'run_model.py','c_cli_bridge')

def main():
    p=argparse.ArgumentParser();p.add_argument('--node',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output=a.output.resolve()
    assert not a.output.exists(),'Keep old verification records'
    a.output.mkdir(parents=True)
    checks=[]
    def check(name,condition):
        assert condition,name;checks.append(name)
    example=HERE/'examples/合成演示/manifest.json';data,files=CLI.load_manifest(example)
    command=[sys.executable,str(HERE/'run_model.py'),str(example),'--node',a.node,'--output',str(a.output/'png_roundtrip.json')]
    run=subprocess.run(command,capture_output=True,timeout=180);(a.output/'png_roundtrip_console.log').write_bytes(run.stdout+run.stderr)
    check('PNG_CLI_exit',run.returncode==0)
    result=json.loads((a.output/'png_roundtrip.json').read_text(encoding='utf-8'))
    check('candidate_ready',result['status']=='CANDIDATE_READY_FOR_REVIEW')
    q=result['profile'];check('original_B_profile_validator',B.validate_profile(q)==[])
    check('original_B_transition_validator',B.validate_transition(data['base'],q,safety_active=True)==[])
    check('uncalibrated_and_no_apply',not q['calibrated'] and not result['automatic_apply'] and not result['hardware_verified'])
    check('PNG_manifest_no_fake_source_identity',all(f['provenance']['source_frame_id'] is None for f in result['sample_manifest']))
    decoded={}
    for role,fs in data.items():
        if role=='base':continue
        decoded[role]=[]
        for frame in fs:
            rgb=np.frombuffer(base64.b64decode(frame['rgb_base64']),np.uint8).reshape(frame['height'],frame['width'],3)
            mask=np.frombuffer(base64.b64decode(frame['mask_base64']),np.uint8).reshape(frame['height'],frame['width']) if 'mask_base64' in frame else None
            decoded[role].append((rgb,mask))
    for prefix,er,ore in [('train','trainEmpty','trainObjects'),('heldout','validationEmpty','validationObjects')]:
        assessment=B.assess_scene([f[0] for f in decoded[er]],[f[0] for f in decoded[ore]],[f[1] for f in decoded[ore]],q)
        check(prefix+'_original_B_assessment',assessment['accepted'])
    # Compare every model evidence count with B's original pixel predicates.
    ordered=decoded['trainEmpty']+decoded['trainObjects']+decoded['validationEmpty']+decoded['validationObjects']+decoded['blockedDark']+decoded['blockedWarm']
    observations=result['evidence']['training']+result['evidence']['validation']+result['evidence']['controls']
    for i,((rgb,mask),actual) in enumerate(zip(ordered,observations)):
        expected=B.region_statistics(rgb,q['roi'],q['guard'],q['threshold'],q['invert'],'B',True)
        for key in ['roi_pixels','foreground_pixels','guard_pixels','guard_dark','guard_warm']:
            check(f'PNG_{i}_{key}',actual[key]==expected[key])
        x0,y0,x1,y1=q['roi'];gray=B.masks(rgb,q['threshold'],q['invert'],'B')['gray']
        check(f'PNG_{i}_gray_sum',actual['roi_gray_sum']==int(gray[y0:y1,x0:x1].sum()))
    # Additional independent random inputs/polarity/threshold boundaries through the same JS core.
    rng=np.random.default_rng(20261026);cases=[];expected=[]
    for i in range(32):
        rgb=rng.integers(0,256,(32,40,3),dtype=np.uint8);threshold=[0,1,127,128,144,254,255,240][i%8];invert=bool((i//8)%2)
        config=copy.deepcopy(q);config.update(roi=[3,5,37,29],guard=[2,1,15,5],threshold=threshold,invert=invert)
        cases.append(dict(width=40,height=32,rgb_base64=base64.b64encode(rgb.tobytes()).decode('ascii'),profile=config))
        stats=B.region_statistics(rgb,config['roi'],config['guard'],threshold,invert,'B',True)
        stats['roi_gray_sum']=int(B.masks(rgb,threshold,invert,'B')['gray'][5:29,3:37].sum());expected.append(stats)
    js="const fs=require('node:fs'),m=require(process.argv[1]),x=JSON.parse(fs.readFileSync(0,'utf8'));console.log(JSON.stringify(x.map(c=>m.statistics(m.prepare({...c,rgb:new Uint8Array(Buffer.from(c.rgb_base64,'base64'))},[40,32],false),c.profile))));"
    run=subprocess.run([a.node,'-e',js,str(HERE/'model.js')],input=json.dumps(cases).encode(),capture_output=True,timeout=180)
    check('random_JS_exit',run.returncode==0);actual=json.loads(run.stdout)
    for i,(x,y) in enumerate(zip(actual,expected)):
        for key in ['roi_pixels','foreground_pixels','guard_pixels','guard_dark','guard_warm','roi_gray_sum']:
            check(f'random_{i}_{key}',x[key]==y[key])
    # Check repeat CLI invocation preserves the existing report.
    old=(a.output/'png_roundtrip.json').read_bytes();again=subprocess.run(command,capture_output=True,timeout=180)
    check('CLI_preserves_existing_report',again.returncode!=0 and (a.output/'png_roundtrip.json').read_bytes()==old)
    invalid_dir=a.output/'invalid_inputs';invalid_dir.mkdir()
    # Store fault fixtures inside the selected output directory.
    with nullcontext(invalid_dir) as temp:
        folder=Path(temp);source=json.loads(example.read_text(encoding='utf-8'));source['base']=str((example.parent/'base.json').resolve())
        for s in source['samples']:
            s['rgb']=str((example.parent/s['rgb']).resolve())
            if 'mask' in s:s['mask']=str((example.parent/s['mask']).resolve())
        def denied(name,change):
            value=copy.deepcopy(source);change(value);path=folder/(name+'.json');path.write_text(json.dumps(value),encoding='utf-8')
            try:CLI.load_manifest(path)
            except (ValueError,KeyError):check(name,True)
            else:check(name,False)
        small=folder/'wrong_size.png';Image.new('RGB',(48,32),(20,20,20)).save(small)
        denied('PNG_size_mismatch',lambda x:x['samples'][0].update(rgb=str(small)))
        transparent=folder/'transparent.png';Image.new('RGBA',(96,64),(0,0,0,0)).save(transparent)
        denied('PNG_transparency_rejected',lambda x:x['samples'][0].update(rgb=str(transparent)))
        notmask=folder/'gray_mask.png';Image.new('L',(96,64),128).save(notmask)
        denied('nonbinary_mask_rejected',lambda x:x['samples'][2].update(mask=str(notmask)))
        jpg=folder/'renamed.png';Image.new('RGB',(96,64),(240,240,240)).save(jpg,format='JPEG')
        denied('renamed_JPEG_rejected',lambda x:x['samples'][0].update(rgb=str(jpg)))
    summary=dict(status='PASS',checks=len(checks),check_names=checks,random_RGB_frames=32,PNG_sample_frames=8,
        original_B_reference_sha256=sha256((HERE/'reference/b_scene_reference.py').read_bytes()).hexdigest(),
        hardware_verified=False,browser_verified=False,scope='PNG CLI roundtrip, B profile geometry and pixel statistics')
    (a.output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS CROSSCHECK',len(checks),'checks, 8 PNG frames, 32 random RGB frames; B reference pixel rules')
if __name__=='__main__':main()
