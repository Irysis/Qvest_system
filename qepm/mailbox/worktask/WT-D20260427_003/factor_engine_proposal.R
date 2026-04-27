# ============================================================
# WT-D20260427_003 — Iter 19 Factor Engine Proposal
#   Universe Pilot: KR_TOP500_FREEFLOAT (L-227)
#   Alpha: STR_1701 multi-sleeve composite (Iter 11 inheritance)
# ============================================================
# Purpose: Forward-looking forge-ready spec. NOT executed during alpha agent
# stage — alpha is pure inheritance. This file documents how to materialize
# Iter 19 alpha from base factors when universe v2 reproduction is needed.
#
# Inheritance source:
#   - Base score column: score_str1701
#   - Source parquet: stage_artifacts/WT_D20260426_007/alpha_scores.parquet
#   - Iter 11 multi-sleeve composite: Core 0.65 (Consensus_4F + Q07 + M08) +
#     Defense 0.35 (Q07 + Q25_Distress). z_A/z_B/z_C audit columns preserved.
#
# Universe v2: KR_TOP500_FREEFLOAT
#   - load_month_factors_v2(sig_date, universe = "KR_TOP500_FREEFLOAT")
#   - PIT-safe via build_universe_v2 (Date <= sig_date enforced)
#   - cost recommendation: 20bps (mid-cap impact buffer)
# ============================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

# ---- Universe v2 build (PIT) ----
source(file.path(ROOT, "02_Infrastructure/factor_db/universe_expanded_v2.R"))

build_iter19_panel <- function(sig_dates, universe_label = "KR_TOP500_FREEFLOAT") {
  # Step 1: build universe per sig_date (PIT)
  uni_list <- lapply(sig_dates, function(sd) {
    build_universe_v2(as.Date(sd), label = universe_label, liq_window_days = 20L)
  })
  uni_dt <- rbindlist(uni_list)

  # Step 2: load factors per sig_date (universe-aware)
  fac_list <- lapply(sig_dates, function(sd) {
    fac <- load_month_factors_v2(as.Date(sd), universe = universe_label)
    fac[, Date := as.Date(sd)]
    fac
  })
  fac_dt <- rbindlist(fac_list, fill = TRUE)

  list(universe = uni_dt, factors = fac_dt)
}

# ---- STR_1701 multi-sleeve composite formula (audit reference) ----
#
# z_A = Core sleeve component (Consensus_4F + Q07 + M08)
# z_B = (alternate Core / weighting if applicable)
# z_C = Defense sleeve component (Q07 + Q25)
# score_str1701 = 0.65 * z_A + 0.35 * z_C  (Iter 11 multi-sleeve, see WT-D20260426_004)
# confidence = c_substab * c_resid * c_cov  (slot agreement signal)
#
# Iter 19 mandate: score_str1701 그대로 inheritance (no transform).
# Universe v2 filter applied AFTER alpha read (universe v2 pilot).

# ---- factor_specs for downstream Risk/Optimizer ----
iter19_factor_specs <- list(
  list(
    factor_family = "Multi_Sleeve_Inheritance_Universe_V2",
    proxy = "STR_1701_base_score on KR_TOP500_FREEFLOAT",
    formula = "score_str1701 (no transform) filtered to KR_TOP500_FREEFLOAT membership per sig_date",
    lag_rule = "monthly t-1 (preserved from STR_1701)",
    winsorization = "preserved (3std at source)",
    neutralization = "preserved (sector+size at source)",
    economic_rationale = paste(
      "STR_1701 multi-sleeve composite (Core 0.65 Consensus_4F+Q07+M08 / Defense 0.35 Q07+Q25)",
      "applied on broader universe to test mid-cap diversification benefit",
      "(Avramov-Cheng-Metzker 2023 universe expansion; Hou-Xue-Zhang 2015 q-factor breadth)."),
    sleeve = "inherited",
    source = "inherited+universe_filter_v2",
    weight_theta = 1.0,
    references = c(
      "Iter 5 WT-D20260425_010", "Iter 11 WT-D20260426_004",
      "L-227 Universe Expansion v2",
      "Avramov-Cheng-Metzker 2023", "Hou-Xue-Zhang 2015 q-factor"
    )
  )
)

# ---- usage example (forge-ready) ----
# sig_dates_train <- seq(as.Date("2008-01-31"), as.Date("2023-11-30"), by = "month")
# panel <- build_iter19_panel(sig_dates_train, "KR_TOP500_FREEFLOAT")
# # Then merge with inherited score_str1701 panel from
# # stage_artifacts/WT_D20260426_007/alpha_scores.parquet
# # (Iter 19 alpha agent did this exact join: see run_alpha_iter19.R Step 3.)

cat("[factor_engine_proposal] Iter 19 spec loaded.\n")
cat("[factor_engine_proposal] Use build_iter19_panel(sig_dates) for forge replication.\n")
cat("[factor_engine_proposal] iter19_factor_specs available.\n")
