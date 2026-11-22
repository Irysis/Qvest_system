#!/usr/bin/env bash
# run_queue_long.sh — 오래 걸리는 생성기 둘을 차례로 돌리고 종합 보고로 끝낸다: 트리 AutoML(끝에 두 팔 평균) → 수식 탐색 3판 → 종합 보고. 한 번에 하나 · 앞이 실패해도 뒤는 돌린다.
#   사용: bash ops/run_queue_long.sh [--no-notify]
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\\//}"
[ -n "$ROOT" ] || { echo "[run_queue_long] QM_ROOT 가 없다"; exit 2; }
fail=0
G() { bash "$SD/ops/run_generator.sh" "$@"; }
G tree_automl tree_automl aif_tree.py tree "트리 AutoML 예측 팩터" "$@" || { echo "[run_queue_long] 트리 AutoML 에서 실패 — 수식 탐색으로 간다"; fail=1; }
AIF_GEN_PY="$ROOT/.venv_gp_alpha/Scripts/python.exe" G gp_v3 gp_v3 aif_gp.py gp "수식 탐색 3판 팩터" "$@" || { echo "[run_queue_long] 수식 탐색에서 실패"; fail=1; }
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"
PY="${QVEST_PY:-python}"; PY="${PY//\\//}"
# 종합 보고 — 끝난 묶음 전부를 한 파일 보고서로 모으고 텔레그램 최종 브리핑을 보낸다(생성기가 실패했어도 끝난 것까지로 만든다)
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
"$PY" -X utf8 "$RD/ops/aif_run.py" --job perf --stage final_report --summary "$ROOT/.cache/aif_research/stage_summary_final.json" "$@" -- "$RS" --vanilla "$RD/run/07_final_report.R" --stage=final_report || { echo "[run_queue_long] 종합 보고에서 실패"; fail=1; }
echo "[run_queue_long] 끝 fail=$fail"; exit $fail
}
main "$@"; exit $?
