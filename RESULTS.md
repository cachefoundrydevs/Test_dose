# ASAP7 synthesis + place and route

Ideal-wire assumptions removed: placement, clock tree and routing are done. SRAM macros are ESTIMATES
(no ASAP7 memory compiler). I/O delay 0, clock uncertainty 5 %. Fmax = 1000 / (period - worst setup slack).

| top | corner | period ps | synth | pnr | last stage | setup WS ps | TNS ps | hold WS ps | area um2 | Fmax GHz |
|---|---|---|---|---|---|---|---|---|---|---|
| l1d_bank | BC | 250 | 0 | 2 | 5_1_grt.json | -786.796 | -4571890.0 | -346.719 | 39721 | 0.965 |
| l1d_bank | BC | 350 | 0 | 2 | 5_1_grt.json | -696.627 | -3011430.0 | -337.01 | 38951.2 | 0.955 |
| l1d_bank | TC | 250 | 0 | 2 | 5_1_grt.json | -938.924 | -6962240.0 | -427.621 | 39914.8 | 0.841 |
| l1d_bank | TC | 350 | 0 | 2 | 5_1_grt.json | -988.523 | -5684790.0 | -426.619 | 39377.3 | 0.747 |

Exit code 0 = stage finished; na = not started. Per-stage slacks:

- l1d_bank BC 250 ps: 2_1_floorplan [-327.5], 3_3_place_gp [-563.3], 3_4_place_resized [-563.3], 3_5_place_dp [-557.0], 4_1_cts [-869.3], 5_1_grt [-786.8]
- l1d_bank BC 350 ps: 2_1_floorplan [-232.5], 3_3_place_gp [-448.6], 3_4_place_resized [-448.6], 3_5_place_dp [-441.4], 4_1_cts [-784.7], 5_1_grt [-696.6]
- l1d_bank TC 250 ps: 2_1_floorplan [-538.6], 3_3_place_gp [-700.7], 3_4_place_resized [-700.7], 3_5_place_dp [-685.8], 4_1_cts [-981.8], 5_1_grt [-938.9]
- l1d_bank TC 350 ps: 2_1_floorplan [-443.6], 3_3_place_gp [-669.7], 3_4_place_resized [-669.7], 3_5_place_dp [-669.2], 4_1_cts [-1093.2], 5_1_grt [-988.5]
