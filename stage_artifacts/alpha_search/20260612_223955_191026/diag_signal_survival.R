# diag_signal_survival.R — STR_AS_20260612_223955_191026 (EN_04 Diversity-Max Ensemble)
# 목적: QEPM 차용 심사 진단 — rank-IC 최근 36m, FM lambda 최근 36m,
#        CAPM 잔차알파 pre/post-2017 + 최근 3y (NW lag-3). 성과 자체합성 없음 — lm/NW 표준만.
suppressPackageStartupMessages({
  library(data.table)
  library(sandwich)
  library(lmtest)
})

art <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260612_223955_191026"

## 1) rank-IC: full / post-2017 / 최근 36m
ic <- fread(file.path(art, "analysis_ic.csv"))
ic[, Signal_Date := as.Date(Signal_Date)]
ic_stat <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  m <- mean(x); s <- sd(x)
  c(n = n, mean = m, t = m / s * sqrt(n), pos_rate = mean(x > 0))
}
cat("== rank-IC ==\n")
print(round(rbind(
  full      = ic_stat(ic$IC),
  post2017  = ic_stat(ic[Signal_Date >= "2017-01-01", IC]),
  last36m   = ic_stat(tail(ic[order(Signal_Date)], 36)$IC),
  last60m   = ic_stat(tail(ic[order(Signal_Date)], 60)$IC)
), 4))

## 2) FM lambda (Score): full / post-2017 / 최근 36m — NW lag-3 t
fmb <- fread(file.path(art, "analysis_fmb.csv"))
fmb[, Signal_Date := as.Date(Signal_Date)]
setorder(fmb, Signal_Date)
fm_stat <- function(x) {
  x <- x[is.finite(x)]
  fit <- lm(x ~ 1)
  tt <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  c(n = length(x), lambda = mean(x), t_nw = tt[1, "t value"])
}
cat("\n== FM lambda (Score) ==\n")
print(round(rbind(
  full     = fm_stat(fmb$Lambda_Score),
  post2017 = fm_stat(fmb[Signal_Date >= "2017-01-01", Lambda_Score]),
  last36m  = fm_stat(tail(fmb$Lambda_Score, 36))
), 4))

## 3) CAPM 잔차알파 (일간 net vs KOSPI200) — full / pre-2017 / post-2017 / 최근 3y
pr <- fread(file.path(art, "03_period_returns.csv"))
bm <- fread(file.path(art, "05_benchmark_returns.csv"))
pr[, date := as.Date(date)]
bm[, date := as.Date(date)]
d <- merge(pr[, .(date, r = ret_net)], bm[, .(date, b = benchmark_ret)], by = "date")
setorder(d, date)

capm <- function(dd, label) {
  fit <- lm(r ~ b, data = dd)
  tt <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  data.table(
    window     = label,
    n          = nrow(dd),
    alpha_ann  = round(coef(fit)[1] * 252 * 100, 2),
    alpha_t_nw = round(tt[1, "t value"], 3),
    beta       = round(coef(fit)[2], 3),
    raw_active_ann = round(mean(dd$r - dd$b) * 252 * 100, 2),
    bm_ann     = round(mean(dd$b) * 252 * 100, 2)
  )
}
cat("\n== CAPM residual alpha (daily, NW lag-3) ==\n")
res <- rbind(
  capm(d, "full 2005-2026"),
  capm(d[date < "2017-01-01"], "pre-2017"),
  capm(d[date >= "2017-01-01"], "post-2017"),
  capm(d[date >= max(date) - 3 * 365], "last 3y"),
  capm(d[date >= "2025-01-01"], "2025-26 meltup")
)
print(res)

## 4) IC_MA6 최근 추이 (참고)
cat("\n== IC_MA6 tail 12 ==\n")
print(tail(ic[order(Signal_Date), .(Signal_Date, IC = round(IC, 4), IC_MA6 = round(IC_MA6, 4))], 12))
