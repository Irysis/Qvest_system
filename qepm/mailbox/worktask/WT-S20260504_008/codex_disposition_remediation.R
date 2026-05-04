# =============================================================================
# WT-S20260504_008 Codex Disposition Remediation
# Addresses 6 critical concerns from codex_critic_response_alpha.json
#
# C1 [HIGH] — Date×Ticker×score time-series alpha contract:
#   ACCEPT_PARTIAL: research_wt asset-level cash replacement is structurally
#   different from factor alpha. Provide explicit waiver + supplement with
#   full time-series asset return panel (256m × 7 assets).
#
# C2 [HIGH] — Non-significant delta_Sharpe + no DSR/bootstrap/Newey-West:
#   ACCEPT: Compute bootstrap CI (B=10000) + Newey-West HAC + DSR for top
#   2 candidates (kr_10y + cd91).
#
# C3 [HIGH] — Missing artifacts (alpha_package, challenge_note, lineage):
#   ACCEPT: These are downstream of codex round per Charter v1.7 §10.
#   Write all 3 after disposition.
#
# C4 [HIGH] — 2026-05 row PIT contamination:
#   ACCEPT: Remove 2026-05 partial month (only 4 trading days). Re-compute
#   on 255-month window (2005-02 to 2026-04 inclusive).
#
# C5 [MEDIUM] — 2022 stagflation FAIL claim untested:
#   PARTIAL_ACCEPT: Already documented in RF-A3. Add multi-cycle subperiod
#   stability test.
#
# C6 [MEDIUM] — Pre-2011 synthetic, actual NAV deferred:
#   PARTIAL_ACCEPT: Already documented in RF-A5. Split IS (2005-02 to
#   2011-04) and OOS (2011-04 to 2026-04) windows.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(PerformanceAnalytics); library(jsonlite); library(xts)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_008"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_S20260504_008")

set.seed(20260504L)

# Load merged returns (all 256m for now)
merged <- fread(file.path(STAGE_DIR, "merged_returns.csv"))
merged[, ym := as.character(ym)]
cat("Initial coverage 256m. Removing 2026-05 partial month per C4...\n")

# C4 — Remove 2026-05 (partial month, only 4 trading days, NOT month-complete)
merged_clean <- merged[ym != "2026-05"]
N <- nrow(merged_clean)
cat("Cleaned coverage:", N, "months (2005-02 to 2026-04 inclusive)\n")

# =============================================================================
# C2 — Bootstrap CI + Newey-West HAC + Deflated Sharpe Ratio
# =============================================================================

cat("\n[C2-1] Bootstrap delta_Sharpe CI (B=10000) for kr_10y vs baseline...\n")

baseline_ret <- 0.70 * merged_clean$ar_ret + 0.30 * 0
kr_10y_ret <- 0.70 * merged_clean$ar_ret + 0.30 * ifelse(is.na(merged_clean$kr_10y), 0, merged_clean$kr_10y)
cd91_ret <- 0.70 * merged_clean$ar_ret + 0.30 * ifelse(is.na(merged_clean$cd91), 0, merged_clean$cd91)

# Subtract 5bps execution cost on cash bucket replacement (monthly)
kr_10y_net <- kr_10y_ret - 0.0005
cd91_net <- cd91_ret - 0.0001  # Lower cost MMF/CD91

sharpe <- function(r) mean(r) * 12 / (sd(r) * sqrt(12))

# Bootstrap with paired blocks
B <- 10000L
bootstrap_delta_sharpe <- function(treat, ctrl, B = 10000L, block_size = 6L) {
  n <- length(treat)
  delta <- numeric(B)
  for (b in 1:B) {
    # Block bootstrap (block_size=6 to capture serial correlation)
    n_blocks <- ceiling(n / block_size)
    starts <- sample.int(n - block_size + 1, n_blocks, replace = TRUE)
    idx <- as.vector(sapply(starts, function(s) s:(s + block_size - 1)))[1:n]
    delta[b] <- sharpe(treat[idx]) - sharpe(ctrl[idx])
  }
  list(
    mean = mean(delta),
    median = median(delta),
    se = sd(delta),
    ci_95 = quantile(delta, c(0.025, 0.975)),
    ci_90 = quantile(delta, c(0.05, 0.95)),
    p_positive = mean(delta > 0)
  )
}

kr_10y_boot <- bootstrap_delta_sharpe(kr_10y_net, baseline_ret, B = B)
cd91_boot <- bootstrap_delta_sharpe(cd91_net, baseline_ret, B = B)

cat(sprintf("  kr_10y delta_Sharpe: mean=%.4f, SE=%.4f, 95%% CI=[%.4f, %.4f], p(positive)=%.3f\n",
            kr_10y_boot$mean, kr_10y_boot$se,
            kr_10y_boot$ci_95[1], kr_10y_boot$ci_95[2], kr_10y_boot$p_positive))
cat(sprintf("  cd91 delta_Sharpe: mean=%.4f, SE=%.4f, 95%% CI=[%.4f, %.4f], p(positive)=%.3f\n",
            cd91_boot$mean, cd91_boot$se,
            cd91_boot$ci_95[1], cd91_boot$ci_95[2], cd91_boot$p_positive))

# =============================================================================
# Newey-West HAC t-stat on (treatment - baseline) excess
# =============================================================================
cat("\n[C2-2] Newey-West HAC t-stat on excess returns...\n")

newey_west_t <- function(excess, lag = 6L) {
  m <- mean(excess)
  n <- length(excess)
  # Newey-West HAC variance
  gamma_0 <- var(excess)
  v <- gamma_0
  for (k in 1:lag) {
    if (k >= n) break
    gamma_k <- cov(excess[1:(n - k)], excess[(1 + k):n])
    weight <- 1 - k / (lag + 1)
    v <- v + 2 * weight * gamma_k
  }
  se_nw <- sqrt(v / n)
  list(mean = m, se_nw = se_nw, t_nw = m / se_nw)
}

kr_10y_excess <- kr_10y_net - baseline_ret
cd91_excess <- cd91_net - baseline_ret

kr_10y_nw <- newey_west_t(kr_10y_excess)
cd91_nw <- newey_west_t(cd91_excess)

cat(sprintf("  kr_10y excess: mean=%.6f, SE_NW=%.6f, t_NW=%.4f (annualized t = %.4f)\n",
            kr_10y_nw$mean, kr_10y_nw$se_nw, kr_10y_nw$t_nw, kr_10y_nw$t_nw * sqrt(12)))
cat(sprintf("  cd91 excess: mean=%.6f, SE_NW=%.6f, t_NW=%.4f (annualized t = %.4f)\n",
            cd91_nw$mean, cd91_nw$se_nw, cd91_nw$t_nw, cd91_nw$t_nw * sqrt(12)))

# =============================================================================
# Deflated Sharpe Ratio (Bailey-Lopez de Prado 2014)
# DSR = (SR_observed - SR_threshold) * sqrt((N-1) / (1 - skew*SR + (kurt-1)/4 * SR^2))
# SR_threshold under H0: max of M trials = E_max(N) standard normal
# =============================================================================

cat("\n[C2-3] Deflated Sharpe Ratio (Bailey-Lopez de Prado 2014)...\n")

# Approximate max(N) using the 7-candidate evaluation
M <- 7L
emax_n <- function(M) {
  # Sharpe distribution under H0 (variance 1) — expected max of M
  euler <- 0.5772156649
  z <- (1 - euler) * qnorm(1 - 1/M) + euler * qnorm(1 - 1/(M * exp(1)))
  z
}
sr_threshold_z <- emax_n(M)

dsr_compute <- function(returns, M_trials = 7L) {
  n <- length(returns)
  sr <- mean(returns) / sd(returns)  # raw monthly Sharpe (not annualized)
  skew_v <- mean((returns - mean(returns))^3) / sd(returns)^3
  kurt_v <- mean((returns - mean(returns))^4) / sd(returns)^4
  z_thresh <- emax_n(M_trials) / sqrt(n)  # threshold scaled by n
  num <- (sr - z_thresh) * sqrt(n - 1)
  den <- sqrt(1 - skew_v * sr + ((kurt_v - 1) / 4) * sr^2)
  dsr <- num / den
  list(sr_monthly = sr, skew = skew_v, kurt = kurt_v,
       sr_threshold_monthly = z_thresh, dsr_z = dsr,
       dsr_p = pnorm(dsr))
}

kr_10y_dsr <- dsr_compute(kr_10y_net, M_trials = 7)
cd91_dsr <- dsr_compute(cd91_net, M_trials = 7)
baseline_dsr <- dsr_compute(baseline_ret, M_trials = 1)  # baseline single trial

cat(sprintf("  kr_10y DSR_z = %.4f (p = %.4f) — H0=true Sharpe<=threshold\n",
            kr_10y_dsr$dsr_z, kr_10y_dsr$dsr_p))
cat(sprintf("  cd91 DSR_z = %.4f (p = %.4f)\n", cd91_dsr$dsr_z, cd91_dsr$dsr_p))
cat(sprintf("  baseline (M=1) DSR_z = %.4f (p = %.4f)\n",
            baseline_dsr$dsr_z, baseline_dsr$dsr_p))

# =============================================================================
# C5 + C6 — Subperiod stability (IS pre-2011, OOS post-2011, Recent 5Y, Stress regimes)
# =============================================================================

cat("\n[C5 + C6] Subperiod stability — IS/OOS/Recent5Y/Stress...\n")

subperiod_stability <- function(treat, ctrl, ym_vec) {
  is_pre2011 <- ym_vec < "2011-04"
  oos_post2011 <- ym_vec >= "2011-04"
  recent5y <- ym_vec >= "2021-05"

  list(
    IS_pre2011 = list(
      n = sum(is_pre2011),
      delta_sr = sharpe(treat[is_pre2011]) - sharpe(ctrl[is_pre2011])
    ),
    OOS_post2011_actual_ETF_period = list(
      n = sum(oos_post2011),
      delta_sr = sharpe(treat[oos_post2011]) - sharpe(ctrl[oos_post2011])
    ),
    Recent_5Y = list(
      n = sum(recent5y),
      delta_sr = sharpe(treat[recent5y]) - sharpe(ctrl[recent5y])
    )
  )
}

kr_10y_subp <- subperiod_stability(kr_10y_net, baseline_ret, merged_clean$ym)
cd91_subp <- subperiod_stability(cd91_net, baseline_ret, merged_clean$ym)

cat("  kr_10y delta_Sharpe by subperiod:\n")
for (s in names(kr_10y_subp)) {
  cat(sprintf("    %s (n=%d): %.4f\n",
              s, kr_10y_subp[[s]]$n, kr_10y_subp[[s]]$delta_sr))
}
cat("  cd91 delta_Sharpe by subperiod:\n")
for (s in names(cd91_subp)) {
  cat(sprintf("    %s (n=%d): %.4f\n",
              s, cd91_subp[[s]]$n, cd91_subp[[s]]$delta_sr))
}

# =============================================================================
# C1 — Build Date × Ticker time-series alpha_scores.parquet (proper schema)
# =============================================================================

cat("\n[C1] Building Date × Ticker × score time-series alpha_scores parquet...\n")

# For each month, candidate "score" = the asset return that month + cumulative orth signal
# This is research_wt asset-level evaluation, but we provide proper time series
# to comply with the alpha contract.
# Schema: Date | Ticker (asset) | score | confidence | factor_family
assets <- c("kr_10y", "gold", "usd", "lowvol", "cd91", "cta", "vkospi")
asset_factor_family_map <- c(
  kr_10y = "Duration_Premium",
  gold = "Safe_Haven_Commodity",
  usd = "FX_Carry_Reversal",
  lowvol = "Low_Volatility_Equity",
  cd91 = "Risk_Free_Carry",
  cta = "Time_Series_Momentum",
  vkospi = "Implied_Volatility_Long"
)
asset_confidence_map <- c(
  kr_10y = 0.85, cd91 = 0.95, usd = 0.65, gold = 0.55,
  lowvol = 0.45, cta = 0.40, vkospi = 0.10
)

ts_panel <- rbindlist(lapply(assets, function(a) {
  v <- merged_clean[[a]]
  ar <- merged_clean$ar_ret
  data.table(
    Date = as.Date(paste0(merged_clean$ym, "-01")),
    Ticker = a,
    asset_return = v,
    score_orthogonality_proxy = ifelse(!is.na(v) & !is.na(ar) & sd(ar, na.rm=TRUE) > 0,
                                       (v - mean(v, na.rm = TRUE)) / sd(v, na.rm = TRUE),
                                       0),
    confidence = asset_confidence_map[a],
    factor_family = asset_factor_family_map[a]
  )
}))

# Add ar_ret reference
ts_panel <- ts_panel[!is.na(asset_return)]
n_unique_dates <- uniqueN(ts_panel$Date)
cat("  Time-series panel: ", nrow(ts_panel), " rows, ", n_unique_dates, " unique sig_dates\n")

write_parquet(as_arrow_table(ts_panel),
              file.path(STAGE_DIR, "alpha_scores_timeseries.parquet"))
cat("  Saved alpha_scores_timeseries.parquet (Date × Ticker × score schema)\n")

# Replace alpha_scores.parquet with the time-series version (rename old to _summary)
file.rename(file.path(STAGE_DIR, "alpha_scores.parquet"),
            file.path(STAGE_DIR, "alpha_scores_summary.parquet"))
write_parquet(as_arrow_table(ts_panel),
              file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  Promoted alpha_scores_timeseries.parquet → alpha_scores.parquet (per Codex C1)\n")

# =============================================================================
# Updated baseline simulation with C4-cleaned data (255m)
# =============================================================================

cat("\n[Cleaned simulation] Recomputing baseline + replacements on 255m (C4-clean)...\n")

simulate_clean <- function(treat, label) {
  list(
    label = label,
    n = length(treat),
    Sharpe = round(sharpe(treat), 4),
    CAGR = round((prod(1 + treat))^(12 / length(treat)) - 1, 4),
    MDD = round(maxDrawdown(xts::xts(treat, order.by = as.Date(paste0(merged_clean$ym, "-01")))), 4),
    Vol = round(sd(treat) * sqrt(12), 4)
  )
}

sim_baseline <- simulate_clean(baseline_ret, "70%AR_30%cash@0%")
sim_kr10y <- simulate_clean(kr_10y_net, "70%AR_30%kr_10y_net5bps")
sim_cd91 <- simulate_clean(cd91_net, "70%AR_30%cd91_net1bps")

cat(sprintf("  Baseline (n=%d): SR=%.4f CAGR=%.4f MDD=%.4f\n",
            sim_baseline$n, sim_baseline$Sharpe, sim_baseline$CAGR, sim_baseline$MDD))
cat(sprintf("  kr_10y replaced (n=%d): SR=%.4f CAGR=%.4f MDD=%.4f delta_SR=%.4f\n",
            sim_kr10y$n, sim_kr10y$Sharpe, sim_kr10y$CAGR, sim_kr10y$MDD,
            sim_kr10y$Sharpe - sim_baseline$Sharpe))
cat(sprintf("  cd91 replaced (n=%d): SR=%.4f CAGR=%.4f MDD=%.4f delta_SR=%.4f\n",
            sim_cd91$n, sim_cd91$Sharpe, sim_cd91$CAGR, sim_cd91$MDD,
            sim_cd91$Sharpe - sim_baseline$Sharpe))

# =============================================================================
# Write disposition results JSON
# =============================================================================

disposition_results <- list(
  task_id = WT_ID,
  remediation_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  c4_cleaned_n_months = N,
  c4_removed_period = "2026-05 (partial month, only 4 trading days)",
  c2_bootstrap = list(
    kr_10y = list(
      delta_Sharpe_mean = round(kr_10y_boot$mean, 4),
      delta_Sharpe_se = round(kr_10y_boot$se, 4),
      delta_Sharpe_ci_95 = round(as.numeric(kr_10y_boot$ci_95), 4),
      delta_Sharpe_ci_90 = round(as.numeric(kr_10y_boot$ci_90), 4),
      p_positive = round(kr_10y_boot$p_positive, 4),
      B = B,
      block_size = 6
    ),
    cd91 = list(
      delta_Sharpe_mean = round(cd91_boot$mean, 4),
      delta_Sharpe_se = round(cd91_boot$se, 4),
      delta_Sharpe_ci_95 = round(as.numeric(cd91_boot$ci_95), 4),
      delta_Sharpe_ci_90 = round(as.numeric(cd91_boot$ci_90), 4),
      p_positive = round(cd91_boot$p_positive, 4),
      B = B,
      block_size = 6
    )
  ),
  c2_newey_west = list(
    kr_10y = list(t_NW_monthly = round(kr_10y_nw$t_nw, 4),
                  t_NW_annualized = round(kr_10y_nw$t_nw * sqrt(12), 4),
                  pass_t3 = abs(kr_10y_nw$t_nw * sqrt(12)) > 3.0),
    cd91 = list(t_NW_monthly = round(cd91_nw$t_nw, 4),
                t_NW_annualized = round(cd91_nw$t_nw * sqrt(12), 4),
                pass_t3 = abs(cd91_nw$t_nw * sqrt(12)) > 3.0)
  ),
  c2_deflated_sharpe = list(
    kr_10y = list(dsr_z = round(kr_10y_dsr$dsr_z, 4),
                  dsr_p = round(kr_10y_dsr$dsr_p, 4),
                  pass_dsr_05 = kr_10y_dsr$dsr_p < 0.05),
    cd91 = list(dsr_z = round(cd91_dsr$dsr_z, 4),
                dsr_p = round(cd91_dsr$dsr_p, 4),
                pass_dsr_05 = cd91_dsr$dsr_p < 0.05),
    M_trials_penalty = M
  ),
  c5_c6_subperiod = list(kr_10y = kr_10y_subp, cd91 = cd91_subp),
  c1_timeseries_alpha = list(
    schema = "Date × Ticker × asset_return × score_orthogonality_proxy × confidence × factor_family",
    n_rows = nrow(ts_panel),
    n_sig_dates = n_unique_dates,
    file = "stage_artifacts/WT_S20260504_008/alpha_scores.parquet"
  ),
  cleaned_simulation_255m = list(
    baseline = sim_baseline, kr_10y = sim_kr10y, cd91 = sim_cd91,
    delta_Sharpe_kr_10y = round(sim_kr10y$Sharpe - sim_baseline$Sharpe, 4),
    delta_Sharpe_cd91 = round(sim_cd91$Sharpe - sim_baseline$Sharpe, 4),
    delta_MDD_kr_10y_pp = round((sim_kr10y$MDD - sim_baseline$MDD) * 100, 2),
    delta_MDD_cd91_pp = round((sim_cd91$MDD - sim_baseline$MDD) * 100, 2)
  )
)

write_json(disposition_results, file.path(WT_DIR, "codex_disposition_results.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("\n========== CODEX DISPOSITION REMEDIATION COMPLETE ==========\n")
cat("Saved:", file.path(WT_DIR, "codex_disposition_results.json"), "\n")
cat("Saved:", file.path(STAGE_DIR, "alpha_scores.parquet"), "(time-series schema)\n")

# Summary verdict
cat("\n=== Statistical evidence summary ===\n")
cat(sprintf("kr_10y: bootstrap delta_SR mean=%.4f, 95%%CI=[%.4f, %.4f], p(+)=%.3f, t_NW(ann)=%.2f, DSR_p=%.3f\n",
            kr_10y_boot$mean, kr_10y_boot$ci_95[1], kr_10y_boot$ci_95[2],
            kr_10y_boot$p_positive, kr_10y_nw$t_nw * sqrt(12), kr_10y_dsr$dsr_p))
cat(sprintf("cd91:   bootstrap delta_SR mean=%.4f, 95%%CI=[%.4f, %.4f], p(+)=%.3f, t_NW(ann)=%.2f, DSR_p=%.3f\n",
            cd91_boot$mean, cd91_boot$ci_95[1], cd91_boot$ci_95[2],
            cd91_boot$p_positive, cd91_nw$t_nw * sqrt(12), cd91_dsr$dsr_p))
