"""Load calibration scenes through the existing console and configuration writer."""
from pathlib import Path
import json
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parent))
import vision_device as v
from algorithm_panel import AlgorithmPanel

ROOT=Path(__file__).resolve().parents[1]
SCENE=ROOT/'verification/calibration/native_scene_example.json'

class CalibrationImportTests(unittest.TestCase):
 def test_current_base_matches_native_defaults(self):
  p=json.loads((ROOT/'tools/offline_calibration/reference/ABC_v1.4_800x480_base.json').read_text(encoding='utf-8'))
  defaults={p['name']:p['default'] for p in v.SCHEMA['config']}
  self.assertEqual(p['algorithm_size'],[800,480])
  self.assertEqual(p['policy']['timeout_cycles'],defaults['cfg_source_timeout_cycles'])
  self.assertEqual(p['motion']['max_step'],defaults['cfg_max_step'])
  self.assertEqual(p['motion']['line_a'],defaults['cfg_line_a'])
  self.assertEqual(p['motion']['line_b'],defaults['cfg_line_b'])
  self.assertEqual(p['motion']['hysteresis'],defaults['cfg_hysteresis'])

 def test_exported_fields_use_native_types_and_ranges(self):
  s=json.loads(SCENE.read_text(encoding='utf-8'))
  self.assertEqual(s['schema'],'ABC-1.4')
  self.assertEqual(v.validate(s['configuration']),s['configuration'])
  self.assertEqual(s['calibration']['clock_hz'],75000000)
  self.assertLessEqual(s['configuration']['cfg_threshold_min'],s['configuration']['cfg_threshold'])
  self.assertLessEqual(s['configuration']['cfg_threshold'],s['configuration']['cfg_threshold_max'])

 def test_console_load_commit_and_readback_preserve_algorithm_switches(self):
  calls=[]
  class App:
   root=None
   def action(self,op,**kw):calls.append((op,kw))
  panel=AlgorithmPanel.__new__(AlgorithmPanel);panel.app=App()
  with patch('algorithm_panel.filedialog.askopenfilename',return_value=str(SCENE)):
   panel.load()
  self.assertEqual(calls[0][0],'vision_apply')
  changes=calls[0][1]['changes']
  class Device:
   def __init__(self):
    self.cfg={p['name']:p['default'] for p in v.SCHEMA['config']}
    self.shadow=dict(self.cfg);self.commands=[]
   def command(self,op,args=None):
    self.commands.append(op)
    if op==8:
     p=v.SCHEMA['config'][args[0]];value=args[1]
     if p.get('signed') and value&0x80000000:value-=1<<32
     self.shadow[p['name']]=value
    elif op==9:self.cfg=dict(self.shadow)
  d=Device();before=dict(d.cfg)
  def state(device):
   return dict(configuration=dict(device.cfg),results=dict(active_source=0,switch_busy=0))
  with patch.object(v,'read',side_effect=state):
   actual=v.apply(d,changes)
  for name in ('cfg_auto_threshold','cfg_auto_denoise','cfg_parallel_enable','cfg_valley_enable','cfg_merge_enable','cfg_speed_enable','cfg_stable_mode'):
   self.assertEqual(actual['configuration'][name],before[name])
  self.assertEqual(actual['configuration']['sys_manual_block'],1)
  self.assertEqual(actual['configuration']['sys_manual_mode'],1)
  self.assertEqual(actual['configuration']['cfg_guard_enable'],1)
  self.assertEqual(actual['configuration']['cfg_mean_offset'],changes['cfg_mean_offset'])
  self.assertEqual(d.commands.count(9),1)
  self.assertNotIn(7,d.commands)

if __name__=='__main__':unittest.main()
