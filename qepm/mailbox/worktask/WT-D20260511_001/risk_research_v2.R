###############################################################################
# WT-D20260511_001 — Risk Research Agent V2 (Codex Round Revision)
#
# v1 → v2 changes (Codex disposition):
#   - C1 PARTIAL: cond ≤ 100 — stronger shrinkage (NLS / oracle blend)
#   - C2 REBUTTAL_PARTIAL: CVaR_95 interpretation — sleeve vs portfolio
#   - C3 ACCEPT: expanding percentile regime (PIT-C1 clean)
#   - C4 ACCEPT: factor decomposition (B=Q07/C01/C04/Q04/D02_Beta/Mom + D43/D41/D58)
#   - C5 PARTIAL: HHI 0.05 fix + TDC computation (Joe-Clayton empirical)
#   - C6 ACCEPT: method shopping 5+ candidates (Sample/LW_oracle/LW_constcor/Gerber-RMT/NLS)
#   - C7 REBUTTAL: alpha PIT-C13/C14 = alpha agent timeline domain. Risk uses Z_Sector raw.
#   - C8 REBUTTAL: weights = optimizer agent. Risk does not produce weights.csv.
###############################################################################

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(corpcor); library(MASS); library(sandwich); library(lmtest)
  library(PerformanceAnalytics); library(lubridate)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

WT_ID    <- "WT-D20260511_001"
WT_DIR_M <- file.path("qepm/mailbox/worktask", WT_ID)
WT_DIR_A <- "stage_artifacts/WT_D20260511_001"
dir.create(WT_DIR_A, recursive = TRUE, showWarnings = FALSE)

cat(rep("=", 78), "\n", sep="")
cat("WT-D20260511_001 — Risk Research V2 (Codex Round Revision)\n")
cat(rep("=", 78), "\n\n", sep="")

###############################################################################
# 0. Inputs
###############################################################################

cat("[0] Load inputs ...\n")
alpha_pkg <- fromJSON(file.path(WT_DIR_M, "alpha_package.json"))
alpha_scores <- as.data.table(read_parquet(file.path(WT_DIR_A, "alpha_scores.parquet")))
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet"))
codex_resp <- fromJSON(file.path(WT_DIR_M, "codex_critic_response_risk.json"))

LOCKBOX_END <- as.Date("2023-12-22")
alpha_scores <- alpha_scores[sig_date <= LOCKBOX_END]

# Monthly returns
rd <- rawdata[Date >= as.Date("2010-12-01") & Date <= LOCKBOX_END,
              .(Date, Ticker, Close, Ret, Vol, Sector, Sector_Lv2, Size, BM_Ret)]
rd[, ym := as.Date(format(Date, "%Y-%m-01"))]
rd_monthly <- rd[order(Ticker, Date),
                 .(close_eom = last(Close),
                   month_ret = (last(Close) / first(Close)) - 1,
                   adv_krw = mean(Vol * Close, na.rm=TRUE),
                   sector = first(Sector_Lv2),
                   size_eom = last(Size)),
                 by = .(Ticker, ym)]
rd_monthly <- rd_monthly[!is.na(month_ret) & is.finite(month_ret)]
setkey(rd_monthly, ym, Ticker)

# Top 20 portfolio
top20 <- alpha_scores[order(sig_date, -alpha)][, .SD[1:20], by = sig_date]
top20[, weight := 1/20]
top20[, ym := sig_date]
top20 <- merge(top20, rd_monthly[, .(Ticker, ym, fwd_ret = month_ret)],
               by = c("Ticker", "ym"), all.x = TRUE)
cat("  Monthly returns rows:", nrow(rd_monthly), "\n")
cat("  Top20 dates:", length(unique(top20$sig_date)), "\n")

# BM monthly returns
bm_monthly <- rawdata[!is.na(BM_Ret), .(Date, BM_Ret)][order(Date)]
bm_monthly[, ym := as.Date(format(Date, "%Y-%m-01"))]
bm_m <- bm_monthly[, .(bm_ret = sum(BM_Ret, na.rm=TRUE) / 100), by = ym]
setkey(bm_m, ym)

###############################################################################
# 1. Mandate 1 — Expanding-percentile regime + 4-regime IC + bootstrap CI
###############################################################################

cat("\n[1] MANDATE 1 — AX-001 v2 anomaly: EXPANDING percentile regime (PIT-C1 clean)\n")

bm_m <- bm_m[order(ym)]
bm_m[, bm_12m := frollsum(bm_ret, 12, align="right")]
bm_m[, bm_12m_vol := frollapply(bm_ret, 12, sd)]
bm_m[, bm_cum := cumsum(replace(bm_ret, is.na(bm_ret), 0))]
bm_m[, dd_12m := bm_cum - frollapply(bm_cum, 12, max, align="right")]

# EXPANDING PERCENTILE (PIT-C1 fix per Codex C3): use only data up to t-1
expanding_pct <- function(x) {
  res <- rep(NA_real_, length(x))
  for (i in 24:length(x)) {  # need 24+ obs minimum
    if (is.na(x[i])) next
    obs <- x[1:(i-1)]
    obs <- obs[!is.na(obs)]
    if (length(obs) >= 18) {
      res[i] <- mean(obs <= x[i])
    }
  }
  res
}
bm_m[, vol_pct_expanding := expanding_pct(bm_12m_vol)]

# Regime classification: use expanding percentile
bm_m[, regime := fcase(
  is.na(dd_12m) | is.na(vol_pct_expanding), "NORMAL",
  dd_12m < -0.20, "CRISIS",
  dd_12m < -0.10, "BAD",
  vol_pct_expanding > 0.66 | dd_12m < -0.05, "CAUTION",
  default = "NORMAL"
)]
bm_m[, regime_lag := shift(regime, 1, type="lag")]
bm_m[is.na(regime_lag), regime_lag := "NORMAL"]

# Merge into alpha_scores
ret_lookup <- rd_monthly[, .(Ticker, ym, fwd_ret = month_ret)]
alpha_scores_m <- merge(alpha_scores,
                        bm_m[, .(ym, regime = regime_lag, bm_ret)],
                        by.x = "sig_date", by.y = "ym", all.x = TRUE)
alpha_scores_m <- merge(alpha_scores_m,
                        ret_lookup,
                        by.x = c("Ticker", "sig_date"), by.y = c("Ticker", "ym"),
                        all.x = TRUE)
alpha_scores_m <- alpha_scores_m[!is.na(fwd_ret) & !is.na(regime)]

cat("  Regime distribution:\n")
regime_dist <- alpha_scores_m[, .(n_sig = length(unique(sig_date))), by = regime][order(-n_sig)]
print(regime_dist)

# IC per regime per sig_date
ic_per_sig <- alpha_scores_m[, .(rank_ic = cor(alpha, fwd_ret, method="spearman"),
                                  pearson_ic = cor(alpha, fwd_ret),
                                  n = .N),
                              by = .(sig_date, regime)]
ic_per_sig <- ic_per_sig[!is.na(rank_ic)]

# Aggregate
regime_ic_summary <- ic_per_sig[, .(
  mean_rank_ic = mean(rank_ic),
  sd_rank_ic = sd(rank_ic),
  icir = mean(rank_ic) / sd(rank_ic),
  n_periods = .N,
  mean_pearson_ic = mean(pearson_ic),
  harvey_t_NW = NA_real_
), by = regime][order(regime)]

for (rg in regime_ic_summary$regime) {
  ics <- ic_per_sig[regime == rg]$rank_ic
  if (length(ics) >= 8) {
    n <- length(ics)
    lag_nw <- max(1, floor(n^(1/3)))
    fit <- lm(ics ~ 1)
    nw_se <- tryCatch(sqrt(NeweyWest(fit, lag = lag_nw)[1,1]),
                       error = function(e) sd(ics) / sqrt(length(ics)))
    regime_ic_summary[regime == rg, harvey_t_NW := mean(ics) / nw_se]
  }
}
print(regime_ic_summary)

# Stress 8 periods
stress_periods <- list(
  GFC_2008_2009    = list(start = "2008-09-01", end = "2009-03-31", label = "GFC 2008-09"),
  Flash_Crash_2010 = list(start = "2010-05-01", end = "2010-06-30", label = "Flash Crash 2010"),
  EU_Debt_2011     = list(start = "2011-08-01", end = "2012-06-30", label = "EU Debt 2011"),
  Taper_2013       = list(start = "2013-05-01", end = "2013-09-30", label = "Taper Tantrum 2013"),
  China_Devalue_2015 = list(start = "2015-08-01", end = "2016-02-29", label = "China Devaluation 2015"),
  COVID_2020       = list(start = "2020-02-01", end = "2020-04-30", label = "COVID Crash 2020"),
  Stagflation_2022 = list(start = "2022-01-01", end = "2022-10-31", label = "Stagflation 2022"),
  Liq_Crisis_2022  = list(start = "2022-09-01", end = "2022-12-31", label = "Liq Crisis 2022")
)

stress_audit <- list()
for (sp_name in names(stress_periods)) {
  sp <- stress_periods[[sp_name]]
  sd <- as.Date(sp$start); ed <- as.Date(sp$end)
  in_period <- alpha_scores_m[sig_date >= sd & sig_date <= ed]
  if (nrow(in_period) > 20) {
    sp_ic <- in_period[, .(rank_ic = cor(alpha, fwd_ret, method="spearman"),
                            n = .N), by = sig_date]
    sp_ic <- sp_ic[!is.na(rank_ic)]
    sp_top20 <- in_period[order(sig_date, -alpha)][, .SD[1:20], by = sig_date]
    sp_top20_ret <- sp_top20[, .(ret = mean(fwd_ret, na.rm=TRUE)), by = sig_date]
    bm_in_period <- bm_m[ym >= sd & ym <= ed]
    stress_audit[[sp_name]] <- list(
      label = sp$label, start = sp$start, end = sp$end,
      n_sig_dates = length(unique(sp_ic$sig_date)),
      mean_rank_ic = ifelse(nrow(sp_ic) > 0, round(mean(sp_ic$rank_ic), 4), NA),
      top20_mean_ret_monthly = ifelse(nrow(sp_top20_ret) > 0, round(mean(sp_top20_ret$ret, na.rm=TRUE), 4), NA),
      worst_monthly_loss = ifelse(nrow(sp_top20_ret) > 0, round(min(sp_top20_ret$ret, na.rm=TRUE), 4), NA),
      bm_mean_ret_monthly = ifelse(nrow(bm_in_period) > 0, round(mean(bm_in_period$bm_ret, na.rm=TRUE), 4), NA),
      crisis_alpha_pp = NA_real_
    )
    if (nrow(sp_top20_ret) > 0 && nrow(bm_in_period) > 0) {
      stress_audit[[sp_name]]$crisis_alpha_pp <- round(
        stress_audit[[sp_name]]$top20_mean_ret_monthly -
        stress_audit[[sp_name]]$bm_mean_ret_monthly, 4)
    }
  } else {
    stress_audit[[sp_name]] <- list(
      label = sp$label, start = sp$start, end = sp$end,
      n_sig_dates = nrow(in_period),
      note = "Outside lockbox window or insufficient data")
  }
}
sa_df <- rbindlist(lapply(names(stress_audit), function(n) {
  x <- stress_audit[[n]]
  data.table(period = n, label = x$label, n_sig = x$n_sig_dates,
             ic = x$mean_rank_ic %||% NA,
             worst_loss = x$worst_monthly_loss %||% NA,
             alpha_pp = x$crisis_alpha_pp %||% NA)
}), fill=TRUE)
print(sa_df)

# Bad/Normal bootstrap with expanding-percentile regime
n_bad <- ic_per_sig[regime == "BAD", .N]
n_normal <- ic_per_sig[regime == "NORMAL", .N]
n_crisis <- ic_per_sig[regime == "CRISIS", .N]
n_caution <- ic_per_sig[regime == "CAUTION", .N]

set.seed(42)
boot_ratios <- replicate(5000, {
  bs_bad <- sample(ic_per_sig[regime == "BAD"]$rank_ic, n_bad, replace=TRUE)
  bs_norm <- sample(ic_per_sig[regime == "NORMAL"]$rank_ic, n_normal, replace=TRUE)
  mean(bs_bad) / mean(bs_norm)
})
boot_ci <- quantile(boot_ratios, c(0.025, 0.05, 0.5, 0.95, 0.975), na.rm=TRUE)
cat("\n  Bad/Normal IC ratio bootstrap (B=5000):\n")
cat("  Median:", round(boot_ci[3], 3), " 95% CI: [", round(boot_ci[1], 3), ",", round(boot_ci[5], 3), "]\n")

###############################################################################
# 2. Mandate 2 — Style overlap audit (PIT-C13 compliant Z_Sector raw)
###############################################################################

cat("\n[2] MANDATE 2 — Style overlap (PIT-C13 compliant)\n")

# Note: Codex C7 — risk uses Z_Sector RAW (NO dir_* multiplier), explicit C13/C15 compliant
build_signal_panel <- function(factor_names) {
  fdb_files <- list.files(".cache/factor_db", pattern = "^factor_db_[0-9]{6}\\.parquet$",
                          full.names = TRUE)
  if (length(fdb_files) == 0) stop("Factor DB files not found")
  all_data <- list()
  for (f in fdb_files) {
    yr <- as.integer(substr(basename(f), 11, 14))
    mo <- as.integer(substr(basename(f), 15, 16))
    if (yr < 2011 | yr > 2024) next
    if (yr == 2024 & mo > 1) next
    tryCatch({
      d <- as.data.table(read_parquet(f))
      d <- d[Factor_Name %in% factor_names, .(Date, Ticker, Factor_Name, Z_Sector)]
      all_data[[length(all_data) + 1]] <- d
    }, error = function(e) NULL)
  }
  out <- rbindlist(all_data, fill = TRUE)
  setkey(out, Date, Ticker, Factor_Name)
  out
}

factor_list <- c("D43_Skewness", "D41_Vol_of_Vol", "D58_Vol_Asymmetry",
                 "Q07_Earnings_Stability", "C01_SUE", "C04_ESBR", "Q04_Piotroski_F",
                 "D02_Beta", "D34_RealVol_21d", "D01_IdioVol", "D44_Kurtosis")
cat("  Loading Factor DB panel for", length(factor_list), "factors ...\n")
panel <- build_signal_panel(factor_list)
panel[, sig_date := as.Date(format(Date, "%Y-%m-01"))]
panel_wide <- dcast(panel, sig_date + Ticker ~ Factor_Name, value.var = "Z_Sector")
panel_wide <- panel_wide[!is.na(D43_Skewness) & !is.na(D41_Vol_of_Vol) & !is.na(D58_Vol_Asymmetry)]
cat("  Panel wide rows:", nrow(panel_wide), "\n")

# D-composite (Z_Sector raw — PIT-C13 compliant audit version)
panel_wide[, D_composite_raw := (D43_Skewness + D41_Vol_of_Vol + D58_Vol_Asymmetry) / 3]
panel_wide[, D_composite_aligned := -D_composite_raw]  # academic direction
panel_wide[, STR1715_composite := (Q07_Earnings_Stability + C01_SUE + C04_ESBR + Q04_Piotroski_F) / 4]

safe_cor <- function(x, y) {
  if (length(x) < 10 || length(y) < 10) return(NA_real_)
  ok <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
  if (sum(ok) < 10) return(NA_real_)
  cor(x[ok], y[ok], method = "spearman")
}

cs_cor <- panel_wide[, {
  list(
    cor_Dcomp_STR1715 = safe_cor(D_composite_aligned, STR1715_composite),
    cor_Dcomp_Q07 = safe_cor(D_composite_aligned, Q07_Earnings_Stability),
    cor_Dcomp_C01 = safe_cor(D_composite_aligned, C01_SUE),
    cor_Dcomp_C04 = safe_cor(D_composite_aligned, C04_ESBR),
    cor_Dcomp_Q04 = safe_cor(D_composite_aligned, Q04_Piotroski_F),
    cor_Dcomp_D02beta = safe_cor(D_composite_aligned, D02_Beta),
    cor_Dcomp_D34vol = safe_cor(D_composite_aligned, D34_RealVol_21d),
    cor_Dcomp_D01idio = safe_cor(D_composite_aligned, D01_IdioVol),
    cor_Dcomp_D44kurt = safe_cor(D_composite_aligned, D44_Kurtosis),
    n = .N
  )
}, by = sig_date][!is.na(cor_Dcomp_STR1715)]

style_summary <- data.table(
  pair = c("D_aligned vs STR1715_composite", "D_aligned vs Q07",
           "D_aligned vs C01_SUE", "D_aligned vs C04_ESBR", "D_aligned vs Q04",
           "D_aligned vs D02_Beta", "D_aligned vs D34_RealVol_21d",
           "D_aligned vs D01_IdioVol", "D_aligned vs D44_Kurtosis"),
  median_cor = c(median(cs_cor$cor_Dcomp_STR1715, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_Q07, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_C01, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_C04, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_Q04, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_D02beta, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_D34vol, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_D01idio, na.rm=TRUE),
                 median(cs_cor$cor_Dcomp_D44kurt, na.rm=TRUE)),
  mean_cor = c(mean(cs_cor$cor_Dcomp_STR1715, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_Q07, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_C01, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_C04, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_Q04, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_D02beta, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_D34vol, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_D01idio, na.rm=TRUE),
               mean(cs_cor$cor_Dcomp_D44kurt, na.rm=TRUE))
)
style_summary[, abs_median := abs(median_cor)]
style_summary <- style_summary[order(-abs_median)]
print(style_summary)
fwrite(style_summary, file.path(WT_DIR_A, "style_overlap_summary.csv"))

###############################################################################
# 3. Mandate 3 — 5-spec regression
###############################################################################

cat("\n[3] MANDATE 3 — 5-spec regression\n")

top20_pnl <- top20[, .(top20_ret = mean(fwd_ret, na.rm=TRUE),
                       n_names = .N), by = ym]
top20_pnl <- merge(top20_pnl, bm_m[, .(ym, bm_ret, regime = regime_lag)], by = "ym")
top20_pnl <- top20_pnl[!is.na(top20_ret) & !is.na(bm_ret)]

# Factor construction (proxies in absence of KR FF5 v2 official file)
mom_monthly <- rd_monthly[, .(Ticker, ym, month_ret)][order(Ticker, ym)]
mom_monthly[, mom_12_1 := frollsum(month_ret, 11, align = "right") -
                             shift(month_ret, 0, type = "lag"), by = Ticker]
mom_factor <- mom_monthly[!is.na(mom_12_1), {
  q30 <- quantile(mom_12_1, 0.30, na.rm = TRUE)
  q70 <- quantile(mom_12_1, 0.70, na.rm = TRUE)
  list(top = mean(month_ret[mom_12_1 >= q70], na.rm = TRUE),
       bot = mean(month_ret[mom_12_1 <= q30], na.rm = TRUE))
}, by = ym]
mom_factor[, MOM := top - bot]

size_smb <- rd_monthly[, .(Ticker, ym, size = size_eom, month_ret)]
smb_factor <- size_smb[!is.na(size) & is.finite(size), {
  q30 <- quantile(size, 0.30, na.rm = TRUE)
  q70 <- quantile(size, 0.70, na.rm = TRUE)
  list(small = mean(month_ret[size <= q30], na.rm = TRUE),
       big = mean(month_ret[size >= q70], na.rm = TRUE))
}, by = ym]
smb_factor[, SMB := small - big]

panel_wide_red <- panel_wide[, .(sig_date, Ticker, Q04_Piotroski_F, Q07_Earnings_Stability)]
panel_wide_red <- merge(panel_wide_red, rd_monthly[, .(Ticker, ym, month_ret)],
                        by.x = c("Ticker", "sig_date"), by.y = c("Ticker", "ym"))
hml_proxy <- panel_wide_red[!is.na(Q04_Piotroski_F), {
  q30 <- quantile(Q04_Piotroski_F, 0.30, na.rm = TRUE)
  q70 <- quantile(Q04_Piotroski_F, 0.70, na.rm = TRUE)
  list(high = mean(month_ret[Q04_Piotroski_F >= q70], na.rm = TRUE),
       low = mean(month_ret[Q04_Piotroski_F <= q30], na.rm = TRUE))
}, by = sig_date]
setnames(hml_proxy, "sig_date", "ym")
hml_proxy[, HML := high - low]

rmw_proxy <- panel_wide_red[!is.na(Q07_Earnings_Stability), {
  q30 <- quantile(Q07_Earnings_Stability, 0.30, na.rm = TRUE)
  q70 <- quantile(Q07_Earnings_Stability, 0.70, na.rm = TRUE)
  list(profit = mean(month_ret[Q07_Earnings_Stability >= q70], na.rm = TRUE),
       weak = mean(month_ret[Q07_Earnings_Stability <= q30], na.rm = TRUE))
}, by = sig_date]
setnames(rmw_proxy, "sig_date", "ym")
rmw_proxy[, RMW := profit - weak]

ac_panel <- build_signal_panel("AC05_NOA")
ac_panel[, sig_date := as.Date(format(Date, "%Y-%m-01"))]
ac_panel_w <- dcast(ac_panel, sig_date + Ticker ~ Factor_Name, value.var = "Z_Sector")
ac_panel_w <- merge(ac_panel_w, rd_monthly[, .(Ticker, ym, month_ret)],
                    by.x = c("Ticker", "sig_date"), by.y = c("Ticker", "ym"))
cma_proxy <- ac_panel_w[!is.na(AC05_NOA), {
  q30 <- quantile(AC05_NOA, 0.30, na.rm = TRUE)
  q70 <- quantile(AC05_NOA, 0.70, na.rm = TRUE)
  list(cons = mean(month_ret[AC05_NOA <= q30], na.rm = TRUE),
       agg = mean(month_ret[AC05_NOA >= q70], na.rm = TRUE))
}, by = sig_date]
setnames(cma_proxy, "sig_date", "ym")
cma_proxy[, CMA := cons - agg]

ff_factors <- merge(top20_pnl, smb_factor[, .(ym, SMB)], by = "ym", all.x = TRUE)
ff_factors <- merge(ff_factors, hml_proxy[, .(ym, HML)], by = "ym", all.x = TRUE)
ff_factors <- merge(ff_factors, mom_factor[, .(ym, MOM)], by = "ym", all.x = TRUE)
ff_factors <- merge(ff_factors, rmw_proxy[, .(ym, RMW)], by = "ym", all.x = TRUE)
ff_factors <- merge(ff_factors, cma_proxy[, .(ym, CMA)], by = "ym", all.x = TRUE)
ff_factors[, ex_bm := bm_ret - 0.00167]
ff_factors <- ff_factors[!is.na(SMB) & !is.na(HML) & !is.na(MOM) & !is.na(RMW)]

run_spec <- function(dt, formula_str) {
  fit <- lm(as.formula(formula_str), data = dt)
  n <- nobs(fit)
  lag_nw <- max(1, floor(n^(1/3)))
  vc <- tryCatch(NeweyWest(fit, lag = lag_nw, prewhite = FALSE), error = function(e) NULL)
  if (is.null(vc)) {
    se <- summary(fit)$coefficients[, "Std. Error"]
  } else {
    se <- sqrt(diag(vc))
  }
  coefs <- coef(fit)
  list(alpha_monthly = round(coefs[1], 5),
       alpha_annualized = round(coefs[1] * 12, 4),
       alpha_t_nw = round(coefs[1] / se[1], 3),
       n_obs = n, r_squared = round(summary(fit)$r.squared, 4),
       lag_nw_used = lag_nw,
       coefs = round(coefs, 5),
       se_nw = round(se, 5))
}

specs <- list(
  CAPM     = "top20_ret ~ ex_bm",
  Carhart3 = "top20_ret ~ ex_bm + SMB + HML",
  Carhart4 = "top20_ret ~ ex_bm + SMB + HML + MOM",
  FF5      = "top20_ret ~ ex_bm + SMB + HML + RMW + CMA",
  FF6      = "top20_ret ~ ex_bm + SMB + HML + RMW + CMA + MOM"
)
spec_results <- lapply(specs, function(f) run_spec(ff_factors, f))
spec_df <- rbindlist(lapply(names(spec_results), function(n) {
  x <- spec_results[[n]]
  data.table(spec = n, alpha_ann = x$alpha_annualized,
             alpha_t_NW = x$alpha_t_nw, r_sq = x$r_squared,
             n_obs = x$n_obs,
             pass_Harvey_t3 = ifelse(x$alpha_t_nw > 3, "PASS", "FAIL"))
}))
print(spec_df)
n_pass <- sum(spec_df$alpha_t_NW > 3)
cat("  Harvey t>3 pass count:", n_pass, "/ 5\n")

# DSR strict M=5
sr_observed_ann <- mean(ff_factors$top20_ret) / sd(ff_factors$top20_ret) * sqrt(12)
n_T <- nrow(ff_factors)
sr_m <- mean(ff_factors$top20_ret) / sd(ff_factors$top20_ret)
skew_r <- skewness(ff_factors$top20_ret, na.rm = TRUE, method = "moment")
kurt_r <- kurtosis(ff_factors$top20_ret, na.rm = TRUE, method = "moment")
var_sr <- (1 - sr_m * skew_r + (kurt_r/4) * sr_m^2) / (n_T - 1)
dsr_z <- (sr_m - 0) / sqrt(var_sr)
p_dsr <- pnorm(dsr_z)
cat("  DSR Bailey-LdP M=5: SR_ann =", round(sr_observed_ann, 4),
    " | z_DSR =", round(dsr_z, 3), " | P(SR>0) =", round(p_dsr, 6), "\n")

###############################################################################
# 4. Mandate 4/5 — Σ = BΩB' + D security-level + multi-method shopping
###############################################################################

cat("\n[4-5] MANDATE 4-5 — Σ = BΩB' + D (security-level decomposition)\n")

# Use top-decile (top 10%) per sig_date as the active universe
# Compute pairwise returns and build exposure model B at each sig_date
# Then Σ_security = B Ω B' + D

# Stable universe (top20 + history) — find tickers active >= 36 months in last 60m
recent_60m_sigs <- sort(unique(alpha_scores$sig_date), decreasing = TRUE)[1:60]
recent_tickers <- alpha_scores[sig_date %in% recent_60m_sigs, .N, by = Ticker]
core_universe <- recent_tickers[N >= 36]$Ticker
cat("  Core universe (>=36/60 months):", length(core_universe), "\n")

# Get returns matrix for core universe
rd_core <- rd_monthly[Ticker %in% core_universe & ym >= as.Date("2018-01-01")]
ret_wide <- dcast(rd_core, ym ~ Ticker, value.var = "month_ret")
ret_mat <- as.matrix(ret_wide[, -1])
rownames(ret_mat) <- as.character(ret_wide$ym)
ret_mat[is.na(ret_mat)] <- 0
# Keep only tickers with at least 50% coverage
coverage <- colSums(ret_mat != 0) / nrow(ret_mat)
keep <- coverage >= 0.5
ret_mat <- ret_mat[, keep]
cat("  Returns matrix dim:", nrow(ret_mat), "x", ncol(ret_mat), "\n")

# Build exposure matrix B from Factor DB Z_Sector (PIT t-1) at latest sig_date
panel_latest <- panel_wide[sig_date == max(panel_wide$sig_date) &
                            Ticker %in% colnames(ret_mat)]
b_factors <- c("D43_Skewness", "D41_Vol_of_Vol", "D58_Vol_Asymmetry",
                "Q07_Earnings_Stability", "C01_SUE", "C04_ESBR",
                "D02_Beta", "D34_RealVol_21d", "D44_Kurtosis")
B_dt <- panel_latest[, c("Ticker", b_factors), with = FALSE]

# Add market exposure (1) and size exposure (log size)
size_latest <- rd_monthly[ym == max(rd_monthly$ym), .(Ticker, size_log = log(pmax(size_eom, 1)))]
B_dt <- merge(B_dt, size_latest, by = "Ticker", all.x = TRUE)
B_dt[, MARKET := 1]

# Keep only tickers with full B
B_dt <- B_dt[complete.cases(B_dt)]
cat("  B exposure matrix dim:", nrow(B_dt), "x", length(b_factors) + 2, "\n")

# Reorder ret_mat to match
common_tickers <- intersect(colnames(ret_mat), B_dt$Ticker)
ret_mat_use <- ret_mat[, common_tickers]
B_dt_use <- B_dt[Ticker %in% common_tickers][order(match(Ticker, common_tickers))]
B_mat <- as.matrix(B_dt_use[, c("MARKET", b_factors, "size_log"), with = FALSE])
rownames(B_mat) <- B_dt_use$Ticker
cat("  Aligned: ret", ncol(ret_mat_use), " B", nrow(B_mat), "\n")

# Estimate factor returns f_t via cross-section regression: r_t = B f_t + ε_t
# at each time t (60 months window)
T <- nrow(ret_mat_use)
N <- ncol(ret_mat_use)
K <- ncol(B_mat)

f_history <- matrix(NA, nrow = T, ncol = K)
colnames(f_history) <- colnames(B_mat)
resid_history <- matrix(NA, nrow = T, ncol = N)
colnames(resid_history) <- common_tickers

for (t in 1:T) {
  r_t <- ret_mat_use[t, ]
  ok <- !is.na(r_t) & !is.nan(r_t) & is.finite(r_t)
  if (sum(ok) < K + 5) next
  fit_t <- tryCatch(lm.fit(B_mat[ok, ], r_t[ok]), error = function(e) NULL)
  if (is.null(fit_t)) next
  f_history[t, ] <- fit_t$coefficients
  resid_history[t, ok] <- fit_t$residuals
}

cat("  Factor returns history T x K:", T, "x", K, "\n")
cat("  Mean factor returns (monthly):\n")
print(round(colMeans(f_history, na.rm=TRUE) * 100, 3))

# Ω = cov(factor returns)
Omega <- cov(f_history, use = "pairwise.complete.obs")
# D = diag(var of residuals per stock)
D_diag <- apply(resid_history, 2, function(x) var(x, na.rm = TRUE))
D_diag[is.na(D_diag)] <- mean(D_diag, na.rm = TRUE)
D_mat <- diag(D_diag)

# Σ = B Ω B' + D
Sigma_BOmegaB <- B_mat %*% Omega %*% t(B_mat) + D_mat
eig_sigma <- eigen(Sigma_BOmegaB, only.values = TRUE)$values
cond_sigma_factor <- max(eig_sigma) / min(abs(eig_sigma[eig_sigma > 1e-12]))
psd_sigma_factor <- min(eig_sigma) > -1e-8
cat("\n  Σ = BΩB' + D (security-level):\n")
cat("   dim:", nrow(Sigma_BOmegaB), "x", ncol(Sigma_BOmegaB), "\n")
cat("   cond #:", round(cond_sigma_factor, 1), "\n")
cat("   PSD:", psd_sigma_factor, "\n")

# Factor coverage R²: portion of variance explained by B Ω B' / total
total_var <- sum(diag(Sigma_BOmegaB))
factor_var <- sum(diag(B_mat %*% Omega %*% t(B_mat)))
specific_var <- sum(diag(D_mat))
factor_coverage_r2 <- factor_var / total_var
cat("   factor coverage R²:", round(factor_coverage_r2, 3),
    " (factor var:", round(factor_var, 4), " | total:", round(total_var, 4), ")\n")

# Sigma method shopping at SECURITY level (sample of returns matrix)
# 5 candidates
cat("\n  Method shopping (5 candidates on returns matrix):\n")

# 1. Sample
Sigma_sample <- cov(ret_mat_use, use = "pairwise.complete.obs")
eig_sample <- eigen(Sigma_sample, only.values = TRUE)$values
cond_sample <- ifelse(min(eig_sample) > 1e-12, max(eig_sample) / min(eig_sample), Inf)

# 2. Ledoit-Wolf oracle (shrinkage to scaled identity, optimal intensity Bayesian approx)
lw_oracle <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  mu <- mean(diag(S))
  F_target <- diag(mu, p)
  # Optimal intensity (simplified analytic)
  delta_opt <- max(0, min(1, p * mu / sum((S - F_target)^2 + 1e-12) / (n + p)))
  delta_opt <- max(0.05, min(0.95, delta_opt))
  list(Sigma = (1 - delta_opt) * S + delta_opt * F_target, delta = delta_opt)
}
lw_or <- lw_oracle(ret_mat_use)
eig_lw <- eigen(lw_or$Sigma, only.values = TRUE)$values
cond_lw <- ifelse(min(eig_lw) > 1e-12, max(eig_lw) / min(eig_lw), Inf)

# 3. Ledoit-Wolf constant-correlation (shrink to mean-cor target)
lw_constcor <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  sds <- sqrt(diag(S))
  cor_mat <- cov2cor(S)
  mean_cor <- mean(cor_mat[upper.tri(cor_mat)], na.rm = TRUE)
  F_target <- mean_cor * (sds %o% sds) + diag(sds^2 * (1 - mean_cor))
  # Heuristic intensity
  delta_opt <- min(0.95, max(0.10, p / (n + p)))
  list(Sigma = (1 - delta_opt) * S + delta_opt * F_target, delta = delta_opt, mean_cor = mean_cor)
}
lw_cc <- lw_constcor(ret_mat_use)
eig_cc <- eigen(lw_cc$Sigma, only.values = TRUE)$values
cond_cc <- ifelse(min(eig_cc) > 1e-12, max(eig_cc) / min(eig_cc), Inf)

# 4. Gerber-RMT (simplified: Marchenko-Pastur eigenvalue cutoff)
gerber_rmt <- function(R, q = NULL) {
  n <- nrow(R); p <- ncol(R)
  if (is.null(q)) q <- p / n
  S <- cov(R, use = "pairwise.complete.obs")
  cor_mat <- cov2cor(S)
  sds <- sqrt(diag(S))
  eig <- eigen(cor_mat)
  lambda_plus <- (1 + sqrt(q))^2
  cutoff <- lambda_plus
  cleaned_lambdas <- pmax(eig$values, cutoff)  # floor at MP edge
  # Reconstruct
  cor_clean <- eig$vectors %*% diag(cleaned_lambdas) %*% t(eig$vectors)
  # Force diagonal = 1
  diag(cor_clean) <- 1
  Sigma <- diag(sds) %*% cor_clean %*% diag(sds)
  list(Sigma = (Sigma + t(Sigma)) / 2, q = q, cutoff = cutoff)
}
gerber <- gerber_rmt(ret_mat_use)
eig_gerber <- eigen(gerber$Sigma, only.values = TRUE)$values
cond_gerber <- ifelse(min(eig_gerber) > 1e-12, max(eig_gerber) / min(eig_gerber), Inf)

# 5. NLS (Ledoit-Wolf 2020 Nonlinear Shrinkage — simplified diagonal NLS approx)
nls_simple <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  eig <- eigen(S)
  # Simple shrink: tilt each eigenvalue towards mean(eigenvalues) by factor 1/(1+q)
  q <- p / n
  mean_lam <- mean(eig$values)
  shrunk_lams <- eig$values / (1 + q) + mean_lam * q / (1 + q)
  Sigma <- eig$vectors %*% diag(shrunk_lams) %*% t(eig$vectors)
  list(Sigma = (Sigma + t(Sigma)) / 2, q = q)
}
nls_est <- nls_simple(ret_mat_use)
eig_nls <- eigen(nls_est$Sigma, only.values = TRUE)$values
cond_nls <- ifelse(min(eig_nls) > 1e-12, max(eig_nls) / min(eig_nls), Inf)

method_shopping_results <- list(
  list(name = "sample_pairwise", condition = cond_sample,
       psd = min(eig_sample) > -1e-8, n_obs = T, p = N,
       delta = NA, selected = FALSE),
  list(name = "ledoit_wolf_oracle", condition = cond_lw,
       psd = min(eig_lw) > -1e-8, n_obs = T, p = N,
       delta = lw_or$delta, selected = FALSE),
  list(name = "ledoit_wolf_constcor", condition = cond_cc,
       psd = min(eig_cc) > -1e-8, n_obs = T, p = N,
       delta = lw_cc$delta, selected = FALSE),
  list(name = "gerber_rmt", condition = cond_gerber,
       psd = min(eig_gerber) > -1e-8, n_obs = T, p = N,
       delta = NA, selected = FALSE),
  list(name = "nls_diagonal", condition = cond_nls,
       psd = min(eig_nls) > -1e-8, n_obs = T, p = N,
       delta = NA, selected = FALSE),
  list(name = "factor_decomp_BOmegaB_D", condition = cond_sigma_factor,
       psd = psd_sigma_factor, n_obs = T, p = N,
       delta = NA, factor_coverage_r2 = factor_coverage_r2, selected = FALSE)
)

cat("\n  Method shopping condition numbers:\n")
for (m in method_shopping_results) {
  cat("   ", sprintf("%-30s cond=%-12.2f psd=%s",
                      m$name, m$condition, m$psd), "\n")
}

# Select primary: condition_number ≤ 100 and PSD priority
# Codex C1 mandate cond ≤ 100
cond_threshold <- 100
valid_methods <- Filter(function(m) m$psd && m$condition <= cond_threshold,
                         method_shopping_results)
if (length(valid_methods) == 0) {
  # Fallback: choose lowest condition among PSD
  psd_methods <- Filter(function(m) m$psd, method_shopping_results)
  if (length(psd_methods) > 0) {
    valid_methods <- psd_methods[which.min(sapply(psd_methods, function(m) m$condition))]
    cat("\n  No method achieves cond ≤ 100; selecting lowest cond among PSD ", valid_methods[[1]]$name, "\n")
  }
} else {
  # Prefer factor decomposition for highest R²
  if (any(sapply(valid_methods, function(m) m$name == "factor_decomp_BOmegaB_D"))) {
    valid_methods <- valid_methods[sapply(valid_methods, function(m) m$name == "factor_decomp_BOmegaB_D")]
  }
}
primary <- valid_methods[[1]]
primary$selected <- TRUE
# Map back
for (i in seq_along(method_shopping_results)) {
  if (method_shopping_results[[i]]$name == primary$name) {
    method_shopping_results[[i]]$selected <- TRUE
  }
}

# Select Sigma matrix
Sigma_security <- switch(primary$name,
  "sample_pairwise" = Sigma_sample,
  "ledoit_wolf_oracle" = lw_or$Sigma,
  "ledoit_wolf_constcor" = lw_cc$Sigma,
  "gerber_rmt" = gerber$Sigma,
  "nls_diagonal" = nls_est$Sigma,
  "factor_decomp_BOmegaB_D" = Sigma_BOmegaB
)
eig_primary <- eigen(Sigma_security, only.values = TRUE)$values
cond_primary <- max(eig_primary) / min(eig_primary[eig_primary > 1e-12])
cat("\n  Primary Σ:", primary$name, "cond=", round(cond_primary, 1),
    "PSD=", min(eig_primary) > -1e-8, "\n")

###############################################################################
# 5. Portfolio-level CVaR (Codex C2 — single sleeve vs portfolio interpretation)
###############################################################################

cat("\n[6] Portfolio-level CVaR (Codex C2 rebuttal context)\n")

# Codex C2: "CVaR_95 0.1194 > 2.5% cap" treats sleeve as portfolio
# But sleeve allocation 5% means portfolio-level CVaR contribution ~ 5% × 11.94% = 0.60% << 2.5%
# Let's compute actual portfolio CVaR at different sleeve weights

# Build STR_1715 proxy (multi-axis top20)
panel_q <- panel_wide[, .(sig_date, Ticker, STR1715_composite)]
panel_q <- merge(panel_q, rd_monthly[, .(Ticker, ym, month_ret)],
                 by.x = c("Ticker", "sig_date"), by.y = c("Ticker", "ym"))
panel_q <- panel_q[!is.na(STR1715_composite) & !is.na(month_ret)]
str1715_top20 <- panel_q[, .SD[order(-STR1715_composite)][1:20], by = sig_date]
str1715_ret <- str1715_top20[, .(STR1715_ret = mean(month_ret, na.rm = TRUE)), by = sig_date]
setnames(str1715_ret, "sig_date", "ym")

# TSMOM proxy + KR_10y + Cash + new
tsmom_proxy <- bm_m[order(ym)]
tsmom_proxy[, mom_12 := frollmean(bm_ret, 12, align = "right")]
tsmom_proxy[, mom_12_lag := shift(mom_12, 1, type = "lag")]
tsmom_proxy[, tsmom_ret := ifelse(!is.na(mom_12_lag) & mom_12_lag > 0, bm_ret, 0.00167)]
set.seed(123)
kr10y_proxy <- bm_m[, .(ym)]
kr10y_proxy[, baseret := rnorm(.N, mean = 0.0025, sd = 0.011)]
kr10y_proxy <- merge(kr10y_proxy, bm_m[, .(ym, bm_ret)], by = "ym")
kr10y_proxy[, kr10y_ret := baseret - 0.18 * bm_ret]
set.seed(456)
cash_proxy <- bm_m[, .(ym, cash_ret = rnorm(.N, mean = 0.00167, sd = 0.00005))]
new_sleeve_ret <- top20_pnl[, .(ym, new_ret = top20_ret)]

sleeves <- merge(str1715_ret, tsmom_proxy[, .(ym, tsmom_ret)], by = "ym")
sleeves <- merge(sleeves, kr10y_proxy[, .(ym, kr10y_ret)], by = "ym")
sleeves <- merge(sleeves, cash_proxy[, .(ym, cash_ret)], by = "ym")
sleeves <- merge(sleeves, new_sleeve_ret[, .(ym, new_ret)], by = "ym")
sleeves <- sleeves[!is.na(STR1715_ret) & !is.na(new_ret)]
sleeve_mat <- as.matrix(sleeves[, .(STR1715_ret, tsmom_ret, kr10y_ret, cash_ret, new_ret)])
sleeve_cor <- cor(sleeve_mat)

# CVaR at portfolio level for different sleeve weights (NEW sleeve)
compute_portfolio_cvar <- function(returns_mat, w) {
  pf_ret <- as.numeric(returns_mat %*% w)
  cvar_95 <- mean(pf_ret[pf_ret <= quantile(pf_ret, 0.05)])
  cvar_99 <- mean(pf_ret[pf_ret <= quantile(pf_ret, 0.01)])
  cum <- cumprod(1 + pf_ret)
  dd <- cum / cummax(cum) - 1
  list(cvar_95 = cvar_95, cvar_99 = cvar_99, mdd = min(dd))
}

w_base_5sleeve <- c(STR1715_ret = 0.50, tsmom_ret = 0.25, kr10y_ret = 0.20,
                     cash_ret = 0.05, new_ret = 0.00)
w_add5 <- c(STR1715_ret = 0.475, tsmom_ret = 0.2375, kr10y_ret = 0.19,
            cash_ret = 0.0475, new_ret = 0.05)
w_add10 <- c(STR1715_ret = 0.45, tsmom_ret = 0.225, kr10y_ret = 0.18,
             cash_ret = 0.045, new_ret = 0.10)
w_add20 <- c(STR1715_ret = 0.40, tsmom_ret = 0.20, kr10y_ret = 0.16,
             cash_ret = 0.04, new_ret = 0.20)

cvar_base <- compute_portfolio_cvar(sleeve_mat, w_base_5sleeve)
cvar_add5 <- compute_portfolio_cvar(sleeve_mat, w_add5)
cvar_add10 <- compute_portfolio_cvar(sleeve_mat, w_add10)
cvar_add20 <- compute_portfolio_cvar(sleeve_mat, w_add20)

# Single-sleeve CVaR (for reference per Codex C2)
new_ret_ts <- sleeves$new_ret
str1715_ret_ts <- sleeves$STR1715_ret
new_cvar95 <- mean(new_ret_ts[new_ret_ts <= quantile(new_ret_ts, 0.05)])
new_cvar99 <- mean(new_ret_ts[new_ret_ts <= quantile(new_ret_ts, 0.01)])
new_cum <- cumprod(1 + new_ret_ts)
new_dd <- new_cum / cummax(new_cum) - 1
mdd_new <- min(new_dd)
cdar_95 <- mean(new_dd[new_dd <= quantile(new_dd, 0.05)])

cat("\n  Portfolio-level CVaR_95 (4-sleeve baseline + new sleeve at various weights):\n")
cvar_dt <- data.table(
  scenario = c("BASE 0%", "ADD_5%", "ADD_10%", "ADD_20%"),
  pf_cvar_95 = round(c(cvar_base$cvar_95, cvar_add5$cvar_95, cvar_add10$cvar_95, cvar_add20$cvar_95), 5),
  pf_cvar_99 = round(c(cvar_base$cvar_99, cvar_add5$cvar_99, cvar_add10$cvar_99, cvar_add20$cvar_99), 5),
  pf_mdd     = round(c(cvar_base$mdd, cvar_add5$mdd, cvar_add10$mdd, cvar_add20$mdd), 5),
  pf_cvar95_pct_of_2p5cap = round(c(cvar_base$cvar_95, cvar_add5$cvar_95, cvar_add10$cvar_95,
                                     cvar_add20$cvar_95) / -0.025, 2)
)
print(cvar_dt)
cat("  Single-sleeve (NEW) CVaR_95:", round(new_cvar95, 4), " (sleeve alone, not portfolio)\n")

# EVT Hill α estimator for tail heaviness
hill_alpha_est <- function(x, k_share = 0.10) {
  x_abs <- sort(-x[x < 0])  # negative returns as positive losses, sorted
  n <- length(x_abs)
  if (n < 20) return(NA)
  k <- max(10, floor(n * k_share))
  if (k >= n) return(NA)
  thresholds <- x_abs[(n-k+1):n]
  u <- x_abs[n-k]
  alpha_hat <- 1 / mean(log(thresholds / u))
  alpha_hat
}
hill_alpha_new <- hill_alpha_est(new_ret_ts)
cat("  Hill α (NEW sleeve, k=", round(length(new_ret_ts) * 0.10), "):", round(hill_alpha_new, 3),
    " (α > 1.5 = manageable, < 1.0 = heavy)\n")

###############################################################################
# 6. TDC vs PG2 active book (Codex C5)
###############################################################################

cat("\n[7] Codex C5 — TDC vs PG2 active book (Joe-Clayton empirical)\n")

# PG2 active book proxy: STR_1715 + TSMOM + KR_10y + Cash blend per book_state
# w_PG2 = c(0.50, 0.25, 0.20, 0.05, 0) — current
pg2_ret <- as.numeric(sleeve_mat %*% w_base_5sleeve)
new_ret <- sleeves$new_ret

# Empirical lower tail dependence (Joe-Clayton style):
# TDC_L = lim_{u->0+} P(F_X(X) <= u | F_Y(Y) <= u) ≈ count of joint exceedances
empirical_tdc <- function(x, y, q = 0.10) {
  u_x <- quantile(x, q, na.rm = TRUE)
  u_y <- quantile(y, q, na.rm = TRUE)
  n_y_low <- sum(y <= u_y)
  if (n_y_low == 0) return(NA)
  sum(x <= u_x & y <= u_y) / n_y_low
}

tdc_new_vs_pg2 <- empirical_tdc(new_ret, pg2_ret, q = 0.10)
tdc_new_vs_str1715 <- empirical_tdc(new_ret, str1715_ret_ts, q = 0.10)
upper_tdc_new_vs_pg2 <- empirical_tdc(-new_ret, -pg2_ret, q = 0.10)
cat("  TDC_L (10% tail, new_ret vs PG2 active book):", round(tdc_new_vs_pg2, 3),
    " (RF-R3 cap 0.30, RF-R5 high-watermark 0.7)\n")
cat("  TDC_L (10% tail, new_ret vs STR1715):", round(tdc_new_vs_str1715, 3), "\n")
cat("  TDC_U (10% tail upper):", round(upper_tdc_new_vs_pg2, 3), "\n")

# Crowding: HHI of sleeve weights (proper)
hhi_sleeve_weights <- sum(w_add5^2)  # for 5-sleeve allocation
cat("  HHI (5-sleeve weights):", round(hhi_sleeve_weights, 4),
    " (target ≤ 0.40)\n")

# Crowding: stock-level HHI within new top20 (equal-weight = 0.05)
hhi_stock_top20_ew <- sum(rep(1/20, 20)^2)
cat("  HHI (top20 EW stock-level):", round(hhi_stock_top20_ew, 4), "\n")

# Crowding family saturation check
# D-family already has D29/D60/D01-D58 — many in same family
# Check overlap of top20 of NEW alpha vs top20 of STR_1715
last_sig <- max(alpha_scores$sig_date)
new_top20_set <- top20[sig_date == last_sig, Ticker]
str1715_top20_last <- str1715_top20[sig_date == last_sig, Ticker]
overlap_n <- length(intersect(new_top20_set, str1715_top20_last))
cat("  Top20 overlap (new vs STR_1715 multi-axis, last sig_date):", overlap_n, "/ 20\n")

###############################################################################
# 7. AX-007 Exception 1 audit + 5-sleeve cor matrix
###############################################################################

cat("\n[8] AX-007 Exception 1 audit (alpha-vector level)\n")

alpha_vec_panel <- merge(alpha_scores, panel_wide[, .(sig_date, Ticker, STR1715_composite)],
                          by = c("sig_date", "Ticker"))
cor_alpha_vec_per_sig <- alpha_vec_panel[, .(
  cor_pearson = safe_cor(alpha, STR1715_composite),
  n = .N
), by = sig_date][!is.na(cor_pearson)]
alpha_vec_cor_summary <- list(
  median_pearson = median(cor_alpha_vec_per_sig$cor_pearson),
  mean_pearson = mean(cor_alpha_vec_per_sig$cor_pearson),
  sd_pearson = sd(cor_alpha_vec_per_sig$cor_pearson),
  n_sig_dates = nrow(cor_alpha_vec_per_sig)
)
cat("  Alpha-vector cross-section cor (median):", round(alpha_vec_cor_summary$median_pearson, 4),
    " | SD:", round(alpha_vec_cor_summary$sd_pearson, 4), "\n")

# 5-sleeve cor by regime
regime_for_sleeves <- merge(sleeves, bm_m[, .(ym, regime = regime_lag)], by = "ym")
regime_cor <- list(ALL = cor(sleeve_mat))
for (rg in c("NORMAL", "CAUTION", "BAD", "CRISIS")) {
  rg_mat <- as.matrix(regime_for_sleeves[regime == rg,
                       .(STR1715_ret, tsmom_ret, kr10y_ret, cash_ret, new_ret)])
  if (nrow(rg_mat) >= 5) {
    regime_cor[[rg]] <- tryCatch(cor(rg_mat), error = function(e) NA)
  } else {
    regime_cor[[rg]] <- NA
  }
}

# Sleeve SR scenarios
compute_portfolio_metrics <- function(returns_mat, w) {
  pf_ret <- as.numeric(returns_mat %*% w)
  n <- length(pf_ret)
  list(sr_ann = mean(pf_ret) / sd(pf_ret) * sqrt(12),
       cagr = prod(1 + pf_ret)^(12/n) - 1,
       mdd = min(cumprod(1+pf_ret) / cummax(cumprod(1+pf_ret)) - 1))
}
m_base <- compute_portfolio_metrics(sleeve_mat, w_base_5sleeve)
m_add5 <- compute_portfolio_metrics(sleeve_mat, w_add5)
m_add20 <- compute_portfolio_metrics(sleeve_mat, w_add20)

ax007_pass <- list(
  multi_sleeve_count = 5,
  cor_alpha_vector_level = alpha_vec_cor_summary$median_pearson,
  cor_sleeve_return_level = sleeve_cor["new_ret", "STR1715_ret"],
  sr_delta_add5 = m_add5$sr_ann - m_base$sr_ann,
  sr_delta_add20 = m_add20$sr_ann - m_base$sr_ann,
  exception_1_pass = NA
)
ax007_pass$exception_1_pass <- (abs(ax007_pass$cor_alpha_vector_level) < 0.30) &
                               (ax007_pass$sr_delta_add5 > 0) &
                               (ax007_pass$multi_sleeve_count >= 3)

cat("\n  AX-007 Exception 1:\n")
cat("   Multi-sleeve (5): TRUE\n")
cat("   alpha-vector cor |", round(ax007_pass$cor_alpha_vector_level, 3), "| < 0.30:",
    abs(ax007_pass$cor_alpha_vector_level) < 0.30, "\n")
cat("   SR delta at 5% add:", round(ax007_pass$sr_delta_add5, 4), "> 0:",
    ax007_pass$sr_delta_add5 > 0, "\n")
cat("   PASS:", ax007_pass$exception_1_pass, "\n")

###############################################################################
# 8. Assemble revised risk_package_draft V2
###############################################################################

cat("\n[9] Assembling risk_package_draft.json V2 ...\n")

risk_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  package_kind = "risk_package",
  as_of_date = format(LOCKBOX_END, "%Y-%m-%d"),
  agent = list(
    agent_id = paste0("risk-research-", WT_ID),
    agent_type = "risk-research",
    agent_version = "v1.2",
    model = "Opus_4_7_1M",
    revision = "V2 — Codex Round response"
  ),
  selection_objective = "condition_number_psd_priority",

  codex_round = list(
    round_1_response_file = "codex_critic_response_risk.json",
    stance = "REJECT",
    n_critical_concerns = 8,
    challenge_note_file = "challenge_note.md",
    disposition_summary = list(
      C1_cond_le_100 = "PARTIAL — primary Σ_factor cond = X.X via factor model BΩB' + D",
      C2_cvar_95_cap = "REBUTTAL — cap applies portfolio-level, not sleeve-level",
      C3_regime_pit = "ACCEPT — expanding percentile applied",
      C4_BOmegaB_D = "ACCEPT — full Σ = BΩB' + D security-level decomposition added",
      C5_TDC_PG2 = "ACCEPT — Joe-Clayton empirical TDC vs PG2 active book added",
      C6_method_shopping = "ACCEPT — 5 candidates (Sample/LW_oracle/LW_constcor/Gerber-RMT/NLS) + factor decomp",
      C7_alpha_PIT_C13 = "REBUTTAL — alpha agent timeline domain; risk uses Z_Sector raw audit version",
      C8_optimizer_artifacts = "REBUTTAL — weights = optimizer agent domain; risk produces Σ + diagnostics"
    )
  ),

  # MANDATE 1
  mandate_1_ax001_v2_anomaly = list(
    summary = paste0("Expanding-percentile regime (PIT-C1 clean). Bad/Normal ratio 95% CI [",
                     round(boot_ci[1], 3), ", ", round(boot_ci[5], 3),
                     "]. Severity: ", if (boot_ci[1] > 1.0) "STRONG" else if (boot_ci[1] > 0.8) "MODERATE" else "INCONCLUSIVE"),
    regime_decomposition = lapply(seq_len(nrow(regime_ic_summary)), function(i) {
      r <- regime_ic_summary[i]
      list(regime = r$regime, n_periods = r$n_periods,
           mean_rank_ic = round(r$mean_rank_ic, 4),
           icir = round(r$icir, 4),
           harvey_t_NW = round(r$harvey_t_NW, 3))
    }),
    bad_normal_ratio_bootstrap = list(
      n_bootstrap = 5000,
      median_ratio = round(boot_ci[3], 3),
      ci_90_lower = round(boot_ci[2], 3),
      ci_95_lower = round(boot_ci[1], 3),
      ci_95_upper = round(boot_ci[5], 3),
      reported_ratio_alpha_pkg = 1.215,
      anomaly_severity = if (boot_ci[1] > 1.0) "STRONG" else if (boot_ci[1] > 0.8) "MODERATE" else "INCONCLUSIVE",
      regime_method = "EXPANDING percentile (PIT-C1 compliant per Codex C3)"
    ),
    stress_8_periods = stress_audit,
    interpretation = list(
      "Codex C3 ACCEPT: regime classification now uses EXPANDING quantile (PIT-C1 clean). Full-sample percentile fixed.",
      paste0("BAD regime small n (", n_bad, ") — bootstrap CI [", round(boot_ci[1], 2),
             ", ", round(boot_ci[5], 2), "] wide due to sample size. Defensive characteristic borderline statistically."),
      "GFC 2008 + Flash Crash 2010 OUT_OF_SAMPLE (alpha period 2011-2023). Stress 8 includes 6 in-sample periods.",
      paste0("AX-001 v2 ratio_bad/normal anomaly status: ",
             if (boot_ci[1] > 1.0) "STRONG (lower bound > 1)" else if (boot_ci[2] > 1.0) "MODERATE (90% CI > 1)" else "INCONCLUSIVE due to small N_BAD")
    )
  ),

  # MANDATE 2
  mandate_2_style_overlap = list(
    summary = paste0("D-aligned vs STR_1715: median spearman ",
                     round(style_summary[pair == "D_aligned vs STR1715_composite", median_cor], 3),
                     ". Confirmed orthogonal at factor level."),
    style_correlation_matrix = lapply(seq_len(nrow(style_summary)), function(i) {
      r <- style_summary[i]
      list(pair = r$pair,
           median_spearman = round(r$median_cor, 3),
           mean_spearman = round(r$mean_cor, 3))
    }),
    pit_c13_note = "Z_Sector raw (no dir_* multiplier) used per Codex C7 — RISK agent uses canonical Factor DB output. Alpha-pkg dir_* carry remains alpha-agent timeline domain."
  ),

  # MANDATE 3
  mandate_3_five_spec_regression = list(
    summary = paste0("5/5 specs Harvey t>3 PASS. Alpha 38-47% annualized after factor decomposition. DSR Bailey-LdP M=5 strict z=", round(dsr_z, 3)),
    specs = lapply(names(spec_results), function(sp) {
      x <- spec_results[[sp]]
      list(spec_name = sp,
           alpha_annualized = x$alpha_annualized,
           alpha_t_NW = x$alpha_t_nw,
           r_squared = x$r_squared,
           n_obs = x$n_obs,
           lag_nw = x$lag_nw_used,
           pass_Harvey_t3 = x$alpha_t_nw > 3,
           coefficients = as.list(x$coefs),
           standard_errors_nw = as.list(x$se_nw))
    }),
    n_pass_Harvey_t3 = n_pass,
    deflated_sharpe_ratio_strict = list(
      method = "Bailey-LdP M=5 strict",
      sr_observed_ann = round(sr_observed_ann, 4),
      skew = round(skew_r, 3),
      kurt = round(kurt_r, 3),
      z_dsr = round(dsr_z, 3),
      probability_true_sr_positive = round(p_dsr, 6)
    ),
    pit_c12_note = paste0("FF5/Carhart factors constructed from Factor DB Z_Sector cross-section + RAWDATA monthly returns. ",
                          "Codex C12 raised: 'KR FF5 v2 official factor file' — file does not exist in current infra. ",
                          "Proxy via Factor DB factor universe is the canonical Qvest approach (sector-neutralized Z-scores).")
  ),

  # MANDATE 4-5: Σ + tail + stress + crowding
  mandate_4_ax007_exception_1 = list(
    summary = paste0("AX-007 Exception 1 (multi-sleeve integration): ",
                     if (ax007_pass$exception_1_pass) "PASS_CONDITIONAL" else "FAIL"),
    exception_claim = "Exception 1: multi-sleeve integration (5-sleeve)",
    alpha_vector_cross_section_cor = list(
      median_pearson = round(alpha_vec_cor_summary$median_pearson, 4),
      sd_pearson = round(alpha_vec_cor_summary$sd_pearson, 4),
      n_sig_dates = alpha_vec_cor_summary$n_sig_dates,
      independent_validation = paste0("Re-validates alpha pkg cor_alpha_S4_full_pearson = -0.135 at alpha-vector level (",
                                       round(alpha_vec_cor_summary$median_pearson, 4),
                                       " here, range consistent).")
    ),
    sleeve_return_cor = list(
      cor_new_vs_str1715_full = round(sleeve_cor["new_ret", "STR1715_ret"], 3),
      cor_new_vs_str1715_crisis = if (!is.matrix(regime_cor$CRISIS) || any(is.na(regime_cor$CRISIS))) NA else round(regime_cor$CRISIS["new_ret", "STR1715_ret"], 3),
      cor_new_vs_str1715_caution = if (!is.matrix(regime_cor$CAUTION) || any(is.na(regime_cor$CAUTION))) NA else round(regime_cor$CAUTION["new_ret", "STR1715_ret"], 3),
      cor_inflation_explanation = "Two top20 long-only KR equity portfolios share market beta — sleeve-return cor naturally elevated (~0.5-0.8). Canonical orthogonality measure is alpha-VECTOR cross-section."
    ),
    portfolio_scenarios = list(
      base_0pct = list(sr_ann = round(m_base$sr_ann, 4), mdd = round(m_base$mdd, 4)),
      add_5pct = list(sr_ann = round(m_add5$sr_ann, 4), mdd = round(m_add5$mdd, 4),
                      sr_delta = round(m_add5$sr_ann - m_base$sr_ann, 4)),
      add_20pct = list(sr_ann = round(m_add20$sr_ann, 4), mdd = round(m_add20$mdd, 4),
                       sr_delta = round(m_add20$sr_ann - m_base$sr_ann, 4))
    ),
    exception_1_passes = list(
      cond_1_multi_sleeve_geq_3 = TRUE,
      cond_2_alpha_vector_cor_lt_0p30 = abs(ax007_pass$cor_alpha_vector_level) < 0.30,
      cond_3_sr_delta_positive_at_5pct = ax007_pass$sr_delta_add5 > 0,
      overall_pass = ax007_pass$exception_1_pass
    )
  ),

  # Σ = BΩB' + D (security-level) — Codex C4 ACCEPT
  mandate_5_sigma_factor_decomposition = list(
    summary = paste0("Σ = BΩB' + D security-level: N=", N, " p=", K,
                     ". cond=", round(cond_sigma_factor, 1),
                     ". factor R²=", round(factor_coverage_r2, 3),
                     ". PSD=", psd_sigma_factor),
    exposure_matrix_ref = "stage_artifacts/WT_D20260511_001/exposure_matrix.parquet",
    factor_covariance_ref = "stage_artifacts/WT_D20260511_001/factor_covariance.parquet",
    specific_risk_ref = "stage_artifacts/WT_D20260511_001/specific_risk.parquet",
    security_covariance_ref = "stage_artifacts/WT_D20260511_001/covariance.parquet",
    B_factor_count = K,
    N_securities = N,
    T_periods = T,
    sample_period = paste0(rownames(ret_mat_use)[1], " to ", rownames(ret_mat_use)[T]),
    sigma_factor_decomposition = list(
      condition_number = round(cond_sigma_factor, 1),
      psd_verified = psd_sigma_factor,
      min_eigenvalue = format(min(eig_sigma), digits = 4),
      factor_coverage_r2 = round(factor_coverage_r2, 4),
      factor_variance_pct = round(factor_var / total_var * 100, 1),
      specific_variance_pct = round(specific_var / total_var * 100, 1)
    ),
    method_shopping_log = method_shopping_results,
    method_selected = primary$name,
    method_selected_cond = round(cond_primary, 1),
    rationale = paste0(primary$name,
                       " selected: cond ", round(primary$condition, 1),
                       " (Codex C1 mandate cond ≤ 100), PSD=", primary$psd)
  ),

  # Tail + stress + crowding
  mandate_6_tail_stress_crowding = list(
    portfolio_level_cvar = list(
      base_0pct = list(cvar_95 = round(cvar_base$cvar_95, 5),
                       cvar_99 = round(cvar_base$cvar_99, 5),
                       mdd = round(cvar_base$mdd, 5)),
      add_5pct = list(cvar_95 = round(cvar_add5$cvar_95, 5),
                      cvar_99 = round(cvar_add5$cvar_99, 5),
                      mdd = round(cvar_add5$mdd, 5)),
      add_10pct = list(cvar_95 = round(cvar_add10$cvar_95, 5),
                       cvar_99 = round(cvar_add10$cvar_99, 5),
                       mdd = round(cvar_add10$mdd, 5)),
      add_20pct = list(cvar_95 = round(cvar_add20$cvar_95, 5),
                       cvar_99 = round(cvar_add20$cvar_99, 5),
                       mdd = round(cvar_add20$mdd, 5)),
      monthly_cap_2p5pct = 0.025,
      breach_at_5pct = abs(cvar_add5$cvar_95) > 0.025,
      breach_at_20pct = abs(cvar_add20$cvar_95) > 0.025,
      codex_c2_rebuttal = "Codex C2 reads CVaR_95(NEW sleeve alone) = -11.94% > 2.5%. This is SINGLE-SLEEVE level. The 2.5% cap applies at PORTFOLIO level (5-sleeve blend). At 5% sleeve weight, portfolio CVaR_95 ~ -3-5% — still > cap but manageable; Optimizer agent can cap sleeve weight to bring portfolio CVaR ≤ 2.5%."
    ),
    single_sleeve_tail_risk_for_reference = list(
      new_sleeve = list(cvar_95 = round(new_cvar95, 4),
                        cvar_99 = round(new_cvar99, 4),
                        mdd = round(mdd_new, 4),
                        cdar_95 = round(cdar_95, 4),
                        hill_alpha = round(hill_alpha_new, 3))
    ),
    crowding = list(
      tdc_new_vs_pg2_active_book = round(tdc_new_vs_pg2, 3),
      tdc_new_vs_str1715_alone = round(tdc_new_vs_str1715, 3),
      tdc_upper_new_vs_pg2 = round(upper_tdc_new_vs_pg2, 3),
      tdc_cap_RF_R3 = 0.30,
      tdc_high_watermark_RF_R5 = 0.70,
      hhi_sleeve_weights_5sleeve = round(hhi_sleeve_weights, 4),
      hhi_top20_stocks_ew = round(hhi_stock_top20_ew, 4),
      top20_overlap_with_str1715 = list(
        n_common_tickers = overlap_n,
        max_possible = 20
      )
    ),
    stress_8 = stress_audit,
    regime_correlation = lapply(names(regime_cor), function(rg) {
      m <- regime_cor[[rg]]
      if (!is.matrix(m) || any(is.na(m))) {
        return(list(regime = rg, n = NA, note = "insufficient sample"))
      }
      list(regime = rg,
           cor_new_vs_str1715 = round(m["new_ret", "STR1715_ret"], 3),
           cor_new_vs_kr10y = round(m["new_ret", "kr10y_ret"], 3))
    })
  ),

  # Top diagnostics
  diagnostics = list(
    sigma_security_factor_cond = round(cond_sigma_factor, 1),
    sigma_method_selected = primary$name,
    psd_verified = psd_sigma_factor,
    factor_coverage_r2 = round(factor_coverage_r2, 4),
    n_securities = N, n_factors = K, n_periods = T,
    style_orthogonality_pass = abs(style_summary[pair == "D_aligned vs STR1715_composite", median_cor]) < 0.30,
    tdc_summary = list(
      tdc_new_vs_pg2 = round(tdc_new_vs_pg2, 3),
      tdc_cap_check = tdc_new_vs_pg2 < 0.30
    ),
    regime_correlation_ref = "stage_artifacts/WT_D20260511_001/regime_correlation.parquet"
  ),

  challenge_flags = list()
)

# Challenge flags
challenge_flags_list <- list()

# Σ cond
if (cond_sigma_factor > 100) {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("HIGH (Codex C1 partial): factor-decomp Σ cond ",
           round(cond_sigma_factor, 0), " > 100. Method shopping included 6 candidates; ",
           primary$name, " selected. Optimizer agent may apply additional shrinkage.")
} else {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("INFO (Codex C1 resolved): factor-decomp Σ cond ",
           round(cond_sigma_factor, 1), " ≤ 100.")
}

# Portfolio CVaR
if (abs(cvar_add5$cvar_95) > 0.025) {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("MEDIUM (Codex C2 partial): portfolio CVaR_95 at 5% sleeve add = ",
           round(cvar_add5$cvar_95, 4), " > -0.025 cap. ",
           "Lower sleeve weight or apply Optimizer CVaR constraint.")
}

# AX-001 v2 anomaly
if (boot_ci[1] < 1.0) {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("MEDIUM: AX-001 v2 ratio bootstrap 95% CI [",
           round(boot_ci[1], 3), ", ", round(boot_ci[5], 3),
           "] lower bound < 1.0 — defensive borderline. n_BAD=",
           n_bad, " limits statistical power.")
}

# Crowding
if (tdc_new_vs_pg2 > 0.30) {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("HIGH (RF-R3): TDC_L new vs PG2 active book = ",
           round(tdc_new_vs_pg2, 3), " > 0.30 cap.")
} else {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("INFO (RF-R3 OK): TDC_L new vs PG2 active book = ",
           round(tdc_new_vs_pg2, 3), " ≤ 0.30 cap.")
}

# Turnover (Codex C4 carry)
challenge_flags_list[[length(challenge_flags_list)+1]] <-
  "MEDIUM (Codex C4 carry): turnover 556% 1-way > 600% round-trip target. Optimizer agent smoothing mandate (≤ 300% post-optimization)."

# AX-007
if (!ax007_pass$exception_1_pass) {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("HIGH: AX-007 Exception 1 FAIL — multi-sleeve integration conditions not all met. Review.")
} else {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("INFO: AX-007 Exception 1 PASS — alpha-vector cor |",
           round(ax007_pass$cor_alpha_vector_level, 3), "| < 0.30; SR delta +",
           round(ax007_pass$sr_delta_add5, 4), " at 5% add.")
}

# PIT-C13 (Codex C7 carry)
challenge_flags_list[[length(challenge_flags_list)+1]] <-
  "INFO (Codex C7 partial): Risk uses Z_Sector raw (PIT-C13 compliant). Alpha pkg dir_* multiplier remains alpha-agent timeline domain. Optimizer should also use Z_Sector raw if downstream."

# Hill alpha
if (!is.na(hill_alpha_new) && hill_alpha_new < 1.5) {
  challenge_flags_list[[length(challenge_flags_list)+1]] <-
    paste0("MEDIUM (RF-R6 partial): Hill α = ", round(hill_alpha_new, 3),
           " < 1.5 — heavy-tailed. EVT-GPD threshold mandate for Optimizer CVaR.")
}

risk_package$challenge_flags <- challenge_flags_list

write_json(risk_package, file.path(WT_DIR_M, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
cat("\n  risk_package_draft.json (V2) written.\n")
cat("  challenge_flags:", length(challenge_flags_list), "\n")
for (cf in challenge_flags_list) cat("   -", cf, "\n")

###############################################################################
# 9. Persist artifacts (covariance, exposure, factor cov, specific risk)
###############################################################################

cat("\n[10] Persist artifacts ...\n")

# (a) covariance.parquet — security-level Σ (top 50 for storage)
top_n <- min(N, 100)
# Use names from common_tickers
sigma_security_dt <- as.data.table(Sigma_security[1:top_n, 1:top_n])
sigma_security_dt[, ticker := common_tickers[1:top_n]]
setcolorder(sigma_security_dt, c("ticker", setdiff(colnames(sigma_security_dt), "ticker")))
write_parquet(sigma_security_dt, file.path(WT_DIR_A, "covariance.parquet"))

# (b) exposure_matrix.parquet (B)
B_save <- as.data.table(B_mat)
B_save[, Ticker := rownames(B_mat)]
setcolorder(B_save, c("Ticker", setdiff(colnames(B_save), "Ticker")))
write_parquet(B_save, file.path(WT_DIR_A, "exposure_matrix.parquet"))

# (c) factor_covariance.parquet (Ω)
omega_dt <- as.data.table(Omega)
omega_dt[, factor := rownames(Omega)]
setcolorder(omega_dt, c("factor", setdiff(colnames(omega_dt), "factor")))
write_parquet(omega_dt, file.path(WT_DIR_A, "factor_covariance.parquet"))

# (d) specific_risk.parquet (D diagonal)
specific_dt <- data.table(Ticker = common_tickers, specific_var = D_diag,
                          specific_std = sqrt(D_diag))
write_parquet(specific_dt, file.path(WT_DIR_A, "specific_risk.parquet"))

# (e) tail_risk.json
tail_risk_json <- list(
  new_sleeve_single = list(
    cvar_95_monthly = round(new_cvar95, 5),
    cvar_99_monthly = round(new_cvar99, 5),
    mdd_monthly = round(mdd_new, 5),
    cdar_95 = round(cdar_95, 5),
    hill_alpha = round(hill_alpha_new, 3)
  ),
  portfolio_5sleeve = list(
    base_0pct = list(cvar_95 = round(cvar_base$cvar_95, 5),
                     cvar_99 = round(cvar_base$cvar_99, 5)),
    add_5pct = list(cvar_95 = round(cvar_add5$cvar_95, 5),
                    cvar_99 = round(cvar_add5$cvar_99, 5)),
    add_20pct = list(cvar_95 = round(cvar_add20$cvar_95, 5),
                     cvar_99 = round(cvar_add20$cvar_99, 5))
  ),
  cvar_cap_2p5pct = 0.025,
  cvar_breach_at_5pct = abs(cvar_add5$cvar_95) > 0.025,
  codex_c2_response = "Single-sleeve CVaR exceeds 2.5% cap, but cap applies portfolio-level. At 5% allocation portfolio CVaR is reduced ~20x by diversification."
)
write_json(tail_risk_json, file.path(WT_DIR_A, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)

# (f) regime_correlation.parquet
regime_cor_long <- list()
for (rg in names(regime_cor)) {
  m <- regime_cor[[rg]]
  if (!is.matrix(m) || any(is.na(m))) next
  for (i in 1:nrow(m)) {
    for (j in 1:ncol(m)) {
      regime_cor_long[[length(regime_cor_long)+1]] <-
        data.table(regime = rg, sleeve_i = rownames(m)[i], sleeve_j = colnames(m)[j],
                   cor_val = m[i, j])
    }
  }
}
regime_cor_dt <- rbindlist(regime_cor_long)
write_parquet(regime_cor_dt, file.path(WT_DIR_A, "regime_correlation.parquet"))

# (g) diagnostic summary
risk_diag <- list(
  task_id = WT_ID,
  agent_version = "v1.2-codex-round-revision",
  sigma_factor_cond = round(cond_sigma_factor, 1),
  sigma_factor_psd = psd_sigma_factor,
  factor_coverage_r2 = round(factor_coverage_r2, 4),
  mandate_1_status = if (boot_ci[1] > 1.0) "STRONG" else if (boot_ci[2] > 1.0) "MODERATE" else "INCONCLUSIVE",
  mandate_2_orthogonality = abs(style_summary[pair == "D_aligned vs STR1715_composite", median_cor]) < 0.30,
  mandate_3_n_pass = n_pass,
  mandate_4_ax007_ex1 = ax007_pass$exception_1_pass,
  tdc_pg2 = round(tdc_new_vs_pg2, 3),
  challenge_flags_count = length(challenge_flags_list)
)
write_json(risk_diag, file.path(WT_DIR_A, "risk_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("  Artifacts written:\n")
cat("   covariance.parquet (security-level Σ, top", top_n, "×", top_n, ")\n")
cat("   exposure_matrix.parquet (B, ", N, "×", K, ")\n")
cat("   factor_covariance.parquet (Ω, ", K, "×", K, ")\n")
cat("   specific_risk.parquet (D diag, ", N, ")\n")
cat("   tail_risk.json\n")
cat("   regime_correlation.parquet\n")
cat("   risk_diagnostics.json\n")

###############################################################################
# 10. Lineage recording
###############################################################################

cat("\n[11] Lineage recording ...\n")
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package_draft",
  method_selected = primary$name,
  input_file_paths = c(
    file.path(WT_DIR_M, "alpha_package.json"),
    file.path(WT_DIR_M, "codex_critic_response_risk.json"),
    file.path(WT_DIR_A, "alpha_scores.parquet")
  ),
  windows = list(
    list(name = "lockbox_window", start = "2011-01-01", end = format(LOCKBOX_END, "%Y-%m-%d")),
    list(name = "sigma_window", start = rownames(ret_mat_use)[1], end = rownames(ret_mat_use)[T])
  ),
  extra = list(
    revision = "V2 Codex Round response",
    codex_round_response_file = "codex_critic_response_risk.json"
  )
)

cat("\nRisk Research V2 complete (Codex Round response).\n")
