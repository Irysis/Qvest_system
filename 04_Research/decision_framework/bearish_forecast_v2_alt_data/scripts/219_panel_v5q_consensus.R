#==============================================================================
# 219_panel_v5q_consensus.R — Cycle 58P preparation
#
# v5q = v5g (86) + consensus clean features (~12)
# 약세 leading indicator (analyst EPS/earnings surprise revision aggregate)
#
# Filter:
#   - Drop constant features (cons_cov_pct_down/up — coverage 단조)
#   - SD features outlier clip (winsorize 99%ile)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_DIR <- file.path(WS, "outputs/01_data")
OUT_PATH <- file.path(IN_DIR, "feature_panel_v5q_consensus.parquet")

cat(sprintf("[%s] Loading v5g + consensus...\n",
            format(Sys.time(), "%H:%M:%S")))
d <- as.data.table(read_parquet(file.path(IN_DIR,
                                          "feature_panel_v5g_cross_market.parquet")))
d[, Date := as.Date(Date)]
setorder(d, Date)

cons <- as.data.table(read_parquet(file.path(IN_DIR,
                                              "consensus_aggregate_features.parquet")))
cons[, Date := as.Date(Date)]

# Drop bad features (constants + sd outliers)
drop_cols <- c(
  "cons_cov_pct_down_lag1",     # constant 0
  "cons_cov_pct_up_lag1",       # constant 1
  "cons_eps_chg3m_sd_val_lag1", # outlier 5505 (rare stocks)
  "cons_eps_chg1m_sd_val_lag1", # outlier 1203
  "cons_sue_sd_val_lag1",       # outlier 3152
  "cons_esbr_sd_val_lag1",      # potential outliers
  "cons_cov_sd_val_lag1"        # potential outliers
)
cons <- cons[, !drop_cols, with = FALSE]
cat(sprintf("  Consensus clean: %d features (dropped %d bad)\n",
            ncol(cons) - 1, length(drop_cols)))

# Winsorize remaining at 1/99 (PIT-expanding could be ideal but using static is OK
# given the aggregate nature, lower noise)
for (col in setdiff(names(cons), "Date")) {
  v <- cons[[col]]
  qs <- quantile(v, c(0.01, 0.99), na.rm = TRUE)
  v[v < qs[1]] <- qs[1]
  v[v > qs[2]] <- qs[2]
  cons[[col]] <- v
}

# Merge
d <- merge(d, cons, by = "Date", all.x = TRUE)
n_total <- ncol(d) - 1
cat(sprintf("\n[%s] Final v5q: %d × %d (= 86 v5g + %d consensus)\n",
            format(Sys.time(), "%H:%M:%S"), nrow(d), n_total, n_total - 86))

# Stats
cat("\nConsensus features (winsorized 1/99):\n")
for (col in setdiff(names(cons), "Date")) {
  v <- d[[col]]
  cat(sprintf("  %-32s n=%d range=[%.4f, %.4f] mean=%.4f\n",
              col, sum(!is.na(v)),
              min(v, na.rm = TRUE), max(v, na.rm = TRUE),
              mean(v, na.rm = TRUE)))
}

write_parquet(d, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s\n", format(Sys.time(), "%H:%M:%S"), OUT_PATH))
