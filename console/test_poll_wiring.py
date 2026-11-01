"""Check the actual live-loop source and linked ARM entry for UART service calls."""
from pathlib import Path
import hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parent
BIN = Path('D:/vivado/2025.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin')

def inspect(root):
    source = (root/'src/main.c').read_text(encoding='utf-8')
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    live = source.split('for(ms=0;ms<1000U;ms++)', 1)[1].split('sec++;', 1)[0]
    assert re.search(r'if\s*\(\s*cup_poll\s*\(\s*\)\s*\)\s*goto\s+stopped\s*;', live), 'UART parser missing from live loop or errors ignored'
    elf = root/'build/camera_control_console.elf'
    symbols = subprocess.run([str(BIN/'arm-none-eabi-nm.exe'), '-S', str(elf)], capture_output=True, text=True, check=True).stdout
    symbol = re.search(r'^([0-9a-f]+)\s+([0-9a-f]+)\s+T\s+main$', symbols, re.M)
    assert symbol, 'linked main symbol unavailable'
    start, size = (int(x, 16) for x in symbol.groups())
    disassembly = subprocess.run([str(BIN/'arm-none-eabi-objdump.exe'), '-d', str(elf)], capture_output=True, text=True, check=True).stdout
    calls = []
    for line in disassembly.splitlines():
        m = re.search(r'^\s*([0-9a-f]+):.*\bbl\s+[0-9a-f]+\s+<(cup_poll|studio_poll|preview_poll)>', line)
        if m and start <= int(m[1], 16) < start+size:
            calls.append({'address': m[1], 'target': m[2]})
    assert {x['target'] for x in calls} == {'cup_poll', 'studio_poll', 'preview_poll'}, 'linked main is missing a required live service'
    return {'elf_sha256': hashlib.sha256(elf.read_bytes()).hexdigest(), 'main_service_calls': calls}

if __name__ == '__main__':
    result = inspect(ROOT)
    if len(sys.argv) == 2:
        baseline = Path(sys.argv[1]).resolve()
        try:
            inspect(baseline)
        except AssertionError as e:
            result['original_bug_reproduced'] = str(e)
        else:
            raise AssertionError('old baseline unexpectedly passed the regression check')
    result.update(status='PASS', scope='Source live-loop integration and actual linked ARM main; not execution on hardware')
    (ROOT/'validation/main_loop_receipt.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('PASS live-loop UART integration, linked ARM calls, and original-bug regression')
