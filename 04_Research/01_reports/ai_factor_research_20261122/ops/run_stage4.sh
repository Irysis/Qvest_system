#!/usr/bin/env bash
# run_stage4.sh — 단계 4(잠재팩터)를 차례로 돌린다: PCA · 위험프리미엄 PCA · IPCA → 측정 → 조건부 오토인코더(시험 실행 → 본 실행) → 측정.
#   각 작업은 감시 셸(aif_run.py)이 띄운다. 앞이 실패하면 그 모형 계열만 건너뛰고 다음 계열로 간다. 다시 띄우면 끝난 단위는 건너뛴다.
#   사용: bash ops/run_stage4.sh [--no-notify]
# (본문을 함수에 넣었다 — 셸이 파일을 끝까지 읽은 뒤 실행하므로, 도는 중에 이 파일을 고쳐도 실행 중인 것은 영향을 받지 않는다)
main() {
set -u
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RD="$(cd "$SD" && pwd -W 2>/dev/null)"; [ -n "$RD" ] || RD="$SD"
ROOT="${AIF_ROOT:-${QM_ROOT:-}}"; ROOT="${ROOT//\\//}"
[ -n "$ROOT" ] || { echo "[run_stage4] QM_ROOT 가 없다"; exit 2; }
PY="${QVEST_PY:-python}"; PY="${PY//\\//}"
VPY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
OUT="$ROOT/.cache/aif_research"; RES="$ROOT/04_Research/01_reports/ai_factor_research_20261122/results"
EXTRA=("$@"); fail=0
W() { "$PY" -X utf8 "$RD/ops/aif_run.py" "$@"; }

W --job pca_ipca --stage pca_ipca "${EXTRA[@]}" -- "$VPY" -X utf8 "$RD/py/aif_latent.py" \
 && W --job perf --stage pca_ipca --summary "$OUT/stage_summary_stage4_latent.json" "${EXTRA[@]}" -- "$RS" --vanilla "$RD/run/06_measure_latent.R" \
      "--manifest=$OUT/manifest_latent.json" --set=stage4_latent --stage=pca_ipca --from=0.9 --to=1 "--label=잠재팩터(PCA · IPCA)" \
      "--logs=$RES/stage4_latent/model_log_pca.json,$RES/stage4_latent/model_log_rppca.json,$RES/stage4_latent/model_log_ipca.json" \
 || { echo "[run_stage4] PCA · IPCA 계열에서 실패 — 다음 계열로 간다"; fail=1; }

W --job cond_autoencoder --stage cond_autoencoder --no-notify -- "$VPY" -X utf8 "$RD/py/aif_cae.py" --smoke \
 && W --job cond_autoencoder --stage cond_autoencoder "${EXTRA[@]}" -- "$VPY" -X utf8 "$RD/py/aif_cae.py" \
 && W --job perf --stage cond_autoencoder --summary "$OUT/stage_summary_stage4_cae.json" "${EXTRA[@]}" -- "$RS" --vanilla "$RD/run/06_measure_latent.R" \
      "--manifest=$OUT/manifest_cae.json" --set=stage4_cae --stage=cond_autoencoder --from=0.9 --to=1 "--label=잠재팩터(조건부 오토인코더)" \
      "--logs=$RES/stage4_cae/model_log_cae.json" \
 || { echo "[run_stage4] 조건부 오토인코더 계열에서 실패"; fail=1; }
echo "[run_stage4] 끝 fail=$fail"; exit $fail
}
main "$@"; exit $?
