from pathlib import Path
import sys,queue,time,json,hashlib
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R))
import tkinter as tk
from PIL import Image
from app import App
class Fake:
 def __init__(self):
  self.events=queue.Queue();self.busy=False;self.connected=False;self.config=None;self.pages=None;self.sent=[];self.frozen=False;self.age=None;self.log_path=R/'validation/FAKE_ONLY.log'
 def status(self):return dict(connected=self.connected,serial=self.connected,port='TEST_ONLY',busy=self.busy,error='',config=self.config,pages=self.pages,rx=0,tx=0,frozen=self.frozen,image_age=self.age)
 def submit(self,name,**args):self.sent.append((name,args))
 def live(self):self.frozen=False
 def pause_now(self):self.sent.append(('urgent_pause',{}))
 def close(self):pass
root=tk.Tk();root.withdraw();f=Fake();a=App(root,f);root.update_idletasks();a.update_status()
assert root.title()=='控制台'
assert a.count.get()=='—' and '未连接' in a.run_state.get()
f.connected=True;f.config=dict(roi=[416,376,4,96,128],threshold=144,epoch=1,flags=5);f.pages=[0]*16;f.pages[0]=1<<20;f.pages[1]=13|1024;a.update_status();assert '运行中' in a.run_state.get()
a.vars[0].set('500');a.update_status();assert a.vars[0].get()=='500' and a.dirty
a.apply_roi();assert f.sent[-1][0]=='roi' and f.sent[-1][1]['gates'][0]==500
a.vars[0].set('1');before=len(f.sent);a.apply_roi();assert len(f.sent)==before
a.set_fields([416,376,4,96,128]);a.image=Image.new('RGB',(800,480));a.image_kind='color';f.age=.1;f.frozen=True
a.point=lambda e:(500,200);a.down(None);a.point=lambda e:(520,210);a.move(None);assert a.gates()==[436,396,4,106,138]
a.drag=None;f.frozen=False;f.age=4;a.down(None);assert a.drag is None and '过期' in a.progress.get()
f.frozen=True;f.age=130;a.down(None);assert a.drag is None
a.notebook.select(a.main_page);a.toggle_log();assert a.notebook.select()==str(a.extra);a.toggle_log();assert a.notebook.select()==str(a.main_page)
f.pages[1]=13|1024|2048|4096;a.update_status();assert '手动暂停' in a.run_state.get()
f.busy=True;a.update_status();assert str(a.pause_btn['state'])=='normal';a.pause();assert f.sent[-1][0]=='urgent_pause'
root.destroy()
(R/'validation/ui_receipt.json').write_text(json.dumps(dict(status='PASS actual Tk widgets/callbacks with a fake controller; no board interaction',source_sha256=hashlib.sha256((R/'app.py').read_bytes()).hexdigest(),checks=['disconnected count unavailable','actual status wording','draft retained across polls','invalid input not transmitted','letterbox drag mapping','stale and old frozen images reject drag','advanced page fits separate tab','urgent pause remains available when busy']),indent=2))
print('PASS native Tk UI state, input validation, drag mapping, tabs and urgent-pause callbacks; fake data only in hidden test window')
