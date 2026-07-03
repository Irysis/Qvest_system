# Diagnostic recomputation — CAPM residual alpha pre/post-2017 + recent windows + rank-IC 36m
# metric_type: diagnostic (회귀 진단 — 성과 자체합성 아님. 게이트 권위값은 authoritative_remeasure.json)
suppressMessages({library(data.table); library(sandwich); library(lmtest)})
d <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260613_075608_251961"
pr <- fread(file.path(d, "03_period_returns.csv"))
br <- fread(file.path(d, "05_benchmark_returns.csv"))
m <- merge(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], by = "date")
setorder(m, date)
m <- m[is.finite(ret_net) & is.finite(benchmark_ret)]
af <- 252
n <- nrow(m)
cat("n =", n, " range:", as.character(min(m$date)), "->", as.character(max(m$date)), "\n\n")

sr <- function(x) if (length(x) > 1 && sd(x) > 0) mean(x)/sd(x)*sqrt(af) else NA_real_

capm <- function(from, to, label) {
  s <- m[date >= as.Date(from) & date <= as.Date(to)]
  if (nrow(s) < 60) { cat(label, ": insufficient n\n"); return(invisible(NULL)) }
  fit <- lm(ret_net ~ benchmark_ret, data = s)
  ct <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  a_d <- ct[1, 1]; t_a <- ct[1, 3]; beta <- ct[2, 1]
  act <- s$ret_net - s$benchmark_ret
  cat(sprintf("%-18s n=%4d | beta %5.3f | resid_alpha %6.2f%%/yr (NW t=%5.2f) | raw_active %6.2f%%/yr | aSR %6.3f | BM_ann %6.1f%%\n",
      label, nrow(s), beta, a_d*af*100, t_a, mean(act)*af*100, sr(act),
      mean(s$benchmark_ret)*af*100))
}

cat("CAPM (daily, NW lag-3) vs KOSPI200:\n")
capm("2005-02-03", "2026-06-11", "FULL")
capm("2005-02-03", "2016-12-31", "pre-2017")
capm("2017-01-01", "2026-06-11", "post-2017")
capm("2017-01-01", "2019-12-31", "2017-2019")
capm("2020-01-01", "2022-12-31", "2020-2022")
capm("2023-01-01", "2026-06-11", "2023-2026")
capm("2023-06-12", "2026-06-11", "last 36m")
capm("2024-06-12", "2026-06-11", "last 24m")
capm("2025-06-12", "2026-06-11", "last 12m")

# essence v2 anchored 3-split replication (active SR retention)
a <- m$ret_net - m$benchmark_ret
cat("\nessence v2 anchored splits (active SR):\n")
rets <- c()
for (fr in c(0.55, 0.65, 0.75)) {
  k <- floor(n * fr)
  isr <- sr(a[1:k]); osr <- sr(a[(k+1):n])
  rt <- if (is.finite(isr) && isr > 0.05) osr/isr else NA_real_
  rets <- c(rets, rt)
  cat(sprintf("split %.2f | IS end %s | IS aSR %.3f | OOS aSR %.3f | retention %.3f\n",
      fr, as.character(m$date[k]), isr, osr, rt))
}
cat(sprintf("median retention = %.3f\n", median(rets, na.rm = TRUE)))

# rank-IC recent windows from analysis_ic.csv
ic <- fread(file.path(d, "analysis_ic.csv"))
setorder(ic, Signal_Date)
ic_t <- function(x) mean(x)/sd(x)*sqrt(length(x))
w <- function(k, label) {
  x <- tail(ic$IC, k)
  cat(sprintf("%-12s n=%3d | IC mean %7.4f | t=%5.2f | pos_rate %4.1f%%\n",
      label, length(x), mean(x), ic_t(x), 100*mean(x > 0)))
}
cat("\nrank-IC windows (monthly, analysis_ic.csv):\n")
w(nrow(ic), "full")
post17 <- ic[Signal_Date >= as.Date("2017-01-01")]$IC
cat(sprintf("%-12s n=%3d | IC mean %7.4f | t=%5.2f | pos_rate %4.1f%%\n",
    "post-2017", length(post17), mean(post17), ic_t(post17), 100*mean(post17 > 0)))
w(36, "last 36m")
w(24, "last 24m")
w(12, "last 12m")
