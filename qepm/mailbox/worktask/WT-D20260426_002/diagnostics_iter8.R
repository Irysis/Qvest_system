#==============================================================================
# WT-D20260426_002 Iter 8 Alpha Diagnostics
#
# Goals:
#  1) Regime-conditional Rank IC + ICIR (BULL / NORMAL / CAUTION / CRISIS / overall)
#  2) Subperiod stability (2008-14 / 2015-19 / 2020-23)
#  3) Harvey t-stat (BULL+NORMAL only — alpha != 0 sample)
#  4) DSR (multi-test 보정)
#  5) TDC vs STR_1700 alpha
#  6) 5-spec robustness (winsor 2/3/4 std × neutralization on/off × subset)
#  7) Monotonicity (decile sorting)
#  8) Turnover proxy
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID    <- "WT-D20260426_002"
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_002")
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)

# ---- Load alpha + STR_1700 + returns ----
alpha_dt <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
setkey(alpha_dt, Date, Ticker)

str1700 <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet"))
setkey(str1700, Date, Ticker)

# ---- Returns: STR_1700 has Ret_1m forward; reuse ----
ret_dt <- str1700[, .(Date, Ticker, Ret_1m)]
setkey(ret_dt, Date, Ticker)

# ---- Merge alpha + return + STR_1700 alpha ----
combo <- alpha_dt[ret_dt, nomatch = 0L]
combo <- combo[str1700[, .(Date, Ticker, alpha_str1700 = score_eff)],
               on = .(Date, Ticker), nomatch = 0L]
combo <- combo[!is.na(Ret_1m) & !is.na(alpha) & !is.na(alpha_str1700)]
cat("[Diag] Merged rows:", nrow(combo), "\n")
cat("[Diag] uniq Dates:", length(unique(combo$Date)),
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

# CAUTION/CRISIS는 alpha=0 → IC undefined (NaN). Filter logic: 분명히 alpha=0
# 인 sample에서 cor(alpha, ret) = NaN이므로 위에서 제외됨. BULL/NORMAL only sample
# 이 진짜 의미 있는 sample.
ic_active <- ic_per_period[regime_state %in% c("BULL", "NORMAL")]
ic_active_summary <- list(
  rank_ic_mean = mean(ic_active$rank_ic),
  rank_ic_sd   = sd(ic_active$rank_ic),
  icir         = mean(ic_active$rank_ic) / sd(ic_active$rank_ic),
  n_periods    = nrow(ic_active)
)
cat(sprintf("[Diag] Active (BULL+NORMAL): rank_IC=%.4f, ICIR=%.3f, N=%d\n",
            ic_active_summary$rank_ic_mean, ic_active_summary$icir,
            ic_active_summary$n_periods))

# ============================================================
# 2) Subperiod stability
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
    rank_ic = mean(sub$rank_ic),
    icir = mean(sub$rank_ic) / sd(sub$rank_ic)
  )
})
subp_ic_dt <- rbindlist(subp_ic)
print(subp_ic_dt)

# stability = signed (sign 일관성) — same sign 비율
sign_consistency <- mean(sign(subp_ic_dt$rank_ic) == sign(ic_overall$rank_ic_mean),
                         na.rm = TRUE)
cat(sprintf("[Diag] Subperiod sign consistency: %.2f\n", sign_consistency))

# ============================================================
# 3) Harvey t-stat (BULL+NORMAL only — alpha != 0 sample)
# ============================================================
# Per-period IC -> t-stat = mean / (sd / sqrt(N))
ic_active_vec <- ic_active$rank_ic
harvey_t <- mean(ic_active_vec) / (sd(ic_active_vec) / sqrt(length(ic_active_vec)))
cat(sprintf("[Diag] Harvey t-stat (BULL+NORMAL active): %.3f\n", harvey_t))

# ============================================================
# 4) DSR (Bailey-Lopez de Prado)
# bootstrap_dsr_fast 시도; 없으면 R fallback
# ============================================================
# Per-period IC를 returns surrogate로 사용
returns_for_dsr <- ic_active_vec
n_trials <- 5L  # 5-spec robustness 후보 수

mu <- mean(returns_for_dsr)
s  <- sd(returns_for_dsr)
n  <- length(returns_for_dsr)
sr_obs <- mu / s
# skew + kurtosis adjustment
m3 <- mean((returns_for_dsr - mu)^3) / s^3
m4 <- mean((returns_for_dsr - mu)^4) / s^4
sr_var <- (1 - m3 * sr_obs + ((m4 - 1) / 4) * sr_obs^2) / (n - 1)
sr_std <- sqrt(max(sr_var, 1e-12))
# expected max SR under H0 (Bailey 2014)
emc <- 0.5772156649  # Euler-Mascheroni
e_max <- (1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials * exp(1)))
dsr <- pnorm((sr_obs - e_max * sr_std) / sr_std)
cat(sprintf("[Diag] DSR (active sample, %d trials): %.3f\n", n_trials, dsr))

# ============================================================
# 5) TDC vs STR_1700 alpha — Tail Dependence Coefficient
# ============================================================
# Per-period correlation of alpha vs alpha_str1700 (cross-sectional)
# Then time-series TDC of these correlations? 더 의미 있는 측정:
# Per-ticker-month alpha series correlation overall
# Approach: monthly cross-sectional rank correlation, then time-mean of |rho|
# 그리고 tail comovement: 양 alpha 모두 hi-decile 동시 진입 비율
xs_corr <- combo[, .(rho = if (.N >= 30) suppressWarnings(cor(alpha, alpha_str1700, method = "spearman")) else NA_real_),
                 by = Date]
xs_corr <- xs_corr[!is.na(rho)]
mean_xs_corr <- mean(xs_corr$rho)
cat(sprintf("[Diag] Mean cross-sectional rank corr vs STR_1700: %.4f\n", mean_xs_corr))

# Tail dependence: P(both in top 20%) — 둘 다 top quintile 동시 진입 비율
# Date별 quintile 계산 — frank 사용 (quantile breaks dup 회피)
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
# tdc_upper = P(STR top | alpha top)
combo[, both_bot := q_alpha == 1 & q_str == 1]
combo[, marginal_bot := q_alpha == 1]
tdc_lower <- combo[, sum(both_bot, na.rm=TRUE) / pmax(sum(marginal_bot, na.rm=TRUE), 1)]
cat(sprintf("[Diag] TDC upper (top quintile co-occurrence): %.3f\n", tdc_upper))
cat(sprintf("[Diag] TDC lower (bot quintile co-occurrence): %.3f\n", tdc_lower))
tdc_avg <- (tdc_upper + tdc_lower) / 2
cat(sprintf("[Diag] TDC avg: %.3f (target < 0.30)\n", tdc_avg))

# ============================================================
# 6) 5-spec Harvey robustness
# Spec1: winsor 2std
# Spec2: winsor 3std (baseline)
# Spec3: winsor 4std
# Spec4: top500 universe (high-liquidity restriction)
# Spec5: BULL only (regime stricter)
# ============================================================
# Compute IC per spec, take t-stat
specs <- list()

# We need raw z_amihud per Date; alpha_dt has it
alpha_raw <- alpha_dt[, .(Date, Ticker, z = z_amihud, regime_state, sleeve_w_liq)]
combo_raw <- alpha_raw[ret_dt, nomatch = 0L]
combo_raw <- combo_raw[!is.na(Ret_1m) & !is.na(z)]

# Restrict to BULL+NORMAL active dates (where sleeve_w_liq > 0)
combo_active <- combo_raw[sleeve_w_liq > 0]

run_spec <- function(dt, label) {
  ic_v <- dt[, .(rank_ic = if (.N >= 30) suppressWarnings(cor(z, Ret_1m, method = "spearman")) else NA_real_),
             by = Date]
  ic_v <- ic_v[!is.na(rank_ic)]
  if (nrow(ic_v) < 5) return(data.table(spec = label, ic = NA_real_, t = NA_real_, n = nrow(ic_v)))
  t_stat <- mean(ic_v$rank_ic) / (sd(ic_v$rank_ic) / sqrt(nrow(ic_v)))
  data.table(spec = label,
             ic = mean(ic_v$rank_ic),
             t  = t_stat,
             n  = nrow(ic_v))
}

# Spec1: winsor 2std applied (recompute z winsorized 2std)
spec_2std <- copy(combo_active)
spec_2std[, z := {
  m <- median(z, na.rm=TRUE); s <- sd(z, na.rm=TRUE)
  pmin(pmax(z, m - 2*s), m + 2*s)
}, by = Date]
specs[[1]] <- run_spec(spec_2std, "winsor_2std")

# Spec2: 3std (baseline = same as alpha)
spec_3std <- copy(combo_active)
spec_3std[, z := {
  m <- median(z, na.rm=TRUE); s <- sd(z, na.rm=TRUE)
  pmin(pmax(z, m - 3*s), m + 3*s)
}, by = Date]
specs[[2]] <- run_spec(spec_3std, "winsor_3std")

# Spec3: 4std
spec_4std <- copy(combo_active)
spec_4std[, z := {
  m <- median(z, na.rm=TRUE); s <- sd(z, na.rm=TRUE)
  pmin(pmax(z, m - 4*s), m + 4*s)
}, by = Date]
specs[[3]] <- run_spec(spec_4std, "winsor_4std")

# Spec4: top500 high-liquidity (restrict by Date — top 500 by abs(z)? 안 됨 → use raw count)
# 대신: top 500 by Ticker frequency in entire sample
ticker_cnt <- combo_active[, .N, by = Ticker]
top500 <- ticker_cnt[order(-N)][1:500, Ticker]
spec_top500 <- combo_active[Ticker %in% top500]
specs[[4]] <- run_spec(spec_top500, "top500_universe")

# Spec5: BULL only
spec_bull <- combo_active[regime_state == "BULL"]
specs[[5]] <- run_spec(spec_bull, "BULL_only")

specs_dt <- rbindlist(specs)
print(specs_dt)
n_pass_harvey <- sum(specs_dt$t > 3.0, na.rm = TRUE)
cat(sprintf("[Diag] 5-spec Harvey PASS count (t>3): %d/5\n", n_pass_harvey))

# ============================================================
# 7) Monotonicity (decile sort over BULL+NORMAL active)
# ============================================================
combo_active_alpha <- alpha_dt[regime_state %in% c("BULL","NORMAL")][
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
# Monotonicity: Spearman correlation of decile-rank vs decile-mean-return
mono_cor <- suppressWarnings(cor(as.numeric(mono_dt$decile),
                                  mono_dt$mean_ret, method = "spearman"))
cat(sprintf("[Diag] Monotonicity (Spearman): %.3f\n", mono_cor))

# ============================================================
# 8) Turnover proxy (rank changes month-over-month)
# ============================================================
setorder(alpha_dt, Ticker, Date)
alpha_dt[, alpha_lag := shift(alpha, 1L), by = Ticker]
to_per_period <- alpha_dt[!is.na(alpha_lag),
                          .(turnover = mean(abs(alpha - alpha_lag), na.rm = TRUE)),
                          by = Date]
turnover_proxy <- mean(to_per_period$turnover, na.rm = TRUE)
cat(sprintf("[Diag] Turnover proxy (avg |Δalpha|): %.3f\n", turnover_proxy))

# ============================================================
# Save diagnostics
# ============================================================
diag_summary <- list(
  task_id = WT_ID,
  ic_overall = ic_overall,
  ic_active_BULLNORMAL = ic_active_summary,
  ic_by_regime = lapply(split(ic_by_regime, ic_by_regime$regime_state), as.list),
  subperiod_ic = lapply(split(subp_ic_dt, subp_ic_dt$period), as.list),
  subperiod_sign_consistency = sign_consistency,
  harvey_t_active = harvey_t,
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
  turnover_proxy = turnover_proxy
)

out_path <- file.path(ART_DIR, "alpha_validation.json")
write_json(diag_summary, out_path, pretty = TRUE, auto_unbox = TRUE,
           digits = 6, na = "null")
cat("[Diag] Saved diagnostics:", out_path, "\n")

# Save summary CSV for codex
write_parquet(ic_per_period, file.path(ART_DIR, "ic_per_period.parquet"))
write_parquet(specs_dt, file.path(ART_DIR, "spec_5_robustness.parquet"))
write_parquet(mono_dt, file.path(ART_DIR, "monotonicity_deciles.parquet"))

cat("[Diag] DONE.\n")
