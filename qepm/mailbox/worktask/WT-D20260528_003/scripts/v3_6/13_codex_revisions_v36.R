#==============================================================================
# Codex Round Revisions v3.6 — Post-Codex 9-Concern Fixes
#
# Codex stance: REJECT (5 HIGH + 3 MEDIUM + 1 LOW concerns)
#
# Fixes:
#   C3 ACCEPT: Recompute fallback over all 82 alpha dates (36.6% != 10.8%)
#   C4 ACCEPT: Clip regime state counts at signal_cutoff (2023-12-22)
#   C5 ACCEPT: Emit alpha_vector at latest pre-cutoff sig_date WITHOUT fwd_ret dependency
#   C6 PARTIAL: Stage artifacts namespace fix (WT_WT-... vs WT_D20260528_003_v3_6)
#   C7 PARTIAL: PIT-C15 macro retain (architect advisory)
#   C8 REBUTTAL: AX-005/007 Optimizer scope
#   C9 ACCEPT: Liquidity 50M vs 200M conflict declaration
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
WT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")
# C6: also create namespace-correct stage dir (WT_WT-D20260528_003 per Codex)
STAGE_DIR_CODEX <- file.path(BASE, "qepm/stage_artifacts/WT_WT-D20260528_003")
dir.create(STAGE_DIR_CODEX, showWarnings = FALSE, recursive = TRUE)

SIG_CUTOFF <- as.Date("2023-12-22")

cat("[Codex Revisions v3.6] === START ===\n")
t0 <- Sys.time()

# ---- C3 FIX: Recompute fallback over all 82 alpha dates ----
cat("[C3] Recompute fallback over all 82 alpha dates ...\n")
state_w <- as.data.table(read_parquet(file.path(OUT_DIR, "regime_family_weights_v36.parquet")))
alpha_rw <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_regime_weighted_neut_v36.parquet")))
all_alpha_ym <- unique(format(as.Date(alpha_rw$Date), "%Y-%m"))
n_total <- length(all_alpha_ym)

n_state_specific <- sum(state_w$weight_source == "state_specific")
n_fallback_strict <- sum(state_w$weight_source == "all_state_fallback")
n_bootstrap <- sum(state_w$weight_source == "bootstrap_overall")
n_no_weight_row <- n_total - nrow(state_w)

fallback_full <- n_total - n_state_specific
fallback_pct_full <- fallback_full / n_total

C3_corrected <- list(
  n_total_alpha_dates = n_total,
  n_state_specific = n_state_specific,
  state_specific_pct = round(n_state_specific / n_total * 100, 1),
  n_all_state_fallback = n_fallback_strict,
  n_bootstrap_overall = n_bootstrap,
  n_no_weight_row_equal_weight = n_no_weight_row,
  fallback_full_count = fallback_full,
  fallback_full_pct = round(fallback_pct_full * 100, 1),
  threshold_30 = 30,
  pass_30 = fallback_pct_full < 0.30,
  codex_C3_verdict = "ACCEPT — Codex correct, fix 2 hmm regime reduction overstated. Actual non-state-specific = 36.6% > 30% target. Pre-Codex report of 10.8% only counted 65 state_w rows, missed 17 alpha months without weight rows."
)
cat("  Full fallback over 82 dates:", round(fallback_pct_full*100, 1), "% (target <30: FAIL)\n")

# ---- C4 FIX: Clip regime state counts at signal_cutoff ----
cat("[C4] Clip regime state counts at signal_cutoff (2023-12-22) ...\n")
regime_monthly <- as.data.table(read_parquet(file.path(OUT_DIR, "regime_labels_monthly_v36.parquet")))
regime_monthly[, Date := as.Date(Date)]
pre_cutoff <- regime_monthly[Date <= SIG_CUTOFF]
post_cutoff <- regime_monthly[Date > SIG_CUTOFF]

pre_state_n <- as.list(table(pre_cutoff$regime_state))
names(pre_state_n) <- paste0("S", names(pre_state_n))
post_state_n <- as.list(table(post_cutoff$regime_state))
names(post_state_n) <- paste0("S", names(post_state_n))

# Pre-cutoff persistence
labels_pre <- as.data.table(read_parquet(file.path(OUT_DIR, "regime_labels_daily_v36.parquet")))
labels_pre[, Date := as.Date(Date)]
labels_pre <- labels_pre[Date <= SIG_CUTOFF & !is.na(regime_state)]
n_states <- 4L
trans_mat_pre <- matrix(0, nrow = n_states, ncol = n_states,
                          dimnames = list(paste0("S", 1:n_states), paste0("S", 1:n_states)))
lab_pre <- labels_pre$regime_state
for (i in seq_len(length(lab_pre) - 1L)) {
  trans_mat_pre[lab_pre[i], lab_pre[i+1L]] <- trans_mat_pre[lab_pre[i], lab_pre[i+1L]] + 1
}
trans_mat_pre_norm <- trans_mat_pre / pmax(rowSums(trans_mat_pre), 1)
persistence_pre <- diag(trans_mat_pre_norm)

C4_corrected <- list(
  pre_cutoff_total_monthly = nrow(pre_cutoff),
  post_cutoff_total_monthly = nrow(post_cutoff),
  pre_cutoff_state_counts = pre_state_n,
  post_cutoff_state_counts = post_state_n,
  pre_cutoff_persistence = setNames(round(persistence_pre, 4), paste0("S", 1:4)),
  target_per_state_n_30 = 30,
  pre_cutoff_pass_30 = all(unlist(pre_state_n) >= 30),
  codex_C4_verdict = "ACCEPT — Pre-cutoff (PIT-strict) state counts: S1=8 / S2=4 / S3=17 / S4=37. Only S3 and S4 meet n>=30 target. S2 reduced from 9 (full) to 4 (pre-cutoff) — confirms post-cutoff diagnostic contamination. PIT-C1 violation."
)
cat("  Pre-cutoff state counts: S1=", pre_state_n$S1, "/ S2=", pre_state_n$S2,
    "/ S3=", pre_state_n$S3, "/ S4=", pre_state_n$S4, "\n")

# ---- C5 FIX: Emit alpha_vector at latest pre-cutoff sig_date without fwd_ret dependency ----
cat("[C5] Emit alpha_vector at latest pre-cutoff sig_date (PIT-strict, no fwd_ret) ...\n")
# Use sector-neutralized panel + regime weights, no fwd_ret
panel_neut <- as.data.table(read_parquet(file.path(OUT_DIR, "k200_factor_panel_sector_neut_v36.parquet")))
panel_neut[, Date := as.Date(Date)]
fam_cols <- c("F_value", "F_quality", "F_momentum", "F_growth",
               "F_consensus", "F_low_vol", "F_size", "F_dividend")
neut_cols <- paste0(fam_cols, "_neut")
panel_neut_pre <- panel_neut[Date <= SIG_CUTOFF]
latest_d <- max(panel_neut_pre$Date)
cat("  Latest pre-cutoff sig_date (panel):", as.character(latest_d), "\n")

# For latest_d we need regime_state(t-1) lag and family weights
ym_latest <- format(latest_d, "%Y-%m")

# Use t-1 regime via regime_monthly (PIT-strict)
regime_pre <- regime_monthly[Date <= latest_d]
setorder(regime_pre, Date)
# Find latest regime_state strictly before latest_d
lag_regime <- regime_pre[Date < latest_d]
if (nrow(lag_regime) == 0) {
  stop("No prior regime state for lag, cannot emit PIT-safe alpha")
}
regime_lag1 <- tail(lag_regime$regime_state, 1)
cat("  Latest regime_state_lag1 (PIT-safe):", regime_lag1, "\n")

# Compute family weights from past IC observations (PIT-strict: data <= latest_d)
ic_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "family_ic_per_date_v36.parquet")))
ic_dt[, Date := as.Date(Date)]
ic_past <- ic_dt[Date < latest_d]  # strictly past
# Merge regime lag
ic_past[, ym := format(Date, "%Y-%m")]
ic_past <- merge(ic_past, regime_monthly[, .(ym = format(Date, "%Y-%m"), regime_state)], by = "ym")
setorder(ic_past, Date)
ic_past[, regime_state_lag1 := shift(regime_state, n = 1L, type = "lag")]
ic_past_state <- ic_past[regime_state_lag1 == regime_lag1 & !is.na(regime_state_lag1)]

fam_labels <- c("value", "quality", "momentum", "growth", "consensus", "low_vol", "size", "dividend")
ic_cols <- paste0("ic_F_", fam_labels, "_neut")

if (nrow(ic_past_state) >= 3L) {
  wts <- sapply(ic_cols, function(c) mean(ic_past_state[[c]], na.rm = TRUE))
  wts[is.na(wts)] <- 0
  wts[wts < 0] <- 0
  if (sum(wts) > 1e-10) wts <- wts / sum(wts) else wts <- rep(1/8, 8)
  weight_source <- "state_specific"
} else {
  wts <- sapply(ic_cols, function(c) mean(ic_past[[c]], na.rm = TRUE))
  wts[is.na(wts)] <- 0
  wts[wts < 0] <- 0
  if (sum(wts) > 1e-10) wts <- wts / sum(wts) else wts <- rep(1/8, 8)
  weight_source <- "all_state_fallback"
}
names(wts) <- fam_labels
cat("  Family weights at latest_d (source=", weight_source, "):\n")
print(round(wts, 3))

# Apply to latest_d panel
latest_panel <- panel_neut[Date == latest_d]
alpha_new <- numeric(nrow(latest_panel))
for (k in seq_along(fam_labels)) {
  nc <- paste0("F_", fam_labels[k], "_neut")
  x <- latest_panel[[nc]]
  x[is.na(x)] <- 0
  alpha_new <- alpha_new + wts[k] * x
}
latest_alpha_dt <- data.table(Date = latest_d, Ticker = latest_panel$Ticker, alpha_rw = alpha_new)
setorder(latest_alpha_dt, -alpha_rw)

cat("  alpha_vector at", as.character(latest_d), ": N=", nrow(latest_alpha_dt),
    " | mean=", round(mean(latest_alpha_dt$alpha_rw), 3),
    " | range:", round(min(latest_alpha_dt$alpha_rw),3), "~",
    round(max(latest_alpha_dt$alpha_rw),3), "\n")

# Update alpha_scores.parquet to include latest_d (no fwd_ret dependency, leaves fwd_ret=NA)
alpha_scores_full <- rbind(alpha_rw[, .(Date, Ticker, alpha_rw, fwd_ret)],
                            latest_alpha_dt[, .(Date, Ticker, alpha_rw, fwd_ret = NA_real_)])
alpha_scores_full <- unique(alpha_scores_full, by = c("Date", "Ticker"))
setorder(alpha_scores_full, Date, Ticker)

# Save full + sector_neut basis alpha_scores
out_alpha_scores <- alpha_scores_full[, .(Date, Ticker, alpha_score = alpha_rw, alpha_confidence_proxy = 0.5)]
write_parquet(out_alpha_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))
write_parquet(out_alpha_scores, file.path(STAGE_DIR_CODEX, "alpha_scores.parquet"))
write_parquet(out_alpha_scores, file.path(OUT_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet updated to latest_d", as.character(latest_d), "in 3 locations\n")

C5_corrected <- list(
  latest_pre_cutoff_sig_date = as.character(latest_d),
  v3_5_emit_date = "2023-10-31",
  delta_days = as.integer(latest_d - as.Date("2023-10-31")),
  alpha_vector_N = nrow(latest_alpha_dt),
  alpha_vector_mean = round(mean(latest_alpha_dt$alpha_rw), 4),
  weight_source_at_latest_d = weight_source,
  regime_state_lag1_at_latest_d = regime_lag1,
  pit_safe_basis = "Family panel (sector-neut Z), regime_state_lag1 (PIT-strict, prior month), past IC mean for weight derivation (Date < latest_d). No fwd_ret label dependency.",
  codex_C5_verdict = "ACCEPT — alpha_vector regenerated for latest pre-cutoff sig_date without fwd_ret dependency. Production-grade PIT-safe emission."
)

# ---- C6 FIX: Stage artifacts namespace ----
cat("[C6] Stage artifacts namespace ...\n")
# Copy alpha_validation.json to Codex-expected path
file.copy(file.path(STAGE_DIR, "alpha_validation.json"),
          file.path(STAGE_DIR_CODEX, "alpha_validation.json"), overwrite = TRUE)
cat("  Mirrored alpha_validation.json to qepm/stage_artifacts/WT_WT-D20260528_003/\n")

C6_partial <- list(
  codex_expected_path = "qepm/stage_artifacts/WT_WT-D20260528_003",
  our_actual_path = "stage_artifacts/WT_D20260528_003_v3_6",
  mirror_created = TRUE,
  mirror_path = "qepm/stage_artifacts/WT_WT-D20260528_003",
  missing_artifacts = c("weights.csv (Optimizer responsibility)",
                         "covariance.parquet (Risk responsibility)",
                         "risk_package.json (Risk responsibility, alpha stage 산출물 아님)",
                         "optimization_package.json (Optimizer responsibility, alpha stage 산출물 아님)"),
  codex_C6_verdict = "PARTIAL — namespace mirror created. Missing artifacts (weights/covariance/risk/optimizer) are 정상적으로 alpha 단계 산출 X (Common Charter §8 역할 경계). 본 alpha 단계의 AX-008 evaluable artifacts: alpha_package + alpha_scores + alpha_validation + challenge_note 4종 완비."
)

# ---- C9 FIX: Liquidity threshold conflict ----
cat("[C9] Liquidity threshold conflict ...\n")
C9_corrected <- list(
  request_json_floor = 50000000,
  base_hard_floor = 200000000,
  v3_6_uses = 50000000,
  conflict_root_cause = "request.json universe_definition.liquidity_min_won_20d_avg = 5e7. Base Production Constraint = 2e8.",
  q_lead_governance_decision_needed = TRUE,
  codex_C9_verdict = "ACCEPT — base hard mandate 2e8 KRW LIQ floor not cleanly enforced (request.json overrides to 5e7). Q-Lead governance: confirm whether base constraint 200M applies or request.json 50M for this WT."
)

# ---- Combine + Save Codex revisions diagnostic ----
codex_revisions <- list(
  codex_stance_received = "REJECT",
  codex_concerns_total = 9,
  codex_concerns_HIGH = 5,
  codex_concerns_MEDIUM = 3,
  codex_concerns_LOW = 1,
  adjudication = list(
    C1_RF_A6_AX001_FAIL = list(severity = "HIGH", adjudication = "ACCEPT",
      rationale = "Graduation FAIL confirmed: Rank IC 0.020 + Harvey 0/5 + DSR 0.0 + AX-001 v2 crisis_alpha NEGATIVE. ICIR 0.224 alone insufficient."),
    C2_RF_A2 = list(severity = "HIGH", adjudication = "ACCEPT",
      rationale = "composite_rw_neut 0.224 < single F_low_vol_raw 0.386 and < F_low_vol_neut 0.275. 8-family regime composite dilutes."),
    C3_HMM_fix_overstated = list(severity = "HIGH", adjudication = "ACCEPT",
      rationale = "Pre-Codex fallback 10.8% (over 65 state_w rows) MISLEADING. Full fallback over 82 alpha dates = 36.6%. Above 30% target. Fix 2 PASS retracted.",
      corrected_metrics = C3_corrected),
    C4_post_cutoff_diagnostic = list(severity = "HIGH", adjudication = "ACCEPT",
      rationale = "Pre-Codex state counts S2=9 included post-cutoff data. Pre-cutoff strict: S2=4. PIT-C1 violation in diagnostic.",
      corrected_metrics = C4_corrected),
    C5_alpha_vector_stale = list(severity = "HIGH", adjudication = "ACCEPT",
      rationale = "Pre-Codex alpha_vector at 2023-10-31 stale (fwd_ret label dependency). Latest pre-cutoff sig_date emitted without fwd_ret.",
      corrected_metrics = C5_corrected),
    C6_AX_008_triangulation = list(severity = "HIGH", adjudication = "PARTIAL",
      rationale = "Mirror to qepm/stage_artifacts/WT_WT-D20260528_003 created. Missing weights/covariance/risk/optimization packages = expected per Common Charter §8 (alpha 단계 산출 X).",
      corrected = C6_partial),
    C7_PIT_C15_macro = list(severity = "MEDIUM", adjudication = "PARTIAL",
      rationale = "Macro time-series via load_month_factors() API gap (architect advisory). PIT-C9 expanding-z PIT 본질 보장. C15 strict literal interpretation only fails.",
      action = "Architect agent advisory queue 적립 — load_macro_factors() API 신설 권고"),
    C8_AX_005_007_optimizer_scope = list(severity = "MEDIUM", adjudication = "REBUTTAL",
      rationale = "AX-007/005 EXCLUSION proof는 Optimizer/Judge 단계 책임 (Common Charter §8 역할 경계). Alpha agent의 산출은 universe-wide score, downstream에서 evaluate."),
    C9_liquidity_conflict = list(severity = "LOW", adjudication = "ACCEPT",
      rationale = "request.json 5e7 vs base hard mandate 2e8 conflict. Q-Lead governance decision.",
      corrected = C9_corrected)
  ),
  rationalization_red_flags_detected_by_codex = list(
    "Markov chain persistence high mitigates sparse-state risk",
    "only required >=8 for HMM identification",
    "load_month_factors() designed for cross-section Z assignment doesn't apply",
    "Score-based universe alpha vector; downstream Optimizer responsibility",
    "Mitigation downstream: forge backtest carry-forward semantics"
  ),
  self_rationalization_acknowledged = TRUE,
  self_rationalization_action = "5 expressions flagged. C7+C8 PARTIAL/REBUTTAL retain with explicit role boundary citations. C3+C4+C5 ACCEPT with direct metric correction (no rationalization retain).",
  high_severity_count = 5,
  q_lead_auto_escalate = TRUE,
  q_lead_auto_escalate_reason = "HIGH severity = 5 (threshold ≥ 5). AX-001 v2 hard FAIL (crisis_alpha negative). PIT-C1 violation (C4 post-cutoff diagnostic).",
  final_verdict = "v3.6 PIVOT GRADUATION FAIL CONFIRMED. Charter §5 Data Mining 방지 정합 — 3 cycles FAIL → TERMINATE STR_1721 family. Codex adjudication: ACCEPT 6 + PARTIAL 2 + REBUTTAL 1.",
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)

writeLines(toJSON(codex_revisions, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "codex_revisions_v36.json"))
cat("\n[Codex Revisions v3.6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")

cat("\n=== Codex Revisions Summary ===\n")
cat("  C3 fallback recomputed (10.8% → 36.6% over 82 dates)\n")
cat("  C4 pre-cutoff state counts (S2: 9 → 4)\n")
cat("  C5 alpha_vector latest pre-cutoff sig_date:", as.character(latest_d),
    "(advance from 2023-10-31)\n")
cat("  C6 namespace mirror created: qepm/stage_artifacts/WT_WT-D20260528_003/\n")
cat("  C9 liquidity 50M vs 200M conflict acknowledged\n")
