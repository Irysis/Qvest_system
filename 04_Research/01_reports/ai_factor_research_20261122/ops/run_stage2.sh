#!/usr/bin/env bash
# run_stage2.sh — 단계 2(전 자료 단말 계층)를 차례로 돌린다.
#   ① 공통 틀과 기존 팩터 특성 내보내기(R · run/03_export_frame.R)
#   ② 단말 패널 적재와 기본 특성 집합(파이썬 · py/aif_terminals.py — 파일이 있을 때만)
#   각 작업은 감시 셸(aif_run.py)이 띄운다. 앞 작업이 실패하면 뒤 작업은 돌리지 않는다. 다시 띄우면 끝난 단위는 건너뛴다.
#   사용: bash ops/run_stage2.sh [--no-notify]
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"      # 윈도 형식 경로(파이썬 · Rscript 에 넘긴다)
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\\//}"
[ -n "$ROOT" ] || { echo "[run_stage2] QM_ROOT 가 없다"; exit 2; }
PY="${QVEST_PY:-python}"; PY="${PY//\\//}"                             # 감시 셸용(표준 라이브러리만)
VPY="$ROOT/.venv_qvest_ml/Scripts/python.exe"                          # 작업용(numpy · pyarrow · pandas)
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
EXTRA=("$@")

"$PY" -X utf8 "$RD/ops/aif_run.py" --job terminals --stage terminals "${EXTRA[@]}" -- "$RS" --vanilla "$RD/run/03_export_frame.R"
rc=$?; [ $rc -eq 0 ] || { echo "[run_stage2] 틀 내보내기 실패 rc=$rc — 멈춘다"; exit $rc; }
if [ -f "$RD/py/aif_terminals.py" ]; then
  "$PY" -X utf8 "$RD/ops/aif_run.py" --job terminals --stage terminals --summary "$ROOT/.cache/aif_research/stage_summary_terminals.json" "${EXTRA[@]}" -- "$VPY" -X utf8 "$RD/py/aif_terminals.py"
  rc=$?
fi
echo "[run_stage2] 끝 rc=$rc"; exit $rc
}
main "$@"; exit $?
