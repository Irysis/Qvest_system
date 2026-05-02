#==============================================================================
# WT-D20260502_001 Alpha Pipeline v4 — DSR + subperiod + alpha_package_draft.json
#==============================================================================

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001")
FUNC_PATH <- file.path(PROJ, "02_Infrastructure")

req <- jsonlite::fromJSON(file.path(WT_DIR, "request.json"))
state <- readRDS(file.path(SA_DIR, "alpha_pipeline_v3_state.rds"))
v2 <- readRDS(file.path(SA_DIR, "alpha_pipeline_v2_state.rds"))

diag_full <- v2$diag_full
final_factors <- state$final_factors
final_weights <- state$final_weights
combo <- state$combo
latest_panel <- state$latest_panel
current_bad_C <- state$current_bad_C
SCALE_BAD <- state$SCALE_BAD
SCALE_NORMAL <- state$SCALE_NORMAL

cat("\n==== STEP 4-EXT: Subperiod Stability + DSR ====\n")

# Re-load IC history per factor + composite
winsor_panel <- v2$winsor_panel
winsor_panel[, defense_composite := 0]
for (f in final_factors) {
  if (f %in% colnames(winsor_panel)) {
    winsor_panel[, defense_composite := defense_composite +
                  fifelse(is.na(get(f)), 0, get(f)) * final_weights[[f]]]
  }
}
n_avail <- winsor_panel[, rowSums(!is.na(.SD)), .SDcols = final_factors]
winsor_panel[n_avail == 0, defense_composite := NA_real_]

compute_ic <- function(dt, factor_col) {
  if (!factor_col %in% colnames(dt)) return(NULL)
  dt[, .(
    n = sum(!is.na(get(factor_col)) & !is.na(fwd_ret)),
    ic = if (sum(!is.na(get(factor_col)) & !is.na(fwd_ret)) >= 30) {
      cor(get(factor_col), fwd_ret, method = "spearman", use = "pairwise.complete.obs")
    } else { NA_real_ }
  ), by = sig_date][!is.na(ic)]
}
nw_t_stat <- function(ic_vec, lag = 3) {
  m <- length(ic_vec); ic_vec <- ic_vec[!is.na(ic_vec)]; m <- length(ic_vec)
  if (m < 5) return(NA_real_)
  mu <- mean(ic_vec); v0 <- mean((ic_vec - mu)^2)
  bw <- min(lag, floor(m/4))
  if (bw >= 1) {
    s <- 0
    for (l in 1:bw) {
      w_l <- 1 - l / (bw + 1)
      cov_l <- mean((ic_vec[1:(m - l)] - mu) * (ic_vec[(l + 1):m] - mu))
      s <- s + 2 * w_l * cov_l
    }
    nw_var <- v0 + s
  } else { nw_var <- v0 }
  nw_se <- sqrt(max(nw_var, 1e-12) / m)
  mu / nw_se
}

ic_dt <- compute_ic(winsor_panel, "defense_composite")
ic_dt[, subp := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2008-2013",
  sig_date < as.Date("2020-01-01"), "P2_2014-2019",
  default = "P3_2020-2026"
)]

# Subperiod stability
sub_stats <- ic_dt[, .(
  ic_mean = mean(ic, na.rm = TRUE),
  ic_std = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE),
  n = .N,
  pos_share = mean(ic > 0, na.rm = TRUE)
), by = subp]
cat("Subperiod stability of composite:\n")
print(sub_stats)

# Pass: count subperiods with ic_mean > 0 / total
sub_pos_count <- sum(sub_stats$ic_mean > 0, na.rm = TRUE)
sub_stab_score <- sub_pos_count / nrow(sub_stats)
cat(sprintf("Subperiod stability score: %.2f (%d/%d periods positive)\n",
            sub_stab_score, sub_pos_count, nrow(sub_stats)))

# DSR (Deflated Sharpe Ratio, Bailey-Lopez de Prado 2014) — TWO views:
#
# View A: IC time series DSR (predictive correlation Sharpe analog)
#  - SR_IC = mean(IC) / sd(IC) for monthly IC series
#  - This is "how stable is the predictive correlation"
#
# View B: LS portfolio DSR (actual strategy Sharpe analog)
#  - SR_LS = annualized Sharpe of long-short quintile portfolio
#  - Dual: full-period LS + bad-state-only gated LS
#
# We report ALL THREE for transparency. The "true" alpha SR is the gated portfolio
# (since the strategy only activates in bad-state).

M_TRIALS <- 7L
gamma_em <- 0.5772156649

# Helper: Bailey-Lopez de Prado (2014) DSR computation (CORRECT formulation)
#  - exp_max_z = expected max Z-score under M iid Gaussian SR_null draws
#  - SR_observed has standard error sqrt((1 - skew*SR + (kurt-1)/4 * SR^2) / (N-1))
#  - DSR = pnorm( (SR_observed - exp_max_z * SR_se) / SR_se )
# Note: exp_max_z is in units of SR_se (Z-score). Convert to SR threshold by
#       SR_threshold = exp_max_z * SR_se.
bld_dsr <- function(sr, n_obs, skew, kurt, M = M_TRIALS) {
  exp_max_z <- (1 - gamma_em) * qnorm(1 - 1/M) +
               gamma_em * qnorm(1 - 1/(M*exp(1)))
  sr_se <- sqrt(max(1 - skew * sr + ((kurt - 1)/4) * sr^2, 1e-9) / max(n_obs - 1, 1))
  exp_max_sr <- exp_max_z * sr_se  # in SR units
  dsr_z <- (sr - exp_max_sr) / sr_se
  dsr_p <- pnorm(dsr_z)
  list(sr = sr, sr_se = sr_se,
       exp_max_z = exp_max_z, exp_max_sr = exp_max_sr,
       dsr_z = dsr_z, dsr_p = dsr_p, n_obs = n_obs)
}

# View A: IC time series
ic_vec <- ic_dt$ic
n_obs_ic <- length(ic_vec)
sr_ic_monthly <- mean(ic_vec) / sd(ic_vec)
ic_skew <- mean((ic_vec - mean(ic_vec))^3) / sd(ic_vec)^3
ic_kurt <- mean((ic_vec - mean(ic_vec))^4) / sd(ic_vec)^4
viewA <- bld_dsr(sr_ic_monthly, n_obs_ic, ic_skew, ic_kurt)
cat(sprintf("\n[View A] DSR on IC time series (M=%d trials):\n", M_TRIALS))
cat(sprintf("  SR_IC_monthly=%.4f n=%d skew=%.3f kurt=%.3f SR_se=%.4f\n",
            viewA$sr, viewA$n_obs, ic_skew, ic_kurt, viewA$sr_se))
cat(sprintf("  E[max_z|null,M=%d]=%.4f → SR_threshold=%.4f → DSR_p=%.4f\n",
            M_TRIALS, viewA$exp_max_z, viewA$exp_max_sr, viewA$dsr_p))

# View B1: LS full-period portfolio (annualized SR)
ls_full <- combo$ls_ret
n_ls <- length(ls_full)
sr_ls_full_monthly <- mean(ls_full) / sd(ls_full)
ls_skew <- mean((ls_full - mean(ls_full))^3) / sd(ls_full)^3
ls_kurt <- mean((ls_full - mean(ls_full))^4) / sd(ls_full)^4
ls_sr_full_ann <- sr_ls_full_monthly * sqrt(12)
viewB1 <- bld_dsr(sr_ls_full_monthly, n_ls, ls_skew, ls_kurt)
cat(sprintf("\n[View B1] DSR on LS portfolio (full period, top-bot quintile):\n"))
cat(sprintf("  SR_LS_monthly=%.4f annualized=%.3f n=%d\n",
            viewB1$sr, ls_sr_full_ann, n_ls))
cat(sprintf("  E[max_z|null]=%.4f → SR_threshold=%.4f → DSR_p=%.4f\n",
            viewB1$exp_max_z, viewB1$exp_max_sr, viewB1$dsr_p))

# View B2: Gated LS portfolio (bad-state only)
gated_active <- combo[def_C_bad == TRUE]
if (nrow(gated_active) > 5) {
  gated_ls <- gated_active$ls_ret
  n_gated <- length(gated_ls)
  sr_gated_monthly <- mean(gated_ls) / sd(gated_ls)
  gated_skew <- mean((gated_ls - mean(gated_ls))^3) / sd(gated_ls)^3
  gated_kurt <- mean((gated_ls - mean(gated_ls))^4) / sd(gated_ls)^4
  gated_sr_ann <- sr_gated_monthly * sqrt(12)
  viewB2 <- bld_dsr(sr_gated_monthly, n_gated, gated_skew, gated_kurt)
  cat(sprintf("\n[View B2] DSR on gated LS portfolio (bad-state only, n=%d):\n", n_gated))
  cat(sprintf("  SR_gated_monthly=%.4f annualized=%.3f\n", viewB2$sr, gated_sr_ann))
  cat(sprintf("  E[max_z|null]=%.4f → SR_threshold=%.4f → DSR_p=%.4f\n",
              viewB2$exp_max_z, viewB2$exp_max_sr, viewB2$dsr_p))
} else {
  viewB2 <- list(sr = NA, sr_se = NA, exp_max_z = NA, exp_max_sr = NA,
                 dsr_z = NA, dsr_p = NA, n_obs = 0)
  gated_sr_ann <- NA
}

# Primary DSR for graduation evaluation: View B2 (gated, the strategy's actual operating mode)
# but we are honest about what we're measuring.
dsr <- viewB2$dsr_p
sr_observed <- viewB2$sr
expected_max <- viewB2$exp_max_sr
ls_sr <- ls_sr_full_ann

cat(sprintf("\nPrimary DSR (View B2 gated bad-state portfolio): %.4f\n", dsr))
cat(sprintf("  Threshold 0.5: %s\n", ifelse(dsr >= 0.5, "PASS", "FAIL")))

#=== Subperiod-conditional IC ==================================================
cat("\n==== Subperiod × Regime conditional IC ====\n")
# Bad/normal split per subperiod
bad_dates_C <- unique(winsor_panel[def_C_bad == TRUE, sig_date])
ic_dt[, bad_C := sig_date %in% bad_dates_C]
sub_reg <- ic_dt[, .(
  n = .N,
  ic_mean = mean(ic, na.rm = TRUE),
  ic_std = sd(ic, na.rm = TRUE)
), by = .(subp, bad_C)]
cat("Composite IC by subperiod × regime:\n")
print(sub_reg)

#=== Save final state to be used in alpha_package_draft.json ==================
cat("\n==== Saving v4 finalize state ====\n")

# Read v3 saved alpha_validation.json to add subperiod + DSR
av_path <- file.path(SA_DIR, "alpha_validation.json")
av <- jsonlite::fromJSON(av_path, simplifyVector = FALSE)
av$subperiod_analysis <- list(
  subperiods = lapply(seq_len(nrow(sub_stats)), function(i) {
    list(
      period = as.character(sub_stats$subp[i]),
      ic_mean = round(sub_stats$ic_mean[i], 4),
      icir = round(sub_stats$icir[i], 4),
      n_periods = sub_stats$n[i],
      positive_share = round(sub_stats$pos_share[i], 4)
    )
  }),
  pos_share_score = round(sub_stab_score, 4),
  pos_count = sub_pos_count,
  total_periods = nrow(sub_stats),
  pass_threshold_05 = sub_stab_score >= 0.5
)
av$dsr_analysis <- list(
  m_trials = M_TRIALS,
  view_A_ic_time_series = list(
    sr_monthly = round(viewA$sr, 4),
    sr_annualized = round(viewA$sr * sqrt(12), 4),
    sr_se = round(viewA$sr_se, 4),
    n_obs = viewA$n_obs,
    skewness = round(ic_skew, 4),
    kurtosis = round(ic_kurt, 4),
    expected_max_z = round(viewA$exp_max_z, 4),
    expected_max_sr = round(viewA$exp_max_sr, 4),
    dsr_probability = round(viewA$dsr_p, 4)
  ),
  view_B1_ls_full_period = list(
    sr_monthly = round(viewB1$sr, 4),
    sr_annualized = round(ls_sr_full_ann, 4),
    sr_se = round(viewB1$sr_se, 4),
    n_obs = viewB1$n_obs,
    skewness = round(ls_skew, 4),
    kurtosis = round(ls_kurt, 4),
    expected_max_sr = round(viewB1$exp_max_sr, 4),
    dsr_probability = round(viewB1$dsr_p, 4)
  ),
  view_B2_ls_gated_badstate_only = list(
    sr_monthly = round(viewB2$sr, 4),
    sr_annualized = round(gated_sr_ann, 4),
    sr_se = round(viewB2$sr_se, 4),
    n_obs = viewB2$n_obs,
    expected_max_sr = round(viewB2$exp_max_sr, 4),
    dsr_probability = round(viewB2$dsr_p, 4)
  ),
  primary_dsr_view = "B2_gated",
  primary_dsr_value = round(dsr, 4),
  pass_threshold_05 = dsr >= 0.5,
  note = paste0("DSR computed three ways for transparency. View B2 (gated bad-state ",
                "portfolio) is primary because the strategy only activates in bad-state. ",
                "View A (IC) and B1 (full-period LS) provided for context.")
)

# Per-period × regime conditional analysis
av$subperiod_regime_conditional <- lapply(seq_len(nrow(sub_reg)), function(i) {
  list(
    subperiod = as.character(sub_reg$subp[i]),
    regime_bad = sub_reg$bad_C[i],
    n_periods = sub_reg$n[i],
    ic_mean = round(sub_reg$ic_mean[i], 4)
  )
})

# Graduation criteria evaluation
av$graduation_criteria_evaluation <- list(
  rank_ic = list(threshold = 0.04, achieved = round(av$composite$rank_ic, 4),
                 pass = av$composite$rank_ic >= 0.04),
  icir = list(threshold = 0.20, achieved = round(av$composite$icir, 4),
              pass = av$composite$icir >= 0.20),
  subperiod_stability = list(threshold = 0.5, achieved = round(sub_stab_score, 4),
                              pass = sub_stab_score >= 0.5),
  harvey_t_stat = list(threshold = 3.0, achieved = round(av$composite$nw_t, 4),
                       pass = av$composite$nw_t >= 3.0),
  deflated_sharpe_ratio = list(threshold = 0.5, achieved = round(dsr, 4),
                                pass = dsr >= 0.5)
)

write_json(av, av_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("alpha_validation.json: updated\n"))

# Save v4 state
saveRDS(list(
  sub_stats = sub_stats, sub_stab_score = sub_stab_score, sub_pos_count = sub_pos_count,
  dsr = dsr, sr_observed = sr_observed, expected_max = expected_max,
  ic_skew = ic_skew, ic_kurt = ic_kurt, M_TRIALS = M_TRIALS,
  ls_sr = ls_sr, sub_reg = sub_reg, ic_vec = ic_vec
), file.path(SA_DIR, "alpha_pipeline_v4_state.rds"))

cat(sprintf("\nGraduation criteria evaluation:\n"))
for (k in names(av$graduation_criteria_evaluation)) {
  e <- av$graduation_criteria_evaluation[[k]]
  cat(sprintf("  %s: %.4f vs %.4f → %s\n",
              k, e$achieved, e$threshold, ifelse(e$pass, "PASS", "FAIL")))
}

cat("\n==== v4 finalize COMPLETE ====\n")
