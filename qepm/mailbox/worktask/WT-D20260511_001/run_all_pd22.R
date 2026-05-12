#==============================================================================
# WT-D20260511_001 PD22 — Forge run_all (5-sleeve Cross-Universe Z-Composite top20)
#
# Mission (도훈 mandate 2026-05-12):
#   "5슬리브를 z스코어로 컴포짓해서 탑20 뽑는 전략으로 프로즌없이 전 기간 백테해서
#    현재 pg2랑 성과 비교해봐"
#
# Design (Forge 자율 결정):
#   - 5 sleeve cross-universe top20 z-composite ranking
#   - KR equity: z_kr = 0.818 × z_1715 + 0.182 × z_NEW (PD20-B 정합)
#     - z_1715: Iter5 STR_1715 alpha (score_eff, 268m 2004-01 ~ 2026-04, 846 tickers)
#     - z_NEW: NEW Vol/Skew (184m 2011-01 ~ 2026-04, 770 tickers)
#   - TSMOM_basket (1 unit): rolling 36m z-score of TSMOM monthly return
#   - KR_10y_bond (1 ETF A148070): rolling 36m z-score
#   - Cash: z = -10 (excluded by design)
#   - Universe: 846 + 1 + 1 + 1 = 849 candidates per sig_date
#   - Top20 EW 5% each
#
# Backtest:
#   - 184 sig_dates (2011-01 ~ 2026-04) — NEW alpha 시작점부터 (z_NEW 가용)
#   - Forward 1m returns: Iter5 alpha Ret_1m 직접 사용 + sm$TSMOM/KR_10y/Cash
#   - PerformanceAnalytics geometric=TRUE scale=12
#   - 15bps cost embed (turnover-weighted one-way × 2 round-trip)
#
# Pure function: alpha/risk/optimizer READ-ONLY (md5sum start/end audit)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
ITER5_DIR <- "stage_artifacts/WT_D20260425_010"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd22")
PD22_SA <- file.path(SA_DIR, "pd22")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(PD22_SA, recursive = TRUE, showWarnings = FALSE)

cat("=== PD22 Forge 5-Sleeve Cross-Universe Z-Composite Top20 ===\n")
cat(sprintf("Started: %s\n\n", format(Sys.time())))

#==============================================================================
# 1. 3-package md5sum (start) — Pure function audit
#==============================================================================
md5_start <- list(
  alpha = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk  = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt   = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("3-package md5sum START:\n")
cat("  alpha:", md5_start$alpha, "\n")
cat("  risk: ", md5_start$risk, "\n")
cat("  opt:  ", md5_start$opt, "\n\n")

#==============================================================================
# 2. Load source data
#==============================================================================
sm <- fread("qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv")
sm[, Date := as.Date(date)]
setorder(sm, Date)
cat(sprintf("Sleeve master: %d rows\n", nrow(sm)))

ascores_NEW <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
setnames(ascores_NEW, "alpha", "alpha_NEW")
ascores_NEW <- ascores_NEW[, .(sig_date, Ticker, alpha_NEW)]
cat(sprintf("NEW alpha_scores: %d rows, %d sig_dates\n",
            nrow(ascores_NEW), length(unique(ascores_NEW$sig_date))))

# Iter5 1715 alpha — 268 sig_dates 2004-01 ~ 2026-04, includes Ret_1m
ascores_1715_iter5 <- as.data.table(read_parquet(file.path(ITER5_DIR, "alpha_scores.parquet")))
ascores_1715_iter5 <- ascores_1715_iter5[, .(Date, Ticker, score_eff, Ret_1m)]
setnames(ascores_1715_iter5, "Date", "sig_date")
cat(sprintf("Iter5 1715 alpha: %d rows, %d sig_dates (%s ~ %s), %d tickers\n",
            nrow(ascores_1715_iter5),
            length(unique(ascores_1715_iter5$sig_date)),
            as.character(min(ascores_1715_iter5$sig_date)),
            as.character(max(ascores_1715_iter5$sig_date)),
            length(unique(ascores_1715_iter5$Ticker))))

#==============================================================================
# 3. Build per-asset z-score table per sig_date
#==============================================================================
cat("\n=== Step 3: Per-asset z-score ===\n")

# 3a. z_NEW within sig_date
ascores_NEW[, z_NEW := (alpha_NEW - mean(alpha_NEW, na.rm = TRUE)) /
              sd(alpha_NEW, na.rm = TRUE), by = sig_date]
ascores_NEW[is.na(z_NEW), z_NEW := 0]

# 3b. z_1715 from Iter5 within sig_date
ascores_1715_iter5[, z_1715 := (score_eff - mean(score_eff, na.rm = TRUE)) /
                     sd(score_eff, na.rm = TRUE), by = sig_date]
ascores_1715_iter5[is.na(z_1715), z_1715 := 0]

# 3c. Merge KR universe — outer join (some tickers in 1715 only, some in NEW only)
# Use NEW sig_dates (184m 2011-01 ~ 2026-04) as primary
z_kr <- merge(ascores_NEW[, .(sig_date, Ticker, z_NEW)],
              ascores_1715_iter5[, .(sig_date, Ticker, z_1715, Ret_1m)],
              by = c("sig_date", "Ticker"), all = TRUE)
z_kr <- z_kr[sig_date %in% unique(ascores_NEW$sig_date)]
z_kr[is.na(z_1715), z_1715 := 0]
z_kr[is.na(z_NEW), z_NEW := 0]

# Composite z (PD20-B weight retain)
W_1715 <- 0.818
W_NEW  <- 0.182
z_kr[, composite_z := W_1715 * z_1715 + W_NEW * z_NEW]
cat(sprintf("KR stock z-table: %d rows, %d sig_dates, %d tickers\n",
            nrow(z_kr), length(unique(z_kr$sig_date)), length(unique(z_kr$Ticker))))
cat(sprintf("  Tickers with Ret_1m present: %d (%.1f%%)\n",
            sum(!is.na(z_kr$Ret_1m)), 100 * mean(!is.na(z_kr$Ret_1m))))

# 3d. TSMOM z-score (rolling 36m, lag 1m PIT)
tsmom_dt <- sm[, .(Date, ret = TSMOM)]
setorder(tsmom_dt, Date)
tsmom_dt[, ret_mean_36m := rollapply(ret, 36, mean, fill = NA, align = "right", na.rm = TRUE)]
tsmom_dt[, ret_sd_36m := rollapply(ret, 36, sd, fill = NA, align = "right", na.rm = TRUE)]
tsmom_dt[, z_tsmom := (ret - ret_mean_36m) / ret_sd_36m]
tsmom_dt[is.na(z_tsmom) | is.infinite(z_tsmom), z_tsmom := 0]
tsmom_dt[, z_tsmom_lag1 := shift(z_tsmom, 1)]
tsmom_dt[is.na(z_tsmom_lag1), z_tsmom_lag1 := 0]
tsmom_dt[, ym := format(Date, "%Y-%m")]
cat(sprintf("TSMOM z: range [%.2f, %.2f]\n",
            min(tsmom_dt$z_tsmom_lag1), max(tsmom_dt$z_tsmom_lag1)))

# 3e. KR_10y z-score
kr10y_dt <- sm[, .(Date, ret = KR_10y)]
setorder(kr10y_dt, Date)
kr10y_dt[, ret_mean_36m := rollapply(ret, 36, mean, fill = NA, align = "right", na.rm = TRUE)]
kr10y_dt[, ret_sd_36m := rollapply(ret, 36, sd, fill = NA, align = "right", na.rm = TRUE)]
kr10y_dt[, z_kr10y := (ret - ret_mean_36m) / ret_sd_36m]
kr10y_dt[is.na(z_kr10y) | is.infinite(z_kr10y), z_kr10y := 0]
kr10y_dt[, z_kr10y_lag1 := shift(z_kr10y, 1)]
kr10y_dt[is.na(z_kr10y_lag1), z_kr10y_lag1 := 0]
kr10y_dt[, ym := format(Date, "%Y-%m")]
cat(sprintf("KR_10y z: range [%.2f, %.2f]\n",
            min(kr10y_dt$z_kr10y_lag1), max(kr10y_dt$z_kr10y_lag1)))

#==============================================================================
# 4. Cross-universe top20 selection per sig_date
#==============================================================================
cat("\n=== Step 4: Cross-universe top20 selection ===\n")

sig_dates <- sort(unique(ascores_NEW$sig_date))
cat(sprintf("Total sig_dates: %d (%s ~ %s)\n", length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates))))

all_holdings <- list()
diagnostic <- list()

for (sd in sig_dates) {
  sd_date <- as.Date(sd, origin = "1970-01-01")
  ym_sd <- format(sd_date, "%Y-%m")

  # KR stocks at this sig_date
  kr_subset <- z_kr[sig_date == sd_date,
                    .(asset_id = Ticker, asset_type = "KR_stock",
                      composite_z = composite_z,
                      z_1715, z_NEW, Ret_1m)]

  # TSMOM/KR_10y z
  ts_z <- tsmom_dt[ym == ym_sd, z_tsmom_lag1]
  ts_z <- if (length(ts_z) > 0 && !is.na(ts_z[1])) ts_z[1] else 0

  kr10y_z <- kr10y_dt[ym == ym_sd, z_kr10y_lag1]
  kr10y_z <- if (length(kr10y_z) > 0 && !is.na(kr10y_z[1])) kr10y_z[1] else 0

  # Forward 1m return for sleeve assets (sm$Date at next month = forward return)
  # ym_sd + 1m = forward ym
  sd_plus1 <- sd_date + 32; ym_fwd <- format(as.Date(paste0(format(sd_plus1, "%Y-%m"), "-01")), "%Y-%m")
  sm_fwd <- sm[format(Date, "%Y-%m") == ym_fwd]
  tsmom_ret_fwd <- if (nrow(sm_fwd) > 0) sm_fwd$TSMOM[1] else 0
  kr10y_ret_fwd <- if (nrow(sm_fwd) > 0) sm_fwd$KR_10y[1] else 0
  cash_ret_fwd <- 0

  # Non-KR candidates
  non_kr <- data.table(
    asset_id = c("TSMOM_basket", "A148070", "CASH_KRW"),
    asset_type = c("TSMOM_ETF", "KR_10y_bond", "Cash"),
    composite_z = c(ts_z, kr10y_z, -10),
    z_1715 = NA_real_,
    z_NEW = NA_real_,
    Ret_1m = c(tsmom_ret_fwd, kr10y_ret_fwd, cash_ret_fwd)
  )
  candidates <- rbind(kr_subset, non_kr)

  # Top20 by composite_z (descending)
  setorder(candidates, -composite_z)
  top20 <- head(candidates, 20)
  top20[, sig_date := sd_date]
  top20[, rank := 1:.N]
  top20[, weight := 1 / 20]

  all_holdings[[length(all_holdings) + 1]] <- top20

  diagnostic[[length(diagnostic) + 1]] <- data.table(
    sig_date = sd_date,
    n_kr_stock = sum(top20$asset_type == "KR_stock"),
    n_tsmom = sum(top20$asset_type == "TSMOM_ETF"),
    n_kr10y = sum(top20$asset_type == "KR_10y_bond"),
    n_cash = sum(top20$asset_type == "Cash"),
    tsmom_z = ts_z,
    kr10y_z = kr10y_z,
    threshold_z_20th = top20[20, composite_z],
    n_kr_with_ret = sum(top20$asset_type == "KR_stock" & !is.na(top20$Ret_1m)),
    period_ret_ew = sum(top20$Ret_1m * top20$weight, na.rm = TRUE)
  )
}

holdings_dt <- rbindlist(all_holdings)
diag_dt <- rbindlist(diagnostic)

cat(sprintf("\nTotal holdings rows: %d\n", nrow(holdings_dt)))
cat("\n[Cross-universe inclusion diagnostic]\n")
cat(sprintf("  KR_stock count: mean=%.2f, range=[%d, %d]\n",
            mean(diag_dt$n_kr_stock),
            min(diag_dt$n_kr_stock),
            max(diag_dt$n_kr_stock)))
cat(sprintf("  TSMOM in top20: %d sig_dates (%.1f%%)\n",
            sum(diag_dt$n_tsmom > 0),
            100 * mean(diag_dt$n_tsmom > 0)))
cat(sprintf("  KR_10y in top20: %d sig_dates (%.1f%%)\n",
            sum(diag_dt$n_kr10y > 0),
            100 * mean(diag_dt$n_kr10y > 0)))
cat(sprintf("  Cash in top20: %d sig_dates\n", sum(diag_dt$n_cash > 0)))
cat(sprintf("  KR with Ret_1m: mean %.2f / 20 (%.1f%%)\n",
            mean(diag_dt$n_kr_with_ret),
            100 * mean(diag_dt$n_kr_with_ret / 20)))

#==============================================================================
# 5. Compute realized monthly returns (Forward 1m via Iter5 Ret_1m + sm)
#==============================================================================
cat("\n=== Step 5: Compute realized monthly returns ===\n")

# Per sig_date period_ret = EW 5% × Ret_1m for each top20 holding
holdings_dt[, period_contribution := weight * Ret_1m]
holdings_dt[is.na(period_contribution), period_contribution := 0]

period_ret <- holdings_dt[, .(monthly_ret = sum(period_contribution, na.rm = TRUE),
                               n_holdings = .N,
                               n_with_ret = sum(!is.na(Ret_1m))),
                          by = sig_date]
setorder(period_ret, sig_date)

cat(sprintf("Period returns: %d rows\n", nrow(period_ret)))
cat(sprintf("Mean monthly: %.4f\n", mean(period_ret$monthly_ret)))
cat(sprintf("Stdev monthly: %.4f\n", sd(period_ret$monthly_ret)))

# All sig_dates have full top20 with Ret_1m (Iter5 alpha completeness)
cat(sprintf("Holdings with Ret_1m: %d / %d (%.1f%%)\n",
            sum(!is.na(holdings_dt$Ret_1m)), nrow(holdings_dt),
            100 * mean(!is.na(holdings_dt$Ret_1m))))

#==============================================================================
# 6. Turnover + cost embed (15bps one-way × 2 round-trip)
#==============================================================================
cat("\n=== Step 6: Turnover + cost embed ===\n")

sig_dates_sorted <- sort(unique(holdings_dt$sig_date))
turnover_seq <- numeric(length(sig_dates_sorted))
turnover_seq[1] <- 1.0

for (i in 2:length(sig_dates_sorted)) {
  curr <- holdings_dt[sig_date == sig_dates_sorted[i]]$asset_id
  prev <- holdings_dt[sig_date == sig_dates_sorted[i - 1]]$asset_id
  added <- length(setdiff(curr, prev))
  removed <- length(setdiff(prev, curr))
  turnover_seq[i] <- (added + removed) / (2 * 20)
}

mean_oneway <- mean(turnover_seq)
cat(sprintf("Turnover: mean one-way = %.4f (annualized %.0f%%)\n",
            mean_oneway, mean_oneway * 12 * 100))

# Cost: 15bps × 2 round-trip per rebalance
COST_BPS <- 0.0015
turnover_dt <- data.table(sig_date = sig_dates_sorted, turnover_oneway = turnover_seq)
turnover_dt[, cost_drag := 2 * turnover_oneway * COST_BPS]
period_ret_net <- merge(period_ret, turnover_dt, by = "sig_date", all.x = TRUE)
period_ret_net[is.na(cost_drag), cost_drag := 0]
period_ret_net[, net_return := monthly_ret - cost_drag]

cat(sprintf("Net mean: %.4f (gross %.4f, drag %.4f = %.2f bps/m, %.2f bps/yr)\n",
            mean(period_ret_net$net_return), mean(period_ret_net$monthly_ret),
            mean(period_ret_net$cost_drag), mean(period_ret_net$cost_drag) * 1e4,
            mean(period_ret_net$cost_drag) * 12 * 1e4))

#==============================================================================
# 7. Backtest metrics (cost-embedded + cost-free)
#==============================================================================
cat("\n=== Step 7: Backtest metrics (PerformanceAnalytics) ===\n")

xt_net <- xts(period_ret_net$net_return, order.by = period_ret_net$sig_date)
xt_gross <- xts(period_ret_net$monthly_ret, order.by = period_ret_net$sig_date)

metrics <- list()
metrics$N <- nrow(period_ret_net)
metrics$date_start <- as.character(min(period_ret_net$sig_date))
metrics$date_end <- as.character(max(period_ret_net$sig_date))

# Cost-embedded
metrics$SR_ann_geometric <- as.numeric(SharpeRatio.annualized(xt_net, scale = 12, geometric = TRUE))
metrics$CAGR <- as.numeric(Return.annualized(xt_net, scale = 12, geometric = TRUE))
metrics$MDD <- as.numeric(maxDrawdown(xt_net, geometric = TRUE))
metrics$Sortino <- as.numeric(SortinoRatio(xt_net, MAR = 0)) * sqrt(12)
metrics$Calmar <- as.numeric(CalmarRatio(xt_net, scale = 12))
metrics$CVaR_95_monthly <- as.numeric(ES(xt_net, p = 0.95, method = "historical"))
metrics$CVaR_99_monthly <- as.numeric(ES(xt_net, p = 0.99, method = "historical"))
metrics$hit_rate <- mean(period_ret_net$net_return > 0)
metrics$vol_ann <- as.numeric(StdDev.annualized(xt_net, scale = 12))

# Cost-free
metrics$SR_gross <- as.numeric(SharpeRatio.annualized(xt_gross, scale = 12, geometric = TRUE))
metrics$CAGR_gross <- as.numeric(Return.annualized(xt_gross, scale = 12, geometric = TRUE))
metrics$MDD_gross <- as.numeric(maxDrawdown(xt_gross, geometric = TRUE))

metrics$mean_turnover_oneway <- mean_oneway
metrics$mean_turnover_oneway_pct <- mean_oneway * 100
metrics$turnover_annualized_pct <- mean_oneway * 12 * 100
metrics$mean_cost_drag_annual_bps <- mean(period_ret_net$cost_drag) * 12 * 1e4

cat(sprintf("\n[PD22 cost-embedded, N=%d (%s ~ %s)]\n",
            metrics$N, metrics$date_start, metrics$date_end))
cat(sprintf("  SR:              %.4f\n", metrics$SR_ann_geometric))
cat(sprintf("  CAGR:            %.4f (%.2f%%)\n", metrics$CAGR, metrics$CAGR*100))
cat(sprintf("  MDD:             %.4f (%.2f%%)\n", metrics$MDD, metrics$MDD*100))
cat(sprintf("  Sortino:         %.4f\n", metrics$Sortino))
cat(sprintf("  Calmar:          %.4f\n", metrics$Calmar))
cat(sprintf("  CVaR_95 monthly: %.4f\n", metrics$CVaR_95_monthly))
cat(sprintf("  hit_rate:        %.4f\n", metrics$hit_rate))
cat(sprintf("  vol_ann:         %.4f\n", metrics$vol_ann))
cat(sprintf("  Turnover: %.0f%% annualized (%.2f%% one-way per rebal)\n",
            metrics$turnover_annualized_pct, metrics$mean_turnover_oneway_pct))
cat(sprintf("  Cost drag: %.2f bps/yr\n", metrics$mean_cost_drag_annual_bps))

cat(sprintf("\n[Cost-free (gross)]\n"))
cat(sprintf("  SR:   %.4f\n", metrics$SR_gross))
cat(sprintf("  CAGR: %.4f (%.2f%%)\n", metrics$CAGR_gross, metrics$CAGR_gross*100))
cat(sprintf("  MDD:  %.4f (%.2f%%)\n", metrics$MDD_gross, metrics$MDD_gross*100))

#==============================================================================
# 8. vs S4 v2 baseline comparison (same 184m period)
#==============================================================================
cat("\n=== Step 8: vs S4 v2 baseline (same period) ===\n")

# S4 v2: 50% AR_on_M4 + 25% TSMOM + 20% KR_10y + 5% Cash
# Forward 1m return at each sig_date = sm at sig_date + 1m
period_ret_net[, ym_sig := format(sig_date, "%Y-%m")]
period_ret_net[, ym_fwd := format(as.Date(paste0(format(sig_date + 32, "%Y-%m"), "-01")), "%Y-%m")]

sm_lookup <- sm[, .(ym_fwd = format(Date, "%Y-%m"), AR_on_M4, TSMOM, KR_10y, Cash)]
prn_s4 <- merge(period_ret_net, sm_lookup, by = "ym_fwd", all.x = TRUE)
prn_s4[, ret_S4_v2 := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]

# S4 v2 cost ~ 5% monthly turnover (slower rebal) × 15bps × 2 round-trip = ~3bps/m
prn_s4[, cost_drag_S4 := 0.05 * 0.0015 * 2]  # 1.5 bps/m
prn_s4[, ret_S4_v2_net := ret_S4_v2 - cost_drag_S4]

xt_S4_net <- xts(prn_s4$ret_S4_v2_net, order.by = prn_s4$sig_date)
S4_metrics <- list(
  SR = as.numeric(SharpeRatio.annualized(xt_S4_net, scale = 12, geometric = TRUE)),
  CAGR = as.numeric(Return.annualized(xt_S4_net, scale = 12, geometric = TRUE)),
  MDD = as.numeric(maxDrawdown(xt_S4_net, geometric = TRUE)),
  CVaR_95 = as.numeric(ES(xt_S4_net, p = 0.95, method = "historical")),
  Sortino = as.numeric(SortinoRatio(xt_S4_net, MAR = 0)) * sqrt(12)
)

cat(sprintf("S4 v2 baseline (184m, 15bps cost embed):\n"))
cat(sprintf("  SR:      %.4f\n", S4_metrics$SR))
cat(sprintf("  CAGR:    %.4f\n", S4_metrics$CAGR))
cat(sprintf("  MDD:     %.4f\n", S4_metrics$MDD))
cat(sprintf("  CVaR_95: %.4f\n", S4_metrics$CVaR_95))
cat(sprintf("  Sortino: %.4f\n", S4_metrics$Sortino))

cat(sprintf("\n[PD22 vs S4 v2 (same-period 4-axis)]\n"))
cat(sprintf("  ΔSR:      %+.4f (PD22 %s)\n",
            metrics$SR_ann_geometric - S4_metrics$SR,
            ifelse(metrics$SR_ann_geometric > S4_metrics$SR, "DOMINATE", "INFERIOR")))
cat(sprintf("  ΔCAGR:    %+.4f pp\n", (metrics$CAGR - S4_metrics$CAGR) * 100))
cat(sprintf("  ΔMDD:     %+.4f pp\n", (metrics$MDD - S4_metrics$MDD) * 100))
cat(sprintf("  ΔCVaR95:  %+.4f pp\n", (metrics$CVaR_95_monthly - S4_metrics$CVaR_95) * 100))

# 4-axis strict improve test
axis_strict <- list(
  SR = metrics$SR_ann_geometric > S4_metrics$SR,
  CAGR = metrics$CAGR > S4_metrics$CAGR,
  MDD = metrics$MDD < S4_metrics$MDD,  # more negative is worse, MDD as |value|, less = better
  CVaR_95 = metrics$CVaR_95_monthly > S4_metrics$CVaR_95  # less negative = better
)
cat(sprintf("\n[4-axis strict improve vs S4 v2]\n"))
cat(sprintf("  SR > S4:       %s\n", ifelse(axis_strict$SR, "PASS", "FAIL")))
cat(sprintf("  CAGR > S4:     %s\n", ifelse(axis_strict$CAGR, "PASS", "FAIL")))
cat(sprintf("  MDD better:    %s\n", ifelse(axis_strict$MDD, "PASS", "FAIL")))
cat(sprintf("  CVaR95 better: %s\n", ifelse(axis_strict$CVaR_95, "PASS", "FAIL")))
cat(sprintf("  4-axis strict: %s\n",
            ifelse(all(unlist(axis_strict)), "ALL PASS", "FAIL on some axes")))

# Diebold-Mariano
diff <- prn_s4$net_return - prn_s4$ret_S4_v2_net
diff <- diff[!is.na(diff)]
nw_lag <- 6; N <- length(diff)
mean_diff <- mean(diff); nw_var <- var(diff)
for (lag in 1:nw_lag) {
  weight <- 1 - lag / (nw_lag + 1)
  ac <- mean((diff[(lag + 1):N] - mean_diff) * (diff[1:(N - lag)] - mean_diff))
  nw_var <- nw_var + 2 * weight * ac
}
nw_se <- sqrt(nw_var / N)
t_nw <- mean_diff / nw_se
p_nw <- 2 * pnorm(-abs(t_nw))

cat(sprintf("\n[Diebold-Mariano vs S4 v2]\n"))
cat(sprintf("  N=%d, mean_diff=%.6f, NW lag6 SE=%.6f\n", N, mean_diff, nw_se))
cat(sprintf("  t_NW=%.4f, p=%.4f\n", t_nw, p_nw))
cat(sprintf("  Harvey-Liu-Zhu t>3.0: %s\n", ifelse(abs(t_nw) > 3.0, "PASS", "FAIL")))

#==============================================================================
# 9. vs PD20-B Path 2 comparison
#==============================================================================
cat("\n=== Step 9: vs PD20-B Path 2 (4-sleeve consolidation) ===\n")

pd20b_path <- file.path(WT_DIR, "backtest_result_pd20b/composite_returns_4sleeve_pd20b.csv")
if (file.exists(pd20b_path)) {
  pd20b_dt <- fread(pd20b_path)
  pd20b_dt[, Date := as.Date(Date)]
  setorder(pd20b_dt, Date)
  xt_pd20b <- xts(pd20b_dt$ret_pd20b_path2_net, order.by = pd20b_dt$Date)
  pd20b_full <- list(
    SR = as.numeric(SharpeRatio.annualized(xt_pd20b, scale = 12, geometric = TRUE)),
    CAGR = as.numeric(Return.annualized(xt_pd20b, scale = 12, geometric = TRUE)),
    MDD = as.numeric(maxDrawdown(xt_pd20b, geometric = TRUE))
  )

  # Aligned 184m comparison
  pd20b_aligned <- pd20b_dt[as.character(format(Date, "%Y-%m")) %in% format(period_ret_net$sig_date, "%Y-%m")]
  if (nrow(pd20b_aligned) >= 30) {
    xt_pd20b_a <- xts(pd20b_aligned$ret_pd20b_path2_net, order.by = pd20b_aligned$Date)
    pd20b_aligned_m <- list(
      SR = as.numeric(SharpeRatio.annualized(xt_pd20b_a, scale = 12, geometric = TRUE)),
      CAGR = as.numeric(Return.annualized(xt_pd20b_a, scale = 12, geometric = TRUE)),
      MDD = as.numeric(maxDrawdown(xt_pd20b_a, geometric = TRUE))
    )
  } else {
    pd20b_aligned_m <- list(SR = NA, CAGR = NA, MDD = NA)
  }

  cat(sprintf("PD20-B full 256m: SR=%.4f, CAGR=%.4f, MDD=%.4f\n",
              pd20b_full$SR, pd20b_full$CAGR, pd20b_full$MDD))
  if (!is.na(pd20b_aligned_m$SR)) {
    cat(sprintf("PD20-B aligned %dm: SR=%.4f, CAGR=%.4f, MDD=%.4f\n",
                nrow(pd20b_aligned), pd20b_aligned_m$SR, pd20b_aligned_m$CAGR, pd20b_aligned_m$MDD))
  }
  cat(sprintf("\n[PD22 vs PD20-B aligned]\n"))
  cat(sprintf("  ΔSR:   %+.4f\n", metrics$SR_ann_geometric - pd20b_aligned_m$SR))
  cat(sprintf("  ΔCAGR: %+.4f pp\n", (metrics$CAGR - pd20b_aligned_m$CAGR) * 100))
  cat(sprintf("  ΔMDD:  %+.4f pp\n", (metrics$MDD - pd20b_aligned_m$MDD) * 100))
} else {
  pd20b_full <- list(SR = NA, CAGR = NA, MDD = NA)
  pd20b_aligned_m <- list(SR = NA, CAGR = NA, MDD = NA)
}

#==============================================================================
# 10. vs PD18 5-sleeve (cap violation baseline)
#==============================================================================
cat("\n=== Step 10: vs PD18 5-sleeve (49 holdings cap violation) ===\n")

pd18_path <- file.path(WT_DIR, "backtest_result_med_10pct_pd18/composite_returns_5sleeve_pd18.csv")
if (file.exists(pd18_path)) {
  pd18_dt <- fread(pd18_path)
  pd18_dt[, Date := as.Date(Date)]
  xt_pd18 <- xts(pd18_dt$ret_5sleeve_redistribute, order.by = pd18_dt$Date)
  pd18_full <- list(
    SR = as.numeric(SharpeRatio.annualized(xt_pd18, scale = 12, geometric = TRUE)),
    CAGR = as.numeric(Return.annualized(xt_pd18, scale = 12, geometric = TRUE)),
    MDD = as.numeric(maxDrawdown(xt_pd18, geometric = TRUE))
  )
  cat(sprintf("PD18 5-sleeve full: SR=%.4f, CAGR=%.4f, MDD=%.4f\n",
              pd18_full$SR, pd18_full$CAGR, pd18_full$MDD))
} else {
  pd18_full <- list(SR = NA, CAGR = NA, MDD = NA)
  cat(sprintf("PD18 path not found: %s\n", pd18_path))
}

#==============================================================================
# 11. Save outputs (Backtest Contract v1.0)
#==============================================================================
cat("\n=== Step 11: Save outputs ===\n")

# period_returns.csv
period_out <- period_ret_net[, .(Date = sig_date, ym = ym_sig,
                                  strategy_return = monthly_ret,
                                  cost_drag, net_return,
                                  turnover_oneway, n_holdings, n_with_ret)]
fwrite(period_out, file.path(OUT_DIR, "period_returns.csv"))

# nav.csv
nav_dt <- period_out[, .(Date, ret = net_return)]
nav_dt[, nav := cumprod(1 + ret)]
fwrite(nav_dt, file.path(OUT_DIR, "nav.csv"))

# metrics.csv
metrics_dt <- data.table(metric = names(metrics), value = unlist(metrics),
                          metric_type = "backtested")
fwrite(metrics_dt, file.path(OUT_DIR, "metrics.csv"))

# holdings.csv
fwrite(holdings_dt, file.path(OUT_DIR, "holdings.csv"))

# benchmark_compare.csv
bc_dt <- data.table(
  strategy = c("PD22_cross_universe", "S4_v2_baseline", "PD20B_Path2_aligned", "PD18_5sleeve_full"),
  SR = c(metrics$SR_ann_geometric, S4_metrics$SR, pd20b_aligned_m$SR, pd18_full$SR),
  CAGR = c(metrics$CAGR, S4_metrics$CAGR, pd20b_aligned_m$CAGR, pd18_full$CAGR),
  MDD = c(metrics$MDD, S4_metrics$MDD, pd20b_aligned_m$MDD, pd18_full$MDD),
  CVaR_95 = c(metrics$CVaR_95_monthly, S4_metrics$CVaR_95, NA, NA),
  period = c("184m_2011_2026", "184m_same", "184m_aligned", "256m_full")
)
fwrite(bc_dt, file.path(OUT_DIR, "benchmark_compare.csv"))

# Diebold-Mariano
dm_dt <- data.table(
  measure = "Diebold-Mariano",
  comparison = "PD22 vs S4 v2",
  N = N, mean_diff = mean_diff,
  NW_lag6_SE = nw_se, t_NW = t_nw, p_value = p_nw,
  hlz_pass = abs(t_nw) > 3.0
)
fwrite(dm_dt, file.path(OUT_DIR, "diebold_mariano.csv"))

# Diagnostic
fwrite(diag_dt, file.path(OUT_DIR, "cross_universe_diagnostic.csv"))

# 4-axis strict improve summary
axis_dt <- data.table(
  axis = c("SR", "CAGR", "MDD", "CVaR_95"),
  pd22 = c(metrics$SR_ann_geometric, metrics$CAGR, metrics$MDD, metrics$CVaR_95_monthly),
  s4_v2 = c(S4_metrics$SR, S4_metrics$CAGR, S4_metrics$MDD, S4_metrics$CVaR_95),
  pass = unlist(axis_strict)
)
axis_dt[, delta := pd22 - s4_v2]
fwrite(axis_dt, file.path(OUT_DIR, "4axis_strict_improve.csv"))

#==============================================================================
# 12. 3-package md5sum (end) — Pure function audit
#==============================================================================
md5_end <- list(
  alpha = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk  = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt   = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("\n3-package md5sum END:\n")
cat("  alpha:", md5_end$alpha, "\n")
cat("  risk: ", md5_end$risk, "\n")
cat("  opt:  ", md5_end$opt, "\n")
md5_match <- all(c(md5_start$alpha == md5_end$alpha,
                   md5_start$risk == md5_end$risk,
                   md5_start$opt == md5_end$opt))
cat(sprintf("Pure function audit: %s\n", ifelse(md5_match, "PASS", "FAIL")))

# Save md5 audit
md5_audit <- data.table(
  package = c("alpha", "risk", "optimization"),
  md5_start = c(md5_start$alpha, md5_start$risk, md5_start$opt),
  md5_end = c(md5_end$alpha, md5_end$risk, md5_end$opt),
  match = c(md5_start$alpha == md5_end$alpha,
            md5_start$risk == md5_end$risk,
            md5_start$opt == md5_end$opt)
)
fwrite(md5_audit, file.path(OUT_DIR, "pure_function_audit.csv"))

#==============================================================================
# 13. Save final metrics RDS
#==============================================================================
saveRDS(list(
  metrics = metrics,
  S4_baseline = S4_metrics,
  PD20B_full = pd20b_full,
  PD20B_aligned = pd20b_aligned_m,
  PD18_full = pd18_full,
  DM_vs_S4 = list(t_NW = t_nw, p = p_nw, N = N, mean_diff = mean_diff, nw_se = nw_se),
  axis_strict_improve = axis_strict,
  cross_universe_diag = list(
    mean_kr_stock = mean(diag_dt$n_kr_stock),
    pct_tsmom_in_top20 = 100 * mean(diag_dt$n_tsmom > 0),
    pct_kr10y_in_top20 = 100 * mean(diag_dt$n_kr10y > 0),
    pct_cash_in_top20 = 100 * mean(diag_dt$n_cash > 0)
  ),
  pure_function = list(md5_start = md5_start, md5_end = md5_end, match = md5_match)
), file.path(OUT_DIR, "metrics_pd22.rds"))

cat("\nDONE: PD22 5-Sleeve Cross-Universe Z-Composite Top20 backtest.\n")
cat(sprintf("Outputs in: %s\n", OUT_DIR))
cat(sprintf("Finished: %s\n", format(Sys.time())))
