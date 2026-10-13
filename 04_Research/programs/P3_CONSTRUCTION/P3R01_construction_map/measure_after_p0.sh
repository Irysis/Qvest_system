#!/usr/bin/env bash
# P3R01 측정 — P0R01 측정이 끝난 뒤(메모리 · E2 기저 캐시 시드) 10칸 3병렬
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
P0LOG=$ROOT/04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/measure_all.log
RDR=04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map
PRE=stage_artifacts/programs/P3_CONSTRUCTION/P3R01_construction_map/prereg.json
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
echo "== $(date +%F' '%T) P0 측정 끝 대기 =="
until grep -q "전체 끝" "$P0LOG" 2>/dev/null; do sleep 30; done
echo "== $(date +%F' '%T) P3R01 측정 시작 =="
m() { Rscript $ROOT/04_Research/programs/_lib/measure_round_cell.R "$RDR" "$PRE" "$1" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$1] /"; }
export -f m; export ROOT RDR PRE
printf "%s\n" P3R01_E1_K1 P3R01_E1_K2 P3R01_E1_K3 P3R01_E1_K4 P3R01_E1_K5 \
              P3R01_E2_K1 P3R01_E2_K2 P3R01_E2_K3 P3R01_E2_K4 P3R01_E2_K5 | xargs -P 3 -I{} bash -c 'm {}'
echo "== $(date +%F' '%T) 전체 끝 =="
