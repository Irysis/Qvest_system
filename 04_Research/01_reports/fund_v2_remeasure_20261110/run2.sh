#!/usr/bin/env bash
# 재무 v2 재측정 — 2차 시도(2026-11-10). 1차(run.sh)의 경과:
#   06:45 시작 → 07:28 P2R03_E3_RX0 rc 1(DNN 작업자 ArrayMemoryError — 07:14 아침 체인 자가 복구 리프레시의 퀀티 Excel 단계와 겹쳐
#   커밋 한도 · 같은 시간 벤치마크 갱신으로 데이터 지문 다름) → L2 배리어 대기 중 07:55 경 스크립트 소멸(로그에 사유 없음).
#   1차에서 DNN 31개월이 내용 주소 캐시에 들어갔다(그 달 입력이 같으면 재사용 · 다르면 재학습 — v1 예측 재사용 불가는 같다).
# 2차에서 바꾼 것(측정 사양 · 계약 · 순서 원칙은 run.sh 와 같다):
#   ① 배리어 = 이 스크립트의 반복 대기(상태 free 가 될 때까지 · 최대 12시간) — 리프레시가 수급 + 시험 배터리까지 2시간을 넘겨 잡는다
#   ② 재개형 — results/<code>.json 이 ok = true 면 건너뜀 · 1차 실패 파일은 results/attempt1/ 로 옮겨 보존
#   ③ DNN 작업자 3 = PYTHON_CPU_COUNT=4 → min(8, 4 − 1)(1차 4 → 실측 파이썬 합 16 GB · 커밋 66/67.5 GB — 여유 확보 · 결과 무관)
#   ④ 신호 · 종료 기록(trap) — 1차처럼 사유 없이 사라지면 원인을 남긴다
#   ⑤ 세 칸이 같은 데이터 판인지 = 칸마다 시작 · 끝 지문 + 칸끼리 시작 지문 대조(끝에 요약)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
OUT=$ROOT/04_Research/01_reports/fund_v2_remeasure_20261110
RS="/c/Program Files/R/R-4.6.2/bin/Rscript.exe"
export PATH="/c/Program Files/R/R-4.6.2/bin:$PATH"
export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
export QVEST_RP_REGISTER=0 PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2 PYTHON_CPU_COUNT=4 PYTHONUTF8=1
FPS="bash $ROOT/04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/fingerprint.sh"
RB="bash $ROOT/02_Infrastructure/ops/refresh_barrier.sh"
trap 'echo "== $(date +%F" "%T) 신호 HUP 받음"' HUP
trap 'echo "== $(date +%F" "%T) 신호 TERM 받음"; exit 143' TERM
trap 'echo "== $(date +%F" "%T) 신호 INT 받음"; exit 130' INT
trap 'echo "== $(date +%F" "%T) 스크립트 종료 rc=$?"' EXIT
mkdir -p "$OUT/results/attempt1"
for f in "$OUT"/results/P2R03_E3_RX0.*; do [ -f "$f" ] && mv -n "$f" "$OUT/results/attempt1/"; done
echo "== $(date +%F' '%T) 2차 시작 · R $("$RS" -e 'cat(R.version$major, R.version$minor, sep=".")' 2>/dev/null) · PYTHON_CPU_COUNT=$PYTHON_CPU_COUNT · PID $$"
wait_free() {   # 상태 free 가 될 때까지(최대 12시간) — 조회 실패는 기다림으로 센다(fail-closed)
  local t0 s; t0=$(date +%s)
  while :; do
    s=$($RB status 2>/dev/null | head -n 1)
    case "$s" in *state=free*) echo "[배리어] free · 대기 $(( ($(date +%s) - t0) / 60 ))분"; return 0 ;; esac
    if [ $(( $(date +%s) - t0 )) -gt 43200 ]; then echo "[배리어] 12시간 뒤에도 free 아님 — 측정하지 않는다 ($s)"; return 10; fi
    sleep 60
  done
}
m() {   # $1 = 라운드 폴더(저장소 상대) · $2 = 칸 코드
  local spec="$ROOT/$1/specs/$2.json" res="$OUT/results/$2" t0 rc
  if [ -f "$res.json" ] && grep -q '"ok": *true' "$res.json"; then echo "== [$2] 이미 ok — 건너뜀"; return 0; fi
  echo "== $(date +%F' '%T) [$2] 배리어 대기"
  wait_free || return 4
  $FPS equality > "$res.fp_start"; $FPS record > "$res.fpc_start"
  t0=$(date +%s)
  "$RS" "$ROOT/02_Infrastructure/ops/rf_cell_worker.R" "$spec" 1 "$2" "$res.json" > "$res.log" 2> "$res.err.log"
  rc=$?
  $FPS equality > "$res.fp_end"; $FPS record > "$res.fpc_end"
  echo "== $(date +%F' '%T) [$2] rc=$rc · $(( ($(date +%s) - t0) / 60 ))분 · 데이터 지문 $(cmp -s "$res.fp_start" "$res.fp_end" && echo 같음 || echo 다름)"
  return $rc
}
m 04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay P2R03_E3_RX0   # 기저 캐시 미스 → DNN 재학습(1차 31개월 재사용 가능)
m 04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay P2R03_E3_L2    # 같은 기저 — 캐시 적중 예상
m 04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings P2R04_E3_RX0    # 같은 기저 — 캐시 적중 예상
u=$(for c in P2R03_E3_RX0 P2R03_E3_L2 P2R04_E3_RX0; do for t in fp_start fp_end; do f="$OUT/results/$c.$t"; [ -f "$f" ] && tr '\n' '|' < "$f" || echo MISSING; echo; done; done | sort -u | wc -l)
echo "== $(date +%F' '%T) 끝 · 세 칸 시작 · 끝 지문 고유 $u 가지(1 = 같은 데이터 판)"
