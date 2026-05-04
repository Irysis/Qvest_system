#!/usr/bin/env Rscript
# Codex C2 disposition: 5-spec Harvey regression + DSR M=lifecycle full count
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-S20260504_009"
DOCS <- file.path(WT_DIR, "docs")

# Load primary panel (TSMOM) + reference
oos <- fread(file.path(DOCS, "rotation_path_TSMOM.csv"))
oos[, date := as.Date(date)]
ref <- fread("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv")
ref[, date := as.Date(date)]
# kospi_ret from benchmark
bm_dt <- as.data.table(arrow::read_parquet("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/benchmark.parquet"))
if ("Date" %in% names(bm_dt)) bm_dt[, date := as.Date(Date)] else bm_dt[, date := as.Date(date)]
if ("Close" %in% names(bm_dt)) {
  bm_dt[, ym := format(date, "%Y-%m")]
  bm_monthly <- bm_dt[, .(close = tail(Close, 1)), by = ym][order(ym)]
  bm_monthly[, kospi_ret := close / shift(close, 1) - 1]
} else {
  bm_dt[, ym := format(date, "%Y-%m")]
  bm_monthly <- bm_dt[, .(kospi_ret = sum(BM_Ret, na.rm=TRUE)), by = ym][order(ym)]
}
fred <- as.data.table(arrow::read_parquet("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/fred_macro.parquet"))
fred_wide <- dcast(fred, Date ~ Series, value.var = "Value", fun.aggregate = mean)
setnames(fred_wide, "Date", "date")
fred_wide[, ym := format(date, "%Y-%m")]
fred_eom <- fred_wide[, lapply(.SD, function(x) tail(na.omit(x), 1)),
                     by = ym, .SDcols = setdiff(names(fred_wide), c("date","ym"))]
oos[, ym := format(date, "%Y-%m")]
oos <- merge(oos, fred_eom[, .(ym, VIX, US_10Y_Yield, KRW_USD, Copper_Price, BBB_Spread)], by="ym", all.x=TRUE)
oos <- merge(oos, bm_monthly[, .(ym, kospi_ret)], by="ym", all.x=TRUE)

# Newey-West SE function
nw_se <- function(x, lag=6L) {
  x <- na.omit(x); n <- length(x); if (n < 12) return(NA_real_)
  m <- mean(x); e <- x - m
  g0 <- sum(e^2) / n; g <- 0
  for (k in 1:lag) {
    if (k >= n) break
    w <- 1 - k/(lag+1)
    g <- g + 2 * w * sum(e[1:(n-k)] * e[(k+1):n]) / n
  }
  v <- g0 + g
  sqrt(max(v, 1e-12) / n)
}

# 5-spec Harvey regressions:
#   Spec 1: rotation ~ const (direct mean test)
#   Spec 2: rotation ~ STR_1715_AR (single-factor)
#   Spec 3: rotation ~ STR_1715_AR + KOSPI200 (CAPM-like)
#   Spec 4: rotation ~ STR_1715_AR + KOSPI200 + VIX_chg (CAPM + vol)
#   Spec 5: rotation ~ STR_1715_AR + KOSPI200 + VIX_chg + US10Y_chg + KRW_chg + Copper_chg (multi-macro)

# oos already has ret_AR_on_M4 + kospi_ret merged. Compute change features.
oos[, vix_chg := (VIX - shift(VIX, 1)) / shift(VIX, 1)]
oos[, us10y_chg := US_10Y_Yield - shift(US_10Y_Yield, 1)]
oos[, krw_chg := (KRW_USD - shift(KRW_USD, 1)) / shift(KRW_USD, 1)]
oos[, copper_chg := (Copper_Price - shift(Copper_Price, 1)) / shift(Copper_Price, 1)]

# Use ml_realized as rotation_ret
y <- oos$ml_realized
spec_results <- list()

# Spec 1: rotation ~ 1
fit1 <- lm(ml_realized ~ 1, data=oos)
spec_results[["spec_1_const"]] <- list(
  alpha_monthly = round(coef(fit1)[1], 5),
  se_nw = round(nw_se(residuals(fit1), 6), 5),
  t_nw = round(coef(fit1)[1] / nw_se(residuals(fit1), 6), 3),
  t_nw_ann = round(coef(fit1)[1] / nw_se(residuals(fit1), 6) * sqrt(12), 3)
)

# Spec 2: rotation ~ ret_AR_on_M4
fit2 <- lm(ml_realized ~ ret_AR_on_M4, data=oos)
resid2 <- residuals(fit2)
alpha2 <- coef(fit2)[1]
se2 <- nw_se(resid2, 6)
spec_results[["spec_2_str1715_only"]] <- list(
  alpha_monthly = round(alpha2, 5),
  beta_str1715 = round(coef(fit2)[2], 4),
  se_nw = round(se2, 5),
  t_nw = round(alpha2/se2, 3),
  t_nw_ann = round(alpha2/se2 * sqrt(12), 3),
  r_squared = round(summary(fit2)$r.squared, 4)
)

# Spec 3: rotation ~ STR_1715 + KOSPI
fit3 <- lm(ml_realized ~ ret_AR_on_M4 + kospi_ret, data=oos)
resid3 <- residuals(fit3)
alpha3 <- coef(fit3)[1]
se3 <- nw_se(resid3, 6)
spec_results[["spec_3_str1715_kospi"]] <- list(
  alpha_monthly = round(alpha3, 5),
  beta_str1715 = round(coef(fit3)[2], 4),
  beta_kospi = round(coef(fit3)[3], 4),
  se_nw = round(se3, 5),
  t_nw = round(alpha3/se3, 3),
  t_nw_ann = round(alpha3/se3 * sqrt(12), 3),
  r_squared = round(summary(fit3)$r.squared, 4)
)

# Spec 4: rotation ~ STR_1715 + KOSPI + VIX_chg
fit4 <- lm(ml_realized ~ ret_AR_on_M4 + kospi_ret + vix_chg, data=oos)
resid4 <- residuals(fit4)
alpha4 <- coef(fit4)[1]
se4 <- nw_se(resid4, 6)
spec_results[["spec_4_str1715_kospi_vix"]] <- list(
  alpha_monthly = round(alpha4, 5),
  beta_str1715 = round(coef(fit4)[2], 4),
  beta_kospi = round(coef(fit4)[3], 4),
  beta_vix_chg = round(coef(fit4)[4], 4),
  se_nw = round(se4, 5),
  t_nw = round(alpha4/se4, 3),
  t_nw_ann = round(alpha4/se4 * sqrt(12), 3),
  r_squared = round(summary(fit4)$r.squared, 4)
)

# Spec 5: rotation ~ STR_1715 + KOSPI + VIX + US10Y + KRW + Copper
fit5 <- lm(ml_realized ~ ret_AR_on_M4 + kospi_ret + vix_chg + us10y_chg + krw_chg + copper_chg, data=oos)
resid5 <- residuals(fit5)
alpha5 <- coef(fit5)[1]
se5 <- nw_se(resid5, 6)
spec_results[["spec_5_full_macro"]] <- list(
  alpha_monthly = round(alpha5, 5),
  beta_str1715 = round(coef(fit5)[2], 4),
  beta_kospi = round(coef(fit5)[3], 4),
  beta_vix_chg = round(coef(fit5)[4], 4),
  beta_us10y_chg = round(coef(fit5)[5], 4),
  beta_krw_chg = round(coef(fit5)[6], 4),
  beta_copper_chg = round(coef(fit5)[7], 4),
  se_nw = round(se5, 5),
  t_nw = round(alpha5/se5, 3),
  t_nw_ann = round(alpha5/se5 * sqrt(12), 3),
  r_squared = round(summary(fit5)$r.squared, 4)
)

# Count specs passing |t_nw_ann| > 3.0
spec_pass_count <- sum(sapply(spec_results, function(s) abs(s$t_nw_ann) > 3.0))
cat("=== 5-spec Harvey regression results ===\n")
for (sn in names(spec_results)) {
  cat(sprintf("  %s: alpha_m=%.5f t_nw_m=%.3f t_nw_ann=%.3f%s\n",
              sn, spec_results[[sn]]$alpha_monthly,
              spec_results[[sn]]$t_nw, spec_results[[sn]]$t_nw_ann,
              if (abs(spec_results[[sn]]$t_nw_ann) > 3.0) " [PASS]" else " [FAIL]"))
}
cat(sprintf("\n  Specs passing |t_nw_ann| > 3.0: %d / 5\n", spec_pass_count))

# DSR with extended M (lifecycle full count)
# WT_S20260504_007 (overlay variants 4) + WT_S20260504_008 (7 candidates) +
# WT_S20260504_009 (6 methods × 3 sub-periods = 18) = 4 + 7 + 18 = 29 trials
# Conservative: M = 30 (round up + research overhead)
M_conservative <- 30
dsr_calc <- function(returns, n_trials) {
  r <- na.omit(returns); n <- length(r); if (n < 12) return(NA_real_)
  sr <- mean(r) / sd(r)
  m3 <- mean((r - mean(r))^3); m4 <- mean((r - mean(r))^4); s <- sd(r)
  skew <- m3 / s^3; kurt <- m4 / s^4
  sr0 <- (sqrt(2*log(n_trials)) - (log(log(n_trials)) + log(4*pi))/(2*sqrt(2*log(n_trials)))) / sqrt(n)
  num <- (sr - sr0) * sqrt(n - 1)
  den <- sqrt(1 - skew * sr + (kurt - 1)/4 * sr^2)
  z <- num / den
  pnorm(z)
}

oos[, ml_realized_net := ml_realized - 0.5/12/100]
dsr_M8 <- dsr_calc(oos$ml_realized_net, 8)
dsr_M30 <- dsr_calc(oos$ml_realized_net, 30)
dsr_M50 <- dsr_calc(oos$ml_realized_net, 50)
cat(sprintf("\nDSR sensitivity to M:\n"))
cat(sprintf("  M=8 (alpha-package internal):  p = %.4f  PASS@0.95=%s\n", dsr_M8, dsr_M8 > 0.95))
cat(sprintf("  M=30 (lifecycle 3-WT total):    p = %.4f  PASS@0.95=%s\n", dsr_M30, dsr_M30 > 0.95))
cat(sprintf("  M=50 (conservative upper):     p = %.4f  PASS@0.95=%s\n", dsr_M50, dsr_M50 > 0.95))

# Save
write_json(list(
  five_spec_harvey = spec_results,
  spec_pass_count = spec_pass_count,
  dsr_sensitivity = list(
    M_8 = round(dsr_M8, 4),
    M_30 = round(dsr_M30, 4),
    M_50 = round(dsr_M50, 4),
    pass_at_M_8 = dsr_M8 > 0.95,
    pass_at_M_30 = dsr_M30 > 0.95,
    pass_at_M_50 = dsr_M50 > 0.95,
    interpretation = "M=8 baseline. M=30 lifecycle accounting for WT-007/008/009 trial count. M=50 conservative upper bound. DSR strict pass requires p > 0.95 at lifecycle M_30."
  ),
  notes = "5-spec Harvey regression directly addresses Codex C2. spec_5_full_macro is the strictest (largest control set) — its t_nw_ann is the truest residual alpha t."
), file.path(DOCS, "harvey_5spec_dsr_sensitivity.json"), pretty=TRUE, auto_unbox=TRUE)

cat("\n=== DONE — saved harvey_5spec_dsr_sensitivity.json ===\n")
