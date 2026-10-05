#!/usr/bin/env bash
# 교정 몬테카를로 드라이버 — wave 단위 병렬(단일 스레드 R 프로세스) · 출력 = work/calib/*.csv
set -uo pipefail
D=/c/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/a_lever/DRAFT2
source /c/tmp/aldraft2/renv.sh; cd /c/tmp/aldraft2
S="$(cygpath -w $D/tools/calib_deep_capture.R)"; O="$(cygpath -w $D/work/calib)"
job() { "$RS" "$S" C:/tmp/aldraft2/sbx "$O/$1.csv" "$2" "$3" "$4" ${5:-} > "$D/work/calib/$1.log" 2>&1; }
if [ "${1:-1}" = 1 ]; then
  for sc in real_norm real_t5het real_t5het_ar; do
    job cal_${sc}_a $sc 1 1000 & job cal_${sc}_b $sc 1001 2000 & job hold_${sc} $sc 2001 3000 &
  done
  job adv_B adv_B 1 1000 &
  wait
else
  job syn_n520 syn_n520 1 400 & job syn_n1040 syn_n1040 1 300 &
  for b in 1 7 12 24; do job blk_$b blk_$b 1 $([ $b = 1 ] && echo 300 || echo 600) & done
  for dl in 0.15 0.30 0.45; do job pow_$dl real_t5het 3001 3600 $dl & done
  wait
fi
echo "wave ${1:-1} done $(date)"
