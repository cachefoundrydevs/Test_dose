#!/usr/bin/env python3
"""Report timing measurements; tool failures and missing coverage fail the report."""
import argparse
import csv
import json
import math
from pathlib import Path


def measurements(row):
    # Write only finite measurements. Negative slack is a valid measured miss.
    def number(key):
        try:
            n = float(row[key])
            return n if math.isfinite(n) else None
        except (KeyError, ValueError, TypeError):
            return None
    period, slack = number('period_ps'), number('slack_all')
    delay = period - slack if period is not None and slack is not None else None
    row['crit_delay_ps'] = f'{delay:.3f}' if delay is not None and delay > 0 else ''
    row['fmax_ghz'] = f'{1000 / delay:.4f}' if delay is not None and delay > 0 else ''
    row['verdict'] = ('MEETS' if slack >= 0 else 'MISSES') if slack is not None and row['status'] == 'ok' else row['status']
    return row


def render(rows, missing):
    s = ['# Test_dose — ASAP7 post-synthesis timing', '',
         'Post-synthesis estimates: ideal clock, no wires, zero I/O delays, 5% clock uncertainty. SRAM models assume data clock-to-output 180 ps and tag 150 ps; these are not foundry measurements.', '',
         'Parents include their flattened children. Combinational modules use a virtual clock; their equivalent GHz value is not a measured operating clock. Generic blocks use their own default parameters; the parent rows include instance-specific sizes. The SRAM row uses the dual-port data-macro timing model (assumed, see macros/macro_assumptions.txt), not a synthesized flip-flop RAM.', '',
         'Effective critical period = target period − worst setup slack; equivalent GHz = 1000 / effective critical period. Setup and uncertainty are included. Passing the workflow means measurement completed, not that every target was met. No post-route frequency or functional/latency compliance is established.', '',
         '| Module | Target ps | Clock | Worst slack ps | Effective critical ps | Equivalent GHz | Area um² | Result |',
         '|---|---:|---|---:|---:|---:|---:|---|']
    for r in sorted(rows, key=lambda x: (float(x['period_ps']), x['module'])):
        s.append('| ' + ' | '.join([r['module'],r['period_ps'],'real' if r['has_clk']=='1' else 'virtual',r.get('slack_all','') or '—',r['crit_delay_ps'] or '—',r['fmax_ghz'] or '—',r.get('area_um2','') or '—',r['verdict']]) + ' |')
    if missing:
        s += ['', '## Missing module/period results', '', *[f'- {m} at {p} ps' for m,p in missing]]
    s += ['', 'Raw CSV, input hashes/revision, constraints, synthesis/STA logs, library selections and detailed worst/hold paths are saved in the job artifacts. Review check_setup reports for unconstrained or other coverage warnings.', '']
    return '\n'.join(s)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--csv', type=Path)
    ap.add_argument('--artifacts', type=Path)
    ap.add_argument('--expected', type=Path)
    ap.add_argument('--periods', default='250 200')
    ap.add_argument('--output', type=Path, required=True)
    args=ap.parse_args()
    paths=[args.csv] if args.csv else sorted(args.artifacts.rglob('modules.csv'))
    rows=[]
    seen=set()
    for p in paths:
        if not p.exists(): continue
        for row in csv.DictReader(p.open()):
            key=(row['module'],int(float(row['period_ps'])))
            if key in seen: raise ValueError(f'duplicate measurement {key}')
            seen.add(key); rows.append(measurements(row))
    missing=[]
    if args.expected:
        inv=json.loads(args.expected.read_text())
        wanted={(x['module'],int(p)) for x in inv['files'] if 'module' in x for p in args.periods.split()}
        missing=sorted(wanted-seen)
        if seen-wanted: raise ValueError('Unexpected module/period results')
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'REPORT.md').write_text(render(rows,missing))
    fields=['module','contains','has_clk','period_ps','slack_all','slack_r2r','slack_in2reg','slack_reg2out','slack_in2out','crit_delay_ps','fmax_ghz','area_um2','status','verdict']
    with (args.output/'modules.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fields,extrasaction='ignore');w.writeheader();w.writerows(rows)
    (args.output/'coverage.json').write_text(json.dumps(dict(measurements=len(rows),missing=missing,tool_failures=[r for r in rows if r['status']!='ok']),indent=2)+'\n')
    print((args.output/'REPORT.md').read_text())
    if not rows or missing or any(r['status']!='ok' for r in rows): raise SystemExit(1)


if __name__=='__main__':main()
