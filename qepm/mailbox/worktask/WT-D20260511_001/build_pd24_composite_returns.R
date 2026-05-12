#==============================================================================
# WT-D20260511_001 PD24 — Recompute PD20-B 4-sleeve composite returns with
# extended alpha (314 sig_dates 1999-01 ~ 2026-04)
#
# Methodology: identical to build_pd20b_zscore_composite_returns_pit_fix.R
# (same sleeve weights, same top20 selection, same cost model).
#
# Output: pd24_path_A_diebold_mariano.csv + pd24_path_A_metrics.csv +
#         pd24_path_A_sleeve_panel.csv + pd24_path_A_summary.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
})

WT_ID    <- "WT-D20260511_001"
WT_DIR   <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR   <- "stage_artifacts/WT_D20260511_001"
ITER5_DIR <- "stage_artifacts/WT_D20260425_010"
RAW_PATH <- ".cache/rawdata.parquet"

cat("=== PD24 — recompute 4-sleeve composite with extended alpha ===\n\n")

# Composite weights (same as PD20-B)
w_1715 <- 0.45 / (0.45 + 0.10)  # 0.8182
w_NEW  <- 0.10 / (0.45 + 0.10)  # 0.1818
cat(sprintf("Composite weights: w_1715=%.4f, w_NEW=%.4f\n", w_1715, w_NEW))

# Load EXTENDED alpha (PD24 path A)
ap_new <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores_pd24.parquet")))
sig_dates <- sort(unique(ap_new$sig_date))
cat(sprintf("PD24 alpha: %d sig_dates (%s ~ %s), %d rows, %d tickers\n",
            length(sig_dates), as.character(min(sig_dates)),
            as.character(max(sig_dates)), nrow(ap_new), uniqueN(ap_new$Ticker)))

# Load 1715 alpha
ap_1715 <- as.data.table(read_parquet(file.path(ITER5_DIR, "alpha_scores.parquet")))
ap_1715 <- ap_1715[, .(Date, Ticker, score_eff)]
setnames(ap_1715, "Date", "sig_date")
cat(sprintf("1715 alpha: %d sig_dates (%s ~ %s)\n",
            uniqueN(ap_1715$sig_date),
            as.character(min(ap_1715$sig_date)),
            as.character(max(ap_1715$sig_date))))

# Z-score per sig_date
ap_1715[, z_1715 := scale(score_eff)[, 1], by = sig_date]
ap_new[, z_NEW := scale(alpha)[, 1], by = sig_date]

# Determine common sig_dates (NEW + 1715 both present)
common_dates <- intersect(sig_dates, unique(ap_1715$sig_date))
common_dates <- sort(common_dates)
cat(sprintf("\nCommon sig_dates (NEW ∩ 1715): %d (%s ~ %s)\n",
            length(common_dates), as.character(min(common_dates)),
            as.character(max(common_dates))))

# Dates where only NEW available (1715 not yet)
new_only_dates <- setdiff(sig_dates, common_dates)
cat(sprintf("NEW-only dates (1715 absent): %d\n", length(new_only_dates)))

# Combine: where both present → composite_z = 0.818 z_1715 + 0.182 z_NEW
#          where 1715 missing → composite_z = z_NEW (full weight on NEW)
ap_1715_dt <- ap_1715[, .(sig_date, Ticker, z_1715)]
setkey(ap_1715_dt, sig_date, Ticker); setkey(ap_new, sig_date, Ticker)
merged <- merge(ap_new[, .(sig_date, Ticker, z_NEW)],
                ap_1715_dt,
                by = c("sig_date", "Ticker"), all.x = TRUE)

# Fallback when 1715 absent: pure NEW
merged[is.na(z_1715), composite_z := z_NEW]
merged[!is.na(z_1715), composite_z := w_1715 * z_1715 + w_NEW * z_NEW]
merged[is.na(z_NEW), composite_z := w_1715 * z_1715]  # NEW NA backup

cat(sprintf("\nMerged: %d rows total. Where 1715 absent: %d rows.\n",
            nrow(merged), sum(is.na(merged$z_1715))))

# Load rawdata
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

LIQ_THRESHOLD <- 2e8

# Top20 composite + monthly returns
cat("\n[Top20 + monthly returns per sig_date] ...\n")
composite_returns <- data.table()
holdings <- data.table()

for (i in seq_along(sig_dates)) {
  d_now <- sig_dates[i]
  d_lag <- d_now - 1L  # PIT-C10 strict t-1

  d_next <- if (i < length(sig_dates)) sig_dates[i + 1] else as.Date("2026-05-01")

  # Universe @ d_lag
  uni_dt <- rd[Date <= d_lag & Date >= (d_lag - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | (!is.na(KQ150) & KQ150 == 1)) &
                    !is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]

  cs_now <- merged[sig_date == d_now & Ticker %in% uni_dt$Ticker & !is.na(composite_z)]
  if (nrow(cs_now) == 0) {
    composite_returns <- rbind(composite_returns, data.table(
      sig_date = d_now, n_holdings = 0, monthly_ret = NA_real_, n_present = 0
    ))
    next
  }

  setorder(cs_now, -composite_z)
  top20 <- head(cs_now, 20)

  holdings <- rbind(holdings,
                     top20[, .(sig_date, Ticker, composite_z, z_NEW, z_1715)])

  # Entry/exit
  entry <- rd[Ticker %in% top20$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  entry <- entry[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry, c("Ticker", "entry_date", "entry_price"))

  exit <- rd[Ticker %in% top20$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  exit <- exit[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(exit, c("Ticker", "exit_date", "exit_price"))

  rets <- merge(entry, exit, by = "Ticker", all.x = TRUE)
  rets[, ret_pct := exit_price / entry_price - 1]
  valid <- rets[!is.na(ret_pct)]
  monthly_ret <- if (nrow(valid) == 0) NA_real_ else mean(valid$ret_pct)

  composite_returns <- rbind(composite_returns, data.table(
    sig_date = d_now, n_holdings = nrow(top20),
    monthly_ret = monthly_ret, n_present = nrow(valid)
  ))

  if (i %% 30 == 0 || i == length(sig_dates) || i == 1) {
    cat(sprintf("  [%3d/%3d] %s: top20=%d, ret=%.4f, has1715=%s\n",
                i, length(sig_dates), as.character(d_now),
                nrow(top20),
                ifelse(is.na(monthly_ret), 0, monthly_ret),
                ifelse(sum(!is.na(top20$z_1715)) > 0, "yes", "no")))
  }
}

cat(sprintf("\nFinal: %d sig_dates with composite returns. Non-NA: %d\n",
            nrow(composite_returns), sum(!is.na(composite_returns$monthly_ret))))

# Save composite returns + holdings
fwrite(composite_returns, file.path(SA_DIR, "composite_top20_returns_pd24.csv"))
fwrite(holdings, file.path(SA_DIR, "composite_top20_holdings_pd24.csv"))

# -------------- Compute 4-sleeve composite returns (PD20-B Path 2 style) --------------
# Load PD20-B existing sleeve_panel structure (S4 v2 baseline weights + sleeve returns)
panel <- fread(file.path(WT_DIR, "backtest_result_pd20b/sleeve_panel_pd20b.csv"))

# Filter panel to dates where NEW alpha (PD24) is available
panel_pd24 <- panel[date %in% as.Date(composite_returns$sig_date)]
cat(sprintf("\npanel_pd24 dates: %d (overlap with PD20-B base)\n", nrow(panel_pd24)))

# But also need to extend the panel back where new alpha exists but PD20-B sleeve panel doesn't
# PD20-B panel: 2005-02 ~ 2026-04
# PD24 alpha: 1999-01 ~ 2026-04
# Need sleeve panel extended back to 1999-01

# For the back-extension period (1999-01 ~ 2005-01):
#   - AR_on_M4: unknown (STR_1715 sleeve panel only goes back to 2005)
#   - TSMOM: 0 (not present)
#   - KR_10y: unknown (KR 10y bond ETF A148070 launched 2011)
#   - Cash: 0
# Realistically, the 4-sleeve composite is undefined pre-2005-02.
# Thus the comparable window for DM remains 2005-02 ~ 2026-04 (panel range).
# But within this window, we now have:
#   - More NEW alpha dates that have z_NEW (mostly 2011~ but some 2005-2010 if 1715 absent)
# Actually z_NEW exists for sig_dates 1999-01~. Within 2005-02~2010-12, z_NEW exists but z_1715 absent.
# So composite_z = z_NEW pure for those dates (no 1715 weight).

# Step: reload panel raw (use original PD20-B sleeve panel structure)
panel_raw <- fread(file.path(WT_DIR, "backtest_result_pd20b/sleeve_panel_pd20b.csv"))
panel_raw[, date := as.Date(date)]
composite_returns[, sig_date := as.Date(sig_date)]

# Merge composite_returns (PD24) with panel_raw on date
panel_merged <- merge(panel_raw[, .(ym, date, AR_on_M4, KR_10y, TSMOM, TSMOM_PRESENT, Cash, ret_S4_baseline)],
                      composite_returns[, .(sig_date, monthly_ret_pd24 = monthly_ret)],
                      by.x = "date", by.y = "sig_date", all = TRUE)
setorder(panel_merged, date)

# Where panel_raw values are NA (pre-2005-02 or post-2026-04 boundary), fill defaults
panel_merged[is.na(AR_on_M4), AR_on_M4 := 0]
panel_merged[is.na(KR_10y), KR_10y := 0]
panel_merged[is.na(TSMOM), TSMOM := 0]
panel_merged[is.na(TSMOM_PRESENT), TSMOM_PRESENT := FALSE]
panel_merged[is.na(Cash), Cash := 0]
panel_merged[is.na(monthly_ret_pd24), monthly_ret_pd24 := 0]
panel_merged[is.na(ret_S4_baseline) | ret_S4_baseline == 0,
             ret_S4_baseline := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]

# Composite portfolio ret (Path 2 style): 55% NEW_composite + 22.5% TSMOM + 18% KR_10y + 4.5% Cash
# NEW_composite = monthly_ret_pd24 (top20 from extended alpha)
panel_merged[, ret_pd24_path2 := 0.55 * monthly_ret_pd24 + 0.225 * TSMOM + 0.18 * KR_10y + 0.045 * Cash]

# Cost drag (same as PD20-B: 0.05 turnover_oneway ~ 15bps)
panel_merged[, turnover_oneway := 0.05]  # default conservative
panel_merged[, cost_drag := turnover_oneway * 0.0015 * 2]  # round-trip
panel_merged[, ret_pd24_path2_net := ret_pd24_path2 - cost_drag]

# Diebold-Mariano: ret_pd24_path2_net vs ret_S4_baseline
non_na <- panel_merged[!is.na(ret_pd24_path2_net) & !is.na(ret_S4_baseline)]
non_na <- non_na[!(ret_pd24_path2_net == 0 & ret_S4_baseline == 0)]  # exclude trivial zeros
diff_v <- non_na$ret_pd24_path2_net - non_na$ret_S4_baseline

cat(sprintf("\n=== DM PD24 ===\n"))
cat(sprintf("  Total panel rows: %d\n", nrow(panel_merged)))
cat(sprintf("  DM N (non-trivial): %d\n", length(diff_v)))

# NW lag 6
nw_lag <- 6L
N <- length(diff_v)
mean_diff <- mean(diff_v)
nw_var <- var(diff_v)
for (lag in 1:nw_lag) {
  weight <- 1 - lag / (nw_lag + 1)
  ac <- mean((diff_v[(lag + 1):N] - mean_diff) * (diff_v[1:(N - lag)] - mean_diff))
  nw_var <- nw_var + 2 * weight * ac
}
nw_se <- sqrt(nw_var / N)
t_nw <- mean_diff / nw_se
p_nw <- 2 * pnorm(-abs(t_nw))
hlz_pass <- abs(t_nw) > 3.0

cat(sprintf("  N=%d, mean_diff_monthly=%.6f, NW_lag6_SE=%.6f\n", N, mean_diff, nw_se))
cat(sprintf("  t_NW = %.4f, p = %.6f\n", t_nw, p_nw))
cat(sprintf("  Harvey-Liu-Zhu (2016) t > 3.0 strict: %s\n",
            ifelse(hlz_pass, "PASS", "FAIL")))

# Compare PRE_PD24 vs PD24
cat("\n=== Comparison ===\n")
cat(sprintf("  PRE PD24 (PD20-B): N=255, t_NW=2.7641\n"))
cat(sprintf("  POST PD24:         N=%d, t_NW=%.4f\n", N, t_nw))
cat(sprintf("  Delta t_NW:        %+.4f\n", t_nw - 2.7641))

# Save outputs
out_dt <- data.table(
  measure = "Diebold-Mariano_PD24_path_A",
  N = N,
  mean_diff_monthly = mean_diff,
  NW_lag6_SE = nw_se,
  t_NW = t_nw,
  p_value = p_nw,
  hlz_pass = hlz_pass
)
fwrite(out_dt, file.path(SA_DIR, "pd24_path_A_diebold_mariano.csv"))

fwrite(panel_merged, file.path(SA_DIR, "pd24_path_A_sleeve_panel.csv"))

# Metrics
xt_pd24 <- xts(non_na$ret_pd24_path2_net, order.by = non_na$date)
SR_pd24 <- as.numeric(SharpeRatio.annualized(xt_pd24, scale = 12, geometric = TRUE))
CAGR_pd24 <- as.numeric(Return.annualized(xt_pd24, scale = 12, geometric = TRUE))
MDD_pd24 <- as.numeric(maxDrawdown(xt_pd24, geometric = TRUE))

xt_S4 <- xts(non_na$ret_S4_baseline, order.by = non_na$date)
SR_S4 <- as.numeric(SharpeRatio.annualized(xt_S4, scale = 12, geometric = TRUE))
CAGR_S4 <- as.numeric(Return.annualized(xt_S4, scale = 12, geometric = TRUE))
MDD_S4 <- as.numeric(maxDrawdown(xt_S4, geometric = TRUE))

mets <- data.table(
  metric = c("SR_ann_geom", "CAGR", "MDD"),
  PD24_path_A = c(SR_pd24, CAGR_pd24, MDD_pd24),
  S4_v2_baseline = c(SR_S4, CAGR_S4, MDD_S4),
  delta = c(SR_pd24 - SR_S4, CAGR_pd24 - CAGR_S4, MDD_pd24 - MDD_S4)
)
fwrite(mets, file.path(SA_DIR, "pd24_path_A_metrics.csv"))
print(mets)

# Summary JSON
sm <- list(
  task_id = WT_ID,
  pd_phase = "PD24_path_A",
  alpha_extension = list(
    pre_n_sig_dates = 184L,
    post_n_sig_dates = uniqueN(composite_returns$sig_date),
    expansion_ratio = round(uniqueN(composite_returns$sig_date) / 184, 3)
  ),
  diebold_mariano = list(
    pre_pd24_t_NW = 2.7641,
    post_pd24_t_NW = round(t_nw, 4),
    delta = round(t_nw - 2.7641, 4),
    N = N,
    mean_diff_monthly = round(mean_diff, 6),
    NW_lag6_SE = round(nw_se, 6),
    p_value = round(p_nw, 6),
    harvey_liu_zhu_strict_pass = hlz_pass
  ),
  metrics = list(
    PD24_path_A = list(SR = round(SR_pd24, 4), CAGR = round(CAGR_pd24, 4), MDD = round(MDD_pd24, 4)),
    S4_v2_baseline = list(SR = round(SR_S4, 4), CAGR = round(CAGR_S4, 4), MDD = round(MDD_S4, 4))
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(sm, file.path(WT_DIR, "pd24_path_A_summary.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("\n=== Saved ===\n")
cat(sprintf("  alpha_scores: stage_artifacts/.../alpha_scores_pd24.parquet (%d rows)\n",
            nrow(ap_new)))
cat(sprintf("  composite_top20_returns: composite_top20_returns_pd24.csv\n"))
cat(sprintf("  composite_top20_holdings: composite_top20_holdings_pd24.csv\n"))
cat(sprintf("  DM: pd24_path_A_diebold_mariano.csv\n"))
cat(sprintf("  metrics: pd24_path_A_metrics.csv\n"))
cat(sprintf("  summary: %s\n", file.path(WT_DIR, "pd24_path_A_summary.json")))
cat("\n=== PD24 Path A — DONE ===\n")
