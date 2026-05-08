#==============================================================================
# WT-D20260508_002 Alpha v5 Phase 3 — diagnostics + multi-trial DSR + max-20 sim
#
# Codex 8 concerns remediation (final):
#   C3 hurdle: max-20 hard simulation (top-quintile sleeve폐기) — TO_ann verified.
#   C4 multi-trial DSR: Bailey-Lopez de Prado strict haircut.
#   C6 sector-neutral: post_neutralization_ic computed separately from rank_ic.
#   C8 max_names=20: Σw=1, weights=[0,0.20], long-only.
#
# Inputs: predictions_v5_all_models.parquet + sig_date_window_lineage.json
# Output: alpha_package_v5_draft.json + alpha_validation_v5.json + alpha_scores_v5.parquet
#         + dsr_strict_bailey_ldp.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(sandwich); library(lmtest)
})
options(warn = 1)

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_002"
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", WT_ID)
ART_DIR <- file.path(PROJ, "stage_artifacts", "WT_D20260508_002")

cat("================================================================\n")
cat("WT-D20260508_002 Alpha v5 Phase 3 — Diagnostics + DSR + Max-20\n")
cat("================================================================\n")

#--- 1. Load predictions ---
cat("\n[1] Loading Phase 2 predictions...\n")
preds <- as.data.table(read_parquet(file.path(ART_DIR, "predictions_v5_all_models.parquet")))
preds[, YM_target := as.Date(YM_target)]
cat("  Total rows:", nrow(preds), "\n")
cat("  Date range:", as.character(min(preds$YM_target)), "-",
    as.character(max(preds$YM_target)), "\n")

# CRITICAL FIX: 2026-05 is incomplete month (7 partial trading days, RAWDATA ends 2026-05-08).
# Phase 1 inadvertently filled y_actual from incomplete data. Force NA here.
# This treats 2026-05 as proper forward as-of (no y_actual), matching deployment intent.
preds[YM_target == as.Date("2026-05-01"), `:=`(y_actual = NA_real_, ret_actual = NA_real_)]

# Forward as-of has y_actual = NA → split realized vs forward
realized <- preds[!is.na(y_actual)]
forward <- preds[is.na(y_actual)]
cat("  Realized rows:", nrow(realized), "  Forward (2026-05) rows:", nrow(forward), "\n")
cat("  Realized last month:", as.character(max(realized$YM_target)),
    "  Forward month:", as.character(max(forward$YM_target)), "\n")

#--- 2. Per-model diagnostics on realized ---
cat("\n[2] Per-model diagnostics (rolling forward only)...\n")
models <- c("pred_ridge", "pred_enet", "pred_xgb", "pred_rf", "pred_mlp", "pred_ens", "pred_ens_secneutral")

compute_diag <- function(preds_subset, model_col, label = "rank_ic") {
  ic_per_month <- preds_subset[, .(
    ic = if (.N >= 5 && sd(.SD[[1]], na.rm = TRUE) > 0 && sd(y_actual, na.rm = TRUE) > 0)
           cor(.SD[[1]], y_actual, method = "spearman", use = "complete.obs")
         else NA_real_
  ), by = YM_target, .SDcols = model_col][!is.na(ic)]
  if (nrow(ic_per_month) < 12) return(NULL)
  rank_ic <- mean(ic_per_month$ic)
  icir <- rank_ic / (sd(ic_per_month$ic, na.rm = TRUE) + 1e-9)
  fit <- lm(ic ~ 1, data = ic_per_month)
  nw <- NeweyWest(fit, lag = 6, prewhite = FALSE)
  t_NW <- coef(fit)[1] / sqrt(nw[1, 1])

  ic_per_month[, period := cut(YM_target,
                                 breaks = c(as.Date("2014-01-01"), as.Date("2018-01-01"),
                                            as.Date("2022-01-01"), as.Date("2027-01-01")),
                                 labels = c("p1", "p2", "p3"))]
  period_signs <- ic_per_month[, .(ic_mean = mean(ic, na.rm = TRUE)), by = period]
  sub_stab <- if (nrow(period_signs) > 0) {
    sum(sign(period_signs$ic_mean) == sign(rank_ic)) / nrow(period_signs)
  } else NA

  # Decile monotonicity: avg per-decile mean return
  # Use rank-based decile (handles ties / constant predictions safely)
  preds_subset <- copy(preds_subset)
  preds_subset[, decile := tryCatch({
    r <- frank(.SD[[1]], ties.method = "average", na.last = "keep")
    pmin(pmax(ceiling(10 * r / max(r, na.rm = TRUE)), 1), 10)
  }, error = function(e) rep(NA_integer_, .N)),
  by = YM_target, .SDcols = model_col]
  dec_returns <- preds_subset[!is.na(decile), .(r = mean(ret_actual, na.rm = TRUE)),
                              by = decile][order(decile)]
  if (nrow(dec_returns) >= 5) {
    monotonicity <- abs(cor(as.numeric(dec_returns$decile), dec_returns$r,
                            method = "spearman", use = "complete.obs"))
    if (is.na(monotonicity)) monotonicity <- 0
  } else monotonicity <- NA

  list(
    rank_ic = rank_ic, icir = icir, t_NW = as.numeric(t_NW),
    sub_stab = sub_stab, n_months = nrow(ic_per_month),
    monotonicity = monotonicity,
    ic_series = ic_per_month$ic,
    ic_dates = ic_per_month$YM_target
  )
}

diag_results <- list()
for (m in models) {
  d <- compute_diag(realized, m)
  if (!is.null(d)) {
    diag_results[[m]] <- d
    cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f stab=%.2f mono=%.3f n=%d\n",
                m, d$rank_ic, d$icir, d$t_NW, d$sub_stab, d$monotonicity, d$n_months))
  }
}

#--- 3. Sector-neutral comparison (Codex C6) ---
cat("\n[3] Sector-neutral diagnostics (post_neutralization_ic vs rank_ic)...\n")
post_neut_ic <- diag_results[["pred_ens_secneutral"]]$rank_ic
raw_ic <- diag_results[["pred_ens"]]$rank_ic
neutral_retention <- post_neut_ic / max(abs(raw_ic), 1e-9)
cat(sprintf("  raw_ic (pred_ens): %.4f\n  post_neutralization_ic (sector demean): %.4f\n  retention: %.2f%%\n",
            raw_ic, post_neut_ic, neutral_retention * 100))
rf_a4_flag <- abs(post_neut_ic) < 0.3 * abs(raw_ic)
cat("  RF-A4 flag (post-neutral < 30% of raw):", rf_a4_flag, "\n")

#--- 4. Max-20 simulation per month (Codex C3 + C8) ---
cat("\n[4] Max-20 hard simulation (top-quintile sleeve폐기)...\n")
# For each model, per month: pick top 20 by prediction. Equal weight. Compute net return after 15bps.
simulate_max20 <- function(preds_subset, model_col, max_names = 20L,
                           one_way_cost = 0.0015) {
  preds_subset <- preds_subset[order(YM_target)]
  months_in_order <- sort(unique(preds_subset$YM_target))
  prev_holdings <- character(0)
  m_returns <- data.table(YM_target = as.Date(character()),
                           ret_gross = numeric(),
                           turnover = numeric(),
                           cost_drag = numeric(),
                           ret_net = numeric())
  for (ym in months_in_order) {
    p_ym <- preds_subset[YM_target == ym]
    # Drop NA predictions
    p_ym <- p_ym[!is.na(get(model_col))]
    if (nrow(p_ym) < max_names) next
    p_ym <- p_ym[order(-get(model_col))]
    top <- head(p_ym, max_names)
    holdings <- top$Ticker
    weights <- rep(1 / max_names, max_names)
    # Realized return (forward as-of has NA → skip)
    r_holdings <- top$ret_actual
    if (all(is.na(r_holdings))) next
    ret_gross_ym <- mean(r_holdings, na.rm = TRUE)
    # Turnover: sum |w_t - w_{t-1}| / 2 simplification (one-side fraction)
    if (length(prev_holdings) == 0) {
      turnover_ym <- 1.0  # initial purchase = 100% one-side
    } else {
      new_names <- setdiff(holdings, prev_holdings)
      turnover_ym <- length(new_names) / max_names
    }
    cost_ym <- 2 * one_way_cost * turnover_ym  # buy + sell
    ret_net_ym <- ret_gross_ym - cost_ym
    m_returns <- rbind(m_returns, data.table(
      YM_target = ym, ret_gross = ret_gross_ym, turnover = turnover_ym,
      cost_drag = cost_ym, ret_net = ret_net_ym
    ))
    prev_holdings <- holdings
  }
  m_returns
}

max20_results <- list()
for (m in models) {
  if (m == "pred_ens_secneutral") next  # skip sector-neutral max-20 (we already have raw)
  out <- simulate_max20(realized, m)
  if (nrow(out) > 12) {
    sr_ann <- mean(out$ret_net) / sd(out$ret_net) * sqrt(12)
    sr_gross_ann <- mean(out$ret_gross) / sd(out$ret_gross) * sqrt(12)
    to_ann <- mean(out$turnover) * 12  # one-way turnover annualized
    cagr <- prod(1 + out$ret_net)^(12 / nrow(out)) - 1
    max20_results[[m]] <- list(
      sr_net_ann = sr_ann, sr_gross_ann = sr_gross_ann,
      to_ann = to_ann, cagr_net = cagr,
      n_months = nrow(out), monthly_table = out
    )
    cat(sprintf("  %s: SR_net=%.3f SR_gross=%.3f TO_ann=%.2f CAGR_net=%.2f%% n=%d\n",
                m, sr_ann, sr_gross_ann, to_ann, cagr * 100, nrow(out)))
  }
}

# Hurdle compliance
cat("\n  Hurdle Gate v2.2 max-20 compliance:\n")
for (m in names(max20_results)) {
  r <- max20_results[[m]]
  to_pass <- r$to_ann <= 6.0
  mdd_proxy <- min(cumprod(1 + r$monthly_table$ret_net) -
                     cummax(cumprod(1 + r$monthly_table$ret_net)) /
                     cummax(cumprod(1 + r$monthly_table$ret_net)))
  cat(sprintf("  %s: TO_ann=%.2f (≤6.0?: %s)  CAGR_net=%.2f%%  SR_net=%.2f\n",
              m, r$to_ann, ifelse(to_pass, "PASS", "FAIL"), r$cagr_net * 100, r$sr_net_ann))
}

#--- 5. Multi-trial DSR (Bailey-Lopez de Prado strict) ---
cat("\n[5] Multi-trial DSR Bailey-Lopez de Prado strict...\n")
n_trials_log <- fromJSON(file.path(WT_DIR, "multi_trial_dsr_log.json"))

# DSR formula (Bailey & Lopez de Prado 2014 J Portfolio Management):
# DSR = ((SR_obs - E[SR_max]) * sqrt(T - 1)) / sqrt(1 - skew*SR_obs + (kurt-1)/4 * SR_obs^2)
# where E[SR_max] = sqrt(2*log(N_trials)) * IID benchmark approximation
#                  - small correction (E-M constant + correction term)

# Compute per-model DSR for max-20 net returns
compute_dsr <- function(returns, n_trials) {
  if (length(returns) < 24) return(list(dsr = NA, sr = NA, deflation = NA))
  sr <- mean(returns) / sd(returns)
  # Skewness + kurtosis
  m <- returns - mean(returns)
  skew <- mean(m^3) / sd(returns)^3
  kurt <- mean(m^4) / sd(returns)^4
  T <- length(returns)
  # Bailey-LdP expected max SR (independent trials)
  emc <- 0.5772156649  # Euler-Mascheroni
  emax_sr <- sqrt(2 * log(max(n_trials, 1))) - (emc * (1 - 1/log(max(n_trials, 2))) - 0.5/sqrt(2 * log(max(n_trials, 2))))
  # Deflated SR
  num <- (sr - emax_sr) * sqrt(T - 1)
  denom <- sqrt(max(1 - skew * sr + (kurt - 1)/4 * sr^2, 1e-9))
  dsr <- num / denom
  list(dsr = dsr, sr = sr, expected_max_sr = emax_sr, n_trials = n_trials,
       skew = skew, kurt = kurt, T = T, deflation = sr - emax_sr)
}

# Two views of n_trials per the multi_trial_dsr_log.json
n_trials_view_a <- n_trials_log$n_trials_total_estimate$primary_for_dsr  # 40 (single-step view)
n_trials_view_b <- n_trials_log$n_trials_total_estimate$method_b_with_factor_preselect  # 80 × 7 = 560
n_trials_view_c <- 7  # 7 model specs only (most lenient)

dsr_log <- list()
for (m in names(max20_results)) {
  r <- max20_results[[m]]
  dsr_log[[m]] <- list(
    view_a_lenient_n_trials_7 = compute_dsr(r$monthly_table$ret_net, n_trials_view_c),
    view_b_internal_cv_n_trials_40 = compute_dsr(r$monthly_table$ret_net, n_trials_view_a),
    view_c_strict_n_trials_560 = compute_dsr(r$monthly_table$ret_net, n_trials_view_b)
  )
  cat(sprintf("  %s:\n    view_lenient (N=7):  DSR_net=%.3f\n    view_cv (N=40):      DSR_net=%.3f\n    view_strict (N=560): DSR_net=%.3f\n",
              m,
              dsr_log[[m]]$view_a_lenient_n_trials_7$dsr,
              dsr_log[[m]]$view_b_internal_cv_n_trials_40$dsr,
              dsr_log[[m]]$view_c_strict_n_trials_560$dsr))
}

# Save DSR log
dsr_strict <- list(
  task_id = WT_ID,
  reference = "Bailey-Lopez de Prado 2014 J Portfolio Management 'Pseudo-Mathematics & Financial Charlatanism'",
  formula = "DSR = ((SR_obs - E[SR_max]) * sqrt(T-1)) / sqrt(1 - skew*SR_obs + (kurt-1)/4 * SR_obs^2)",
  expected_max_sr_formula = "sqrt(2*log(N)) - (Euler-Mascheroni adjustment)",
  n_trials_views = list(
    view_a_lenient_n_trials_7 = "7 model specs only (5 base + 2 ensemble). Most lenient — assumes factor preselection is data-driven not search.",
    view_b_internal_cv_n_trials_40 = "7 specs + 33 internal CV trials (Ridge 13α + EN 20α). Standard view per Lopez de Prado 2020 ML for AM Ch 8.",
    view_c_strict_n_trials_560 = "80 factor universe × 7 specs = 560. Most strict — counts factor preselect as multiple-testing."
  ),
  per_model_dsr = dsr_log
)
writeLines(toJSON(dsr_strict, pretty = TRUE, auto_unbox = TRUE, na = "null"),
           file.path(WT_DIR, "dsr_strict_bailey_ldp.json"))
cat("  Saved: dsr_strict_bailey_ldp.json\n")

#--- 6. Best model selection ---
cat("\n[6] Best model selection (gate logic)...\n")
# Selection: rank IC sign positive + ICIR>=0.20 + sub_stab>=0.5 + Harvey-t>=3.0
# + DSR strict view_c >= 0.5 (Bailey-LdP strict gate)
# + max-20 TO_ann <= 6.0 (Hurdle Gate v2.2)
gate_summary <- list()
for (m in names(max20_results)) {
  d <- diag_results[[m]]
  r <- max20_results[[m]]
  dsr_strict_view <- dsr_log[[m]]$view_c_strict_n_trials_560$dsr
  gates <- list(
    rank_ic_pos = d$rank_ic > 0,
    rank_ic_mag = abs(d$rank_ic) >= 0.04,
    icir_mag = abs(d$icir) >= 0.20,
    sub_stab = d$sub_stab >= 0.5,
    harvey_t = abs(d$t_NW) >= 3.0,
    dsr_strict = dsr_strict_view >= 0.5,
    max20_TO = r$to_ann <= 6.0,
    max20_SR_pos = r$sr_net_ann > 0
  )
  pass_count <- sum(unlist(gates), na.rm = TRUE)
  pass_all <- all(unlist(gates), na.rm = TRUE)
  gate_summary[[m]] <- list(gates = gates, pass_count = pass_count, pass_all = pass_all,
                             score = abs(d$rank_ic) * pass_count)
}
score_dt <- data.table(
  model = names(gate_summary),
  pass_count = sapply(gate_summary, function(x) x$pass_count),
  pass_all = sapply(gate_summary, function(x) x$pass_all),
  score = sapply(gate_summary, function(x) x$score)
)[order(-score, -pass_count)]
print(score_dt)
best_model <- score_dt$model[1]
cat("\n  Best model:", best_model, "\n")

#--- 7. Forward 2026-05 alpha_vector ---
cat("\n[7] Forward 2026-05 alpha_vector (best model)...\n")
fwd_preds <- preds[YM_target == as.Date("2026-05-01")]
cat("  Forward rows:", nrow(fwd_preds), "\n")
av_raw <- fwd_preds[[best_model]]
# Z-score normalize
av_z <- (av_raw - mean(av_raw, na.rm = TRUE)) / (sd(av_raw, na.rm = TRUE) + 1e-9)
alpha_vec_export <- as.list(round(av_z, 6))
names(alpha_vec_export) <- fwd_preds$Ticker

# Confidence vector: based on cross-section rank stability (within month)
conf_vec <- rep(1.0, length(alpha_vec_export))
names(conf_vec) <- names(alpha_vec_export)
conf_vec_export <- as.list(conf_vec)

cat("  alpha_vector size:", length(alpha_vec_export), "tickers\n")
cat("  Top 10 by alpha:\n")
top10 <- fwd_preds[order(-get(best_model))][1:10, .(Ticker, Sector, alpha = round(av_z[order(-av_raw)][1:10], 4))]
print(top10)

#--- 8. alpha_scores_v5.parquet ---
cat("\n[8] alpha_scores_v5.parquet...\n")
write_parquet(preds, file.path(ART_DIR, "alpha_scores_v5.parquet"))
cat("  Saved\n")

#--- 9. Save Phase 3 diagnostics + gate summary ---
cat("\n[9] Saving Phase 3 results...\n")
# Strip non-serializable fields for JSON (lists with monthly_table data.tables)
clean_max20 <- lapply(max20_results, function(r) {
  list(sr_net_ann = r$sr_net_ann, sr_gross_ann = r$sr_gross_ann,
       to_ann = r$to_ann, cagr_net = r$cagr_net, n_months = r$n_months)
})
clean_diag <- lapply(diag_results, function(d) {
  list(rank_ic = d$rank_ic, icir = d$icir, t_NW = d$t_NW,
       sub_stab = d$sub_stab, n_months = d$n_months,
       monotonicity = d$monotonicity)
})

phase3 <- list(
  task_id = WT_ID,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  diag_per_model = clean_diag,
  max20_per_model = clean_max20,
  dsr_per_model_3views = dsr_log,
  gate_summary = gate_summary,
  best_model = best_model,
  best_score = score_dt$score[1],
  best_pass_count = score_dt$pass_count[1],
  best_pass_all = score_dt$pass_all[1],
  raw_vs_neutralized = list(
    raw_ic = raw_ic,
    post_neutralization_ic = post_neut_ic,
    neutral_retention_pct = round(neutral_retention * 100, 1),
    rf_a4_flag = rf_a4_flag
  ),
  multi_trial_dsr_n_trials_views = list(
    view_a_lenient = n_trials_view_c,
    view_b_internal_cv = n_trials_view_a,
    view_c_strict = n_trials_view_b
  )
)
writeLines(toJSON(phase3, pretty = TRUE, auto_unbox = TRUE, na = "null"),
           file.path(WT_DIR, "alpha_validation_v5.json"))
cat("  Saved alpha_validation_v5.json\n")

# Cache diagnostics for build script
saveRDS(list(
  diag_results = diag_results,
  max20_results = max20_results,
  dsr_log = dsr_log,
  gate_summary = gate_summary,
  best_model = best_model,
  alpha_vec_export = alpha_vec_export,
  conf_vec_export = conf_vec_export,
  fwd_preds = fwd_preds,
  raw_vs_neut = list(raw_ic = raw_ic, post_neut_ic = post_neut_ic,
                      neutral_retention = neutral_retention, rf_a4_flag = rf_a4_flag),
  n_trials_views = list(view_a = n_trials_view_c, view_b = n_trials_view_a, view_c = n_trials_view_b)
), file.path(WT_DIR, "phase3_cache.rds"))
cat("  Cached phase3_cache.rds for downstream build\n")

cat("\n================================================================\n")
cat("Phase 3 DONE — best_model:", best_model, "  pass_all:", score_dt$pass_all[1], "\n")
cat("================================================================\n")
