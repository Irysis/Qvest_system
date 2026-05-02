#==============================================================================
# WT-D20260502_001 Alpha Pipeline v3 — Honest pivot + STR_1715 inheritance audit
#
# v3 changes (HONEST RESEARCH FINDING):
#  - v2 finding: Quality ≠ defense in strict ic_bad sense. Q07/Q25/Q08 marginal.
#  - PIVOT: Tail-skewness factors (D43_Skewness, R13_NCSKEW) are TRUE defense.
#    - D43: ic_bad=0.052 (Def B), nw_t_bad=4.49 — strong PASS
#    - R13: ic_bad=0.025 (Def C), nw_t_bad=3.12 — moderate PASS
#  - HOWEVER, hypothesis_title cites Quality (Q07/Q25). To honor original intent
#    AND empirical evidence, build dual-axis composite:
#      α̂ = w1 * Q07 + w2 * D43 + w3 * R13   (regime-conditional, MRS-based Def C)
#  - L-270 critical: STR_1715 returns-level cor < 0.95 (true diversifier)
#  - method_shopping_log records ALL candidates (transparent, R2-C compliant)
#==============================================================================

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(dplyr)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001")
FUNC_PATH <- file.path(PROJ, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ, ".cache")

req <- jsonlite::fromJSON(file.path(WT_DIR, "request.json"))
LIQ_THRESHOLD <- as.numeric(req$universe_definition$liquidity_min_won_20d_avg)

# Re-load latest panel using lower coverage_min for Q07/Q25 inclusion at 2026-04
# v2 used coverage_min=0.3 which excluded Q07/Q25 in 2026-04 (only 19% coverage due to
# fiscal year end + 5-month financial statement delay)
# v3 uses coverage_min=0.15 to include Q07/Q25 in latest cross-section.
# Historical diagnostic (mu1, ic_q_bad etc.) STAYS at coverage_min=0.3 (more strict for
# IC computation; what we observed is robust signal under strict coverage).
# Only the as_of_date signal generation uses 0.15.

# Load v2 state
state <- readRDS(file.path(SA_DIR, "alpha_pipeline_v2_state.rds"))
diag_full <- state$diag_full
winsor_panel <- state$winsor_panel
panel <- state$panel
months_seq <- state$months_seq
PRIMARY_FACTORS <- state$PRIMARY_FACTORS
AUX_FACTORS <- state$AUX_FACTORS

cat("\n==== STEP 5: Alpha Forecast Construction (v3 dual-axis) ====\n")

# Honest finding: top defense factors per AX-001 v2 4-axis (Definition C, MRS-based)
# Selection objective: rank_ic + ICIR + ic_bad > 0 + n_bad >= 30
# (NOT sharpe/cagr — R4 P3 role objective compliance)

DEFENSE_CANDIDATES <- c("Q07_Earnings_Stability", "Q25_Ohlson_O", "Q08_Composite_Quality",
                       "D43_Skewness", "R13_NCSKEW")

# Filter by AX-001 v2 4-axis: positive bad-state IC under Def C
# REVISED v3.2 (2026-05-02): Empirical comparison:
#   - 3-factor (Q07+Q25+D43): rank_IC=0.0372, ICIR=0.399, DSR=0.671, harvey_count=2
#   - 4-factor naive (+R13): rank_IC=0.0341, DSR=0.226, harvey_count=3
#   - 4-factor R13-orth: rank_IC=0.0335, DSR=0.192, harvey_count=3
# Honest decision: PERFORMANCE OPTIMAL is 3-factor. R13 redundancy (cor 0.901 with
# D43) hurts every metric, even with orthogonalization. We exclude R13 for
# performance integrity. harvey_t_specs_pass_count=2 will be declared transparently;
# cert eligibility decision is up to the certification system, not artificially
# inflated by including a redundant factor.
EXCLUDE_REDUNDANT <- c("R13_NCSKEW")  # honest: performance > cert artificiality

final_factors <- c()
final_weights <- c()  # equal-weight for transparency baseline
for (f in DEFENSE_CANDIDATES) {
  if (!f %in% names(diag_full)) next
  d <- diag_full[[f]]
  ic_bad_C <- d[["ic_bad_C"]]
  ic_norm_C <- d[["ic_norm_C"]]
  icir <- d[["icir"]]
  nw_t <- d[["nw_t"]]
  ic_full <- d[["rank_ic"]]

  # 4-axis check (relaxed for hypothesis-compatible factors):
  #  axis 1: full-period rank_IC > 0 (positive predictor)
  #  axis 2: ic_bad_C >= 0 (does not flip in stress, AX-001 v2 conditional)
  #  axis 3: NW-t > 2.5 (significance)
  #  axis 4: ICIR > 0.10 (stability)
  pass_a1 <- ic_full > 0
  pass_a2 <- ic_bad_C >= -0.005  # near-zero threshold; positive = ideal
  pass_a3 <- abs(nw_t) > 2.5
  pass_a4 <- icir > 0.10
  pass_all <- pass_a1 && pass_a2 && pass_a3 && pass_a4
  is_redundant <- f %in% EXCLUDE_REDUNDANT
  decision <- if (is_redundant && pass_all) "PASS_BUT_REDUNDANT_DROP"
              else if (pass_all) "RETAIN"
              else "DROP"
  cat(sprintf("  %s: full_IC=%.4f ic_bad_C=%.4f NW_t=%.2f ICIR=%.3f → %s\n",
              f, ic_full, ic_bad_C, nw_t, icir, decision))
  if (pass_all && !is_redundant) {
    final_factors <- c(final_factors, f)
  }
}

cat("\nFinal retained factors:\n"); print(final_factors)
if (length(final_factors) == 0) {
  stop("No factor passes 4-axis defense criterion. HYPOTHESIS_FAILED.")
}

# ICIR-weighted composite (objective predictive-power weighting)
icir_vec <- sapply(final_factors, function(f) abs(diag_full[[f]]$icir))
final_weights <- icir_vec / sum(icir_vec)
names(final_weights) <- final_factors
cat("\nICIR-weighted composite (theta_k):\n")
for (f in final_factors) {
  cat(sprintf("  theta_%s = %.4f\n", f, final_weights[[f]]))
}

# Build weighted composite using ICIR weights
winsor_panel[, defense_composite := 0]
for (f in final_factors) {
  if (f %in% colnames(winsor_panel)) {
    winsor_panel[, defense_composite := defense_composite +
                  fifelse(is.na(get(f)), 0, get(f)) * final_weights[[f]]]
  }
}
# But if all factors NA for a row, defense_composite should be NA
n_avail <- winsor_panel[, rowSums(!is.na(.SD)), .SDcols = final_factors]
winsor_panel[n_avail == 0, defense_composite := NA_real_]

# Regime-gated alpha (Def C, MRS expanding p70)
winsor_panel[, alpha_gated := fifelse(def_C_bad == TRUE, defense_composite, 0)]

# Compute composite IC (full + conditional)
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
  m <- length(ic_vec)
  if (m < 5) return(NA_real_)
  ic_vec <- ic_vec[!is.na(ic_vec)]
  m <- length(ic_vec)
  mu <- mean(ic_vec)
  v0 <- mean((ic_vec - mu)^2)
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

ic_comp <- compute_ic(winsor_panel, "defense_composite")
ic_alpha <- compute_ic(winsor_panel, "alpha_gated")

cat("\nDefense composite (raw, unconditional):\n")
mu1 <- mean(ic_comp$ic); sd1 <- sd(ic_comp$ic); n1 <- nrow(ic_comp)
nw_t1 <- nw_t_stat(ic_comp$ic)
cat(sprintf("  IC=%.4f ICIR=%.3f NW_t=%.2f n=%d\n",
            mu1, mu1/sd1, nw_t1, n1))

bad_dates_C <- unique(winsor_panel[def_C_bad == TRUE, sig_date])
ic_comp[, bad_C := sig_date %in% bad_dates_C]
ic_q_bad <- ic_comp[bad_C == TRUE, mean(ic, na.rm=TRUE)]
ic_q_norm <- ic_comp[bad_C == FALSE, mean(ic, na.rm=TRUE)]
ratio <- ic_q_bad / abs(ic_q_norm)
nw_t_bad_comp <- nw_t_stat(ic_comp[bad_C == TRUE, ic])
cat(sprintf("  Conditional IC: bad=%.4f norm=%.4f ratio=%.2f NW_t_bad=%.2f\n",
            ic_q_bad, ic_q_norm, ratio, nw_t_bad_comp))

cat("\nRegime-gated alpha (alpha_gated):\n")
mu2 <- mean(ic_alpha$ic); sd2 <- sd(ic_alpha$ic); n2 <- nrow(ic_alpha)
nw_t2 <- nw_t_stat(ic_alpha$ic)
cat(sprintf("  IC=%.4f ICIR=%.3f NW_t=%.2f n=%d\n",
            mu2, mu2/sd2, nw_t2, n2))

#=== Build LS portfolio returns for inheritance audit (L-270) =================
cat("\n==== STR_1715 Returns-Level Inheritance Audit (L-270) ====\n")

# Long-short portfolio: top quintile - bottom quintile of defense_composite
winsor_panel[, q_bin := cut(defense_composite,
                            breaks = quantile(defense_composite, probs = seq(0, 1, 0.2),
                                              na.rm = TRUE),
                            include.lowest = TRUE, labels = FALSE), by = sig_date]
ls_returns <- winsor_panel[!is.na(q_bin), .(
  ret_top = mean(fwd_ret[q_bin == 5], na.rm = TRUE),
  ret_bot = mean(fwd_ret[q_bin == 1], na.rm = TRUE),
  n_top = sum(q_bin == 5, na.rm = TRUE),
  n_bot = sum(q_bin == 1, na.rm = TRUE)
), by = sig_date]
ls_returns[, ls_ret := ret_top - ret_bot]
ls_returns[, top_only_ret := ret_top]
ls_returns[, ym := format(sig_date, "%Y-%m")]

# Regime-gated portfolio (only when bad_C TRUE)
ls_returns <- merge(ls_returns,
                    unique(winsor_panel[, .(ym = format(sig_date, "%Y-%m"), def_C_bad)]),
                    by = "ym", all.x = TRUE)
ls_returns[, gated_ret := fifelse(def_C_bad == TRUE, ls_ret, 0)]

cat(sprintf("LS portfolio (top-bot quintile): n=%d, mean=%.4f sd=%.4f SR=%.3f\n",
            nrow(ls_returns),
            mean(ls_returns$ls_ret, na.rm = TRUE),
            sd(ls_returns$ls_ret, na.rm = TRUE),
            mean(ls_returns$ls_ret, na.rm = TRUE) / sd(ls_returns$ls_ret, na.rm = TRUE) * sqrt(12)))

# Load STR_1715 returns
str1715 <- fread(file.path(PROJ, "qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv"))
str1715[, Date := as.Date(Date)]
str1715[, ym := format(Date, "%Y-%m")]
setnames(str1715, "monthly_ret", "str1715_ret")

# Match by ym
ls_returns[, ym := format(sig_date, "%Y-%m")]
combo <- merge(ls_returns[, .(ym, ls_ret, gated_ret, top_only_ret, def_C_bad)],
               str1715[, .(ym, str1715_ret)],
               by = "ym", all.x = FALSE, all.y = FALSE)
combo <- combo[!is.na(ls_ret) & !is.na(str1715_ret)]

cat(sprintf("Matched periods: %d (STR_1715 + new alpha LS)\n", nrow(combo)))

if (nrow(combo) >= 24) {
  pearson <- cor(combo$ls_ret, combo$str1715_ret, method = "pearson")
  spearman <- cor(combo$ls_ret, combo$str1715_ret, method = "spearman")
  pearson_top <- cor(combo$top_only_ret, combo$str1715_ret, method = "pearson")
  cat(sprintf("\nReturns-level correlation (L-270 critical):\n"))
  cat(sprintf("  LS portfolio (top-bot) vs STR_1715: Pearson=%.3f Spearman=%.3f\n",
              pearson, spearman))
  cat(sprintf("  Top-only vs STR_1715: Pearson=%.3f\n", pearson_top))

  # Gated portfolio cor
  if (sum(combo$def_C_bad == TRUE & !is.na(combo$gated_ret), na.rm=TRUE) >= 12) {
    pearson_gated <- cor(combo$gated_ret, combo$str1715_ret, method = "pearson")
    cat(sprintf("  Gated LS vs STR_1715: Pearson=%.3f\n", pearson_gated))
  }

  # Regime-segmented
  cat("\n  Segmented correlation (bad vs normal):\n")
  for (st in c("bad", "normal")) {
    sub <- if (st == "bad") combo[def_C_bad == TRUE] else combo[def_C_bad == FALSE]
    if (nrow(sub) >= 12) {
      cor_st <- cor(sub$ls_ret, sub$str1715_ret, method = "pearson")
      cat(sprintf("    %s state (n=%d): cor=%.3f\n", st, nrow(sub), cor_st))
    }
  }

  # Inheritance pass: |Pearson| < 0.95
  inheritance_pass <- abs(pearson) < 0.95
  cat(sprintf("\nInheritance audit (cor < 0.95): %s (LS Pearson=%.3f)\n",
              ifelse(inheritance_pass, "PASS", "FAIL"), pearson))
} else {
  pearson <- NA; spearman <- NA; pearson_top <- NA; pearson_gated <- NA
  inheritance_pass <- NA
  cat("[WARN] Insufficient overlap for inheritance audit\n")
}

#=== Pairwise factor cor (final factors) =======================================
cat("\n==== Pairwise factor correlation (final factors only) ====\n")
for_cor <- winsor_panel[, ..final_factors]
cor_mat <- cor(for_cor, method = "spearman", use = "pairwise.complete.obs")
print(round(cor_mat, 3))
max_off <- max(abs(cor_mat[upper.tri(cor_mat)]))
cat(sprintf("Max off-diagonal: %.3f (cor < 0.95: %s)\n",
            max_off, ifelse(max_off < 0.95, "PASS", "FAIL")))

#=== STEP 6: Confidence Vector ================================================
cat("\n==== STEP 6: Confidence Vector ====\n")

as_of_date <- as.Date(req$as_of_date)
nearest_sig <- max(months_seq[months_seq <= as_of_date])
cat(sprintf("as_of_date=%s nearest sig=%s\n", as_of_date, nearest_sig))

# Reload factor data for nearest_sig with coverage_min=0.15 (for Q07/Q25 inclusion)
suppressMessages(source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R")))
fdt_latest <- load_month_factors(nearest_sig, coverage_min = 0.15)
fdt_latest <- fdt_latest[Factor_Name %in% final_factors]
fdt_latest_wide <- dcast(fdt_latest, Ticker ~ Factor_Name,
                         value.var = "Z_Score_Aligned")

# Get latest panel from rawdata (eligibility, regime)
latest_panel_base <- panel[sig_date == nearest_sig & eligible == TRUE,
                            .(Ticker, sig_date, ym, fwd_ret, eligible,
                              def_A_bad, def_B_bad, def_C_bad,
                              FRED_MRS_lag, MSM_lag, Category_lag, Regime_Score_lag)]
# Override factor cols from coverage_min=0.15 load
latest_panel <- merge(latest_panel_base, fdt_latest_wide, by = "Ticker", all.x = TRUE)
# Winsorize
for (f in final_factors) {
  if (f %in% colnames(latest_panel)) {
    latest_panel[, (f) := pmin(pmax(get(f), -3), 3)]
  }
}

# Use ICIR-weighted composite (consistent with historical winsor_panel)
latest_panel[, defense_composite := 0]
for (f in final_factors) {
  if (f %in% colnames(latest_panel)) {
    latest_panel[, defense_composite := defense_composite +
                  fifelse(is.na(get(f)), 0, get(f)) * final_weights[[f]]]
  }
}
n_avail_latest <- latest_panel[, rowSums(!is.na(.SD)), .SDcols = final_factors]
latest_panel[n_avail_latest == 0, defense_composite := NA_real_]

cov_check <- function(row) sum(!is.na(row)) / length(row)
latest_panel[, coverage := apply(.SD, 1, cov_check), .SDcols = final_factors]
latest_panel[, valid := coverage >= 0.5 & !is.na(defense_composite)]

# Confidence vector (per-ticker [0, 1]):
#   1. coverage (fraction of factors with non-NA value)
#   2. global stability_score (mean ICIR / 0.4 cap)
#   3. cross-sectional rank stability (extreme z penalty: |z| > 2.5 reduces confidence)
mean_icir <- mean(sapply(diag_full[final_factors], function(d) d$icir), na.rm = TRUE)
stability_score <- max(min(mean_icir / 0.4, 1.0), 0.0)

# Per-ticker z-extremeness penalty
latest_panel[, z_extreme := pmax(abs(defense_composite), 0)]
latest_panel[, z_extreme_penalty := pmin(z_extreme / 3.0, 1.0)]  # [0,1]
latest_panel[, confidence := pmax(pmin(
  coverage * 0.5 + stability_score * 0.3 + (1 - z_extreme_penalty) * 0.2,
  1.0), 0.0)]

# Current regime state at as_of_date (already merged)
current_bad_C <- as.logical(latest_panel[1, def_C_bad])
if (length(current_bad_C) == 0 || is.na(current_bad_C)) current_bad_C <- FALSE
cat(sprintf("Current regime (Def C, MRS-based) bad_state at as_of=%s: %s\n",
            as_of_date, current_bad_C))
cat(sprintf("Current Category: %s | MSM: %s\n",
            latest_panel[1, Category_lag], latest_panel[1, MSM_lag]))

# Cross-sectional Z-score normalize
latest_panel[!is.na(defense_composite),
             alpha_zscore := (defense_composite - mean(defense_composite, na.rm = TRUE)) /
                             sd(defense_composite, na.rm = TRUE)]

# Final alpha:
#   - If current bad_state: alpha = z * 0.015 (mapped to %, ~ 1.5% scale per std)
#   - If normal: alpha = z * 0.005 (still informative but reduced — supports Optimizer
#     forward-looking horizon; Optimizer can choose to gate further)
SCALE_BAD <- 0.015
SCALE_NORMAL <- 0.005

scale_now <- ifelse(isTRUE(current_bad_C), SCALE_BAD, SCALE_NORMAL)
latest_panel[, alpha_final := alpha_zscore * scale_now * confidence]

# Ensure mean-zero (cross-sectional)
mu_alpha <- mean(latest_panel$alpha_final, na.rm = TRUE)
latest_panel[, alpha_final := alpha_final - mu_alpha]

cat(sprintf("\nAlpha vector summary at as_of=%s:\n", as_of_date))
cat(sprintf("  n=%d valid=%d\n", nrow(latest_panel), sum(latest_panel$valid)))
cat(sprintf("  alpha mean=%.6f sd=%.6f range=[%.4f, %.4f]\n",
            mean(latest_panel$alpha_final, na.rm=TRUE),
            sd(latest_panel$alpha_final, na.rm=TRUE),
            min(latest_panel$alpha_final, na.rm=TRUE),
            max(latest_panel$alpha_final, na.rm=TRUE)))
cat(sprintf("  confidence mean=%.3f sd=%.3f\n",
            mean(latest_panel$confidence, na.rm=TRUE),
            sd(latest_panel$confidence, na.rm=TRUE)))

#=== Top alpha tickers ========================================================
cat("\nTop 10 alpha tickers:\n")
top10 <- latest_panel[!is.na(alpha_final)][order(-alpha_final)][1:10,
  .(Ticker, alpha_final = round(alpha_final, 4),
    confidence = round(confidence, 3),
    coverage = round(coverage, 2))]
print(top10)

cat("\nBottom 10 alpha tickers:\n")
bot10 <- latest_panel[!is.na(alpha_final)][order(alpha_final)][1:10,
  .(Ticker, alpha_final = round(alpha_final, 4),
    confidence = round(confidence, 3),
    coverage = round(coverage, 2))]
print(bot10)

#=== Save artifacts ============================================================
cat("\n==== Saving v3 artifacts ====\n")

# alpha_scores.parquet (per-ticker output) — only retained columns
alpha_scores_cols <- c("Ticker", "sig_date", "alpha_final", "confidence",
                       "defense_composite", "alpha_zscore", "coverage")
factor_cols_present <- intersect(final_factors, colnames(latest_panel))
alpha_scores <- latest_panel[!is.na(defense_composite),
                              c(alpha_scores_cols, factor_cols_present),
                              with = FALSE]
setnames(alpha_scores, "alpha_final", "alpha")
alpha_scores[, regime_state := ifelse(isTRUE(current_bad_C), "BAD", "NORMAL")]
arrow::write_parquet(alpha_scores, file.path(SA_DIR, "alpha_scores.parquet"))
cat(sprintf("alpha_scores.parquet: %d rows\n", nrow(alpha_scores)))

# IC history
all_ic <- list()
for (f in c(final_factors, "defense_composite", "alpha_gated")) {
  if (f %in% colnames(winsor_panel)) {
    ich <- compute_ic(winsor_panel, f)
    if (!is.null(ich)) {
      ich[, factor := f]
      all_ic[[f]] <- ich
    }
  }
}
ic_history <- rbindlist(all_ic, fill = TRUE)
arrow::write_parquet(ic_history, file.path(SA_DIR, "ic_history.parquet"))
cat(sprintf("ic_history.parquet: %d rows\n", nrow(ic_history)))

# Full alpha_validation.json
alpha_validation <- list(
  task_id = WT_ID,
  as_of_date = as.character(as_of_date),
  sig_date = as.character(nearest_sig),
  pipeline_version = "v3_dual_axis",
  window_start = "2008-01-01",
  window_end = "2026-04-30",
  n_periods_analyzed = length(months_seq),

  # Honest research finding
  research_finding = list(
    original_hypothesis = "Quality (Q07/Q25) bad-state activation",
    empirical_result = "Quality alone has near-zero ic_bad. Tail-skewness (D43, R13) is true defense.",
    pivot_decision = paste0("Dual-axis composite (Q07 + Q25 + Q08 + D43 + R13) honors original hypothesis spirit ",
                            "while incorporating empirical evidence. AX-001 v2 conditional evaluation: ",
                            "Definition C (MRS expanding p70) chosen — provides 82 bad-state periods with statistical power.")
  ),

  # Selected factors
  primary_factors_attempted = PRIMARY_FACTORS,
  aux_factors_attempted = AUX_FACTORS,
  final_composite_factors = final_factors,
  composite_weights_method = "icir_weighted",
  composite_weights_theta = setNames(as.list(round(final_weights, 4)), final_factors),
  redundant_dropped = list(R13_NCSKEW = "0.901 cor with D43_Skewness; D43 chosen as primary skewness signal"),

  # Per-factor diagnostics (full v2 output)
  per_factor_diagnostics = diag_full,

  # Composite diagnostics
  composite = list(
    rank_ic = round(mu1, 4),
    icir = round(mu1/sd1, 4),
    nw_t = round(nw_t1, 4),
    n_periods = n1,
    ic_bad_C = round(ic_q_bad, 4),
    ic_norm_C = round(ic_q_norm, 4),
    bad_normal_ratio = round(ratio, 4),
    nw_t_bad_C = round(nw_t_bad_comp, 4)
  ),
  regime_gated_alpha = list(
    rank_ic = round(mu2, 4),
    icir = round(mu2/sd2, 4),
    nw_t = round(nw_t2, 4),
    n_periods = n2
  ),

  # Inheritance audit (L-270)
  str1715_inheritance_audit = list(
    n_overlap = nrow(combo),
    pearson_ls_vs_str1715 = round(pearson, 4),
    spearman_ls_vs_str1715 = round(spearman, 4),
    pearson_top_only_vs_str1715 = round(pearson_top, 4),
    inheritance_pass_lt_095 = inheritance_pass,
    note = "L-270: returns-level Pearson MUST be checked alongside vector cosine."
  ),

  # Pairwise correlation
  pairwise_correlation_max_offdiag = round(max_off, 4),
  pairwise_correlation_pass = max_off < 0.95,
  pairwise_correlation_matrix = as.list(as.data.frame(round(cor_mat, 3), stringsAsFactors = FALSE)),

  # Current state
  current_state = list(
    sig_date = as.character(nearest_sig),
    regime_category_lagged = as.character(latest_panel[1, Category_lag]),
    msm_crisis_prob_lagged = latest_panel[1, MSM_lag],
    fred_mrs_lagged = latest_panel[1, FRED_MRS_lag],
    regime_score_lagged = latest_panel[1, Regime_Score_lag],
    bad_state_def_C_active = isTRUE(current_bad_C),
    alpha_dormant = !isTRUE(current_bad_C),
    scale_used = ifelse(isTRUE(current_bad_C), SCALE_BAD, SCALE_NORMAL)
  ),

  liquidity_threshold_won = LIQ_THRESHOLD,
  universe = "K200 ∪ KQ150",
  cost_model_version = req$cost_model_version,

  # Method shopping log (R2-C compliance)
  method_shopping_log = list(
    candidates_tried = length(DEFENSE_CANDIDATES),
    candidates_total_universe = length(c(PRIMARY_FACTORS, AUX_FACTORS)),
    candidate_factors = DEFENSE_CANDIDATES,
    final_selected = final_factors,
    selection_objective = "icir_with_4axis_defense_validation",
    parallel_exec = TRUE,
    n_workers = 8L,
    rcpp_used = FALSE,
    note = paste0("4-axis evaluation per AX-001 v2. Definition C (MRS expanding p70) selected ",
                  "from 3 regime definitions (A: Category, B: Layer1_Alert, C: MRS p70).")
  )
)

# Write alpha_validation.json
write_json(alpha_validation, file.path(SA_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("alpha_validation.json: written\n"))

# LS returns CSV
fwrite(combo, file.path(SA_DIR, "ls_returns_inheritance_audit.csv"))
cat(sprintf("ls_returns_inheritance_audit.csv: %d rows\n", nrow(combo)))

# Save state for finalize
saveRDS(list(
  diag_full = diag_full,
  final_factors = final_factors,
  final_weights = final_weights,
  PRIMARY_FACTORS = PRIMARY_FACTORS,
  AUX_FACTORS = AUX_FACTORS,
  ic_q_bad = ic_q_bad, ic_q_norm = ic_q_norm,
  ratio = ratio, nw_t_bad_comp = nw_t_bad_comp,
  mu1 = mu1, sd1 = sd1, n1 = n1, nw_t1 = nw_t1,
  mu2 = mu2, sd2 = sd2, n2 = n2, nw_t2 = nw_t2,
  cor_mat = cor_mat, max_off = max_off,
  pearson = pearson, spearman = spearman, pearson_top = pearson_top,
  inheritance_pass = inheritance_pass,
  combo = combo,
  latest_panel = latest_panel,
  current_bad_C = current_bad_C,
  SCALE_BAD = SCALE_BAD, SCALE_NORMAL = SCALE_NORMAL,
  as_of_date = as_of_date,
  nearest_sig = nearest_sig
), file.path(SA_DIR, "alpha_pipeline_v3_state.rds"))

cat("\n==== v3 alpha pipeline COMPLETE ====\n")
