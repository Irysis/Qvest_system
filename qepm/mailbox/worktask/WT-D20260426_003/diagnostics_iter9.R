#==============================================================================
# WT-D20260426_003 Iter 9 Alpha Diagnostics
#
# Goals (13 v6.2 Mandate aligned):
#  1) Regime-conditional Rank IC + ICIR (BULL / NORMAL / CAUTION / CRISIS / overall)
#  2) Subperiod stability (2008-14 / 2015-19 / 2020-23)
#  3) Harvey t-stat (active sample only — alpha != 0)
#  4) DSR (multi-test 보정, 5 trials)
#  5) TDC vs STR_1700 alpha (target < 0.30)
#  6) 5-spec robustness (winsor 2/3/4 std × growth-only × flow-only)
#  7) Monotonicity (decile sorting)
#  8) Turnover proxy
#  9) Standalone SR proxy (per-period rank-IC mean / sd × sqrt(12))
# 10) Cross-sectional rank-IC of growth_z, flow_resid_z, interact_z separately
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID    <- "WT-D20260426_003"
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_003")
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)

# ---- Load ----
alpha_dt <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
setkey(alpha_dt, Date, Ticker)

str1700 <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet"))
setkey(str1700, Date, Ticker)

# Returns from STR_1700 (same Ret_1m forward)
ret_dt <- str1700[, .(Date, Ticker, Ret_1m)]
setkey(ret_dt, Date, Ticker)

combo <- alpha_dt[ret_dt, nomatch = 0L]
combo <- combo[str1700[, .(Date, Ticker, alpha_str1700 = score_eff)],
               on = .(Date, Ticker), nomatch = 0L]
combo <- combo[!is.na(Ret_1m) & !is.na(alpha) & !is.na(alpha_str1700)]
cat("[Diag] Merged rows:", nrow(combo),
    " | uniq Dates:", length(unique(combo$Date)),
    " | Tickers:", length(unique(combo$Ticker)), "\n")

# ============================================================
# 1) Regime-conditional Rank IC + ICIR
# ============================================================
ic_per_period <- combo[, .(
  N = .N,
  rank_ic = if (.N >= 30) suppressWarnings(cor(alpha, Ret_1m, method = "spearman")) else NA_real_,
  regime_state = regime_state[1]
), by = Date]
ic_per_period <- ic_per_period[!is.na(rank_ic)]

ic_overall <- list(
  rank_ic_mean = mean(ic_per_period$rank_ic, na.rm = TRUE),
  rank_ic_sd   = sd(ic_per_period$rank_ic, na.rm = TRUE),
  icir         = mean(ic_per_period$rank_ic) / sd(ic_per_period$rank_ic),
  n_periods    = nrow(ic_per_period)
)
cat(sprintf("[Diag] Overall: rank_IC=%.4f, sd=%.4f, ICIR=%.3f, N=%d\n",
            ic_overall$rank_ic_mean, ic_overall$rank_ic_sd,
            ic_overall$icir, ic_overall$n_periods))

ic_by_regime <- ic_per_period[, .(
  N = .N,
  rank_ic_mean = mean(rank_ic),
  rank_ic_sd   = sd(rank_ic),
  icir = mean(rank_ic) / sd(rank_ic)
), by = regime_state]
print(ic_by_regime)

# Active = sleeve_w_alpha > 0 → BULL/NORMAL/CAUTION
ic_active <- ic_per_period[regime_state %in% c("BULL", "NORMAL", "CAUTION")]
ic_active_summary <- list(
  rank_ic_mean = mean(ic_active$rank_ic),
  rank_ic_sd   = sd(ic_active$rank_ic),
  icir         = mean(ic_active$rank_ic) / sd(ic_active$rank_ic),
  n_periods    = nrow(ic_active)
)
cat(sprintf("[Diag] Active (BULL+NORMAL+CAUTION): rank_IC=%.4f, ICIR=%.3f, N=%d\n",
            ic_active_summary$rank_ic_mean, ic_active_summary$icir,
            ic_active_summary$n_periods))

# ============================================================
# 2) Subperiod stability (2008-14 / 2015-19 / 2020-23)
# ============================================================
subperiods <- list(
  "2008-2014" = c(as.Date("2008-01-01"), as.Date("2014-12-31")),
  "2015-2019" = c(as.Date("2015-01-01"), as.Date("2019-12-31")),
  "2020-2023" = c(as.Date("2020-01-01"), as.Date("2023-12-31"))
)
subp_ic <- lapply(names(subperiods), function(nm) {
  rng <- subperiods[[nm]]
  sub <- ic_per_period[Date >= rng[1] & Date <= rng[2]]
  data.table(
    period = nm, n = nrow(sub),
    rank_ic = if (nrow(sub) > 0) mean(sub$rank_ic) else NA_real_,
    icir = if (nrow(sub) > 1) mean(sub$rank_ic) / sd(sub$rank_ic) else NA_real_
  )
})
subp_ic_dt <- rbindlist(subp_ic)
print(subp_ic_dt)

sign_consistency <- mean(sign(subp_ic_dt$rank_ic) == sign(ic_overall$rank_ic_mean),
                         na.rm = TRUE)
cat(sprintf("[Diag] Subperiod sign consistency: %.2f\n", sign_consistency))

# ============================================================
# 3) Harvey t-stat (active sample)
# ============================================================
ic_active_vec <- ic_active$rank_ic
harvey_t <- mean(ic_active_vec) / (sd(ic_active_vec) / sqrt(length(ic_active_vec)))
cat(sprintf("[Diag] Harvey t-stat (active): %.3f\n", harvey_t))

# Overall sample
ic_overall_vec <- ic_per_period$rank_ic
harvey_t_overall <- mean(ic_overall_vec) / (sd(ic_overall_vec) / sqrt(length(ic_overall_vec)))
cat(sprintf("[Diag] Harvey t-stat (overall): %.3f\n", harvey_t_overall))

# ============================================================
# 4) DSR (Bailey-Lopez de Prado)
# ============================================================
returns_for_dsr <- ic_active_vec
n_trials <- 5L  # 5-spec robustness 후보

mu <- mean(returns_for_dsr)
s  <- sd(returns_for_dsr)
n  <- length(returns_for_dsr)
sr_obs <- mu / s
m3 <- mean((returns_for_dsr - mu)^3) / s^3
m4 <- mean((returns_for_dsr - mu)^4) / s^4
sr_var <- (1 - m3 * sr_obs + ((m4 - 1) / 4) * sr_obs^2) / (n - 1)
sr_std <- sqrt(max(sr_var, 1e-12))
emc <- 0.5772156649
e_max <- (1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials * exp(1)))
dsr <- pnorm((sr_obs - e_max * sr_std) / sr_std)
cat(sprintf("[Diag] DSR (active sample, %d trials): %.3f\n", n_trials, dsr))

# ============================================================
# 5) TDC vs STR_1700 alpha
# ============================================================
xs_corr <- combo[, .(rho = if (.N >= 30) suppressWarnings(cor(alpha, alpha_str1700, method = "spearman")) else NA_real_),
                 by = Date]
xs_corr <- xs_corr[!is.na(rho)]
mean_xs_corr <- mean(xs_corr$rho)
cat(sprintf("[Diag] Mean cross-sectional rank corr vs STR_1700: %.4f\n", mean_xs_corr))

combo[, q_alpha := {
  r <- frank(alpha, ties.method = "average")
  ceiling(5 * r / .N)
}, by = Date]
combo[, q_str := {
  r <- frank(alpha_str1700, ties.method = "average")
  ceiling(5 * r / .N)
}, by = Date]
combo[, both_top := q_alpha == 5 & q_str == 5]
combo[, marginal_top := q_alpha == 5]
tdc_upper <- combo[, sum(both_top, na.rm=TRUE) / pmax(sum(marginal_top, na.rm=TRUE), 1)]
combo[, both_bot := q_alpha == 1 & q_str == 1]
combo[, marginal_bot := q_alpha == 1]
tdc_lower <- combo[, sum(both_bot, na.rm=TRUE) / pmax(sum(marginal_bot, na.rm=TRUE), 1)]
tdc_avg <- (tdc_upper + tdc_lower) / 2
cat(sprintf("[Diag] TDC upper (top quintile): %.3f\n", tdc_upper))
cat(sprintf("[Diag] TDC lower (bot quintile): %.3f\n", tdc_lower))
cat(sprintf("[Diag] TDC avg: %.3f (target < 0.30)\n", tdc_avg))

# ============================================================
# 6) 5-spec Harvey robustness
# Spec1: winsor 2std composite
# Spec2: winsor 3std (baseline)
# Spec3: winsor 4std
# Spec4: growth_z only (no flow, no interact)
# Spec5: flow_resid_z only (no growth, no interact)
# ============================================================
xs_zscore_local <- function(x, ws = 3) {
  if (all(is.na(x))) return(rep(0, length(x)))
  x[is.na(x)] <- median(x, na.rm = TRUE)
  m <- median(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-12) return(rep(0, length(x)))
  x_w <- pmin(pmax(x, m - ws * s), m + ws * s)
  mu <- mean(x_w); sd0 <- sd(x_w)
  if (is.na(sd0) || sd0 < 1e-12) return(rep(0, length(x_w)))
  (x_w - mu) / sd0
}

# Active rows (alpha sleeve > 0)
combo_active <- combo[sleeve_w_alpha > 0]

run_spec <- function(dt, sig_col, label) {
  ic_v <- dt[, {
    sigvals <- get(sig_col)
    rv <- Ret_1m
    if (.N >= 30 && sd(sigvals, na.rm=TRUE) > 1e-12) {
      list(rank_ic = suppressWarnings(cor(sigvals, rv, method = "spearman")))
    } else list(rank_ic = NA_real_)
  }, by = Date]
  ic_v <- ic_v[!is.na(rank_ic)]
  if (nrow(ic_v) < 5) return(data.table(spec = label, ic = NA_real_, t = NA_real_, n = nrow(ic_v)))
  t_stat <- mean(ic_v$rank_ic) / (sd(ic_v$rank_ic) / sqrt(nrow(ic_v)))
  data.table(spec = label,
             ic = mean(ic_v$rank_ic),
             t  = t_stat,
             n  = nrow(ic_v))
}

# Spec1: composite winsor 2std (rebuild)
specs <- list()
ws_apply <- function(dt, ws) {
  dt[, growth_z2 := xs_zscore_local(growth_z, ws), by = Date]
  dt[, flow_z2   := xs_zscore_local(flow_resid_z, ws), by = Date]
  dt[, interact2 := xs_zscore_local(interact_z, ws), by = Date]
  dt[, signal := 0.50 * growth_z2 + 0.30 * flow_z2 + 0.20 * interact2]
  dt
}
spec_2std <- ws_apply(copy(combo_active), 2)
specs[[1]] <- run_spec(spec_2std, "signal", "winsor_2std_composite")
spec_3std <- ws_apply(copy(combo_active), 3)
specs[[2]] <- run_spec(spec_3std, "signal", "winsor_3std_composite")
spec_4std <- ws_apply(copy(combo_active), 4)
specs[[3]] <- run_spec(spec_4std, "signal", "winsor_4std_composite")
specs[[4]] <- run_spec(combo_active, "growth_z", "growth_only")
specs[[5]] <- run_spec(combo_active, "flow_resid_z", "flow_resid_only")

specs_dt <- rbindlist(specs)
print(specs_dt)
n_pass_harvey <- sum(specs_dt$t > 3.0, na.rm = TRUE)
cat(sprintf("[Diag] 5-spec Harvey PASS count (t>3): %d/5\n", n_pass_harvey))

# ============================================================
# 7) Monotonicity (decile)
# ============================================================
combo_active_alpha <- alpha_dt[regime_state %in% c("BULL","NORMAL","CAUTION") &
                                 sleeve_w_alpha > 0][
  ret_dt, on = .(Date, Ticker), nomatch = 0L]
combo_active_alpha <- combo_active_alpha[!is.na(Ret_1m) & !is.na(alpha)]
combo_active_alpha[, decile := {
  r <- frank(alpha, ties.method = "average")
  ceiling(10 * r / .N)
}, by = Date]
mono_dt <- combo_active_alpha[!is.na(decile),
                              .(mean_ret = mean(Ret_1m, na.rm = TRUE), n = .N),
                              by = decile][order(decile)]
print(mono_dt)
mono_cor <- suppressWarnings(cor(as.numeric(mono_dt$decile),
                                  mono_dt$mean_ret, method = "spearman"))
cat(sprintf("[Diag] Monotonicity (Spearman): %.3f\n", mono_cor))

# ============================================================
# 8) Turnover proxy
# ============================================================
setorder(alpha_dt, Ticker, Date)
alpha_dt[, alpha_lag := shift(alpha, 1L), by = Ticker]
to_per_period <- alpha_dt[!is.na(alpha_lag),
                          .(turnover = mean(abs(alpha - alpha_lag), na.rm = TRUE)),
                          by = Date]
turnover_proxy <- mean(to_per_period$turnover, na.rm = TRUE)
cat(sprintf("[Diag] Turnover proxy (avg |Δalpha|): %.3f\n", turnover_proxy))

# ============================================================
# 9) Standalone SR proxy
#   Per-period IC mean / IC sd * sqrt(12) — annualized SR proxy from IC stream
# ============================================================
sr_proxy_annual <- (mean(ic_active_vec) / sd(ic_active_vec)) * sqrt(12)
cat(sprintf("[Diag] Standalone SR proxy (active, annualized from IC stream): %.3f\n", sr_proxy_annual))

sr_proxy_overall <- (mean(ic_overall_vec) / sd(ic_overall_vec)) * sqrt(12)
cat(sprintf("[Diag] Standalone SR proxy (overall, annualized): %.3f\n", sr_proxy_overall))

# ============================================================
# 10) Per-component IC (growth / flow / interact)
# ============================================================
component_ic <- list()
for (comp in c("growth_z", "flow_resid_z", "interact_z")) {
  dt_c <- combo_active[, {
    sigv <- get(comp)
    if (.N >= 30 && sd(sigv, na.rm=TRUE) > 1e-12) {
      list(rank_ic = suppressWarnings(cor(sigv, Ret_1m, method = "spearman")))
    } else list(rank_ic = NA_real_)
  }, by = Date]
  dt_c <- dt_c[!is.na(rank_ic)]
  if (nrow(dt_c) > 0) {
    component_ic[[comp]] <- list(
      mean_ic = mean(dt_c$rank_ic),
      icir    = mean(dt_c$rank_ic) / sd(dt_c$rank_ic),
      n       = nrow(dt_c),
      t_stat  = mean(dt_c$rank_ic) / (sd(dt_c$rank_ic) / sqrt(nrow(dt_c)))
    )
  }
}
cat("[Diag] Per-component IC:\n")
for (k in names(component_ic)) {
  v <- component_ic[[k]]
  cat(sprintf("  %s: IC=%.4f, ICIR=%.3f, t=%.3f, N=%d\n",
              k, v$mean_ic, v$icir, v$t_stat, v$n))
}

# ============================================================
# Save
# ============================================================
diag_summary <- list(
  task_id = WT_ID,
  ic_overall = ic_overall,
  ic_active = ic_active_summary,
  ic_by_regime = lapply(split(ic_by_regime, ic_by_regime$regime_state), as.list),
  subperiod_ic = lapply(split(subp_ic_dt, subp_ic_dt$period), as.list),
  subperiod_sign_consistency = sign_consistency,
  harvey_t_active = harvey_t,
  harvey_t_overall = harvey_t_overall,
  dsr_post_penalty = dsr,
  tdc_vs_str1700 = list(
    cross_sectional_corr_mean = mean_xs_corr,
    tdc_upper = tdc_upper,
    tdc_lower = tdc_lower,
    tdc_avg   = tdc_avg
  ),
  spec_5_robustness = lapply(split(specs_dt, specs_dt$spec), as.list),
  n_specs_harvey_pass = n_pass_harvey,
  monotonicity = mono_cor,
  turnover_proxy = turnover_proxy,
  standalone_sr_proxy_active = sr_proxy_annual,
  standalone_sr_proxy_overall = sr_proxy_overall,
  component_ic = component_ic
)

out_path <- file.path(ART_DIR, "alpha_validation.json")
write_json(diag_summary, out_path, pretty = TRUE, auto_unbox = TRUE,
           digits = 6, na = "null")
cat("[Diag] Saved diagnostics:", out_path, "\n")

write_parquet(ic_per_period, file.path(ART_DIR, "ic_per_period.parquet"))
write_parquet(specs_dt, file.path(ART_DIR, "spec_5_robustness.parquet"))
write_parquet(mono_dt, file.path(ART_DIR, "monotonicity_deciles.parquet"))

cat("[Diag] DONE.\n")
