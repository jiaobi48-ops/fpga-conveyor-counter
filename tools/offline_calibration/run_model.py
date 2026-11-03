"""Decode a PNG manifest and run the shared browser calibration model."""
from pathlib import Path
import argparse,base64,hashlib,json,subprocess
from PIL import Image

HERE=Path(__file__).resolve().parent
ROLES=['trainEmpty','trainObjects','validationEmpty','validationObjects','blockedDark','blockedWarm']

def load_manifest(path):
    spec=json.loads(path.read_text(encoding='utf-8-sig'))
    if set(spec)-{'base','samples','note'}:raise ValueError('Unknown manifest field')
    def resolve(name):return (path.parent/name).resolve()
    base=json.loads(resolve(spec['base']).read_text(encoding='utf-8-sig'))
    w,h=base['algorithm_size']
    if type(w) is not int or type(h) is not int or not(32<=w<=4096 and 32<=h<=4096 and w*h<=4194304):raise ValueError('Invalid declared image size')
    samples=spec['samples']
    if not isinstance(samples,list) or len(samples)>20:raise ValueError('At most 20 samples')
    data={'base':base,**{r:[] for r in ROLES}};manifest=[]
    def read_png(filename,is_mask=False):
        p=resolve(filename)
        if p.stat().st_size>20*1024*1024:raise ValueError('PNG too large')
        with Image.open(p) as im:
            if im.format!='PNG' or im.size!=(w,h):raise ValueError('PNG format/algorithm dimensions mismatch: '+filename)
            rgba=im.convert('RGBA')
            if rgba.getchannel('A').getextrema()!=(255,255):raise ValueError('Transparent PNG: '+filename)
            rgb=rgba.convert('RGB').tobytes()
        if is_mask:
            values=[]
            for i in range(0,len(rgb),3):
                r,g,b=rgb[i:i+3]
                if r!=g or r!=b or r not in (0,255):raise ValueError('Mask must be exact black/white')
                values.append(int(r==255))
            rgb=bytes(values)
        return rgb,dict(filename=filename,file_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),source_frame_id=None,source_generation=None,source_timestamp=None)
    for s in samples:
        if set(s)-{'role','rgb','mask','id'} or s['role'] not in ROLES:raise ValueError('Unsupported sample field/role')
        rgb,origin=read_png(s['rgb']);f=dict(id=s.get('id',s['rgb']),width=w,height=h,rgb_base64=base64.b64encode(rgb).decode('ascii'))
        info=dict(role=s['role'],id=f['id'],provenance=origin)
        if s['role'] in ['trainObjects','validationObjects']:
            mask,mask_origin=read_png(s['mask'],True);f['mask_base64']=base64.b64encode(mask).decode('ascii');info['mask_provenance']=mask_origin
        elif 'mask' in s:raise ValueError('Mask supplied for a non-object role')
        data[s['role']].append(f);manifest.append(info)
    return data,manifest

def main():
    p=argparse.ArgumentParser();p.add_argument('manifest',type=Path);p.add_argument('--node',default='node');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.exists():raise ValueError('Keep previous reports; select a new output filename')
    data,manifest=load_manifest(a.manifest)
    run=subprocess.run([a.node,str(HERE/'runner.js')],input=json.dumps(data).encode('utf-8'),capture_output=True,timeout=180)
    if run.returncode:raise RuntimeError(run.stderr.decode('utf-8',errors='replace'))
    result=json.loads(run.stdout);result.update(sample_manifest=manifest,input_base=data['base'],contains_original_RGB=False,board_connected=False,commands_sent=False)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(result['status'],result['reasons'])
    return 1 if result['status']=='REJECTED' else 0

if __name__=='__main__':raise SystemExit(main())
