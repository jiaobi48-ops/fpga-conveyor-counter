from pathlib import Path
import sys,tempfile,threading,json,time,hashlib
R=Path(__file__).resolve().parent;sys.path[:0]=[str(R),str(R/'validation')]
from controller import Controller
from mock_board import FakeTransport
tr=FakeTransport()
class Serial:
 def __init__(self):self.handle=None;self.name='';self.sent=[]
 def open(self,n):self.name=n;self.handle=1
 def close(self):self.handle=None;self.name=''
 def read(self):return b''
 def write(self,data):
  assert self.handle;self.sent.append(data);s=data.decode().strip();h=tr.h
  if s in ['H','U','A']:h[73]=(h[73]&~12)|{'H':12,'U':4,'A':0}[s]
  elif s.startswith('ROI '):h[64:69]=list(map(int,s.split()[1:]))
  elif s.startswith('SETTHR '):h[69]=int(s.split()[1])
  elif s.startswith('SETMASK '):h[73]=(h[73]&~2)|(int(s.split()[1])<<1)
  elif s=='R':h[84]+=1;h[80]=0;return
  else:return
  h[83]+=1;bits=h[73]&12;h[81]=13|((bits&4)<<8)|((bits&8)<<8)|(4096 if bits==12 else 0)
o=R/'validation/controller_tests';o.mkdir(exist_ok=True);folder=Path(tempfile.mkdtemp(prefix='MOCK_ONLY_',dir=o));(folder/'snapshots').mkdir();(folder/'logs').mkdir()
c=Controller(folder,serial_factory=Serial,transport_factory=lambda *args:tr)
try:
 c.do_connect('TEST');assert c.connected and c.config['flags']==13
 c.do_mode('clear');assert c.config['flags']&12==4
 c.do_roi([500,460,8,180,212]);assert c.config['roi']==[500,460,8,180,212] and c.config['flags']&12==12
 assert not c.serial.sent,'Common controls must work even without UART transmit'
 c.do_threshold(160);assert c.config['threshold']==160;c.do_mask(True);assert c.config['flags']&2
 tr.h[80]=23;c.do_clear();assert c.header[80]==0
 p=folder/'scene.json';c.save_profile(p,c.config['roi']);c.do_profile(p);assert c.config['flags']&12==12
 before=len(c.serial.sent)
 try:c.do_roi([500,520,8,180,212]);raise AssertionError('invalid accepted')
 except ValueError:pass
 try:c.send('FOLLOW 1');raise AssertionError('follow accepted')
 except ValueError:pass
 assert len(c.serial.sent)==before
 c.do_capture();assert c.frozen and len(list((folder/'snapshots').rglob('original_1280x720.png')))==1
 c.live();assert not c.frozen
 # Busy-operation pause must persist even if the serial transmit path fails.
 saved_write=c.serial.write
 def broken_write(data):raise RuntimeError('mock unavailable UART TX')
 c.serial.write=broken_write;c.pause_now();assert c.pause_pending.is_set()
 c.submit('mode',mode='clear')
 deadline=time.monotonic()+3
 while c.busy and time.monotonic()<deadline:time.sleep(.02)
 assert not c.busy and c.config['flags']&12==12 and not c.pause_pending.is_set()
 c.serial.write=saved_write
 # Requested config alone is insufficient: an unchanged hardware epoch must fail.
 old=c._refresh;calls=[];c._refresh=lambda:tr.h.copy();c.send=lambda s:calls.append(s)
 clock=time.monotonic
 import controller
 real=controller.time.monotonic;tick=[0]
 def fake_time():tick[0]+=9;return tick[0]
 controller.time.monotonic=fake_time
 try:
  try:c._verified('ROI 500 460 8 180 212',lambda h:True);raise AssertionError('stale epoch accepted')
  except RuntimeError:pass
  saved_command=c.device.command;mail_calls=[]
  c.device.command=lambda *a,**kw:mail_calls.append((a,kw))
  try:
   try:c._control(4,[12,0,0,0,0],lambda h:True);raise AssertionError('stale mailbox epoch accepted')
   except RuntimeError:pass
   assert len(mail_calls)==1
  finally:c.device.command=saved_command
 finally:controller.time.monotonic=real;c._refresh=old
 assert len(calls)==1
 # A renamed desktop program must not silently accept old board firmware.
 tr.h[1]=2
 try:
  try:c.device.header();c.device.command(0);raise AssertionError('old firmware accepted')
  except ValueError as e:assert '初始化开发板' in str(e)
 finally:tr.h[1]=3
finally:c.close()
(R/'validation/controller_receipt.json').write_text(json.dumps(dict(status='PASS mock UART/JTAG backend; no board claim',checks=['mode readback','ROI pauses and retains total','threshold/mask absolute readback','session-confirmed clear','profile restores paused','invalid/follow commands rejected before TX','full immutable capture','stale hardware epoch cannot confirm request','no auto retry'],sources={n:hashlib.sha256((R/n).read_bytes()).hexdigest() for n in ['controller.py','protocol.py','serial_win.py']}),indent=2))
print('PASS unified controller: actual readback, pending vs active config, pause, profiles, stale epoch rejection; mocks only')
