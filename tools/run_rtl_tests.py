from pathlib import Path
import os, subprocess, json, hashlib
R=Path(__file__).resolve().parents[1];F=R/'fpga'
B=Path(os.environ.get('VIVADO_BIN','D:/vivado/2025.2/Vivado/bin'))
O=R/'rebuild/rtl_tests';O.mkdir(parents=True,exist_ok=True)
names=['tb_cup_passage','tb_cup_control','tb_cup_v3_video','tb_follow_capture']
def run(args,name):
 p=subprocess.run(list(map(str,args)),cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace')
 (O/name).write_text(p.stdout+p.stderr,encoding='utf-8')
 if p.returncode: raise RuntimeError(name)
 return p.stdout+p.stderr
run([B/'xvlog.bat','--sv',B.parent/'data/verilog/src/glbl.v',*sorted((F/'rtl').glob('*.v')),*[F/'sim'/(n+'.v') for n in names]],'compile.log')
for n in names:
 run([B/'xelab.bat',n,'glbl','-L','unisims_ver','-s',n+'_sim'],n+'_elab.log')
 result=run([B/'xsim.bat',n+'_sim','-runall'],n+'_run.log')
 assert 'PASS ' in result and not any(s in result for s in ['Fatal','FATAL','ERROR:'])
 print(n, 'PASS')
(O/'receipt.json').write_text(json.dumps({'status':'PASS RTL simulation only','tests':names,'rtl_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (F/'rtl').glob('*.v')}},indent=2))
