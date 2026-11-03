"""B pixel statistics, profile geometry and labelled-sample assessment.

Rectangles use half-open algorithm coordinates. Mapping is axis-aligned.
"""
from __future__ import annotations
from pathlib import Path
import argparse, copy, json, math
import numpy as np


def _integer(v, lo, hi):
    return isinstance(v, (int,np.integer)) and not isinstance(v,(bool,np.bool_)) and lo<=v<=hi


def _finite(v):
    return isinstance(v,(int,float,np.integer,np.floating)) and not isinstance(v,(bool,np.bool_)) and math.isfinite(v)


def _rgb(rgb):
    a=np.asarray(rgb)
    if a.ndim!=3 or a.shape[2]!=3 or min(a.shape[:2])==0:
        raise ValueError('RGB array must be nonempty HxWx3')
    if a.dtype.kind not in 'ui' or np.any(a<0) or np.any(a>255):
        raise ValueError('RGB samples must be integers in [0,255]')
    return a.astype(np.int32,copy=False)


def masks(rgb,threshold=144,invert=False,model='B'):
    a=_rgb(rgb)
    if not _integer(threshold,0,255) or not isinstance(invert,(bool,np.bool_)):
        raise ValueError('Invalid threshold or polarity')
    r,g,b=a[...,0],a[...,1],a[...,2]
    if model=='V3':gray=(r+2*g+b)//4
    elif model=='B':gray=(77*r+150*g+29*b+128)//256
    else:raise ValueError('Unknown algorithm model')
    warm=(r>80)&(r>g+12)&(r>b+16)
    neutral=(r<=g+12)&(r<=b+16)
    # V3 fixed dark-neutral predicate ignores invert, matching the RTL oracle.
    foreground=(gray<threshold)&neutral if model=='V3' else (gray>=threshold)^bool(invert)
    return dict(gray=gray,foreground=foreground,dark=gray<threshold,warm=warm)


def rect_valid(rect,width,height):
    return isinstance(rect,(list,tuple,np.ndarray)) and len(rect)==4 and all(_integer(v,0,65535) for v in rect) and 0<=rect[0]<rect[2]<=width and 0<=rect[1]<rect[3]<=height


def region_statistics(rgb,roi,guard,threshold=144,invert=False,model='B',guard_enable=True):
    """Match RTL counts; preserve clipped invalid geometry for fault fixtures."""
    a=_rgb(rgb);h,w=a.shape[:2];m=masks(a,threshold,invert,model)
    def clipped(rect):
        if not isinstance(rect,(list,tuple,np.ndarray)) or len(rect)!=4 or not all(_integer(v,0,65535) for v in rect):
            raise ValueError('Rectangle requires four unsigned integer coordinates')
        x0,y0,x1,y1=rect
        return slice(min(h,y0),min(h,y1)),slice(min(w,x0),min(w,x1))
    rs=clipped(roi)
    result=dict(geometry_good=rect_valid(roi,w,h) and (not guard_enable or rect_valid(guard,w,h)),
        roi_pixels=int(m['foreground'][rs].size),foreground_pixels=int(m['foreground'][rs].sum()),
        guard_pixels=0,guard_dark=0,guard_warm=0)
    if guard_enable:
        gs=clipped(guard);result.update(guard_pixels=int(m['dark'][gs].size),guard_dark=int(m['dark'][gs].sum()),guard_warm=int(m['warm'][gs].sum()))
    return result


def _mapping_valid(mapping):
    if not isinstance(mapping,dict):return False
    s,o=mapping.get('scale_xy'),mapping.get('offset_xy')
    return isinstance(s,(list,tuple)) and len(s)==2 and isinstance(o,(list,tuple)) and len(o)==2 and all(_finite(v) for v in [*s,*o]) and all(v>0 for v in s)


def validate_profile(profile):
    """Reject malformed values without coercing strings, booleans or NaNs."""
    if not isinstance(profile,dict):return ['profile_type']
    errors=[];size=profile.get('algorithm_size')
    size_good=isinstance(size,(list,tuple)) and len(size)==2 and all(_integer(v,5,65535) for v in size) and size[0]*size[1]<=16777216
    if not size_good:errors.append('algorithm_size')
    else:
        w,h=size
        if not rect_valid(profile.get('roi'),w,h):errors.append('roi')
        if profile.get('guard_enabled') is True and not rect_valid(profile.get('guard'),w,h):errors.append('guard')
    for field in ['guard_enabled','invert','calibrated']:
        if not isinstance(profile.get(field),bool):errors.append(field)
    p=profile.get('policy')
    if not isinstance(p,dict):errors.append('policy')
    else:
        for kind in ['dark','warm']:
            off,on=p.get(kind+'_off'),p.get(kind+'_on')
            if not (_integer(off,0,255) and _integer(on,1,256) and off<on):errors.append(kind+'_hysteresis')
        if not _integer(p.get('empty_ratio'),0,256):errors.append('empty_ratio')
        if not all(_integer(p.get(k),1,255) for k in ['normal_frames','empty_frames']):errors.append('recovery_frames')
        if not _integer(p.get('timeout_cycles'),1,0xffffffff):errors.append('timeout_cycles')
    motion=profile.get('motion')
    if not isinstance(motion,dict):errors.append('motion')
    else:
        a,b,hy=motion.get('line_a'),motion.get('line_b'),motion.get('hysteresis')
        good=all(_integer(v,0,65535) for v in [a,b,hy])
        if good and size_good and 'roi' not in errors:
            r=profile['roi'];good=b>=hy+2 and a+hy<=w-3 and a>b+2*hy and r[0]<b<a<r[2]
        else:good=False
        if not good:errors.append('motion_lines')
        if not _integer(motion.get('max_step'),1,65535) or not _integer(motion.get('width_delta'),0,65535):errors.append('motion_range')
        if not _integer(motion.get('min_hits'),1,255) or not _integer(motion.get('max_missed'),0,255):errors.append('track_confirmation')
    if profile.get('model') not in ['B','V3']:errors.append('model')
    if profile.get('model')=='V3' and profile.get('invert') is True:errors.append('v3_fixed_polarity')
    if not _integer(profile.get('threshold'),0,255):errors.append('threshold')
    if not _integer(profile.get('schema_version'),1,1):errors.append('schema_version')
    if not _integer(profile.get('scene_epoch'),0,0xffffffff):errors.append('scene_epoch')
    if profile.get('direction')!='right_to_left':errors.append('direction')
    if not _mapping_valid(profile.get('mapping')):errors.append('mapping')
    # Check declared pixel-size and morphology requirements.
    if 'projected_size' in profile:
        z=profile['projected_size'];good=isinstance(z,dict)
        if good:
            good=all(_integer(z.get(k),1,65535) for k in ['min_width','max_width','min_height','max_height'])
        if good:
            good=z['min_width']<=z['max_width'] and z['min_height']<=z['max_height']
            if size_good and 'roi' not in errors:
                r=profile['roi'];good=good and z['max_width']<=r[2]-r[0] and z['max_height']<=r[3]-r[1]
        if not good:errors.append('projected_size')
    if 'morphology' in profile:
        z=profile['morphology'];good=isinstance(z,dict) and _integer(z.get('kernel_size'),1,3) and z['kernel_size'] in [1,3] and _integer(z.get('passes'),0,2)
        if good and size_good and 'roi' not in errors:
            r=profile['roi'];border=(z['kernel_size']//2)*z['passes'];good=r[0]>=border and r[1]>=border and r[2]<=w-border and r[3]<=h-border
            if good and isinstance(profile.get('projected_size'),dict) and 'projected_size' not in errors:
                q=profile['projected_size'];good=q['min_width']>2*border and q['min_height']>2*border
        if not good:errors.append('morphology_margin')
    if 'speed' in profile:
        z=profile['speed'];good=isinstance(z,dict) and _integer(z.get('max_pixels_per_frame'),1,65535)
        if good and isinstance(motion,dict) and _integer(motion.get('max_step'),1,65535):good=z['max_pixels_per_frame']<=motion['max_step']
        if not good:errors.append('speed_range')
    return sorted(set(errors))


def validate_transition(previous,proposed,safety_active=True):
    """Check scene version changes when profile parameters change.

    safety_active means safety is enabled before OR after the commit. Any semantic
    profile edit requires a different epoch. Informational notes are ignored.
    """
    errors=['previous_'+s for s in validate_profile(previous)]+['proposed_'+s for s in validate_profile(proposed)]
    if not isinstance(safety_active,bool):errors.append('safety_active_type')
    if errors:return sorted(set(errors))
    old={k:v for k,v in previous.items() if k not in ['scene_epoch','note']}
    new={k:v for k,v in proposed.items() if k not in ['scene_epoch','note']}
    if safety_active and old!=new and previous['scene_epoch']==proposed['scene_epoch']:
        errors.append('scene_epoch_unchanged')
    return errors


def map_point(x,y,mapping,inverse=False):
    """Apply an axis-aligned floating-point coordinate mapping."""
    if not _mapping_valid(mapping) or not _finite(x) or not _finite(y):raise ValueError('Invalid axis-aligned mapping')
    sx,sy=mapping['scale_xy'];ox,oy=mapping['offset_xy']
    return ((x-ox)/sx,(y-oy)/sy) if inverse else (x*sx+ox,y*sy+oy)


def map_rect(rect,mapping,inverse=False):
    if not isinstance(rect,(list,tuple)) or len(rect)!=4 or not all(_finite(v) for v in rect) or not(rect[0]<rect[2] and rect[1]<rect[3]):raise ValueError('Invalid half-open rectangle')
    return (*map_point(rect[0],rect[1],mapping,inverse),*map_point(rect[2],rect[3],mapping,inverse))


def _assessment(accepted=False,reasons=None,**evidence):
    return dict(accepted=accepted,reasons=sorted(set(reasons or [])),automatic_apply=False,requires_human_confirmation=True,
        scope='sampled foreground, guard and empty-frame statistics',**evidence)


def assess_scene(empty_frames,object_frames,object_masks,profile):
    errors=validate_profile(profile)
    if errors:return _assessment(reasons=errors)
    if not isinstance(empty_frames,(list,tuple)) or not isinstance(object_frames,(list,tuple)) or not isinstance(object_masks,(list,tuple)) or not empty_frames or not object_frames or len(object_frames)!=len(object_masks):
        return _assessment(reasons=['missing_evidence'])
    w,h=profile['algorithm_size'];roi=np.zeros((h,w),dtype=bool);x0,y0,x1,y1=profile['roi'];roi[y0:y1,x0:x1]=True
    p,rows,reasons,recall,background_ratios=profile['policy'],[],[],[],[]
    def frame(a):
        try:a=_rgb(a)
        except (ValueError,TypeError):reasons.append('invalid_rgb');return None
        if a.shape[:2]!=(h,w):reasons.append('image_size');return None
        return a
    def guard_checks(s):
        if profile['guard_enabled'] and (s['guard_dark']*256>s['guard_pixels']*p['dark_off'] or s['guard_warm']*256>s['guard_pixels']*p['warm_off']):reasons.append('background_guard_unsuitable')
    for a in empty_frames:
        a=frame(a)
        if a is None:continue
        s=region_statistics(a,profile['roi'],profile['guard'],profile['threshold'],profile['invert'],profile['model'],profile['guard_enabled']);rows.append(s)
        if s['foreground_pixels']*256>s['roi_pixels']*p['empty_ratio']:reasons.append('background_occupied')
        guard_checks(s)
    for a,raw_label in zip(object_frames,object_masks):
        a=frame(a)
        if a is None:continue
        label=np.asarray(raw_label)
        if label.shape!=(h,w) or label.dtype.kind not in 'buif' or not np.isin(label,[0,1]).all() or not label.any():reasons.append('invalid_object_label');continue
        label=label.astype(bool)
        if np.any(label&~roi):reasons.append('object_outside_roi')
        m=masks(a,profile['threshold'],profile['invert'],profile['model']);recall.append(float((m['foreground']&label&roi).sum()/label.sum()))
        if recall[-1]<0.8:reasons.append('object_not_separated')
        negative=roi&~label;fp=int((m['foreground']&negative).sum());background_ratios.append(float(fp/max(1,int(negative.sum()))))
        if fp*256>int(negative.sum())*p['empty_ratio']:reasons.append('unlabelled_foreground')
        s=region_statistics(a,profile['roi'],profile['guard'],profile['threshold'],profile['invert'],profile['model'],profile['guard_enabled']);guard_checks(s)
        # The recovery supervisor uses this exact whole-ROI predicate. Good
        # per-target recall alone is insufficient: a tiny target can otherwise
        # be labelled an empty scene and permit unsafe history reinitialization.
        if s['foreground_pixels']*256<=s['roi_pixels']*p['empty_ratio']:
            reasons.append('object_indistinguishable_from_empty')
        if profile['guard_enabled']:
            gx0,gy0,gx1,gy1=profile['guard']
            if label[gy0:gy1,gx0:gx1].any():reasons.append('object_enters_guard')
    return _assessment(accepted=not reasons,reasons=reasons,empty_statistics=rows,object_pixel_recall=recall,
        object_background_false_positive_ratio=background_ratios,empty_frame_count=len(empty_frames),object_frame_count=len(object_frames))


def suggest_threshold(empty_frames,object_frames,object_masks,profile):
    """Search the sampled threshold band and retain base geometry."""
    errors=validate_profile(profile)
    if errors:return _assessment(reasons=errors)
    bands=[]
    for invert in ([False] if profile['model']=='V3' else [False,True]):
        band=[]
        for threshold in range(16,241,4):
            p=copy.deepcopy(profile);p['threshold'],p['invert']=threshold,invert
            if assess_scene(empty_frames,object_frames,object_masks,p)['accepted']:band.append((threshold,p))
            elif band:bands.append(band);band=[]
        if band:bands.append(band)
    if not bands:return _assessment(reasons=['no_separable_candidate'])
    band=max(bands,key=lambda b:(len(b),b[0][1]['invert']==profile['invert'],-b[0][0]));chosen=band[len(band)//2]
    chosen[1]['calibrated']=False
    return _assessment(accepted=True,profile=chosen[1],valid_thresholds=[x[0] for x in band],candidate_threshold_band=[band[0][0],band[-1][0]],
        model_scope=['fixed threshold samples','labelled foreground','guard and occupancy checks'])


def main():
    p=argparse.ArgumentParser();p.add_argument('profile',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
    profile=json.loads(a.profile.read_text(encoding='utf-8-sig'));result=_assessment(reasons=validate_profile(profile));result['accepted']=not result['reasons'];result['errors']=result['reasons']
    result['scope']='profile structure and geometry';data=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if a.output:a.output.write_text(data,encoding='utf-8')
    print(data,end='');return 1 if result['errors'] else 0
if __name__=='__main__':raise SystemExit(main())
