"""Live hardware algorithm controls, all sourced from the shared register schema."""
import tkinter as tk
from tkinter import ttk,filedialog
from pathlib import Path
import json
from vision_device import SCHEMA

LABELS={
 'cfg_auto_threshold':'动态阈值','cfg_auto_denoise':'自动动态降噪','cfg_parallel_enable':'三阈值并行融合',
 'cfg_valley_enable':'峰谷切分','cfg_merge_enable':'合并判别与轨迹恢复','cfg_speed_enable':'投影相关测速',
 'cfg_motion_enable':'动态通过计数','cfg_safety_enable':'场景保护与自动恢复','cfg_guard_enable':'遮挡区域判定',
 'cfg_invert':'暗色目标','cfg_test_async':'BRAM自测源','cfg_bist_dynamic':'动态BIST','cfg_scene_auto':'静态场景轮播',
 'cfg_threshold':'初始/固定阈值','cfg_mean_offset':'均值偏移','cfg_threshold_delta':'三阈值间隔',
 'cfg_stable_mode':'静态多帧模式 0原始/1中值/2连续','cfg_bist_profile':'动态自测场景 0～3',
 'sys_dip_override':'拨码参数字优先','sys_dip_bits':'拨码参数字 0～255','sys_manual_block':'人工暂停',
 'cfg_safety_roi_x0':'ROI左','cfg_safety_roi_x1':'ROI右','cfg_safety_roi_y0':'ROI上','cfg_safety_roi_y1':'ROI下',
 'cfg_line_a':'入口线A（右）','cfg_line_b':'出口线B（左）'}

class AlgorithmPanel:
 def __init__(self,app):
  self.app=app;self.vars={};self.last=None
  page=ttk.Frame(app.notebook,padding=12);app.notebook.add(page,text='FPGA算法 / 三路并行')
  page.columnconfigure(0,weight=1);page.rowconfigure(2,weight=1)
  self.summary=tk.StringVar(value='等待算法结果');ttk.Label(page,textvariable=self.summary,wraplength=1100,font=('Microsoft YaHei UI',11)).grid(row=0,column=0,sticky='ew',pady=8)
  buttons=ttk.Frame(page);buttons.grid(row=1,column=0,sticky='ew')
  for title,fn in [('读回全部配置',lambda:app.action('vision_refresh')),('应用全部参数',self.apply),('相机模式',lambda:self.preset(0)),('静态ROM自测',lambda:self.preset(1)),('动态BIST',lambda:self.preset(2)),('保存算法场景',self.save),('载入算法场景',self.load)]:
   app.button(buttons,title,fn).pack(side='left',padx=3,pady=3)
  canvas=tk.Canvas(page,highlightthickness=0,bg='#eef2f7');scroll=ttk.Scrollbar(page,orient='vertical',command=canvas.yview)
  canvas.configure(yscrollcommand=scroll.set);canvas.grid(row=2,column=0,sticky='nsew');scroll.grid(row=2,column=1,sticky='ns')
  fields=ttk.Frame(canvas);canvas.create_window((0,0),window=fields,anchor='nw');fields.bind('<Configure>',lambda e:canvas.configure(scrollregion=canvas.bbox('all')))
  items=[p for p in SCHEMA['config'] if p['name'] not in ('cfg_config_version','cfg_scene_epoch')]
  for n,p in enumerate(items):
   col=(n%2)*3;row=n//2;name=p['name'];var=tk.StringVar(value=str(p['default']));self.vars[name]=var
   ttk.Label(fields,text=LABELS.get(name,name),width=36).grid(row=row,column=col,sticky='w',padx=4,pady=3)
   if p['width']==1:widget=ttk.Combobox(fields,textvariable=var,values=['0','1'],state='readonly',width=10)
   else:widget=ttk.Entry(fields,textvariable=var,width=12)
   widget.grid(row=row,column=col+1,padx=(0,20),pady=3)
 def changes(self):return {name:int(var.get(),0) for name,var in self.vars.items()}
 def apply(self):
  try:self.app.action('vision_apply',changes=self.changes())
  except ValueError as e:self.app.progress.set(str(e))
 def preset(self,mode):
  changes={'cfg_test_async':int(mode!=0),'cfg_bist_dynamic':int(mode==2),'sys_dip_override':0,'sys_manual_block':0}
  self.app.action('vision_apply',changes=changes)
 def update(self,state,force=False):
  if not state:return
  r=state['results'];cfg=state['configuration'];speed=state['velocity_px_s']
  speed_text=f'{speed:.1f} px/s' if speed is not None else '等待测速结果'
  text=(f"{'自测' if r['active_source'] else '相机'}累计 {state['count']}　中心/低/高 {r['result_count']}/{r['parallel_low_result_count']}/{r['parallel_high_result_count']}　"
        f"T {r['parallel_threshold_low']}/{r['active_threshold']}/{r['parallel_threshold_high']}　去噪模式 {r['active_mode']}　"
        f"稳定值 {r['stable_count']}　速度 {speed_text}\n保护状态 {r['safety_state']} / 原因 0x{r['safety_reason']:04x}　"
        f"合并 {r['motion_merge_active']} / 恢复组数 {r['motion_merge_restored_groups']}　事件 {r['motion_event_seq']}　"
        f"BIST {'PASS' if r['bist_pass'] and r['bist_valid'] else 'FAIL' if r['bist_valid'] else 'RUN' if r['bist_busy'] else 'IDLE'}　配置 {cfg['cfg_config_version']}")
  self.summary.set(text)
  if force or self.last is None:
   for name,var in self.vars.items():var.set(str(cfg[name]))
  self.last=state
 def save(self):
  name=filedialog.asksaveasfilename(parent=self.app.root,defaultextension='.json',filetypes=[('算法场景','*.json')])
  if name and self.last:Path(name).write_text(json.dumps({'schema':'ABC-1.4','configuration':self.last['configuration']},ensure_ascii=False,indent=2),encoding='utf-8')
 def load(self):
  name=filedialog.askopenfilename(parent=self.app.root,filetypes=[('算法场景','*.json')])
  if name:
   try:
    record=json.loads(Path(name).read_text(encoding='utf-8-sig'))
    if record.get('schema')!='ABC-1.4':raise ValueError('场景版本不匹配')
    self.app.action('vision_apply',changes=record['configuration'])
   except (ValueError,KeyError) as e:self.app.progress.set(str(e))
