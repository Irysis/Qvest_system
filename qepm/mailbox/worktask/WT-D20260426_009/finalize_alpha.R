# =============================================================================
# WT-D20260426_009 — Alpha finalization (date alignment fix + lineage + final package)
# =============================================================================
# Issue found in pipeline run: STR_1701 alpha uses month-start (YYYY-MM-01) dates,
# our alpha uses month-end (Date last trading day) dates. zero intersection → NA.
# Fix: align via year-month key, then re-compute corr/TDC vs STR_1701.
# Also: write final alpha_package.json + lineage.
# =============================================================================
cat("=== WT-D20260426_009 — Alpha Finalization ===\n")
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260426_009"
WT_DIR_TAG   <- "WT_D20260426_009"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_DIR_TAG)

# Load existing pipeline outputs
draft <- fromJSON(file.path(WT_MAIL_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
val   <- fromJSON(file.path(ARTIFACT_DIR, "alpha_validation.json"), simplifyVector = FALSE)
ours  <- as.data.table(read_parquet(file.path(ARTIFACT_DIR, "alpha_scores.parquet")))
ours[, ym := format(Date, "%Y-%m")]

# Load STR_1701 + STR_1656
str1701 <- as.data.table(read_parquet(file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_004/alpha_scores.parquet")))
str1701[, ym := format(Date, "%Y-%m")]
str1701 <- str1701[, .(ym, Ticker, score_1701 = score_eff)]

str1656 <- as.data.table(read_parquet(file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_006/alpha_scores.parquet")))
str1656[, ym := format(Date, "%Y-%m")]
if ("score_xgb" %in% names(str1656) && "score_cat" %in% names(str1656)) {
  str1656[, score_1656 := (rank(score_xgb) + rank(score_cat)) / 2 / .N, by = ym]
} else if ("score_xgb" %in% names(str1656)) {
  str1656[, score_1656 := score_xgb]
}
str1656 <- str1656[, .(ym, Ticker, score_1656)]

# =============================================================================
# Re-compute correlations using ym alignment
# =============================================================================
cat("\n[1] Cross-correlation (ym-aligned)...\n")

corr_ym <- function(target_dt, target_col, name) {
  m <- merge(ours[, .(ym, Ticker, alpha_joint_z)], target_dt,
             by = c("ym", "Ticker"), all = FALSE)
  m <- m[complete.cases(m)]
  if (nrow(m) < 100) {
    cat(sprintf("    [Corr] %s: insufficient rows (%d)\n", name, nrow(m)))
    return(list(mean = NA, median = NA, n_periods = 0))
  }
  per_ym <- m[, .(c = if (.N >= 10 && sd(alpha_joint_z, na.rm=TRUE) > 0 &&
                          sd(get(target_col), na.rm=TRUE) > 0)
                       cor(alpha_joint_z, get(target_col), method="spearman", use="complete.obs")
                     else NA_real_,
                  n = .N), by = ym][!is.na(c)]
  cat(sprintf("    [Corr] %s: n_periods=%d, mean=%.4f, median=%.4f, std=%.4f\n",
              name, nrow(per_ym), mean(per_ym$c, na.rm=TRUE),
              median(per_ym$c, na.rm=TRUE), sd(per_ym$c, na.rm=TRUE)))
  list(mean = mean(per_ym$c, na.rm=TRUE),
       median = median(per_ym$c, na.rm=TRUE),
       n_periods = nrow(per_ym))
}

c_1701 <- corr_ym(str1701, "score_1701", "vs STR_1701 (Iter 11)")
c_1656 <- corr_ym(str1656, "score_1656", "vs STR_1656 (Iter 13 ML)")

# =============================================================================
# TDC q5 (ym-aligned)
# =============================================================================
cat("\n[2] TDC q5 (ym-aligned)...\n")
tdc_ym <- function(target_dt, target_col, q = 0.20, name = "?") {
  m <- merge(ours[, .(ym, Ticker, alpha_joint_z)], target_dt,
             by = c("ym", "Ticker"), all = FALSE)
  m <- m[complete.cases(m)]
  if (nrow(m) < 100) return(NA_real_)
  m[, rk_a := rank(alpha_joint_z) / .N, by = ym]
  m[, rk_t := rank(get(target_col)) / .N, by = ym]
  m[, top_a := rk_a >= (1 - q)]
  m[, top_t := rk_t >= (1 - q)]
  per_ym <- m[, .(joint_top = sum(top_a & top_t),
                  target_top = sum(top_t)), by = ym]
  tdc <- per_ym[, sum(joint_top) / sum(target_top)]
  cat(sprintf("    TDC q=%.2f vs %s: %.4f (independence baseline=%.2f, target<0.30)\n",
              q, name, tdc, q))
  tdc
}
tdc_pg2_v2  <- tdc_ym(str1701, "score_1701", 0.20, "STR_1701 (PG2)")
tdc_1656_v2 <- tdc_ym(str1656, "score_1656", 0.20, "STR_1656")

# =============================================================================
# Update alpha_package.json with corrected metrics
# =============================================================================
cat("\n[3] Updating alpha_package.json...\n")

# Update diagnostics
draft$diagnostics$cross_corr_str1701 <- round(c_1701$mean, 4)
draft$diagnostics$cross_corr_str1656 <- round(c_1656$mean, 4)
draft$diagnostics$tdc_q5_vs_pg2      <- round(tdc_pg2_v2, 4)
draft$diagnostics$tdc_q5_vs_str1656  <- round(tdc_1656_v2, 4)
draft$diagnostics$cross_corr_str1701_n_periods <- c_1701$n_periods
draft$diagnostics$cross_corr_str1656_n_periods <- c_1656$n_periods

# Update validation
val$cross_corr$vs_str1701 <- round(c_1701$mean, 4)
val$cross_corr$vs_str1656 <- round(c_1656$mean, 4)
val$cross_corr$ym_alignment_used <- TRUE
val$cross_corr$str1701_n_periods <- c_1701$n_periods
val$cross_corr$str1656_n_periods <- c_1656$n_periods
val$tdc_q5$vs_pg2_str1701 <- round(tdc_pg2_v2, 4)
val$tdc_q5$vs_str1656 <- round(tdc_1656_v2, 4)

# Update hypothesis_summary
draft$hypothesis_summary <- gsub(
  "vs STR_1701 corr=NA",
  sprintf("vs STR_1701 corr=%.4f", c_1701$mean),
  draft$hypothesis_summary
)
draft$hypothesis_summary <- gsub(
  "vs STR_1656 corr=0\\.0025",
  sprintf("vs STR_1656 corr=%.4f", c_1656$mean),
  draft$hypothesis_summary
)

# Update challenge flags
new_flags <- list()
icir_v <- val$diagnostics$joint$icir
sub_v  <- val$diagnostics$joint$sub_stab
nw_t_v <- val$diagnostics$joint$nw_hac_t
spec_pass <- val$diagnostics$joint$nw_hac_5spec_pass
icir_lin <- val$diagnostics$linear$icir
icir_skew <- val$diagnostics$skew_only$icir

if (!is.null(icir_v) && icir_v < 0.20) new_flags <- c(new_flags, list(list(
  flag = "ALPHA_LAB_GATE_FAIL", severity = "HIGH",
  detail = sprintf("Joint ICIR %.4f < 0.20 (Alpha Lab Gate threshold). Fails graduation criterion.", icir_v)
)))
if (!is.null(icir_v) && !is.null(icir_lin) && icir_v <= icir_lin) new_flags <- c(new_flags, list(list(
  flag = "L211_NOT_AVOIDED", severity = "HIGH",
  detail = sprintf("Joint ICIR %.4f <= Linear ICIR %.4f. Sigmoid joint did NOT improve over linear baseline. L-211 KR top-universe linear composite fail pattern reproduced.",
                   icir_v, icir_lin)
)))
if (!is.null(icir_v) && !is.null(icir_skew) && icir_v < icir_skew) new_flags <- c(new_flags, list(list(
  flag = "SINGLE_AXIS_DOMINATES", severity = "HIGH",
  detail = sprintf("Joint ICIR %.4f < Skew-only ICIR %.4f. Single NCSKEW axis dominates joint. Accrual ICIR %.4f (negative). Conditioning loses signal vs single-factor.",
                   icir_v, icir_skew, val$diagnostics$accrual_only$icir)
)))
if (!is.null(spec_pass) && !is.na(spec_pass) && spec_pass < 3) new_flags <- c(new_flags, list(list(
  flag = "HARVEY_5SPEC_FAIL", severity = "HIGH",
  detail = sprintf("NW-HAC 5-spec |t|>=3 pass count = %d/5. Fails 3/5 minimum (Harvey-Liu-Zhu multi-test).", spec_pass)
)))
if (!is.null(nw_t_v) && !is.na(nw_t_v) && abs(nw_t_v) < 3.0) new_flags <- c(new_flags, list(list(
  flag = "HARVEY_T_BELOW_3", severity = "HIGH",
  detail = sprintf("NW-HAC t-stat = %.2f < 3.0 (Harvey multi-test). Joint not statistically significant.", nw_t_v)
)))

# 2008-14 negative ICIR + 2020-26 strong → recent overfit warning
sub_periods <- val$diagnostics$joint$sub_periods_pos
if (!is.null(draft$diagnostics$sub_stab_periods)) {
  p2008 <- as.numeric(draft$diagnostics$sub_stab_periods$`2008-14`)
  p2020 <- as.numeric(draft$diagnostics$sub_stab_periods$`2020-26`)
  if (!is.na(p2008) && !is.na(p2020) && p2020 > 1.5 * abs(p2008) + 0.2 && p2008 < 0) {
    new_flags <- c(new_flags, list(list(
      flag = "RF-A3_RECENT_OVERFIT", severity = "MEDIUM",
      detail = sprintf("2008-14 ICIR=%.3f (NEG), 2015-19=+%.3f, 2020-26=+%.3f. Recent periods >>> early period. Possible regime-specific alpha or recent overfit.",
                       p2008, as.numeric(draft$diagnostics$sub_stab_periods$`2015-19`), p2020)
    )))
  }
}

if (!is.na(c_1701$mean) && c_1701$mean >= 0.30) new_flags <- c(new_flags, list(list(
  flag = "CROSS_FAMILY_FAIL", severity = "HIGH",
  detail = sprintf("vs STR_1701 corr %.4f >= 0.30 (cross-family target violated)", c_1701$mean)
)))
if (!is.na(c_1656$mean) && c_1656$mean >= 0.30) new_flags <- c(new_flags, list(list(
  flag = "DIVERSIFIER_OVERLAP", severity = "MEDIUM",
  detail = sprintf("vs STR_1656 corr %.4f >= 0.30 (diversifier overlap)", c_1656$mean)
)))
if (!is.na(tdc_pg2_v2) && tdc_pg2_v2 >= 0.30) new_flags <- c(new_flags, list(list(
  flag = "TDC_PG2_VIOLATION", severity = "HIGH",
  detail = sprintf("TDC q5 vs PG2 (STR_1701) = %.4f >= 0.30 (tail co-movement)", tdc_pg2_v2)
)))

draft$challenge_flags <- new_flags

# Update validation graduation_check
val$graduation_check$rank_ic_pass <- (val$diagnostics$joint$ic_mean >= 0.04)
val$graduation_check$icir_pass <- (icir_v >= 0.20)
val$graduation_check$sub_stab_pass <- (sub_v >= 0.50)
val$graduation_check$harvey_t_pass <- (!is.na(nw_t_v) && abs(nw_t_v) >= 3.0)
val$graduation_check$harvey_5spec_pass <- (!is.na(spec_pass) && spec_pass >= 3)
val$graduation_check$cross_family_pass_str1701 <- (!is.na(c_1701$mean) && c_1701$mean < 0.30)
val$graduation_check$cross_family_pass_str1656 <- (!is.na(c_1656$mean) && c_1656$mean < 0.30)
val$graduation_check$tdc_pg2_pass <- (!is.na(tdc_pg2_v2) && tdc_pg2_v2 < 0.30)

# Final write
write_json(draft, file.path(WT_MAIL_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    saved: alpha_package.json\n")

write_json(val, file.path(ARTIFACT_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    saved: alpha_validation.json (updated)\n")

# =============================================================================
# Lineage (after alpha_package.json write)
# =============================================================================
cat("\n[4] Recording lineage...\n")
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
  method_selected = "Sigmoid Joint NCSKEW × Accrual Quality (k=1.0 optimal). Z_Score_Aligned PIT C13. K200∪KQ150 PIT + 2e8 KRW liquidity.",
  input_file_paths = input_files,
  windows = list(
    train_val_end = "2024-01-22",
    oos_start = "2008-01-31",
    oos_end_observed = "2023-12-28",
    n_periods = 192L
  ),
  random_seed = 20260426L,
  extra = list(
    factor_formula_hash = digest(list(f1 = "R13_NCSKEW", f2 = "AC18_Accrual_Quality",
                                       joint = "sigmoid(z1,k) * sigmoid(z2,k)", k = 1.0),
                                  algo = "sha1"),
    icir_joint = round(icir_v, 4),
    icir_linear_baseline = round(icir_lin, 4),
    sub_stab = round(sub_v, 2),
    cross_corr_str1701 = round(c_1701$mean, 4),
    cross_corr_str1656 = round(c_1656$mean, 4),
    tdc_q5_vs_pg2 = round(tdc_pg2_v2, 4),
    n_challenge_flags = length(new_flags)
  ),
  wt_root = file.path(PROJECT_ROOT, "qepm/mailbox/worktask")
)

# =============================================================================
# Summary
# =============================================================================
cat("\n=== FINAL SUMMARY ===\n")
cat(sprintf("ICIR (joint)         : %.4f  [target ≥0.20]  %s\n",
            icir_v, ifelse(icir_v >= 0.20, "PASS", "FAIL")))
cat(sprintf("ICIR (linear)        : %.4f  (joint vs linear lift = %+.1f%%)\n",
            icir_lin, (icir_v - icir_lin) / abs(icir_lin + 1e-9) * 100))
cat(sprintf("ICIR (skew_only)     : %.4f  (single-axis dominates joint = %s)\n",
            icir_skew, ifelse(icir_skew > icir_v, "YES", "no")))
cat(sprintf("Rank IC mean         : %.4f  [target ≥0.04]  %s\n",
            val$diagnostics$joint$ic_mean,
            ifelse(val$diagnostics$joint$ic_mean >= 0.04, "PASS", "FAIL")))
cat(sprintf("Sub-period stability : %.2f   [target ≥0.50]  %s\n",
            sub_v, ifelse(sub_v >= 0.50, "PASS", "FAIL")))
cat(sprintf("NW-HAC t-stat        : %.2f   [target ≥3.0]   %s\n",
            nw_t_v, ifelse(abs(nw_t_v) >= 3.0, "PASS", "FAIL")))
cat(sprintf("Harvey NW 5-spec     : %d/5   [target ≥3/5]   %s\n",
            spec_pass, ifelse(spec_pass >= 3, "PASS", "FAIL")))
cat(sprintf("Corr vs STR_1701     : %.4f [target <0.30]  %s\n",
            c_1701$mean, ifelse(!is.na(c_1701$mean) && c_1701$mean < 0.30, "PASS", "FAIL")))
cat(sprintf("Corr vs STR_1656     : %.4f [target <0.30]  %s\n",
            c_1656$mean, ifelse(!is.na(c_1656$mean) && c_1656$mean < 0.30, "PASS", "FAIL")))
cat(sprintf("TDC q5 vs PG2        : %.4f [target <0.30]  %s\n",
            tdc_pg2_v2, ifelse(!is.na(tdc_pg2_v2) && tdc_pg2_v2 < 0.30, "PASS", "FAIL")))
cat(sprintf("TDC q5 vs STR_1656   : %.4f [target <0.30]  %s\n",
            tdc_1656_v2, ifelse(!is.na(tdc_1656_v2) && tdc_1656_v2 < 0.30, "PASS", "FAIL")))
cat(sprintf("Challenge flags      : %d (HIGH=%d)\n",
            length(new_flags),
            sum(sapply(new_flags, function(f) f$severity == "HIGH"))))

# n gates passed
gates <- list(
  ICIR = (icir_v >= 0.20),
  IC = (val$diagnostics$joint$ic_mean >= 0.04),
  SUB_STAB = (sub_v >= 0.50),
  HARVEY_T = (!is.na(nw_t_v) && abs(nw_t_v) >= 3.0),
  HARVEY_5SPEC = (!is.na(spec_pass) && spec_pass >= 3)
)
n_pass <- sum(unlist(gates))
cat(sprintf("\nGates: %d/5 PASS [%s]\n",
            n_pass, paste(names(gates)[unlist(gates)], collapse=",")))

cat("\n>>> FINAL_LINE <<<\n")
cat(sprintf("ALPHA_DONE_TRACK_B — N_sig_dates=%d, ICIR=%.4f, sub_stab=%.2f, harvey_nw_5spec=%d/5, dsr_post=NA, V3_vs_STR1701_cor=%.4f, V3_vs_STR1656_cor=%.4f, tdc_q5_vs_pg2=%.4f, tdc_q5_vs_str1656=%.4f, sigmoid_steepness_optimal=1.0, regime_subset_optimal=BULL, codex_stance=PENDING_R1, gates_pass=%d/5, resolution_count=PENDING\n",
            length(unique(ours$ym)),
            icir_v, sub_v, spec_pass,
            c_1701$mean, c_1656$mean, tdc_pg2_v2, tdc_1656_v2, n_pass))
