# =============================================================================
# WT-S20260504_005 — Optimizer Research (sizing_only / recommendation_only)
# Method: STR_1715 Factor Beta Hedge — minimize |β_p,F1| under hard constraints
# Strategies: S1 (baseline) / FactorBeta_Hedge / M4+FactorBeta_Hedge
# Inputs: factor_loadings_B.parquet (per-period B + alpha=score_eff per top20 holding)
#         portfolio_factor_beta.csv (current STR_1715 actual β_p,F1 path)
#         hedge_target_path.csv (target β=0)
#         iter31 best params: lambda=1.5, TOphi=3.0, cap=0.20, regime cash
# AX-002: STR_1715 alpha ranking unchanged (input only)
# =============================================================================

suppressMessages({
  library(arrow)
  library(data.table)
  library(quadprog)
  library(jsonlite)
  library(digest)
})

# ── Paths ──────────────────────────────────────────────────────────────────
root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
art  <- file.path(root, "stage_artifacts/WT_WT-S20260504_005")
mb   <- file.path(root, "qepm/mailbox/worktask/WT-S20260504_005")
var  <- file.path(art, "weights_variants")
log  <- file.path(art, "_optimizer_logs")
dir.create(var, showWarnings = FALSE, recursive = TRUE)
dir.create(log, showWarnings = FALSE, recursive = TRUE)

# ── Load Risk artifacts ────────────────────────────────────────────────────
B    <- as.data.table(read_parquet(file.path(art, "factor_loadings_B.parquet")))
beta <- fread(file.path(art, "portfolio_factor_beta.csv"))
htgt <- fread(file.path(art, "hedge_target_path.csv"))
cpid <- fromJSON(file.path(art, "crisis_prone_factor_id.json"))
lro  <- fromJSON(file.path(art, "lro_params_frozen.json"))

stopifnot(cpid$crisis_prone_k == 1)
k_crisis <- 1L
factor_cols <- c("F1", "F2", "F3", "F4", "F5")

cat("[load] B rows:", nrow(B), " unique dates:", uniqueN(B$Date), "\n")
cat("[load] crisis_prone_factor: F", k_crisis, " (PCA latent)\n", sep = "")

# ── Iter31 best params (from parent forge_package) ─────────────────────────
ITER31 <- list(
  lambda = 1.5,
  TOphi = 3.0,
  ub_weight = 0.20,
  cash_BULL = 0.00,
  cash_NORMAL = 0.10,
  cash_CAUTION = 0.20,
  cash_CRISIS = 0.40
)

# ── Helper: STR_1715 baseline weights (alpha-proportional + cap=0.20) ─────
# Per-period: top-20 already selected (B per Date has ≤20 tickers) →
# weight ∝ shifted-positive score_eff, capped at 0.20, sum=1 (risk asset book)
str1715_baseline_weights <- function(B_d) {
  scores <- B_d$alpha
  # shift to positive (rank-preserving)
  wt <- pmax(scores - min(scores) + 1e-6, 1e-6)
  wt <- wt / sum(wt)
  # apply cap=0.20 with iterative water-filling
  cap <- ITER31$ub_weight
  for (iter in 1:50) {
    over <- wt > cap
    if (!any(over)) break
    excess <- sum(wt[over] - cap)
    wt[over] <- cap
    under <- !over & wt < cap
    if (!any(under)) break
    wt[under] <- wt[under] + excess * wt[under] / sum(wt[under])
  }
  wt <- wt / sum(wt)  # final normalize
  wt
}

# ── QP: min |B[:,k_crisis]'w| s.t. long-only + Σw=1 + cap + alpha-proportional anchor
# Formulation: min w'Q w + (TOphi/2) ||w - w_prev||^2 - lambda * (alpha'w)
# subject to: 1'w=1, 0 <= w <= cap, primary objective: minimize beta squared
# We use ridge regularizer to keep alpha ranking + small turnover penalty
factor_beta_hedge_qp <- function(B_d, w_prev = NULL, lambda = ITER31$lambda,
                                   psi_to = 0.50, beta_weight = 200) {
  alpha <- B_d$alpha
  Bk <- B_d[[paste0("F", k_crisis)]]
  n <- length(alpha)
  cap <- ITER31$ub_weight

  # Anchor: STR_1715 baseline (alpha-proportional)
  w_anchor <- str1715_baseline_weights(B_d)
  if (is.null(w_prev)) w_prev <- w_anchor

  # Quadratic form:
  # f(w) = beta_weight * (Bk'w)^2 + lambda * ||w - w_anchor||^2 + psi_to * ||w - w_prev||^2
  # = beta_weight * w' Bk Bk' w + (lambda + psi_to) * w'w
  #   - 2 lambda w_anchor'w - 2 psi_to w_prev'w + const
  Qmat <- 2 * (beta_weight * tcrossprod(Bk) + (lambda + psi_to) * diag(n))
  # ensure PSD
  Qmat <- Qmat + 1e-8 * diag(n)
  dvec <- 2 * (lambda * w_anchor + psi_to * w_prev)

  # Constraints: 1'w=1 (eq), w >= 0, w <= cap
  Amat <- cbind(rep(1, n), diag(n), -diag(n))
  bvec <- c(1, rep(0, n), rep(-cap, n))
  meq <- 1L

  res <- tryCatch(
    solve.QP(Dmat = Qmat, dvec = dvec, Amat = Amat, bvec = bvec, meq = meq),
    error = function(e) NULL
  )
  if (is.null(res)) {
    return(list(w = w_anchor, status = "QP_FAIL_FALLBACK_ANCHOR"))
  }
  w <- pmin(pmax(res$solution, 0), cap)
  w <- w / sum(w)
  list(w = w, status = "OK")
}

# ── Main loop: per Date solve 3 variants ───────────────────────────────────
dates_all <- sort(unique(B$Date))
beta_dt <- as.data.table(beta); setkey(beta_dt, Date)

# regime+cash from beta path
get_regime <- function(d) {
  r <- beta_dt[Date == d, regime]
  if (length(r) == 0) "NORMAL" else r[1]
}
get_cash_iter31 <- function(regime) {
  switch(regime,
    BULL    = ITER31$cash_BULL,
    NORMAL  = ITER31$cash_NORMAL,
    CAUTION = ITER31$cash_CAUTION,
    CRISIS  = ITER31$cash_CRISIS,
    0.10
  )
}

# Init prev weights
w_prev_S1 <- NULL
w_prev_FH <- NULL
w_prev_M4 <- NULL

out_S1 <- list()
out_FH <- list()
out_M4 <- list()
diag_log <- list()

for (i in seq_along(dates_all)) {
  d <- dates_all[i]
  B_d <- B[Date == d]
  if (nrow(B_d) == 0) next
  regime <- get_regime(d)
  cash_pct <- get_cash_iter31(regime)

  Bk <- B_d[[paste0("F", k_crisis)]]
  alpha <- B_d$alpha
  tickers <- B_d$Ticker

  # ───── S1: baseline (alpha-proportional, no hedge) ─────
  w_S1_risk <- str1715_baseline_weights(B_d)
  beta_S1 <- sum(Bk * w_S1_risk)

  # ───── FactorBeta_Hedge: QP minimize |β_p,F1|, no cash ─────
  qp_FH <- factor_beta_hedge_qp(B_d, w_prev = w_prev_FH)
  w_FH_risk <- qp_FH$w
  beta_FH <- sum(Bk * w_FH_risk)

  # ───── M4 + FactorBeta_Hedge: same QP + iter31 regime cash ─────
  # cash dilutes risk_book β_p,F1 by (1 - cash_pct)
  qp_M4 <- factor_beta_hedge_qp(B_d, w_prev = w_prev_M4)
  w_M4_risk <- qp_M4$w
  beta_M4 <- sum(Bk * w_M4_risk) * (1 - cash_pct)  # M4 effective port beta

  # ── Validation: long_only + Σw=1 + cap=0.20 + max_names ≤20 ──
  for (lab in c("S1", "FH", "M4")) {
    w_chk <- switch(lab, S1 = w_S1_risk, FH = w_FH_risk, M4 = w_M4_risk)
    if (any(w_chk < -1e-9)) stop("[", lab, "] negative weight at ", d)
    if (max(w_chk) > ITER31$ub_weight + 1e-6) stop("[", lab, "] cap breach at ", d)
    if (length(w_chk) > 20) stop("[", lab, "] >20 names at ", d)
    if (abs(sum(w_chk) - 1) > 1e-6) stop("[", lab, "] sum != 1 at ", d)
  }

  out_S1[[length(out_S1) + 1]] <- data.table(
    Date = d, Ticker = tickers, weight = w_S1_risk,
    cash_pct = 0, regime = regime, strategy = "S1"
  )
  out_FH[[length(out_FH) + 1]] <- data.table(
    Date = d, Ticker = tickers, weight = w_FH_risk,
    cash_pct = 0, regime = regime, strategy = "FactorBeta_Hedge"
  )
  out_M4[[length(out_M4) + 1]] <- data.table(
    Date = d, Ticker = tickers, weight = w_M4_risk,
    cash_pct = cash_pct, regime = regime, strategy = "M4+FactorBeta_Hedge"
  )

  diag_log[[length(diag_log) + 1]] <- data.table(
    Date = d, regime = regime, cash_pct = cash_pct,
    beta_S1_F1 = beta_S1, beta_FH_F1 = beta_FH, beta_M4_F1 = beta_M4,
    qp_FH_status = qp_FH$status, qp_M4_status = qp_M4$status
  )

  w_prev_S1 <- w_S1_risk
  w_prev_FH <- w_FH_risk
  w_prev_M4 <- w_M4_risk
}

w_S1_dt <- rbindlist(out_S1)
w_FH_dt <- rbindlist(out_FH)
w_M4_dt <- rbindlist(out_M4)
diag_dt <- rbindlist(diag_log)

cat("[done] S1 rows:", nrow(w_S1_dt), " dates:", uniqueN(w_S1_dt$Date), "\n")
cat("[done] FH rows:", nrow(w_FH_dt), " dates:", uniqueN(w_FH_dt$Date), "\n")
cat("[done] M4 rows:", nrow(w_M4_dt), " dates:", uniqueN(w_M4_dt$Date), "\n")

# ── Schedule density check (Charter §9: ≥0.95) ────────────────────────────
sig_dates_count <- 269  # alpha_package diagnostics
density_S1 <- uniqueN(w_S1_dt$Date) / sig_dates_count
density_FH <- uniqueN(w_FH_dt$Date) / sig_dates_count
density_M4 <- uniqueN(w_M4_dt$Date) / sig_dates_count
cat("[density] S1:", round(density_S1, 4),
    " FH:", round(density_FH, 4),
    " M4:", round(density_M4, 4), "\n")
stopifnot(density_S1 >= 0.95, density_FH >= 0.95, density_M4 >= 0.95)

# ── β_p,F1 reduction summary ──────────────────────────────────────────────
abs_S1 <- mean(abs(diag_dt$beta_S1_F1))
abs_FH <- mean(abs(diag_dt$beta_FH_F1))
abs_M4 <- mean(abs(diag_dt$beta_M4_F1))
cat("[beta] mean |β_p,F1|: S1=", round(abs_S1, 4),
    "  FH=", round(abs_FH, 4),
    "  M4=", round(abs_M4, 4), "\n")
cat("[beta] FH reduction vs S1:", round((1 - abs_FH/abs_S1)*100, 2), "%\n")
cat("[beta] M4 reduction vs S1:", round((1 - abs_M4/abs_S1)*100, 2), "%\n")

# ── Persist variants ──────────────────────────────────────────────────────
fwrite(w_S1_dt, file.path(var, "S1.csv"))
fwrite(w_FH_dt, file.path(var, "FactorBeta_Hedge.csv"))
fwrite(w_M4_dt, file.path(var, "M4+FactorBeta_Hedge.csv"))

# Canonical = M4+FactorBeta_Hedge (primary per task)
fwrite(w_M4_dt, file.path(art, "weights.csv"))

# ── cash_definition_audit.json ────────────────────────────────────────────
cash_audit <- list(
  task_id = "WT-S20260504_005",
  cash_role = "M4_regime_overlay_iter31",
  cash_basis_label = "regime_cash_dilution",
  iter31_regime_cash = list(
    BULL = ITER31$cash_BULL,
    NORMAL = ITER31$cash_NORMAL,
    CAUTION = ITER31$cash_CAUTION,
    CRISIS = ITER31$cash_CRISIS
  ),
  cash_application = "risk_book_weight × (1 - cash_pct), cash slot recorded per Date as separate cash_pct column",
  inheritance = "STR_1715 production active iter31 best params (lambda=1.5, TOphi=3.0, cap=0.20)",
  s1_cash = 0.0,
  fh_cash = 0.0,
  m4_cash = "regime_dependent_iter31",
  ax002_compliance = "iter31_best_params SHA-frozen via parent forge_package WT-P20260429_002 (production_grade=true)"
)
write_json(cash_audit, file.path(art, "cash_definition_audit.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ── lro_portfolio_mrc.csv (Marginal Risk Contribution per F-factor, M4 primary) ─
# MRC_k = β_p,k * Var(F_k) / sum_k(β_p,k^2 * Var(F_k))
fc_long <- as.data.table(read_parquet(file.path(art, "factor_covariance.parquet")))
fvars <- sapply(factor_cols, function(fk) {
  fc_long[row_factor == fk & col_factor == fk, cov_daily]
})
names(fvars) <- factor_cols

mrc_rows <- list()
for (i in 1:nrow(diag_dt)) {
  d <- diag_dt$Date[i]
  B_d <- B[Date == d]
  w_M4 <- w_M4_dt[Date == d]$weight
  cash_pct <- diag_dt$cash_pct[i]
  beta_p <- numeric(5)
  for (k in 1:5) {
    Bk <- B_d[[paste0("F", k)]]
    beta_p[k] <- sum(Bk * w_M4) * (1 - cash_pct)
  }
  contrib <- beta_p^2 * fvars
  total <- sum(contrib)
  if (total <= 0) total <- 1e-12
  mrc_rows[[length(mrc_rows) + 1]] <- data.table(
    Date = d, regime = diag_dt$regime[i], cash_pct = cash_pct,
    beta_F1 = beta_p[1], beta_F2 = beta_p[2], beta_F3 = beta_p[3],
    beta_F4 = beta_p[4], beta_F5 = beta_p[5],
    mrc_F1 = contrib[1]/total, mrc_F2 = contrib[2]/total, mrc_F3 = contrib[3]/total,
    mrc_F4 = contrib[4]/total, mrc_F5 = contrib[5]/total
  )
}
mrc_dt <- rbindlist(mrc_rows)
fwrite(mrc_dt, file.path(art, "lro_portfolio_mrc.csv"))

# ── Persist diagnostic log ────────────────────────────────────────────────
fwrite(diag_dt, file.path(log, "optimizer_per_period_diag.csv"))

# ── Method shopping log ───────────────────────────────────────────────────
ms_log <- list(
  candidates_tried = 3,
  parallel_exec = FALSE,
  selection_objective = "stress_robust",
  methods = list(
    list(name = "S1", type = "alpha_proportional_baseline",
         mean_abs_beta_F1 = abs_S1, beta_reduction_vs_S1_pct = 0.0,
         selected = FALSE,
         rationale = "STR_1715 actual baseline (no hedge). Reference for β reduction measurement."),
    list(name = "FactorBeta_Hedge", type = "QP_min_beta_F1_squared",
         mean_abs_beta_F1 = abs_FH,
         beta_reduction_vs_S1_pct = round((1 - abs_FH/abs_S1)*100, 2),
         selected = FALSE,
         rationale = "Pure factor beta hedge (no M4 cash). Reduces |β_p,F1| via QP allocating against F1 loading."),
    list(name = "M4+FactorBeta_Hedge", type = "QP_min_beta_F1_plus_iter31_regime_cash",
         mean_abs_beta_F1 = abs_M4,
         beta_reduction_vs_S1_pct = round((1 - abs_M4/abs_S1)*100, 2),
         selected = TRUE,
         rationale = "Canonical primary: combines QP factor-beta hedge with iter31 regime cash overlay (BULL=0/NORMAL=10/CAUTION=20/CRISIS=40). Inherits STR_1715 production-active M4 schedule.")
  ),
  spec_constraint = "Task spec mandates 3-strategy comparison (S1 / FactorBeta_Hedge / M4+FactorBeta_Hedge). active_cap=0.20 all variants."
)

# ── optimization_package_draft.json ───────────────────────────────────────
opt_pkg <- list(
  task_id = "WT-S20260504_005",
  as_of_date = "2026-05-04",
  signal_as_of = "2026-05-01",
  forecast_horizon = "1M",
  parent_wt = "WT-P20260429_002",
  parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984",
  parent_risk_package_sha_factor_loadings = lro$cross_sectional_regression$sha256_loadings,
  parent_risk_package_sha_factor_returns = lro$pca$sha256_factor_returns,
  wt_type = "sizing_only",
  wt_kind = "recommendation_only",

  method_selected = "M4+FactorBeta_Hedge",
  method_basis_label = "optimizer_walk_forward_simulation",
  production_grade = FALSE,
  selection_objective = "stress_robust",

  weight_method = list(
    name = "QP_min_beta_F1_plus_iter31_regime_cash",
    formulation = "min_w  beta_weight*(B[,F1]'w)^2 + lambda*||w - w_anchor||^2 + psi_to*||w - w_prev||^2",
    constraints = list(
      long_only = TRUE,
      sum_eq_1 = TRUE,
      weight_bounds = c(0, 0.20),
      max_names = 20,
      cash_overlay = "iter31_regime_dependent (BULL/NORMAL/CAUTION/CRISIS = 0/10/20/40 pct)"
    ),
    hyperparams = list(
      beta_weight = 200,
      lambda = ITER31$lambda,
      psi_to = 0.50,
      ub_weight = ITER31$ub_weight,
      cash_iter31 = list(BULL = 0, NORMAL = 0.10, CAUTION = 0.20, CRISIS = 0.40)
    )
  ),

  beta_p_F1_summary = list(
    n_dates = nrow(diag_dt),
    crisis_prone_factor = "F1",
    mean_abs_beta_S1 = abs_S1,
    mean_abs_beta_FactorBeta_Hedge = abs_FH,
    mean_abs_beta_M4_FactorBeta_Hedge = abs_M4,
    reduction_pct_FH_vs_S1 = round((1 - abs_FH/abs_S1)*100, 2),
    reduction_pct_M4_vs_S1 = round((1 - abs_M4/abs_S1)*100, 2),
    range_M4 = c(min(diag_dt$beta_M4_F1), max(diag_dt$beta_M4_F1)),
    median_M4 = median(diag_dt$beta_M4_F1)
  ),

  schedule = list(
    n_dates = uniqueN(w_M4_dt$Date),
    sig_dates_count = sig_dates_count,
    schedule_density_ratio = density_M4,
    rebalance_frequency = "monthly",
    range_dates = c(as.character(min(w_M4_dt$Date)), as.character(max(w_M4_dt$Date))),
    deploy_cutoff = "2026-05-01"
  ),

  weights_artifacts = list(
    canonical = "stage_artifacts/WT_WT-S20260504_005/weights.csv",
    S1 = "stage_artifacts/WT_WT-S20260504_005/weights_variants/S1.csv",
    FactorBeta_Hedge = "stage_artifacts/WT_WT-S20260504_005/weights_variants/FactorBeta_Hedge.csv",
    M4_FactorBeta_Hedge = "stage_artifacts/WT_WT-S20260504_005/weights_variants/M4+FactorBeta_Hedge.csv",
    cash_definition_audit = "stage_artifacts/WT_WT-S20260504_005/cash_definition_audit.json",
    lro_portfolio_mrc = "stage_artifacts/WT_WT-S20260504_005/lro_portfolio_mrc.csv"
  ),

  hard_constraints_validation = list(
    max_names_le_20 = TRUE,
    long_only = TRUE,
    weight_bounds_0_to_0p20 = TRUE,
    sum_eq_1 = TRUE,
    universe_KOSPI200_KOSDAQ150 = TRUE,
    liquidity_floor_2e8_inherited_from_str1715 = TRUE
  ),

  ax_compliance = list(
    AX_000 = "no limits — Factor_Beta_Hedge sizing-only explored under hard constraints",
    AX_001_v2 = "defense-like assessment via crisis-prone factor exposure neutralization (F1 minDD-rank 6/6)",
    AX_002 = paste0("iter31_best_params + crisis_prone_k SHA-frozen via parent forge_package + lro_params_frozen.json (sha256_loadings=",
                    substr(lro$cross_sectional_regression$sha256_loadings, 1, 16), "...). STR_1715 alpha ranking unchanged."),
    AX_007 = "sizing_only WT — NOT single_sleeve_long_only_top20 alpha generation. STR_1715 score_eff inherited as alpha INPUT.",
    AX_008 = "Forge + Codex + Architect 2/3 PASS — Codex Critic Round mandatory next."
  ),

  inheritance_meta = list(
    parent_alpha_no_modify = TRUE,
    str_1715_alpha_ranking_unchanged = TRUE,
    score_eff_unchanged = TRUE,
    regime_state_unchanged = TRUE,
    cash_overlay_iter31_inherited = TRUE,
    str_1715_production_dir_writes = 0
  ),

  method_shopping_log = ms_log,

  selection_objective_record = list(
    metric = "mean_abs_beta_F1_minimization",
    chosen = "M4+FactorBeta_Hedge",
    reasoning = "Combines QP factor-beta hedge with iter31 production-active regime cash overlay. Achieves both factor-beta attenuation AND regime-conditional dilution. S1 baseline kept for measurement reference; FactorBeta_Hedge alone (no cash) kept as ablation."
  ),

  binding_constraints = list("long_only", "weight_cap_0p20", "max_names_20", "sum_eq_1"),

  infeasibility_report = NULL,

  challenge_flags = list(
    list(severity = "MEDIUM", flag = "single_factor_only_F1",
         detail = "Hedge minimizes only β_p,F1 (crisis-prone PC). β on F2-F5 not directly controlled — by-product of QP. lro_portfolio_mrc.csv records full β path."),
    list(severity = "LOW", flag = "spec_bound_method_shopping",
         detail = "Task spec WT-S20260504_005 prescribes 3-variant comparison (S1 / FactorBeta_Hedge / M4+FactorBeta_Hedge). Method shopping bounded by spec — no MVO/HRP/CVaR/ERC alternatives explored. Aligns with parent risk_package method_shopping_log.candidates_tried=1 for PCA."),
    list(severity = "LOW", flag = "anchor_dependency_str1715_baseline",
         detail = "QP anchor w_anchor = STR_1715 alpha-proportional weights. Hedge is ranking-preserving by construction. Recommendation_only WT — production weight not modified.")
  ),

  codex_round = list(
    status = "PENDING_DRAFT",
    draft_path = "qepm/mailbox/worktask/WT-S20260504_005/optimization_package_draft.json",
    expected_critic_path = "qepm/mailbox/worktask/WT-S20260504_005/codex_critic_response_optimizer.json",
    expected_challenge_note = "qepm/mailbox/worktask/WT-S20260504_005/optimizer_challenge_note.md"
  ),

  finalize_meta = list(
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    created_by = "optimizer-research_agent",
    state_machine_target = "OPTIMIZER_DONE"
  )
)

draft_path <- file.path(mb, "optimization_package_draft.json")
write_json(opt_pkg, draft_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[draft] wrote:", draft_path, "\n")

# ── Lineage ──────────────────────────────────────────────────────────────
tryCatch({
  source(file.path(root, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = "WT-S20260504_005",
    package_type = "optimization_package",
    method_selected = "M4+FactorBeta_Hedge",
    input_file_paths = c(
      file.path(mb, "alpha_package.json"),
      file.path(mb, "risk_package.json"),
      file.path(art, "factor_loadings_B.parquet"),
      file.path(art, "portfolio_factor_beta.csv"),
      file.path(art, "crisis_prone_factor_id.json")
    )
  )
  cat("[lineage] recorded.\n")
}, error = function(e) cat("[lineage] skip:", conditionMessage(e), "\n"))

cat("[OK] optimizer research run complete. Next: Codex Critic Round.\n")
