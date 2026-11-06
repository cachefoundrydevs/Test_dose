#!/usr/bin/env python3
"""summarize.py one --work W --top T --period P --corner C --synth-rc N --pnr-rc N --out file.json
summarize.py all --dir artifacts --out RESULTS.md
Reads the ORFS stage metrics (json) and writes the worst setup slack per stage and the maximum frequency."""
import argparse
import glob
import json
import os
import re

KEYS = ("timing__setup__ws", "timing__setup__tns", "timing__hold__ws", "design__instance__area",
        "design__instance__count", "design__instance__utilization", "power__total",
        "timing__drv__max_slew", "timing__drv__max_cap", "route__drc_errors", "antenna_diodes_count",
        "design__violations")


def stage_metrics(logdir):
    rows = {}
    for f in sorted(glob.glob(os.path.join(logdir, "**", "*.json"), recursive=True)):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        got = {k: v for k, v in d.items() if any(k.endswith(x) or x in k for x in KEYS)}
        if got:
            rows[os.path.basename(f)] = got
    return rows


def pick(rows, suffix):
    last = None
    for name in sorted(rows):
        for k, v in rows[name].items():
            if k.endswith(suffix) and isinstance(v, (int, float)):
                last = (name, k, v)
    return last


def one(a):
    logdir = os.path.join(a.work, "logs", "asap7", a.top, "base")
    rows = stage_metrics(logdir)
    period = float(a.period)
    res = {"top": a.top, "period_ps": period, "corner": a.corner, "synth_rc": a.synth_rc, "pnr_rc": a.pnr_rc,
           "stages": {}}
    for name, d in rows.items():
        res["stages"][name] = {k: v for k, v in d.items() if "setup__ws" in k or "setup__tns" in k}
    ws = pick(rows, "timing__setup__ws")
    tns = pick(rows, "timing__setup__tns")
    hold = pick(rows, "timing__hold__ws")
    area = pick(rows, "design__instance__area")
    if ws:
        res["last_stage"] = ws[0]
        res["setup_ws_ps"] = ws[2]
        crit = period - ws[2]
        res["crit_ps"] = crit
        res["fmax_ghz"] = round(1000.0 / crit, 3) if crit > 0 else None
    if tns:
        res["setup_tns_ps"] = tns[2]
    if hold:
        res["hold_ws_ps"] = hold[2]
    if area:
        res["area_um2"] = area[2]
    res["done"] = (a.pnr_rc == "0")
    json.dump(res, open(a.out, "w"), indent=1)
    print(json.dumps(res, indent=1))


def allm(a):
    runs = []
    for f in sorted(glob.glob(os.path.join(a.dir, "**", "summary.json"), recursive=True)):
        try:
            runs.append(json.load(open(f)))
        except Exception:
            pass
    runs.sort(key=lambda r: (r["top"], r["corner"], r["period_ps"]))
    t = ["# ASAP7 synthesis + place and route", "",
         "Ideal-wire assumptions removed: placement, clock tree and routing are done. SRAM macros are ESTIMATES",
         "(no ASAP7 memory compiler). I/O delay 0, clock uncertainty 5 %. Fmax = 1000 / (period - worst setup slack).", "",
         "| top | corner | period ps | synth | pnr | last stage | setup WS ps | TNS ps | hold WS ps | area um2 | Fmax GHz |",
         "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in runs:
        t.append("| %s | %s | %g | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["top"], r["corner"], r["period_ps"], r["synth_rc"], r["pnr_rc"], r.get("last_stage", "-"),
            r.get("setup_ws_ps", "-"), r.get("setup_tns_ps", "-"), r.get("hold_ws_ps", "-"),
            r.get("area_um2", "-"), r.get("fmax_ghz", "-")))
    t += ["", "Exit code 0 = stage finished; na = not started. Per-stage slacks:", ""]
    for r in runs:
        t.append("- %s %s %g ps: %s" % (r["top"], r["corner"], r["period_ps"],
                 ", ".join("%s %s" % (n.replace(".json", ""), [round(v, 1) for k, v in s.items() if k.endswith("setup__ws")])
                           for n, s in r["stages"].items() if any(k.endswith("setup__ws") for k in s)) or "no metrics"))
    open(a.out, "w").write("\n".join(t) + "\n")
    print("\n".join(t))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("mode")
    p.add_argument("--work")
    p.add_argument("--top")
    p.add_argument("--period")
    p.add_argument("--corner")
    p.add_argument("--synth-rc", dest="synth_rc")
    p.add_argument("--pnr-rc", dest="pnr_rc")
    p.add_argument("--dir")
    p.add_argument("--out")
    a = p.parse_args()
    one(a) if a.mode == "one" else allm(a)
