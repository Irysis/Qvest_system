#!/usr/bin/env bash
# run_smokes.sh — 긴 실행 전에 생성기들의 코드 경로를 짧게 시험한다(승인 계획 '사전 스모크'). 알림 없음 · 산출은 '<이름>_smoke' 폴더.
#   순서: 특징 부스팅(한 해) → 신경망(한 해 · GPU) → 트리 AutoML(한 해) → 수식 탐색 일별 단말 패널(본 실행 · 자가 시험 포함) → 수식 탐색(두 해 · 작은 개체군)
#   하나라도 실패하면 멈춘다. 사용: bash ops/run_smokes.sh
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\\//}"
[ -n "$ROOT" ] || { echo "[run_smokes] QM_ROOT 가 없다"; exit 2; }
PY="${QVEST_PY:-python}"; PY="${PY//\\//}"
VPY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
GPY="$ROOT/.venv_gp_alpha/Scripts/python.exe"
run() { local job="$1" stage="$2"; shift 2; "$PY" -X utf8 "$RD/ops/aif_run.py" --job "$job" --stage "$stage" --no-notify -- "$@"; local rc=$?; echo "[run_smokes] $job rc=$rc"; return $rc; }
run feature_boost feature_boost "$VPY" -X utf8 "$RD/py/aif_fboost.py" --smoke || exit 1
run neural_net neural_net "$VPY" -X utf8 "$RD/py/aif_nn.py" --smoke || exit 1
run tree_automl tree_automl "$VPY" -X utf8 "$RD/py/aif_tree.py" --smoke || exit 1
run terminals gp_v3 "$VPY" -X utf8 "$RD/py/aif_gp_panel.py" || exit 1
run gp_v3 gp_v3 "$GPY" -X utf8 "$RD/py/aif_gp.py" --smoke || exit 1
echo "[run_smokes] 전부 통과"
}
main "$@"; exit $?
