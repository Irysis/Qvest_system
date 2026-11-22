#!/usr/bin/env bash
# run_generator.sh — 생성기 하나(파이썬)와 그 팩터 묶음의 성과 측정(R)을 차례로 돌린다(단계 3 · 4 공용).
#   각 작업은 감시 셸(aif_run.py)이 띄운다. 생성이 실패하면 측정은 돌리지 않는다. 다시 띄우면 끝난 단위는 건너뛴다.
#   사용: bash ops/run_generator.sh <작업 키> <단계 키> <파이썬 스크립트> <묶음 이름> <표 제목 머리말> [--no-notify]
#   예:   bash ops/run_generator.sh enumerate enumerate aif_enumerate.py enumerate "체계적 열거 팩터"
#   약속: 생성기는 .cache/aif_research/manifest_<묶음>.json 을 쓰고, 측정 결과는 results/stage3_<묶음>/ 에 놓인다.
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
[ $# -ge 5 ] || { echo "사용: run_generator.sh <작업 키> <단계 키> <파이썬 스크립트> <묶음 이름> <표 제목 머리말> [--no-notify]"; exit 2; }
JOB="$1"; STAGE="$2"; SCRIPT="$3"; SETN="$4"; LABEL="$5"; shift 5
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\//}"
[ -n "$ROOT" ] || { echo "[run_generator] QM_ROOT 가 없다"; exit 2; }
PY="${QVEST_PY:-python}"; PY="${PY//\//}"
VPY="${AIF_GEN_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"      # 생성기 실행 환경(수식 탐색은 전용 환경을 AIF_GEN_PY 로 넘긴다)
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
OUT="$ROOT/.cache/aif_research"
EXTRA=("$@")

"$PY" -X utf8 "$RD/ops/aif_run.py" --job "$JOB" --stage "$STAGE" "${EXTRA[@]}" -- "$VPY" -X utf8 "$RD/py/$SCRIPT"
rc=$?; [ $rc -eq 0 ] || { echo "[run_generator] 생성 실패 rc=$rc — 멈춘다"; exit $rc; }
"$PY" -X utf8 "$RD/ops/aif_run.py" --job perf --stage "$STAGE" --summary "$OUT/stage_summary_stage3_$SETN.json" "${EXTRA[@]}" -- "$RS" --vanilla "$RD/run/05_measure_set.R" "--manifest=$OUT/manifest_$SETN.json" "--set=stage3_$SETN" "--stage=$STAGE" --from=0.9 --to=1 "--label=$LABEL"
rc=$?; echo "[run_generator] 끝 rc=$rc"; exit $rc
}
main "$@"; exit $?
