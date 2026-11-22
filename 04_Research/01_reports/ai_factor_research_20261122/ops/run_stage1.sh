#!/usr/bin/env bash
# run_stage1.sh — 단계 1 을 차례로 돌린다: ① 측정기 자가 시험 + 이미 만든 새 팩터 6개 ② 기존 팩터 DB 비교 기준.
#   각 작업은 감시 셸(aif_run.py)이 띄운다 — 출발 조건을 기다리고, 낮은 우선순위로 돌리고, 진행 알림을 보낸다.
#   앞 작업이 실패하면 뒤 작업은 돌리지 않는다. 다시 띄우면 끝난 단위는 건너뛴다.
#   사용: bash ops/run_stage1.sh [--no-notify]
set -u
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"      # 윈도 형식 경로(파이썬 · Rscript 에 넘긴다)
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\\//}"
[ -n "$ROOT" ] || { echo "[run_stage1] QM_ROOT 가 없다"; exit 2; }
PY="${QVEST_PY:-python}"; PY="${PY//\\//}"
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
OUT="$ROOT/.cache/aif_research"
EXTRA=("$@")

"$PY" -X utf8 "$RD/ops/aif_run.py" --job perf --stage perf_base --summary "$OUT/stage_summary_perf_new.json" "${EXTRA[@]}" -- "$RS" --vanilla "$RD/run/01_stage1_new_factors.R"
rc=$?; [ $rc -eq 0 ] || { echo "[run_stage1] 앞 작업 실패 rc=$rc — 멈춘다"; exit $rc; }
"$PY" -X utf8 "$RD/ops/aif_run.py" --job perf --stage perf_base --summary "$OUT/stage_summary_perf_db.json" "${EXTRA[@]}" -- "$RS" --vanilla "$RD/run/02_stage1_factor_db.R"
rc=$?; echo "[run_stage1] 끝 rc=$rc"; exit $rc
