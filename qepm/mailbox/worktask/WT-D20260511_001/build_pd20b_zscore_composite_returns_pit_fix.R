#==============================================================================
# WT-D20260511_001 PD20-B PIT FIX — Strict PIT-C10 t-1 liquidity filter
#
# Codex C2 HIGH severity: 92/184 sig_dates are trading days where ADV_20d
# rolled with right-alignment included same-day vol — PIT-C10 violation.
#
# This script re-runs the build with STRICT t-1 lag for liquidity filter
# AND computes top20 overlap + metric deltas vs original PD20-B build.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics)
})

SA_DIR <- "stage_artifacts/WT_D20260511_001"
ITER5_DIR <- "stage_artifacts/WT_D20260425_010"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
RAW_PATH <- ".cache/rawdata.parquet"

cat("=== PD20-B PIT-C10 strict t-1 fix re-run ===\n\n")

# Composite weights
w_1715 <- 0.45 / (0.45 + 0.10)  # 0.8182
w_NEW  <- 0.10 / (0.45 + 0.10)  # 0.1818

# Load alphas
ap_new <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates <- sort(unique(ap_new$sig_date))

ap_1715 <- as.data.table(read_parquet(file.path(ITER5_DIR, "alpha_scores.parquet")))
ap_1715 <- ap_1715[, .(Date, Ticker, score_eff)]
setnames(ap_1715, "Date", "sig_date")
ap_1715 <- ap_1715[sig_date %in% sig_dates]

# Per-sig_date z-score
ap_1715[, z_1715 := scale(score_eff)[, 1], by = sig_date]
ap_new[, z_NEW := scale(alpha)[, 1], by = sig_date]

setkey(ap_1715, sig_date, Ticker)
setkey(ap_new, sig_date, Ticker)
merged <- merge(ap_new[, .(sig_date, Ticker, z_NEW)],
                ap_1715[, .(sig_date, Ticker, z_1715)],
                by = c("sig_date", "Ticker"), all.x = TRUE)
merged[is.na(z_1715), z_1715 := 0]
merged[is.na(z_NEW), z_NEW := 0]
merged[, composite_z := w_1715 * z_1715 + w_NEW * z_NEW]

# Load rawdata
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)

# Compute adv_20d (regardless of how it's used later)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

LIQ_THRESHOLD <- 2e8

cat("[Per sig_date: STRICT t-1 lag liquidity filter + top20 + monthly returns]\n")
composite_returns_pit_fix <- data.table()
holdings_pit_fix <- data.table()

for (i in seq_along(sig_dates)) {
  d_now <- sig_dates[i]

  # PIT-C10 STRICT: use t-1 day for liquidity (no same-day even if d_now is trading day)
  # d_lag = d_now - 1 (calendar day prior — most recent trading day before d_now)
  d_lag <- d_now - 1L

  if (i < length(sig_dates)) {
    d_next <- sig_dates[i + 1]
  } else {
    d_next <- as.Date("2026-05-01")
  }

  # Universe @ d_lag (strict t-1): K200|KQ150 AND adv_20d (at d_lag, fully t-1) >= 2e8
  uni_dt <- rd[Date <= d_lag & Date >= (d_lag - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | KQ150 == 1) & !is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]

  cscores_now <- merged[sig_date == d_now & Ticker %in% uni_dt$Ticker]
  if (nrow(cscores_now) == 0) {
    composite_returns_pit_fix <- rbind(composite_returns_pit_fix, data.table(
      sig_date = d_now, n_holdings = 0, monthly_ret = NA_real_, n_present = 0
    ))
    next
  }

  setorder(cscores_now, -composite_z)
  top20 <- head(cscores_now, 20)

  holdings_pit_fix <- rbind(holdings_pit_fix,
                             top20[, .(sig_date, Ticker, composite_z, z_1715, z_NEW)])

  # Entry/exit prices (same as before — these are entry @ d_now)
  entry_prices <- rd[Ticker %in% top20$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  exit_prices <- rd[Ticker %in% top20$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

  rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
  rets[, ret_pct := (exit_price / entry_price) - 1]

  valid <- rets[!is.na(ret_pct)]
  monthly_ret <- if (nrow(valid) == 0) NA_real_ else mean(valid$ret_pct)

  composite_returns_pit_fix <- rbind(composite_returns_pit_fix, data.table(
    sig_date = d_now, n_holdings = nrow(top20), monthly_ret = monthly_ret, n_present = nrow(valid)
  ))

  if (i %% 30 == 0 || i == length(sig_dates) || i == 1) {
    cat(sprintf("  [%3d/%3d] %s: top20=%d, ret=%.4f\n",
                i, length(sig_dates), as.character(d_now),
                nrow(top20), ifelse(is.na(monthly_ret), 0, monthly_ret)))
  }
}

# Save outputs
fwrite(composite_returns_pit_fix, file.path(SA_DIR, "composite_top20_returns_pd20b_pit_fix.csv"))
fwrite(holdings_pit_fix, file.path(SA_DIR, "composite_top20_holdings_pd20b_pit_fix.csv"))

# Diagnostic
non_na <- composite_returns_pit_fix[!is.na(monthly_ret)]
cat(sprintf("\nPIT-fix results: non-NA %d/%d sig_dates\n", nrow(non_na), nrow(composite_returns_pit_fix)))
cat(sprintf("  mean monthly: %.6f, sd: %.6f, SR_ann_arith: %.4f\n",
            mean(non_na$monthly_ret), sd(non_na$monthly_ret),
            mean(non_na$monthly_ret) / sd(non_na$monthly_ret) * sqrt(12)))

# Compare with original (non PIT-fix)
orig_dt <- fread(file.path(SA_DIR, "composite_top20_returns_pd20b.csv"))
fix_dt <- composite_returns_pit_fix
merged_compare <- merge(orig_dt[, .(sig_date, orig_ret = monthly_ret)],
                         fix_dt[, .(sig_date, fix_ret = monthly_ret)],
                         by = "sig_date")
merged_compare <- merged_compare[!is.na(orig_ret) & !is.na(fix_ret)]

# Top20 overlap per sig_date
orig_hd <- fread(file.path(SA_DIR, "composite_top20_holdings_pd20b.csv"))
fix_hd <- holdings_pit_fix

overlap_stats <- data.table()
common_dates <- intersect(unique(orig_hd$sig_date), unique(fix_hd$sig_date))
for (d in common_dates) {
  o <- orig_hd[sig_date == d]$Ticker
  f <- fix_hd[sig_date == d]$Ticker
  overlap_stats <- rbind(overlap_stats,
                          data.table(sig_date = as.Date(d),
                                     n_overlap = length(intersect(o, f)),
                                     n_orig = length(o), n_fix = length(f)))
}
mean_overlap <- mean(overlap_stats$n_overlap)
cat(sprintf("\n[Top20 overlap PIT-fix vs original]\n"))
cat(sprintf("  Mean overlap: %.2f / 20 (%.1f%%)\n", mean_overlap, mean_overlap / 20 * 100))
cat(sprintf("  Days with overlap < 19: %d / %d\n",
            nrow(overlap_stats[n_overlap < 19]), nrow(overlap_stats)))
cat(sprintf("  Days with overlap < 15: %d / %d\n",
            nrow(overlap_stats[n_overlap < 15]), nrow(overlap_stats)))

# Return delta
ret_diff <- merged_compare$fix_ret - merged_compare$orig_ret
cat(sprintf("\n[Return delta PIT-fix - original]\n"))
cat(sprintf("  mean diff: %.6f\n", mean(ret_diff)))
cat(sprintf("  max |diff|: %.6f\n", max(abs(ret_diff))))
cat(sprintf("  cor(orig, fix): %.6f\n", cor(merged_compare$orig_ret, merged_compare$fix_ret)))

# SR comparison
mean_orig <- mean(merged_compare$orig_ret)
sd_orig <- sd(merged_compare$orig_ret)
SR_orig <- mean_orig / sd_orig * sqrt(12)
mean_fix <- mean(merged_compare$fix_ret)
sd_fix <- sd(merged_compare$fix_ret)
SR_fix <- mean_fix / sd_fix * sqrt(12)
cat(sprintf("\nArithmetic SR_ann: orig=%.4f, fix=%.4f, Δ=%.4f\n",
            SR_orig, SR_fix, SR_fix - SR_orig))

cat("\nDONE: PD20-B PIT-C10 strict t-1 fix re-run\n")
