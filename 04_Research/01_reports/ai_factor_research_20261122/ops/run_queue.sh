#!/usr/bin/env bash
# run_queue.sh — 단계 3 의 남은 생성기를 차례로 돌린다(한 번에 하나 · 앞이 실패하면 멈춘다). 다시 띄우면 끝난 단위는 건너뛴다.
#   순서: 특징 부스팅 → 신경망 → 트리 AutoML(끝에 두 팔 평균) → 수식 탐색 3판. 짧은 것부터 돌려 결과가 일찍 나오게 한다.
#   사용: bash ops/run_queue.sh [--no-notify]
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\//}"
[ -n "$ROOT" ] || { echo "[run_queue] QM_ROOT 가 없다"; exit 2; }
G() { bash "$SD/ops/run_generator.sh" "$@"; }
G feature_boost feature_boost aif_fboost.py fboost "특징 부스팅 팩터" "$@" || { echo "[run_queue] 특징 부스팅에서 멈춤"; exit 1; }
G neural_net neural_net aif_nn.py nn "신경망 예측 팩터" "$@" || { echo "[run_queue] 신경망에서 멈춤"; exit 1; }
G tree_automl tree_automl aif_tree.py tree "트리 AutoML 예측 팩터" "$@" || { echo "[run_queue] 트리 AutoML 에서 멈춤"; exit 1; }
AIF_GEN_PY="$ROOT/.venv_gp_alpha/Scripts/python.exe" G gp_v3 gp_v3 aif_gp.py gp "수식 탐색 3판 팩터" "$@" || { echo "[run_queue] 수식 탐색에서 멈춤"; exit 1; }
echo "[run_queue] 끝"
}
main "$@"; exit $?
