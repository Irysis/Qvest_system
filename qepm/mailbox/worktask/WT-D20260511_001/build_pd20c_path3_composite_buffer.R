#==============================================================================
# WT-D20260511_001 PD20-C Path 3 — Z-Score Composite top20 (composite 0.45 + buffer zone keep25/entry20)
#
# Mitigation of Codex C5 HARD FAIL (PD20-B Path 2 round-trip 685% > 600% Hurdle Gate v2.2):
#   - Composite KR equity sleeve weight 0.55 -> 0.45 (NEW alpha contribution 축소)
#   - Buffer zone keep25/entry20 — name churn smoothing (hysteresis band)
#   - Cash sleeve 4.5% -> 14.5% (option 1 conservative redistribute)
#
# Composite internal ratio retain (within sleeve):
#   w_1715' = 0.45 / (0.45 + 0.10) = 0.8182
#   w_NEW'  = 0.10 / (0.45 + 0.10) = 0.1818
#
# Buffer zone keep25/entry20 (hysteresis band TO control):
#   keep_n = 25 (existing holdings retained if rank <= 25)
#   entry_n = 20 (new entries require rank <= 20)
#   n_target = 20 strict
#
# Sleeve weights (PD20-C Path 3):
#   Composite KR equity: 45% (composite top20, buffer zone keep25/entry20)
#   TSMOM_8_ETF: 22.5% retain
#   KR_10y: 18% retain
#   Cash: 14.5% (4.5 + 10 redistribution)
#
# Pure function (alpha/risk/optimization READ-ONLY): 3-package md5sum start/end
#
# PIT C1~C15 정합 (inherit PD20-B PIT-fix):
#   - z-score per sig_date (expanding direction-align)
#   - 1715 H1 alpha + NEW alpha sig_date alignment
#   - Universe filter at d_lag = d_now - 1 (strict t-1 ADV_20d)
#   - Buffer zone keep25 PIT-aware: previous-rebal holdings (sequential, no lookahead)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

SA_DIR <- "stage_artifacts/WT_D20260511_001"
ITER5_DIR <- "stage_artifacts/WT_D20260425_010"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
RAW_PATH <- ".cache/rawdata.parquet"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20c_path3")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("=== PD20-C Path 3 Z-Score Composite + Buffer Zone keep25/entry20 ===\n\n")

# 1. 3-package md5sum (start)
md5_start <- list(
  alpha    = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk     = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt      = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("3-package md5sum START:\n")
cat("  alpha:", md5_start$alpha, "\n")
cat("  risk: ", md5_start$risk, "\n")
cat("  opt:  ", md5_start$opt, "\n")

# 2. Composite weights (internal ratio retain)
w_1715 <- 0.45 / (0.45 + 0.10)  # 0.8182
w_NEW  <- 0.10 / (0.45 + 0.10)  # 0.1818
cat(sprintf("\nComposite internal: w_1715' = %.4f, w_NEW' = %.4f, sum = %.4f\n",
            w_1715, w_NEW, w_1715 + w_NEW))

# 3. Load alphas
ap_new <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates <- sort(unique(ap_new$sig_date))
cat(sprintf("\nNEW alpha sig_dates: %d (%s ~ %s)\n",
            length(sig_dates), as.character(min(sig_dates)), as.character(max(sig_dates))))

ap_1715 <- as.data.table(read_parquet(file.path(ITER5_DIR, "alpha_scores.parquet")))
ap_1715 <- ap_1715[, .(Date, Ticker, score_eff)]
setnames(ap_1715, "Date", "sig_date")
ap_1715 <- ap_1715[sig_date %in% sig_dates]

# Per-sig_date z-score (PIT-safe — uses only same-date cross-section)
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
cat(sprintf("merged composite rows: %d\n", nrow(merged)))

# 4. Load rawdata
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

LIQ_THRESHOLD <- 2e8
N_TARGET <- 20L
KEEP_N <- 25L
ENTRY_N <- 20L

cat(sprintf("\nBuffer zone config: keep_n=%d, entry_n=%d, n_target=%d\n",
            KEEP_N, ENTRY_N, N_TARGET))
cat(sprintf("Liquidity threshold: %.0e KRW\n", LIQ_THRESHOLD))

# 5. Per sig_date: PIT-strict t-1 universe + buffer zone keep25/entry20 selection
cat("\n[Sequential selection: buffer zone keep25/entry20]\n")

composite_returns <- data.table()
holdings_path3 <- data.table()
prev_holdings <- character(0)  # sequential carry of previous rebal holdings

for (i in seq_along(sig_dates)) {
  d_now <- sig_dates[i]
  d_lag <- d_now - 1L  # PIT-C10 strict t-1

  if (i < length(sig_dates)) {
    d_next <- sig_dates[i + 1]
  } else {
    d_next <- as.Date("2026-05-01")
  }

  # Universe @ d_lag (strict t-1 ADV_20d)
  uni_dt <- rd[Date <= d_lag & Date >= (d_lag - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | KQ150 == 1) & !is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]

  cscores_now <- merged[sig_date == d_now & Ticker %in% uni_dt$Ticker]
  if (nrow(cscores_now) == 0) {
    composite_returns <- rbind(composite_returns, data.table(
      sig_date = d_now, n_holdings = 0, monthly_ret = NA_real_, n_present = 0,
      n_kept = 0, n_new = 0, turnover_oneway = 0
    ))
    prev_holdings <- character(0)
    next
  }

  setorder(cscores_now, -composite_z)
  cscores_now[, rank := .I]

  # === Buffer Zone keep25/entry20 (hysteresis band) ===
  if (length(prev_holdings) > 0) {
    # Retain existing if rank <= KEEP_N (25)
    kept <- cscores_now[Ticker %in% prev_holdings & rank <= KEEP_N]$Ticker
  } else {
    kept <- character(0)
  }

  # New entries: rank <= ENTRY_N (20), not already kept
  new_candidates <- cscores_now[!(Ticker %in% kept) & rank <= ENTRY_N]$Ticker
  n_slots_for_new <- max(0L, N_TARGET - length(kept))
  selected <- c(kept, head(new_candidates, n_slots_for_new))

  # Fill if still under N_TARGET (rare — best-rank fallback)
  if (length(selected) < N_TARGET) {
    fill <- cscores_now[!(Ticker %in% selected)]$Ticker
    n_fill <- N_TARGET - length(selected)
    selected <- c(selected, head(fill, n_fill))
  }

  selected <- head(selected, N_TARGET)

  # TO measurement: one-way turnover this rebal
  if (length(prev_holdings) == 0) {
    to_oneway <- 1.0  # initial full entry
    n_kept_eff <- 0L
    n_new_eff <- length(selected)
  } else {
    n_kept_eff <- length(intersect(selected, prev_holdings))
    n_new_eff <- length(setdiff(selected, prev_holdings))
    to_oneway <- n_new_eff / N_TARGET  # one-way TO = added / target
  }

  # Record holdings
  top20_dt <- cscores_now[Ticker %in% selected]
  top20_dt[, in_top20_rank := rank <= 20]
  holdings_path3 <- rbind(holdings_path3,
                          top20_dt[, .(sig_date, Ticker, composite_z, z_1715, z_NEW,
                                        rank, in_top20_rank)])

  # Entry/exit prices (entry @ d_now, exit @ d_next)
  entry_prices <- rd[Ticker %in% selected & Date >= d_now & Date <= (d_now + 5L)]
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  exit_prices <- rd[Ticker %in% selected & Date >= d_next & Date <= (d_next + 5L)]
  exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

  rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
  rets[, ret_pct := (exit_price / entry_price) - 1]

  valid <- rets[!is.na(ret_pct)]
  monthly_ret <- if (nrow(valid) == 0) NA_real_ else mean(valid$ret_pct)

  composite_returns <- rbind(composite_returns, data.table(
    sig_date = d_now, n_holdings = length(selected), monthly_ret = monthly_ret,
    n_present = nrow(valid), n_kept = n_kept_eff, n_new = n_new_eff,
    turnover_oneway = to_oneway
  ))

  # Carry forward
  prev_holdings <- selected

  if (i %% 30 == 0 || i == length(sig_dates) || i == 1) {
    cat(sprintf("  [%3d/%3d] %s: n=%d, kept=%d, new=%d, TO_oneway=%.3f, ret=%.4f\n",
                i, length(sig_dates), as.character(d_now),
                length(selected), n_kept_eff, n_new_eff, to_oneway,
                ifelse(is.na(monthly_ret), 0, monthly_ret)))
  }
}

cat(sprintf("\nGenerated composite returns: %d sig_dates\n", nrow(composite_returns)))
non_na <- composite_returns[!is.na(monthly_ret)]
cat(sprintf("Non-NA: %d/%d\n", nrow(non_na), nrow(composite_returns)))

# 6. TO diagnostic
mean_to_oneway <- mean(composite_returns$turnover_oneway)
mean_to_oneway_post_init <- mean(composite_returns$turnover_oneway[-1])  # exclude initial 1.0
cat(sprintf("\n[Path 3 Composite TO (Buffer zone keep25/entry20)]\n"))
cat(sprintf("  Mean one-way TO per rebal: %.4f (annual %.1f%%)\n",
            mean_to_oneway, mean_to_oneway * 12 * 100))
cat(sprintf("  Mean (excl initial entry): %.4f (annual %.1f%%)\n",
            mean_to_oneway_post_init, mean_to_oneway_post_init * 12 * 100))
cat(sprintf("  Round-trip TO annual: %.1f%%\n", mean_to_oneway_post_init * 12 * 100 * 2))

# Compare with PD20-B (no buffer) round-trip 1245.7%
cat(sprintf("\n[vs PD20-B Path 2 sleeve-internal TO]\n"))
cat(sprintf("  PD20-B no-buffer round-trip: 1245.7%% annual\n"))
cat(sprintf("  Path 3 buffer keep25/entry20 round-trip: %.1f%% annual\n",
            mean_to_oneway_post_init * 12 * 100 * 2))
cat(sprintf("  TO reduction: %.1f%%\n",
            (1245.7 - mean_to_oneway_post_init * 12 * 100 * 2) / 1245.7 * 100))

# 7. Save composite returns + holdings
fwrite(composite_returns, file.path(SA_DIR, "composite_top20_returns_pd20c_path3.csv"))
fwrite(holdings_path3, file.path(SA_DIR, "composite_top20_holdings_pd20c_path3.csv"))

# 8. Merge with 4-sleeve baseline
sm <- fread("qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv")
sm[, Date := as.Date(date)]
setorder(sm, Date)

comp_dt <- composite_returns[, .(sig_date, monthly_ret)]
comp_dt[, Date := as.Date(sig_date)]
setnames(comp_dt, "monthly_ret", "Composite_path3")
comp_dt[is.na(Composite_path3), Composite_path3 := 0]

sm[, ym := format(Date, "%Y-%m")]
comp_dt[, ym := format(Date, "%Y-%m")]
sm_comp <- merge(sm, comp_dt[, .(ym, Composite_path3)], by = "ym", all.x = TRUE)
sm_comp[is.na(Composite_path3), Composite_path3 := 0]
setorder(sm_comp, Date)

# 9. Path 3 sleeve weights (composite 0.45 + Cash 14.5% redistribute)
w_COMP   <- 0.450   # Composite KR equity (-10pp vs PD20-B 0.55)
w_TSMOM  <- 0.225   # TSMOM_8_ETF retain
w_KR     <- 0.180   # KR_10y retain
w_CASH   <- 0.145   # Cash (4.5 + 10 redistribute)
w_sum    <- w_COMP + w_TSMOM + w_KR + w_CASH
stopifnot(abs(w_sum - 1.0) < 1e-9)
cat(sprintf("\nPath 3 sleeve weights:\n"))
cat(sprintf("  Composite: %.3f\n", w_COMP))
cat(sprintf("  TSMOM:     %.3f\n", w_TSMOM))
cat(sprintf("  KR_10y:    %.3f\n", w_KR))
cat(sprintf("  Cash:      %.3f (option 1: +10pp from PD20-B 4.5%%)\n", w_CASH))
cat(sprintf("  Sum:       %.4f\n", w_sum))

# 10. Pre-2011 redistribute: S4 v2 baseline (50/25/20/5) — same as PD20-B
#     Path 3 active period 2011-01 onward (Composite non-zero)
sm_comp[, ret_pd20c_path3 := ifelse(
  Composite_path3 != 0,
  w_COMP * Composite_path3 + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash,
  0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash
)]

# 11. Cost embedding: portfolio-weighted at composite-level
# Composite sleeve internal TO (from buffer zone): mean_to_oneway_post_init
# Portfolio-weighted Composite TO = w_COMP * sleeve_TO
# Mix with baseline ~10% one-way for TSMOM/KR/Cash blocs
COST_BPS_ONEWAY <- 0.0015

sm_comp[, turnover_oneway_path3 := ifelse(Composite_path3 != 0,
                                            w_COMP * mean_to_oneway_post_init + (1 - w_COMP) * 0.10,
                                            0.50 * 0.10)]
sm_comp[, cost_drag_path3 := 2 * turnover_oneway_path3 * COST_BPS_ONEWAY]
sm_comp[, ret_pd20c_path3_net := ret_pd20c_path3 - cost_drag_path3]

# 12. Metrics
non_na_net <- sm_comp[!is.na(ret_pd20c_path3_net)]
xt_net <- xts(non_na_net$ret_pd20c_path3_net, order.by = non_na_net$Date)

metrics <- list()
metrics$N <- nrow(non_na_net)
metrics$SR_ann_geometric <- as.numeric(SharpeRatio.annualized(xt_net, scale = 12, geometric = TRUE))
metrics$CAGR <- as.numeric(Return.annualized(xt_net, scale = 12, geometric = TRUE))
metrics$MDD <- as.numeric(maxDrawdown(xt_net, geometric = TRUE))
metrics$Sortino <- as.numeric(SortinoRatio(xt_net, MAR = 0)) * sqrt(12)
metrics$Calmar <- as.numeric(CalmarRatio(xt_net, scale = 12))
metrics$CVaR_95_monthly <- as.numeric(ES(xt_net, p = 0.95, method = "historical"))
metrics$CVaR_99_monthly <- as.numeric(ES(xt_net, p = 0.99, method = "historical"))
metrics$hit_rate <- as.numeric(mean(non_na_net$ret_pd20c_path3_net > 0))
metrics$mean_ann <- as.numeric(Return.annualized(xt_net, scale = 12, geometric = FALSE))
metrics$vol_ann <- as.numeric(StdDev.annualized(xt_net, scale = 12))
metrics$mean_turnover_oneway_sleeve_internal <- mean_to_oneway_post_init
metrics$mean_turnover_round_trip_sleeve_internal_annual_pct <- mean_to_oneway_post_init * 12 * 100 * 2
metrics$portfolio_weighted_round_trip_annual_pct <- 12 * 2 * mean(sm_comp$turnover_oneway_path3[sm_comp$Composite_path3 != 0])
metrics$mean_cost_drag_annual_bps <- mean(sm_comp$cost_drag_path3, na.rm = TRUE) * 12 * 1e4

cat("\n[PD20-C Path 3 metrics (256m, 15bps embedded, buffer zone keep25/entry20)]\n")
cat(sprintf("  N=%d months (%s ~ %s)\n",
            metrics$N, as.character(min(non_na_net$Date)), as.character(max(non_na_net$Date))))
cat(sprintf("  SR_ann_geometric: %.4f\n", metrics$SR_ann_geometric))
cat(sprintf("  CAGR:             %.4f\n", metrics$CAGR))
cat(sprintf("  MDD:              %.4f\n", metrics$MDD))
cat(sprintf("  Sortino:          %.4f\n", metrics$Sortino))
cat(sprintf("  Calmar:           %.4f\n", metrics$Calmar))
cat(sprintf("  CVaR_95_monthly:  %.4f\n", metrics$CVaR_95_monthly))
cat(sprintf("  CVaR_99_monthly:  %.4f\n", metrics$CVaR_99_monthly))
cat(sprintf("  hit_rate:         %.4f\n", metrics$hit_rate))
cat(sprintf("  vol_ann:          %.4f\n", metrics$vol_ann))
cat(sprintf("  sleeve_internal TO (one-way annual): %.1f%%\n",
            metrics$mean_turnover_oneway_sleeve_internal * 12 * 100))
cat(sprintf("  sleeve_internal TO (round-trip annual): %.1f%%\n",
            metrics$mean_turnover_round_trip_sleeve_internal_annual_pct))
cat(sprintf("  portfolio-weighted TO (round-trip annual): %.1f%%\n",
            metrics$portfolio_weighted_round_trip_annual_pct))
cat(sprintf("  cost_drag_annual_bps: %.2f\n", metrics$mean_cost_drag_annual_bps))

# Hurdle Gate v2.2 check
cat("\n[Hurdle Gate v2.2 TO check]\n")
to_rt_sleeve <- metrics$mean_turnover_round_trip_sleeve_internal_annual_pct
to_rt_port <- metrics$portfolio_weighted_round_trip_annual_pct
cat(sprintf("  Sleeve-internal RT TO: %.1f%% (hurdle 600%% -> %s)\n",
            to_rt_sleeve, ifelse(to_rt_sleeve < 600, "PASS", "FAIL")))
cat(sprintf("  Portfolio-weighted RT TO: %.1f%% (hurdle 600%% -> %s)\n",
            to_rt_port, ifelse(to_rt_port < 600, "PASS", "FAIL")))

# 13. DM vs S4 v2 baseline
sm_comp[, ret_S4_baseline := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]
non_na_dm <- sm_comp[!is.na(ret_pd20c_path3_net) & !is.na(ret_S4_baseline)]
diff <- non_na_dm$ret_pd20c_path3_net - non_na_dm$ret_S4_baseline

nw_lag <- 6
N <- length(diff)
mean_diff <- mean(diff)
nw_var <- var(diff)
for (lag in 1:nw_lag) {
  weight <- 1 - lag / (nw_lag + 1)
  ac <- mean((diff[(lag + 1):N] - mean_diff) * (diff[1:(N - lag)] - mean_diff))
  nw_var <- nw_var + 2 * weight * ac
}
nw_se <- sqrt(nw_var / N)
t_nw <- mean_diff / nw_se
p_nw <- 2 * pnorm(-abs(t_nw))

cat("\n[Diebold-Mariano vs S4 v2 baseline]\n")
cat(sprintf("  N=%d, mean_diff_monthly=%.6f, NW lag6 SE=%.6f\n", N, mean_diff, nw_se))
cat(sprintf("  t_NW = %.4f, p = %.4f\n", t_nw, p_nw))
cat(sprintf("  Harvey-Liu-Zhu (2016) strict t > 3.0: %s\n",
            ifelse(abs(t_nw) > 3.0, "PASS", "FAIL")))

# S4 v2 baseline metrics
xt_S4 <- xts(non_na_dm$ret_S4_baseline, order.by = non_na_dm$Date)
S4_SR <- as.numeric(SharpeRatio.annualized(xt_S4, scale = 12, geometric = TRUE))
S4_CAGR <- as.numeric(Return.annualized(xt_S4, scale = 12, geometric = TRUE))
S4_MDD <- as.numeric(maxDrawdown(xt_S4, geometric = TRUE))
S4_CVaR_95 <- as.numeric(ES(xt_S4, p = 0.95, method = "historical"))

cat(sprintf("\n[S4 v2 baseline (50/25/20/5) realized 256m]\n"))
cat(sprintf("  SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f\n",
            S4_SR, S4_CAGR, S4_MDD, S4_CVaR_95))

# 14. vs PD20-B Path 2 comparison
pd20b_dt <- fread(file.path(WT_DIR, "backtest_result_pd20b/composite_returns_4sleeve_pd20b.csv"))
pd20b_dt[, Date := as.Date(Date)]
merged_pd20b <- merge(non_na_net[, .(Date, path3 = ret_pd20c_path3_net)],
                       pd20b_dt[, .(Date, pd20b = ret_pd20b_path2_net)],
                       by = "Date")
merged_pd20b <- merged_pd20b[!is.na(path3) & !is.na(pd20b)]

xt_pd20b <- xts(merged_pd20b$pd20b, order.by = merged_pd20b$Date)
PD20B_SR <- as.numeric(SharpeRatio.annualized(xt_pd20b, scale = 12, geometric = TRUE))
PD20B_CAGR <- as.numeric(Return.annualized(xt_pd20b, scale = 12, geometric = TRUE))
PD20B_MDD <- as.numeric(maxDrawdown(xt_pd20b, geometric = TRUE))
PD20B_CVaR <- as.numeric(ES(xt_pd20b, p = 0.95, method = "historical"))

cat(sprintf("\n[vs PD20-B Path 2 (composite 0.55, no buffer, 15bps embedded)]\n"))
cat(sprintf("  PD20-B: SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f\n",
            PD20B_SR, PD20B_CAGR, PD20B_MDD, PD20B_CVaR))
cat(sprintf("  Path 3: SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f\n",
            metrics$SR_ann_geometric, metrics$CAGR, metrics$MDD, metrics$CVaR_95_monthly))
cat(sprintf("  Delta SR (vs PD20-B): %.4f\n", metrics$SR_ann_geometric - PD20B_SR))
cat(sprintf("  Delta CAGR pp (vs PD20-B): %.4f\n", (metrics$CAGR - PD20B_CAGR) * 100))
cat(sprintf("  Delta MDD pp (vs PD20-B): %.4f\n", (metrics$MDD - PD20B_MDD) * 100))

# 15. vs PD20-A Path 1
# load from pd20a path1 dir if exists
pd20a_path1_dir <- file.path(WT_DIR, "backtest_result_pd20a_path1")
if (file.exists(file.path(pd20a_path1_dir, "metrics_pd20a_path1.rds"))) {
  pd20a_metrics <- readRDS(file.path(pd20a_path1_dir, "metrics_pd20a_path1.rds"))
  cat(sprintf("\n[vs PD20-A Path 1 (16+4 split)]\n"))
  cat(sprintf("  PD20-A: SR=%.4f, CAGR=%.4f, MDD=%.4f\n",
              pd20a_metrics$metrics$SR_ann_geometric,
              pd20a_metrics$metrics$CAGR,
              pd20a_metrics$metrics$MDD))
}

# 16. Strict improve evaluation (4-axis vs S4 v2 baseline)
strict_improve <- list(
  criteria = list(
    SR_threshold = round(S4_SR, 4),
    MDD_threshold_pp = round(S4_MDD, 4),
    CVaR_threshold = round(S4_CVaR_95, 4),
    CAGR_threshold = round(S4_CAGR, 4)
  ),
  path3 = list(
    SR_pass = metrics$SR_ann_geometric > S4_SR,
    delta_SR = round(metrics$SR_ann_geometric - S4_SR, 4),
    MDD_pass = metrics$MDD > S4_MDD,  # less negative = better
    delta_MDD_pp = round((metrics$MDD - S4_MDD) * 100, 2),
    CVaR_pass = metrics$CVaR_95_monthly > S4_CVaR_95,  # less negative = better
    delta_CVaR_pp = round((metrics$CVaR_95_monthly - S4_CVaR_95) * 100, 2),
    CAGR_pass = metrics$CAGR > S4_CAGR,
    delta_CAGR_pp = round((metrics$CAGR - S4_CAGR) * 100, 2)
  )
)
strict_improve$path3$n_pass <- sum(unlist(strict_improve$path3[grep("_pass$", names(strict_improve$path3))]))
strict_improve$path3$verdict_4_axis <- sprintf("%d/4_PASS", strict_improve$path3$n_pass)
strict_improve$path3$turnover_hurdle_pass <- to_rt_port < 600
strict_improve$path3$verdict_final <- ifelse(
  strict_improve$path3$n_pass == 4 && strict_improve$path3$turnover_hurdle_pass,
  "4_PASS_STRICT_IMPROVE_AND_TO_HURDLE_OK",
  ifelse(strict_improve$path3$turnover_hurdle_pass,
         sprintf("%d/4_PASS_TO_OK", strict_improve$path3$n_pass),
         sprintf("%d/4_PASS_TO_HARD_FAIL", strict_improve$path3$n_pass)))

cat("\n[Strict improve evaluation vs S4 v2 baseline]\n")
cat(sprintf("  SR pass:   %s (delta %+.4f)\n",
            strict_improve$path3$SR_pass, strict_improve$path3$delta_SR))
cat(sprintf("  MDD pass:  %s (delta %+.2fpp, target_pp=%.2f)\n",
            strict_improve$path3$MDD_pass, strict_improve$path3$delta_MDD_pp,
            S4_MDD * 100))
cat(sprintf("  CVaR pass: %s (delta %+.2fpp)\n",
            strict_improve$path3$CVaR_pass, strict_improve$path3$delta_CVaR_pp))
cat(sprintf("  CAGR pass: %s (delta %+.2fpp)\n",
            strict_improve$path3$CAGR_pass, strict_improve$path3$delta_CAGR_pp))
cat(sprintf("  4-axis: %s\n", strict_improve$path3$verdict_4_axis))
cat(sprintf("  TO hurdle (port-weighted RT < 600%%): %s\n",
            strict_improve$path3$turnover_hurdle_pass))
cat(sprintf("  Final verdict: %s\n", strict_improve$path3$verdict_final))

# 17. Save outputs
fwrite(sm_comp, file.path(OUT_DIR, "sleeve_panel_pd20c_path3.csv"))
fwrite(non_na_net, file.path(OUT_DIR, "composite_returns_4sleeve_pd20c_path3.csv"))

# nav.csv
nav_dt <- copy(non_na_net)
nav_dt[, nav := cumprod(1 + ret_pd20c_path3_net)]
nav_dt <- nav_dt[, .(Date, ret = ret_pd20c_path3_net, nav)]
fwrite(nav_dt, file.path(OUT_DIR, "nav.csv"))

# period_returns
pr_dt <- non_na_net[, .(Date,
                         strategy_return = ret_pd20c_path3,
                         cost_ret = cost_drag_path3,
                         net_return = ret_pd20c_path3_net,
                         turnover_oneway = turnover_oneway_path3,
                         AR_on_M4, TSMOM, KR_10y, Cash, Composite = Composite_path3)]
fwrite(pr_dt, file.path(OUT_DIR, "period_returns.csv"))

# metrics
metrics_dt <- data.table(
  metric = names(metrics),
  value = unlist(metrics),
  metric_type = "backtested"
)
fwrite(metrics_dt, file.path(OUT_DIR, "metrics.csv"))

# benchmark_compare
bc_dt <- data.table(
  strategy = c("PD20C_Path3", "S4_v2_baseline", "PD20B_Path2"),
  SR = c(metrics$SR_ann_geometric, S4_SR, PD20B_SR),
  CAGR = c(metrics$CAGR, S4_CAGR, PD20B_CAGR),
  MDD = c(metrics$MDD, S4_MDD, PD20B_MDD),
  CVaR_95 = c(metrics$CVaR_95_monthly, S4_CVaR_95, PD20B_CVaR)
)
bc_dt[, delta_SR_vs_S4 := SR - S4_SR]
bc_dt[, delta_CAGR_vs_S4 := CAGR - S4_CAGR]
bc_dt[, delta_MDD_vs_S4 := MDD - S4_MDD]
fwrite(bc_dt, file.path(OUT_DIR, "benchmark_compare.csv"))

# DM
dm_dt <- data.table(
  measure = "Diebold-Mariano",
  N = N,
  mean_diff_monthly = mean_diff,
  NW_lag6_SE = nw_se,
  t_NW = t_nw,
  p_value = p_nw,
  hlz_pass = abs(t_nw) > 3.0
)
fwrite(dm_dt, file.path(OUT_DIR, "diebold_mariano.csv"))

# 18. 3-package md5sum (end)
md5_end <- list(
  alpha    = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk     = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt      = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("\n3-package md5sum END:\n")
cat("  alpha:", md5_end$alpha, "\n")
cat("  risk: ", md5_end$risk, "\n")
cat("  opt:  ", md5_end$opt, "\n")
md5_match <- (md5_start$alpha == md5_end$alpha &&
              md5_start$risk == md5_end$risk &&
              md5_start$opt == md5_end$opt)
cat("Pure function audit:", ifelse(md5_match, "PASS", "FAIL"), "\n")

md5_audit <- data.table(
  package = c("alpha", "risk", "optimization"),
  md5_start = c(md5_start$alpha, md5_start$risk, md5_start$opt),
  md5_end = c(md5_end$alpha, md5_end$risk, md5_end$opt),
  match = c(md5_start$alpha == md5_end$alpha,
            md5_start$risk == md5_end$risk,
            md5_start$opt == md5_end$opt)
)
fwrite(md5_audit, file.path(OUT_DIR, "pure_function_audit.csv"))

# 19. Save metrics rds
saveRDS(list(
  metrics = metrics,
  S4_baseline = list(SR = S4_SR, CAGR = S4_CAGR, MDD = S4_MDD, CVaR_95 = S4_CVaR_95),
  PD20B_aligned = list(SR = PD20B_SR, CAGR = PD20B_CAGR, MDD = PD20B_MDD, CVaR_95 = PD20B_CVaR),
  DM = list(t_NW = t_nw, p = p_nw, N = N, mean_diff = mean_diff, nw_se = nw_se),
  strict_improve = strict_improve,
  buffer_zone = list(keep_n = KEEP_N, entry_n = ENTRY_N, n_target = N_TARGET),
  sleeve_weights = list(COMP = w_COMP, TSMOM = w_TSMOM, KR = w_KR, CASH = w_CASH),
  composite_internal_ratio = list(w_1715 = w_1715, w_NEW = w_NEW),
  pure_function = list(md5_start = md5_start, md5_end = md5_end, match = md5_match)
), file.path(OUT_DIR, "metrics_pd20c_path3.rds"))

cat("\nDONE: PD20-C Path 3 Forge backtest (Composite 0.45 + Buffer keep25/entry20 + Cash 14.5%).\n")
cat("Outputs in:", OUT_DIR, "\n")
