#==============================================================================
# 202_panel_v5i_expanded_interactions.R — Cycle 58E expanded interactions
#
# v5h (91 features) baseline → v5i (101 features). 10 신규 interactions 추가:
#
# Cross-market × KR macro/breadth (economic intuition):
#   1. dxy_x_kr_ind_prod          DXY ↑ + KR 산업생산 ↓ = export pressure risk
#   2. usdkrw_x_breadth           FX 5d 변화 × 외인 net buy breadth
#   3. vix_x_breadth              VIX × 외인 breadth (risk-off detector)
#   4. t10y2y_x_kr_baserate       US yield curve × KR base rate (rate cycle)
#   5. cfnai_x_bbva_macro         US 성장 × KR macro stress
#   6. stlfsi_x_bbva_market       US 금융스트레스 × KR market stress
#   7. vix_x_k200_skew            VIX × KR implied skew (tail risk amplification)
#   8. wti_x_kr_cpi               WTI × KR CPI (inflation pass-through)
#   9. nikkei_x_bbva_market       Nikkei × KR market (asia coupling)
#  10. hangseng_x_bbva_sovereign  HangSeng × KR sovereign (china contagion)
#
# All interactions PIT-clean (multiplicand 둘 다 _lag1 또는 _change_5d_lag1).
# 모든 신규 cols z-normalized (rolling 252d expanding).
# Output: outputs/01_data/feature_panel_v5i_expanded_interactions.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_PATH <- file.path(WS, "outputs/01_data",
  "feature_panel_v5h_cross_market_interactions.parquet")
OUT_PATH <- file.path(WS, "outputs/01_data",
  "feature_panel_v5i_expanded_interactions.parquet")
AUDIT_PATH <- file.path(WS, "outputs/04_evaluation",
  "cycle58e_panel_v5i_build.json")

cat(sprintf("[%s] Loading v5h panel...\n", format(Sys.time(), "%H:%M:%S")))
d <- as.data.table(read_parquet(IN_PATH))
cat(sprintf("  rows=%d, cols=%d\n", nrow(d), ncol(d)))
setorder(d, Date)

# Rolling z-norm (expanding window, PIT-safe — only uses past)
roll_z <- function(x, min_obs = 252L) {
  n <- length(x)
  z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < min_obs) next
    hist <- x[1:(i - 1)]
    mu <- mean(hist, na.rm = TRUE)
    sd <- sd(hist, na.rm = TRUE)
    if (is.na(sd) || sd < 1e-9) next
    z[i] <- (x[i] - mu) / sd
  }
  z
}

# 1. dxy × kr_ind_prod
d[, dxy_x_kr_ind_prod_raw :=
    dxy_change_5d_lag1 * ecos_industrial_production_yoy_lag1]
d[, dxy_x_kr_ind_prod_lag1 := roll_z(dxy_x_kr_ind_prod_raw)]
d[, dxy_x_kr_ind_prod_raw := NULL]

# 2. usdkrw × breadth
d[, usdkrw_x_breadth_raw :=
    usdkrw_change_5d_lag1 * foreign_breadth_ad_ratio_5d_avg_lag1]
d[, usdkrw_x_breadth_lag1 := roll_z(usdkrw_x_breadth_raw)]
d[, usdkrw_x_breadth_raw := NULL]

# 3. vix × breadth
d[, vix_x_breadth_raw :=
    vix_change_5d_lag1 * foreign_breadth_ad_ratio_5d_avg_lag1]
d[, vix_x_breadth_lag1 := roll_z(vix_x_breadth_raw)]
d[, vix_x_breadth_raw := NULL]

# 4. us_t10y2y × kr_baserate
d[, t10y2y_x_kr_baserate_raw :=
    us_t10y2y_spread_lag1 * ecos_base_rate_lag1]
d[, t10y2y_x_kr_baserate_lag1 := roll_z(t10y2y_x_kr_baserate_raw)]
d[, t10y2y_x_kr_baserate_raw := NULL]

# 5. cfnai × bbva_macro_composite
d[, cfnai_x_bbva_macro_raw :=
    us_cfnai_lag1 * bbva_macro_composite_lag1]
d[, cfnai_x_bbva_macro_lag1 := roll_z(cfnai_x_bbva_macro_raw)]
d[, cfnai_x_bbva_macro_raw := NULL]

# 6. stlfsi × bbva_market
d[, stlfsi_x_bbva_market_raw :=
    us_stlfsi_lag1 * bbva_market_z_lag1]
d[, stlfsi_x_bbva_market_lag1 := roll_z(stlfsi_x_bbva_market_raw)]
d[, stlfsi_x_bbva_market_raw := NULL]

# 7. vix × k200_implied_skew
d[, vix_x_k200_skew_raw :=
    vix_change_5d_lag1 * k200_implied_skew_z_lag1]
d[, vix_x_k200_skew_lag1 := roll_z(vix_x_k200_skew_raw)]
d[, vix_x_k200_skew_raw := NULL]

# 8. wti × kr_cpi
d[, wti_x_kr_cpi_raw :=
    wti_change_5d_lag1 * ecos_cpi_yoy_lag1]
d[, wti_x_kr_cpi_lag1 := roll_z(wti_x_kr_cpi_raw)]
d[, wti_x_kr_cpi_raw := NULL]

# 9. nikkei × bbva_market
d[, nikkei_x_bbva_market_raw :=
    nikkei225_return_lag1 * bbva_market_z_lag1]
d[, nikkei_x_bbva_market_lag1 := roll_z(nikkei_x_bbva_market_raw)]
d[, nikkei_x_bbva_market_raw := NULL]

# 10. hangseng × bbva_sovereign
d[, hangseng_x_bbva_sovereign_raw :=
    hangseng_return_lag1 * bbva_sovereign_z_lag1]
d[, hangseng_x_bbva_sovereign_lag1 := roll_z(hangseng_x_bbva_sovereign_raw)]
d[, hangseng_x_bbva_sovereign_raw := NULL]

cat(sprintf("[%s] New interactions built: %d\n",
            format(Sys.time(), "%H:%M:%S"), 10))

# Validate
new_cols <- c(
  "dxy_x_kr_ind_prod_lag1", "usdkrw_x_breadth_lag1",
  "vix_x_breadth_lag1", "t10y2y_x_kr_baserate_lag1",
  "cfnai_x_bbva_macro_lag1", "stlfsi_x_bbva_market_lag1",
  "vix_x_k200_skew_lag1", "wti_x_kr_cpi_lag1",
  "nikkei_x_bbva_market_lag1", "hangseng_x_bbva_sovereign_lag1"
)

cat("\nNew interaction validation:\n")
for (col in new_cols) {
  v <- d[[col]]
  cat(sprintf("  %s: n_obs=%d non_NA=%d min=%.2f max=%.2f mean=%.3f\n",
              col, length(v), sum(!is.na(v)),
              min(v, na.rm = TRUE), max(v, na.rm = TRUE),
              mean(v, na.rm = TRUE)))
}

# Save
write_parquet(d, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s (%d cols, %d rows)\n",
            format(Sys.time(), "%H:%M:%S"), OUT_PATH,
            ncol(d), nrow(d)))

# Max |cor| of new interactions to existing features (collinearity check)
existing_cols <- setdiff(names(d), c("Date", new_cols))
max_cors <- sapply(new_cols, function(nc) {
  v <- d[[nc]]
  mask <- !is.na(v)
  if (sum(mask) < 100) return(NA_real_)
  cors <- sapply(existing_cols, function(ec) {
    other <- d[[ec]]
    valid <- mask & !is.na(other)
    if (sum(valid) < 100) return(NA_real_)
    cor(v[valid], other[valid])
  })
  max(abs(cors), na.rm = TRUE)
})

cat("\nMax |cor| of new interactions to existing features:\n")
for (i in seq_along(new_cols)) {
  cat(sprintf("  %-35s max|r|=%.3f\n", new_cols[i], max_cors[i]))
}

audit <- list(
  cycle = "58E_panel_v5i_expanded_interactions",
  script = "202_panel_v5i_expanded_interactions.R",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  base_panel = "v5h",
  new_interactions = new_cols,
  n_features_new = 10L,
  n_features_total = ncol(d) - 1L,
  n_rows = nrow(d),
  max_cor_to_existing = setNames(as.numeric(max_cors), new_cols),
  output_path = OUT_PATH
)
jsonlite::write_json(audit, AUDIT_PATH, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[%s] Audit saved: %s\n",
            format(Sys.time(), "%H:%M:%S"), AUDIT_PATH))
