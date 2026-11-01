from io import BytesIO
import hashlib,struct,time,secrets
import numpy as np
from PIL import Image
BASE=0x03000000;PIXELS=0x02400000;GRAY=0x02000000
MAGIC=0x43545231;SEAL=0x93E57A21;N=1280*720*3;ERROR_MASK=0xCFF0
ACK=32;STATE=33;ERR=34;SEQ=35;CFG=64;PAGES=80
def fnv(data):
 v=2166136261
 for b in data:v=((v^b)*16777619)&0xffffffff
 return v
def png(image):
 f=BytesIO();image.save(f,format='PNG');return f.getvalue()
def valid_roi(g):
 return len(g)==5 and all(type(v) is int for v in g) and 2<=g[0]<=798 and 2<=g[1]<=798 and 1<=g[2]<=32 and g[0]+g[2]<=798 and g[1]+g[2]<g[0] and 54<=g[3]<=478 and g[3]+8<=g[4]<=478 and g[4]-g[3]<=128
def validate_header(h):
 if h[0]!=MAGIC or h[1]!=3:raise ValueError('板上仍是旧固件：请停带后点击“初始化开发板”下载v1.2；仅连接设备不会升级，初始化会清零')
 if h[31]!=1:raise ValueError('采集固件未就绪或已停止，请检查串口初始化日志')
def configuration(h):
 c=list(h[CFG:CFG+10]);p=list(h[PAGES:PAGES+16])
 if not valid_roi(c[:5]) or not 32<=c[5]<=224 or p[14]!=0xC30401 or p[15]&3:raise ValueError('配置或固件不匹配，或仍启用了自动跟随')
 return dict(roi=c[:5],threshold=c[5],on=c[6],off=c[7],warm_limit=c[8],flags=c[9],epoch=p[3],session=p[4],counting_enabled=bool(c[9]&1),snapshot_pages=p,snapshot_scope='Nearest LCD boundary before freeze; not an identity tag of selected DDR pixels')
def exact_v3_rules(image,c):
 a=np.asarray(image.crop((240,120,1040,600))).astype(np.uint16);r,g,b=a[:,:,0],a[:,:,1],a[:,:,2]
 lum=(r+2*g+b)//4;warm=(r>80)&(r>g+12)&(r>b+16)
 cup=(lum<c['threshold'])&(r<=g+12)&(r<=b+16)
 ax,bx,w,y0,y1=c['roi'];ap=int(cup[y0:y1,ax:ax+w].sum());bp=int(cup[y0:y1,bx:bx+w].sum())
 aw=int(warm[y0:y1,ax:ax+w].sum());bw=int(warm[y0:y1,bx:bx+w].sum())
 uw=int(warm[8:48,320:480].sum());ud=int((lum[8:48,320:480]<c['threshold']).sum())
 wv=aw>=c['warm_limit'] or bw>=c['warm_limit'];uv=uw>=640 or ud>=3200
 return dict(model='Actual A V3 pixel rules, recomputed on this exact exported crop',a_pixels=ap,b_pixels=bp,a_warm=aw,b_warm=bw,upper_warm=uw,upper_dark=ud,warm_veto=wv,upper_veto=uv,raw_pixel_veto=wv or uv,counting_enabled=c['counting_enabled'],interpretation='Raw pixel rules on this exported image; manual mode can override raw veto; not a production same-frame event; B v0.13 is not active')
def decode_full(h,one,two):
 validate_header(h);c=configuration(h)
 if h[36:40]!=(1280,720,3840,N) or h[50]!=PIXELS or h[SEQ]<1:raise ValueError('原始帧格式不匹配')
 if h[41]>=3 or h[42]!=0x01000000+h[41]*0x00400000 or h[41] in (h[43],h[44]) or h[43]>=3 or h[44]>=3:raise ValueError('停止后缓冲所有权校验失败')
 if any((h[i]&ERROR_MASK) or not(h[i]&1) for i in (45,46)) or h[47]!=0x20:raise ValueError('冻结DMA状态或相机极性异常')
 if len(one)!=N+128 or one!=two or one[:64]!=b'\x5a'*64 or one[-64:]!=b'\x5a'*64:raise ValueError('两次完整DDR读不一致或保护区异常')
 raw=one[64:-64]
 if np.any(np.frombuffer(raw,dtype=np.uint8)&3) or fnv(raw)!=h[40]:raise ValueError('原始帧量化/校验失败')
 image=Image.frombytes('RGB',(1280,720),raw,'raw','BGR');crop=image.crop((240,120,1040,600))
 meta=dict(capture_seq=h[SEQ],actual_source_frame_id=None,observed_stream_counter_at_freeze=h[96],observed_stream_counter_scope='Diagnostic only, not bound to the selected DDR buffer',source_buffer=hex(h[42]),selected_buffer=h[41],park_before=h[43],park_after=h[44],frozen_s2mm=hex(h[45]),frozen_mm2s=hex(h[46]),resume_s2mm=hex(h[97]),resume_mm2s=hex(h[98]),freeze_device_ms=h[48],capture_and_restart_ms=h[49],source_dimensions=[1280,720],algorithm_crop=dict(x=240,y=120,width=800,height=480),byte_order='BGR decoded to RGB PNG',raw_fnv=f'{h[40]:08X}',raw_sha256=hashlib.sha256(raw).hexdigest(),double_complete_read_identical=True,guards='PASS',configuration=c,image_rules=exact_v3_rules(image,c),calibrated=False)
 return raw,png(image),png(crop),meta
def decode_gray(header,blob,header2):
 if len(header)!=64 or header!=header2 or len(blob)!=14400:raise ValueError('预览发布期间发生更新，请重读')
 h=struct.unpack('<16I',header)
 if h[0]!=0x464f4c31 or h[2:5]!=(160,90,14400) or h[6]!=0xC30401 or h[10]!=MAGIC or fnv(blob)!=h[5]:raise ValueError('实时预览未就绪或校验失败')
 im=Image.frombytes('L',(160,90),blob).crop((30,15,130,75)).resize((800,480),Image.Resampling.NEAREST)
 return png(im),dict(stream_frame_id=h[1],device_publish_ms=h[8],source_dimensions=[160,90],display_dimensions=[800,480],kind='live_gray',pixel_resolution_note='8 source pixels per thumbnail cell; use full-color freeze for precise 4-pixel gates')
class StudioDevice:
 def __init__(self,transport):self.io=transport;self.token=secrets.randbelow(0xfffffffe)+1
 def header(self):return struct.unpack('<128I',self.io.read(BASE,512))
 def command(self,op,args=None,expected=None,timeout=25):
  h=self.header();validate_header(h)
  self.token=(self.token+1)&0xffffffff or 1;t=self.token;g=args or [0]*5
  if len(g)!=5:raise ValueError('argument count')
  if op==2 and not valid_roi(g):raise ValueError('ROI不合法')
  if op not in range(8):raise ValueError('未知板卡操作')
  if op>=4 and (any(g[1:]) or (op==4 and g[0] not in (0,4,12)) or (op==5 and not 32<=g[0]<=224) or (op==6 and g[0] not in (0,1)) or (op==7 and g[0]!=0)):raise ValueError('控制参数不合法')
  values=[op,h[SEQ] if expected is None else expected,*g];seal=SEAL^t
  for v in values:seal^=v
  self.io.write(BASE+12,[*values,seal]);self.io.write(BASE+8,[t])
  until=time.monotonic()+timeout
  while time.monotonic()<until:
   h=self.header()
   if h[ACK]==t:
    if h[STATE]!=2:raise ValueError(f'板卡拒绝/停止：错误码 {h[ERR]}，请查看串口日志')
    configuration(h);return h
   time.sleep(.025)
  raise TimeoutError('采集台固件未响应；可能未运行当前采集程序，请检查串口与JTAG')
 def capture(self,progress=lambda text:None):
  progress('等待板卡冻结完整帧并恢复视频…');h=self.command(1)
  progress('读取原始DDR：第1遍…');a=self.io.read(PIXELS-64,N+128)
  progress('读取原始DDR：第2遍稳定性核对…');b=self.io.read(PIXELS-64,N+128)
  end=self.header()
  if h!=end:raise ValueError('原始帧在导出期间被另一个请求替换，未保存')
  progress('核对校验值、生成原始PNG和对应规则日志…')
  return decode_full(h,a,b)
 def gray(self):
  a=self.io.read(GRAY,64);b=self.io.read(GRAY+64,14400);c=self.io.read(GRAY,64)
  return decode_gray(a,b,c)
