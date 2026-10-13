#!/usr/bin/env bash
# P0R01 측정 스케줄 — ① E2_C0(DNN 기저 · 기저 캐시 시드) 단독 백그라운드 + E1 7칸 2병렬 ② E2_C0 끝나면 E2·E3 나머지 13칸 3병렬
# 실행: bash measure_all.sh  (로그 = measure_all.log)
set -u
RD=/c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P0_FRONTIER/P0R01_feasibility_map
cd /c/Users/99922/OneDrive/Quant_Module_Moltbot || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
m() { Rscript "$RD/measure_cell.R" "$1" 2>&1 | grep -E "^\[측정\]|Error|에러|멈" | sed "s/^/[$1] /"; }
export -f m; export RD
echo "== $(date +%F' '%T) 시작 =="
( m P0R01_E2_C0; echo "== $(date +%F' '%T) E2_C0 끝 ==" ) &
P_E2C0=$!
printf "%s\n" P0R01_E1_C0 P0R01_E1_C1 P0R01_E1_C2 P0R01_E1_C3 P0R01_E1_C4 P0R01_E1_C5 P0R01_E1_C6 | xargs -P 2 -I{} bash -c 'm {}'
echo "== $(date +%F' '%T) E1 7칸 끝 — E2_C0 대기 =="
wait $P_E2C0
printf "%s\n" P0R01_E2_C1 P0R01_E2_C2 P0R01_E2_C3 P0R01_E2_C4 P0R01_E2_C5 P0R01_E2_C6 \
              P0R01_E3_C0 P0R01_E3_C1 P0R01_E3_C2 P0R01_E3_C3 P0R01_E3_C4 P0R01_E3_C5 P0R01_E3_C6 | xargs -P 3 -I{} bash -c 'm {}'
echo "== $(date +%F' '%T) 전체 끝 =="
