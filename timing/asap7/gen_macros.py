#!/usr/bin/env python3
"""Generate the TRUE DUAL-PORT SRAM macro models of Test_dose for the ASAP7 timing flow (ESTIMATES).

ASAP7 has no memory compiler. Every l1d_sram_tdp instance is replaced in the synthesis input (l1d_sram_tdp_asap7.v)
by one of two hard macros:
    l1d_macro_data_tdp : 64 x 512 bits, whole-line write (no byte enables), ports A and B   (data array, one per way)
    l1d_macro_tag_tdp  : 64 x  50 bits, ports A and B                                     (tag array, one per way)
Port A is used for reads (Stage G), port B for writes (Stage S2 / S3). Each port: clk, X_en, X_we, X_addr[5:0],
X_wdata, X_rdata.

The read time (clock to X_rdata) and the setup time are ASSUMPTIONS, not foundry data. The bank registers the SRAM
output at the end of Stage R (one cycle), so for a 4 GHz design the read must fit about one clock period minus the
flop setup and clock uncertainty. Override the defaults with environment variables to see how the result moves:
    DATA_CLKQ_PS (default 180)  TAG_CLKQ_PS (default 150)  DATA_SETUP_PS (default 50)  TAG_SETUP_PS (default 40)
For comparison, the earlier single-port flow assumed data 320 ps / tag 200 ps (it does not fit one 250 ps cycle).

usage: gen_macros.py <out_dir>
"""
import os
import sys


def env_ps(name, default):
    v = os.environ.get(name, '').strip()
    return float(v) if v else float(default)


# name, depth, bits, clk->rdata (ps), setup (ps), width, height (um)
MACROS = [
    ("l1d_macro_data_tdp", 64, 512, env_ps("DATA_CLKQ_PS", 180), env_ps("DATA_SETUP_PS", 50), 60.0, 40.0),
    ("l1d_macro_tag_tdp",  64,  50, env_ps("TAG_CLKQ_PS", 150),  env_ps("TAG_SETUP_PS", 40),  20.0, 12.0),
]
HOLD_PS = 15.0
IN_CAP_FF = 1.0
PORTS = ("a", "b")


def clog2(n):
    return max(1, (n - 1).bit_length())


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


def make_lib(name, depth, bits, clk_q, setup, w, h):
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
    s += '  cell(%s) {\n    area : %.1f;\n    dont_touch : true;\n' % (name, w * h)
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


def make_lef(name, depth, bits, w, h):
    aw = clog2(depth)
    names = [("clk", "INPUT")]
    for p in PORTS:
        names += [("%s_en" % p, "INPUT"), ("%s_we" % p, "INPUT")]
        names += [("%s_addr[%d]" % (p, i), "INPUT") for i in range(aw)]
        names += [("%s_wdata[%d]" % (p, i), "INPUT") for i in range(bits)]
        names += [("%s_rdata[%d]" % (p, i), "OUTPUT") for i in range(bits)]
    s = 'VERSION 5.8 ;\nBUSBITCHARS "[]" ;\nDIVIDERCHAR "/" ;\n\nMACRO %s\n  CLASS BLOCK ;\n' % name
    s += '  ORIGIN 0 0 ;\n  SIZE %.3f BY %.3f ;\n  SYMMETRY X Y R90 ;\n' % (w, h)
    n_in = sum(1 for _, d in names if d == "INPUT")
    n_out = len(names) - n_in
    ii = oi = 0
    for pn, d in names:
        if d == "INPUT":
            x = 0.5 + (w - 1.0) * (ii + 0.5) / max(1, n_in)
            y = 0.2
            ii += 1
        else:
            x = 0.5 + (w - 1.0) * (oi + 0.5) / max(1, n_out)
            y = h - 0.4
            oi += 1
        s += ('  PIN %s\n    DIRECTION %s ;\n    USE SIGNAL ;\n    PORT\n      LAYER M4 ;\n'
              '        RECT %.3f %.3f %.3f %.3f ;\n    END\n  END %s\n'
              % (pn, d, x, y, x + 0.02, y + 0.2, pn))
    s += ('  PIN VDD\n    DIRECTION INOUT ;\n    USE POWER ;\n    PORT\n      LAYER M4 ;\n'
          '        RECT 0.0 %.3f %.3f %.3f ;\n    END\n  END VDD\n'
          '  PIN VSS\n    DIRECTION INOUT ;\n    USE GROUND ;\n    PORT\n      LAYER M4 ;\n'
          '        RECT 0.0 %.3f %.3f %.3f ;\n    END\n  END VSS\n'
          % (h / 2, w, h / 2 + 0.2, h / 2 + 1.0, w, h / 2 + 1.2))
    s += '  OBS\n    LAYER M1 ;\n      RECT 0 0 %.3f %.3f ;\n  END\nEND %s\n\nEND LIBRARY\n' % (w, h, name)
    return s


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "macro_assumptions.txt"), "w") as f:
        f.write("ASSUMED dual-port SRAM macro timing (not foundry data)\n")
        for (name, depth, bits, clk_q, setup, w, h) in MACROS:
            f.write("%s: %d x %d, clk->rdata %.1f ps, setup %.1f ps, hold %.1f ps, %.0f x %.0f um\n"
                    % (name, depth, bits, clk_q, setup, HOLD_PS, w, h))
            with open(os.path.join(out, name + ".lib"), "w") as g:
                g.write(make_lib(name, depth, bits, clk_q, setup, w, h))
            with open(os.path.join(out, name + ".lef"), "w") as g:
                g.write(make_lef(name, depth, bits, w, h))
    print(open(os.path.join(out, "macro_assumptions.txt")).read())


if __name__ == "__main__":
    main()
