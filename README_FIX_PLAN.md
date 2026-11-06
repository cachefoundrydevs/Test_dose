# How to fix Test_dose: GOD RULE, coding rules, 4-cycle hit

Written 2026-11-06. This is the work plan. Nothing in it is done yet. When the user says "fix", start at section 6 and go in order.

## 0. Status update (2026-11-06, later the same day)
Done since this plan was written (code only; the timing fix of section 6 is still NOT started):
- **Bank split by stage** (commit `4474c9c`): `l1d_bank` is now a thin wrapper around `l1d_bank_fifo_s0`, `l1d_bank_r`, `l1d_bank_s1`, `l1d_bank_s2`, `l1d_bank_s3`, so each stage can be timed alone. Same behaviour; 37 of 37 tests passed.
- **VPU port** (commit `8437ff2`): with `HAS_VPU = 1` (default) port 3 is a 512-bit vector load / store port (`vpu_req_*`, `vpu_resp_*`, whole line, no byte mask). The request packet is 146 bits (new `line` bit); the 512-bit store line goes beside it into a 2-place per-bank buffer (`l1d_vec_store_buf`); the VPU response merger is 586 bits wide. New test `tb_ports_vpu` (4 runs). 41 of 41 tests passed, lint 0 errors, `tb_latency` still 4 / 4.
- **Per-module timing** (commit `9b2cc40`): the ASAP7 per-module job now covers all 42 RTL modules including the six new ones. Started, not read yet.
- Known cost of the VPU choice: only 2 vector data places per bank (a vector store can wait at the bank door), and a vector miss is fetched then retried; mean vector latency under load in the tests was about 120 cycles, a hit is 4.
- GR-1 is still not met; nothing new is timed after place and route.

## 1. What must be true at the end

| Rule | Text | Source |
|---|---|---|
| GOD RULE (GR-1) | Every stage of a process with a promised cycle count completes in **under 240 ps, flop to flop**, at 4 GHz or faster, **after place and route, with positive slack**. No stage or cycle is added, no frequency is traded, no function is lost. It is met by rework: fewer logic levels, a restructured stage. A change that misses it is **not finished**; name the gap in ps. | `Data_Cache_HPC/DESIGN_RULES.md` |
| Hit latency | **Load hit and store hit: 4 cycles** at the bank pins in an idle bank (user decision 2026-11-06; the upper limit in LAT-1 is 6, 4 is the target and the tests already expect 4). Other request classes stay fast: miss, AMO, LR/SC, snoop, prefetch, NC. | `tb_latency`, `DESIGN_RULES.md` LAT-1 |
| Function | Never dropped or changed. All tests keep passing. | `DESIGN_RULES.md` |
| Coding rules | Section 5 below. | `Data_Cache_HPC/CODING_RULES.md`, root `CLAUDE.md` |

A 4-cycle hit has 4 stages, so 4 x 240 ps. Each stage has a clock-to-Q, logic and setup cost inside its 240 ps, so it gets only a few logic levels.

## 2. Where we are (facts from the `pnr-results` branch, commit `7e82328`)

ASAP7, `l1d_bank`, after global route. SRAM macros are **estimates** (no ASAP7 memory compiler). I/O delay was 0.

| Corner | Period ps | Setup WS ps | Hold WS ps | Fmax GHz |
|---|---|---|---|---|
| BC | 250 | -787 | -347 | 0.97 |
| BC | 350 | -697 | -337 | 0.96 |
| TC | 250 | -939 | -428 | 0.84 |
| TC | 350 | -989 | -427 | 0.75 |

Functional tests (`results` branch): all `RESULT` lines OK, load hit 4 cycles, store hit 4 cycles. So the **function is right and the timing is far off**.

Worst path (BC 250): `u_vc.lk_addr_q[4]` (flop) -> about 25 gates and 12 repeater buffers -> pin `lsu_response_packet[7]`. Data path about 675 ps. Allowed 240 ps. Real GR-1 gap about **435 ps** on this one path.

Why the reported -787 ps is not the full truth (two causes, kept apart):
1. **Real RTL gap**, about 435 ps on the worst path: a victim-cache lookup (match, first-match, encode, mux) is combinational all the way to an output pin.
2. **Constraint gap**, about 350 ps: the clock tree takes about 350 ps to reach the flops, but `flow/run_pnr.sh` lines 34 to 37 constrain the pins against an ideal 0 ps clock (`set_input_delay 0`, `set_output_delay 0`). This makes setup look worse and makes hold fail (-347 ps) for input pins. This is a flow error, not an RTL error.

Not known yet (do not guess): how many other endpoints fail and which cones they belong to. Section 6 step 2 finds out.

## 3. The plan in one picture

```
 flow fix  ->  list all violating endpoints  ->  group them into cones  ->  rework one cone at a time
 (honest        (top 200 + per-stage            (VC lookup, queue          (RTL change -> tests ->
  numbers)       flop-to-flop table)             picks, resp mux, ...)       synthesis -> PnR -> ps table)
```

## 4. Fix recipes for the RTL (use in this order)

**R1. Register at the stage end.** Any value that goes to an output pin, to another stage, or into a long cone comes out of a flop. No logic between the last flop and a pin. Example: `lookup_hit`, `lookup_slot`, `lookup_slot_state`, `lookup_dirty`, `lookup_shared` in `rtl/bank/miss/l1d_victim_cache.v` (lines 75 to 110) are built from `lk_addr_q` with a priority loop and are used combinationally.

**R2. One-hot select, no encode and decode.** Keep a match vector one-hot and use an AND-OR mux (`|(match & data)`). Do not do match -> priority chain -> binary index -> decode again. A priority chain over N slots (`lk_first` loop) is N levels deep; make it a parallel prefix or remove the need (a line can match at most one slot, so assert that and drop the priority).

**R3. Move the compare earlier.** Do the tag/address compare in the stage that already reads the tags, and register the match. The next stage then only muxes.

**R4. Cut fan-out.** A signal with fan-out above about 8 gets a duplicated flop (one copy per consumer group) instead of a buffer tree. The report shows 12 repeaters on one path, which means high fan-out nets.

**R5. Split wide ANDs and ORs into a balanced tree** (2 or 3 input gates, depth log2). The path above has OR3 and OA211 chains that are linear.

**R6. Precompute in the previous cycle** what is known early (valid bits, state decode, way select) and register it. Speculation is allowed if there is a recovery path (rule F-0).

**R7. Never meet timing by adding a pipeline stage or removing a function.** If a cone cannot fit, move work between the existing stages. If it truly cannot, stop and tell the user the gap in ps; do not hide it.

## 5. Coding rules check (every touched file, state the result in the reply)

From `CODING_RULES.md` and the root `CLAUDE.md`. Old code is **not exempt**: when a file is touched, bring it up to date or list what is left.

| Check | Rule |
|---|---|
| Verilog-2005 in RTL; SystemVerilog only in testbenches and assertion bind files | root `CLAUDE.md` |
| One module per file, one file per module type; repeated blocks via `generate for` with an index parameter (`BANK_ID`) | root `CLAUDE.md` |
| `` `default_nettype none ``, include guards, synchronous reset, no latches, SRAM only behind the SRAM wrapper | root `CLAUDE.md` |
| Parameters first in the module, each with its default in the comment (`parameter SETS = 64, // default 64: sets per bank`) | V-7.10 |
| Every size and width parameterised, derived with `$clog2`; no numeric size literals inside modules | root `CLAUDE.md` |
| Width comment with the exact default value (`reg [TAG_W-1:0] tag_q; // TAG_W = 50 bits`) | P8 |
| Names say the job (no `lk_`, `q`, `excl`, `tmp`, `b2`, `a_g`); standard short words only | V-2.16, V-2.17, V-2.18 |
| Module header: purpose in simple words, ports table, parameter table, worked example; every port, register and block commented | V-1.7, V-6.13 |
| Testbenches stay plain Verilog (no SV classes) so Icarus, Verilator and Vivado xsim run them; every new test goes into `tests.txt` | root `CLAUDE.md` |

Known gaps against these rules (seen while reading, not yet counted): `l1d_victim_cache.v` uses short names (`lk_*`, `q`, `excl`, `st`, `dty`, `shr`, `iss`), and has no header table or width comments. Expect the same in other files; count them in step 3.

## 6. Work steps (do them in this order when the user says "fix")

1. **Flow honesty** (`flow/run_pnr.sh`). Set the pin constraints against the clock tree (input and output delay as a real budget, or `set_clock_latency` for the ports). Add a flop-to-flop report (`report_checks -from [all_registers] -to [all_registers]`). Print WNS per stage in `summarize.py`. Mark macro numbers as estimates. Do not claim a pass from this step alone.
2. **List the real gaps.** Dump every violating endpoint (`report_checks -group_path_count 200`, unique endpoints) from a PnR or synthesis run. Group by startpoint and endpoint cone. Write the table (cone, stage, ps over 240) into a new file `TIMING_GAPS.md`. Add the same gaps to the known-gaps list in `DESIGN_RULES.md` (that file is in `Data_Cache_HPC`; ask the user before editing it there).
3. **Count coding-rule gaps** per file (section 5 table) into `CODING_GAPS.md`.
4. **Fix cone by cone**, worst first (the victim-cache lookup to the response pin first). For each cone: apply recipes R1 to R7, bring the file up to the coding rules, run all tests in `tests.txt`, run synthesis (minutes) for a quick ps check, then a PnR run to confirm.
5. **After every cone**, reply with the per-stage ps table and the rule check (pass, or gap in ps / rule number). Never report finished with a gap open.
6. **Keep the 4-cycle hit.** `tb_latency` must keep printing load hit 4 and store hit 4. If a rework changes a latency, stop and tell the user.
7. **Done means:** every stage under 240 ps flop to flop at 4 GHz or faster after place and route with positive setup slack **and** non-negative hold slack, all tests pass, load hit and store hit 4 cycles, all coding checks pass.

## 7. How to improve the Test_dose code (beyond timing)

- **Delete duplicate and dead logic** the lint log reports (`logs/lint.log` on the `results` branch).
- **Assertions** (SystemVerilog bind files, testbench only): one-hot match vectors, no response without a request, victim cache slot never matches twice. They also justify dropping the priority chain in R2.
- **Latency regression**: keep `tb_latency` and add checks for store hit, hit behind a refill, AMO and snoop so a rework cannot slow a class unnoticed.
- **Seeds**: the random coherence tests already run several seeds (`tests.txt`); add more seeds to run every push.
- **One timing script** (`flow/summarize.py`) that writes the per-stage ps table to `RESULTS.md`, so reading the result needs no manual log digging.
- **Cost**: PnR runs take hours. Use synthesis for the loop and PnR to confirm. The GitHub Actions run of an earlier repo was blocked by a billing problem; check that first.

## 8. Commands

```
# run all tests locally is not possible on this machine (no Icarus, Verilator, Vivado);
# push and read the `results` branch:
git fetch origin results && git show origin/results:logs/status.txt   # 0 = pass
git fetch origin pnr-results && git show origin/pnr-results:RESULTS.md
```

PnR runs when anything under `flow/` changes (`.github/workflows/pnr.yml`). Tests run on every push (`test.yml`).

## 9. Rules for whoever fixes this

- Do not weaken a test, a rule or a constraint to make a number pass.
- Separate facts from estimates in every reply; name the gap in ps.
- Never write tokens or passwords into any file.
- Commit and push after each finished cone, staging only the files touched.
