#!/usr/bin/env bash
# WT-D20260802_005 — quarantine 재고 회수 canonical dual-basis 재실측 배치
# 순차 실행(프로세스 격리, RAM 규칙). canonical_screen_bt 계약 경유 — 자체합성 없음.
set -u
cd "${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}" || exit 1
OUT=stage_artifacts/WT-D20260802_005
RUNNER=stage_artifacts/WT-D20260802_005/run_dualbasis_wt005.R
FEDIR=02_Infrastructure/alpha_search

run_one() {
  local label="$1"; local fe="$2"
  echo "########## $label ##########"
  AS_LABEL="$label" AS_FE="$(pwd)/$fe" AS_TOPN=25 AS_START=2005-01-01 AS_OUT="$OUT" \
    Rscript -e 'source("stage_artifacts/WT-D20260802_005/run_dualbasis_wt005.R")' \
    > "$OUT/log_$label.txt" 2>&1
  echo "exit=$? label=$label"
  tail -8 "$OUT/log_$label.txt"
}

run_one "C_VolRankStability_3M"    "04_Research/strategies/AS_C_VolRankStability_20260802/factor_engine.R"
run_one "T_RetAutoCorr_12M"        "04_Research/strategies/AS_T_RetAutoCorr_12M_20260802/factor_engine.R"
run_one "vol_rank_stability_v1"    "$FEDIR/fe_vol_rank_stability.R"
run_one "hill_tail_index"          "$FEDIR/fe_hill_tail_index.R"
run_one "vol_adj_volume_surprise"  "$FEDIR/fe_vol_adj_volume_surprise.R"

# Chen-Welch RD-to-Market — fe_factor_combo (factor DB IN03, C15: load_month_factors 경유)
echo "########## chen_welch_rd_to_market ##########"
AS_LABEL="chen_welch_rd_to_market" AS_FE="$(pwd)/$FEDIR/fe_factor_combo.R" \
  AS_TOPN=25 AS_START=2005-01-01 AS_OUT="$OUT" \
  FACTOR_NAMES="IN03_RD_to_Market" \
  Rscript -e 'source("stage_artifacts/WT-D20260802_005/run_dualbasis_wt005.R")' \
  > "$OUT/log_chen_welch_rd_to_market.txt" 2>&1
echo "exit=$? label=chen_welch_rd_to_market"
tail -8 "$OUT/log_chen_welch_rd_to_market.txt"

echo "ALL DONE WT005"
