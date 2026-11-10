#!/usr/bin/env bash
#==============================================================================
# chain.sh — 총부채(TotalDebt) 수리 체인 (2026-11-10 · 도훈 "팩터 DB의 총부채(TotalDebt) 수리해 0으로 나와")
#
# 순서(어느 단계든 실패하면 멈추고 다음 단계로 가지 않는다):
#   ① 일일 리프레시 잠금(/tmp/qm_daily_refresh.lock) 해제 대기 — 데이터 판 보호(리프레시 도중 재무 정본을 바꾸지 않는다)
#   ② 재무 정본 교체 = 정규 생산기 02_Infrastructure/data/fundamental_produce_v2.R(후보 검사 · 사본 · 교체)
#   ③ 교체된 정본 = 세션이 대조한 후보와 같은가 — 항목별 서명(행 수 · 값 합 · 날짜 합 · candidate_signature.json ·
#      table_signature.py). 다르면 멈춘다(입력이 그 사이 바뀐 것 — 대조 없이 재계산하지 않는다)
#   ④ 영향 팩터 전 기간 재계산 = 02_Infrastructure/factor_db/run_factor_subset_repair.sh --no-wait (명세 repair_spec.json)
#      — 이번 달은 일일 체인 [6a] 가 고친 코드 · 정본으로 짓는다 · IC · 대응표 · 결합용 뷰까지
# 띄우기(세션과 떼어서 · WMI): Invoke-CimMethod Win32_Process Create '"C:\Program Files\Git\bin\bash.exe" -c "bash <이 파일>"'
#==============================================================================
set -u
ROOT="/g/OneDrive/Quant_Module_Moltbot"
export QM_ROOT="G:/OneDrive/Quant_Module_Moltbot"
HERE="$ROOT/04_Research/01_reports/factor_db_debt_fix_20261110"
RS="/c/Program Files/R/R-4.6.2/bin/Rscript.exe"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
STAMP=$(date +%Y%m%d_%H%M%S)
LOG="$ROOT/.cache/scheduler_logs/debt_fix_chain_$STAMP.log"
STATE="$HERE/chain_state.json"
say() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
state() { printf '{"stamp": "%s", "step": "%s", "result": "%s", "note": "%s", "at": "%s", "log": "%s"}\n' \
  "$STAMP" "$1" "$2" "$3" "$(date '+%Y-%m-%dT%H:%M:%S')" "$(printf '%s' "$LOG" | tr '\\' '/')" > "$STATE"; }

say "체인 시작 · 명세 $HERE/repair_spec.json · 후보 서명 $HERE/candidate_signature.json"
state "1_wait" "running" "일일 리프레시 잠금 해제 대기"
n=0
while [ -d /tmp/qm_daily_refresh.lock ]; do
  n=$((n + 1)); [ "$n" -gt 360 ] && { say "① 12시간 기다려도 리프레시 잠금 — 멈춤"; state "1_wait" "fail" "리프레시 잠금 12시간"; exit 1; }
  sleep 120
done
say "① 리프레시 잠금 해제 확인"

state "2_produce" "running" "재무 정본 교체(fundamental_produce_v2.R)"
"$RS" --no-save "$(cygpath -m "$ROOT/02_Infrastructure/data/fundamental_produce_v2.R")" >> "$LOG" 2>&1; rc=$?
say "② 재무 정본 교체 rc=$rc"
[ "$rc" -eq 0 ] || { state "2_produce" "fail" "fundamental_produce_v2.R rc=$rc — 정본 그대로(생산기가 교체 전에 멈춘다)"; exit 1; }

state "3_compare" "running" "교체된 정본 = 대조한 후보?"
"$PY" -I -X utf8 "$(cygpath -w "$HERE/table_signature.py")" --check "$(cygpath -w "$ROOT/.cache/fundamental_merged.parquet")" \
  "$(cygpath -w "$ROOT/.cache/fundamental_xlsx.parquet")" "$(cygpath -w "$HERE/candidate_signature.json")" >> "$LOG" 2>&1
rc=$?
say "③ 대조 rc=$rc"
[ "$rc" -eq 0 ] || { state "3_compare" "fail" "교체된 정본이 대조한 후보와 다르다 — 재계산 안 함(사본: .cache/fundamental_backup 최신)"; exit 1; }

state "4_repair" "running" "영향 팩터 전 기간 재계산(run_factor_subset_repair.sh --no-wait)"
QVEST_RFS_SPEC="$(cygpath -m "$HERE/repair_spec.json")" bash "$ROOT/02_Infrastructure/factor_db/run_factor_subset_repair.sh" --no-wait --workers 3 >> "$LOG" 2>&1; rc=$?
say "④ 재계산 rc=$rc"
SUM=$(ls -t "$ROOT"/.cache/scheduler_logs/factor_subset_repair_*.json 2>/dev/null | head -n 1)
[ "$rc" -eq 0 ] || { state "4_repair" "fail" "run_factor_subset_repair.sh rc=$rc · 요약 $SUM"; exit 1; }
state "done" "ok" "재계산 끝 · 요약 $SUM"
say "체인 끝"
exit 0
