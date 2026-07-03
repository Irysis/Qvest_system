# 진단: AdjILLIQ 잔차알파 pre/post-2017 분해 + 최근 36m 신호 생존
# 표준함수만: xts / PerformanceAnalytics::apply.monthly / lm / sandwich::NeweyWest
# 성과 자체합성 없음 — 회귀 진단 전용 (어제 선례 diag_oos_dd.R 패턴)
suppressMessages({ library(xts); library(PerformanceAnalytics); library(data.table) })
has_sw <- requireNamespace("sandwich", quietly = TRUE) && requireNamespace("lmtest", quietly = TRUE)

art <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260612_124658_77279"
bt  <- readRDS(file.path(art, "bt_result.rds"))

pr <- bt$period_returns; bm <- bt$benchmark_returns
stopifnot(identical(pr$date, bm$date))
strat_d <- xts(pr$ret_net, order.by = pr$date)
bm_d    <- xts(bm$benchmark_ret, order.by = bm$date)

# 월간 집계 (PerformanceAnalytics 표준)
strat_m <- apply.monthly(strat_d, Return.cumulative)
bm_m    <- apply.monthly(bm_d,    Return.cumulative)
m <- merge(strat_m, bm_m); colnames(m) <- c("strat","bm")

capm <- function(z, label) {
  if (nrow(z) < 12) { cat(sprintf("%-22s n=%d (insufficient)\n", label, nrow(z))); return(invisible(NULL)) }
  fit <- lm(strat ~ bm, data = as.data.frame(z))
  a_m <- coef(fit)[1]; b <- coef(fit)[2]
  if (has_sw) {
    tt <- lmtest::coeftest(fit, vcov = sandwich::NeweyWest(fit, lag = 3, prewhite = FALSE))
    a_t <- tt[1,3]
  } else a_t <- summary(fit)$coefficients[1,3]
  raw_act_ann <- mean(z$strat - z$bm) * 12
  bm_ann <- mean(z$bm) * 12
  cat(sprintf("%-22s n=%3d | beta %.3f | CAPM alpha %+6.2f%%/yr (NWt %+5.2f) | raw active %+6.2f%%/yr | BM %+6.2f%%/yr | beta-drag %+6.2f%%/yr\n",
      label, nrow(z), b, a_m*12*100, a_t, raw_act_ann*100, bm_ann*100, (b-1)*bm_ann*100))
}

cat("== CAPM residual alpha decomposition (monthly, NW lag-3) ==\n")
capm(m, "FULL 2005-2026")
capm(m["/2016-12"], "PRE-2017")
capm(m["2017-01/"], "POST-2017")
capm(m["2020-01/"], "POST-2020")
capm(tail(m, 36),  "RECENT 36m")
capm(m["2025-01/"], "2025-26 meltup")

# rank-IC 최근 구간
ic <- fread(file.path(art, "analysis_ic.csv"))
icw <- function(x, label) {
  tval <- mean(x)/sd(x)*sqrt(length(x))
  cat(sprintf("%-18s n=%d  mean IC %+0.4f  t %+0.2f  IC>0 %.0f%%\n", label, length(x), mean(x), tval, mean(x>0)*100))
}
cat("\n== rank-IC ==\n")
icw(ic$IC, "FULL")
icw(ic[Signal_Date <  as.Date("2017-01-01")]$IC, "PRE-2017")
icw(ic[Signal_Date >= as.Date("2017-01-01")]$IC, "POST-2017")
icw(tail(ic$IC, 36), "RECENT 36m")

# FM lambda 최근 구간
fmb <- fread(file.path(art, "analysis_fmb.csv"))
lw <- function(x, label) {
  tval <- mean(x)/sd(x)*sqrt(length(x))
  cat(sprintf("%-18s n=%d  mean lambda %+0.4f  t %+0.2f\n", label, length(x), mean(x), tval))
}
cat("\n== FM lambda (Score) ==\n")
lw(fmb$Lambda_Score, "FULL")
lw(fmb[Signal_Date <  as.Date("2017-01-01")]$Lambda_Score, "PRE-2017")
lw(fmb[Signal_Date >= as.Date("2017-01-01")]$Lambda_Score, "POST-2017")
lw(tail(fmb$Lambda_Score, 36), "RECENT 36m")

# 활성수익 SR pre/post (참고 — FMT-07 재현)
act <- m$strat - m$bm
sr_ann <- function(z) mean(z)/sd(z)*sqrt(12)
cat(sprintf("\nactive SR: pre-2017 %.2f | post-2017 %.2f | recent36m %.2f\n",
    sr_ann(act["/2016-12"]), sr_ann(act["2017-01/"]), sr_ann(tail(act,36))))
cat(sprintf("strat ann vol pre %.1f%% post %.1f%%\n",
    sd(m$strat["/2016-12"])*sqrt(12)*100, sd(m$strat["2017-01/"])*sqrt(12)*100))
cat(sprintf("NW available: %s\n", has_sw))
