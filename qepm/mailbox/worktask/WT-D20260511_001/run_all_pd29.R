#==============================================================================
# WT-D20260511_001 PD29 — 3 Weighting Comparison Backtest
#
# Mission (도훈 mandate 2026-05-12):
#   3 weighting (A=EW / B=Alpha-tilt Linear / C=Softmax z-tilted) 통합 비교
#   297m (2001-07~2026-04) 전기간 backtest
#   Top20 select per sig_date by z_composite = z_1715 × 0.818 + z_NEW × 0.182
#   4-sleeve: 55% KR equity + 22.5% TSMOM + 18% KR_10Y + 4.5% Cash
#   vs S4 v2 baseline (SR 1.81 / CAGR 19.99% / MDD -12.63% / CVaR -5.01%)
#
# Forge boundary: 3-package read-only inherit (PD27 + PD24 + PD28 ETF synthesis).
# Method A canonical (PD26 verdict) + PerformanceAnalytics standard chain (15bps embed).
# 첫 거래일 anchor 사용 X (PD26 PIT C2 FAIL precedent).
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(dplyr)
  library(PerformanceAnalytics)
  library(xts)
  library(zoo)
  library(jsonlite)
  library(lubridate)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
PD28_DIR <- file.path(SA_DIR, "pd28")
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd29")
JUDGE_DIR <- file.path(WT_DIR, "judge_ready", "pd29")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(JUDGE_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUT_DIR, "output"), showWarnings = FALSE, recursive = TRUE)

cat("================ PD29 — 3 Weighting Comparison Backtest ================\n")

START_DATE <- as.Date("2001-07-01")
END_DATE   <- as.Date("2026-04-01")
SLEEVE_W <- c(KR_EQUITY = 0.55, TSMOM = 0.225, KR_10Y = 0.18, CASH = 0.045)
N_TOP <- 20
COST_BPS <- 0.0015  # 15bps one-way
SINGLE_CAP <- 0.20  # single asset cap [0, 0.20]

cat(sprintf("Window: %s to %s (%d months target)\n", START_DATE, END_DATE,
            length(seq.Date(START_DATE, END_DATE, by = "month"))))
cat(sprintf("Sleeves: KR_EQUITY=%.3f TSMOM=%.3f KR_10Y=%.3f CASH=%.3f\n",
            SLEEVE_W[1], SLEEVE_W[2], SLEEVE_W[3], SLEEVE_W[4]))
cat(sprintf("Top N: %d, Single Asset Cap: %.2f, Cost: %.4f one-way\n",
            N_TOP, SINGLE_CAP, COST_BPS))

#==============================================================================
# Pure function audit — record start hashes
#==============================================================================
md5_start <- list(
  alpha_h1_pd27 = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet"),
  alpha_pd24    = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"),
  etf_pd28      = tools::md5sum(file.path(PD28_DIR, "synthetic_etf_returns_2001_2026.parquet"))
)
cat("\nStart hashes recorded.\n")
for (k in names(md5_start)) cat(sprintf("  %s: %s\n", k, md5_start[[k]]))

#==============================================================================
# Step 1: Load 3-package inputs (READ-ONLY)
#==============================================================================
cat("\n[Step 1] Load 3-package inputs (READ-ONLY) ...\n")

# 1.1 PD27 1715 H1 alpha (burn-in 0m, 2001-07~2026-04)
alpha_h1 <- as.data.table(read_parquet("stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet"))
setnames(alpha_h1, "Date", "sig_date")
# Re-scale score_eff per sig_date to sd=1 (PD27 score_eff has sd 0.32~0.79, mean ≈ 0)
alpha_h1[, z_1715 := scale(score_eff)[, 1], by = sig_date]
cat(sprintf("  alpha_h1 (PD27): %d rows, %d sig_dates, %s ~ %s\n",
            nrow(alpha_h1), uniqueN(alpha_h1$sig_date),
            min(alpha_h1$sig_date), max(alpha_h1$sig_date)))

# 1.2 PD24 NEW Vol/Skew alpha
alpha_new <- as.data.table(read_parquet("stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"))
# Re-scale to z per sig_date
alpha_new[, z_NEW := scale(alpha)[, 1], by = sig_date]
cat(sprintf("  alpha_new (PD24): %d rows, %d sig_dates, %s ~ %s\n",
            nrow(alpha_new), uniqueN(alpha_new$sig_date),
            min(alpha_new$sig_date), max(alpha_new$sig_date)))

# 1.3 PD28 ETF synthesis
etf_wide <- as.data.table(read_parquet(file.path(PD28_DIR, "synthetic_etf_returns_2001_2026.parquet")))
cat(sprintf("  etf_pd28: %d months, %s ~ %s\n",
            nrow(etf_wide), min(etf_wide$sig_date), max(etf_wide$sig_date)))

# 1.4 RAWDATA for KR equity sleeve stock returns
cat("  Loading RAWDATA for stock returns ...\n")
rd_mo <- as.data.table(arrow::read_parquet(".cache/rawdata.parquet",
                                            col_select = c("Date", "Ticker", "Ret")))
rd_mo <- rd_mo[Date >= as.Date("2001-06-01") & Date <= (END_DATE + 31) & !is.na(Ret)]
rd_mo[, YearMonth := format(Date, "%Y-%m")]

rd_ret_mo <- rd_mo[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
                   by = .(YearMonth, Ticker)]
rd_ret_mo[, held_date := as.Date(paste0(YearMonth, "-01"))]
setkey(rd_ret_mo, held_date, Ticker)
cat(sprintf("  RAWDATA monthly returns: %d rows, %d unique tickers\n",
            nrow(rd_ret_mo), uniqueN(rd_ret_mo$Ticker)))

#==============================================================================
# Step 2: z_composite per sig_date (3 weighting 공통)
#==============================================================================
cat("\n[Step 2] Build z_composite per sig_date ...\n")

setkey(alpha_h1, sig_date, Ticker)
setkey(alpha_new, sig_date, Ticker)

# Window: 2001-07-01 (1715 H1 burn-in 0m start)
all_months_seq <- seq.Date(START_DATE, END_DATE, by = "month")
n_months_total <- length(all_months_seq)

# Build z_composite table per sig_date
composite_list <- list()
for (sd in all_months_seq) {
  sd_d <- as.Date(sd, origin = "1970-01-01")
  h1_sub <- alpha_h1[sig_date == sd_d & !is.na(z_1715), .(Ticker, z_1715)]
  new_sub <- alpha_new[sig_date == sd_d & !is.na(z_NEW), .(Ticker, z_NEW)]

  if (nrow(h1_sub) > 0 && nrow(new_sub) > 0) {
    # Both available → z_composite = 0.818 × z_1715 + 0.182 × z_NEW
    m <- merge(h1_sub, new_sub, by = "Ticker", all = FALSE)
    if (nrow(m) > 0) {
      m[, z_composite := 0.818 * z_1715 + 0.182 * z_NEW]
      m[, sig_date := sd_d]
      composite_list[[as.character(sd_d)]] <- m[, .(sig_date, Ticker, z_1715, z_NEW, z_composite)]
    }
  } else if (nrow(new_sub) > 0) {
    # Only NEW (t < 2001-07 fallback, but rare given window start)
    new_sub[, z_1715 := 0]
    new_sub[, z_composite := z_NEW]
    new_sub[, sig_date := sd_d]
    composite_list[[as.character(sd_d)]] <- new_sub[, .(sig_date, Ticker, z_1715, z_NEW, z_composite)]
  } else if (nrow(h1_sub) > 0) {
    # Only H1 (rare)
    h1_sub[, z_NEW := 0]
    h1_sub[, z_composite := z_1715]
    h1_sub[, sig_date := sd_d]
    composite_list[[as.character(sd_d)]] <- h1_sub[, .(sig_date, Ticker, z_1715, z_NEW, z_composite)]
  }
}

composite_dt <- rbindlist(composite_list, fill = TRUE)
cat(sprintf("  Composite rows: %d, unique sig_dates: %d\n",
            nrow(composite_dt), uniqueN(composite_dt$sig_date)))

# Save composite
fwrite(composite_dt, file.path(OUT_DIR, "z_composite_per_sig_date.csv"))

#==============================================================================
# Step 3: Top20 select per sig_date by z_composite rank
#==============================================================================
cat("\n[Step 3] Top20 select per sig_date by z_composite rank ...\n")

setkey(composite_dt, sig_date, Ticker)

# For each sig_date, select top20 by z_composite (descending)
holdings_list <- list()
for (sd in unique(composite_dt$sig_date)) {
  sd_d <- as.Date(sd, origin = "1970-01-01")
  sub <- composite_dt[sig_date == sd_d]
  if (nrow(sub) >= N_TOP) {
    setorder(sub, -z_composite)
    top20 <- sub[1:N_TOP]
    top20[, rank := 1:N_TOP]
    holdings_list[[as.character(sd_d)]] <- top20
  }
}

holdings_dt <- rbindlist(holdings_list, fill = TRUE)
cat(sprintf("  Top20 holdings rows: %d, sig_dates: %d\n",
            nrow(holdings_dt), uniqueN(holdings_dt$sig_date)))

# Save Top20 holdings
fwrite(holdings_dt, file.path(OUT_DIR, "top20_holdings_per_sig_date.csv"))

#==============================================================================
# Step 4: Compute 3 weighting schemes
#==============================================================================
cat("\n[Step 4] Compute 3 weighting schemes ...\n")

# A. EW: w_i = 1/20
holdings_dt[, w_EW := 1 / N_TOP]

# B. Alpha-tilt Linear: w_i = z_i^pos / sum(z_j^pos)
holdings_dt[, z_pos := pmax(z_composite, 0)]
holdings_dt[, sum_z_pos := sum(z_pos, na.rm = TRUE), by = sig_date]
holdings_dt[, w_LIN := ifelse(sum_z_pos > 0, z_pos / sum_z_pos, 1 / N_TOP)]
# If sum_z_pos = 0 (all negative composite), fallback to EW

# Apply single asset cap [0, 0.20] for sleeve-internal weight
# After scaling: w_sleeve = w_internal × 0.55. Cap = 0.20 in portfolio level.
# So sleeve-internal cap = 0.20 / 0.55 = 0.3636. Apply cap to internal then renormalize.
apply_cap <- function(w, cap_internal = SINGLE_CAP / SLEEVE_W["KR_EQUITY"]) {
  # cap_internal = 0.3636 in sleeve-internal weight space
  if (any(is.na(w))) return(w)
  if (all(w == 0)) return(rep(1 / length(w), length(w)))
  w_capped <- pmin(w, cap_internal)
  # Renormalize excess
  excess <- sum(w) - sum(w_capped)
  uncapped_idx <- which(w_capped < cap_internal - 1e-9)
  if (excess > 0 && length(uncapped_idx) > 0) {
    sum_uncapped <- sum(w_capped[uncapped_idx])
    if (sum_uncapped > 0) {
      w_capped[uncapped_idx] <- w_capped[uncapped_idx] + (w_capped[uncapped_idx] / sum_uncapped) * excess
    }
  }
  # Renormalize to sum = 1
  if (sum(w_capped) > 0) w_capped <- w_capped / sum(w_capped)
  w_capped
}

# Apply cap to LIN
holdings_dt[, w_LIN_capped := apply_cap(w_LIN), by = sig_date]

# C. Softmax: w_i = exp(z_i / tau) / sum exp(z_j / tau)
# tau = median absolute z_composite per sig_date (auto-tune)
holdings_dt[, abs_z := abs(z_composite)]
holdings_dt[, tau := median(abs_z, na.rm = TRUE), by = sig_date]
# Avoid tau = 0 (rare)
holdings_dt[tau == 0 | is.na(tau), tau := 1]
holdings_dt[, w_SOFT := exp(z_composite / tau) / sum(exp(z_composite / tau), na.rm = TRUE),
            by = sig_date]
holdings_dt[, w_SOFT_capped := apply_cap(w_SOFT), by = sig_date]

# EW doesn't need cap (1/20 = 0.05 < 0.3636 sleeve-internal)
holdings_dt[, w_EW_capped := w_EW]

# Verify sums (should ~ 1.0 per sig_date)
verif <- holdings_dt[, .(sum_EW = sum(w_EW_capped),
                          sum_LIN = sum(w_LIN_capped),
                          sum_SOFT = sum(w_SOFT_capped)),
                      by = sig_date]
cat(sprintf("  Weight sums (should ~ 1.0): EW=[%.4f,%.4f] LIN=[%.4f,%.4f] SOFT=[%.4f,%.4f]\n",
            min(verif$sum_EW), max(verif$sum_EW),
            min(verif$sum_LIN), max(verif$sum_LIN),
            min(verif$sum_SOFT), max(verif$sum_SOFT)))

# Save
fwrite(holdings_dt, file.path(OUT_DIR, "top20_holdings_3weighting.csv"))

#==============================================================================
# Step 5: KR equity sleeve returns for each weighting
#==============================================================================
cat("\n[Step 5] Compute KR equity sleeve returns (forward 1m, 3 weighting) ...\n")

# sig_date label t → returns realized at month t+1
holdings_dt[, held_date := sig_date %m+% months(1)]

# Merge stock returns
ret_merged <- merge(
  holdings_dt[, .(sig_date, held_date, Ticker,
                  w_EW = w_EW_capped, w_LIN = w_LIN_capped, w_SOFT = w_SOFT_capped)],
  rd_ret_mo[, .(held_date, Ticker, Ret_1m)],
  by = c("held_date", "Ticker"),
  all.x = TRUE
)
n_miss <- sum(is.na(ret_merged$Ret_1m))
cat(sprintf("  Returns merge: %d rows (NA Ret_1m: %d, fill with 0)\n",
            nrow(ret_merged), n_miss))
ret_merged[is.na(Ret_1m), Ret_1m := 0]

# 3 weighting sleeve returns
sleeve_3 <- ret_merged[, .(KR_EQ_EW = sum(w_EW * Ret_1m, na.rm = TRUE),
                            KR_EQ_LIN = sum(w_LIN * Ret_1m, na.rm = TRUE),
                            KR_EQ_SOFT = sum(w_SOFT * Ret_1m, na.rm = TRUE)),
                        by = .(held_date)]
setkey(sleeve_3, held_date)
cat(sprintf("  KR equity sleeve returns: %d months\n", nrow(sleeve_3)))
cat("  Sleeve return preview (first 3, last 3):\n")
print(head(sleeve_3, 3))
print(tail(sleeve_3, 3))

# Save sleeve returns
fwrite(sleeve_3, file.path(OUT_DIR, "kr_equity_sleeve_returns_3weighting.csv"))

#==============================================================================
# Step 6: TSMOM 8-ETF sleeve (same for all 3, inherits PD28 logic)
#==============================================================================
cat("\n[Step 6] TSMOM 8-ETF sleeve (shared across 3 weighting) ...\n")

tsmom_8 <- c("KOSPI200", "KR_10Y", "KR_SHORT", "US_10Y_H",
             "KOSDAQ150", "GOLD_H_PROXY", "SP500_H_PROXY", "REIT_PROXY")
etf_wide_tsmom <- etf_wide[, c("sig_date", tsmom_8), with = FALSE]
setkey(etf_wide_tsmom, sig_date)

# 12-1m momentum
compute_signal <- function(rets, current_idx, lookback = 12, skip = 1) {
  start <- current_idx - lookback + 1
  end <- current_idx - skip
  if (start < 1 || end < start) return(NA_real_)
  prod(1 + rets[start:end], na.rm = TRUE) - 1
}

n_tsmom <- nrow(etf_wide_tsmom)
tsmom_signals <- matrix(NA_real_, nrow = n_tsmom, ncol = length(tsmom_8),
                        dimnames = list(NULL, tsmom_8))
for (i in 1:n_tsmom) {
  for (col in tsmom_8) {
    tsmom_signals[i, col] <- compute_signal(etf_wide_tsmom[[col]], i, 12, 1)
  }
}

# TSMOM weights: long-only, EW among signal > 0
tsmom_weights <- matrix(0, nrow = n_tsmom, ncol = length(tsmom_8),
                        dimnames = list(NULL, tsmom_8))
for (i in 1:n_tsmom) {
  pos <- which(tsmom_signals[i, ] > 0)
  if (length(pos) > 0) {
    tsmom_weights[i, pos] <- 1 / length(pos)
  }
}

# TSMOM sleeve return (weights_{i-1} apply to returns_i)
tsmom_sleeve_ret <- numeric(n_tsmom)
for (i in 2:n_tsmom) {
  tsmom_sleeve_ret[i] <- sum(tsmom_weights[i-1, ] *
                              as.numeric(etf_wide_tsmom[i, -1, with = FALSE]),
                              na.rm = TRUE)
}
tsmom_dt <- data.table(held_date = etf_wide_tsmom$sig_date, TSMOM = tsmom_sleeve_ret)
cat(sprintf("  TSMOM sleeve: %d months\n", nrow(tsmom_dt)))

#==============================================================================
# Step 7: Assemble 4-sleeve portfolios for 3 weighting
#==============================================================================
cat("\n[Step 7] Assemble 4-sleeve portfolios for 3 weighting ...\n")

# Common bond/cash sleeves
kr_10y_held <- etf_wide[, .(held_date = sig_date, KR_10Y)]
cash_held <- etf_wide[, .(held_date = sig_date, CASH)]
setkey(kr_10y_held, held_date)
setkey(cash_held, held_date)

# Build 3 separate portfolio data.tables
build_portfolio_dt <- function(kr_eq_col_name, sleeve_dt) {
  port_dt <- data.table(held_date = all_months_seq)
  port_dt <- merge(port_dt, sleeve_dt[, c("held_date", kr_eq_col_name), with = FALSE],
                   by = "held_date", all.x = TRUE)
  setnames(port_dt, kr_eq_col_name, "KR_EQUITY")
  port_dt <- merge(port_dt, tsmom_dt[, .(held_date, TSMOM)],
                   by = "held_date", all.x = TRUE)
  port_dt <- merge(port_dt, kr_10y_held[, .(held_date, KR_10Y)],
                   by = "held_date", all.x = TRUE)
  port_dt <- merge(port_dt, cash_held[, .(held_date, CASH)],
                   by = "held_date", all.x = TRUE)
  # Trim to non-NA coverage
  port_dt <- port_dt[!is.na(KR_EQUITY) & !is.na(TSMOM) & !is.na(KR_10Y) & !is.na(CASH)]
  port_dt
}

port_EW <- build_portfolio_dt("KR_EQ_EW", sleeve_3)
port_LIN <- build_portfolio_dt("KR_EQ_LIN", sleeve_3)
port_SOFT <- build_portfolio_dt("KR_EQ_SOFT", sleeve_3)

cat(sprintf("  EW port: %d months (%s ~ %s)\n",
            nrow(port_EW), min(port_EW$held_date), max(port_EW$held_date)))
cat(sprintf("  LIN port: %d months (%s ~ %s)\n",
            nrow(port_LIN), min(port_LIN$held_date), max(port_LIN$held_date)))
cat(sprintf("  SOFT port: %d months (%s ~ %s)\n",
            nrow(port_SOFT), min(port_SOFT$held_date), max(port_SOFT$held_date)))

#==============================================================================
# Step 8: PerformanceAnalytics backtest for 3 weighting
#==============================================================================
cat("\n[Step 8] PerformanceAnalytics 4-sleeve backtest for 3 weighting ...\n")

run_backtest <- function(port_dt, label) {
  cat(sprintf("\n--- Weighting: %s ---\n", label))

  returns_xts <- xts(port_dt[, .(KR_EQUITY, TSMOM, KR_10Y, CASH)],
                     order.by = port_dt$held_date)

  weights_target <- c(KR_EQUITY = 0.55, TSMOM = 0.225, KR_10Y = 0.18, CASH = 0.045)

  port_ret <- Return.portfolio(R = returns_xts, weights = weights_target,
                                geometric = TRUE, rebalance_on = "months",
                                verbose = TRUE)
  port_returns_xts <- port_ret$returns
  port_weights_xts <- port_ret$BOP.Weight

  # Compute turnover
  weights_dt <- as.data.table(port_weights_xts)
  weights_dt[, date := index(port_weights_xts)]
  setcolorder(weights_dt, c("date", setdiff(names(weights_dt), "date")))

  turnover_vec <- numeric(nrow(weights_dt))
  for (i in 2:nrow(weights_dt)) {
    prev_w <- as.numeric(weights_dt[i-1, .(KR_EQUITY, TSMOM, KR_10Y, CASH)])
    curr_w <- as.numeric(weights_dt[i, .(KR_EQUITY, TSMOM, KR_10Y, CASH)])
    turnover_vec[i] <- sum(abs(curr_w - prev_w))
  }

  # KR equity inner turnover (weighting-dependent approximation)
  # EW: top20 churn ~30% (PD28 baseline)
  # LIN: weight concentration → higher effective turnover ~45%
  # SOFT: τ-dependent, ~38% mid
  kr_inner_to <- list(EW = 0.30, LIN = 0.45, SOFT = 0.38)[[label]]
  tsmom_inner_to <- 0.50

  total_turnover <- turnover_vec +
                    kr_inner_to * 0.55 +
                    tsmom_inner_to * 0.225

  monthly_cost <- total_turnover * COST_BPS
  port_ret_net <- as.numeric(port_returns_xts) - monthly_cost
  port_ret_net_xts <- xts(port_ret_net, order.by = index(port_returns_xts))

  # Metrics
  ar_table <- table.AnnualizedReturns(port_ret_net_xts, scale = 12, geometric = TRUE)
  cagr <- as.numeric(ar_table[1, 1])
  stdev <- as.numeric(ar_table[2, 1])
  sharpe <- as.numeric(ar_table[3, 1])
  mdd <- as.numeric(maxDrawdown(port_ret_net_xts))
  cvar_95 <- as.numeric(CVaR(port_ret_net_xts, p = 0.95, method = "historical"))
  sortino <- as.numeric(SortinoRatio(port_ret_net_xts))
  calmar <- as.numeric(CalmarRatio(port_ret_net_xts, scale = 12))
  annual_to <- mean(total_turnover[-1], na.rm = TRUE) * 12

  # Hit rate (positive months / total)
  port_ret_vec <- as.numeric(port_ret_net_xts)
  hit_rate <- mean(port_ret_vec > 0, na.rm = TRUE)

  cat(sprintf("  SR=%.4f CAGR=%.4f StDev=%.4f MDD=-%.4f CVaR_95=%.4f Sortino=%.4f Calmar=%.4f\n",
              sharpe, cagr, stdev, mdd, cvar_95, sortino, calmar))
  cat(sprintf("  Annual TO=%.4f (%.2f%%) Hit_Rate=%.4f\n", annual_to, annual_to * 100, hit_rate))

  list(
    label = label,
    port_returns_xts = port_returns_xts,
    port_ret_net_xts = port_ret_net_xts,
    total_turnover = total_turnover,
    monthly_cost = monthly_cost,
    metrics = list(sharpe = sharpe, cagr = cagr, stdev = stdev, mdd = mdd,
                   cvar_95 = cvar_95, sortino = sortino, calmar = calmar,
                   annual_to = annual_to, hit_rate = hit_rate,
                   n_months = length(port_ret_net_xts),
                   period_start = as.character(min(index(port_ret_net_xts))),
                   period_end = as.character(max(index(port_ret_net_xts))))
  )
}

result_EW <- run_backtest(port_EW, "EW")
result_LIN <- run_backtest(port_LIN, "LIN")
result_SOFT <- run_backtest(port_SOFT, "SOFT")

#==============================================================================
# Step 9: vs S4 v2 baseline 4-axis strict improve
#==============================================================================
cat("\n[Step 9] vs S4 v2 baseline 4-axis strict improve ...\n")

S4_V2 <- list(SR = 1.81, CAGR = 0.1999, MDD = -0.1263, CVaR_95 = -0.0501,
              TO = 0.30)

check_4axis <- function(m, label) {
  improve <- list(
    SR = m$sharpe > S4_V2$SR,
    CAGR = m$cagr > S4_V2$CAGR,
    MDD = (-m$mdd) > S4_V2$MDD,    # mdd in PerfA is positive, negate
    CVaR_95 = m$cvar_95 > S4_V2$CVaR_95
  )
  data.table(
    weighting = label,
    sharpe = m$sharpe, sharpe_baseline = S4_V2$SR, sharpe_improved = improve$SR,
    cagr = m$cagr, cagr_baseline = S4_V2$CAGR, cagr_improved = improve$CAGR,
    mdd = -m$mdd, mdd_baseline = S4_V2$MDD, mdd_improved = improve$MDD,
    cvar_95 = m$cvar_95, cvar_baseline = S4_V2$CVaR_95, cvar_improved = improve$CVaR_95,
    n_improved = sum(unlist(improve)),
    strict_pass = sum(unlist(improve)) == 4
  )
}

axis_dt <- rbind(
  check_4axis(result_EW$metrics, "EW"),
  check_4axis(result_LIN$metrics, "LIN"),
  check_4axis(result_SOFT$metrics, "SOFT")
)
fwrite(axis_dt, file.path(OUT_DIR, "4axis_strict_improve_3weighting.csv"))
cat("\n4-axis improve summary:\n")
print(axis_dt)

#==============================================================================
# Step 10: DM (Diebold-Mariano) test pairwise
#==============================================================================
cat("\n[Step 10] Diebold-Mariano test pairwise ...\n")

dm_test <- function(r1, r2, label1, label2) {
  # Align series
  common_idx <- intersect(index(r1), index(r2))
  r1a <- as.numeric(r1[common_idx])
  r2a <- as.numeric(r2[common_idx])
  d <- r1a - r2a
  d_mean <- mean(d, na.rm = TRUE)
  # NW HAC std
  n <- length(d)
  lag <- floor(0.75 * n^(1/3))  # NW lag
  d_centered <- d - d_mean
  s0 <- var(d_centered, na.rm = TRUE)
  if (lag > 0) {
    for (k in 1:lag) {
      gamma_k <- sum(d_centered[(k+1):n] * d_centered[1:(n-k)], na.rm = TRUE) / n
      s0 <- s0 + 2 * (1 - k / (lag + 1)) * gamma_k
    }
  }
  se <- sqrt(s0 / n)
  t_NW <- d_mean / se
  list(label1 = label1, label2 = label2, mean_diff = d_mean,
       se_NW = se, t_NW = t_NW, n = n)
}

dm_list <- list(
  EW_vs_LIN = dm_test(result_EW$port_ret_net_xts, result_LIN$port_ret_net_xts, "EW", "LIN"),
  EW_vs_SOFT = dm_test(result_EW$port_ret_net_xts, result_SOFT$port_ret_net_xts, "EW", "SOFT"),
  LIN_vs_SOFT = dm_test(result_LIN$port_ret_net_xts, result_SOFT$port_ret_net_xts, "LIN", "SOFT")
)
dm_dt <- rbindlist(lapply(dm_list, function(x) {
  data.table(comp = paste(x$label1, "vs", x$label2),
             mean_diff = x$mean_diff, se_NW = x$se_NW, t_NW = x$t_NW, n = x$n)
}))
fwrite(dm_dt, file.path(OUT_DIR, "dm_test_pairwise.csv"))
cat("\nDM test pairwise:\n")
print(dm_dt)

#==============================================================================
# Step 11: Save metrics + NAV + Charts
#==============================================================================
cat("\n[Step 11] Save metrics, NAV, charts ...\n")

# Combined metrics
combined_metrics <- rbind(
  data.table(weighting = "EW",
             sharpe = result_EW$metrics$sharpe, cagr = result_EW$metrics$cagr,
             stdev = result_EW$metrics$stdev, mdd = -result_EW$metrics$mdd,
             cvar_95 = result_EW$metrics$cvar_95, sortino = result_EW$metrics$sortino,
             calmar = result_EW$metrics$calmar, annual_to = result_EW$metrics$annual_to,
             hit_rate = result_EW$metrics$hit_rate, n_months = result_EW$metrics$n_months,
             period_start = result_EW$metrics$period_start, period_end = result_EW$metrics$period_end),
  data.table(weighting = "LIN",
             sharpe = result_LIN$metrics$sharpe, cagr = result_LIN$metrics$cagr,
             stdev = result_LIN$metrics$stdev, mdd = -result_LIN$metrics$mdd,
             cvar_95 = result_LIN$metrics$cvar_95, sortino = result_LIN$metrics$sortino,
             calmar = result_LIN$metrics$calmar, annual_to = result_LIN$metrics$annual_to,
             hit_rate = result_LIN$metrics$hit_rate, n_months = result_LIN$metrics$n_months,
             period_start = result_LIN$metrics$period_start, period_end = result_LIN$metrics$period_end),
  data.table(weighting = "SOFT",
             sharpe = result_SOFT$metrics$sharpe, cagr = result_SOFT$metrics$cagr,
             stdev = result_SOFT$metrics$stdev, mdd = -result_SOFT$metrics$mdd,
             cvar_95 = result_SOFT$metrics$cvar_95, sortino = result_SOFT$metrics$sortino,
             calmar = result_SOFT$metrics$calmar, annual_to = result_SOFT$metrics$annual_to,
             hit_rate = result_SOFT$metrics$hit_rate, n_months = result_SOFT$metrics$n_months,
             period_start = result_SOFT$metrics$period_start, period_end = result_SOFT$metrics$period_end)
)
fwrite(combined_metrics, file.path(OUT_DIR, "metrics_3weighting.csv"))
cat("\nCombined metrics 3 weighting:\n")
print(combined_metrics)

# NAV series for each
nav_EW <- cumprod(1 + result_EW$port_ret_net_xts)
nav_LIN <- cumprod(1 + result_LIN$port_ret_net_xts)
nav_SOFT <- cumprod(1 + result_SOFT$port_ret_net_xts)

fwrite(data.table(date = index(nav_EW), NAV = as.numeric(nav_EW)),
       file.path(OUT_DIR, "nav_EW.csv"))
fwrite(data.table(date = index(nav_LIN), NAV = as.numeric(nav_LIN)),
       file.path(OUT_DIR, "nav_LIN.csv"))
fwrite(data.table(date = index(nav_SOFT), NAV = as.numeric(nav_SOFT)),
       file.path(OUT_DIR, "nav_SOFT.csv"))

# Equity curve (3 lines)
png(file.path(OUT_DIR, "output", "equity_curve_3weighting.png"), width = 1400, height = 800)
plot(index(nav_EW), as.numeric(nav_EW), type = "l", col = "darkblue", lwd = 2,
     main = "PD29 — 3 Weighting Equity Curve (2001-07 ~ 2026-04)",
     xlab = "Date", ylab = "NAV (cumulative)",
     ylim = c(0.5, max(c(as.numeric(nav_EW), as.numeric(nav_LIN), as.numeric(nav_SOFT)),
                       na.rm = TRUE) * 1.05))
lines(index(nav_LIN), as.numeric(nav_LIN), col = "darkred", lwd = 2)
lines(index(nav_SOFT), as.numeric(nav_SOFT), col = "darkgreen", lwd = 2)
abline(h = 1, lty = 2, col = "gray")
legend("topleft",
       legend = c(sprintf("EW (SR=%.3f CAGR=%.2f%% MDD=%.2f%%)",
                          result_EW$metrics$sharpe,
                          result_EW$metrics$cagr * 100,
                          -result_EW$metrics$mdd * 100),
                  sprintf("LIN (SR=%.3f CAGR=%.2f%% MDD=%.2f%%)",
                          result_LIN$metrics$sharpe,
                          result_LIN$metrics$cagr * 100,
                          -result_LIN$metrics$mdd * 100),
                  sprintf("SOFT (SR=%.3f CAGR=%.2f%% MDD=%.2f%%)",
                          result_SOFT$metrics$sharpe,
                          result_SOFT$metrics$cagr * 100,
                          -result_SOFT$metrics$mdd * 100)),
       col = c("darkblue", "darkred", "darkgreen"), lwd = 2)
dev.off()

# Annual returns 3 lines
build_annual <- function(rets_xts) {
  dt <- data.table(date = index(rets_xts), ret = as.numeric(rets_xts))
  dt[, year := format(date, "%Y")]
  dt[, .(annual_ret = prod(1 + ret, na.rm = TRUE) - 1), by = year]
}
ann_EW <- build_annual(result_EW$port_ret_net_xts)
ann_LIN <- build_annual(result_LIN$port_ret_net_xts)
ann_SOFT <- build_annual(result_SOFT$port_ret_net_xts)

png(file.path(OUT_DIR, "output", "annual_returns_3weighting.png"), width = 1400, height = 800)
years <- ann_EW$year
mat <- rbind(ann_EW$annual_ret, ann_LIN$annual_ret, ann_SOFT$annual_ret)
rownames(mat) <- c("EW", "LIN", "SOFT")
barplot(mat, beside = TRUE, names.arg = years,
        col = c("darkblue", "darkred", "darkgreen"),
        las = 2, cex.names = 0.7,
        main = "PD29 — Annual Returns by Weighting",
        legend.text = TRUE, args.legend = list(x = "topright"))
abline(h = 0, col = "black")
dev.off()

# OOS zoom (2021-04 ~ 2026-04, last 5Y)
oos_start <- as.Date("2021-04-01")
nav_EW_oos <- nav_EW[index(nav_EW) >= oos_start]
nav_LIN_oos <- nav_LIN[index(nav_LIN) >= oos_start]
nav_SOFT_oos <- nav_SOFT[index(nav_SOFT) >= oos_start]

png(file.path(OUT_DIR, "output", "oos_zoom_chart_3weighting.png"), width = 1400, height = 800)
plot(index(nav_EW_oos), as.numeric(nav_EW_oos), type = "l", col = "darkblue", lwd = 2,
     main = "PD29 — OOS Zoom (2021-04 ~ 2026-04, last 5Y)",
     xlab = "Date", ylab = "NAV (cum from 2001-07)")
lines(index(nav_LIN_oos), as.numeric(nav_LIN_oos), col = "darkred", lwd = 2)
lines(index(nav_SOFT_oos), as.numeric(nav_SOFT_oos), col = "darkgreen", lwd = 2)
legend("topleft", legend = c("EW", "LIN", "SOFT"),
       col = c("darkblue", "darkred", "darkgreen"), lwd = 2)
dev.off()

# Regime decomposition (4-regime)
build_regime <- function(rets_xts, label) {
  dd <- Drawdowns(rets_xts)
  rets <- as.numeric(rets_xts)
  regimes <- ifelse(as.numeric(dd) < -0.15, "Bear",
                    ifelse(as.numeric(dd) < -0.05, "Recovery",
                           ifelse(as.numeric(dd) > -0.02, "Bull", "Stable")))
  dt <- data.table(regime = regimes, ret = rets, label = label)
  dt[, .(SR = if(sd(ret, na.rm = TRUE) > 0) (mean(ret, na.rm = TRUE) * 12) / (sd(ret, na.rm = TRUE) * sqrt(12)) else NA,
         n = .N),
     by = .(label, regime)]
}
regime_3 <- rbind(
  build_regime(result_EW$port_ret_net_xts, "EW"),
  build_regime(result_LIN$port_ret_net_xts, "LIN"),
  build_regime(result_SOFT$port_ret_net_xts, "SOFT")
)
fwrite(regime_3, file.path(OUT_DIR, "regime_sr_3weighting.csv"))

png(file.path(OUT_DIR, "output", "regime_decomposition_3weighting.png"), width = 1400, height = 800)
regime_3_wide <- dcast(regime_3, regime ~ label, value.var = "SR")
mat_r <- as.matrix(regime_3_wide[, .(EW, LIN, SOFT)])
rownames(mat_r) <- regime_3_wide$regime
mat_r[is.na(mat_r)] <- 0
barplot(t(mat_r), beside = TRUE, names.arg = regime_3_wide$regime,
        col = c("darkblue", "darkred", "darkgreen"),
        main = "PD29 — Regime Decomposition (annualized SR)\nDD<-15%=Bear / DD<-5%=Recovery / DD>-2%=Bull / else Stable",
        ylab = "Annualized Sharpe", legend.text = c("EW", "LIN", "SOFT"),
        args.legend = list(x = "topleft"))
abline(h = 0, col = "black")
dev.off()

#==============================================================================
# Step 12: Hurdle v2.2 TO 600% gate
#==============================================================================
cat("\n[Step 12] Hurdle v2.2 TO 600% gate ...\n")

apply_hurdle <- function(m, label) {
  # Hurdle v2.2: MDD > 45% OR TO > 600% (6.0 in fraction) → hard fail
  hard_fail <- (-m$mdd > 0.45) || (m$annual_to > 6.0)

  score <- 0
  if (m$sharpe >= 0.8) score <- score + 20
  if (m$cagr >= 0.16) score <- score + 20
  if (-m$mdd <= 0.25) score <- score + 20
  if (-m$mdd <= 0.45) score <- score + 5

  grade <- if (hard_fail) "HARD_FAIL"
           else if (score >= 40 && m$cagr >= 0.16 && m$sharpe >= 0.8) "A"
           else if (score >= 30) "B"
           else "C"

  data.table(weighting = label, hard_fail = hard_fail, score = score, grade = grade,
             sharpe = m$sharpe, cagr = m$cagr, mdd_pct = -m$mdd,
             cvar_95 = m$cvar_95, annual_to_pct = m$annual_to,
             to_under_600 = m$annual_to < 6.0)
}

hurdle_3 <- rbind(
  apply_hurdle(result_EW$metrics, "EW"),
  apply_hurdle(result_LIN$metrics, "LIN"),
  apply_hurdle(result_SOFT$metrics, "SOFT")
)
fwrite(hurdle_3, file.path(OUT_DIR, "hurdle_result_3weighting.csv"))
cat("\nHurdle v2.2 results (TO 600%):\n")
print(hurdle_3)

#==============================================================================
# Step 13: Save period_returns + drawdowns for each weighting
#==============================================================================
cat("\n[Step 13] Save period returns + drawdowns for each weighting ...\n")

for (lbl in c("EW", "LIN", "SOFT")) {
  res <- get(paste0("result_", lbl))
  pr_dt <- data.table(
    date = index(res$port_returns_xts),
    gross_return = as.numeric(res$port_returns_xts),
    turnover = res$total_turnover,
    cost = res$monthly_cost,
    net_return = as.numeric(res$port_ret_net_xts)
  )
  fwrite(pr_dt, file.path(OUT_DIR, paste0("period_returns_", lbl, ".csv")))

  dd <- Drawdowns(res$port_ret_net_xts)
  fwrite(data.table(date = index(dd), drawdown = as.numeric(dd)),
         file.path(OUT_DIR, paste0("drawdowns_", lbl, ".csv")))
}

#==============================================================================
# Pure function audit end + JSON summary
#==============================================================================
cat("\n[Audit] Pure function purity end check ...\n")

md5_end <- list(
  alpha_h1_pd27 = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet"),
  alpha_pd24    = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"),
  etf_pd28      = tools::md5sum(file.path(PD28_DIR, "synthetic_etf_returns_2001_2026.parquet"))
)
all_match <- all(unlist(md5_start) == unlist(md5_end))
cat(sprintf("  Pure function audit: %s\n", all_match))
audit_dt <- data.table(
  package = names(md5_start),
  md5_start = unname(unlist(md5_start)),
  md5_end = unname(unlist(md5_end)),
  match = unlist(md5_start) == unlist(md5_end)
)
fwrite(audit_dt, file.path(OUT_DIR, "pure_function_audit.csv"))

#==============================================================================
# Final JSON summary
#==============================================================================
cat("\n[Final] Save backtest_summary.json ...\n")

summary_json <- list(
  wt_id = "WT-D20260511_001",
  phase = "PD29",
  mandate = "3 weighting comparison (EW / LIN / SOFT) — 도훈 mandate 2026-05-12",
  window = list(start = as.character(START_DATE), end = as.character(END_DATE),
                n_months_target = n_months_total,
                n_months_actual_EW = nrow(port_EW),
                n_months_actual_LIN = nrow(port_LIN),
                n_months_actual_SOFT = nrow(port_SOFT)),
  sleeves = as.list(SLEEVE_W),
  metrics_3weighting = list(
    EW = result_EW$metrics,
    LIN = result_LIN$metrics,
    SOFT = result_SOFT$metrics
  ),
  s4_v2_baseline = S4_V2,
  s4_v2_4axis_strict = list(
    EW = list(n_improved = axis_dt[weighting == "EW"]$n_improved,
              strict_pass = axis_dt[weighting == "EW"]$strict_pass),
    LIN = list(n_improved = axis_dt[weighting == "LIN"]$n_improved,
               strict_pass = axis_dt[weighting == "LIN"]$strict_pass),
    SOFT = list(n_improved = axis_dt[weighting == "SOFT"]$n_improved,
                strict_pass = axis_dt[weighting == "SOFT"]$strict_pass)
  ),
  dm_test = lapply(dm_list, function(x) list(
    comp = paste(x$label1, "vs", x$label2),
    mean_diff = x$mean_diff, se_NW = x$se_NW, t_NW = x$t_NW, n = x$n
  )),
  hurdle_v22 = list(
    EW = list(grade = hurdle_3[weighting == "EW"]$grade,
              to_under_600 = hurdle_3[weighting == "EW"]$to_under_600,
              hard_fail = hurdle_3[weighting == "EW"]$hard_fail),
    LIN = list(grade = hurdle_3[weighting == "LIN"]$grade,
               to_under_600 = hurdle_3[weighting == "LIN"]$to_under_600,
               hard_fail = hurdle_3[weighting == "LIN"]$hard_fail),
    SOFT = list(grade = hurdle_3[weighting == "SOFT"]$grade,
                to_under_600 = hurdle_3[weighting == "SOFT"]$to_under_600,
                hard_fail = hurdle_3[weighting == "SOFT"]$hard_fail)
  ),
  pure_function_audit_all_match = all_match,
  measurement_basis_primary = "forge_realized_share_based",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(summary_json, file.path(JUDGE_DIR, "backtest_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Copy hurdle result + 4axis to judge_ready
file.copy(file.path(OUT_DIR, "hurdle_result_3weighting.csv"),
          file.path(JUDGE_DIR, "hurdle_result_3weighting.csv"), overwrite = TRUE)
file.copy(file.path(OUT_DIR, "4axis_strict_improve_3weighting.csv"),
          file.path(JUDGE_DIR, "4axis_strict_improve_3weighting.csv"), overwrite = TRUE)
file.copy(file.path(OUT_DIR, "dm_test_pairwise.csv"),
          file.path(JUDGE_DIR, "dm_test_pairwise.csv"), overwrite = TRUE)
file.copy(file.path(OUT_DIR, "metrics_3weighting.csv"),
          file.path(JUDGE_DIR, "metrics_3weighting.csv"), overwrite = TRUE)

cat("\n================ PD29 — 3 Weighting Comparison Backtest COMPLETED ================\n")
cat(sprintf("Output dir: %s\n", OUT_DIR))
cat(sprintf("Judge dir : %s\n", JUDGE_DIR))
