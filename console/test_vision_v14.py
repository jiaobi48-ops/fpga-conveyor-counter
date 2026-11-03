import json,struct,unittest,queue,tempfile
from unittest.mock import patch
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import vision_device as v

def packet():
 words=[0]*(128+v.SCHEMA['snapshot_words']);words[:4]=[2,0xC31401,len(v.BY_NAME),v.SCHEMA['snapshot_words']]
 for name,p in v.BY_NAME.items():words[16+p['index']]=p['default']&0xffffffff
 def put(name,value):
  p=v.RESULTS[name]
  for i in range(p['words']):words[128+p['word']+i]=(value>>(32*i))&0xffffffff
 put('camera_total',1234567);put('test_total',12);put('active_source',0)
 words[128+14]=v.SCHEMA['clock_hz']
 put('speed_valid',1);put('speed_dx',(-3)&65535);put('speed_cycles_per_frame',3333333)
 put('motion_event_context',(1<<120)+91)
 return words

class VisionTests(unittest.TestCase):
 def test_all_native_ports_and_fields(self):
  self.assertEqual(len(v.BY_NAME),77)
  names=[p['name'] for p in v.SCHEMA['results']];self.assertEqual(len(names),len(set(names)))
  for name in ['active_threshold','active_mode','parallel_low_result_count','parallel_high_result_count','motion_merge_restored_groups','speed_dx','safety_state','bist_pass','stable_count']:
   self.assertIn(name,names)
 def test_full_width_signed_and_context(self):
  words=packet();d=v.decode(struct.pack('<'+'I'*len(words),*words))
  self.assertEqual(d['count'],1234567)
  self.assertEqual(d['configuration']['cfg_mean_offset'],-24)
  self.assertEqual(d['results']['speed_dx'],-3)
  self.assertEqual(d['results']['motion_event_context'],(1<<120)+91)
  self.assertAlmostEqual(d['velocity_px_s'],-67.50000675,places=5)
 def test_source_totals_isolation(self):
  words=packet();words[128+v.RESULTS['active_source']['word']]=1
  d=v.decode(struct.pack('<'+'I'*len(words),*words));self.assertEqual(d['source'],'test');self.assertEqual(d['count'],12)
 def test_dip_and_test_effective_parameters(self):
  cfg={p['name']:p['default'] for p in v.SCHEMA['config']}
  cfg.update(sys_dip_override=1,sys_dip_bits=0b10110111,sys_manual_block=0)
  e=v.effective_configuration(cfg)
  self.assertEqual((e['cfg_test_async'],e['cfg_bist_dynamic'],e['cfg_bist_profile']),(1,1,1))
  self.assertEqual((e['cfg_auto_threshold'],e['cfg_auto_denoise'],e['cfg_parallel_enable'],e['cfg_valley_enable']),(1,1,0,1))
  self.assertEqual((e['cfg_invert'],e['cfg_mean_offset'],e['cfg_motion_enable']),(0,24,1))
  self.assertEqual(cfg['cfg_mean_offset'],-24)
 def test_config_ranges_and_versions(self):
  self.assertEqual(v.validate({'cfg_mean_offset':-256,'cfg_parallel_enable':0,'cfg_scene_epoch':123}),{'cfg_mean_offset':-256,'cfg_parallel_enable':0})
  for bad in [{'cfg_mean_offset':256},{'cfg_parallel_enable':2},{'cfg_noise_on':True},{'unknown':1}]:
   with self.assertRaises(ValueError):v.validate(bad)
 def test_one_action_switches_static_to_dynamic_and_replays(self):
  class Device:
   def __init__(self):
    self.cfg={p['name']:p['default'] for p in v.SCHEMA['config']};self.cfg.update(cfg_test_async=1,cfg_bist_dynamic=0)
    self.shadow=dict(self.cfg);self.commits=[]
   def command(self,op,args=None):
    if op==8:
     name=v.SCHEMA['config'][args[0]]['name'];self.shadow[name]=args[1]
    elif op==9:self.cfg=dict(self.shadow);self.commits.append((self.cfg['cfg_test_async'],self.cfg['cfg_bist_dynamic']))
  def state(device):
   return dict(configuration=dict(device.cfg),results=dict(active_source=v.effective_configuration(device.cfg)['cfg_test_async'],switch_busy=0))
  d=Device()
  with patch.object(v,'read',side_effect=state):
   v.apply(d,{'cfg_test_async':1,'cfg_bist_dynamic':1,'sys_dip_override':0})
   self.assertEqual(d.commits,[(0,0),(1,1)])
   v.apply(d,{'cfg_test_async':1,'cfg_bist_dynamic':1,'sys_dip_override':0})
   self.assertEqual(d.commits[-2:],[(0,1),(1,1)])
 def test_seqlock(self):
  words=packet();words[0]=3
  with self.assertRaises(ValueError):v.decode(struct.pack('<'+'I'*len(words),*words))
 def test_advanced_ranges_keep_basic_connection(self):
  import protocol
  h=[0]*128;h[64:74]=[799,0,4,0,480,255,70,5,48,4];h[94]=0xC31401
  self.assertEqual(protocol.configuration(h)['threshold'],255)
  h[69]=0;self.assertEqual(protocol.configuration(h)['threshold'],0)
 def test_gui_build_and_live_update(self):
  import tkinter as tk
  from app import App
  class Fake:
   def __init__(self):self.events=queue.Queue();self.config=None;self.busy=False
   def status(self):return dict(connected=False,serial=False,port='',busy=False,error='',config=None,pages=None,vision=None,rx=0,tx=0,frozen=False,image_age=None)
   def live(self):pass
   def close(self):pass
  root=tk.Tk();root.withdraw()
  try:
   app=App(root,controller=Fake());root.update_idletasks()
   words=packet();state=v.decode(struct.pack('<'+'I'*len(words),*words))
   app.algorithm_panel.update(state,force=True)
   self.assertIn('1234567',app.algorithm_panel.summary.get())
   self.assertEqual(app.algorithm_panel.vars['cfg_mean_offset'].get(),'-24')
   self.assertEqual(len(app.algorithm_panel.vars),75)
  finally:root.destroy()

if __name__=='__main__':unittest.main()
