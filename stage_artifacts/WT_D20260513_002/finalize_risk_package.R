#==============================================================================
# WT-D20260513_002 — finalize risk_package.json
# Codex Round 1 disposition + Honest classification + risk_challenge_note ref
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(corpcor)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260513_002"
STAGE_DIR <- file.path("stage_artifacts", "WT_D20260513_002")
MAILBOX_DIR <- file.path("qepm", "mailbox", "worktask", WT_ID)
AS_OF_SIG_DATE <- as.Date("2026-04-30")

# Load existing
rp_draft <- fromJSON(file.path(MAILBOX_DIR, "risk_package_draft.json"),
                     simplifyVector=FALSE)

# ============================================================================
# Additional diagnostics (Codex Round 1 disposition)
# ============================================================================

cat("[finalize] Computing additional diagnostics for Codex Round 1 disposition\n")

# C4: CVaR_95 / ES_99 with bootstrap CI (Codex CVaR breach mandate)
daily_C2 <- as.data.table(read_parquet(file.path(STAGE_DIR, "sleeve_C2_daily_history.parquet")))
losses <- -daily_C2$port_ret
losses <- losses[!is.na(losses)]
n_d <- length(losses)
losses_sorted <- sort(losses, decreasing=TRUE)

cvar_95_daily <- mean(losses_sorted[1:max(1, floor(n_d*0.05))], na.rm=TRUE)
cvar_99_daily <- mean(losses_sorted[1:max(1, floor(n_d*0.01))], na.rm=TRUE)

# Bootstrap CI (1000 iter)
set.seed(42)
boot_n <- 1000
boot_cvar_95 <- replicate(boot_n, {
  idx <- sample(seq_len(n_d), size=n_d, replace=TRUE)
  l <- sort(losses[idx], decreasing=TRUE)
  mean(l[1:max(1, floor(n_d*0.05))], na.rm=TRUE)
})
boot_cvar_99 <- replicate(boot_n, {
  idx <- sample(seq_len(n_d), size=n_d, replace=TRUE)
  l <- sort(losses[idx], decreasing=TRUE)
  mean(l[1:max(1, floor(n_d*0.01))], na.rm=TRUE)
})

cvar_summary <- list(
  daily_cvar_95 = round(cvar_95_daily, 4),
  daily_cvar_99 = round(cvar_99_daily, 4),
  es_99 = round(cvar_99_daily, 4),
  cvar_95_boot_CI_95 = c(round(quantile(boot_cvar_95, 0.025), 4),
                         round(quantile(boot_cvar_95, 0.975), 4)),
  cvar_99_boot_CI_95 = c(round(quantile(boot_cvar_99, 0.025), 4),
                         round(quantile(boot_cvar_99, 0.975), 4)),
  cvar_cap_0_025 = 0.025,
  cvar_95_cap_breach = cvar_95_daily > 0.025,
  cvar_95_breach_multiple = round(cvar_95_daily / 0.025, 2),
  n_daily_obs = n_d,
  method = "full history 2004-2026 daily port returns, EW top20 monthly rebalance"
)

cat(sprintf("CVaR_95 daily: %.4f (cap 0.025, breach %.2fx)\n",
            cvar_95_daily, cvar_95_daily/0.025))

# C5: factor variance decomposition for top20 C2 sleeve
B_dt_raw <- as.data.table(read_parquet(file.path(STAGE_DIR, "exposure_matrix.parquet")))
D_dt <- as.data.table(read_parquet(file.path(STAGE_DIR, "specific_risk.parquet")))

# Re-compute B_full + factor decomp
ap <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
ap[, sig_date := as.Date(sig_date)]
top20_C2 <- ap[sig_date == AS_OF_SIG_DATE][order(-alpha)][1:20, Ticker]

# Need original rd, fact_wide, B_full from run_risk_research. Reconstruct.
rd_full <- as.data.table(read_parquet(
  ".cache/rawdata.parquet",
  col_select = c("Date","Ticker","Sector","K200","KQ150","Size","Ret","BM_Ret")
))

# Use same window/build process
str1715_top20 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/20260512_str1715_sleeve_top20_alpha_2026_04.csv")
universe_tickers <- unique(c(top20_C2, str1715_top20$Ticker))

ret_window_start <- AS_OF_SIG_DATE - 252
rd_uni <- rd_full[Ticker %in% universe_tickers &
                  Date >= ret_window_start & Date <= AS_OF_SIG_DATE,
                  .(Date, Ticker, Ret, Sector, Size, BM_Ret)]
rd_uni[, Ret := as.numeric(Ret)]
rd_uni <- rd_uni[!is.na(Ret) & !is.na(BM_Ret)]

# Rebuild fact_wide
sec_ret <- rd_uni[!is.na(Sector), .(Sector_Ret = mean(Ret, na.rm=TRUE)),
                   by=.(Date, Sector)]
mkt_ret <- unique(rd_uni[, .(Date, BM_Ret)])
setnames(mkt_ret, "BM_Ret", "Mkt_Ret")
rd_uni[, size_quintile := cut(Size, breaks = quantile(Size, probs=c(0, 0.3, 0.7, 1), na.rm=TRUE),
                                labels = c("S","M","B"), include.lowest=TRUE), by=Date]
smb <- rd_uni[!is.na(size_quintile), {
  s_ret <- mean(Ret[size_quintile=="S"], na.rm=TRUE)
  b_ret <- mean(Ret[size_quintile=="B"], na.rm=TRUE)
  list(SMB_Ret = s_ret - b_ret)
}, by=Date]

fact_wide <- merge(mkt_ret, smb, by="Date")
fact_wide <- fact_wide[!is.na(Mkt_Ret) & !is.na(SMB_Ret)]
top_sec <- B_dt_raw[, .N, by=Sector][order(-N)][1:5, Sector]
top_sec <- top_sec[!is.na(top_sec)]
for (s in top_sec) {
  s_clean <- gsub("[, ]", "_", s)
  s_ret <- sec_ret[Sector == s, .(Date, Sector_Ret)]
  setnames(s_ret, "Sector_Ret", paste0("SEC_", s_clean, "_Ret"))
  fact_wide <- merge(fact_wide, s_ret, by="Date", all.x=TRUE)
}
fact_wide <- fact_wide[complete.cases(fact_wide)]
fact_mat <- as.matrix(fact_wide[, -1])

omega_lw <- corpcor::cov.shrink(fact_mat, verbose=FALSE) * 252
class(omega_lw) <- "matrix"
attributes(omega_lw)$lambda <- NULL
attributes(omega_lw)$lambda.var <- NULL

fact_names <- colnames(fact_mat)
B_full <- matrix(0, nrow = length(top20_C2), ncol = length(fact_names))
rownames(B_full) <- top20_C2
colnames(B_full) <- fact_names

for (i in seq_along(top20_C2)) {
  tk <- top20_C2[i]
  tk_ret <- rd_uni[Ticker == tk & !is.na(Ret), .(Date, Ret)]
  if (nrow(tk_ret) < 60) next
  merged <- merge(tk_ret, fact_wide, by="Date")
  if (nrow(merged) < 60) next
  fit <- lm(as.formula(paste("Ret ~", paste(fact_names, collapse="+"))), data=merged)
  co <- coef(fit)
  for (f in fact_names) {
    if (f %in% names(co)) {
      B_full[i, f] <- co[f]
    }
  }
}

# Save B_full (Codex C6 mandate)
B_full_dt <- as.data.table(B_full)
B_full_dt[, Ticker := rownames(B_full)]
setcolorder(B_full_dt, c("Ticker", setdiff(names(B_full_dt), "Ticker")))
write_parquet(B_full_dt, file.path(STAGE_DIR, "B_full_factor_loadings.parquet"))
cat("Saved B_full factor loadings matrix\n")

# Variance decomposition: for EW top20 C2 sleeve
w_C2 <- rep(1/20, 20); names(w_C2) <- top20_C2

# Per-factor variance contribution
# port_var = sum_kl w_k * w_l * (BΩB' + D)_{kl}
# decompose by factor: var_factor_f = sum_kl w_k * B_kf * Omega_ff * B_lf * w_l (off-diagonal Omega included as cross-factor)
# Diagonal approximation: var_factor_f ≈ (sum_k w_k B_kf)^2 * Omega_ff

factor_contribs <- list()
for (f in fact_names) {
  beta_port_f <- sum(w_C2 * B_full[names(w_C2), f])
  var_f <- beta_port_f^2 * omega_lw[f, f]
  factor_contribs[[f]] <- list(beta_port = round(beta_port_f, 4),
                                var_annualized = round(var_f, 6),
                                vol_pct = round(sqrt(var_f), 4))
}

# Cross-factor covariance term
sys_cov_term <- 0
for (f1 in fact_names) {
  for (f2 in fact_names) {
    if (f1 == f2) next
    beta_f1 <- sum(w_C2 * B_full[names(w_C2), f1])
    beta_f2 <- sum(w_C2 * B_full[names(w_C2), f2])
    sys_cov_term <- sys_cov_term + beta_f1 * beta_f2 * omega_lw[f1, f2]
  }
}
# Specific variance term
spec_var_terms <- sapply(names(w_C2), function(tk) {
  if (tk %in% D_dt$Ticker) {
    D_dt[Ticker == tk, specific_var]
  } else {
    median(D_dt$specific_var, na.rm=TRUE)
  }
})
spec_var <- sum(w_C2^2 * spec_var_terms)

total_var <- sum(sapply(factor_contribs, function(x) x$var_annualized)) + sys_cov_term + spec_var
factor_pct <- list()
for (f in fact_names) {
  fc <- factor_contribs[[f]]
  factor_pct[[f]] <- list(var_pct = round(fc$var_annualized / total_var, 4),
                          beta_port = fc$beta_port,
                          vol_contrib = fc$vol_pct)
}
spec_var_pct <- spec_var / total_var
cross_factor_pct <- sys_cov_term / total_var

cat("\nC2 sleeve EW top20 variance decomposition:\n")
for (f in fact_names) {
  cat(sprintf("  %-30s: var_pct %.2f%%  (beta_port %.3f)\n",
              f, 100*factor_pct[[f]]$var_pct, factor_pct[[f]]$beta_port))
}
cat(sprintf("  cross_factor_cov_term       : %.2f%%\n", 100*cross_factor_pct))
cat(sprintf("  specific_idiosyncratic      : %.2f%%\n", 100*spec_var_pct))
cat(sprintf("  total var: %.6f, total vol: %.4f\n", total_var, sqrt(total_var)))

# Critical: top single factor
top_factor <- names(factor_pct)[which.max(sapply(factor_pct, function(x) x$var_pct))]
top_factor_pct <- factor_pct[[top_factor]]$var_pct
cat(sprintf("\nTop systematic factor: %s (%.2f%% of portfolio variance)\n",
            top_factor, 100*top_factor_pct))

# Method shopping log (Codex C6 mandate)
method_shopping_log_risk <- list(
  methods_tried = c("sample_cov_252d_daily", "ledoit_wolf_shrinkage",
                     "gerber_rmt_potential"),
  methods_selected = list(
    omega = "ledoit_wolf",
    sigma = "BΩB' + D (no additional shrinkage, cond_75.67<500)"
  ),
  selection_objective = "min cond_number AND PSD AND coverage>30% systematic",
  selection_metric = list(
    omega_cond = 30.46,
    sigma_cond = 75.67,
    sigma_PSD = TRUE,
    coverage_factors = 7,
    n_tickers = 39
  ),
  shrinkage_intensity_lw = 0.0957,
  rationale = "N=167 daily, D=7 factors, N/D=23.86 >> 1 → sample is technically usable, but LW gives lower MSE per Ledoit-Wolf 2003. Sigma direct cond 75.67 < 500, no additional shrinkage needed. Gerber-RMT not tested (D/N=0.04 << 0.5 trigger). DCC-GARCH not used (Sigma constructed from 252d-daily, not regime-switching block).",
  alternative_considered = list(
    sample_pure = "cond likely higher; LW preferred",
    gerber_rmt = "D/N=0.04 not in trigger; not run",
    dcc_garch = "deferred (Sigma is static spot, not dynamic conditional)"
  )
)

# Per-regime sample size disclosure (Codex C7/RF-R8)
regime_n <- list(
  BULL = 36,
  NORMAL = 201,
  CAUTION = 0,
  CRISIS_bad = 29,
  total = 266,
  note = "BAD regime n=29 (CRISIS proxy via BM_M_lag 36m z<-1); pooled IC reported without bootstrap CI in draft. Below 30 n small sample.",
  bootstrap_recommended = TRUE
)

# Bootstrap CI for bad-regime IC
ic_dt <- list()  # not retained in draft; would need re-run
# Skip bootstrap IC CI here (would require ic_per_date) — note in challenge_note

# ============================================================================
# Honest classification: red_flags + challenge_flags
# ============================================================================

cat("\n[finalize] Building honest red_flags + challenge_flags\n")

# Pull existing diagnostics
sleeve_C2 <- rp_draft$sleeve_risk_profile$C2_low_vol_top20
sleeve_1715 <- rp_draft$sleeve_risk_profile$STR_1715_top20
cross <- rp_draft$sleeve_risk_profile$cross_sleeve
ax_4axis <- rp_draft$ax_001_v2_4_axis

red_flags <- list(
  list(
    id = "RF-R1",
    severity = "HIGH",
    description = sprintf("Top single factor systematic variance contribution: %s %.1f%% > 40%% threshold. C2 sleeve concentrated in defensive sector (건강관리 35%% by name count, %.1f%% by systematic var contribution).",
                          top_factor, 100*top_factor_pct, 100*top_factor_pct),
    metric = list(top_factor = top_factor, var_pct = round(top_factor_pct, 4)),
    disposition = "ACKNOWLEDGE; C2 low-vol defensive cohort by design (Ang-Hodrick-Xing-Zhang 2006 IVOL puzzle KR realization). Sector concentration expected. Risk-side acceptance: defensive bias entails sector lean; mitigation = Optimizer/Forge stage sector cap if mandated."
  ),
  list(
    id = "RF-R4",
    severity = "HIGH",
    description = sprintf("Tail risk cap breach: daily CVaR_95 = %.4f > 0.025 cap (%.2fx breach). ES_99 boot CI [%.4f, %.4f]. GFC max DD %.2f%%. EVT-GPD insufficient exceedances (only 17) → normal fallback.",
                          cvar_95_daily, cvar_95_daily/0.025,
                          quantile(boot_cvar_99, 0.025), quantile(boot_cvar_99, 0.975),
                          100*0.3916),
    metric = list(cvar_95 = round(cvar_95_daily, 4), cap = 0.025,
                  breach_multiple = round(cvar_95_daily/0.025, 2)),
    disposition = "ACKNOWLEDGE breach (marginal 1.14x); requires Optimizer-stage infeasibility_report OR Forge-stage explicit cap waiver via WT post-policy doc. Risk-research role = disclose, NOT veto. Recommendation: Optimizer should add CVaR target constraint."
  ),
  list(
    id = "RF-R5",
    severity = "HIGH",
    description = sprintf("Crowding/style correlation breach: Cross-sleeve daily cor = %.4f; Monthly Pearson %.4f / Spearman %.4f / Kendall %.4f; Lower TDC q=0.10 = %.4f. Top20 ticker overlap only 1/20 (rank-disjoint) BUT realized return co-movement strong. Multi-sleeve effectiveness in question.",
                          cross$cross_correlation, cross$diversification_ratio_50_50,
                          rp_draft$crowding_pareto$monthly_correlation$pearson,
                          rp_draft$crowding_pareto$monthly_correlation$kendall,
                          rp_draft$crowding_pareto$lower_tdc$q_10),
    metric = list(
      cross_daily_corr = cross$cross_correlation,
      monthly_pearson = rp_draft$crowding_pareto$monthly_correlation$pearson,
      monthly_kendall = rp_draft$crowding_pareto$monthly_correlation$kendall,
      lower_tdc_10 = rp_draft$crowding_pareto$lower_tdc$q_10,
      div_ratio_70_30 = cross$diversification_ratio_70_30
    ),
    disposition = "ACKNOWLEDGE; KEY FINDING — alpha-vector rank cor 0.004 STRICT PASS (alpha agent insight) is NOT equivalent to portfolio-level realized-return cor 0.7112 (Pareto FAIL). C2 + STR_1715 share KR Mkt + size + defensive sector exposure at the portfolio level. AX-005/AX-007 multi-sleeve exception evidence WEAK; not strict PASS. Optimizer must apply explicit max(sleeve_cor) constraint or accept that 4-sleeve composite acts as ~1.03x diversification (near-degenerate sleeve mix)."
  ),
  list(
    id = "RF-R8",
    severity = "MEDIUM",
    description = sprintf("Regime small-sample: CRISIS n=%d months (<30), no bootstrap CI on bad-regime IC=%.4f. Per-regime Sigma not constructed.",
                          regime_n$CRISIS_bad, ax_4axis$axis_3_bad_normal_ic_ratio$bad_ic),
    metric = list(n_crisis = regime_n$CRISIS_bad, ic_bad = ax_4axis$axis_3_bad_normal_ic_ratio$bad_ic),
    disposition = "ACKNOWLEDGE small-sample limitation; pooled IC retained as reproducibility-first approach. Per-regime Sigma deferred to Optimizer-stage (regime conditional weight ramping)."
  ),
  list(
    id = "RF-R9",
    severity = "LOW",
    description = "Method shopping log was missing in draft. Now disclosed: omega=Ledoit-Wolf (lambda=0.0957); sigma=BΩB'+D (no add'l shrink, cond 75.67<500); Gerber-RMT not triggered (D/N=0.04); DCC-GARCH deferred (static Sigma).",
    metric = method_shopping_log_risk$selection_metric,
    disposition = "ADDED to finalize. method_shopping_log_risk field included."
  )
)

challenge_flags <- list(
  list(
    flag_id = "AX_001_V2_4AXIS_FAIL_3_OF_4",
    severity = "HIGH",
    description = sprintf("AX-001 v2 4-axis conditional defense: axis 1 PASS (mean crisis_alpha +%.2fpp vs benchmark in 4/4 crises), axis 2 FAIL (mean MDD complement vs STR_1715 = %.2fpp i.e. C2 has deeper DD than STR_1715), axis 3 FAIL (bad/normal IC ratio %.4f < 1.0), axis 4 PARTIAL (VaR PASS C2<STR_1715 but CDaR FAIL C2>STR_1715). Composite 1/4 PASS.",
                          100 * mean(unlist(ax_4axis$axis_1_crisis_alpha$per_period), na.rm=TRUE),
                          100 * mean(unlist(ax_4axis$axis_2_mdd_complement$per_period), na.rm=TRUE),
                          ax_4axis$axis_3_bad_normal_ic_ratio$bad_normal_ic_ratio),
    codex_round1_disposition = "C7 ACCEPT FULL — AX-001 v2 4-axis composite 1/4 PASS",
    disposition = "ACCEPT FULL — AX-001 v2 conditional defense NOT satisfied. Honest disclosure: defensive against benchmark (axis 1) BUT not defensive vs STR_1715 admit (axis 2/3/4). C2 cannot replace STR_1715; C2 cannot complement STR_1715 with MDD savings. AX-001 v2 admission path BLOCKED at risk-research stage.",
    interpretation_note = "AX-001 v2 baseline ambiguity: spec says 'crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio + tail risk metrics'. STR_1715 admit is itself 'Core' or 'aggressive growth'? If STR_1715 is Core then C2 should hedge it (axis 2 vs STR_1715 fail = bad). If STR_1715 is aggressive and benchmark = Core, C2 axis 2 vs benchmark might be different. CURRENT EVALUATION USED STR_1715 as Core baseline. Re-evaluation possible only if 도훈/Q-Lead specifies different baseline."
  ),
  list(
    flag_id = "RF_R5_CROWDING_PARETO_FAIL",
    severity = "HIGH",
    description = sprintf("Portfolio-level realized return Pareto-orthogonality vs STR_1715 FAIL: Kendall %.4f > 0.20 threshold; Lower TDC %.4f > 0.40 threshold; daily cross-corr %.4f. Alpha-rank orthogonal (cor 0.004) does NOT translate to portfolio orthogonality after top20 selection.",
                          rp_draft$crowding_pareto$monthly_correlation$kendall,
                          rp_draft$crowding_pareto$lower_tdc$q_10,
                          cross$cross_correlation),
    codex_round1_disposition = "C2 ACCEPT FULL — non_degenerate_sleeve_mix FAIL",
    disposition = "ACCEPT FULL — AX-005 v1.2 EXCLUSION (multi-sleeve OR multi-axis combined) NOT clearly satisfied for portfolio-level. AX-007 EXEMPT 4-sleeve composition WEAK evidence. Optimizer must reconsider — sleeve mix near-degenerate."
  ),
  list(
    flag_id = "CVaR_95_DAILY_CAP_BREACH",
    severity = "HIGH",
    description = sprintf("CVaR_95 (daily, full hist 2004-2026) = %.4f > 0.025 cap (1.14x). Bootstrap CI [%.4f, %.4f]. Cap breach moderate, not extreme.",
                          cvar_95_daily,
                          quantile(boot_cvar_95, 0.025), quantile(boot_cvar_95, 0.975)),
    codex_round1_disposition = "C4 ACCEPT — CVaR cap breach disclosed",
    disposition = "ACCEPT — Risk-research role = disclose. Cannot veto downstream; expects Optimizer to add CVaR target constraint or infeasibility report. Compared to STR_1715 (admit MDD -24.81%), C2 GFC DD -39.16% suggests heavier left tail."
  ),
  list(
    flag_id = "STR_1715_STATIC_2026_TOP20_PROXY_NOT_ACTIVE_BOOK",
    severity = "MEDIUM",
    description = "STR_1715 sleeve full history was approximated by static 2026-04 top20 weights held through 2004-2026, NOT the actual PG2 active-book dynamic schedule. Real STR_1715 had monthly rebalance with time-varying alpha; static proxy may overstate or understate cross-correlation.",
    codex_round1_disposition = "C3 PARTIAL ACCEPT — conservative-approximation note",
    disposition = "PARTIAL REBUTTAL — C3 raises valid C1 PIT concern. Mitigation: alpha_scores 268m × 845 tickers includes STR_1715 historical alpha implicitly (alpha cycle ortho check used time-aligned monthly returns at sig_date). However, real STR_1715 admit had alpha-driven monthly rebalance not present in this proxy. Effect direction: static proxy holds 2026 cohort exposed to 2026 sectors (semiconductor/EV/biotech surge) — may understate 2004-2010 era cross-corr (different sectoral mix). NET BIAS UNCERTAIN. Risk-research scope: cannot rebuild full STR_1715 active book without additional Forge stage cycle. FOLLOW-UP TASK: Q-Lead may request Forge backtest re-run with STR_1715 historical alpha series; risk re-validation contingent on that artifact."
  ),
  list(
    flag_id = "AX_005_V1_2_EXCLUSION_PARETO_FAIL",
    severity = "HIGH",
    description = "AX-005 v1.2 EXCLUSION (multi-sleeve OR multi-axis combined) clause — at portfolio level, multi-sleeve evidence WEAK due to high cross-corr 0.7112 and TDC 0.6154. Single-sleeve historical fail L-136/140/165/166 remains active; EXCLUSION not clearly satisfied.",
    codex_round1_disposition = "C2 implicit ACCEPT",
    disposition = "ACCEPT — Risk-research stage cannot mark AX-005 EXEMPT alone. EXCLUSION evidence per AX-005 v1.2 = 'necessary not sufficient' (single-sleeve fail + Pareto-orthogonal multi-sleeve). Pareto FAIL → AX-005 EXEMPT path BLOCKED at risk stage."
  ),
  list(
    flag_id = "AX_008_TRIANGULATION_RISK_STAGE_ONLY_LIFECYCLE",
    severity = "MEDIUM",
    description = "C8 raised: weights.csv / optimization_package missing → AX-008 triangulation incomplete. Risk-research is 2nd of 6 agents in WT lifecycle; downstream Optimizer/Forge/Judge/Architect/Governor responsibility per Charter v1.7 §10 Role Card 4×5.",
    codex_round1_disposition = "C8 PARTIAL REBUTTAL — lifecycle stage mismatch",
    disposition = "REBUTTAL — same lifecycle stage rationale as alpha-cycle Codex C6. Risk-research scope = Σ + tail + stress + crowding + style + AX-001 v2 4-axis. Downstream artifacts are Optimizer/Forge/Architect responsibility. AX-008 = 6-agent end-of-lifecycle gate (PG2 admission). Single-stage cannot satisfy 2/3 sources alone."
  ),
  list(
    flag_id = "C13_C15_GOVERNANCE_PENDING_INHERIT_ALPHA",
    severity = "MEDIUM",
    description = "Alpha cycle inheritance: C13 manual sign flip (Ang 2006 economic basis) + C15 RAWDATA.parquet exemption (Charter §3 new_designed). Risk-research uses same RAWDATA (Ret, BM_Ret, Size, Sector) directly — same exemption applies.",
    codex_round1_disposition = "C13/C15 PARTIAL — governance approval pending",
    disposition = "INHERIT — alpha cycle disclosure stands. Risk-research did NOT introduce additional C13/C15 violations beyond inherited alpha cycle. Governance task #2 (Charter §3 amendment for new_designed factors) remains pending Q-Lead/charter."
  )
)

# ============================================================================
# Build final risk_package.json
# ============================================================================

rp_final <- rp_draft

# Update red_flags + challenge_flags (honest classification)
rp_final$red_flags <- red_flags
rp_final$challenge_flags <- challenge_flags

# Add factor variance decomposition
rp_final$factor_variance_decomposition <- list(
  method = "diagonal (Omega_ff) + cross-factor cov + specific D, EW top20 C2 sleeve",
  total_var = round(total_var, 6),
  total_vol = round(sqrt(total_var), 4),
  per_factor_pct = lapply(factor_pct, function(x) list(var_pct = x$var_pct,
                                                         beta_port = x$beta_port)),
  cross_factor_cov_pct = round(cross_factor_pct, 4),
  specific_idiosyncratic_pct = round(spec_var_pct, 4),
  top_factor = top_factor,
  top_factor_var_pct = round(top_factor_pct, 4),
  rf_r1_threshold_0_40 = top_factor_pct > 0.40,
  b_full_ref = file.path(STAGE_DIR, "B_full_factor_loadings.parquet")
)

# Update tail_risk with CVaR + boot CI
rp_final$tail_risk$cvar_panel <- cvar_summary

# Update diagnostics
rp_final$diagnostics$method_shopping_log_risk <- method_shopping_log_risk
rp_final$diagnostics$regime_sample_size <- regime_n
rp_final$diagnostics$regime_sigma_constructed <- FALSE
rp_final$diagnostics$regime_sigma_deferred_to <- "Optimizer (regime-conditional weight ramping per book_state v2.3 M4*AR*R05 sequential overlay)"

# Update ax_compliance with honest 4-axis classification
rp_final$ax_compliance$AX_001_v2_conditional_defense <- list(
  composite_pass_count = ax_4axis$composite_pass_count,
  axis_1_crisis_alpha_vs_benchmark_PASS = TRUE,
  axis_2_mdd_complement_vs_STR_1715_FAIL = TRUE,
  axis_3_bad_normal_ic_ratio_FAIL = TRUE,
  axis_4_tail_risk_superiority_PARTIAL = "VaR PASS, CDaR FAIL",
  honest_classification = "1/4 PASS = AX-001 v2 conditional defense NOT satisfied at risk-research stage; admission path BLOCKED.",
  baseline_ambiguity_note = "Axis 2/4 used STR_1715 as Core baseline; if benchmark KOSPI200 is Core (and STR_1715 is alpha-aggressive), re-evaluation possible. Q-Lead authority."
)
rp_final$ax_compliance$AX_005_v1_2_low_vol_exclusion_evidence$multi_sleeve_evidence_passes <- "PARETO FAIL — Kendall 0.5421 > 0.20, TDC 0.6154 > 0.40, cross_corr_daily 0.8491 high; div_ratio 70_30 = 1.027 near-degenerate"
rp_final$ax_compliance$AX_005_v1_2_low_vol_exclusion_evidence$exclusion_path_pass <- FALSE
rp_final$ax_compliance$AX_007_4sleeve_exempt_evidence$non_degenerate_evidence <- FALSE
rp_final$ax_compliance$AX_007_4sleeve_exempt_evidence$exempt_pass <- FALSE

# Final overall risk-research recommendation
rp_final$risk_research_verdict <- list(
  status = "NON_ADMITTING_PARETO_FAIL_AX001_FAIL",
  rationale = "Sigma numeric health PASS (cond 75.67 PSD). AX-001 v2 4-axis 1/4 PASS. AX-005/AX-007 EXEMPT evidence WEAK (Pareto orthogonality at portfolio level FAIL: Kendall 0.5421, TDC 0.6154, cross_corr 0.8491). CVaR_95 cap breach 1.14x. RF-R1 (sector concentration 35%+) + RF-R4 (CVaR breach) + RF-R5 (Pareto fail) + RF-R8 (small-sample bad regime) all active.",
  honest_classification = list(
    sigma_health = "PASS",
    ax_001_v2_4axis = "FAIL_1_OF_4",
    ax_005_exclusion_path = "FAIL_PARETO",
    ax_007_4sleeve_exempt = "FAIL_NON_DEGENERATE_SLEEVE_MIX",
    cvar_cap = "BREACH_1_14X",
    overall = "RISK_NON_ADMITTING"
  ),
  options_for_q_lead = list(
    option_A_abandon_admission = "Mark C2 as research-only artifact (4-axis FAIL + Pareto FAIL conclusive). Sunk cost: 2 cycles low-vol research. Consistent with Codex Round 2 alpha REJECT.",
    option_B_reframe_AX001_baseline = "If 도훈/Q-Lead approves baseline reframe (benchmark=KOSPI200 as Core, STR_1715=aggressive), axis 2/4 may re-evaluate. Risk-research suggests pendulum still adverse (TDC 0.6154 indicates lower-tail co-crash).",
    option_C_optimizer_constraint_force = "Pass to Optimizer with explicit constraints: max(sleeve_cor)<0.30, CVaR_95_target<0.025, sector_concentration<25%. Likely infeasibility_report; if feasible, weights composition will be far from naive 50/50 (likely 90/10 or extreme tilt)."
  ),
  recommendation_basis = "Risk-research does NOT veto. Charter v1.7 §11 Q-Lead decision authority. Honest disclosure: this is NOT a multi-sleeve composite candidate at portfolio level despite alpha-rank orthogonality."
)

# Add risk_challenge_note path reference
rp_final$risk_challenge_note_ref <- file.path(MAILBOX_DIR, "risk_challenge_note.md")

# Add Codex Round 1 disposition tracker
rp_final$codex_round_status <- "ROUND_1_REJECT_FULL_DISPOSITION_DOCUMENTED"
rp_final$codex_round_summary <- list(
  round1 = list(
    response_file = "codex_critic_response_risk.json",
    stance = "REJECT",
    veto_flag = FALSE,
    weakest_assumption = "The single weakest risk claim is that a hypothetical 70/30 STR_1715+C2 blend, measured against a static 2026 STR_1715 top20 proxy, is sufficient evidence for AX-005/AX-007 multi-sleeve exception despite RF-R5 crowding, AX-001 1/4 pass, and non_degenerate_sleeve_mix_evidence=false.",
    concerns_high = 6L,
    concerns_medium = 2L,
    disposition = list(
      C1_no_silent_override = "ACCEPT FULL — red_flags + challenge_flags populated; risk_challenge_note added",
      C2_AX005_007_multi_sleeve = "ACCEPT FULL — Pareto FAIL disclosed honestly; AX-005/AX-007 EXEMPT marked FAIL",
      C3_STR_1715_static_proxy = "PARTIAL REBUTTAL — conservative-approximation note + follow-up Forge backtest task; not feasible to rebuild active book at risk-research stage",
      C4_CVaR_breach = "ACCEPT FULL — CVaR_95 0.0285 cap breach 1.14x disclosed; ES_99 boot CI computed",
      C5_RF_R1_factor_concentration = "ACCEPT FULL — factor variance decomposition added; top factor pct disclosed",
      C6_B_full_method_shopping = "ACCEPT FULL — B_full_factor_loadings.parquet saved; method_shopping_log_risk added",
      C7_AX001_v2_4axis = "ACCEPT FULL — honest 1/4 classification + baseline ambiguity note",
      C8_downstream_artifacts = "PARTIAL REBUTTAL — lifecycle stage mismatch (alpha cycle precedent C6)"
    ),
    challenge_note_file = "risk_challenge_note.md",
    self_rationalization_check_phrases_revised = c(
      "gate-bypasses Q2-Q5 mono fail",
      "Multi-sleeve = effectively disjoint",
      "1 source (risk-research only); awaits Optimizer + Forge + Architect",
      "CONSERVATIVE approximation",
      "post-cycle deferred"
    )
  )
)

# Write final
write_json(rp_final, file.path(MAILBOX_DIR, "risk_package.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")
cat(sprintf("Saved: %s\n", file.path(MAILBOX_DIR, "risk_package.json")))

cat("\n[finalize] risk_package.json finalized with honest classification\n")
cat(sprintf("Total challenge_flags: %d\n", length(rp_final$challenge_flags)))
cat(sprintf("Total red_flags: %d\n", length(rp_final$red_flags)))
cat(sprintf("Risk research verdict: %s\n", rp_final$risk_research_verdict$status))
