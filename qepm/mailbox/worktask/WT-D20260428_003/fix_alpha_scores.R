#==============================================================================
# Fix alpha_scores.parquet to Date x Ticker x score panel (RF-A7 fix)
# Codex C1 ACCEPT: PIT-safe time-series panel required.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260428_003"
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

panel <- readRDS(file.path(WT_DIR, "alpha_panel.rds"))
panel[, sig_date := as.Date(sig_date)]
setorder(panel, sig_date, -alpha)

# Time-series panel: sig_date x Ticker x score (+ axis components)
ts_panel <- panel[, .(
  sig_date,
  Ticker,
  score = alpha,
  Z_A1, Z_A2, Z_A3, Z_A4,
  score_S2 = alpha_S2_PS,
  score_S3 = alpha_S3_PG
)]

cat("Time-series panel dimensions:\n")
cat(sprintf("  Total rows: %d\n", nrow(ts_panel)))
cat(sprintf("  Unique sig_dates: %d\n", uniqueN(ts_panel$sig_date)))
cat(sprintf("  Unique Tickers: %d\n", uniqueN(ts_panel$Ticker)))
cat(sprintf("  Date range: %s ~ %s\n", min(ts_panel$sig_date), max(ts_panel$sig_date)))

# Write to BOTH stage_artifacts paths (Codex C8 — both expected)
write_parquet(ts_panel, file.path(ROOT, "stage_artifacts/WT_D20260428_003/alpha_scores.parquet"))
write_parquet(ts_panel, file.path(ROOT, "qepm/stage_artifacts/WT_WT-D20260428_003/alpha_scores.parquet"))
cat("alpha_scores.parquet written (both paths) — full panel\n")

# Also save asof-only snapshot for backward compat (signal_as_of = 2023-10-31)
asof_panel <- ts_panel[sig_date == as.Date("2023-10-31")][order(-score)]
write_parquet(asof_panel, file.path(WT_DIR, "alpha_scores_asof_2023_10_31.parquet"))
cat(sprintf("asof_2023_10_31 snapshot: %d rows\n", nrow(asof_panel)))
