# Diagnostic — Piotroski F-Score (STR_AS_20260612_132740_321995) QEPM 차용 심사
# metric_type: diagnostic (잔차 회귀 / rank-IC / FM lambda 진단 — 성과 합성 아님, 게이트 권위값은 authoritative_remeasure.json)
# 선례: stage_artifacts/alpha_search/20260613_010409_210011/diag_oos_dd.R
suppressMessages({library(data.table); library(sandwich); library(lmtest)})
d <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260612_132740_321995"
b <- readRDS(file.path(d, "bt_result.rds"))
m <- merge(b$period_returns[, .(date, ret_net)],
           b$benchmark_returns[, .(date, benchmark_ret)], by = "date")
setorder(m, date)
m <- m[is.finite(ret_net) & is.finite(benchmark_ret)]
af <- 252
sr <- function(x) if (length(x) > 1 && sd(x) > 0) mean(x)/sd(x)*sqrt(af) else NA_real_
m[, act := ret_net - benchmark_ret]
cat("n =", nrow(m), " range:", as.character(range(m$date)), "\n\n")

# --- segment: beta + CAPM residual alpha (NW lag-3 t) ---
seg <- function(from, to, label) {
  s <- m[date >= as.Date(from) & date <= as.Date(to)]
  fit <- lm(ret_net ~ benchmark_ret, data = s)
  ct <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  a_d <- ct[1, "Estimate"]; a_t <- ct[1, "t value"]
  beta <- coef(fit)[2]
  cat(sprintf("%-24s n=%4d | beta %5.3f | resid_alpha %6.2f%%/yr (NW t=%6.2f) | aSR %6.3f | ann_act %6.1f%% | BM ann %6.1f%%\n",
      label, nrow(s), beta, a_d*af*100, a_t, sr(s$act), mean(s$act)*af*100, mean(s$benchmark_ret)*af*100))
}
cat("CAPM residual alpha by segment (daily, NW lag-3):\n")
seg("2005-02-03", "2016-12-31", "pre-2017")
seg("2017-01-01", "2026-06-11", "post-2017")
seg("2017-01-01", "2019-12-31", "2017-2019")
seg("2020-01-01", "2022-12-31", "2020-2022")
seg("2023-01-01", "2026-06-11", "2023-2026")
seg("2023-06-12", "2026-06-11", "recent 3y")
seg("2024-06-12", "2026-06-11", "recent 2y")
seg("2025-06-12", "2026-06-11", "recent 1y")

# --- trailing PORT_t (intercept-only on raw active, NW lag-3) ---
for (yrs in c(3, 5)) {
  tw <- m[date >= max(date) - yrs*365.25]
  fit <- lm(act ~ 1, data = tw)
  tt <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE))
  cat(sprintf("\nTrailing %dy raw-active PORT_t (NW lag-3): t = %.3f (ann_act %.1f%%)", yrs,
      tt[1, "t value"], mean(tw$act)*af*100))
}

# --- yearly active + beta ---
m[, yr := year(date)]
ya <- m[, .(ann_act = round(mean(act)*af*100, 1),
            beta = round(cov(ret_net, benchmark_ret)/var(benchmark_ret), 2),
            bm_ann = round(mean(benchmark_ret)*af*100, 1)), by = yr]
cat("\n\nYearly active vs KOSPI200 + beta:\n"); print(ya)

# --- rank-IC: full vs recent 36m (analysis_ic.csv 실측 사용) ---
ic <- fread(file.path(d, "analysis_ic.csv"))
icv <- ic$IC[is.finite(ic$IC)]
t36 <- tail(icv, 36); t60 <- tail(icv, 60)
ict <- function(x) mean(x)/sd(x)*sqrt(length(x))
cat(sprintf("\nrank-IC full  n=%d: mean %.4f (t=%.2f) | pos %.0f%%\n", length(icv), mean(icv), ict(icv), mean(icv>0)*100))
cat(sprintf("rank-IC 60m  : mean %.4f (t=%.2f) | pos %.0f%%\n", mean(t60), ict(t60), mean(t60>0)*100))
cat(sprintf("rank-IC 36m  : mean %.4f (t=%.2f) | pos %.0f%% | last sig %s\n", mean(t36), ict(t36), mean(t36>0)*100,
    as.character(tail(ic$Signal_Date, 1))))

# --- FM lambda: full vs recent 36m (NW lag-3 on monthly lambda series) ---
fm <- fread(file.path(d, "analysis_fmb.csv"))
lam <- fm$Lambda_Score[is.finite(fm$Lambda_Score)]
nwt <- function(x) { f <- lm(x ~ 1); coeftest(f, vcov. = NeweyWest(f, lag = 3, prewhite = FALSE))[1, "t value"] }
cat(sprintf("\nFM lambda_Score full n=%d: mean %.5f (NW t=%.2f)\n", length(lam), mean(lam), nwt(lam)))
l36 <- tail(lam, 36); l60 <- tail(lam, 60)
cat(sprintf("FM lambda_Score 60m: mean %.5f (NW t=%.2f)\n", mean(l60), nwt(l60)))
cat(sprintf("FM lambda_Score 36m: mean %.5f (NW t=%.2f)\n", mean(l36), nwt(l36)))

# --- overlap vs SUE+EPS revision (20260612_161342_1312338) ---
d2 <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260612_161342_1312338"
f2 <- file.path(d2, "bt_result.rds")
if (file.exists(f2)) {
  b2 <- readRDS(f2)
  m2 <- merge(m, b2$period_returns[, .(date, ret2 = ret_net)], by = "date")
  m2 <- merge(m2, b2$benchmark_returns[, .(date, bm2 = benchmark_ret)], by = "date")
  r1res <- residuals(lm(ret_net ~ benchmark_ret, data = m2))
  r2res <- residuals(lm(ret2 ~ bm2, data = m2))
  cat(sprintf("\nvs SUE+EPSrev(1312338): n=%d | ret cor %.3f | resid(beta-hedged) cor %.3f | act cor %.3f\n",
      nrow(m2), cor(m2$ret_net, m2$ret2), cor(r1res, r2res),
      cor(m2$ret_net - m2$benchmark_ret, m2$ret2 - m2$bm2)))
} else cat("\nSUE bt_result.rds not found at", f2, "\n")
