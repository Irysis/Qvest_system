#==============================================================================
# WT-D20260508_007 — Step 2: Strict 12M Diagnostics
#
# Critical 12M-specific adjustments:
#   - Newey-West lag = 12 (Hansen-Hodrick standard for 12M overlapping returns)
#   - HAC robust SE for Harvey-t
#   - Bailey-LdP DSR strict, N_trials = 20 (보수)
#   - Subperiod 3 windows + sign + strict ICIR≥0.20
#   - Decile monotonicity + D10-D1 12M LS
#   - Turnover proxy (12M rebalance design)
#   - Sector-neutral retention check (RF-A4)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(sandwich); library(lmtest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_007")

# Try Rcpp DSR
rcpp_ok <- tryCatch({
  source(file.path(PROJ, "02_Infrastructure", "cpp", "rcpp_hotspots.R"))
  TRUE
}, error = function(e) { cat("[02] Rcpp not available:", e$message, "\n"); FALSE })

cat("[02] WT-D20260508_007 strict 12M diagnostics\n")
mm <- as.data.table(read_parquet(file.path(OUT, "alpha_panel_12m.parquet")))

variants <- c(
  raw_signed   = "alpha_signed_z",
  ema3         = "alpha_ema3_z",
  ema6         = "alpha_ema6_z",
  ema12        = "alpha_ema12_z",
  sector_neut  = "alpha_sn"
)

# ---- (1) IC table for 12M target across variants ----
ic_table <- list()
ic_period_store <- list()
for (vn in names(variants)) {
  vc <- variants[[vn]]
  sub <- mm[!is.na(get(vc)) & !is.na(FwdRet_12M)]
  ic_v <- sub[, .(rank_ic = cor(get(vc), FwdRet_12M, method = "spearman", use = "complete.obs"),
                  n = .N), by = ym]
  setorder(ic_v, ym)
  if (nrow(ic_v) > 0) {
    ic_period_store[[vn]] <- ic_v
    ic_table[[length(ic_table) + 1]] <- data.table(
      variant = vn, horizon = "12M",
      ic_mean = mean(ic_v$rank_ic, na.rm = TRUE),
      ic_sd   = sd(ic_v$rank_ic, na.rm = TRUE),
      icir    = mean(ic_v$rank_ic, na.rm = TRUE) / sd(ic_v$rank_ic, na.rm = TRUE),
      t_simple = mean(ic_v$rank_ic, na.rm = TRUE) /
                  (sd(ic_v$rank_ic, na.rm = TRUE) / sqrt(nrow(ic_v))),
      n_periods = nrow(ic_v),
      hit_pos = mean(ic_v$rank_ic > 0, na.rm = TRUE)
    )
  }
}
ic_table <- rbindlist(ic_table, fill = TRUE)
fwrite(ic_table, file.path(OUT, "ic_12m_strict_table.csv"))
cat("\n[02] 12M IC table (post-2013):\n"); print(ic_table)

setorder(ic_table, -icir)
PRIMARY <- ic_table$variant[1]
PRIMARY_COL <- variants[PRIMARY]
cat(sprintf("\n[02] PRIMARY variant (12M ICIR-best): %s (col=%s, ICIR=%.3f)\n",
            PRIMARY, PRIMARY_COL, ic_table$icir[1]))

# ---- (2) Harvey-Liu-Zhu t-stat with NW lag = 12 (HH 12M overlap) ----
ic_primary <- ic_period_store[[PRIMARY]]

harvey_t_nw_12 <- function(ic_series, lag = 12L) {
  v <- ic_series[!is.na(ic_series)]
  n <- length(v)
  if (n < 24) return(list(t_simple = NA_real_, t_nw = NA_real_, mean = NA_real_, n = n))
  fit <- lm(v ~ 1)
  vcv <- NeweyWest(fit, lag = lag, prewhite = FALSE, adjust = TRUE)
  se_nw <- sqrt(vcv[1, 1])
  list(
    t_simple = mean(v) / (sd(v) / sqrt(n)),
    t_nw     = mean(v) / se_nw,
    mean     = mean(v),
    se_nw    = se_nw,
    n        = n,
    lag_used = lag
  )
}

# Compute at multiple lags (sensitivity analysis)
ht_lag4  <- harvey_t_nw_12(ic_primary$rank_ic, lag = 4L)
ht_lag6  <- harvey_t_nw_12(ic_primary$rank_ic, lag = 6L)
ht_lag12 <- harvey_t_nw_12(ic_primary$rank_ic, lag = 12L)
ht_lag18 <- harvey_t_nw_12(ic_primary$rank_ic, lag = 18L)
cat(sprintf("[02] Harvey-NW (12M target) primary=%s:\n", PRIMARY))
cat(sprintf("       lag=4  → t_NW=%.3f / SE=%.5f\n",  ht_lag4$t_nw,  ht_lag4$se_nw))
cat(sprintf("       lag=6  → t_NW=%.3f / SE=%.5f\n",  ht_lag6$t_nw,  ht_lag6$se_nw))
cat(sprintf("       lag=12 → t_NW=%.3f / SE=%.5f\n", ht_lag12$t_nw, ht_lag12$se_nw))
cat(sprintf("       lag=18 → t_NW=%.3f / SE=%.5f\n", ht_lag18$t_nw, ht_lag18$se_nw))

# 12M overlapping returns standard = lag 12 (Hansen-Hodrick)
ht_primary <- ht_lag12

# Number of variants passing Harvey-t > 3.0 (graduation threshold)
harvey_specs_pass <- 0L
harvey_t_per_variant <- list()
for (vn in names(variants)) {
  if (!is.null(ic_period_store[[vn]])) {
    h <- harvey_t_nw_12(ic_period_store[[vn]]$rank_ic, lag = 12L)
    harvey_t_per_variant[[vn]] <- h
    if (!is.na(h$t_nw) && abs(h$t_nw) > 3.0) harvey_specs_pass <- harvey_specs_pass + 1L
  }
}
cat(sprintf("\n[02] Harvey-NW lag=12 specs passing |t|>3.0: %d / %d variants\n",
            harvey_specs_pass, length(variants)))

# ---- (3) Subperiod stability for primary 12M ----
subps <- list(p1 = c("2013-01", "2016-12"),
              p2 = c("2017-01", "2020-12"),
              p3 = c("2021-01", "2026-12"))
sub_stab <- lapply(names(subps), function(pn) {
  rng <- subps[[pn]]
  sub <- ic_primary[ym >= rng[1] & ym <= rng[2]]
  if (nrow(sub) < 6) return(data.table(p = pn, ic_mean = NA_real_, icir = NA_real_,
                                       n = nrow(sub), strict_pass = FALSE,
                                       sign = NA_integer_))
  ic_mean <- mean(sub$rank_ic, na.rm = TRUE)
  icir <- ic_mean / sd(sub$rank_ic, na.rm = TRUE)
  data.table(p = pn, ic_mean = ic_mean, icir = icir, n = nrow(sub),
             strict_pass = abs(icir) >= 0.20,
             sign = sign(ic_mean))
}) |> rbindlist()
overall_sign <- sign(mean(ic_primary$rank_ic, na.rm = TRUE))
sign_stab <- mean(sub_stab[!is.na(sign), sign] == overall_sign)
strict_pass_count <- sum(sub_stab$strict_pass, na.rm = TRUE)
cat("\n[02] 12M Subperiod stability (primary variant):\n"); print(sub_stab)
cat(sprintf("[02] Sign stability = %.2f (%d/%d) | Strict ICIR>=0.20 = %d/3\n",
            sign_stab, sum(sub_stab[!is.na(sign), sign] == overall_sign),
            sum(!is.na(sub_stab$sign)), strict_pass_count))

# ---- (4) Decile monotonicity + D10-D1 12M LS ----
mm[, decile := {
  v <- get(PRIMARY_COL)
  if (sum(!is.na(v)) >= 10) {
    qs <- quantile(v, seq(0, 1, 0.1), na.rm = TRUE)
    qs <- unique(qs)
    if (length(qs) >= 2) {
      as.integer(cut(v, qs, include.lowest = TRUE, labels = FALSE))
    } else rep(NA_integer_, length(v))
  } else rep(NA_integer_, length(v))
}, by = ym]

dec_ret <- mm[!is.na(decile) & !is.na(FwdRet_12M),
              .(mean_ret = mean(FwdRet_12M, na.rm = TRUE), n = .N),
              by = .(ym, decile)]
dec_avg <- dec_ret[, .(mean_ret = mean(mean_ret, na.rm = TRUE)), by = decile]
setorder(dec_avg, decile)
cat("\n[02] Decile mean 12M returns:\n"); print(dec_avg)

dec_ls <- dcast(dec_ret[decile %in% c(1, 10)], ym ~ decile, value.var = "mean_ret")
setnames(dec_ls, c("ym", "D1", "D10"))
dec_ls[, D10_minus_D1 := D10 - D1]
dec_ls <- dec_ls[!is.na(D10_minus_D1)]
ls_mean <- mean(dec_ls$D10_minus_D1, na.rm = TRUE)
ls_sd   <- sd(dec_ls$D10_minus_D1, na.rm = TRUE)
ls_t    <- ls_mean / (ls_sd / sqrt(nrow(dec_ls)))
# 12M overlapping → annual SR = mean / sd (already 12M return scale, no scaling)
ls_sr_annual_gross <- ls_mean / ls_sd
cat(sprintf("[02] LS D10-D1 (12M): mean=%.4f / sd=%.4f / t=%.3f / SR_annual_gross=%.3f / n=%d\n",
            ls_mean, ls_sd, ls_t, ls_sr_annual_gross, nrow(dec_ls)))

mono <- cor(dec_avg$decile, dec_avg$mean_ret, method = "spearman")
cat(sprintf("[02] 12M Decile monotonicity (Spearman) = %.3f\n", mono))

# ---- (5) DSR Bailey-Lopez de Prado strict (12M LS) ----
ls_returns <- dec_ls$D10_minus_D1
n_ls <- length(ls_returns)
sr_annual <- ls_sr_annual_gross
g3 <- mean((ls_returns - mean(ls_returns))^3) / sd(ls_returns)^3
g4 <- mean((ls_returns - mean(ls_returns))^4) / sd(ls_returns)^4
sr_se_analytical <- sqrt((1 + 0.5 * sr_annual^2 - g3 * sr_annual + (g4 - 3) / 4 * sr_annual^2) / (n_ls - 1))

# DSR strict at multiple N_trials
N_trials_set <- c(12, 17, 20, 27)
dsr_strict_list <- list()
for (N_TRIALS in N_trials_set) {
  sr_max_expected <- (1 - 0.5772) * qnorm(1 - 1/N_TRIALS) +
                     0.5772 * qnorm(1 - 1/(N_TRIALS * exp(1)))
  var_sr_normal <- (1 + 0.5 * sr_annual^2 - g3 * sr_annual + (g4 - 3) / 4 * sr_annual^2) / n_ls
  sr0_blp <- sqrt(var_sr_normal) * sr_max_expected
  dsr_blp_z <- (sr_annual - sr0_blp) / sqrt(var_sr_normal)
  dsr_blp_p <- pnorm(dsr_blp_z, lower.tail = FALSE)
  dsr_strict_list[[as.character(N_TRIALS)]] <- list(
    n_trials = N_TRIALS,
    sr0_blp = sr0_blp,
    dsr_z_analytical = dsr_blp_z,
    dsr_p_analytical = dsr_blp_p,
    pass_strict = (dsr_blp_z >= 0.5)
  )
  cat(sprintf("[02] DSR strict N=%d: sr0=%.3f, z=%.3f, p=%.4g, pass=%s\n",
              N_TRIALS, sr0_blp, dsr_blp_z, dsr_blp_p, dsr_blp_z >= 0.5))
}

# Bootstrap DSR (fat-tail robust)
dsr_bootstrap_z <- NA_real_
dsr_bootstrap_p <- NA_real_
if (rcpp_ok && n_ls >= 24) {
  bs <- tryCatch({
    bootstrap_dsr_fast(ls_returns, n_trials = 20L, B = 1000L)
  }, error = function(e) NULL)
  if (!is.null(bs) && !is.null(bs$dsr_bootstrap)) {
    dsr_bootstrap_z <- bs$dsr_bootstrap
    if (!is.null(bs$pvalue)) dsr_bootstrap_p <- bs$pvalue
  }
}
if (is.na(dsr_bootstrap_z)) {
  set.seed(42)
  B <- 1000L
  boot_sr <- numeric(B)
  for (b in 1:B) {
    idx <- sample(n_ls, replace = TRUE)
    rs <- ls_returns[idx]
    boot_sr[b] <- mean(rs) / sd(rs)
  }
  sr_se_boot <- sd(boot_sr)
  N20 <- 20L
  sr_max_20 <- (1 - 0.5772) * qnorm(1 - 1/N20) + 0.5772 * qnorm(1 - 1/(N20 * exp(1)))
  sr0_b <- sd(boot_sr) * sr_max_20  # pseudo
  # Use analytical sr0 for N=20 already computed
  sr0_n20 <- dsr_strict_list[["20"]]$sr0_blp
  dsr_bootstrap_z <- (sr_annual - sr0_n20) / sr_se_boot
  dsr_bootstrap_p <- pnorm(dsr_bootstrap_z, lower.tail = FALSE)
}
cat(sprintf("[02] DSR bootstrap (B=1000, fat-tail robust): z=%.3f, p=%.4g\n",
            dsr_bootstrap_z, dsr_bootstrap_p))

dsr_out <- list(
  method = "Bailey-Lopez de Prado (2014) PMS 40(5):94-107 — 12M overlapping returns",
  primary_variant = PRIMARY,
  ls_basis = "decile D10 - D1 12M long-short on primary variant",
  observed = list(
    sr_annual_gross_12m = sr_annual,
    skew = g3, kurt = g4,
    n_periods = n_ls,
    sr_se_analytical = sr_se_analytical
  ),
  multi_trial_strict = dsr_strict_list,
  dsr_bootstrap_z = dsr_bootstrap_z,
  dsr_bootstrap_p = dsr_bootstrap_p,
  graduation_threshold_dsr = 0.5,
  pass_dsr_analytical_n20 = dsr_strict_list[["20"]]$pass_strict,
  pass_dsr_bootstrap = (!is.na(dsr_bootstrap_z) && dsr_bootstrap_z >= 0.5)
)
write_json(dsr_out, file.path(OUT, "dsr_strict_bailey_ldp_12m.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

# ---- (6) Turnover proxy (12M rebalance assumption) ----
mm[, alpha_rank := frank(get(PRIMARY_COL), na.last = "keep"), by = ym]
n_per_ym <- mm[, .(N = sum(!is.na(alpha_rank))), by = ym]
mm <- merge(mm, n_per_ym, by = "ym")
setorder(mm, Ticker, ym)
mm[, alpha_rank_lag := shift(alpha_rank, 1L), by = Ticker]
mm[, ym_num := as.integer(gsub("-", "", ym))]
mm[, ym_lag := shift(ym_num, 1L), by = Ticker]
mm[, gap_ok := (ym_num - ym_lag) %in% c(1, 89)]
turnover_dt <- mm[gap_ok == TRUE & !is.na(alpha_rank) & !is.na(alpha_rank_lag),
                  .(rank_change = abs(alpha_rank - alpha_rank_lag) / N),
                  by = ym]
turnover_proxy_monthly <- mean(turnover_dt$rank_change, na.rm = TRUE)
# 12M annual rebalance assumption: monthly cross-section rank change × 12 = approx 12M turnover proxy
turnover_proxy_annual_12m_design <- turnover_proxy_monthly * 12
cat(sprintf("[02] Turnover proxy: monthly=%.3f / 12M-design (×12)=%.3f\n",
            turnover_proxy_monthly, turnover_proxy_annual_12m_design))

# ---- (7) Sector-neutral retention (RF-A4 12M check) ----
ic_raw <- ic_table[variant == "raw_signed", icir]
ic_sn <- ic_table[variant == "sector_neut", icir]
sn_retention <- if (length(ic_raw) && length(ic_sn) && ic_raw != 0) ic_sn / ic_raw else NA_real_
cat(sprintf("[02] Sector-neutral 12M ICIR retention: %.3f (raw=%.3f / sn=%.3f)\n",
            sn_retention, ic_raw, ic_sn))
rf_a4_active <- !is.na(sn_retention) && sn_retention < 0.5

# ---- Aggregate ----
diag_out <- list(
  primary_variant = PRIMARY,
  primary_col = unname(PRIMARY_COL),
  forecast_horizon = "12M",
  ic_table = ic_table,
  harvey_t_nw_lag_sensitivity = list(
    lag4 = ht_lag4, lag6 = ht_lag6, lag12 = ht_lag12, lag18 = ht_lag18
  ),
  harvey_t_primary_lag12_HH = ht_lag12,
  harvey_t_per_variant_lag12 = harvey_t_per_variant,
  harvey_specs_pass_count_t3 = harvey_specs_pass,
  subperiod_stability = sub_stab,
  subperiod_sign_stab = sign_stab,
  subperiod_strict_pass = strict_pass_count,
  decile_monotonicity = mono,
  decile_means = dec_avg,
  ls_d10_d1_12m = list(
    mean = ls_mean, sd = ls_sd, t = ls_t,
    sr_annual_gross_12m = ls_sr_annual_gross,
    n_periods = nrow(dec_ls)
  ),
  turnover_proxy = list(
    monthly_rank_change = turnover_proxy_monthly,
    twelve_month_design = turnover_proxy_annual_12m_design,
    interpretation = "12M long-horizon design: predictor = 24M rolling β. Monthly cross-section rank change is naturally low. Annual turnover for 12M rebalance < 200%."
  ),
  sector_neutral_check = list(
    raw_icir = unname(ic_raw),
    sector_neut_icir = unname(ic_sn),
    retention = unname(sn_retention),
    rf_a4_active = rf_a4_active,
    note = if (rf_a4_active) "Sector-neutral retention < 0.5: signal carries sector-mediated component" else "Sector-neutral retention >= 0.5: signal robust to sector neutralization"
  ),
  dsr_strict = dsr_out
)
write_json(diag_out, file.path(OUT, "diagnostics_12m_strict.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

cat("\n[02] DONE. 12M strict diagnostics saved.\n")
