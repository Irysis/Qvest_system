#==============================================================================
# WT-D20260508_006 — Build alpha_package_draft.json from validation artifacts
# Run AFTER run_ipca_kr.R completes.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

WT_ID <- "WT-D20260508_006"
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))

setwd(PROJECT_ROOT)

av <- fromJSON(file.path(OUT_STAGE_DIR, "alpha_validation.json"), simplifyVector = FALSE)
alpha_dt <- as.data.table(read_parquet(file.path(OUT_STAGE_DIR, "alpha_scores.parquet")))
setorder(alpha_dt, Ticker)

cat("[draft] alpha_dt rows:", nrow(alpha_dt), "\n")

# ---- alpha_vector + confidence_vector dict ----
alpha_vector <- as.list(round(alpha_dt$alpha_ipca, 6))
names(alpha_vector) <- alpha_dt$Ticker
conf_vector <- as.list(round(alpha_dt$confidence, 4))
names(conf_vector) <- alpha_dt$Ticker

# ---- factor_specs ----
factor_specs <- av$factor_specs_summary

# ---- diagnostics ----
diag_obj <- list(
  rank_ic = round(av$diagnostics$mean_IC, 5),
  icir = round(av$diagnostics$ICIR, 4),
  monotonicity = round(av$diagnostics$monotonicity, 3),
  subperiod_stability = round(av$diagnostics$subperiod_stability, 3),
  turnover_proxy = NA_real_,
  harvey_t_stat = round(av$diagnostics$Harvey_t_NW, 3),
  post_neutralization_ic = round(av$diagnostics$mean_IC, 5),
  validation_mean_IC = round(av$diagnostics$validation_mean_IC, 5),
  validation_ICIR = round(av$diagnostics$validation_ICIR, 4),
  lockbox_mean_IC = round(av$diagnostics$lockbox_mean_IC, 5),
  lockbox_ICIR = round(av$diagnostics$lockbox_ICIR, 4),
  lockbox_LS_annualized_SR = round(av$diagnostics$lockbox_LS_annualized_SR, 3),
  lockbox_monotonicity = round(av$diagnostics$lockbox_monotonicity, 3),
  Bailey_LdP_DSR = round(av$diagnostics$Bailey_LdP_DSR, 3),
  LS_annualized_SR_full = round(av$diagnostics$LS_annualized_SR, 3),
  train_R2 = round(av$diagnostics$train_R2, 4),
  subperiod_breakdown = av$diagnostics$subperiod_breakdown,
  predictor_autocor_lag1_summary = list(
    median_across_chars = round(median(sapply(av$diagnostics$predictor_autocor_lag1, function(x) x$median_ac1)), 3),
    pct_high_ac_max = round(max(sapply(av$diagnostics$predictor_autocor_lag1, function(x) x$pct_high_ac)), 3)
  )
)

# ---- challenge_flags ----
cflags <- list()
graduation_fail_count <- 0L
fail_codes <- character()

if (av$diagnostics$mean_IC < 0.04) {
  cflags <- c(cflags, list(list(severity = "HIGH", code = "GRAD_RANK_IC_FAIL",
    detail = sprintf("rank_ic=%+.4f < 0.04 graduation threshold", av$diagnostics$mean_IC))))
  graduation_fail_count <- graduation_fail_count + 1L
  fail_codes <- c(fail_codes, "GRAD_RANK_IC_FAIL")
}
if (av$diagnostics$ICIR < 0.20) {
  cflags <- c(cflags, list(list(severity = "HIGH", code = "GRAD_ICIR_FAIL",
    detail = sprintf("ICIR=%+.4f < 0.20 Alpha Lab Gate threshold", av$diagnostics$ICIR))))
  graduation_fail_count <- graduation_fail_count + 1L
  fail_codes <- c(fail_codes, "GRAD_ICIR_FAIL")
}
if (abs(av$diagnostics$Harvey_t_NW) < 3.0) {
  cflags <- c(cflags, list(list(severity = "HIGH", code = "GRAD_HARVEY_T_FAIL",
    detail = sprintf("|Harvey_t_NW|=%.3f < 3.0 Harvey-Liu-Zhu multi-test threshold",
                     abs(av$diagnostics$Harvey_t_NW)))))
  graduation_fail_count <- graduation_fail_count + 1L
  fail_codes <- c(fail_codes, "GRAD_HARVEY_T_FAIL")
}
if (av$diagnostics$subperiod_stability < 0.50) {
  cflags <- c(cflags, list(list(severity = "HIGH", code = "GRAD_SUBPERIOD_INSTABILITY",
    detail = "subperiod_stability=0.0; 2010-14 IC=+0.058 → 2015-19 IC=-0.008 → 2020-24 IC=-0.039 = monotonic signal decay (1 of 3 subperiods positive)")))
  graduation_fail_count <- graduation_fail_count + 1L
  fail_codes <- c(fail_codes, "GRAD_SUBPERIOD_INSTABILITY")
}
if (av$diagnostics$validation_mean_IC < 0) {
  cflags <- c(cflags, list(list(severity = "HIGH", code = "VALIDATION_OOS_NEGATIVE",
    detail = sprintf("validation IC=%+.4f / ICIR=%+.4f (2023-2024, 24 periods)",
                     av$diagnostics$validation_mean_IC, av$diagnostics$validation_ICIR))))
  graduation_fail_count <- graduation_fail_count + 1L
  fail_codes <- c(fail_codes, "VALIDATION_OOS_NEGATIVE")
}
if (av$diagnostics$lockbox_mean_IC < 0) {
  cflags <- c(cflags, list(list(severity = "HIGH", code = "LOCKBOX_OOS_NEGATIVE",
    detail = sprintf("lockbox IC=%+.4f / ICIR=%+.4f (2025-01 ~ 2026-04, 16 periods, untouched during fit)",
                     av$diagnostics$lockbox_mean_IC, av$diagnostics$lockbox_ICIR))))
  graduation_fail_count <- graduation_fail_count + 1L
  fail_codes <- c(fail_codes, "LOCKBOX_OOS_NEGATIVE")
}
cflags <- c(cflags, list(list(severity = "INFO", code = "RF-A1_INFO",
  detail = "5 papers cited (KPS 2019 / BPZ 2024 / Novy-Marx 2013 / Jegadeesh-Titman 1993 / FF 1992). RF-A1 only triggers when ≤2 papers + subperiod<0.5; subperiod IS<0.5 here but >2 papers cited.")))
cflags <- c(cflags, list(list(severity = "INFO", code = "RF-A4_NA",
  detail = "post_neutralization_ic = rank_ic by construction (IPCA chars are cross-section z-scored per period; no separate sector neutral step). RF-A4 not applicable.")))

ac_med_max <- max(sapply(av$diagnostics$predictor_autocor_lag1, function(x) x$median_ac1))
if (ac_med_max > 0.93) {
  cflags <- c(cflags, list(list(severity = "MEDIUM", code = "PREDICTOR_AUTOCOR_HIGH",
    detail = sprintf("max char median lag-1 autocor=%.3f > 0.93 (S01_Size 0.933, Q01_GPA 0.911, V01_BM 0.905). KR Size + Quality slow-moving — partial signal decay risk.",
                     ac_med_max))))
}

# ---- Method shopping log ----
method_log <- list(
  candidates_tried = 5L,
  selected = av$characteristics_used,
  parallel_exec = TRUE,
  n_workers = 8L,
  rolling_seconds = 110.0,
  rcpp_used = FALSE,
  rcpp_rationale = "ALS L=6 K=4 T=156 < 1s convergence (37 iter). DSR is parametric Bailey-LdP closed form. Bootstrap not needed.",
  method_log = list(
    list(name = "V01_BM", instrument_role = "Value", selected = TRUE,
         reference = "Fama-French 1992 JFE"),
    list(name = "M01_Mom_12_1", instrument_role = "Momentum", selected = TRUE,
         reference = "Jegadeesh-Titman 1993 JF"),
    list(name = "Q01_GPA", instrument_role = "Quality", selected = TRUE,
         reference = "Novy-Marx 2013 JFE"),
    list(name = "S01_Size", instrument_role = "Size", selected = TRUE,
         reference = "Banz 1981 JFE / Fama-French 1992"),
    list(name = "L02_Turnover", instrument_role = "Liquidity", selected = TRUE,
         reference = "Datar-Naik-Radcliffe 1998 JFM")
  )
)

# ---- Window isolation log ----
window_isolation <- list(
  train_window = list(start = "2010-01-01", end = "2022-12-31", n_periods = 156L),
  validation_window = list(start = "2023-01-01", end = "2024-12-31", n_periods = 24L),
  lockbox_window = list(start = "2025-01-01", end = "2026-04-30", n_periods = 16L),
  forward_signal_date = "2026-04-30",
  forward_horizon = "1M",
  contamination_status = "isolated",
  notes = "Lockbox 16 periods completely untouched during ALS fit and Γ̂_α/Γ̂_β estimation. Only used for honest post-hoc OOS evaluation. Validation 24 periods for hyperparameter tuning (K=4 chosen ex-ante, no grid search performed)."
)

# ---- alpha_inheritance_cor ----
ortho_set <- av$orthogonality_vs_hybrid
alpha_inh_cor <- if (!is.null(ortho_set$wt_004) &&
                    is.list(ortho_set$wt_004) &&
                    isTRUE(ortho_set$wt_004$status == "evaluated")) {
  abs(as.numeric(ortho_set$wt_004$cor_pearson))
} else {
  NA_real_
}

# ---- Forward prediction summary ----
fwd_top5 <- alpha_dt[order(-alpha_ipca)][1:5,
  .(Ticker, alpha_ipca = round(alpha_ipca, 6), confidence = round(confidence, 3))]
fwd_bot5 <- alpha_dt[order(alpha_ipca)][1:5,
  .(Ticker, alpha_ipca = round(alpha_ipca, 6), confidence = round(confidence, 3))]

# ---- Decision ----
overall_decision <- if (graduation_fail_count >= 3L) {
  "GRADUATION_FAIL_HONEST_NEGATIVE"
} else if (graduation_fail_count >= 1L) {
  "GRADUATION_PARTIAL"
} else {
  "GRADUATION_PASS"
}

interp <- paste0(
  "Honest empirical: KPS 2019 IPCA framework applied to Korean cross-section ",
  "(K=4 latent factors + Γ_α intercept, L=6 chars including CONST, ",
  "T=156 train + 24 validation + 16 lockbox periods). ",
  "In-sample IC=+0.003 / ICIR=+0.022 / Harvey-t=+0.23 — well below graduation thresholds. ",
  "Subperiod IC: 2010-14 +0.058 → 2015-19 -0.008 → 2020-24 -0.039 = monotonic signal decay. ",
  "Validation IC -0.046 + Lockbox IC -0.027 = OOS negative (signal flipped post-2020). ",
  "Lockbox monotonicity -0.014, lockbox annual SR +0.295. ",
  "Alpha source mechanism (KPS 2019) academically valid but Korean data does not support ",
  "Γ̂_α stability post-2020. Hypothesis: Korean cross-section anomaly base rates ",
  "decayed (cf. AX-003 KR value EP_STANDALONE failed; AX-004 KR quality_profitability ",
  "single-signal long-only failed). ",
  "Ortho vs WT-D20260508_004 reference alpha = pearson 0.05 / spearman 0.05 PASS (<0.25). ",
  "Cross-section signals genuinely different but does not redeem negative absolute IC."
)

# ---- alpha_package_draft.json ----
pkg <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  selection_objective = "icir",
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  alpha_vector = alpha_vector,
  confidence_vector = conf_vector,
  alpha_discovery_count = length(alpha_vector),
  signal_matrix_ref = paste0("file://", file.path(OUT_STAGE_DIR, "alpha_scores.parquet")),
  factor_specs = factor_specs,
  diagnostics = diag_obj,
  alpha_inheritance_cor = alpha_inh_cor,
  challenge_flags = cflags,
  method_shopping_log = method_log,
  window_isolation = window_isolation,
  orthogonality_audit = ortho_set,
  forward_prediction = list(
    sig_date = "2026-04-30",
    horizon = "1M",
    n_stocks = nrow(alpha_dt),
    alpha_mean = round(mean(alpha_dt$alpha_ipca), 6),
    alpha_sd = round(sd(alpha_dt$alpha_ipca), 6),
    alpha_min = round(min(alpha_dt$alpha_ipca), 6),
    alpha_max = round(max(alpha_dt$alpha_ipca), 6),
    alpha_top5 = fwd_top5,
    alpha_bottom5 = fwd_bot5
  ),
  graduation_assessment = list(
    pass_count = 9L - graduation_fail_count,
    fail_count = graduation_fail_count,
    fail_codes = fail_codes,
    overall_decision = overall_decision,
    interpretation = interp,
    next_action = "Codex critique → challenge_note → if Codex APPROVE/REVISE then alpha_package.json finalize. Charter §8 No Silent Override applies. Risk/Optimizer downstream NOT warranted given 6/9 graduation FAILs absent explicit Q-Lead override."
  ),
  algorithm_metadata = list(
    algo = "IPCA_ALS_Kelly_Pruitt_Su_2019",
    K = 4L,
    L = 6L,
    unrestricted = TRUE,
    iter_used = av$iter_used,
    converged = av$converged,
    train_R2 = av$diagnostics$train_R2,
    convergence_notes = "ALS converged in 37 iterations with delta < tol after Q-decomposition orthogonalization step."
  ),
  references = list(
    "Kelly, B. T., Pruitt, S., & Su, Y. (2019). Characteristics are covariances: A unified model of risk and return. Journal of Financial Economics, 134(3), 501-524.",
    "Bryzgalova, S., Pelger, M., & Zhu, J. (2024). Forest through the trees: Building cross-sections of stock returns. Review of Financial Studies, forthcoming.",
    "Novy-Marx, R. (2013). The other side of value: The gross profitability premium. Journal of Financial Economics, 108(1), 1-28.",
    "Jegadeesh, N., & Titman, S. (1993). Returns to buying winners and selling losers: Implications for stock market efficiency. Journal of Finance, 48(1), 65-91.",
    "Fama, E. F., & French, K. R. (1992). The cross-section of expected stock returns. Journal of Finance, 47(2), 427-465.",
    "Banz, R. W. (1981). The relationship between return and market value of common stocks. Journal of Financial Economics, 9(1), 3-18.",
    "Datar, V. T., Naik, N. Y., & Radcliffe, R. (1998). Liquidity and stock returns: An alternative test. Journal of Financial Markets, 1(2), 203-219.",
    "Bailey, D. H., & López de Prado, M. (2014). The deflated Sharpe ratio. Journal of Portfolio Management, 40(5), 94-107.",
    "Harvey, C. R., Liu, Y., & Zhu, H. (2016). ...and the cross-section of expected returns. Review of Financial Studies, 29(1), 5-68."
  ),
  saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

# ---- Write draft ----
draft_path <- file.path(OUT_WT_DIR, "alpha_package_draft.json")
write_json(pkg, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[draft] saved:", draft_path, "\n")
cat("[draft] alpha_discovery_count:", pkg$alpha_discovery_count, "\n")
cat("[draft] graduation_fail_count:", graduation_fail_count, "\n")
cat("[draft] decision:", overall_decision, "\n")
cat("[draft] alpha_inheritance_cor:", round(alpha_inh_cor, 4), "\n")

# ---- Lineage ----
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package_draft",
    method_selected = "IPCA_ALS K=4 unrestricted L=6",
    input_file_paths = c(
      "02_Infrastructure/factor_db/factor_db_connector.R",
      ".cache/rawdata.parquet",
      "stage_artifacts/WT_WT-D20260508_006/alpha_scores.parquet",
      "stage_artifacts/WT_WT-D20260508_006/alpha_validation.json"
    )
  )
  cat("[lineage] recorded\n")
}, error = function(e) {
  cat("[lineage] WARN: ", conditionMessage(e), "\n")
})
