# diag_residual_alpha.R — QEPM 차용 심사 진단 (STR_AS_20260613_035516_228297)
# 목적: (1) rank-IC 최근 36m (2) β-조정 잔차알파 pre/post-2017 + 최근 3y 분해
# 원칙: 성과 자체합성 금지 — 회귀/IC 진단만. 월별 집계는 PerformanceAnalytics apply.monthly(Return.cumulative).
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest)
})

dirp <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260613_035516_228297"

pr <- fread(file.path(dirp, "03_period_returns.csv"))
bm <- fread(file.path(dirp, "05_benchmark_returns.csv"))
ic <- fread(file.path(dirp, "analysis_ic.csv"))

stopifnot(nrow(pr) == nrow(bm))
d <- merge(pr[, .(date = as.Date(date), ret_net)],
           bm[, .(date = as.Date(date), benchmark_ret)], by = "date")

x_p <- xts(d$ret_net, order.by = d$date)
x_b <- xts(d$benchmark_ret, order.by = d$date)

# 월별 집계 (표준함수)
m_p <- apply.monthly(x_p, Return.cumulative)
m_b <- apply.monthly(x_b, Return.cumulative)
M <- merge(m_p, m_b); colnames(M) <- c("p", "b")
M <- na.omit(M)

capm_nw <- function(sub, label) {
  if (nrow(sub) < 12) { cat(sprintf("%s: n=%d insufficient\n", label, nrow(sub))); return(invisible(NULL)) }
  fit <- lm(p ~ b, data = as.data.frame(sub))
  ct <- coeftest(fit, vcov = NeweyWest(fit, lag = 3, prewhite = FALSE))
  a_m <- ct[1, 1]; a_t <- ct[1, 3]; beta <- ct[2, 1]; beta_t <- ct[2, 3]
  cat(sprintf("%s | n=%d | alpha_ann=%+.2f%% (NW3 t=%+.2f, p=%.3f) | beta=%.3f\n",
              label, nrow(sub), a_m * 12 * 100, a_t, ct[1, 4], beta))
  # active 분해: mean active = alpha + (beta-1)*mean(bm)
  act <- mean(sub$p - sub$b) * 12 * 100
  drag <- (beta - 1) * mean(sub$b) * 12 * 100
  cat(sprintf("    active_ann=%+.2f%% = alpha %+.2f%% + beta-drag %+.2f%% (BM ann %+.2f%%)\n",
              act, a_m * 12 * 100, drag, mean(sub$b) * 12 * 100))
}

cat("==== CAPM monthly NW(3) 분해 ====\n")
capm_nw(M, "FULL  2005-02~2026-06")
capm_nw(M["/2016-12"], "PRE-2017")
capm_nw(M["2017-01/"], "POST-2017")
capm_nw(M["2021-01/"], "POST-2021")
capm_nw(M[paste0(as.Date(end(M)) - 365 * 3 + 1, "/")], "RECENT-36M")

cat("\n==== rank-IC ====\n")
ic[, Signal_Date := as.Date(Signal_Date)]
ic_t <- function(v, label) {
  v <- v[is.finite(v)]
  tt <- mean(v) / sd(v) * sqrt(length(v))
  cat(sprintf("%s | n=%d | mean IC=%+.4f | t=%+.2f | IC>0 %.0f%%\n",
              label, length(v), mean(v), tt, 100 * mean(v > 0)))
}
ic_t(ic$IC, "FULL")
ic_t(ic[Signal_Date >= as.Date("2017-01-01")]$IC, "POST-2017")
ic_t(tail(ic, 36)$IC, "RECENT-36M")
ic_t(tail(ic, 60)$IC, "RECENT-60M")

cat("\n==== 연도별 active (참고) ====\n")
ann <- data.table(date = index(M), p = as.numeric(M$p), b = as.numeric(M$b))
ann[, y := year(date)]
print(ann[, .(act_pp = round(sum(p - b) * 100, 1), bm_pp = round(sum(b) * 100, 1)), by = y])
