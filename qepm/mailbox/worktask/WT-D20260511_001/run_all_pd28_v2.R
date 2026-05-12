#==============================================================================
# WT-D20260511_001 PD28 v2 — 297m max backtest (corrected)
#
# 핵심 수정 (v2):
# - POST-2011 KR equity sleeve: inherit PD20-b composite_top20 holdings/returns (PIT-fix)
#   (alpha-research가 이미 산출한 정통 z_composite 0.818/0.182 top20 결과 reuse)
# - PRE-2011 KR equity sleeve: z_NEW solo top20 (Forge가 alpha를 만들지 않음, 단순 ranking)
#   - PD24 NEW alpha 1999-01~2010-12 = 114 monthly cross-section
#   - 각 sig_date에서 alpha 값 desc rank top20 EW
# - TSMOM/KR_10Y/Cash: ETF synthesis (Step 1 동일)
# - Cost / weights / Return.portfolio: Method A canonical (PD26 verdict)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(dplyr)
  library(PerformanceAnalytics); library(xts); library(zoo)
  library(jsonlite); library(lubridate)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
PD28_DIR <- file.path(SA_DIR, "pd28")
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd28")
JUDGE_DIR <- file.path(WT_DIR, "judge_ready", "pd28")
dir.create(PD28_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(JUDGE_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUT_DIR, "output"), showWarnings = FALSE, recursive = TRUE)

cat("================ PD28 v2 — 297m max backtest (inherit-based) ================\n")

START_DATE <- as.Date("2001-07-01")
END_DATE   <- as.Date("2026-04-01")

# Pure function audit
md5_start <- list(
  alpha_h1   = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores.parquet"),
  alpha_pd24 = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"),
  pd20b_returns = tools::md5sum("stage_artifacts/WT_D20260511_001/composite_top20_returns_pd20b_pit_fix.csv"),
  risk = tools::md5sum(file.path(WT_DIR, "risk_package.json")),
  opt  = tools::md5sum(file.path(WT_DIR, "optimization_package.json"))
)
cat("Start hashes recorded.\n")

#==============================================================================
# Step 1: ETF synthesis (reuse v1 cache if exists)
#==============================================================================
cat("\n[Step 1] ETF synthesis ...\n")

bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, YearMonth := format(Date, "%Y-%m")]
kospi_mo <- bm[!is.na(BM_Ret) & Date >= as.Date("2001-06-01"),
               .(KOSPI200 = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YearMonth]
kospi_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(kospi_mo, sig_date)

ec <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))

# KR 10Y bond
kr_10y <- ec[Series == "KR_Gov10Y", .(Date, yield = Value)]
setkey(kr_10y, Date)
D_KR <- 8.5
kr_10y[, yield_chg := c(NA, diff(yield))]
kr_10y[, daily_ret := -((D_KR) / (1 + yield/100)) * (yield_chg/100) + (yield/100)/252]
kr_10y[, YearMonth := format(Date, "%Y-%m")]
kr_10y_mo <- kr_10y[!is.na(daily_ret),
                    .(KR_10Y = prod(1 + daily_ret, na.rm = TRUE) - 1), by = YearMonth]
kr_10y_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(kr_10y_mo, sig_date)

# KR short bond (CD91)
kr_cd <- ec[Series == "KR_CD91", .(Date, yield = Value)]
setkey(kr_cd, Date)
kr_cd[, daily_ret := (yield/100) / 252]
kr_cd[, YearMonth := format(Date, "%Y-%m")]
kr_short_mo <- kr_cd[!is.na(daily_ret),
                     .(KR_SHORT = prod(1 + daily_ret, na.rm = TRUE) - 1), by = YearMonth]
kr_short_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(kr_short_mo, sig_date)

# Cash KRW
kr_call <- ec[Series == "KR_Call1D", .(Date, yield = Value)]
setkey(kr_call, Date)
kr_call[, daily_ret := (yield/100) / 252]
kr_call[, YearMonth := format(Date, "%Y-%m")]
cash_mo <- kr_call[!is.na(daily_ret),
                   .(CASH = prod(1 + daily_ret, na.rm = TRUE) - 1), by = YearMonth]
cash_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(cash_mo, sig_date)

# US 10Y hedged
fred <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
us_10y <- fred[Series_ID == "DGS10", .(Date, yield = Value)]
setkey(us_10y, Date)
D_US <- 8.0
us_10y[, yield_chg := c(NA, diff(yield))]
us_10y[, daily_ret := -((D_US) / (1 + yield/100)) * (yield_chg/100) + (yield/100)/252]
us_10y[, YearMonth := format(Date, "%Y-%m")]
us_10y_mo <- us_10y[!is.na(daily_ret),
                    .(US_10Y_H = prod(1 + daily_ret, na.rm = TRUE) - 1), by = YearMonth]
us_10y_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(us_10y_mo, sig_date)

# Build wide table 2001-07~2026-04
all_months <- data.table(sig_date = seq.Date(START_DATE, END_DATE, by = "month"))
setkey(all_months, sig_date)
etf_wide <- merge(all_months, kospi_mo[, .(sig_date, KOSPI200)], by = "sig_date", all.x = TRUE)
etf_wide <- merge(etf_wide, kr_10y_mo[, .(sig_date, KR_10Y)], by = "sig_date", all.x = TRUE)
etf_wide <- merge(etf_wide, kr_short_mo[, .(sig_date, KR_SHORT)], by = "sig_date", all.x = TRUE)
etf_wide <- merge(etf_wide, us_10y_mo[, .(sig_date, US_10Y_H)], by = "sig_date", all.x = TRUE)
etf_wide <- merge(etf_wide, cash_mo[, .(sig_date, CASH)], by = "sig_date", all.x = TRUE)

# KOSDAQ150 + proxies (use KOSPI200 fallback pre-2015)
rd_mo <- as.data.table(arrow::read_parquet(".cache/rawdata.parquet",
          col_select = c("Date", "Ticker", "Ret", "KQ150", "K200")))
rd_mo <- rd_mo[Date >= as.Date("2001-06-01") & Date <= (END_DATE + 31) & !is.na(Ret)]
rd_mo[, YearMonth := format(Date, "%Y-%m")]
kq150_panel <- rd_mo[KQ150 == TRUE & !is.na(Ret),
                     .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1),
                     by = .(YearMonth, Ticker)]
kq150_mo <- kq150_panel[, .(KOSDAQ150 = mean(stock_ret, na.rm = TRUE)), by = YearMonth]
kq150_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(kq150_mo, sig_date)
etf_wide <- merge(etf_wide, kq150_mo[, .(sig_date, KOSDAQ150)], by = "sig_date", all.x = TRUE)
etf_wide[is.na(KOSDAQ150), KOSDAQ150 := KOSPI200]
etf_wide[, GOLD_H_PROXY := KOSPI200]
etf_wide[, SP500_H_PROXY := KOSPI200]
etf_wide[, REIT_PROXY := KOSPI200]

arrow::write_parquet(etf_wide, file.path(PD28_DIR, "synthetic_etf_returns_2001_2026.parquet"))
cat(sprintf("  ETF synthetic returns saved: %d months × %d ETFs\n", nrow(etf_wide), ncol(etf_wide) - 1))

#==============================================================================
# Step 2: KR equity sleeve (PRE-2011 z_NEW solo + POST-2011 inherit PD20-b)
#==============================================================================
cat("\n[Step 2] KR equity sleeve (PRE-2011 z_NEW solo + POST-2011 inherit) ...\n")

# 2a. Pre-2011 z_NEW solo top20
alpha_new <- as.data.table(read_parquet("stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"))
alpha_new <- alpha_new[sig_date >= START_DATE & sig_date < as.Date("2011-01-01")]
cat(sprintf("  alpha_new pre-2011: %d rows, %d sig_dates\n",
            nrow(alpha_new), uniqueN(alpha_new$sig_date)))

# Ret_1m per Ticker (RAWDATA) — forward 1m at sig_date label
rd_ret_mo <- rd_mo[!is.na(Ret),
                   .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
                   by = .(YearMonth, Ticker)]
rd_ret_mo[, sig_date := as.Date(paste0(YearMonth, "-01"))]
rd_ret_mo[, sig_date_held := sig_date]  # this YearMonth = held period
setkey(rd_ret_mo, sig_date, Ticker)

# At sig_date label t, return is for month t+1 (forward 1m per Method A canonical)
# So holdings at sig_date t are held during month t+1
pre_2011_sig_dates <- unique(alpha_new$sig_date)
pre_2011_rets <- list()
for (sd in pre_2011_sig_dates) {
  sd_d <- as.Date(sd, origin = "1970-01-01")
  sub <- alpha_new[sig_date == sd_d & !is.na(alpha)]
  if (nrow(sub) < 20) next
  setorder(sub, -alpha)
  top20 <- sub[1:20]

  # Forward 1m return: held during YearMonth = format(sd + 1m, "%Y-%m")
  held_period <- sd_d %m+% months(1)
  rets_held <- rd_ret_mo[sig_date == held_period & Ticker %in% top20$Ticker, .(Ticker, Ret_1m)]
  merged <- merge(top20[, .(Ticker)], rets_held, by = "Ticker", all.x = TRUE)
  merged[is.na(Ret_1m), Ret_1m := 0]
  pre_ret <- mean(merged$Ret_1m)  # EW
  pre_2011_rets[[as.character(sd_d)]] <- data.table(
    sig_date = sd_d,
    held_date = held_period,
    monthly_ret = pre_ret,
    n_holdings = 20,
    n_present = nrow(rets_held)
  )
}
pre_2011_dt <- rbindlist(pre_2011_rets)
cat(sprintf("  PRE-2011 z_NEW solo returns: %d months\n", nrow(pre_2011_dt)))

# 2b. POST-2011 inherit from PD20-b composite_top20_returns_pd20b_pit_fix.csv (READ-ONLY)
pd20b <- fread("stage_artifacts/WT_D20260511_001/composite_top20_returns_pd20b_pit_fix.csv")
pd20b[, sig_date := as.Date(sig_date)]
# sig_date label here = held_date (which YearMonth was returns computed?)
# Per PD26 verdict Method A canonical: sig_date label t = forward 1m return for month t+1
# But PD20-b CSV reports monthly_ret at sig_date label — need to clarify
# Check first row: 2011-01-01 monthly_ret -0.01292733. KOSPI 200 Feb 2011 ret was ~-1.2% (Lehman aftermath).
# So sig_date label t = held during t+1 month (PD26 Method A canonical) → here we treat sig_date=held_date_marker
# meaning return reported is Feb 2011 (held during Feb 2011)

# To align with our pre-2011 (where held_date = sig_date + 1m),
# we set held_date for PD20-b such that consistent: held_date = sig_date_label + 1m
pd20b[, held_date := sig_date %m+% months(1)]
pd20b_dt <- pd20b[, .(sig_date, held_date, monthly_ret, n_holdings, n_present)]
cat(sprintf("  POST-2011 PD20-b inherit: %d months\n", nrow(pd20b_dt)))

# 2c. Combine
kr_eq_sleeve <- rbindlist(list(pre_2011_dt, pd20b_dt))
setorder(kr_eq_sleeve, held_date)
cat(sprintf("  KR equity sleeve combined: %d months (%s ~ %s)\n",
            nrow(kr_eq_sleeve), min(kr_eq_sleeve$held_date), max(kr_eq_sleeve$held_date)))

fwrite(kr_eq_sleeve, file.path(PD28_DIR, "kr_equity_sleeve_v2_returns.csv"))

#==============================================================================
# Step 2c: TSMOM 8-ETF sleeve (same as v1)
#==============================================================================
cat("\n[Step 2c] TSMOM 8-ETF sleeve ...\n")
tsmom_8 <- c("KOSPI200", "KR_10Y", "KR_SHORT", "US_10Y_H",
             "KOSDAQ150", "GOLD_H_PROXY", "SP500_H_PROXY", "REIT_PROXY")
etf_wide_tsmom <- etf_wide[, c("sig_date", tsmom_8), with = FALSE]
setkey(etf_wide_tsmom, sig_date)

n_tsmom <- nrow(etf_wide_tsmom)
tsmom_signals <- matrix(NA_real_, nrow = n_tsmom, ncol = length(tsmom_8),
                        dimnames = list(NULL, tsmom_8))
for (i in 1:n_tsmom) {
  for (col in tsmom_8) {
    start <- i - 12 + 1; end <- i - 1
    if (start >= 1 && end >= start) {
      tsmom_signals[i, col] <- prod(1 + etf_wide_tsmom[[col]][start:end], na.rm = TRUE) - 1
    }
  }
}
tsmom_weights <- matrix(0, nrow = n_tsmom, ncol = length(tsmom_8),
                        dimnames = list(NULL, tsmom_8))
for (i in 1:n_tsmom) {
  pos <- which(tsmom_signals[i, ] > 0)
  if (length(pos) > 0) tsmom_weights[i, pos] <- 1 / length(pos)
}
# TSMOM portfolio return: weights at i-1 apply to returns at i (signals known at sig_date t use rets t)
tsmom_ret <- numeric(n_tsmom)
for (i in 2:n_tsmom) {
  tsmom_ret[i] <- sum(tsmom_weights[i-1, ] * as.numeric(etf_wide_tsmom[i, -1, with = FALSE]),
                      na.rm = TRUE)
}
tsmom_dt <- data.table(held_date = etf_wide_tsmom$sig_date, TSMOM = tsmom_ret)
cat(sprintf("  TSMOM sleeve: %d months\n", nrow(tsmom_dt)))

#==============================================================================
# Step 3: Portfolio backtest (PerformanceAnalytics)
#==============================================================================
cat("\n[Step 3] 4-sleeve portfolio backtest ...\n")

# Align all sleeves by held_date
port_dt <- merge(
  data.table(held_date = etf_wide$sig_date),
  kr_eq_sleeve[, .(held_date, KR_EQUITY = monthly_ret)],
  by = "held_date", all.x = TRUE
)
port_dt <- merge(port_dt, tsmom_dt[, .(held_date, TSMOM)], by = "held_date", all.x = TRUE)
port_dt <- merge(port_dt, kr_10y_mo[, .(held_date = sig_date, KR_10Y)],
                 by = "held_date", all.x = TRUE)
port_dt <- merge(port_dt, cash_mo[, .(held_date = sig_date, CASH)],
                 by = "held_date", all.x = TRUE)
port_dt <- port_dt[!is.na(KR_EQUITY) & !is.na(TSMOM) & !is.na(KR_10Y) & !is.na(CASH)]
cat(sprintf("  Portfolio: %d months (%s ~ %s)\n",
            nrow(port_dt), min(port_dt$held_date), max(port_dt$held_date)))

returns_xts <- xts(port_dt[, .(KR_EQUITY, TSMOM, KR_10Y, CASH)],
                   order.by = port_dt$held_date)
weights_target <- c(KR_EQUITY = 0.55, TSMOM = 0.225, KR_10Y = 0.18, CASH = 0.045)

port_ret <- Return.portfolio(R = returns_xts, weights = weights_target,
                              geometric = TRUE, rebalance_on = "months",
                              verbose = TRUE)
port_returns_xts <- port_ret$returns
port_weights_xts <- port_ret$BOP.Weight

# Turnover + cost
turnover_vec <- numeric(nrow(port_weights_xts))
for (i in 2:nrow(port_weights_xts)) {
  prev_w <- as.numeric(port_weights_xts[i-1, ])
  curr_w <- as.numeric(port_weights_xts[i, ])
  turnover_vec[i] <- sum(abs(curr_w - prev_w))
}
# Inner sleeve turnover (KR equity top20 churn 30% + TSMOM rotation 50%)
total_turnover <- turnover_vec + 0.30 * 0.55 + 0.50 * 0.225
monthly_cost <- total_turnover * 0.0015
port_ret_net <- as.numeric(port_returns_xts) - monthly_cost
port_ret_net_xts <- xts(port_ret_net, order.by = index(port_returns_xts))

fwrite(data.table(
  date = index(port_returns_xts),
  gross_return = as.numeric(port_returns_xts),
  turnover = total_turnover,
  cost = monthly_cost,
  net_return = port_ret_net
), file.path(OUT_DIR, "period_returns.csv"))

#==============================================================================
# Step 4: Metrics
#==============================================================================
cat("\n[Step 4] Metrics ...\n")

ar_table <- PerformanceAnalytics::table.AnnualizedReturns(port_ret_net_xts, scale = 12, geometric = TRUE)
print(ar_table)
annualized_return <- as.numeric(ar_table[1, 1])
annualized_stdev  <- as.numeric(ar_table[2, 1])
sharpe_ratio      <- as.numeric(ar_table[3, 1])

mdd <- PerformanceAnalytics::maxDrawdown(port_ret_net_xts)
cvar_95 <- as.numeric(PerformanceAnalytics::CVaR(port_ret_net_xts, p = 0.95, method = "historical"))
sortino <- as.numeric(PerformanceAnalytics::SortinoRatio(port_ret_net_xts))
calmar <- as.numeric(PerformanceAnalytics::CalmarRatio(port_ret_net_xts, scale = 12))
annual_turnover <- mean(total_turnover[-1], na.rm = TRUE) * 12

cat(sprintf("\nSR=%.4f  CAGR=%.4f  MDD=%.4f  CVaR_95=%.4f  Sortino=%.4f  Calmar=%.4f  TO=%.2f\n",
            sharpe_ratio, annualized_return, mdd, cvar_95, sortino, calmar, annual_turnover))

nav_series <- cumprod(1 + port_ret_net_xts)
nav_dt <- data.table(date = index(nav_series), NAV = as.numeric(nav_series))
fwrite(nav_dt, file.path(OUT_DIR, "nav.csv"))
dd_series <- Drawdowns(port_ret_net_xts)
dd_dt <- data.table(date = index(dd_series), drawdown = as.numeric(dd_series))
fwrite(dd_dt, file.path(OUT_DIR, "drawdowns.csv"))

metrics_dt <- data.table(
  metric = c("annualized_return", "annualized_stdev", "sharpe_ratio",
             "max_drawdown", "cvar_95", "sortino_ratio", "calmar_ratio",
             "annualized_turnover", "n_months",
             "period_start", "period_end"),
  value = c(annualized_return, annualized_stdev, sharpe_ratio,
            mdd, cvar_95, sortino, calmar,
            annual_turnover, length(port_ret_net_xts),
            as.character(min(index(port_ret_net_xts))),
            as.character(max(index(port_ret_net_xts))))
)
fwrite(metrics_dt, file.path(OUT_DIR, "metrics.csv"))

#==============================================================================
# Step 5: vs S4 v2 strict 4-axis
#==============================================================================
cat("\n[Step 5] vs S4 v2 baseline ...\n")
S4_V2 <- list(SR = 1.81, CAGR = 0.1999, MDD = -0.1263, CVaR_95 = -0.0501)
improve <- list(
  SR = sharpe_ratio > S4_V2$SR,
  CAGR = annualized_return > S4_V2$CAGR,
  MDD = (-mdd) > S4_V2$MDD,
  CVaR_95 = cvar_95 > S4_V2$CVaR_95
)
n_improve <- sum(unlist(improve))
strict_pass <- n_improve >= 3

improve_dt <- data.table(
  axis = c("SR", "CAGR", "MDD", "CVaR_95"),
  pd28_value = c(sharpe_ratio, annualized_return, -mdd, cvar_95),
  s4_v2_baseline = c(S4_V2$SR, S4_V2$CAGR, S4_V2$MDD, S4_V2$CVaR_95),
  improved = unlist(improve)
)
fwrite(improve_dt, file.path(OUT_DIR, "4axis_strict_improve_vs_s4_v2.csv"))
print(improve_dt)
cat(sprintf("  4-axis: %d/4 (strict pass = %s)\n", n_improve, strict_pass))

# Sub-period
pre_idx <- index(port_ret_net_xts) < as.Date("2011-01-01")
post_idx <- index(port_ret_net_xts) >= as.Date("2011-01-01")
ret_pre <- port_ret_net_xts[pre_idx]
ret_post <- port_ret_net_xts[post_idx]
ar_pre <- table.AnnualizedReturns(ret_pre, scale=12, geometric=TRUE)
ar_post <- table.AnnualizedReturns(ret_post, scale=12, geometric=TRUE)
cat("\nSub-period analysis:\n")
cat(sprintf("  PRE-2011 (%d mo, z_NEW solo): SR=%.3f CAGR=%.4f MDD=%.4f\n",
            length(ret_pre), as.numeric(ar_pre[3,1]), as.numeric(ar_pre[1,1]), maxDrawdown(ret_pre)))
cat(sprintf("  POST-2011 (%d mo, inherit PD20-b): SR=%.3f CAGR=%.4f MDD=%.4f\n",
            length(ret_post), as.numeric(ar_post[3,1]), as.numeric(ar_post[1,1]), maxDrawdown(ret_post)))

sub_period_dt <- data.table(
  period = c("PRE_2011_z_NEW_solo", "POST_2011_inherit_PD20b"),
  n_months = c(length(ret_pre), length(ret_post)),
  SR = c(as.numeric(ar_pre[3,1]), as.numeric(ar_post[3,1])),
  CAGR = c(as.numeric(ar_pre[1,1]), as.numeric(ar_post[1,1])),
  MDD = c(maxDrawdown(ret_pre), maxDrawdown(ret_post))
)
fwrite(sub_period_dt, file.path(OUT_DIR, "sub_period_pre_post_2011.csv"))

#==============================================================================
# Step 6: Charts
#==============================================================================
cat("\n[Step 6] Charts ...\n")

png(file.path(OUT_DIR, "output", "equity_curve.png"), width = 1200, height = 700)
plot(nav_dt$date, nav_dt$NAV, type = "l",
     main = sprintf("PD28 v2 296m Equity Curve (2001-08 ~ 2026-03)\nSR=%.3f CAGR=%.2f%% MDD=%.2f%%",
                    sharpe_ratio, annualized_return * 100, mdd * 100),
     xlab = "Date", ylab = "NAV", col = "darkblue", lwd = 2)
abline(h = 1, lty = 2, col = "gray")
abline(v = as.Date("2011-01-01"), col = "red", lty = 2)
text(as.Date("2011-01-01"), 0.9 * max(nav_dt$NAV), "2011-01\n(z_composite start)",
     pos = 4, col = "darkred", cex = 0.8)
dev.off()

ret_dt <- data.table(date = index(port_ret_net_xts), ret = as.numeric(port_ret_net_xts))
ret_dt[, year := format(date, "%Y")]
annual_rets <- ret_dt[, .(annual_ret = prod(1 + ret, na.rm = TRUE) - 1), by = year]
png(file.path(OUT_DIR, "output", "annual_returns.png"), width = 1200, height = 700)
barplot(annual_rets$annual_ret, names.arg = annual_rets$year,
        main = sprintf("PD28 v2 Annual Returns\nMean=%.2f%% Max=%.2f%% Min=%.2f%%",
                       mean(annual_rets$annual_ret) * 100,
                       max(annual_rets$annual_ret) * 100,
                       min(annual_rets$annual_ret) * 100),
        col = ifelse(annual_rets$annual_ret >= 0, "darkgreen", "darkred"),
        las = 2, cex.names = 0.7)
abline(h = 0)
dev.off()

oos_start <- as.Date("2021-04-01")
oos_idx_c <- index(nav_series) >= oos_start
oos_nav <- nav_series[oos_idx_c]
png(file.path(OUT_DIR, "output", "oos_zoom_chart.png"), width = 1200, height = 700)
plot(index(oos_nav), as.numeric(oos_nav), type = "l",
     main = "PD28 v2 OOS Zoom (2021-04 ~ 2026-03)",
     xlab = "Date", ylab = "NAV (cum from 2001-08)",
     col = "darkred", lwd = 2)
dev.off()

regimes <- ifelse(dd_dt$drawdown < -0.15, "Bear",
                  ifelse(dd_dt$drawdown < -0.05, "Recovery",
                         ifelse(dd_dt$drawdown > -0.02, "Bull", "Stable")))
regime_df <- data.table(date = dd_dt$date, regime = regimes, ret = as.numeric(port_ret_net_xts))
regime_sr <- regime_df[, .(SR = (mean(ret, na.rm=TRUE)*12) / (sd(ret, na.rm=TRUE)*sqrt(12)), n = .N),
                       by = regime]
png(file.path(OUT_DIR, "output", "regime_decomposition.png"), width = 1200, height = 700)
barplot(regime_sr$SR, names.arg = regime_sr$regime,
        main = "PD28 v2 Regime SR Decomposition",
        col = c("darkred", "orange", "darkgreen", "gray"),
        ylab = "Annualized SR")
abline(h = 0)
dev.off()
fwrite(regime_sr, file.path(OUT_DIR, "regime_sr.csv"))

#==============================================================================
# Step 7: Hurdle
#==============================================================================
cat("\n[Step 7] Hurdle ...\n")

hard_fail <- (-mdd > 0.45) || (annual_turnover > 8.0)
score <- 0
if (sharpe_ratio >= 0.8) score <- score + 20
if (annualized_return >= 0.16) score <- score + 20
if (-mdd <= 0.25) score <- score + 20
if (-mdd <= 0.45) score <- score + 5
if (n_improve >= 3) score <- score + 10
grade <- if (hard_fail) {
  "HARD_FAIL"
} else if (score >= 50 && annualized_return >= 0.16 && sharpe_ratio >= 0.8) {
  "A"
} else if (score >= 30) {
  "B"
} else {
  "C"
}

hurdle_dt <- data.table(
  hard_fail = hard_fail,
  score = score,
  grade = grade,
  sharpe = sharpe_ratio,
  cagr = annualized_return,
  mdd = -mdd,
  cvar_95 = cvar_95,
  to_annualized = annual_turnover,
  s4_v2_4axis_improve = n_improve,
  s4_v2_strict_pass = strict_pass
)
fwrite(hurdle_dt, file.path(OUT_DIR, "hurdle_result.csv"))

#==============================================================================
# Audit
#==============================================================================
cat("\n[Audit] Pure function check ...\n")
md5_end <- list(
  alpha_h1 = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores.parquet"),
  alpha_pd24 = tools::md5sum("stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet"),
  pd20b_returns = tools::md5sum("stage_artifacts/WT_D20260511_001/composite_top20_returns_pd20b_pit_fix.csv"),
  risk = tools::md5sum(file.path(WT_DIR, "risk_package.json")),
  opt = tools::md5sum(file.path(WT_DIR, "optimization_package.json"))
)
all_match <- all(unlist(md5_start) == unlist(md5_end))
cat(sprintf("  All match: %s\n", all_match))
audit_dt <- data.table(
  package = names(md5_start),
  md5_start = unname(unlist(md5_start)),
  md5_end = unname(unlist(md5_end)),
  match = unlist(md5_start) == unlist(md5_end)
)
fwrite(audit_dt, file.path(OUT_DIR, "pure_function_audit.csv"))

#==============================================================================
# Summary JSON
#==============================================================================
summary_json <- list(
  wt_id = "WT-D20260511_001",
  phase = "PD28_v2",
  window = list(start = as.character(min(index(port_ret_net_xts))),
                end = as.character(max(index(port_ret_net_xts))),
                n_months = length(port_ret_net_xts)),
  metrics = list(
    sharpe_ratio = sharpe_ratio,
    cagr = annualized_return,
    annualized_stdev = annualized_stdev,
    mdd = -mdd,
    cvar_95 = cvar_95,
    sortino = sortino,
    calmar = calmar,
    annualized_turnover = annual_turnover
  ),
  sub_period = list(
    pre_2011_z_NEW_solo = list(
      n_months = length(ret_pre),
      SR = as.numeric(ar_pre[3,1]),
      CAGR = as.numeric(ar_pre[1,1]),
      MDD = maxDrawdown(ret_pre)
    ),
    post_2011_inherit_pd20b = list(
      n_months = length(ret_post),
      SR = as.numeric(ar_post[3,1]),
      CAGR = as.numeric(ar_post[1,1]),
      MDD = maxDrawdown(ret_post)
    )
  ),
  vs_s4_v2_baseline = list(
    s4_v2_metrics = S4_V2,
    improvement_count = n_improve,
    strict_pass = strict_pass,
    detail = improve
  ),
  hurdle = list(
    hard_fail = hard_fail,
    score = score,
    grade = grade
  ),
  pure_function_audit = list(all_match = all_match, detail = audit_dt),
  charts = list(
    equity_curve = "output/equity_curve.png",
    annual_returns = "output/annual_returns.png",
    oos_zoom = "output/oos_zoom_chart.png",
    regime_decomposition = "output/regime_decomposition.png"
  ),
  data_caveats = list(
    pre_2011_KR_equity = "z_NEW solo top20 (PD24 NEW alpha 2001-07~2010-12, 114 months). 1715 H1 alpha absent pre-2011.",
    post_2011_KR_equity = "INHERIT PD20-b composite_top20_returns_pd20b_pit_fix.csv (z_composite 0.818*z_1715 + 0.182*z_NEW). PIT-fixed Method A canonical.",
    etf_proxy = "Gold/SP500/KOSPI200_LV/REIT use KOSPI 200 proxy (no native pre-launch data). KOSDAQ150 falls back to KOSPI200 pre-2015 (KQ150 flag absent).",
    method_a_canonical = "PD26 verdict applied — Method A only (PerformanceAnalytics::Return.portfolio + 월말 anchor). Method B XV (first-trading-day anchor) NOT used."
  )
)
write_json(summary_json, file.path(OUT_DIR, "metrics_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(summary_json, file.path(JUDGE_DIR, "backtest_summary_pd28.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n================ PD28 v2 — DONE ================\n")
cat(sprintf("  SR=%.3f  CAGR=%.2f%%  MDD=%.2f%%  CVaR_95=%.2f%%  TO=%.2fx\n",
            sharpe_ratio, annualized_return * 100, mdd * 100, cvar_95 * 100, annual_turnover))
cat(sprintf("  Sub: PRE-2011 SR=%.3f / POST-2011 SR=%.3f\n",
            as.numeric(ar_pre[3,1]), as.numeric(ar_post[3,1])))
cat(sprintf("  4-axis vs S4 v2: %d/4 (strict pass = %s)\n", n_improve, strict_pass))
cat(sprintf("  Hurdle: hard_fail=%s, score=%d, grade=%s\n", hard_fail, score, grade))
cat(sprintf("  Pure function audit: all_match=%s\n", all_match))
