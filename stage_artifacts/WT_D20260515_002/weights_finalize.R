#==============================================================================
# Schema-clean weights.csv finalization (Codex C2 + C7 + C3 response)
#
# 1. Add explicit CASH row with cash_residual weight per sig_date
# 2. Add method_selected + as_of_date schema columns
# 3. Add universe membership verification flag per sig_date × Ticker
# 4. Final weights.csv: Σw including CASH = 1.0 exactly
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

STAGE_DIR <- "stage_artifacts/WT_D20260515_002"
WT_ID     <- "WT-D20260515_002"
SELECTED  <- "Sleeve_blend_A_SignalTilt_B_EW_alloc_12_8"

# Load current weights
w <- fread(file.path(STAGE_DIR, "weights.csv"))
w[, sig_date := as.Date(sig_date)]

# Add CASH rows where cash_residual > 0
cash_rows <- unique(w[cash_residual > 1e-8, .(sig_date, cash_residual)])
cat("Sig dates with cash > 0:", nrow(cash_rows), " / ", length(unique(w$sig_date)), "\n")

cash_dt <- cash_rows[, .(
  sig_date,
  Ticker         = "CASH_KRW",
  weight         = cash_residual,
  sleeve_A_in    = FALSE,
  sleeve_B_in    = FALSE,
  combined_score = NA_real_,
  score_A        = NA_real_,
  score_B        = NA_real_,
  cash_residual  = cash_residual
)]

# Merge
w_final <- rbindlist(list(w, cash_dt), use.names = TRUE, fill = TRUE)

# Universe / LIQ verification:
# Per request.json universe_definition.label = "KR_TOP500_LIQ1E8", liquidity 2e8 KRW
# We use returns_monthly_panel coverage as PIT-clean listing universe proxy.
# Liquidity 20d ADV ≥ 2e8 KRW requires daily price+volume access — not directly in
# returns_monthly_panel (which is monthly aggregate). We mark verification status.
rp <- as.data.table(read_parquet("stage_artifacts/WT_D20260514_007/returns_monthly_panel.parquet"))
rp[, sig_date := Date]

# Per (sig_date, Ticker): is Ticker present in rp at sig_date?
rp_idx <- rp[, .(in_returns_panel = TRUE), by = .(sig_date, Ticker)]
w_final <- merge(w_final, rp_idx, by = c("sig_date", "Ticker"), all.x = TRUE)
w_final[Ticker == "CASH_KRW", in_returns_panel := TRUE]
w_final[is.na(in_returns_panel), in_returns_panel := FALSE]

# Add schema columns
w_final[, method_selected := SELECTED]
w_final[, as_of_date := sig_date]
w_final[, cost_model_version := "v2.3_kr_retail_15bps"]
w_final[, weight_source := fcase(
  Ticker == "CASH_KRW",                    "cash_overlay_residual",
  sleeve_A_in == TRUE,                     "sleeve_A_STR_1715_SignalTilt",
  sleeve_B_in == TRUE & sleeve_A_in==FALSE, "sleeve_B_M6_EW",
  default                                  = "unknown"
)]

# LIQ verification flag — for non-CASH, mark "PIT_LISTING_OK_ADV_DEFERRED_EXECUTION"
# Real 20d ADV verify requires daily volume — execution agent obligation per Charter §10.
w_final[, liquidity_verification := fcase(
  Ticker == "CASH_KRW",  "CASH_NA",
  in_returns_panel,      "PIT_LISTING_OK_ADV_DEFERRED_EXECUTION_AGENT",
  !in_returns_panel,     "FAIL_NOT_IN_RETURNS_PANEL"
)]

# Sort
setorder(w_final, sig_date, -weight)

# Sanity: Σw per sig_date
sum_check <- w_final[, .(sum_w = sum(weight)), by = sig_date]
cat("Sum weight per sig_date (with CASH):\n")
print(summary(sum_check$sum_w))
cat("\nMax dev from 1.0:", max(abs(sum_check$sum_w - 1.0)), "\n")

fwrite(w_final, file.path(STAGE_DIR, "weights.csv"))
cat("\nFinal schema-clean weights.csv saved (n_rows = ", nrow(w_final), ")\n")
cat("Columns:", paste(names(w_final), collapse = ", "), "\n")

# Save schema doc
schema <- list(
  file = "stage_artifacts/WT_D20260515_002/weights.csv",
  n_rows = nrow(w_final),
  n_sig_dates = length(unique(w_final$sig_date)),
  cash_row_count = nrow(cash_dt),
  columns = list(
    sig_date          = "Date — sig_date (month-end close-of-day, T-1 signal)",
    Ticker            = "Character — KR ticker (Annnnnn format) or 'CASH_KRW'",
    weight            = "Numeric [0, 0.20] — target portfolio weight (after STR_1715 overlay applied)",
    sleeve_A_in       = "Logical — TRUE if name selected from STR_1715 sleeve",
    sleeve_B_in       = "Logical — TRUE if name selected from M6 Ensemble sleeve",
    combined_score    = "Numeric — sleeve-z combined score (diagnostic, NA for CASH)",
    score_A           = "Numeric — STR_1715 score_eff (NA for B-only and CASH)",
    score_B           = "Numeric — M6 alpha_score (NA for A-only and CASH)",
    cash_residual     = "Numeric — STR_1715 overlay cash share at sig_date (consistent for all rows of that date)",
    in_returns_panel  = "Logical — Ticker present in returns_monthly_panel at sig_date (PIT listing universe proxy)",
    method_selected   = "Character — optimizer method label",
    as_of_date        = "Date — duplicate of sig_date for Backtest Contract schema parity",
    cost_model_version= "Character — 'v2.3_kr_retail_15bps' (one-way 15bps each leg)",
    weight_source     = "Character enum — sleeve_A_STR_1715_SignalTilt / sleeve_B_M6_EW / cash_overlay_residual",
    liquidity_verification = "Character enum — PIT_LISTING_OK_ADV_DEFERRED_EXECUTION_AGENT / CASH_NA / FAIL_NOT_IN_RETURNS_PANEL"
  ),
  sum_weight_per_sig_date_with_cash = list(
    min  = round(min(sum_check$sum_w), 6),
    max  = round(max(sum_check$sum_w), 6),
    mean = round(mean(sum_check$sum_w), 6),
    max_abs_deviation_from_1 = round(max(abs(sum_check$sum_w - 1.0)), 8)
  ),
  schedule_density_certification = list(
    n_sig_dates_alpha = 84,
    n_unique_sig_dates_weights = length(unique(w_final$sig_date)),
    ratio = round(length(unique(w_final$sig_date)) / 84, 4),
    charter_9_threshold = 0.95,
    pass = (length(unique(w_final$sig_date)) / 84) >= 0.95
  )
)
write_json(schema, file.path(STAGE_DIR, "weights_schema.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("\nSchema doc saved.\n")
