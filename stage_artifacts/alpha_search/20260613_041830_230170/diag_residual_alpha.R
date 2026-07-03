# diag_residual_alpha.R — STR_AS_20260613_041830_230170 진단 (성과합성 아님 — 회귀/통계 진단만)
# 1) rank-IC 최근 36m (값·t)  2) FM lambda 최근 36m t  3) CAPM 잔차알파 pre/post-2017 + 최근 3y (NW lag-3)
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest)
})
ad <- "stage_artifacts/alpha_search/20260613_041830_230170"

# ---- 1) rank-IC ----
ic <- fread(file.path(ad, "analysis_ic.csv"))
ic[, Signal_Date := as.Date(Signal_Date)]
setorder(ic, Signal_Date)
ic36 <- tail(ic, 36)
t_ic <- function(x) mean(x) / sd(x) * sqrt(length(x))
cat(sprintf("[IC] full n=%d mean=%.4f t=%.2f | recent36 mean=%.4f t=%.2f | recent36 IC>0 %.0f%%\n",
  nrow(ic), mean(ic$IC), t_ic(ic$IC), mean(ic36$IC), t_ic(ic36$IC), 100*mean(ic36$IC > 0)))

# ---- 2) FM lambda ----
fmb <- fread(file.path(ad, "analysis_fmb.csv"))
fmb[, Signal_Date := as.Date(Signal_Date)]
setorder(fmb, Signal_Date)
fm36 <- tail(fmb, 36)
nw_t <- function(x) {
  fit <- lm(x ~ 1)
  ct <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  ct[1, 3]
}
cat(sprintf("[FMB] full lambda=%.5f NW_t=%.2f | recent36 lambda=%.5f NW_t=%.2f\n",
  mean(fmb$Lambda_Score), nw_t(fmb$Lambda_Score), mean(fm36$Lambda_Score), nw_t(fm36$Lambda_Score)))

# ---- 3) CAPM residual alpha (monthly, NW lag-3) ----
pr <- fread(file.path(ad, "03_period_returns.csv"))
bm <- fread(file.path(ad, "05_benchmark_returns.csv"))
sx <- xts(pr$ret_net, order.by = as.Date(pr$date))
bx <- xts(bm$benchmark_ret, order.by = as.Date(bm$date))
sm <- apply.monthly(sx, Return.cumulative)
bmm <- apply.monthly(bx, Return.cumulative)
m <- merge(sm, bmm, join = "inner"); colnames(m) <- c("strat", "bm")

capm <- function(z, label) {
  fit <- lm(strat ~ bm, data = as.data.frame(z))
  ct <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  cat(sprintf("[CAPM %s] n=%d alpha_ann=%.2f%% t_NW=%.2f beta=%.3f | activeSR(ann)=%.2f\n",
    label, nrow(z), 12 * ct[1, 1] * 100, ct[1, 3], ct[2, 1],
    mean(z$strat - z$bm) / sd(z$strat - z$bm) * sqrt(12)))
}
capm(m, "FULL 2005-2026")
capm(m[index(m) < as.Date("2017-01-01")], "PRE-2017")
capm(m[index(m) >= as.Date("2017-01-01")], "POST-2017")
capm(tail(m, 36), "RECENT-36M")
capm(m[index(m) >= as.Date("2024-12-31")], "2025-26 meltup")

# active return raw (b-drag 확인)
act <- m$strat - m$bm
cat(sprintf("[ACTIVE] post-2017 raw active ann=%.2f%% | recent36 raw active ann=%.2f%%\n",
  12 * mean(act[index(act) >= as.Date("2017-01-01")]) * 100,
  12 * mean(tail(act, 36)) * 100))
