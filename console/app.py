"""Native fixed-camera operator console: camera/ROI, count controls and UART in one window."""
from pathlib import Path
from io import BytesIO
import sys,time,queue,json,threading,shutil,traceback
sys.path.insert(0,str(Path(__file__).resolve().parent))
import tkinter as tk
from tkinter import ttk,messagebox,filedialog
from PIL import Image,ImageTk
from controller import Controller,ROOT,ports
from protocol import valid_roi
class App:
 def __init__(self,root,controller=None):
  self.root=root;self.ctrl=controller or Controller();self.image=None;self.photo=None;self.image_kind=None;self.image_source=None;self.drag=None;self.dirty=False;self.suppress=False;self.last_cfg=None;self.buttons=[];self.last_busy=False;self.closing=False
  root.title('控制台');root.geometry(f'1240x{min(850,root.winfo_screenheight()-70)}');root.minsize(1000,680);root.configure(bg='#eef2f7')
  root.option_add('*Font',('Microsoft YaHei UI',10));style=ttk.Style();style.theme_use('clam');style.configure('TFrame',background='#eef2f7');style.configure('TLabel',background='#eef2f7',foreground='#1b314c');style.configure('TButton',padding=7);style.configure('TNotebook',background='#eef2f7')
  root.columnconfigure(0,weight=1);root.rowconfigure(1,weight=1)
  top=ttk.Frame(root,padding=(16,12));top.grid(row=0,column=0,sticky='ew');top.columnconfigure(8,weight=1)
  ttk.Label(top,text='控制台',font=('Microsoft YaHei UI',17,'bold')).grid(row=0,column=0,columnspan=4,sticky='w',pady=(0,9))
  ttk.Label(top,text='动态降噪 · 三阈值并行 · 轨迹恢复 · v1.4',foreground='#5b6f86').grid(row=0,column=4,columnspan=5,sticky='e')
  ttk.Label(top,text='串口').grid(row=1,column=0,sticky='w');self.port=tk.StringVar();self.port_box=ttk.Combobox(top,textvariable=self.port,state='readonly',width=9);self.port_box.grid(row=1,column=1,padx=5)
  ttk.Button(top,text='刷新',command=self.refresh_ports).grid(row=1,column=2,padx=3)
  self.connect_btn=ttk.Button(top,text='连接设备',command=lambda:self.action('connect',port=self.port.get()));self.connect_btn.grid(row=1,column=3,padx=3)
  self.init_btn=ttk.Button(top,text='初始化开发板…',command=self.initialize);self.init_btn.grid(row=1,column=4,padx=8)
  self.connection=tk.StringVar(value='未连接 · 115200 / 8N1');ttk.Label(top,textvariable=self.connection).grid(row=1,column=5,columnspan=4,sticky='e')
  self.notebook=ttk.Notebook(root);self.notebook.grid(row=1,column=0,sticky='nsew')
  body=ttk.Frame(self.notebook,padding=(16,0));self.main_page=body;self.notebook.add(body,text='计数与调框');body.columnconfigure(0,weight=1);body.columnconfigure(1,minsize=290);body.rowconfigure(0,weight=1)
  left=ttk.Frame(body);left.grid(row=0,column=0,sticky='nsew',padx=(0,14));left.columnconfigure(0,weight=1);left.rowconfigure(0,weight=1)
  self.canvas=tk.Canvas(left,bg='#15253a',highlightthickness=0);self.canvas.grid(row=0,column=0,sticky='nsew');self.canvas.bind('<Configure>',lambda e:self.draw());self.canvas.bind('<ButtonPress-1>',self.down);self.canvas.bind('<B1-Motion>',self.move);self.canvas.bind('<ButtonRelease-1>',lambda e:setattr(self,'drag',None))
  tools=ttk.Frame(left);tools.grid(row=1,column=0,sticky='ew',pady=(8,3))
  self.button(tools,'取高清图调框（暂停）',lambda:self.action('capture')).pack(side='left',padx=(0,8));self.button(tools,'恢复实时预览',self.ctrl.live).pack(side='left')
  self.image_label=tk.StringVar(value='等待相机画面');ttk.Label(left,textvariable=self.image_label).grid(row=2,column=0,sticky='w',pady=3)
  ttk.Label(left,text='拖黄色A、青色B可移动框；拖上下边界改高度，拖空白处共同平移。精细调框先取高清图。',wraplength=780,foreground='#5b6f86').grid(row=3,column=0,sticky='w')
  right=ttk.Frame(body);right.grid(row=0,column=1,sticky='nsew');right.columnconfigure(0,weight=1)
  self.count=tk.StringVar(value='—');ttk.Label(right,text='累计数量').grid(row=0,column=0,sticky='w');ttk.Label(right,textvariable=self.count,font=('Microsoft YaHei UI',40,'bold')).grid(row=1,column=0,sticky='w')
  self.run_state=tk.StringVar(value='等待连接');ttk.Label(right,textvariable=self.run_state,font=('Microsoft YaHei UI',12,'bold'),wraplength=290).grid(row=2,column=0,sticky='w',pady=(0,8))
  self.button(right,'正常计数 · 手动无遮挡',lambda:self.action('mode',mode='clear'),bg='#16764b').grid(row=3,column=0,sticky='ew',pady=3)
  self.pause_btn=self.button(right,'暂停计数 · 有遮挡',self.pause,bg='#b33c35');self.pause_btn.grid(row=4,column=0,sticky='ew',pady=3)
  line=ttk.Frame(right);line.grid(row=5,column=0,sticky='ew',pady=3)
  self.button(line,'自动判遮挡',lambda:self.action('mode',mode='auto')).pack(side='left',fill='x',expand=True,padx=(0,5));self.button(line,'计数清零…',self.clear).pack(side='left',fill='x',expand=True)
  ttk.Separator(right).grid(row=6,column=0,sticky='ew',pady=10)
  ttk.Label(right,text='检测框位置',font=('Microsoft YaHei UI',12,'bold')).grid(row=7,column=0,sticky='w')
  fields=ttk.Frame(right);fields.grid(row=8,column=0,sticky='ew');fields.columnconfigure(1,weight=1)
  self.vars=[tk.StringVar(value=str(v)) for v in [410,220,4,2,478]]
  for i,(label,var) in enumerate(zip(['A位置（右框）','B位置（左框）','辅助框宽','上边界','下边界'],self.vars)):
   ttk.Label(fields,text=label).grid(row=i,column=0,sticky='w',pady=2);ttk.Spinbox(fields,from_=0,to=800,textvariable=var,width=9).grid(row=i,column=1,sticky='e',pady=2);var.trace_add('write',self.edit)
  self.validation=tk.StringVar(value='');ttk.Label(right,textvariable=self.validation,wraplength=290,foreground='#a3382d').grid(row=9,column=0,sticky='w',pady=3)
  self.button(right,'应用检测框（保持暂停）',self.apply_roi,bg='#1764ba').grid(row=10,column=0,sticky='ew',pady=5)
  self.applied=tk.StringVar(value='等待设备配置');ttk.Label(right,textvariable=self.applied,wraplength=290,foreground='#526a84').grid(row=11,column=0,sticky='w')
  presets=ttk.Frame(right);presets.grid(row=12,column=0,sticky='ew',pady=8)
  self.button(presets,'保存已生效场景',self.save_profile).pack(side='left',padx=(0,5));self.button(presets,'载入场景…',self.load_profile).pack(side='left')
  footer=ttk.Frame(root,padding=(16,8));footer.grid(row=2,column=0,sticky='ew');footer.columnconfigure(0,weight=1)
  self.progress=tk.StringVar(value='先选择串口连接；首次使用或当前为旧程序时，点“初始化开发板”。');ttk.Label(footer,textvariable=self.progress,wraplength=960).grid(row=0,column=0,sticky='w')
  ttk.Button(footer,text='串口日志 / 高级设置',command=self.toggle_log).grid(row=0,column=1,sticky='e')
  self.extra=ttk.Frame(self.notebook,padding=(16,0,16,12));self.notebook.add(self.extra,text='串口日志 / 高级');self.extra.columnconfigure(0,weight=1);self.extra.rowconfigure(1,weight=1);self.log_shown=False
  adv=ttk.Frame(self.extra);adv.grid(row=0,column=0,sticky='ew',pady=4)
  ttk.Label(adv,text='识别阈值').pack(side='left');self.threshold=tk.StringVar(value='144');ttk.Spinbox(adv,from_=32,to=224,textvariable=self.threshold,width=6).pack(side='left',padx=4);self.button(adv,'应用固定阈值（暂停）',self.apply_threshold).pack(side='left',padx=4)
  self.mask=tk.BooleanVar();self.mask_btn=ttk.Checkbutton(adv,text='LCD显示阈值掩膜',variable=self.mask,command=lambda:self.action('mask',value=self.mask.get()));self.mask_btn.pack(side='left',padx=8)
  self.button(adv,'读取状态',lambda:self.action('raw',text='P')).pack(side='left');ttk.Button(adv,text='保存日志…',command=self.save_log).pack(side='right');ttk.Button(adv,text='清空显示',command=lambda:self.logbox.delete('1.0','end')).pack(side='right',padx=5)
  self.logbox=tk.Text(self.extra,height=7,font=('Consolas',9),bg='#132237',fg='#e2eaf4',wrap='none');self.logbox.grid(row=1,column=0,sticky='nsew')
  sendrow=ttk.Frame(self.extra);sendrow.grid(row=2,column=0,sticky='ew',pady=5);sendrow.columnconfigure(1,weight=1);ttk.Label(sendrow,text='英文命令').grid(row=0,column=0)
  self.command=tk.StringVar();entry=ttk.Entry(sendrow,textvariable=self.command);entry.grid(row=0,column=1,sticky='ew',padx=6);entry.bind('<Return>',lambda e:self.send_raw());ttk.Button(sendrow,text='发送（自动换行）',command=self.send_raw).grid(row=0,column=2)
  self.traffic=tk.StringVar(value='接收0字节 / 发送0字节');ttk.Label(sendrow,textvariable=self.traffic).grid(row=0,column=3,padx=8)
  from algorithm_panel import AlgorithmPanel
  self.algorithm_panel=AlgorithmPanel(self)
  self.refresh_ports();self.draw();root.after(100,self.poll);root.protocol('WM_DELETE_WINDOW',self.close)
 def button(self,parent,text,command,bg=None):
  b=tk.Button(parent,text=text,command=command,bg=bg or '#e2e9f2',fg='white' if bg else '#183657',relief='flat',padx=9,pady=7,cursor='hand2',disabledforeground='#8b98a7');self.buttons.append(b);return b
 def refresh_ports(self):
  values=ports();self.port_box['values']=values
  if self.port.get() not in values:self.port.set('COM8' if 'COM8' in values else '')
 def action(self,name,**args):
  try:self.ctrl.submit(name,**args)
  except Exception as e:self.progress.set(str(e))
 def initialize(self):
  if not self.port.get():self.progress.set('未发现串口，请检查USB串口连接并刷新');return
  if messagebox.askyesno('初始化开发板','将下载本程序配套固件并清零计数。\n请先停下传送带。初始化后保持手动暂停。',parent=self.root):self.action('initialize',port=self.port.get())
 def pause(self):
  try:
   if self.ctrl.busy:self.ctrl.pause_now()
   else:self.action('mode',mode='blocked')
  except Exception as e:self.progress.set(str(e))
 def clear(self):
  if messagebox.askyesno('计数清零','将累计数量清为0，检测框和模式保持不变。\n请在检测区没有杯子时操作。',parent=self.root):self.action('clear')
 def gates(self):
  try:return [int(v.get()) for v in self.vars]
  except ValueError:return []
 def edit(self,*args):
  if self.suppress:return
  self.dirty=True;self.draw()
 def set_fields(self,g):
  self.suppress=True
  for v,n in zip(self.vars,g):v.set(str(n))
  self.suppress=False;self.draw()
 def apply_roi(self):
  g=self.gates()
  if not valid_roi(g):self.progress.set('框参数不合法：A在B右侧，宽1～32，高至少8，上边界至少2');return
  self.action('roi',gates=g)
 def apply_threshold(self):
  try:n=int(self.threshold.get())
  except ValueError:self.progress.set('阈值需要是32～224之间的整数');return
  self.action('threshold',value=n)
 def send_raw(self):
  text=self.command.get().strip()
  if text:self.action('raw',text=text)
 def toggle_log(self):
  self.notebook.select(self.main_page if self.notebook.select()==str(self.extra) else self.extra)
 def save_log(self):
  name=filedialog.asksaveasfilename(parent=self.root,title='保存串口与操作日志',defaultextension='.log',initialfile=self.ctrl.log_path.name,filetypes=[('日志文件','*.log')])
  if name:
   try:shutil.copyfile(self.ctrl.log_path,name);self.progress.set('日志已保存：'+name)
   except Exception as e:messagebox.showerror('保存失败',str(e),parent=self.root)
 def save_profile(self):
  if not self.ctrl.config:self.progress.set('请先连接设备');return
  name=filedialog.asksaveasfilename(parent=self.root,title='保存已生效场景',initialdir=ROOT/'profiles',initialfile='我的传送带.json',defaultextension='.json',filetypes=[('场景文件','*.json')])
  if name:
   try:self.ctrl.save_profile(name,self.ctrl.config['roi']);self.progress.set('已保存板上生效配置：'+name)
   except Exception as e:messagebox.showerror('保存失败',str(e),parent=self.root)
 def load_profile(self):
  name=filedialog.askopenfilename(parent=self.root,title='载入场景（恢复后保持暂停）',initialdir=ROOT/'profiles',filetypes=[('本程序场景','*.json')])
  if name:self.action('profile',path=name)
 def geometry(self):
  w=max(1,self.canvas.winfo_width());h=max(1,self.canvas.winfo_height());scale=min(w/800,h/480);return scale,(w-800*scale)/2,(h-480*scale)/2
 def draw(self):
  self.canvas.delete('all');s,ox,oy=self.geometry()
  if self.image:
   size=(max(1,round(800*s)),max(1,round(480*s)));self.photo=ImageTk.PhotoImage(self.image.resize(size,Image.Resampling.NEAREST if self.image_kind=='gray' else Image.Resampling.BILINEAR));self.canvas.create_image(ox,oy,anchor='nw',image=self.photo)
  else:self.canvas.create_text(max(1,self.canvas.winfo_width())/2,max(1,self.canvas.winfo_height())/2,text='等待相机画面\n请选择串口并连接设备',fill='#b3c3d7',font=('Microsoft YaHei UI',14),justify='center')
  g=self.gates();ok=valid_roi(g);self.validation.set(('待应用：点击下方按钮生效' if self.dirty else '') if ok else '位置不合法：A在右，框宽1～32，高度≥8，上边界≥2')
  if len(g)==5:
   a,b,w,y0,y1=g
   for x,color,label in [(a,'#ffe33d','A'),(b,'#00dce9','B')]:
    c=color if ok else '#ff524b';self.canvas.create_rectangle(ox+x*s,oy+y0*s,ox+(x+w)*s,oy+y1*s,outline=c,width=2);self.canvas.create_text(ox+(x+w/2)*s,oy+y0*s-10,text=label,fill=c)
 def point(self,e):
  s,ox,oy=self.geometry();return round((e.x-ox)/s),round((e.y-oy)/s)
 def down(self,e):
  status=self.ctrl.status()
  if not self.image or not status['connected'] or status['busy']:return
  age=status['image_age']
  if age is None or age>(120 if status['frozen'] else 3):self.progress.set('画面已过期，请恢复实时预览或重新取高清图后调框');return
  x,y=self.point(e);g=self.gates()
  if not valid_roi(g):return
  if not(0<=x<800 and 0<=y<480):return
  near=min(abs(x-g[0]),abs(x-g[1]))<22;mode='all'
  if near and abs(y-g[3])<8:mode='top'
  elif near and abs(y-g[4])<8:mode='bottom'
  elif abs(x-g[0])<15:mode='a'
  elif abs(x-g[1])<15:mode='b'
  self.drag=(x,y,g,mode)
 def move(self,e):
  if not self.drag:return
  x,y=self.point(e);x0,y0,g,mode=self.drag;g=g.copy();dx=x-x0;dy=y-y0
  if mode=='a':g[0]+=dx
  elif mode=='b':g[1]+=dx
  elif mode=='top':g[3]+=dy
  elif mode=='bottom':g[4]+=dy
  else:g[0]+=dx;g[1]+=dx;g[3]+=dy;g[4]+=dy
  self.dirty=True;self.set_fields(g)
 def update_status(self):
  s=self.ctrl.status();c=s['config'];p=s['pages'];busy=s['busy'];ready=s['connected'] and s['serial']
  self.algorithm_panel.update(s.get('vision'))
  self.connection.set(('串口 '+s['port']+' 已连接' if s['serial'] else '串口未连接')+' · '+('画面已连接' if s['connected'] else '画面未连接'))
  for b in self.buttons:b.configure(state='normal' if ready and not busy else 'disabled')
  self.pause_btn.configure(state='normal' if s['serial'] else 'disabled');self.connect_btn.configure(state='disabled' if busy else 'normal');self.init_btn.configure(state='disabled' if busy else 'normal');self.mask_btn.configure(state='normal' if ready and not busy else 'disabled')
  self.traffic.set(f'接收{s["rx"]}字节 / 发送{s["tx"]}字节')
  if not s['connected']:self.run_state.set('等待连接')
  elif p:
   flags=p[1];phase=(p[0]>>20)&3;self.count.set(str(s['vision']['count']) if s.get('vision') else str(p[0]&0xfffff))
   mode='手动' if flags&(1<<10) else '自动'
   if not flags&1:text='计数未启用'
   elif not flags&4 or not flags&8:text='采集异常，暂停计数'
   elif flags&(1<<11) and flags&(1<<10):text='手动暂停 / 有遮挡'
   elif flags&(1<<12):text='保护暂停：'+('暖色过多' if flags&(1<<7) else '上方背景异常' if flags&(1<<8) else '等待状态确认')
   elif phase==0:text='等待检测区清空'
   elif phase==3:text='顺序异常，等待检测区清空'
   elif phase==2:text='杯子通过中'
   else:text='运行中 · '+mode+'无遮挡'
   self.run_state.set(text)
  if c:
   if not self.dirty:self.set_fields(c['roi'])
   self.applied.set('板上已生效：'+str(c['roi'])+'\n阈值 '+str(c['threshold'])+' · 配置版本 '+str(c['epoch']))
   if not self.last_cfg or self.last_cfg['epoch']!=c['epoch']:self.threshold.set(str(c['threshold']));self.mask.set(bool(c['flags']&2))
   self.last_cfg=c
  age=s['image_age']
  if self.image:
   label=('高清彩色冻结图' if s['frozen'] else '实时灰度预览')+f' · 编号 {self.image_source}'
   if age is not None:label+=f' · {age:.1f}秒前'
   if not s['connected'] or (not s['frozen'] and age is not None and age>3):label+=' · 预览已过期'
   elif s['frozen']:label+=' · 高清图已冻结，点击“恢复实时预览”更新画面'
   self.image_label.set(label)
 def poll(self):
  if self.closing:return
  for _ in range(200):
   try:kind,value=self.ctrl.events.get_nowait()
   except queue.Empty:break
   if kind=='vision':self.algorithm_panel.update(value,force=True)
   elif kind=='log':
    self.logbox.insert('end',value+'\n');self.logbox.see('end')
    if int(self.logbox.index('end-1c').split('.')[0])>4000:self.logbox.delete('1.0','1000.0')
   elif kind in ['progress','error']:self.progress.set(value)
   elif kind=='busy':self.progress.set('正在处理，请稍等…')
   elif kind=='done':
    if value in ['roi','profile']:self.dirty=False
   elif kind=='frame':self.image=Image.open(BytesIO(value['data'])).copy();self.image_kind=value['kind'];self.image_source=value['source'];self.draw()
  self.update_status();self.root.after(150,self.poll)
 def close(self):
  if self.ctrl.busy:messagebox.showinfo('操作进行中','取图或初始化完成后可关闭窗口。',parent=self.root);return
  self.closing=True;self.root.destroy();self.ctrl.close()
def main():
 root=tk.Tk();App(root);root.mainloop()
if __name__=='__main__':
 try:main()
 except Exception:
  (ROOT/'logs').mkdir(exist_ok=True);(ROOT/'logs/startup_error.txt').write_text(traceback.format_exc(),encoding='utf-8')
  try:messagebox.showerror('启动失败','请查看程序目录 logs/startup_error.txt。')
  except Exception:pass
  raise
