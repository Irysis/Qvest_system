# Diagnostic: QEPM adoption review for STR_AS_20260612_130540_180351 (Trended Momentum)
# Purpose: beta-adjusted residual alpha pre/post-2017 + recent 36m, rank-IC recency, FMB lambda recency.
# Diagnostic regressions only — no performance synthesis. Monthly aggregation via PerformanceAnalytics standard functions.
suppressMessages({
  library(xts); library(PerformanceAnalytics); library(sandwich); library(lmtest); library(data.table)
})

setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260612_130540_180351")
bt <- readRDS("bt_result.rds")

pr <- bt$period_returns
bm <- bt$benchmark_returns
stopifnot(all(pr$date == bm$date))

strat_d <- xts(pr$ret_net, order.by = pr$date)
bm_d    <- xts(bm$benchmark_ret, order.by = bm$date)

# Monthly aggregation (standard: apply.monthly + Return.cumulative)
strat_m <- apply.monthly(strat_d, Return.cumulative)
bm_m    <- apply.monthly(bm_d,    Return.cumulative)
m <- merge(strat_m, bm_m); colnames(m) <- c("strat", "bm")
m <- na.omit(m)

capm_nw <- function(sub, label) {
  if (nrow(sub) < 12) { cat(sprintf("%s: insufficient obs (%d)\n", label, nrow(sub))); return(invisible(NULL)) }
  fit <- lm(strat ~ bm, data = as.data.frame(sub))
  ct  <- coeftest(fit, vcov = NeweyWest(fit, lag = 3, prewhite = FALSE))
  a_m <- ct[1, 1]; a_t <- ct[1, 3]; b <- ct[2, 1]; b_t <- ct[2, 3]
  act <- sub$strat - sub$bm
  act_sr <- as.numeric(SharpeRatio.annualized(act, Rf = 0))
  cat(sprintf("%-22s n=%3d | CAPM alpha %+6.2f%%/yr (NW t=%+5.2f) | beta %5.3f (t=%4.1f) | active SR %+5.2f\n",
              label, nrow(sub), a_m * 12 * 100, a_t, b, b_t, act_sr))
}

cat("== CAPM residual alpha vs KOSPI200 (monthly, NW lag-3) ==\n")
capm_nw(m,                       "FULL 2005-2026")
capm_nw(m["/2016-12"],           "PRE-2017")
capm_nw(m["2017-01/"],           "POST-2017")
capm_nw(m["2020-01/"],           "POST-2020")
capm_nw(m["2023-07/"],           "RECENT 36M")

cat("\n== BM context (Return.cumulative) ==\n")
cat(sprintf("BM 2025-01..end cum: %+.1f%% | strat: %+.1f%%\n",
    100 * as.numeric(Return.cumulative(bm_d["2025-01/"])),
    100 * as.numeric(Return.cumulative(strat_d["2025-01/"]))))
cat(sprintf("BM 2017-01..end cum ann (table): \n"))
print(table.AnnualizedReturns(merge(strat_d["2017-01/"], bm_d["2017-01/"])))

cat("\n== Rank-IC recency (analysis_ic.csv) ==\n")
ic <- fread("analysis_ic.csv")
ic[, Signal_Date := as.Date(Signal_Date)]
ic_t <- function(x) mean(x) / sd(x) * sqrt(length(x))
for (w in list(c("FULL", NA), c("LAST60", 60), c("LAST36", 36), c("LAST24", 24))) {
  sub <- if (is.na(w[2])) ic$IC else tail(ic$IC, as.integer(w[2]))
  cat(sprintf("%-7s n=%3d | IC mean %+7.4f | t=%+5.2f | IC>0 %4.1f%%\n",
      w[1], length(sub), mean(sub), ic_t(sub), 100 * mean(sub > 0)))
}

cat("\n== FMB lambda_Score recency (analysis_fmb.csv, NW lag-3) ==\n")
fmb <- fread("analysis_fmb.csv")
fmb[, Signal_Date := as.Date(Signal_Date)]
fmb_nw <- function(x, label) {
  fit <- lm(x ~ 1)
  ct <- coeftest(fit, vcov = NeweyWest(fit, lag = 3, prewhite = FALSE))
  cat(sprintf("%-9s n=%3d | lambda mean %+8.5f | NW t=%+5.2f\n", label, length(x), ct[1,1], ct[1,3]))
}
fmb_nw(fmb$Lambda_Score, "FULL")
fmb_nw(fmb[Signal_Date < as.Date("2017-01-01")]$Lambda_Score, "PRE-2017")
fmb_nw(fmb[Signal_Date >= as.Date("2017-01-01")]$Lambda_Score, "POST-2017")
fmb_nw(tail(fmb$Lambda_Score, 36), "LAST36")

cat("\n== IC pre/post 2017 ==\n")
pre  <- ic[Signal_Date <  as.Date("2017-01-01")]$IC
post <- ic[Signal_Date >= as.Date("2017-01-01")]$IC
cat(sprintf("PRE-2017  n=%3d | IC mean %+7.4f | t=%+5.2f\n", length(pre), mean(pre), ic_t(pre)))
cat(sprintf("POST-2017 n=%3d | IC mean %+7.4f | t=%+5.2f\n", length(post), mean(post), ic_t(post)))
