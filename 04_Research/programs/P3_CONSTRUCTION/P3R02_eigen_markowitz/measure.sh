#!/usr/bin/env bash
# P3R02 측정 — 밤 파이프라인(P0R01 · P3R01 · P2R02 · P1R01) 끝 표식 뒤에만(메모리 경합 회피) · precheck 통과 시에만.
#   칸 4 = M5 2(카탈로그 등재) + RX0 2(같은 배치 기준 재측정 · QVEST_RP_REGISTER=0 — P0R01 C0 와 같은 모듈 중복 등재 방지).
#   ★같은 엔진 쌍(M5 · RX0)은 함께 시작한다(E1 쌍 → E2 쌍 · 쌍 안 2병렬) — 쌍이 서로 다른 데이터 판본이 되지 않게(재점검 권고 ④).
#   칸마다 시작 · 종료 데이터 지문(RAWDATA · 벤치 캐시 크기 · mtime)을 results/<code>.fp_start · .fp_end 에 남긴다 —
#   evaluate.R 은 쌍 안 지문 4개가 모두 같을 때만 판정한다(다르면 그 쌍 재측정 · rules.vintage_pair).
#   이미 ok 인 칸은 rk_measure_cell 이 건너뛰므로 지문도 다시 쓰지 않는다(측정 당시 지문 보존).
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz
PRE=stage_artifacts/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/prereg.json
ST=$ROOT/04_Research/programs/_lib/night_state
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
echo "== $(date +%F' '%T) 밤 파이프라인 끝 대기 =="
until [ -f "$ST/pipeline.done" ]; do sleep 60; done
echo "== $(date +%F' '%T) precheck =="
Rscript $ROOT/$RDR/precheck.R || { echo "== $(date +%F' '%T) precheck 불일치 — 측정하지 않는다 =="; exit 3; }
mkdir -p "$ROOT/$RDR/results"
fp() { stat -c '%n %s %Y' "$ROOT/.cache/RAWDATA.parquet" "$ROOT/.cache/benchmark.parquet" 2>&1 | sed "s#^$ROOT/##"; }
m() {
  local res="$ROOT/$RDR/results/$1"
  if [ -f "$res.json" ] && grep -q '"ok": *true' "$res.json"; then echo "[$1] [측정] 이미 있음(지문 보존)"; return 0; fi
  if [[ "$1" == *_RX0 ]]; then export QVEST_RP_REGISTER=0; else unset QVEST_RP_REGISTER; fi
  fp > "$res.fp_start"
  Rscript $ROOT/04_Research/programs/_lib/measure_round_cell.R "$RDR" "$PRE" "$1" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$1] /"
  fp > "$res.fp_end"
}
export -f m fp; export ROOT RDR PRE
for pair in "P3R02_E1_M5 P3R02_E1_RX0" "P3R02_E2_M5 P3R02_E2_RX0"; do
  echo "== $(date +%F' '%T) 쌍 시작: $pair =="
  printf "%s\n" $pair | xargs -P 2 -I{} bash -c 'm {}'
done
echo "== $(date +%F' '%T) 전체 끝 =="
touch $ST/p3r02_measured.done
