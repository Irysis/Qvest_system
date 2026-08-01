#!/usr/bin/env bash
# 순차 실행 — 각 엔진마다 별도 R 프로세스(메모리 격리). RAM 80% 규칙 준수.
set -u
cd "${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}" || exit 1
OUT=stage_artifacts/alpha_search_dualbasis_20260802
FEDIR=02_Infrastructure/alpha_search

run_one() {
  local label="$1"; local fe="$2"
  echo "########## $label ##########"
  AS_LABEL="$label" AS_FE="$(pwd)/$fe" AS_TOPN=25 AS_START=2005-01-01 \
    Rscript -e 'source("stage_artifacts/alpha_search_dualbasis_20260802/run_dualbasis.R")' \
    > "$OUT/log_$label.txt" 2>&1
  echo "exit=$? label=$label"
  tail -14 "$OUT/log_$label.txt"
}

run_one "spec_mass_lowfreq_60d_BASE" "$FEDIR/factor_engine_spec_mass_lowfreq.R"
run_one "resid_info_vol_BASE"        "$FEDIR/fe_resid_info_vol.R"
run_one "resid_info_vol_M60"         "$FEDIR/fe_resid_info_vol_m60.R"
run_one "spec_mass_lowvol"           "$FEDIR/fe_spec_mass_lowvol.R"
echo "ALL DONE"
