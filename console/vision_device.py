"""ABC native configuration and coherent, firmware-published result reader."""
from pathlib import Path
import json,struct,time

SCHEMA=json.loads((Path(__file__).with_name('vision_registers.json')).read_text(encoding='utf-8'))
BY_NAME={p['name']:p for p in SCHEMA['config']}
RESULTS={p['name']:p for p in SCHEMA['results']}
BASE=0x03001000

def effective_configuration(cfg):
    effective=dict(cfg)
    if cfg['sys_dip_override']:
        bits=cfg['sys_dip_bits']
        for name,bit in [('cfg_test_async',0),('cfg_bist_dynamic',1),('cfg_auto_threshold',4),('cfg_auto_denoise',5),('cfg_parallel_enable',6),('cfg_valley_enable',7)]:
            effective[name]=(bits>>bit)&1
        effective['cfg_scene']=effective['cfg_bist_profile']=(bits>>2)&3
    if effective['cfg_test_async']:
        effective['cfg_invert']=0;effective['cfg_mean_offset']=24
    effective['cfg_motion_enable']=int(bool(cfg['cfg_motion_enable'] and cfg['sys_count_enable'] and not(cfg['sys_manual_mode'] and cfg['sys_manual_block'])))
    effective['cfg_guard_enable']=int(bool(cfg['cfg_guard_enable'] and not cfg['sys_manual_mode']))
    return effective

def decode(blob):
    words=struct.unpack('<'+'I'*(len(blob)//4),blob)
    if words[0]&1 or words[1]!=0xC31401 or words[2]!=len(BY_NAME) or words[3]!=SCHEMA['snapshot_words']:
        raise ValueError('算法快照正在更新或版本不匹配')
    cfg={}
    for p in SCHEMA['config']:
        v=words[16+p['index']]
        if p.get('signed') and v&0x80000000:v-=1<<32
        cfg[p['name']]=v
    raw=words[128:];results={}
    for n,p in RESULTS.items():
        v=sum(raw[p['word']+i]<<(32*i) for i in range(p['words']))
        if p.get('signed') and v&(1<<(p['width']-1)):v-=1<<p['width']
        results[n]=v
    r=results
    clock_hz=raw[14] or SCHEMA['clock_hz']
    velocity=r['speed_dx']*clock_hz/r['speed_cycles_per_frame'] if r['speed_valid'] and r['speed_cycles_per_frame'] else None
    return dict(version='ABC-1.4',sequence=words[0],configuration=cfg,effective_configuration=effective_configuration(cfg),results=results,
        source='test' if r['active_source'] else 'camera',count=r['test_total'] if r['active_source'] else r['camera_total'],
        velocity_px_s=velocity,observed_feature_mask=raw[6],clock_hz=clock_hz)

def read(device):
    n=(128+SCHEMA['snapshot_words'])*4
    for _ in range(3):
        a=device.io.read(BASE,4);blob=device.io.read(BASE,n);b=device.io.read(BASE,4)
        if a==b==blob[:4] and not struct.unpack('<I',a)[0]&1:return decode(blob)
    raise ValueError('算法快照更新中，请重读')

def validate(changes):
    checked={}
    for name,value in changes.items():
        if name not in BY_NAME:raise ValueError('未知算法参数：'+name)
        p=BY_NAME[name]
        if name in ('cfg_config_version','cfg_scene_epoch'):continue
        if type(value) is not int:raise ValueError(name+' 需要整数')
        lo=-(1<<(p['width']-1)) if p.get('signed') else 0
        hi=(1<<(p['width']-1))-1 if p.get('signed') else (1<<p['width'])-1
        if not lo<=value<=hi:raise ValueError(name+' 超出位宽范围')
        checked[name]=value
    return checked

def apply(device,changes):
    checked=validate(changes)
    device.command(10);before=read(device)
    target={**before['configuration'],**checked}
    # The BIST source latches its profile during the source-switch reset window.
    # Re-enter Test automatically so static/dynamic changes and Replay are one action.
    if before['results']['active_source'] and effective_configuration(target)['cfg_test_async']:
        for name,value in {'sys_dip_override':0,'cfg_test_async':0}.items():
            device.command(8,args=[BY_NAME[name]['index'],value,0,0,0])
        device.command(9)
        until=time.monotonic()+8
        while True:
            device.command(10);state=read(device)
            if not state['results']['active_source'] and not state['results']['switch_busy']:break
            if time.monotonic()>=until:raise TimeoutError('等待自测源重新启动超时')
            time.sleep(.02)
        checked={**{n:target[n] for n in ('sys_dip_override','cfg_test_async')},**checked}
    for name,value in checked.items():device.command(8,args=[BY_NAME[name]['index'],value&0xffffffff,0,0,0])
    device.command(9);device.command(10)
    result=read(device)
    for name,value in checked.items():
        if result['configuration'][name]!=value:raise ValueError('参数读回不一致：'+name)
    return result

def event(device,sequence):
    h=device.command(11,args=[sequence,0,0,0,0]);words=h[100:112]
    if words[0]!=sequence:raise ValueError('事件缓存已更新，请读取最新序号')
    return dict(sequence=words[0],track_id=words[1],frame_id=words[2],source='test' if words[3]&0x80000000 else 'camera',
        context=f'{sum(words[4+i]<<(32*i) for i in range(4)):032x}',camera_total=words[8],test_total=words[9],
        configuration_version=words[10],session=words[11])
