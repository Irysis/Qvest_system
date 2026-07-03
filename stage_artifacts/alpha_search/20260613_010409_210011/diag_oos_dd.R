# Diagnostic recomputation — essence_score.R oos_retention v2 replication + segment analysis
# metric_type: diagnostic (essence v2 동일 산식 재현, 게이트 권위값은 authoritative_remeasure.json)
suppressMessages(library(data.table))
d <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260613_010409_210011"
pr <- fread(file.path(d, "03_period_returns.csv"))
br <- fread(file.path(d, "05_benchmark_returns.csv"))
m <- merge(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], by = "date")
setorder(m, date)
a <- m$ret_net - m$benchmark_ret
a <- a[is.finite(a)]
n <- length(a)
af <- 252
sr <- function(x) if (length(x) > 1 && sd(x) > 0) mean(x)/sd(x)*sqrt(af) else NA_real_

cat("n =", n, " date range:", as.character(min(m$date)), "to", as.character(max(m$date)), "\n\n")

# --- essence v2 anchored 3-split replication ---
for (fr in c(0.55, 0.65, 0.75)) {
  k <- floor(n * fr)
  ia <- a[1:k]; oa <- a[(k+1):n]
  cat(sprintf("split %.2f | IS end %s | IS aSR %.3f | OOS aSR %.3f | retention %.3f\n",
      fr, as.character(m$date[k]), sr(ia), sr(oa),
      if (sr(ia) > 0.05) sr(oa)/sr(ia) else NA_real_))
}

# --- total-return Sharpe same splits (참고: hurdle D062는 total SR 기반) ---
r <- m$ret_net
srT <- function(x) mean(x)/sd(x)*sqrt(af)
cat("\nTotal-return SR splits:\n")
for (fr in c(0.55, 0.65, 0.75)) {
  k <- floor(n*fr)
  cat(sprintf("split %.2f | IS SR %.3f | OOS SR %.3f | ret %.3f\n",
      fr, srT(r[1:k]), srT(r[(k+1):n]), srT(r[(k+1):n])/srT(r[1:k])))
}

# --- calendar segments: active SR + total SR + ann active mean ---
seg <- function(from, to, label) {
  idx <- m$date >= as.Date(from) & m$date <= as.Date(to)
  x <- a[idx]; y <- r[idx]; b <- m$benchmark_ret[idx]
  cat(sprintf("%-22s n=%4d | aSR %6.3f | ann_active %6.1f%% | SR %6.3f | BM SR %6.3f | beta %5.2f\n",
      label, sum(idx), sr(x), mean(x)*af*100, sr(y), sr(b),
      cov(y, b)/var(b)))
}
cat("\nCalendar segments (active = vs KOSPI200, daily):\n")
seg("2005-02-03", "2011-12-31", "2005-2011")
seg("2012-01-01", "2016-12-31", "2012-2016")
seg("2005-02-03", "2016-12-31", "pre-2017 full")
seg("2017-01-01", "2026-06-11", "post-2017 full")
seg("2017-01-01", "2019-12-31", "2017-2019")
seg("2020-01-01", "2022-12-31", "2020-2022")
seg("2023-01-01", "2026-06-11", "2023-2026 (recent 3.5y)")
seg("2023-06-13", "2026-06-11", "recent 3y")
seg("2025-06-13", "2026-06-11", "recent 1y")

# --- yearly active return ---
m[, yr := year(date)]
m[, act := ret_net - benchmark_ret]
ya <- m[, .(ann_active_pct = round(mean(act)*252*100, 1),
            aSR = round(mean(act)/sd(act)*sqrt(252), 2)), by = yr]
cat("\nYearly active (vs KOSPI200):\n")
print(ya)

# --- trailing PORT_t (NW lag-3) for band escalation evidence #1: last 3y active ---
suppressMessages(library(sandwich)); suppressMessages(library(lmtest))
tw <- m[date >= as.Date("2023-06-13")]
fit <- lm(act ~ 1, data = tw)
tt <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
cat(sprintf("\nTrailing 3y PORT_t (NW lag-3, intercept-only on active): t = %.3f (p=%.3f)\n",
    tt[1, "t value"], tt[1, "Pr(>|t|)"]))
tw5 <- m[date >= as.Date("2021-06-13")]
fit5 <- lm(act ~ 1, data = tw5)
tt5 <- coeftest(fit5, vcov. = NeweyWest(fit5, lag = 3, prewhite = FALSE))
cat(sprintf("Trailing 5y PORT_t (NW lag-3): t = %.3f (p=%.3f)\n",
    tt5[1, "t value"], tt5[1, "Pr(>|t|)"]))

# --- beta-hedged residual segments (diagnostic: overlay/optimizer 압축 가능성 판단) ---
beta_full <- cov(r, m$benchmark_ret)/var(m$benchmark_ret)
resid <- r - beta_full * m$benchmark_ret
m[, res := resid]
cat(sprintf("\nFull beta = %.3f | residual(beta-hedged) ann SR by segment:\n", beta_full))
for (p in list(c("2005-02-03","2016-12-31","pre-2017"),
               c("2017-01-01","2026-06-11","post-2017"),
               c("2023-06-13","2026-06-11","recent 3y"))) {
  idx <- m$date >= as.Date(p[1]) & m$date <= as.Date(p[2])
  x <- m$res[idx]
  cat(sprintf("%-12s residSR %6.3f | ann resid %6.1f%%\n", p[3], sr(x), mean(x)*af*100))
}
