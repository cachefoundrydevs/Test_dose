#!/usr/bin/env python3
"""Validate the standalone RTL file list and construct complete timing coverage."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def inventory():
    listed = []
    for line in ((ROOT / 'filelists/rtl.f').read_text() + '\n' + (ROOT / 'filelists/dummy_l2.f').read_text()).splitlines():
        line = line.strip()
        if line and not line.startswith(('#', '-')):
            listed.append(line)
    actual = sorted(str(p.relative_to(ROOT)) for folder in ('rtl', 'dummy_l2') for p in (ROOT / folder).rglob('*.v'))
    if len(listed) != len(set(listed)) or set(actual) != set(listed):
        raise ValueError('filelists/rtl.f must list every RTL module exactly once')
    mpath = ROOT / 'SOURCE_MANIFEST.json'   # Test_dose: optional (this folder has no assembly manifest)
    manifest = json.loads(mpath.read_text()) if mpath.is_file() else {'files': []}
    original = {x['destination']: x for x in manifest['files']}
    files = []
    for p in sorted(p for folder in ('rtl', 'dummy_l2') for p in (ROOT / folder).rglob('*')):
        if not p.is_file() or p.suffix not in ('.v', '.vh', '.sv'):
            continue
        data = p.read_bytes()
        rel = str(p.relative_to(ROOT))
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        entry = dict(path=rel, git_blob=blob, sha256=hashlib.sha256(data).hexdigest(),
                     assembly_source=original.get(rel, {}).get('source'),
                     matches_assembly_snapshot=(blob == original.get(rel, {}).get('sha')))
        text = re.sub(r'/\*.*?\*/|//[^\n]*', '', data.decode(), flags=re.S)
        for inc in re.findall(r'`include\s+"([^"]+)"', text):
            if not (ROOT / 'rtl/include' / inc).is_file() and not (p.parent / inc).is_file():
                raise ValueError(f'{rel}: missing include {inc}')
        if p.suffix == '.v':
            names = re.findall(r'(?m)^\s*module\s+(\w+)', text)
            if names != [p.stem]:
                raise ValueError(f'{rel}: expected one module named {p.stem}, found {names}')
            entry.update(module=p.stem, has_clk=bool(re.search(r'\binput\b[^;\n]*\bclk\b', text)),
                         children=sorted(set(re.findall(r'(?m)^\s*(l1d_\w+)\s+(?:#\s*\(|\w+\s*\()', text)) - set(names)))
        files.append(entry)
    try:
        revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        revision = os.environ.get('GITHUB_SHA', 'local-uncommitted')
    return dict(source_revision=revision, root=str(ROOT), files=files,
                method='ASAP7 post-synthesis; ideal clock; zero I/O delay; no wires; assumed dual-port SRAM macros (gen_macros.py)',
                run_url=(f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
                         if 'GITHUB_RUN_ID' in os.environ else None))


def plan(data, periods):
    ps = periods.split()
    if not ps or len(ps) > 4 or len(set(ps)) != len(ps) or any(not p.isdigit() or not 50 <= int(p) <= 10000 for p in ps):
        raise ValueError('periods must be 1–4 distinct integer ps values between 50 and 10000')
    groups = {g: [] for g in ['primitives', 'buffers', 'miss', 'bank', 'top', 'soc']}
    for f in data['files']:
        if 'module' not in f:
            continue
        m, p = f['module'], f['path']
        if m == 'l1d_bank': group = 'bank'
        elif m == 'l1d_top': group = 'top'
        elif m == 'l1d_top_soc': group = 'soc'
        elif p.startswith('rtl/bank/miss/'): group = 'miss'
        elif p.startswith(('rtl/bank/fifo/', 'rtl/axi/', 'rtl/snoop/')) or m == 'l1d_maint': group = 'buffers'
        else: group = 'primitives'
        groups[group].append(m)
    rows = [dict(group=g, period=int(p), modules=' '.join(ms)) for p in ps for g, ms in groups.items() if ms]
    return dict(include=rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--periods', default='250 200')
    ap.add_argument('--snapshot', type=Path)
    ap.add_argument('--modules', default='')
    ap.add_argument('--lines', action='store_true')
    args = ap.parse_args()
    data = inventory()
    if args.snapshot:
        args.snapshot.parent.mkdir(parents=True, exist_ok=True)
        args.snapshot.write_text(json.dumps(data, indent=2) + '\n')
    mods = [x for x in data['files'] if 'module' in x]
    if args.lines:
        requested = args.modules.split() or [x['module'] for x in mods]
        if len(requested) != len(set(requested)) or set(requested) - {x['module'] for x in mods}:
            raise ValueError('unknown or duplicate module requested')
        for m in requested:
            f = next(x for x in mods if x['module'] == m)
            print(f"{m}\t{int(f['has_clk'])}\t{f['path']}\t{' '.join(f['children']) or '-'}")
    else:
        print(json.dumps(plan(data, args.periods), separators=(',', ':')))


if __name__ == '__main__':
    main()
