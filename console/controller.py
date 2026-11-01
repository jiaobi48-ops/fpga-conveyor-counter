from pathlib import Path
from collections import deque
from datetime import datetime
import json,time,threading,queue,subprocess,urllib.request,urllib.parse,hashlib,os
from protocol import StudioDevice,configuration,valid_roi
from transport import DDRTransport
from serial_win import SerialPort,ports
ROOT=Path(__file__).resolve().parent
PYTHON=Path('C:/Users/asus/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
def stamp():return datetime.now().strftime('%Y%m%d_%H%M%S')
class Controller:
 def __init__(self,root=ROOT,serial_factory=SerialPort,transport_factory=DDRTransport):
  self.root=Path(root);self.root.mkdir(exist_ok=True);self.lock=threading.RLock();self.io=threading.RLock();self.closed=threading.Event();self.events=queue.Queue();self.jobs=queue.Queue()
  self.serial=serial_factory();self.transport_factory=transport_factory;self.transport=None;self.device=None;self.connected=False;self.busy=False;self.error='';self.config=None;self.header=None;self.pause_pending=threading.Event()
  self.frame=None;self.frame_time=0;self.frozen=False;self.source=None;self.logs=deque(maxlen=8000);self.rx=0;self.tx=0
  self.log_path=self.root/'logs'/('serial_'+stamp()+'.log');self.log_path.parent.mkdir(exist_ok=True);self.log_file=self.log_path.open('a',encoding='utf-8',buffering=1);self.rx_file=self.log_path.with_suffix('.bin').open('ab',buffering=0)
  threading.Thread(target=self._serial_loop,daemon=True).start();threading.Thread(target=self._worker,daemon=True).start();threading.Thread(target=self._preview_loop,daemon=True).start()
 def log(self,text,kind='info'):
  with self.lock:
   line=datetime.now().strftime('%H:%M:%S')+' '+kind.upper()+' '+text.rstrip();self.logs.append(line);self.log_file.write(line+'\n');self.events.put(('log',line))
 def progress(self,text):self.events.put(('progress',text))
 def _serial_loop(self):
  pending=b''
  while not self.closed.wait(.025):
   try:
    data=self.serial.read()
    if not data:continue
    with self.lock:self.rx+=len(data);self.rx_file.write(data)
    pending+=data
    while b'\n' in pending:
     line,pending=pending.split(b'\n',1);self.log(line.decode('utf-8',errors='replace').rstrip('\r'),'rx')
    if len(pending)>8192:self.log(pending.decode('utf-8',errors='replace'),'rx');pending=b''
   except Exception as e:
    if self.closed.is_set():break
    self.log(str(e),'error');self.serial.close();self.events.put(('error',str(e)))
 def submit(self,action,**args):
  with self.lock:
   if self.busy:raise RuntimeError('当前操作尚未完成，请稍等')
   self.busy=True
  self.jobs.put((action,args));self.events.put(('busy',action))
 def _worker(self):
  while not self.closed.is_set():
   try:action,args=self.jobs.get(timeout=.1)
   except queue.Empty:continue
   try:
    getattr(self,'do_'+action)(**args);self.error='';self.events.put(('done',action))
   except Exception as e:self.error=str(e);self.log(str(e),'error');self.events.put(('error',str(e)))
   finally:
    if self.pause_pending.is_set():
     self.pause_pending.clear()
     try:self.do_mode('blocked')
     except Exception as e:self.error=str(e);self.log(str(e),'error');self.events.put(('error','暂停尚未确认：'+str(e)))
    with self.lock:self.busy=False
 def _refresh(self):
  if not self.device or not self.connected:raise RuntimeError('请先初始化开发板并连接画面')
  h=self.device.command(3);c=configuration(h)
  with self.lock:self.header=h;self.config=c
  self.events.put(('status',self.status()));return h
 def status(self):
  with self.lock:
   h=self.header;p=list(h[80:96]) if h else None
   return dict(connected=self.connected,serial=bool(self.serial.handle),port=self.serial.name,busy=self.busy,error=self.error,config=self.config,pages=p,rx=self.rx,tx=self.tx,frozen=self.frozen,image_age=time.monotonic()-self.frame_time if self.frame_time else None)
 def _connect_jtag(self):
  if self.transport:self.transport.close()
  self.connected=False;self.device=None
  tr=self.transport_factory(self.root,self.root/'logs'/('jtag_'+stamp()+'.log'));self.transport=tr;tr.connect();self.device=StudioDevice(tr)
  deadline=time.monotonic()+25
  while time.monotonic()<deadline:
   h=self.device.header()
   if h[0]==0x43545231 and h[1]==3 and h[31]==0:time.sleep(.2);continue
   self.device.command(0);break
  else:raise RuntimeError('初始化超时，请查看串口日志中的失败原因')
  self.connected=True;self.source=None;self.frozen=False;self._refresh()
 def do_connect(self,port):
  self.progress('连接串口与画面…')
  if self.serial.name!=port or not self.serial.handle:self.serial.open(port)
  with self.io:self._connect_jtag()
  self.log('设备已连接，所有常用按钮均核对板上读回')
 def _stop_old_studio(self):
  p=self.root.parent/'camera_capture_studio_2026-10-26/studio_runtime.json'
  if not p.exists():return
  try:
   v=json.loads(p.read_text(encoding='utf-8'));u=v['url'];q=urllib.parse.urlparse(u)
   if q.hostname!='127.0.0.1' or q.scheme!='http':raise RuntimeError('旧采集界面地址异常，未操作')
   req=urllib.request.Request(u+'api/shutdown',data=b'{}',headers={'Content-Type':'application/json','X-Studio-Token':v['local_shutdown_token']},method='POST')
   urllib.request.urlopen(req,timeout=4).close();time.sleep(2)
  except urllib.error.URLError:pass
 def do_initialize(self,port):
  self.progress('连接串口，下载配套程序；本次初始化会清零…')
  if self.serial.name!=port or not self.serial.handle:self.serial.open(port)
  with self.io:
   self.connected=False
   if self.transport:self.transport.close();self.transport=None
   self._stop_old_studio()
   cmd=[os.environ.get('COMSPEC','cmd.exe'),'/d','/c','D:/vivado/2025.2/Vitis/bin/xsdb.bat',str(self.root/'run_control.tcl')]
   p=subprocess.run(cmd,cwd=self.root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=120,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
   lines=p.stdout.splitlines()
   for line in lines:self.log(line,'init')
   if p.returncode or not any('CAMERA_CONTROL_CONSOLE_STARTED' in line for line in lines):raise RuntimeError('下载未完成，请查看下方初始化日志')
   self._connect_jtag()
  self.log('初始化完成，当前为手动暂停；调框后点击“正常计数”')
 def send(self,text):
  if not text or len(text)>78 or any(ord(c)<32 or ord(c)>126 for c in text):raise ValueError('请输入一行英文命令，最多78字符')
  if text.startswith(('FOLLOW','TRACK')):raise ValueError('本程序已移除自动跟随，请直接调节检测框')
  data=(text+'\r\n').encode('ascii');self.serial.write(data)
  with self.lock:self.tx+=len(data)
  self.log(text,'tx')
 def _verified(self,text,predicate):
  changes=text in ('U','H','A') or text.startswith(('ROI ','SETTHR ','SETMASK '))
  old_epoch=self._refresh()[83] if changes else None
  self.send(text);end=time.monotonic()+8
  while time.monotonic()<end:
   h=self._refresh()
   if predicate(h) and (not changes or h[83]!=old_epoch):return h
   time.sleep(.08)
  raise RuntimeError('命令已发送，但板上读回未确认；没有自动重发，请查看串口日志')
 def _control(self,op,args,predicate,changes=True):
  before=self._refresh()[83] if changes else None
  self.log('板卡控制 op='+str(op)+' args='+str(args),'control')
  self.device.command(op,args=args)
  end=time.monotonic()+8
  while time.monotonic()<end:
   h=self._refresh()
   if predicate(h) and (not changes or h[83]!=before):return h
   time.sleep(.08)
  raise RuntimeError('板卡操作已应答，但实际状态未确认；未重复执行，请检查日志')
 def do_mode(self,mode):
  values={'clear':4,'blocked':12,'auto':0}
  if mode not in values:raise ValueError('未知模式')
  bits=values[mode]
  with self.io:self._control(4,[bits,0,0,0,0],lambda h:(h[73]&12)==bits and ((h[81]>>8)&12)==bits and (bits==0 or bool(h[81]&4096)==(bits==12)))
  self.progress('已读回：'+{'clear':'手动无遮挡','blocked':'手动暂停 / 有遮挡','auto':'自动判遮挡'}[mode])
 def pause_now(self):
  # An urgent request survives a busy action; mailbox confirmation follows it.
  self.pause_pending.set()
  try:self.send('H')
  except Exception as e:self.log('串口即时暂停未确认，当前操作结束后通过控制邮箱暂停：'+str(e),'control')
  self.events.put(('progress','已请求暂停，等待当前操作结束及板上读回确认'))
 def do_clear(self):
  with self.io:
   before=self._refresh()[84];self._control(7,[0]*5,lambda h:h[84]!=before and (h[80]&0xfffff)==0,changes=False)
  self.progress('计数已清零；等待检测区清空后就绪')
 def do_roi(self,gates):
  if not valid_roi(gates):raise ValueError('检测框参数超出允许范围，请检查红色提示')
  with self.io:
   self._control(4,[12,0,0,0,0],lambda h:h[73]&12==12 and bool(h[81]&4096))
   self._control(2,gates,lambda h:list(h[64:69])==gates)
  self.progress('检测框已生效并读回。当前保持暂停，准备好后点击“正常计数”。')
 def do_threshold(self,value):
  if type(value) is not int or not 32<=value<=224:raise ValueError('阈值范围32～224')
  with self.io:
   self._control(4,[12,0,0,0,0],lambda h:h[73]&12==12 and bool(h[81]&4096));self._control(5,[value,0,0,0,0],lambda h:h[69]==value)
  self.progress('阈值已读回；当前保持暂停')
 def do_mask(self,value):
  if type(value) is not bool:raise ValueError('显示模式不合法')
  with self.io:self._control(6,[int(value),0,0,0,0],lambda h:bool(h[73]&2)==value)
 def do_raw(self,text):
  with self.io:
   self.send(text)
   if self.connected:time.sleep(.1);self._refresh()
 def do_capture(self):
  with self.io:
   self._control(4,[12,0,0,0,0],lambda h:h[73]&12==12 and bool(h[81]&4096))
   raw,full,crop,m=self.device.capture(self.progress)
   directory=self.root/'snapshots'/(stamp()+f'_{m["capture_seq"]:06d}');directory.mkdir(parents=True,exist_ok=False)
   for name,data in [('original_1280x720.png',full),('algorithm_800x480.png',crop),('original.bgr',raw)]: (directory/name).write_bytes(data)
   (directory/'metadata.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
   with self.lock:self.frame=crop;self.frame_time=time.monotonic();self.frozen=True
   self.events.put(('frame',dict(data=crop,kind='color',source=m['capture_seq'],frozen=True)));self._refresh()
  self.progress('高清图已冻结，可精细拖框；照片保存在 '+str(directory))
 def live(self):
  with self.lock:self.frozen=False
  self.events.put(('progress','恢复实时灰度预览，按新源帧更新'))
 def _preview_loop(self):
  last_status=0
  while not self.closed.wait(.2):
   if not self.connected or self.busy or not self.io.acquire(blocking=False):continue
   try:
    if time.monotonic()-last_status>1:self._refresh();last_status=time.monotonic()
    data,m=self.device.gray();sid=m['stream_frame_id']
    if self.source is not None:
     delta=(sid-self.source)&0xffffff
     if not delta:continue
     if delta>=0x800000:raise RuntimeError('相机帧身份已重启，请重新连接设备')
    self.source=sid
    with self.lock:
     if self.frozen:continue
     self.frame=data;self.frame_time=time.monotonic()
    self.events.put(('frame',dict(data=data,kind='gray',source=sid,frozen=False)))
   except ValueError:pass # publication overlap, never renew the old image's age
   except Exception as e:self.connected=False;self.error=str(e);self.events.put(('error',str(e)))
   finally:self.io.release()
 def save_profile(self,path,gates):
  if not self.config:raise RuntimeError('尚无板上配置，请先连接')
  if not valid_roi(gates):raise ValueError('参数不合法')
  v=dict(schema='fixed-camera-console-v1',roi=gates,threshold=self.config['threshold'],mask=bool(self.config['flags']&2),algorithm='A manual two-gate counting / C30401',calibrated=False)
  Path(path).write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
 def do_profile(self,path):
  v=json.loads(Path(path).read_text(encoding='utf-8-sig'))
  if v.get('schema')!='fixed-camera-console-v1' or not valid_roi(v.get('roi',[])) or type(v.get('threshold')) is not int or not 32<=v['threshold']<=224 or type(v.get('mask')) is not bool:raise ValueError('不是本程序保存的有效场景文件')
  self.do_roi(v['roi']);self.do_threshold(v['threshold']);self.do_mask(v['mask']);self.progress('场景已恢复并读回，保持暂停；不会自动开始计数')
 def close(self):
  self.closed.set();self.serial.close()
  with self.io:
   if self.transport:self.transport.close()
  with self.lock:self.log_file.close();self.rx_file.close()
