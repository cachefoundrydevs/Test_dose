#!/usr/bin/env bash
# Test_dose: synthesize this RTL tree with the ASAP7 ORFS flow; SRAMs = dual-port macro models (gen_macros.py).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(cd "$HERE/../.." && pwd)
PERIOD=${PERIOD:-250}
OUT=${OUT:-$PROJECT/timing_results/local_p$PERIOD}
mkdir -p "$OUT/results" "$OUT/inputs" "$OUT/macros"
OUT=$(cd "$OUT" && pwd)
[[ "$PERIOD" =~ ^[0-9]+$ ]] && (( PERIOD >= 50 && PERIOD <= 10000 )) || { echo 'Invalid PERIOD'; exit 1; }
python3 "$HERE/inventory.py" --periods "$PERIOD" --snapshot "$OUT/inputs/source_inventory.json" --lines --modules "${MODULES:-}" > "$OUT/inputs/modules.tsv"
cp "$PROJECT/filelists/rtl.f" "$OUT/inputs/rtl.f"
[[ -f "$PROJECT/SOURCE_MANIFEST.json" ]] && cp "$PROJECT/SOURCE_MANIFEST.json" "$OUT/inputs/assembly_manifest.json" || true
if [[ ${DRY_RUN:-0} == 1 ]]; then cat "$OUT/inputs/modules.tsv"; exit 0; fi

if [[ -z ${FLOW_HOME:-} ]]; then
    for p in /OpenROAD-flow-scripts/flow /opt/OpenROAD-flow-scripts/flow; do
        if [[ -f $p/Makefile ]]; then export FLOW_HOME=$p; break; fi
    done
fi
[[ -f ${FLOW_HOME:-}/Makefile ]] || { echo 'ERROR: set FLOW_HOME to the ORFS flow directory'; exit 1; }
if [[ -z ${OPENROAD:-} || -d ${OPENROAD:-} || ! -x ${OPENROAD:-} ]]; then
    OPENROAD=$(command -v openroad || find "$FLOW_HOME/.." -type f -name openroad -perm -u+x -print -quit)
fi
[[ -f ${OPENROAD:-} && -x ${OPENROAD:-} ]] || { echo 'ERROR: OpenROAD binary not found'; exit 1; }
export OPENROAD CLK_PERIOD_PS=$PERIOD
{
    printf 'Source SHA: %s\n' "${GITHUB_SHA:-local}"
    printf 'Period: %s ps\nFLOW_HOME: %s\nOPENROAD: %s\n' "$PERIOD" "$FLOW_HOME" "$OPENROAD"
    "$OPENROAD" -version
    (git -C "$FLOW_HOME" log -1 --format='ORFS %H' 2>/dev/null || true)
    (yosys -V 2>/dev/null || true)
    printf 'Job: %s\nRun: %s\n' "${GITHUB_JOB:-local}" "${GITHUB_RUN_ID:-local}"
} > "$OUT/inputs/tool_versions.txt" 2>&1
cat "$OUT/inputs/tool_versions.txt"
python3 "$HERE/gen_macros.py" "$OUT/macros"
FILES=''
while read -r f; do
    [[ -z "$f" || "$f" == \#* || "$f" == -* || "$f" == rtl/common/l1d_sram_tdp.v ]] && continue
    FILES="$FILES $PROJECT/$f"
done < <(cat "$PROJECT/filelists/rtl.f" "$PROJECT/filelists/dummy_l2.f")
FILES="$FILES $HERE/l1d_sram_tdp_asap7.v"
CSV="$OUT/results/modules.csv"
echo 'module,contains,has_clk,period_ps,slack_all,slack_r2r,slack_in2reg,slack_reg2out,slack_in2out,crit_delay_ps,fmax_ghz,area_um2,status' > "$CSV"

make_sdc() {
    local file=$1 hasclk=$2
    {
        echo 'set_units -time ps -capacitance fF'
        if [[ $hasclk == 1 ]]; then
            echo "create_clock -name clk -period $PERIOD [get_ports clk]"
            echo "set_clock_uncertainty [expr {0.05 * $PERIOD}] [get_clocks clk]"
            cat <<'SDC'
set in_ports [lsearch -all -inline -not -exact [all_inputs] [get_ports clk]]
set_input_delay 0 -clock clk $in_ports
set_output_delay 0 -clock clk [all_outputs]
SDC
        else
            echo "create_clock -name vclk -period $PERIOD"
            echo "set_clock_uncertainty [expr {0.05 * $PERIOD}] [get_clocks vclk]"
            echo 'set_input_delay 0 -clock vclk [all_inputs]'
            echo 'set_output_delay 0 -clock vclk [all_outputs]'
        fi
    } > "$file"
}
failure() {
    printf '%s,"%s",%s,%s,,,,,,,,,%s\n' "$M" "$KIDS" "$HASCLK" "$PERIOD" "$1" >> "$CSV"
    echo "ERROR: $M $1; see results logs"
}
while IFS=$'\t' read -r M HASCLK SOURCE KIDS; do
    echo "=== $M at $PERIOD ps ($SOURCE; clock=$HASCLK; children=$KIDS) ==="
    W="$OUT/work_$M"
    mkdir -p "$W"
    SDC="$OUT/inputs/$M.sdc"
    make_sdc "$SDC" "$HASCLK"
    CONFIG="$OUT/inputs/$M.mk"
    cat > "$CONFIG" <<CFG
export PLATFORM             = asap7
export DESIGN_NAME          = $M
export VERILOG_FILES        = $FILES
export VERILOG_INCLUDE_DIRS = $PROJECT/rtl/include
export SDC_FILE             = $SDC
export ADDITIONAL_LEFS      = $OUT/macros/l1d_macro_data_tdp.lef $OUT/macros/l1d_macro_tag_tdp.lef
export ADDITIONAL_LIBS      = $OUT/macros/l1d_macro_data_tdp.lib $OUT/macros/l1d_macro_tag_tdp.lib
export CORE_UTILIZATION    = 40
export SYNTH_HIERARCHICAL   = 0
CFG
    if ! (cd "$FLOW_HOME" && make DESIGN_CONFIG="$CONFIG" WORK_HOME="$W" synth) > "$OUT/results/synth_$M.log" 2>&1; then
        tail -30 "$OUT/results/synth_$M.log"; failure SYNTH_FAIL; continue
    fi
    NET=$(find "$W" -type f \( -name '1_2_yosys.v' -o -name '1_synth.v' \) -print | sort | head -1)
    if [[ -z $NET ]]; then failure NETLIST_MISSING; continue; fi
    STDLIBS=$(sed -n 's/^read_liberty //p' "$OUT/results/synth_$M.log" | grep -v l1d_macro | sort -u | tr '\n' ' ' || true)
    if [[ -z $STDLIBS ]]; then
        STDLIBS=$(find "$FLOW_HOME/platforms/asap7/lib/NLDM" -name '*RVT_FF*' \( -name '*.lib' -o -name '*.lib.gz' \) -print | sort | tr '\n' ' ')
    fi
    if [[ -z $STDLIBS ]]; then failure LIBRARIES_MISSING; continue; fi
    LIBS="$STDLIBS $OUT/macros/l1d_macro_data_tdp.lib $OUT/macros/l1d_macro_tag_tdp.lib"
    TECH=$(find "$FLOW_HOME/platforms/asap7/lef" -name '*tech*.lef' -print | sort | head -1)
    CELL_LEF=$(find "$FLOW_HOME/platforms/asap7/lef" -name '*sc7p5t*_R_1x*.lef' -print | sort | head -1)
    LEFS="$TECH $CELL_LEF $OUT/macros/l1d_macro_data_tdp.lef $OUT/macros/l1d_macro_tag_tdp.lef"
    printf '%s\n' "$LIBS" > "$OUT/inputs/${M}_libraries.txt"
    printf '%s\n' "$LEFS" > "$OUT/inputs/${M}_lefs.txt"
    if ! LEF_FILES="$LEFS" LIB_FILES="$LIBS" NETLIST="$NET" TOP="$M" SDC_FILE="$SDC" REPORT_PREFIX="$OUT/results/$M" \
        "$OPENROAD" -no_init -exit "$HERE/sta_module.tcl" > "$OUT/results/sta_$M.log" 2>&1; then
        tail -30 "$OUT/results/sta_$M.log"; failure STA_FAIL; continue
    fi
    R=$(grep '^RESULT ' "$OUT/results/sta_$M.log" | tail -1 || true)
    if [[ -z $R ]]; then failure STA_RESULT_MISSING; continue; fi
    get() { sed -n "s/.*$1=\([^ ]*\).*/\1/p" <<< "$R"; }
    SA=$(get slack_all)
    if [[ ! $SA =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then failure NO_TIMING_PATH; continue; fi
    AREA=$(sed -n 's/^Design area \([0-9.]*\) u.*/\1/p' "$OUT/results/sta_$M.log" | head -1)
    printf '%s,"%s",%s,%s,%s,%s,%s,%s,%s,,,%s,ok\n' "$M" "$KIDS" "$HASCLK" "$PERIOD" "$SA" "$(get slack_r2r)" "$(get slack_in2reg)" "$(get slack_reg2out)" "$(get slack_in2out)" "$AREA" >> "$CSV"
    echo "RESULT $M: worst setup slack $SA ps"
    if [[ ${KEEP_WORK:-0} != 1 ]]; then rm -rf "$W"; fi
done < "$OUT/inputs/modules.tsv"
python3 "$HERE/report.py" --csv "$CSV" --output "$OUT/results"
