#==============================================================================
# WT-D20260528_003 Hypothesis B Step 5 — Validation Summary + DSR + Harvey
#
# All-source validation consolidation:
#   - Rank IC + ICIR (Step 2)
#   - Harvey t-stat (Step 2)
#   - Subperiod stability (Step 2)
#   - AX-001 v2 crisis_alpha + Bad/Normal (Step 3)
#   - Decile monotonicity (Step 3)
#   - Top 20 active return + t-stat (Step 4)
#   - DSR (Deflated Sharpe Ratio): n_trials = 1 (single factor pure, no candidate selection)
#
# Graduation criteria check (request.json):
#   - min_rank_ic = 0.04
#   - min_icir = 0.2
#   - min_subperiod_stability = 0.5
#   - max_drawdown_days = 100 (DEFERRED — backtest scope)
#   - min_harvey_t_stat = 3.0
#   - min_deflated_sharpe_ratio = 0.5
#
# Output:
#   - outputs/overnight_B/m22_step5_validation.json
#   - stage_artifacts/WT_D20260528_003_overnight_B/alpha_validation.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/overnight_B")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_overnight_B")

cat("[Step 5: Validation Summary + DSR] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load all step results ----
step2 <- fromJSON(file.path(OUT_DIR, "m22_step2_ic.json"))
step3 <- fromJSON(file.path(OUT_DIR, "m22_step3_ax001v2.json"))
step4 <- fromJSON(file.path(OUT_DIR, "m22_step4_alpha.json"))

# ---- 2. Graduation criteria check ----
cat("[2] Graduation criteria check ...\n")

# Use NEUT (sector-neutralized) as primary
rank_ic <- step2$neut_summary$rank_ic_mean
icir <- step2$neut_summary$icir
harvey_t <- step2$neut_summary$t_stat
subperiod_stab <- step2$stability_ratio_min_max
monotonicity_neut <- step3$monotonicity_neut$value
top20_active_t <- step4$top20_full_period$active_t_stat

# Min graduation thresholds (from request.json)
gates <- list(
  min_rank_ic = 0.04,
  min_icir = 0.2,
  min_subperiod_stability = 0.5,
  min_harvey_t_stat = 3.0,
  min_deflated_sharpe_ratio = 0.5
)

# Compute DSR — Bailey & Lopez de Prado 2014
# DSR = SR_observed * sqrt((1-skew*SR + (kurt-1)/4 * SR^2) / (T-1))
# For single-factor pure (no candidate selection from N candidates), n_trials = 1
# So DSR ~ SR_observed (no deflation)
# However, the underlying factor M22 was selected from 269 Factor DB candidates
# (Phase 1 untapped + Phase 3 orthogonal Top12), so true n_trials >= 269
# Conservative DSR with n_trials = 269:

ic_per_date <- as.data.table(read_parquet(file.path(OUT_DIR, "m22_ic_per_date.parquet")))
ic_per_date[, Date := as.Date(Date)]
ic_neut <- ic_per_date$rank_ic_neut
ic_neut <- ic_neut[!is.na(ic_neut)]
T_n <- length(ic_neut)
SR <- mean(ic_neut) / sd(ic_neut) * sqrt(12)  # annualized "IC SR"
ic_skew <- {
  m <- mean(ic_neut); s <- sd(ic_neut)
  mean(((ic_neut - m) / s)^3)
}
ic_kurt <- {
  m <- mean(ic_neut); s <- sd(ic_neut)
  mean(((ic_neut - m) / s)^4)
}

# Sharpe ratio (annualized IC-based)
cat("    IC-based ann SR:", round(SR, 3),
    " skew:", round(ic_skew, 3),
    " kurt:", round(ic_kurt, 3),
    " T:", T_n, "\n")

# Lopez de Prado DSR formula (single trial baseline):
# DSR = Φ((SR_obs - SR_threshold) * sqrt((T-1) / (1 - skew*SR_obs + (kurt-1)/4 * SR_obs^2)))
# SR_threshold for n_trials = N: E[max SR] approximated as:
# SR_threshold ≈ sqrt(2*ln(N)) * (1 + γ) where γ = 0.5772 (Euler-Mascheroni)
# For N = 269: SR_threshold ≈ sqrt(2*ln(269)) ≈ sqrt(11.18) ≈ 3.34
# But this is z-score; convert to annualized SR requires periodicity adjustment
# Here we use SR threshold = 0 (no selection adjustment) and N=1 for transparency,
# then a second pass with N=269 for "true" DSR

n_trials_pure <- 1
n_trials_full <- 269  # Phase 1 untapped candidate set

# Adjusted "DSR" (probabilistic SR) — Bailey/Lopez de Prado 2014 eq 7
psr <- function(SR, T, skew = 0, kurt = 3, SR_star = 0) {
  num <- (SR - SR_star) * sqrt(T - 1)
  den <- sqrt(1 - skew * SR + (kurt - 1) / 4 * SR^2)
  z <- num / den
  pnorm(z)
}

# n_trials = 1 baseline
dsr_pure <- psr(SR, T_n, ic_skew, ic_kurt, SR_star = 0)

# n_trials = 269 (true selection denominator)
# SR_star for max of N: approximated as
# E[max_N SR] = sqrt(2 ln N) - (gamma + log log N) / sqrt(2 ln N), where gamma = 0.5772
g <- 0.5772
N <- n_trials_full
SR_star_n <- sqrt(2 * log(N)) - (g + log(log(N))) / sqrt(2 * log(N))
# Annualize SR threshold (per-month -> per-annum scale conversion)
# Here SR is already annualized IC-SR, so threshold in same units
dsr_selection <- psr(SR, T_n, ic_skew, ic_kurt, SR_star = SR_star_n)

cat("    DSR (n_trials=1, SR* = 0):", round(dsr_pure, 4), "\n")
cat("    DSR (n_trials=269, SR* =", round(SR_star_n, 3), "):", round(dsr_selection, 4), "\n")

# ---- 3. Gate check matrix ----
cat("\n[3] Gate check matrix:\n")

results <- list(
  rank_ic = list(value = rank_ic, threshold = gates$min_rank_ic,
                 pass = !is.na(rank_ic) && rank_ic >= gates$min_rank_ic),
  icir = list(value = icir, threshold = gates$min_icir,
              pass = !is.na(icir) && icir >= gates$min_icir),
  subperiod_stability = list(value = subperiod_stab, threshold = gates$min_subperiod_stability,
                              pass = !is.na(subperiod_stab) && subperiod_stab >= gates$min_subperiod_stability),
  harvey_t = list(value = harvey_t, threshold = gates$min_harvey_t_stat,
                  pass = !is.na(harvey_t) && abs(harvey_t) >= gates$min_harvey_t_stat),
  dsr_pure = list(value = dsr_pure, threshold = gates$min_deflated_sharpe_ratio,
                  pass = !is.na(dsr_pure) && dsr_pure >= gates$min_deflated_sharpe_ratio),
  dsr_selection = list(value = dsr_selection, threshold = gates$min_deflated_sharpe_ratio,
                       pass = !is.na(dsr_selection) && dsr_selection >= gates$min_deflated_sharpe_ratio)
)

# Auxiliary
auxiliary <- list(
  monotonicity_neut = list(value = monotonicity_neut, threshold = 0.5,
                            pass = !is.na(monotonicity_neut) && abs(monotonicity_neut) >= 0.5),
  ax_001_v2_crisis_pass = step3$ax_001_v2$ax_crisis_pass,
  ax_001_v2_bad_normal_pass = step3$ax_001_v2$ax_bad_normal_pass,
  top20_active_t = list(value = top20_active_t, threshold = 1.5,
                        pass = !is.na(top20_active_t) && abs(top20_active_t) >= 1.5)
)

for (k in names(results)) {
  r <- results[[k]]
  cat(sprintf("  %-25s %10.4f >= %5.3f -> %s\n",
              k, r$value, r$threshold,
              if (r$pass) "PASS" else "FAIL"))
}
cat("\n  Auxiliary:\n")
for (k in names(auxiliary)) {
  r <- auxiliary[[k]]
  if (is.list(r)) {
    cat(sprintf("  %-25s %10.4f >= %5.3f -> %s\n",
                k, r$value, r$threshold,
                if (r$pass) "PASS" else "FAIL"))
  } else {
    cat(sprintf("  %-25s %s\n", k, as.character(r)))
  }
}

# ---- 4. Verdict ----
graduation_pass <- all(sapply(results, function(x) x$pass))
cat("\n[4] === Graduation overall:", if (graduation_pass) "PASS" else "FAIL", "===\n")

# Failure reasons
fail_reasons <- names(results)[!sapply(results, function(x) x$pass)]
if (length(fail_reasons) > 0) {
  cat("  Failed gates:", paste(fail_reasons, collapse = ", "), "\n")
}

# ---- 5. Save validation JSON ----
cat("\n[5] Save validation ...\n")
val <- list(
  task_id = "WT-D20260528_003",
  hypothesis = "B",
  hypothesis_title = "STR_1724 Bali 2011 MAX Lottery Anomaly Pure (M22_Max_Return single-factor)",
  step = "05_validation_summary",
  as_of = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  diagnostics = list(
    rank_ic = rank_ic,
    icir = icir,
    harvey_t = harvey_t,
    subperiod_stability = subperiod_stab,
    monotonicity_neut = monotonicity_neut,
    dsr_pure_n1 = dsr_pure,
    dsr_selection_n269 = dsr_selection,
    ic_skew = ic_skew,
    ic_kurt = ic_kurt,
    ic_annualized_sr = SR,
    n_dates = T_n
  ),
  graduation_gates = gates,
  gate_results = results,
  auxiliary_checks = auxiliary,
  graduation_pass = graduation_pass,
  fail_reasons = fail_reasons,
  ax_compliance = list(
    AX_001_v2_status = "FAIL — crisis IC = -0.0195 (defensive role broken)",
    AX_005_status = "ELEVATED RISK — 2020-2026 ICIR=0.209 (decay vs 2015-2019=0.498); BAB-type 약화 가설 부분 지지",
    AX_007_status = "VIOLATION — single-sleeve top20 long-only, no exception applied",
    AX_008_status = "PENDING — requires Codex Round + downstream verification"
  ),
  top20_active = step4$top20_full_period,
  top20_subperiod = step4$top20_subperiod
)
write_json(val, file.path(OUT_DIR, "m22_step5_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: m22_step5_validation.json\n")

write_json(val, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: stage_artifacts/.../alpha_validation.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 5] === DONE === elapsed:", round(elapsed, 1), "sec\n")
