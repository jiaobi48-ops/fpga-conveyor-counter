from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[1]
data=json.loads((R/'MANIFEST.json').read_text(encoding='utf-8'))
for item in data['files']:
 p=R/item['path']
 if not p.is_file() or p.stat().st_size!=item['bytes'] or hashlib.sha256(p.read_bytes()).hexdigest()!=item['sha256']:
  raise SystemExit('Changed/missing file: '+item['path'])
print('PASS',len(data['files']),'files match sealed package; not a board acceptance test')
