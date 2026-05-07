# =============================================================================
# Cycle 5 — Axis 5: Regime shift conditional response
# =============================================================================
# 1) 사이클 4 4-regime per-regime Σ inheritance
# 2) Forward 12m regime transition Markov simulation (ergodic + non-ergodic)
# 3) BULL → CAUTION → CRISIS scenario에서 Hybrid 응답 분포
# 4) AX-001 v2 conditional defense (KR_10y bond) 시간 검증
#
# Methodology:
# - Hamilton 1989 ECMA Markov regime
# - Empirical transition matrix (post-2015)
# - Markov simulation + Hybrid return distribution per regime
# - AX-001 v2: crisis_alpha + Core MDD relief + bad/normal IC ratio
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

set.seed(20260508L)

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

hybrid_dir <- "qepm/mailbox/research/risk_cycle5_20260507"

# ---- 1. Data load ----
master <- fread("qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")
master[, ym_date := as.Date(paste0(ym, "-01"))]
post2015 <- master[ym_date >= as.Date("2015-01-01") & has_tsmom == TRUE]
post2015 <- post2015[!is.na(r_AR) & !is.na(r_TSMOM) & !is.na(r_KR10y)]
post2015[, r_Hybrid := 0.70 * r_AR + 0.15 * r_TSMOM + 0.15 * r_KR10y]

# Regime classification (Hybrid bottom 10%/40%/70%)
post2015[, hybrid_q := ecdf(r_Hybrid)(r_Hybrid)]
post2015[, regime := fifelse(hybrid_q <= 0.10, "CRISIS",
                     fifelse(hybrid_q <= 0.40, "CAUTION",
                     fifelse(hybrid_q <= 0.70, "NORMAL", "BULL")))]

# Time-ordered regime sequence
post2015 <- post2015[order(ym_date)]

# ---- 2. Empirical transition matrix ----
regimes <- c("BULL", "NORMAL", "CAUTION", "CRISIS")
n_states <- length(regimes)

# Build transition counts
trans_counts <- matrix(0, nrow = n_states, ncol = n_states,
                       dimnames = list(from = regimes, to = regimes))
for (i in 2:nrow(post2015)) {
  from <- post2015$regime[i - 1L]
  to <- post2015$regime[i]
  trans_counts[from, to] <- trans_counts[from, to] + 1
}

# Row-normalize
trans_matrix <- trans_counts / rowSums(trans_counts)
trans_matrix[is.nan(trans_matrix)] <- 0

cat("Empirical transition matrix (post-2015):\n")
print(round(trans_matrix, 4))
cat("\nTransition counts:\n")
print(trans_counts)

fwrite(as.data.table(trans_matrix, keep.rownames = "from"),
       file.path(hybrid_dir, "axis5_transition_matrix.csv"))

# ---- 3. Stationary distribution + ergodicity check ----
# Stationary distribution: π = π × P (left eigenvector with eigenvalue 1)
eig <- eigen(t(trans_matrix))
# Find eigenvector with eigenvalue close to 1
idx_one <- which.min(abs(eig$values - 1))
pi_stationary <- Re(eig$vectors[, idx_one])
pi_stationary <- pi_stationary / sum(pi_stationary)
names(pi_stationary) <- regimes

cat("\nStationary distribution (ergodic equilibrium):\n")
print(round(pi_stationary, 4))

# Empirical distribution
emp_dist <- table(post2015$regime)
emp_dist <- emp_dist / sum(emp_dist)
cat("\nEmpirical distribution (post-2015):\n")
print(round(as.numeric(emp_dist[regimes]), 4))

# ---- 4. Per-regime Hybrid return distribution ----
regime_summary <- post2015[, .(
  n = .N,
  mean_ann = mean(r_Hybrid) * 12,
  sd_ann = sd(r_Hybrid) * sqrt(12),
  sr = (mean(r_Hybrid) * 12) / (sd(r_Hybrid) * sqrt(12)),
  q025 = quantile(r_Hybrid, 0.025),
  q500 = quantile(r_Hybrid, 0.500),
  q975 = quantile(r_Hybrid, 0.975)
), by = regime][order(factor(regime, levels = regimes))]
fwrite(regime_summary, file.path(hybrid_dir, "axis5_per_regime_hybrid.csv"))
cat("\nHybrid 70/15/15 per-regime returns:\n")
print(regime_summary)

# Per-regime each source
regime_per_source <- post2015[, .(
  n = .N,
  mean_AR_ann = mean(r_AR) * 12,
  mean_TSMOM_ann = mean(r_TSMOM) * 12,
  mean_KR10y_ann = mean(r_KR10y) * 12,
  sd_AR_ann = sd(r_AR) * sqrt(12),
  sd_TSMOM_ann = sd(r_TSMOM) * sqrt(12),
  sd_KR10y_ann = sd(r_KR10y) * sqrt(12)
), by = regime][order(factor(regime, levels = regimes))]
fwrite(regime_per_source, file.path(hybrid_dir, "axis5_per_regime_sources.csv"))
cat("\nPer-source per-regime annualized:\n")
print(regime_per_source)

# ---- 5. Markov forward simulation 12 months × 1000 trials ----
sim_markov <- function(P, init_state, n_steps, n_trials = 1000L) {
  states <- rownames(P)
  n_s <- length(states)
  out <- matrix("", nrow = n_trials, ncol = n_steps)
  for (m in 1:n_trials) {
    cur <- init_state
    for (t in 1:n_steps) {
      probs <- P[cur, ]
      cur <- sample(states, 1L, prob = probs)
      out[m, t] <- cur
    }
  }
  out
}

# Initial state: 2026-03 (latest in sample)
# 5월 운용: m4=1.0 NORMAL × β_AR=0.7
# 사이클 5 forward simulation 시작점: latest sample regime
init_state <- post2015$regime[nrow(post2015)]
cat(sprintf("\nInitial state (2026-03): %s\n", init_state))

# 12-month forward simulation 1000 trials
mk_sim <- sim_markov(trans_matrix, init_state, n_steps = 12L, n_trials = 1000L)

# Probability of each state per horizon
prob_per_horizon <- list()
for (h in 1:12L) {
  state_counts <- table(mk_sim[, h])
  state_probs <- state_counts / 1000
  prob_per_horizon[[h]] <- as.list(state_probs[regimes])
}
prob_dt <- rbindlist(lapply(seq_along(prob_per_horizon), function(h) {
  p <- prob_per_horizon[[h]]
  data.table(
    h_month = h,
    BULL = ifelse(is.null(p$BULL) || is.na(p$BULL), 0, p$BULL),
    NORMAL = ifelse(is.null(p$NORMAL) || is.na(p$NORMAL), 0, p$NORMAL),
    CAUTION = ifelse(is.null(p$CAUTION) || is.na(p$CAUTION), 0, p$CAUTION),
    CRISIS = ifelse(is.null(p$CRISIS) || is.na(p$CRISIS), 0, p$CRISIS)
  )
}))
fwrite(prob_dt, file.path(hybrid_dir, "axis5_markov_forward_state_probs.csv"))
cat("\nMarkov forward state probabilities:\n")
print(prob_dt)

# ---- 6. Cumulative Hybrid return per Markov path ----
# 각 trial: Markov path → per-regime mean return → cumulative
sim_cum_ret <- function(states_path, regime_summary) {
  # use mean monthly return per regime
  monthly_means <- regime_summary[, .(regime, mean_monthly = mean_ann / 12)]
  monthly_sds <- regime_summary[, .(regime, sd_monthly = sd_ann / sqrt(12))]
  cum <- numeric(length(states_path))
  for (t in seq_along(states_path)) {
    rg <- states_path[t]
    mu <- monthly_means[regime == rg]$mean_monthly
    sigma <- monthly_sds[regime == rg]$sd_monthly
    if (length(mu) == 0L) mu <- 0
    if (length(sigma) == 0L) sigma <- 0.01
    cum[t] <- rnorm(1L, mean = mu, sd = sigma)
  }
  cumprod(1 + cum) - 1
}

mk_cum_ret <- t(sapply(1:1000L, function(m) {
  sim_cum_ret(mk_sim[m, ], regime_summary)
}))

cum_ret_summary <- data.table(
  h_month = 1:12L,
  cum_ret_q025 = apply(mk_cum_ret, 2L, quantile, 0.025),
  cum_ret_q500 = apply(mk_cum_ret, 2L, quantile, 0.500),
  cum_ret_q975 = apply(mk_cum_ret, 2L, quantile, 0.975),
  pr_neg = apply(mk_cum_ret, 2L, function(x) mean(x < 0))
)
fwrite(cum_ret_summary, file.path(hybrid_dir, "axis5_markov_cum_ret.csv"))
cat("\nMarkov forward cumulative return distribution:\n")
print(cum_ret_summary)

# ---- 7. AX-001 v2 conditional defense check (KR_10y) ----
# AX-001 v2: crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio
#
# KR_10y bond ETF role: defensive sleeve in Hybrid (15%)
# Test 1: crisis_alpha — KR_10y CRISIS regime contribution > 0?
# Test 2: Core (AR) 대비 MDD 완화 — 15% KR_10y addition reduces drawdown?
# Test 3: bad / normal IC ratio — KR_10y bad-regime correlation with AR < normal?

ax001_check <- list()

# Test 1: CRISIS regime KR10y mean
kr10y_crisis_mean <- post2015[regime == "CRISIS", mean(r_KR10y, na.rm = TRUE)]
kr10y_normal_mean <- post2015[regime == "NORMAL", mean(r_KR10y, na.rm = TRUE)]
kr10y_caution_mean <- post2015[regime == "CAUTION", mean(r_KR10y, na.rm = TRUE)]
ar_crisis_mean <- post2015[regime == "CRISIS", mean(r_AR, na.rm = TRUE)]

ax001_check$test1_crisis_alpha <- list(
  kr10y_crisis = kr10y_crisis_mean,
  ar_crisis = ar_crisis_mean,
  kr10y_normal = kr10y_normal_mean,
  kr10y_caution = kr10y_caution_mean,
  pass = kr10y_crisis_mean > 0,
  rationale = sprintf("CRISIS regime KR10y mean monthly: %.4f. AR CRISIS mean: %.4f. KR10y CRISIS positive = crisis_alpha PASS",
                      kr10y_crisis_mean, ar_crisis_mean)
)

# Test 2: MDD relief
# AR 70% standalone vs Hybrid 70/15/15 MDD comparison
compute_mdd <- function(r) {
  cum <- cumprod(1 + r)
  peak <- cummax(cum)
  dd <- (cum / peak) - 1
  min(dd)
}

mdd_AR_only <- compute_mdd(post2015$r_AR)  # Note: this is AR strategy only, not w_AR scaled
mdd_Hybrid <- compute_mdd(post2015$r_Hybrid)
# 비교 정정: Hybrid 70/15/15 vs Pure AR (100% AR allocation 가정)
# Pure AR strategy 100% = r_AR
# Hybrid = 0.70 * r_AR + 0.15 * r_TSMOM + 0.15 * r_KR10y
# 70% AR + 30% cash 5월 운용: r_AR70_cash30 = 0.70 * r_AR
r_AR70_cash30 <- 0.70 * post2015$r_AR  # current 5월 운용 mode
mdd_AR70_cash30 <- compute_mdd(r_AR70_cash30)

ax001_check$test2_mdd_relief <- list(
  mdd_AR_100pct = mdd_AR_only,
  mdd_AR70_cash30_currentMay = mdd_AR70_cash30,
  mdd_Hybrid_70_15_15 = mdd_Hybrid,
  hybrid_vs_AR100_relief_pp = (mdd_AR_only - mdd_Hybrid) * 100,
  hybrid_vs_AR70cash30_relief_pp = (mdd_AR70_cash30 - mdd_Hybrid) * 100,
  pass = mdd_Hybrid > mdd_AR_only && mdd_Hybrid > mdd_AR70_cash30,
  rationale = "Hybrid MDD < AR pure MDD 시 PASS"
)

# Test 3: bad/normal IC ratio
# Proxy: cor(r_AR, r_KR10y) per regime
cor_AR_KR10y_crisis <- post2015[regime == "CRISIS", cor(r_AR, r_KR10y)]
cor_AR_KR10y_caution <- post2015[regime == "CAUTION", cor(r_AR, r_KR10y)]
cor_AR_KR10y_normal <- post2015[regime == "NORMAL", cor(r_AR, r_KR10y)]
cor_AR_KR10y_bull <- post2015[regime == "BULL", cor(r_AR, r_KR10y)]

ax001_check$test3_bad_normal_ratio <- list(
  cor_crisis = cor_AR_KR10y_crisis,
  cor_caution = cor_AR_KR10y_caution,
  cor_normal = cor_AR_KR10y_normal,
  cor_bull = cor_AR_KR10y_bull,
  bad_lt_normal = cor_AR_KR10y_crisis < cor_AR_KR10y_normal,
  rationale = "bad regime (CRISIS) cor with AR should be < normal regime cor (defensive role)"
)

# Overall AX-001 v2 verdict
ax001_check$overall_pass <- (
  ax001_check$test1_crisis_alpha$pass &&
  ax001_check$test2_mdd_relief$pass &&
  ax001_check$test3_bad_normal_ratio$bad_lt_normal
)

cat("\nAX-001 v2 conditional defense check (KR_10y):\n")
cat(sprintf("  Test 1 crisis_alpha:  %s (KR10y CRISIS %.4f > 0)\n",
            ax001_check$test1_crisis_alpha$pass, kr10y_crisis_mean))
cat(sprintf("  Test 2 MDD relief:    %s (Hybrid %.4f vs AR100 %.4f)\n",
            ax001_check$test2_mdd_relief$pass, mdd_Hybrid, mdd_AR_only))
cat(sprintf("  Test 3 bad/normal:    %s (cor crisis %.4f vs normal %.4f)\n",
            ax001_check$test3_bad_normal_ratio$bad_lt_normal,
            cor_AR_KR10y_crisis, cor_AR_KR10y_normal))
cat(sprintf("  Overall PASS:         %s\n", ax001_check$overall_pass))

# ---- 8. Scenario stress: 12m forward {BULL_dominant, NORMAL_average, CAUTION_persist, CRISIS_shock} ----
# 명시 시나리오 — 보수적 stress test
scenario_stress <- list(
  bull_12m = list(
    description = "BULL regime persists 12 months",
    assumed_regime_path = rep("BULL", 12L),
    expected_return_ann = regime_summary[regime == "BULL"]$mean_ann,
    expected_sr = regime_summary[regime == "BULL"]$sr
  ),
  normal_12m = list(
    description = "NORMAL regime persists 12 months",
    assumed_regime_path = rep("NORMAL", 12L),
    expected_return_ann = regime_summary[regime == "NORMAL"]$mean_ann,
    expected_sr = regime_summary[regime == "NORMAL"]$sr
  ),
  caution_12m = list(
    description = "CAUTION regime persists 12 months",
    assumed_regime_path = rep("CAUTION", 12L),
    expected_return_ann = regime_summary[regime == "CAUTION"]$mean_ann,
    expected_sr = regime_summary[regime == "CAUTION"]$sr
  ),
  crisis_2of12 = list(
    description = "CRISIS occurs 2 of 12 months (rest NORMAL)",
    assumed_regime_path = c(rep("NORMAL", 5L), "CRISIS", rep("NORMAL", 5L), "CRISIS"),
    expected_cum_ret = (1 + regime_summary[regime == "NORMAL"]$mean_ann/12)^10 *
                       (1 + regime_summary[regime == "CRISIS"]$mean_ann/12)^2 - 1
  ),
  crisis_4of12 = list(
    description = "CRISIS escalation: 4 of 12 months CRISIS",
    expected_cum_ret = (1 + regime_summary[regime == "NORMAL"]$mean_ann/12)^8 *
                       (1 + regime_summary[regime == "CRISIS"]$mean_ann/12)^4 - 1
  )
)

# Save
write_json(scenario_stress, file.path(hybrid_dir, "axis5_scenario_stress.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ---- 9. Save Axis 5 summary ----
axis5_summary <- list(
  axis = "axis_5_regime_shift_conditional_response",
  empirical_transition_matrix_csv = "axis5_transition_matrix.csv",
  stationary_distribution = as.list(pi_stationary),
  empirical_distribution = list(
    BULL = as.numeric(emp_dist["BULL"]),
    NORMAL = as.numeric(emp_dist["NORMAL"]),
    CAUTION = as.numeric(emp_dist["CAUTION"]),
    CRISIS = as.numeric(emp_dist["CRISIS"])
  ),
  per_regime_hybrid_csv = "axis5_per_regime_hybrid.csv",
  per_regime_sources_csv = "axis5_per_regime_sources.csv",
  initial_state_2026_03 = init_state,
  markov_forward_state_probs_csv = "axis5_markov_forward_state_probs.csv",
  markov_cum_ret_csv = "axis5_markov_cum_ret.csv",
  ax_001_v2_check = ax001_check,
  scenario_stress_json = "axis5_scenario_stress.json",
  alert_thresholds = list(
    crisis_persist_warning_h_lt_3 = 0.30,
    cum_ret_neg_warning_h12 = 0.20,
    rationale = "12m horizon에서 P(CRISIS) > 30% OR P(cum_ret<0) > 20% 시 monitoring agent alert"
  ),
  citations = c(
    "Hamilton 1989 ECMA Markov regime",
    "AX-001 v2 conditional defense L-274",
    "L-281 KR_10y bond conditional Pareto"
  )
)

write_json(axis5_summary, file.path(hybrid_dir, "axis5_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Axis 5] DONE\n")
