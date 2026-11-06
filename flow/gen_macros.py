#!/usr/bin/env python3
"""Make the dual-port SRAM macro models (lib + lef) for the ASAP7 synthesis / place and route flow.
ASAP7 has no memory compiler, so the timing numbers here are ESTIMATES, not foundry data.
  l1d_macro_data_tdp : 64 x 512 bits, whole-line write, ports a and b   (one per way)
  l1d_macro_tag_tdp  : 64 x  50 bits, ports a and b                    (one per way)
Port a reads, port b writes. Pins sit on the M4 track grid read from the tech LEF, so the router can reach them.
Env: DATA_CLKQ_PS (180) TAG_CLKQ_PS (150) DATA_SETUP_PS (50) TAG_SETUP_PS (40)
usage: gen_macros.py <out_dir> <tech_lef>
"""
import math
import os
import re
import sys


def env_ps(name, default):
    v = os.environ.get(name, '').strip()
    return float(v) if v else float(default)


MACROS = [
    ("l1d_macro_data_tdp", 64, 512, env_ps("DATA_CLKQ_PS", 180), env_ps("DATA_SETUP_PS", 50), 2400.0),
    ("l1d_macro_tag_tdp", 64, 50, env_ps("TAG_CLKQ_PS", 150), env_ps("TAG_SETUP_PS", 40), 240.0),
]
HOLD_PS = 15.0
IN_CAP_FF = 1.0
PORTS = ("a", "b")
GRID = 0.27


def clog2(n):
    return max(1, (n - 1).bit_length())


def up(v):
    return math.ceil(v / GRID - 1e-9) * GRID


def layer_info(tech_lef, layer):
    txt = open(tech_lef).read()
    m = re.search(r'LAYER\s+%s\s*\n(.*?)END\s+%s' % (layer, layer), txt, re.S)
    body = m.group(1) if m else ''
    def g(key, default):
        r = re.search(r'\b%s\s+([0-9.]+)' % key, body)
        return float(r.group(1)) if r else default
    d = re.search(r'DIRECTION\s+(\w+)', body)
    return (d.group(1) if d else 'VERTICAL'), g('PITCH', 0.048), g('OFFSET', 0.024), g('WIDTH', 0.024)


def table(t_name, val, tmpl="t1"):
    return '%s(%s) { index_1("0.0, 200.0"); values("%.1f, %.1f"); }' % (t_name, tmpl, val, val)


def setup_hold(setup, hold):
    return ('      timing() { related_pin : "clk"; timing_type : setup_rising;\n'
            '        %s\n        %s }\n'
            '      timing() { related_pin : "clk"; timing_type : hold_rising;\n'
            '        %s\n        %s }\n'
            % (table("rise_constraint", setup, "c1"), table("fall_constraint", setup, "c1"),
               table("rise_constraint", hold, "c1"), table("fall_constraint", hold, "c1")))


def bus_pin(name, width, direction, extra):
    return ('    bus(%s) {\n      bus_type : bus_%d;\n      direction : %s;\n%s    }\n'
            % (name, width, direction, extra))


def make_lib(name, depth, bits, clk_q, setup, area):
    aw = clog2(depth)
    s = 'library(%s) {\n' % name
    s += ('  delay_model : table_lookup;\n  time_unit : "1ps";\n  voltage_unit : "1V";\n'
          '  current_unit : "1uA";\n  pulling_resistance_unit : "1kohm";\n'
          '  capacitive_load_unit(1, ff);\n  leakage_power_unit : "1nW";\n'
          '  nom_process : 1; nom_temperature : 25; nom_voltage : 0.7;\n'
          '  input_threshold_pct_rise : 50; input_threshold_pct_fall : 50;\n'
          '  output_threshold_pct_rise : 50; output_threshold_pct_fall : 50;\n'
          '  slew_lower_threshold_pct_rise : 10; slew_upper_threshold_pct_rise : 90;\n'
          '  slew_lower_threshold_pct_fall : 10; slew_upper_threshold_pct_fall : 90;\n'
          '  default_max_transition : 320;\n')
    s += '  lu_table_template(t1) { variable_1 : input_net_transition; index_1("0.0, 200.0"); }\n'
    s += '  lu_table_template(c1) { variable_1 : related_pin_transition; index_1("0.0, 200.0"); }\n'
    for n in sorted({aw, bits}):
        s += ('  type(bus_%d) { base_type : array; data_type : bit; bit_width : %d;'
              ' bit_from : %d; bit_to : 0; downto : true; }\n' % (n, n, n - 1))
    s += '  cell(%s) {\n    area : %.1f;\n    dont_touch : true;\n' % (name, area)
    s += ('    pin(clk) { direction : input; clock : true; capacitance : %.1f;\n'
          '      min_pulse_width_high : 60; min_pulse_width_low : 60; }\n' % IN_CAP_FF)
    body = ('      capacitance : %.1f;\n' % IN_CAP_FF) + setup_hold(setup, HOLD_PS)
    out = ('      timing() { related_pin : "clk"; timing_type : rising_edge;\n'
           '        %s\n        %s\n        %s\n        %s }\n'
           % (table("cell_rise", clk_q), table("cell_fall", clk_q),
              table("rise_transition", 40.0), table("fall_transition", 40.0)))
    for p in PORTS:
        s += '    pin(%s_en) { direction : input;\n%s    }\n' % (p, body)
        s += '    pin(%s_we) { direction : input;\n%s    }\n' % (p, body)
        s += bus_pin('%s_addr' % p, aw, "input", body)
        s += bus_pin('%s_wdata' % p, bits, "input", body)
        s += bus_pin('%s_rdata' % p, bits, "output", "      max_capacitance : 80;\n" + out)
    s += '  }\n}\n'
    return s


def pin_names(depth, bits):
    aw = clog2(depth)
    ins = [("clk", "INPUT")]
    outs = []
    for p in PORTS:
        ins += [("%s_en" % p, "INPUT"), ("%s_we" % p, "INPUT")]
        ins += [("%s_addr[%d]" % (p, i), "INPUT") for i in range(aw)]
        ins += [("%s_wdata[%d]" % (p, i), "INPUT") for i in range(bits)]
        outs += [("%s_rdata[%d]" % (p, i), "OUTPUT") for i in range(bits)]
    return ins, outs


def make_lef(name, depth, bits, area, tech):
    direction, pitch, offset, width = tech
    ins, outs = pin_names(depth, bits)
    edge = up(max(len(ins), len(outs)) * pitch + 2.0)
    other = up(area / edge)
    if direction == 'VERTICAL':
        w, h = edge, other
    else:
        w, h = other, edge
    s = 'VERSION 5.8 ;\nBUSBITCHARS "[]" ;\nDIVIDERCHAR "/" ;\n\nMACRO %s\n  CLASS BLOCK ;\n' % name
    s += '  ORIGIN 0 0 ;\n  SIZE %.3f BY %.3f ;\n  SYMMETRY X Y R90 ;\n' % (w, h)
    hw = width / 2.0
    for group, side in ((ins, 0), (outs, 1)):
        for k, (pn, d) in enumerate(group):
            t = offset + 1.0 + k * pitch
            if direction == 'VERTICAL':
                y0 = 0.2 if side == 0 else h - 0.6
                r = (t - hw, y0, t + hw, y0 + 0.4)
            else:
                x0 = 0.2 if side == 0 else w - 0.6
                r = (x0, t - hw, x0 + 0.4, t + hw)
            s += ('  PIN %s\n    DIRECTION %s ;\n    USE SIGNAL ;\n    PORT\n      LAYER M4 ;\n'
                  '        RECT %.3f %.3f %.3f %.3f ;\n    END\n  END %s\n' % ((pn, d) + r + (pn,)))
    s += ('  PIN VDD\n    DIRECTION INOUT ;\n    USE POWER ;\n    PORT\n      LAYER M4 ;\n'
          '        RECT 1.0 %.3f %.3f %.3f ;\n    END\n  END VDD\n'
          '  PIN VSS\n    DIRECTION INOUT ;\n    USE GROUND ;\n    PORT\n      LAYER M4 ;\n'
          '        RECT 1.0 %.3f %.3f %.3f ;\n    END\n  END VSS\n'
          % (h / 2, w - 1.0, h / 2 + 0.2, h / 2 + 1.0, w - 1.0, h / 2 + 1.2))
    s += '  OBS\n    LAYER M1 ;\n      RECT 0 0 %.3f %.3f ;\n  END\nEND %s\n\nEND LIBRARY\n' % (w, h, name)
    return s, w, h


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    out, tech_lef = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    tech = layer_info(tech_lef, 'M4')
    lines = ["ASSUMED dual-port SRAM macro timing (not foundry data); M4 = %s pitch %.3f offset %.3f width %.3f" % tech]
    for (name, depth, bits, clk_q, setup, area) in MACROS:
        lef, w, h = make_lef(name, depth, bits, area, tech)
        with open(os.path.join(out, name + ".lef"), "w") as g:
            g.write(lef)
        with open(os.path.join(out, name + ".lib"), "w") as g:
            g.write(make_lib(name, depth, bits, clk_q, setup, w * h))
        lines.append("%s: %d x %d, clk->rdata %.1f ps, setup %.1f ps, hold %.1f ps, %.2f x %.2f um"
                     % (name, depth, bits, clk_q, setup, HOLD_PS, w, h))
    with open(os.path.join(out, "macro_assumptions.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
