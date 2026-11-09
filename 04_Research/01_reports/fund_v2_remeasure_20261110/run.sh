#!/usr/bin/env bash
# 재무 v2 재측정 — 등급 v3.3 재채점(11-10)에서 A 가 된 3칸(P2R03_E3_RX0 · P2R03_E3_L2 · P2R04_E3_RX0)
#   왜: 세 칸은 재무 v1(결함) 위에서 잰 값이다 — decision_register FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109 ③
#       '인용 · 풀 · BOOK · 라운드 재료로 쓸 때는 v2 팩터 DB 로 다시 잰 값만'. 도훈 11-10 '지금 재측정'.
#   절차 = 라운드 measure.sh 의 칸 측정 m() 과 같은 순서 — 배리어 대기 → 시작 지문 → 정본 셀 작업자(rf_cell_worker.R) → 끝 지문.
#   사양 = 사전등록 그대로(md5 대조 = 사전 점검 · 이 폴더 README). 원 라운드와 다른 점(측정 사양 · 계약은 같다):
#     ① 결과 = 이 폴더 results/ (닫힌 라운드의 results/ · 판정 기록은 건드리지 않는다 · 새 측정 폴더 = stage_artifacts/replication/<새 run_id>)
#     ② 카탈로그 · 팩터 등재 없음 — QVEST_RP_REGISTER=0(세 칸 모두 · 원 라운드는 RX0 만)
#     ③ R = 4.6.2 정본 경로 직접(앱 세션 PATH 는 옛 4.5.2) · DNN 작업자 4 = PYTHON_CPU_COUNT=5 → min(8, 5 − 1)
#        (메인 PC 32 GB · 작업자 8 추산 25~33 GB(project-main-pc-ram-benchmark) · 달마다 독립 학습 · 시드 · 내용 주소 캐시라 작업자 수는 결과와 무관)
#     ④ GPU 할당기 = roundup_power2_divisions:2 (10-18 measure_now_vram.sh 와 같다 — 커지는 달 텐서의 세그먼트 재사용)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
OUT=$ROOT/04_Research/01_reports/fund_v2_remeasure_20261110
RS="/c/Program Files/R/R-4.6.2/bin/Rscript.exe"
export PATH="/c/Program Files/R/R-4.6.2/bin:$PATH"
export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
export QVEST_RP_REGISTER=0 PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2 PYTHON_CPU_COUNT=5 PYTHONUTF8=1
FPS="bash $ROOT/04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/fingerprint.sh"
mkdir -p "$OUT/results"
echo "== $(date +%F' '%T) 시작 · R $("$RS" -e 'cat(R.version$major, R.version$minor, sep=".")' 2>/dev/null) · PYTHON_CPU_COUNT=$PYTHON_CPU_COUNT · PID $$"
m() {   # $1 = 라운드 폴더(저장소 상대) · $2 = 칸 코드
  local spec="$ROOT/$1/specs/$2.json" res="$OUT/results/$2" t0 rc
  echo "== $(date +%F' '%T) [$2] 배리어 대기"
  bash "$ROOT/02_Infrastructure/ops/refresh_barrier.sh" wait 7200 60 | sed "s/^/[배리어] /"
  if [ "${PIPESTATUS[0]}" = "10" ]; then echo "== $(date +%F' '%T) [$2] 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다"; return 4; fi
  $FPS equality > "$res.fp_start"; $FPS record > "$res.fpc_start"
  t0=$(date +%s)
  "$RS" "$ROOT/02_Infrastructure/ops/rf_cell_worker.R" "$spec" 1 "$2" "$res.json" > "$res.log" 2> "$res.err.log"
  rc=$?
  $FPS equality > "$res.fp_end"; $FPS record > "$res.fpc_end"
  echo "== $(date +%F' '%T) [$2] rc=$rc · $(( ($(date +%s) - t0) / 60 ))분 · 데이터 지문 $(cmp -s "$res.fp_start" "$res.fp_end" && echo 같음 || echo 다름)"
  return $rc
}
m 04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay P2R03_E3_RX0   # 기저 캐시 미스 예상 → DNN 재학습(길다)
m 04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay P2R03_E3_L2    # 같은 기저 — 캐시 적중 예상
m 04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings P2R04_E3_RX0    # 같은 기저 — 캐시 적중 예상
echo "== $(date +%F' '%T) 끝"
