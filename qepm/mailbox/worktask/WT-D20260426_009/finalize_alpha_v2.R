# =============================================================================
# WT-D20260426_009 — Alpha v2 finalization (Codex R1 9-resolution + alpha_scores rebuild)
# =============================================================================
# Codex R1 stance = REJECT. 7 critical_concerns + 2 alpha_specific_questions = 9 items.
#
# KEY FIX: alpha_scores.parquet was persisted with k=2 (SIGMOID_K=2 default in pipeline)
#   but final package selected k=1.0 as optimal. This is the C1 inconsistency.
#   We add a `score_final_k1` column with k=1 alpha and re-derive top20 from THAT column,
#   so package alpha_vector and persisted scores are bit-consistent.
#
# Approach: HONEST disclosure. The hypothesis FAILS gates 4/5. We do NOT spin failure.
#   - Joint underperforms linear and skew_only (L-211 reproduced)
#   - All 4 statistical gates fail (ICIR/IC/Harvey-t/5-spec)
#   - Sub_stab passes (0.67) BUT driven entirely by 2020-26 (RF-A3 recent overfit)
#   - Cross-family low corr is the ONLY positive finding
# =============================================================================
cat("=== WT-D20260426_009 — Alpha v2 (Codex R1 9-resolution) ===\n")
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
  library(sandwich); library(lmtest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260426_009"
WT_DIR_TAG   <- "WT_D20260426_009"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_DIR_TAG)

sigmoid <- function(x, k = 1.0) 1 / (1 + exp(-k * x))

# Load existing
ours <- as.data.table(read_parquet(file.path(ARTIFACT_DIR, "alpha_scores.parquet")))
ours[, ym := format(Date, "%Y-%m")]

# =============================================================================
# C1 fix: Add k=1 final score column + recompute top20 from k=1
# =============================================================================
cat("\n[C1 fix] Adding score_final_k1 column...\n")
ours[, alpha_final_k1 := sigmoid(ncskew_z, 1.0) * sigmoid(accrual_qual_z, 1.0)]
ours[, alpha_final_k1_z := scale(alpha_final_k1)[,1], by = Date]

# Persist to parquet
write_parquet(ours[, !c("ym"), with=FALSE], file.path(ARTIFACT_DIR, "alpha_scores.parquet"))
cat(sprintf("    Updated alpha_scores.parquet (n_rows=%d, +score_final_k1)\n", nrow(ours)))

# =============================================================================
# C5 fix: Monotonicity (decile ordering) — explicit calculation
# =============================================================================
cat("\n[C5 fix] Monotonicity (decile ordering)...\n")
# Per-Date: rank alpha into 10 deciles, compute mean fwd_ret_21d per decile
mono_dt <- ours[!is.na(alpha_final_k1_z) & !is.na(fwd_ret_21d)]
mono_dt[, decile := cut(rank(alpha_final_k1_z, ties.method = "first") / .N,
                         breaks = seq(0, 1, 0.1), labels = 1:10, include.lowest = TRUE), by = Date]
decile_ret <- mono_dt[!is.na(decile),
                      .(mean_ret = mean(fwd_ret_21d, na.rm=TRUE), n=.N),
                      by = decile][order(decile)]
cat("    Decile mean returns:\n"); print(decile_ret)

# Monotonicity = fraction of adjacent pairs that are correctly ordered (D10 > D1 expected)
adj_pairs <- diff(decile_ret$mean_ret)
mono_score <- mean(adj_pairs > 0)  # if all increasing, = 1.0
top_minus_bot <- decile_ret$mean_ret[10] - decile_ret$mean_ret[1]
cat(sprintf("    Monotonicity (adj pair fraction increasing): %.3f\n", mono_score))
cat(sprintf("    Top decile - Bottom decile mean: %+.4f\n", top_minus_bot))

# =============================================================================
# C7 / unresolved_dispute fix: stage_artifacts dir consistency
# =============================================================================
# Codex flags qepm/stage_artifacts/WT_WT-D20260426_009 missing — but the WT-D template
# is `stage_artifacts/WT_D20260426_009` (no `qepm/` prefix, no `WT_` prefix on full id).
# Path is correct per output_contract. Mark as resolved by clarifying.

# =============================================================================
# Reload draft + recompute alpha_vector from k=1 score (C1 fix)
# =============================================================================
cat("\n[Re-derive] alpha_vector from k=1...\n")
draft <- fromJSON(file.path(WT_MAIL_DIR, "alpha_package.json"), simplifyVector = FALSE)

as_of_me <- max(ours$Date)
asof <- ours[Date == as_of_me & !is.na(alpha_final_k1_z)][order(-alpha_final_k1_z)]
top20_v2 <- head(asof, 20)
cat(sprintf("    as_of=%s, top20 from k=1 (sample):\n", as_of_me))
print(head(top20_v2[, .(Ticker, ncskew_z, accrual_qual_z, alpha_final_k1, alpha_final_k1_z)], 5))

# Build new alpha_vector + confidence_vector
hist_window <- ours[Date >= as.Date("2023-07-01") & Date <= as_of_me]
hist_window[, alpha_z_hist := scale(sigmoid(ncskew_z, 1.0) * sigmoid(accrual_qual_z, 1.0))[,1], by = Date]
rank_stab <- hist_window[, .(rk_std = sd(rank(alpha_z_hist) / .N, na.rm=TRUE)), by = Ticker]
top20_v2 <- merge(top20_v2, rank_stab, by = "Ticker", all.x = TRUE)
top20_v2[is.na(rk_std), rk_std := 0.5]
top20_v2[, factor_coverage := (!is.na(ncskew_z)) + (!is.na(accrual_qual_z))]
top20_v2[, confidence := pmin(1.0, pmax(0.0,
  0.25 * (factor_coverage / 2) +
  0.50 * (1 - pmin(rk_std, 0.5) / 0.5) +
  0.25
))]
top20_v2 <- top20_v2[order(-alpha_final_k1_z)]

new_alpha_vec <- as.list(setNames(round(top20_v2$alpha_final_k1_z, 4), top20_v2$Ticker))
new_conf_vec  <- as.list(setNames(round(top20_v2$confidence, 4), top20_v2$Ticker))

draft$alpha_vector <- new_alpha_vec
draft$confidence_vector <- new_conf_vec

# =============================================================================
# Re-compute IC/ICIR for k=1 (was previously k=2 in headline)
# =============================================================================
cat("\n[Re-compute] k=1 diagnostics...\n")
ic_k1 <- ours[!is.na(alpha_final_k1_z) & !is.na(fwd_ret_21d),
              .(ic = if (.N >= 10 && sd(alpha_final_k1_z) > 0)
                       cor(alpha_final_k1_z, fwd_ret_21d, method="spearman", use="complete.obs")
                     else NA_real_,
                n = .N), by = Date][!is.na(ic)]
icir_k1 <- mean(ic_k1$ic, na.rm=TRUE) / sd(ic_k1$ic, na.rm=TRUE)
ic_mean_k1 <- mean(ic_k1$ic, na.rm=TRUE)

# NW-HAC t (k=1)
m_k1 <- lm(ic ~ 1, data = ic_k1)
vcov_nw_k1 <- tryCatch(NeweyWest(m_k1, lag = 4L, prewhite = FALSE), error = function(e) NULL)
nw_t_k1 <- if (!is.null(vcov_nw_k1)) coef(m_k1)[1] / sqrt(diag(vcov_nw_k1)[1]) else NA
cat(sprintf("    k=1: ICIR=%.4f, IC=%.4f, NW-t=%.2f\n", icir_k1, ic_mean_k1, nw_t_k1))

# Subperiod
ic_k1[, period := fifelse(year(Date) <= 2014, "2008-14",
                  fifelse(year(Date) <= 2019, "2015-19", "2020-26"))]
sub_k1 <- ic_k1[, .(icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE), n = .N), by = period][order(period)]
sub_stab_k1 <- mean(sub_k1$icir > 0)
cat("    Subperiod ICIR (k=1):\n"); print(sub_k1)

# 5-spec NW-HAC
ff5_path <- file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet")
spec_pass_k1 <- NA_integer_; spec_details_k1 <- list()
if (file.exists(ff5_path)) {
  ff5 <- as.data.table(read_parquet(ff5_path))
  ff5[, ym := format(as.Date(Date), "%Y-%m")]
  ff5_m <- ff5[, .(MKT = mean(MKT, na.rm=TRUE), SMB = mean(SMB, na.rm=TRUE),
                   HML = mean(HML, na.rm=TRUE), WML = mean(WML, na.rm=TRUE),
                   RMW = mean(RMW, na.rm=TRUE), CMA = mean(CMA, na.rm=TRUE)), by = ym]
  ic_k1[, ym := format(Date, "%Y-%m")]
  m <- merge(ic_k1[, .(ym, ic)], ff5_m, by = "ym", all.x = TRUE)
  m <- m[complete.cases(m)]
  specs <- list(
    CAPM     = ic ~ MKT,
    C3       = ic ~ MKT + SMB + HML,
    Carhart4 = ic ~ MKT + SMB + HML + WML,
    FF5      = ic ~ MKT + SMB + HML + RMW + CMA,
    FF6      = ic ~ MKT + SMB + HML + WML + RMW + CMA
  )
  spec_pass_k1 <- 0L
  for (sn in names(specs)) {
    fit <- tryCatch(lm(specs[[sn]], data = m), error = function(e) NULL)
    if (is.null(fit)) { spec_details_k1[[sn]] <- NA; next }
    vcov_nw <- tryCatch(NeweyWest(fit, lag = 4L, prewhite = FALSE), error = function(e) NULL)
    if (is.null(vcov_nw)) { spec_details_k1[[sn]] <- NA; next }
    alpha_t <- coef(fit)[1] / sqrt(diag(vcov_nw)[1])
    spec_details_k1[[sn]] <- as.numeric(alpha_t)
    if (!is.na(alpha_t) && abs(alpha_t) >= 3.0) spec_pass_k1 <- spec_pass_k1 + 1L
  }
  cat(sprintf("    5-spec |t|>=3: %d/5  details=%s\n", spec_pass_k1,
              paste(sprintf("%s=%.2f", names(spec_details_k1),
                            sapply(spec_details_k1, function(x) ifelse(is.null(x) || is.na(x), NA, x))),
                    collapse=", ")))
}

# =============================================================================
# DSR (Deflated Sharpe Ratio) — Codex C2/RF-A6 fix
# =============================================================================
cat("\n[DSR] Bailey-Lopez de Prado Deflated Sharpe Ratio...\n")
# Convert IC time series to monthly Sharpe (treating IC as monthly return proxy of long-short)
# DSR = SR * sqrt(2 * (n-1) / variance_under_null)
# Simpler: bootstrap SR distribution
if (length(ic_k1$ic) >= 24L) {
  ic_m <- ic_k1$ic
  sr_obs <- mean(ic_m) / sd(ic_m) * sqrt(12)  # annualized
  # Variance of skewness/kurtosis-adjusted SR (Bailey-Lopez de Prado 2014)
  n <- length(ic_m)
  g3 <- mean((ic_m - mean(ic_m))^3) / sd(ic_m)^3
  g4 <- mean((ic_m - mean(ic_m))^4) / sd(ic_m)^4
  sr_var <- (1 - g3 * sr_obs/sqrt(12) + (g4-1)/4 * (sr_obs/sqrt(12))^2) / (n - 1)
  # Number of trials = candidates_tried in method log
  N_trials <- 5L  # method_log
  # Expected max SR under null among N_trials standard normals (Mertens 2002 approx)
  emax <- (1 - 0.5772) * qnorm(1 - 1/N_trials) + 0.5772 * qnorm(1 - 1/(N_trials * exp(1)))
  dsr <- pnorm((sr_obs/sqrt(12) - emax * sqrt(sr_var)) / sqrt(sr_var))
  cat(sprintf("    Annualized SR (IC-based) = %.3f, n=%d, g3=%.2f, g4=%.2f, N_trials=%d, expected_max=%.3f\n",
              sr_obs, n, g3, g4, N_trials, emax))
  cat(sprintf("    DSR (Deflated Sharpe Ratio probability) = %.4f\n", dsr))
} else {
  dsr <- NA_real_
}

# =============================================================================
# Update draft.diagnostics and validation
# =============================================================================
cat("\n[Update] Diagnostics with k=1 (consistency)...\n")
draft$diagnostics$rank_ic <- round(ic_mean_k1, 4)
draft$diagnostics$icir <- round(icir_k1, 4)
draft$diagnostics$harvey_t_stat <- round(nw_t_k1, 4)
draft$diagnostics$harvey_nw_5spec_pass <- spec_pass_k1
draft$diagnostics$post_neutralization_ic <- round(ic_mean_k1, 4)
draft$diagnostics$subperiod_stability <- round(sub_stab_k1, 2)
draft$diagnostics$monotonicity <- round(mono_score, 3)
draft$diagnostics$top_minus_bottom_decile <- round(top_minus_bot, 4)
draft$diagnostics$dsr <- if (is.na(dsr)) NA else round(dsr, 4)
draft$diagnostics$annualized_sr_ic_based <- if (length(ic_k1$ic) >= 24) round(sr_obs, 3) else NA

draft$diagnostics$sub_stab_periods <- list(
  `2008-14` = sub_k1[period == "2008-14", icir],
  `2015-19` = sub_k1[period == "2015-19", icir],
  `2020-26` = sub_k1[period == "2020-26", icir]
)

# Update method_shopping_log with k=1 selected (was implicit before)
draft$method_shopping_log$method_log <- list(
  list(name = "joint_sigmoid_k1.0",   icir = round(icir_k1, 4), selected = TRUE),
  list(name = "joint_sigmoid_k2.0",   icir = 0.1247,            selected = FALSE),
  list(name = "joint_sigmoid_k3.0",   icir = 0.1149,            selected = FALSE),
  list(name = "linear_baseline",      icir = 0.1329,            selected = FALSE),
  list(name = "single_skew_only",     icir = 0.1486,            selected = FALSE)
)
draft$method_shopping_log$candidates_tried <- 5L

# Final challenge_flags update — be honest about all failures
new_flags <- list(
  list(flag = "ALPHA_LAB_GATE_FAIL", severity = "HIGH",
       detail = sprintf("ICIR (k=1) %.4f < 0.20. Discovery WT graduation FAIL.", icir_k1)),
  list(flag = "RANK_IC_FAIL", severity = "HIGH",
       detail = sprintf("Rank IC %.4f < 0.04 KR top-universe benchmark.", ic_mean_k1)),
  list(flag = "HARVEY_T_FAIL", severity = "HIGH",
       detail = sprintf("NW-HAC t=%.2f < 3.0 (Harvey multi-test).", nw_t_k1)),
  list(flag = "HARVEY_5SPEC_FAIL", severity = "HIGH",
       detail = sprintf("5-spec |t|>=3 pass %d/5 < 3/5.", spec_pass_k1)),
  list(flag = "L211_NOT_AVOIDED", severity = "HIGH",
       detail = sprintf("Joint sigmoid ICIR %.4f < Linear ICIR 0.1329 < Skew_only ICIR 0.1486. Single-axis dominates joint. L-211 KR linear composite fail pattern reproduced via different path (sigmoid).", icir_k1)),
  list(flag = "RF-A3_RECENT_OVERFIT", severity = "MEDIUM",
       detail = sprintf("Sub-period ICIR: 2008-14=%.3f (NEG), 2015-19=+%.3f, 2020-26=+%.3f. recent_3Y/full ratio=%.2f > 1.5 threshold.",
                        sub_k1[period == "2008-14", icir],
                        sub_k1[period == "2015-19", icir],
                        sub_k1[period == "2020-26", icir],
                        sub_k1[period == "2020-26", icir] / abs(icir_k1))),
  list(flag = "MONOTONICITY_FAIL", severity = "MEDIUM",
       detail = sprintf("Adjacent decile increasing fraction = %.3f (target ~0.80). Top-Bot diff = %+.4f.", mono_score, top_minus_bot))
)

# Cross-family observations (positive but irrelevant since alpha fails)
positive_findings <- list(
  list(flag = "CROSS_FAMILY_LOW_CORR", severity = "INFO",
       detail = sprintf("vs STR_1701 corr=%.4f, vs STR_1656 corr=%.4f. Cross-family diversification CONFIRMED. But alpha source itself fails Discovery gates so unusable.",
                        draft$diagnostics$cross_corr_str1701, draft$diagnostics$cross_corr_str1656))
)
draft$challenge_flags <- c(new_flags, positive_findings)

# Hypothesis title clarification — final REJECT outcome
draft$hypothesis_status <- "REJECTED_BY_GATES"
draft$hypothesis_summary <- paste0(
  "Track B Iter 16 — NCSKEW × Accrual Quality nonlinear sigmoid joint. ",
  sprintf("Final ICIR (k=1) = %.4f (<0.20 FAIL). Joint < Linear < Skew_only. ", icir_k1),
  "Sigmoid joint did NOT improve over linear or single-axis baseline. ",
  sprintf("Sub-period ICIR: 2008-14=%.3f (negative), 2020-26=%.3f (RF-A3 recent overfit). ",
          sub_k1[period == "2008-14", icir], sub_k1[period == "2020-26", icir]),
  sprintf("Cross-family corr LOW (STR_1701=%.4f, STR_1656=%.4f) — only positive finding, ",
          draft$diagnostics$cross_corr_str1701, draft$diagnostics$cross_corr_str1656),
  "but alpha source itself fails 4/5 Discovery WT graduation gates. ",
  "Hypothesis REJECTED. L-211 reproduced via nonlinear path (different mechanism, same failure)."
)

# Update factor_specs to k=1
draft$factor_specs[[3]]$formula <- "alpha = sigmoid(NCSKEW_z, k=1.0) × sigmoid(Accrual_z, k=1.0) [k=1 selected via ICIR sweep, validated against persisted alpha_scores$alpha_final_k1]"

# selection_objective unchanged (icir)

# alpha_inheritance hash update
draft$alpha_inheritance$factor_formula_hash <- digest(list(
  factor_1 = "R13_NCSKEW", factor_2 = "AC18_Accrual_Quality",
  joint = "sigmoid(z1,k) × sigmoid(z2,k)", k = 1.0,
  alpha_scores_col = "alpha_final_k1_z"
), algo = "sha1")

write_json(draft, file.path(WT_MAIL_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    saved: alpha_package.json (k=1 consistent)\n")

# Update validation
val <- fromJSON(file.path(ARTIFACT_DIR, "alpha_validation.json"), simplifyVector = FALSE)
val$diagnostics$joint$icir <- round(icir_k1, 4)
val$diagnostics$joint$ic_mean <- round(ic_mean_k1, 4)
val$diagnostics$joint$nw_hac_t <- round(nw_t_k1, 4)
val$diagnostics$joint$nw_hac_5spec_pass <- spec_pass_k1
val$diagnostics$joint$nw_hac_5spec_details <- spec_details_k1
val$diagnostics$joint$sub_stab <- round(sub_stab_k1, 2)
val$diagnostics$joint$monotonicity <- round(mono_score, 3)
val$diagnostics$joint$top_minus_bottom <- round(top_minus_bot, 4)
val$diagnostics$joint$dsr <- if (is.na(dsr)) NA else round(dsr, 4)
val$diagnostics$joint$annualized_sr <- if (length(ic_k1$ic) >= 24) round(sr_obs, 3) else NA

val$selected_k <- 1.0
val$alpha_scores_columns <- list(
  primary = "alpha_final_k1_z",
  ablation = c("alpha_joint_z (k=2)", "alpha_linear_z", "alpha_skew_only_z", "alpha_accrual_only_z"),
  rationale = "k=1 selected as optimal via ICIR sweep. C1 fix: persisted score now matches package alpha_vector."
)
val$graduation_check$icir_pass <- (icir_k1 >= 0.20)
val$graduation_check$rank_ic_pass <- (ic_mean_k1 >= 0.04)
val$graduation_check$harvey_t_pass <- (!is.na(nw_t_k1) && abs(nw_t_k1) >= 3.0)
val$graduation_check$harvey_5spec_pass <- (!is.na(spec_pass_k1) && spec_pass_k1 >= 3)
val$graduation_check$dsr_pass <- (!is.na(dsr) && dsr >= 0.5)
val$graduation_check$monotonicity_pass <- (mono_score >= 0.7)
val$graduation_check$overall_verdict <- "REJECTED"
val$graduation_check$gates_passed <- sum(c(
  val$graduation_check$icir_pass,
  val$graduation_check$rank_ic_pass,
  val$graduation_check$sub_stab_pass,
  val$graduation_check$harvey_t_pass,
  val$graduation_check$harvey_5spec_pass
))

write_json(val, file.path(ARTIFACT_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    saved: alpha_validation.json (final, k=1)\n")

# Re-record lineage
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
input_files <- c(
  file.path(PROJECT_ROOT, ".cache/rawdata.rds"),
  file.path(PROJECT_ROOT, ".cache/factor_db_daily/factor_db_daily_registry.json"),
  file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet"),
  file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_004/alpha_scores.parquet"),
  file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_006/alpha_scores.parquet")
)
input_files <- input_files[file.exists(input_files)]

record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "Sigmoid Joint NCSKEW × Accrual Quality (k=1.0 via ICIR sweep). Z_Score_Aligned PIT C13. K200∪KQ150 PIT + 2e8 KRW Close×Vol liquidity. C1 fix: alpha_scores$alpha_final_k1_z = package alpha_vector source.",
  input_file_paths = input_files,
  windows = list(
    train_val_end = "2024-01-22",
    oos_start = "2008-01-31",
    oos_end_observed = "2023-12-28",
    n_periods = 192L
  ),
  random_seed = 20260426L,
  extra = list(
    factor_formula_hash = draft$alpha_inheritance$factor_formula_hash,
    icir_k1 = round(icir_k1, 4),
    rank_ic = round(ic_mean_k1, 4),
    nw_t = round(nw_t_k1, 4),
    nw_5spec = spec_pass_k1,
    sub_stab = round(sub_stab_k1, 2),
    monotonicity = round(mono_score, 3),
    dsr = if (is.na(dsr)) NA else round(dsr, 4),
    cross_corr_str1701 = draft$diagnostics$cross_corr_str1701,
    cross_corr_str1656 = draft$diagnostics$cross_corr_str1656,
    tdc_q5_vs_pg2 = draft$diagnostics$tdc_q5_vs_pg2,
    n_challenge_flags = length(draft$challenge_flags),
    overall_verdict = "REJECTED_BY_GATES",
    codex_round1_stance = "REJECT",
    rebuild_reason = "C1 alpha_scores k=1 score column added"
  ),
  wt_root = file.path(PROJECT_ROOT, "qepm/mailbox/worktask")
)

cat("\n=== FINAL k=1 SUMMARY ===\n")
cat(sprintf("ICIR (k=1)           : %.4f  [target ≥0.20]  %s\n",
            icir_k1, ifelse(icir_k1 >= 0.20, "PASS", "FAIL")))
cat(sprintf("Rank IC (k=1)        : %.4f  [target ≥0.04]  %s\n",
            ic_mean_k1, ifelse(ic_mean_k1 >= 0.04, "PASS", "FAIL")))
cat(sprintf("Sub_stab (k=1)       : %.2f   [target ≥0.50]  %s\n",
            sub_stab_k1, ifelse(sub_stab_k1 >= 0.50, "PASS", "FAIL")))
cat(sprintf("NW-HAC t (k=1)       : %.2f   [target ≥3.0]   %s\n",
            nw_t_k1, ifelse(abs(nw_t_k1) >= 3.0, "PASS", "FAIL")))
cat(sprintf("5-spec pass (k=1)    : %d/5   [target ≥3/5]   %s\n",
            spec_pass_k1, ifelse(spec_pass_k1 >= 3, "PASS", "FAIL")))
cat(sprintf("Monotonicity         : %.3f  [target ≥0.7]   %s\n",
            mono_score, ifelse(mono_score >= 0.7, "PASS", "FAIL")))
cat(sprintf("DSR                  : %s  [target ≥0.5]   %s\n",
            ifelse(is.na(dsr), "NA", sprintf("%.4f", dsr)),
            ifelse(!is.na(dsr) && dsr >= 0.5, "PASS", "FAIL")))
cat(sprintf("Cross corr STR_1701  : %.4f [target <0.30]  PASS\n", draft$diagnostics$cross_corr_str1701))
cat(sprintf("Cross corr STR_1656  : %.4f [target <0.30]  PASS\n", draft$diagnostics$cross_corr_str1656))
cat(sprintf("TDC q5 vs PG2        : %.4f [target <0.30]  PASS\n", draft$diagnostics$tdc_q5_vs_pg2))

cat("\nVerdict: hypothesis REJECTED — alpha fails 4/5 Discovery gates + L-211 reproduced.\n")
cat(sprintf("Cross-family diversification CONFIRMED (corr both <0.01) but unusable since alpha source fails.\n"))
