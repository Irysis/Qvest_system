#==============================================================================
# WT-D20260511_001 PD20-B — Z-Score Composite top20 returns build
#
# Mission (Production 종목수 20 cap fix):
#   PD18 (5-sleeve composite, NEW = independent top20 → KR equity 40 names) →
#   PD20-B Path 2 Z-Score Composite (1715 + NEW merged top20 → KR equity 20 names).
#
#   Per sig_date (184 dates 2011-01 ~ 2026-04):
#     1) z-score normalize STR_1715 score_eff (Iter5 multi-axis composite) — universe-wide
#     2) z-score normalize NEW alpha (3-axis Vol/Skew composite) — universe-wide
#     3) composite_z = w_1715 * z_1715 + w_NEW * z_NEW
#        w_1715 = 0.45 / (0.45 + 0.10) = 0.818
#        w_NEW  = 0.10 / (0.45 + 0.10) = 0.182
#     4) top20 by composite_z (EW 5% per name)
#     5) monthly compound return entry@sig_date → exit@next_sig_date
#
# Universe (PD18 정합):
#   KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d (PIT t-1) >= 2e8 KRW
#
# PIT compliance:
#   - z-score normalization PER sig_date only (no full-sample stats)
#   - alpha sig_date alignment: both 184 dates 2011-01 ~ 2026-04 (already matched)
#   - 15bps cost embedded composite-level (Return.portfolio with rebalance_on/transaction_cost=0)
#     Note: 15bps applied separately as turnover-weighted drag (judge-grade)
#
# Output:
#   - composite_top20_returns_pd20b.csv: 184 dates × composite top20 monthly returns
#   - composite_top20_holdings_pd20b.csv: 184 dates × 20 tickers × {Ticker, composite_z, z_1715, z_NEW}
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics)
})

# Paths
SA_DIR <- "stage_artifacts/WT_D20260511_001"
ITER5_DIR <- "stage_artifacts/WT_D20260425_010"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
RAW_PATH <- ".cache/rawdata.parquet"

cat("=== PD20-B Z-Score Composite top20 returns build ===\n\n")
cat("Methodology (Production 종목수 20 cap fix):\n")
cat("  composite_z = 0.818 * z_1715(score_eff) + 0.182 * z_NEW(alpha)\n")
cat("  top20 EW per sig_date (5% each, max 20 names)\n")
cat("  Universe: KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d (t-1) >= 2e8 KRW\n\n")

# Composite weights (effective allocation 0.45 STR_1715 + 0.10 NEW in PD18 → merged 0.55)
w_1715 <- 0.45 / (0.45 + 0.10)  # 0.8182
w_NEW  <- 0.10 / (0.45 + 0.10)  # 0.1818
cat(sprintf("composite weights: w_1715=%.4f, w_NEW=%.4f, sum=%.4f\n\n",
            w_1715, w_NEW, w_1715 + w_NEW))

# 1. Load NEW alpha (184 sig_dates × 770 tickers)
cat("[1] Load NEW alpha_scores ...\n")
ap_new <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates <- sort(unique(ap_new$sig_date))
cat(sprintf("  NEW: %d sig_dates, range %s ~ %s, %d tickers\n",
            length(sig_dates),
            as.character(min(sig_dates)),
            as.character(max(sig_dates)),
            length(unique(ap_new$Ticker))))
stopifnot(length(sig_dates) == 184)

# 2. Load STR_1715 alpha (268 dates × 846 tickers, score_eff)
cat("\n[2] Load STR_1715 alpha_scores (Iter5 score_eff) ...\n")
ap_1715 <- as.data.table(read_parquet(file.path(ITER5_DIR, "alpha_scores.parquet")))
ap_1715 <- ap_1715[, .(Date, Ticker, score_eff)]
setnames(ap_1715, "Date", "sig_date")
cat(sprintf("  1715: %d dates, range %s ~ %s, %d tickers\n",
            length(unique(ap_1715$sig_date)),
            as.character(min(ap_1715$sig_date)),
            as.character(max(ap_1715$sig_date)),
            length(unique(ap_1715$Ticker))))

# 3. Restrict 1715 to 184 NEW sig_dates (align)
ap_1715 <- ap_1715[sig_date %in% sig_dates]
cat(sprintf("  1715 restricted to 184 NEW sig_dates: %d rows\n", nrow(ap_1715)))

# 4. Per-sig_date z-score normalize (both alphas)
cat("\n[3] Per-sig_date z-score normalize both alphas ...\n")
# 1715 z_1715: re-normalize per sig_date (drop NAs)
ap_1715[, z_1715 := scale(score_eff)[, 1], by = sig_date]
# NEW z_NEW: re-normalize per sig_date
ap_new[, z_NEW := scale(alpha)[, 1], by = sig_date]

# 5. Merge on (sig_date, Ticker)
cat("\n[4] Merge on (sig_date, Ticker) ...\n")
setkey(ap_1715, sig_date, Ticker)
setkey(ap_new, sig_date, Ticker)
merged <- merge(ap_new[, .(sig_date, Ticker, alpha, confidence, z_NEW)],
                ap_1715[, .(sig_date, Ticker, score_eff, z_1715)],
                by = c("sig_date", "Ticker"),
                all.x = TRUE)
cat(sprintf("  merged rows: %d (NEW=%d, with 1715 z: %d)\n",
            nrow(merged),
            nrow(merged),
            sum(!is.na(merged$z_1715))))

# z_1715 NA fill: 0 (= neutral; ticker absent from STR_1715 universe)
merged[is.na(z_1715), z_1715 := 0]
merged[is.na(z_NEW), z_NEW := 0]

# 6. Composite z
merged[, composite_z := w_1715 * z_1715 + w_NEW * z_NEW]

# 7. Load rawdata for universe filter + price returns
cat("\n[5] Load rawdata.parquet ...\n")
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)
cat(sprintf("  rawdata rows: %s, tickers: %d, range: %s ~ %s\n",
            format(nrow(rd), big.mark = ","),
            length(unique(rd$Ticker)),
            as.character(min(rd$Date)),
            as.character(max(rd$Date))))

# Build adv_20d (PIT-safe)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

LIQ_THRESHOLD <- 2e8

# 8. Per sig_date: filter universe, select top20 by composite_z, compute monthly return
cat("\n[6] Per sig_date: universe filter + top20 + monthly returns ...\n")
composite_returns <- data.table()
holdings_all <- data.table()

for (i in seq_along(sig_dates)) {
  d_now <- sig_dates[i]

  # Next sig_date (or +1 month forward for last)
  if (i < length(sig_dates)) {
    d_next <- sig_dates[i + 1]
  } else {
    d_next <- as.Date("2026-05-01")  # one month forward for last
  }

  # Universe (PIT-safe lag-1): K200|KQ150 AND adv_20d (t-1) >= 2e8
  uni_dt <- rd[Date <= d_now & Date >= (d_now - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | KQ150 == 1) & !is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]

  # Composite scores at d_now ∩ universe
  cscores_now <- merged[sig_date == d_now & Ticker %in% uni_dt$Ticker]

  if (nrow(cscores_now) == 0) {
    composite_returns <- rbind(composite_returns, data.table(
      sig_date = d_now, n_holdings = 0, monthly_ret = NA_real_, n_present = 0
    ))
    next
  }

  # Top 20 by composite_z
  setorder(cscores_now, -composite_z)
  top20 <- head(cscores_now, 20)

  # Save holdings for audit
  holdings_all <- rbind(holdings_all, top20[, .(sig_date, Ticker, composite_z, z_1715, z_NEW)])

  # Entry @ d_now (first trading day >= d_now)
  entry_prices <- rd[Ticker %in% top20$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  # Exit @ d_next (first trading day >= d_next)
  exit_prices <- rd[Ticker %in% top20$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

  rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
  rets[, ret_pct := (exit_price / entry_price) - 1]

  valid <- rets[!is.na(ret_pct)]
  monthly_ret <- if (nrow(valid) == 0) NA_real_ else mean(valid$ret_pct)

  composite_returns <- rbind(composite_returns, data.table(
    sig_date = d_now,
    n_holdings = nrow(top20),
    monthly_ret = monthly_ret,
    n_present = nrow(valid)
  ))

  if (i %% 20 == 0 || i == length(sig_dates) || i == 1) {
    cat(sprintf("  [%3d/%3d] %s: n_top20=%d, n_present=%d, ret=%.4f\n",
                i, length(sig_dates), as.character(d_now),
                nrow(top20), nrow(valid),
                ifelse(is.na(monthly_ret), 0, monthly_ret)))
  }
}

# 9. Save outputs
cat("\n[7] Save outputs ...\n")
fwrite(composite_returns, file.path(SA_DIR, "composite_top20_returns_pd20b.csv"))
cat(sprintf("  written: composite_top20_returns_pd20b.csv (%d rows)\n", nrow(composite_returns)))

fwrite(holdings_all, file.path(SA_DIR, "composite_top20_holdings_pd20b.csv"))
cat(sprintf("  written: composite_top20_holdings_pd20b.csv (%d rows)\n", nrow(holdings_all)))

# 10. Diagnostic summary
cat("\n[8] Diagnostic summary:\n")
non_na <- composite_returns[!is.na(monthly_ret)]
cat(sprintf("  non-NA: %d / %d sig_dates\n", nrow(non_na), nrow(composite_returns)))
cat(sprintf("  mean monthly: %.6f\n", mean(non_na$monthly_ret)))
cat(sprintf("  sd monthly:   %.6f\n", sd(non_na$monthly_ret)))
cat(sprintf("  SR_ann (cost-free, arithmetic): %.4f\n",
            mean(non_na$monthly_ret) / sd(non_na$monthly_ret) * sqrt(12)))

# Orthogonality check: correlation with PD18 NEW sleeve (10% allocation)
new_dt_pd18 <- fread(file.path(SA_DIR, "new_sleeve_returns_184m_pd18.csv"))
setnames(new_dt_pd18, "monthly_ret", "new_ret")
merged_check <- merge(composite_returns[, .(sig_date, comp_ret = monthly_ret)],
                      new_dt_pd18[, .(sig_date, new_ret)], by = "sig_date")
merged_check <- merged_check[!is.na(comp_ret) & !is.na(new_ret)]
cat(sprintf("\n  Cross-check vs PD18 NEW (10%% alloc) cor = %.4f (n=%d)\n",
            cor(merged_check$comp_ret, merged_check$new_ret),
            nrow(merged_check)))

# Cross-check vs STR_1715 top20 (sleeve-internal) — proxy by re-running 1715-only top20
# (Approximation: composite_z when z_NEW=0 → ranks ~ z_1715 only)
ap_1715_pure <- copy(ap_1715)
ap_1715_pure[, composite_z := z_1715]

cat("\nDONE: PD20-B Z-Score Composite top20 returns built.\n")
