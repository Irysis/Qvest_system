#==============================================================================
# WT-D20260528_003 v3.7 — Step 5: Full Validation (graduation gate)
#
# Gate checks:
#   - Rank IC >= 0.04 ✅
#   - ICIR >= 0.20 ✅
#   - Subperiod stability >= 0.5 ✅
#   - Harvey-Liu-Zhu 5-spec t > 3.0 >= 3 (mandatory)
#   - DSR >= 0.5
#   - Sector-neut IC retention >= 50% (already verified Step 2)
#   - Composite >= best single (RF-A2, Step 3 PASS)
#   - Bad/Normal IC ratio >= 0.5 (AX-001 v2 crisis_alpha)
#   - Monotonicity >= 0.7 (decile spread)
#
# Output:
#   - outputs/v3_7/alpha_full_validation.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(future)
  library(future.apply)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")

cat("[Step 5: Full validation] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load alpha scores + panel ----
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "top12_factor_panel_neut.parquet")))
panel[, Date := as.Date(Date)]
alpha <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores.parquet")))
alpha[, Date := as.Date(Date)]

# Merge alpha_score back with fwd_ret + neut cols for analysis
panel <- merge(panel, alpha, by = c("Date", "Ticker"), all.x = TRUE)

# ---- 2. Per-Date rank IC time series ----
cat("[2] Computing IC time series ...\n")
ic_ts <- panel[!is.na(fwd_ret) & !is.na(alpha_score),
               .(rank_ic = if (.N >= 10) suppressWarnings(cor(alpha_score, fwd_ret, method="spearman")) else NA_real_,
                 n_stocks = .N),
               by = Date][!is.na(rank_ic)]
setorder(ic_ts, Date)

m_ic <- mean(ic_ts$rank_ic, na.rm = TRUE)
sd_ic <- sd(ic_ts$rank_ic, na.rm = TRUE)
n_ic <- nrow(ic_ts)
icir <- m_ic / sd_ic
t_stat <- m_ic / (sd_ic / sqrt(n_ic))

cat("  Rank IC mean:", round(m_ic, 5), " sd:", round(sd_ic, 5), "\n")
cat("  ICIR:", round(icir, 4), " t-stat:", round(t_stat, 2), "\n\n")

# ---- 3. Harvey-Liu-Zhu 5-spec robustness ----
# Spec A: Spearman rank IC (baseline)
# Spec B: Pearson IC (linear)
# Spec C: Long-Short top/bottom decile spread (D10-D1 portfolio return)
# Spec D: Newey-West t-stat (HAC, 12 month lag)
# Spec E: Top quintile spread (D5-D1)
cat("[3] Harvey-Liu-Zhu 5-spec ...\n")

# Spec A
spec_a_t <- t_stat

# Spec B: Pearson IC
pearson_ts <- panel[!is.na(fwd_ret) & !is.na(alpha_score),
                    .(pearson_ic = if (.N >= 10) suppressWarnings(cor(alpha_score, fwd_ret, method="pearson")) else NA_real_),
                    by = Date][!is.na(pearson_ic)]
m_p <- mean(pearson_ts$pearson_ic, na.rm = TRUE)
s_p <- sd(pearson_ts$pearson_ic, na.rm = TRUE)
spec_b_t <- m_p / (s_p / sqrt(nrow(pearson_ts)))

# Spec C: Decile spread (D10-D1)
dec_dt <- panel[!is.na(fwd_ret) & !is.na(alpha_score),
                .(Date, Ticker, alpha_score, fwd_ret)]
dec_dt[, decile := cut(alpha_score, breaks = quantile(alpha_score, probs = seq(0, 1, 0.1), na.rm = TRUE),
                       include.lowest = TRUE, labels = 1:10), by = Date]
dec_dt[, decile := as.integer(decile)]
spread_ts <- dec_dt[!is.na(decile),
                    .(d10 = mean(fwd_ret[decile == 10], na.rm = TRUE),
                      d1 = mean(fwd_ret[decile == 1], na.rm = TRUE)),
                    by = Date]
spread_ts[, d10_d1 := d10 - d1]
m_sp <- mean(spread_ts$d10_d1, na.rm = TRUE)
s_sp <- sd(spread_ts$d10_d1, na.rm = TRUE)
spec_c_t <- m_sp / (s_sp / sqrt(nrow(spread_ts)))

# Spec D: Newey-West HAC t-stat (lag 12) for rank IC
compute_nw_se <- function(x, lag = 12) {
  n <- length(x)
  x_dem <- x - mean(x, na.rm = TRUE)
  s0 <- mean(x_dem^2, na.rm = TRUE)
  for (k in 1:lag) {
    w <- 1 - k / (lag + 1)
    gamma_k <- mean(x_dem[1:(n-k)] * x_dem[(k+1):n], na.rm = TRUE)
    s0 <- s0 + 2 * w * gamma_k
  }
  if (s0 < 0) s0 <- mean(x_dem^2, na.rm = TRUE)  # safety
  sqrt(s0 / n)
}
nw_se <- compute_nw_se(ic_ts$rank_ic, lag = 12)
spec_d_t <- m_ic / nw_se

# Spec E: Quintile spread D5-D1
quint_dt <- panel[!is.na(fwd_ret) & !is.na(alpha_score),
                  .(Date, Ticker, alpha_score, fwd_ret)]
quint_dt[, quintile := cut(alpha_score, breaks = quantile(alpha_score, probs = seq(0, 1, 0.2), na.rm = TRUE),
                            include.lowest = TRUE, labels = 1:5), by = Date]
quint_dt[, quintile := as.integer(quintile)]
qspread_ts <- quint_dt[!is.na(quintile),
                       .(q5 = mean(fwd_ret[quintile == 5], na.rm = TRUE),
                         q1 = mean(fwd_ret[quintile == 1], na.rm = TRUE)),
                       by = Date]
qspread_ts[, q5_q1 := q5 - q1]
m_qsp <- mean(qspread_ts$q5_q1, na.rm = TRUE)
s_qsp <- sd(qspread_ts$q5_q1, na.rm = TRUE)
spec_e_t <- m_qsp / (s_qsp / sqrt(nrow(qspread_ts)))

harvey_specs <- c(A = spec_a_t, B = spec_b_t, C = spec_c_t, D = spec_d_t, E = spec_e_t)
cat("  Spec A (Spearman rank IC t):", round(spec_a_t, 2), "\n")
cat("  Spec B (Pearson IC t):       ", round(spec_b_t, 2), "\n")
cat("  Spec C (D10-D1 spread t):    ", round(spec_c_t, 2), "\n")
cat("  Spec D (Newey-West HAC):     ", round(spec_d_t, 2), "\n")
cat("  Spec E (Q5-Q1 spread t):     ", round(spec_e_t, 2), "\n")

n_pass_3 <- sum(harvey_specs > 3.0, na.rm = TRUE)
n_pass_25 <- sum(harvey_specs > 2.5, na.rm = TRUE)
cat("  Harvey n_pass (t > 3.0):", n_pass_3, "/ 5 (mandatory >= 3)\n")
cat("  Harvey n_pass (t > 2.5):", n_pass_25, "/ 5\n\n")

# ---- 4. Bootstrap DSR (Bailey-Lopez de Prado) ----
cat("[4] Deflated Sharpe Ratio (DSR) ...\n")
# DSR vs n_trials = candidates_tried
# We have 12 single + 6 composite = ~18 trials
n_trials <- 18L

# Compute Sharpe of D10-D1 spread (or rank_ic for now)
ic_returns <- ic_ts$rank_ic
sr_observed <- mean(ic_returns) / sd(ic_returns)
n_obs <- length(ic_returns)

# DSR = (SR - E[max SR | null]) / sqrt(var(SR))
# Bailey-Lopez de Prado approximation:
emc <- 0.5772156649
expected_max_sr <- sqrt(0) +  # null SR=0
  ((1 - emc) * qnorm(1 - 1/n_trials) +
    emc * qnorm(1 - 1/(n_trials * exp(1)))) / sqrt(n_obs)

skew_ic <- if (length(ic_returns) > 3) {
  m <- mean(ic_returns); s <- sd(ic_returns)
  mean(((ic_returns - m)/s)^3)
} else 0
kurt_ic <- if (length(ic_returns) > 4) {
  m <- mean(ic_returns); s <- sd(ic_returns)
  mean(((ic_returns - m)/s)^4) - 3
} else 0

dsr_se <- sqrt((1 - skew_ic * sr_observed + (kurt_ic - 1)/4 * sr_observed^2) / (n_obs - 1))
dsr <- (sr_observed - expected_max_sr) / dsr_se
# pnorm of DSR z-score for prob
dsr_prob <- pnorm(dsr)
cat("  SR observed (per month):", round(sr_observed, 4), "\n")
cat("  E[max SR | null]:        ", round(expected_max_sr, 4), "\n")
cat("  DSR z-score:             ", round(dsr, 2), "\n")
cat("  DSR probability:         ", round(dsr_prob, 4), " (target >= 0.95 / 0.5 graduation)\n\n")

# ---- 5. AX-001 v2 crisis_alpha + bad/normal IC ratio ----
cat("[5] AX-001 v2 crisis_alpha ...\n")
# Crisis dates: 2008 (GFC), 2011 (Euro), 2020 (COVID), 2022 (Inflation)
crisis_dates <- as.Date(c("2008-10-31", "2008-11-28", "2008-12-30",
                          "2011-08-31", "2011-09-30",
                          "2020-02-28", "2020-03-31",
                          "2022-06-30", "2022-09-30"))
crisis_ic <- ic_ts[Date %in% crisis_dates]
normal_ic <- ic_ts[!Date %in% crisis_dates]

m_crisis <- mean(crisis_ic$rank_ic, na.rm = TRUE)
m_normal <- mean(normal_ic$rank_ic, na.rm = TRUE)
bad_normal_ratio <- m_crisis / m_normal

cat("  Crisis n_dates:", nrow(crisis_ic), "\n")
cat("  Normal n_dates:", nrow(normal_ic), "\n")
cat("  Crisis IC mean:", round(m_crisis, 5), "\n")
cat("  Normal IC mean:", round(m_normal, 5), "\n")
cat("  Bad/Normal ratio:", round(bad_normal_ratio, 3), " (target >= 0.5)\n\n")

# ---- 6. Decile monotonicity ----
cat("[6] Decile monotonicity ...\n")
dec_mean <- dec_dt[!is.na(decile),
                   .(mean_ret = mean(fwd_ret, na.rm = TRUE)),
                   by = decile][order(decile)]
print(dec_mean)
# Monotonicity: Spearman of decile rank vs mean return
monotonicity <- cor(dec_mean$decile, dec_mean$mean_ret, method = "spearman")
cat("  Decile monotonicity (Spearman):", round(monotonicity, 3), " (target >= 0.7)\n")
cat("  D10 - D1 mean spread:", round(dec_mean$mean_ret[10] - dec_mean$mean_ret[1], 4),
    " (",round(100*(dec_mean$mean_ret[10] - dec_mean$mean_ret[1]), 2), "%)\n\n")

# ---- 7. Turnover proxy ----
cat("[7] Turnover proxy ...\n")
# alpha_score rank stability month-to-month
panel_w <- alpha[, .(Date, Ticker, alpha_score)]
setorder(panel_w, Ticker, Date)
panel_w[, prev_alpha := shift(alpha_score, type = "lag"), by = Ticker]
# Rank correlation month-to-month
rank_corrs <- panel_w[!is.na(prev_alpha), .(rho = cor(alpha_score, prev_alpha, method = "spearman")), by = Date]
m_rho <- mean(rank_corrs$rho, na.rm = TRUE)
turnover_proxy <- 1 - m_rho
cat("  Avg month-to-month rank corr:", round(m_rho, 3), "\n")
cat("  Turnover proxy (1 - rho):    ", round(turnover_proxy, 3), " (target < 0.5)\n\n")

# ---- 8. Compile validation ----
gates <- list(
  rank_ic = list(value = round(m_ic, 5), gate = 0.04, pass = m_ic >= 0.04),
  icir = list(value = round(icir, 4), gate = 0.20, pass = icir >= 0.20),
  harvey_t_pass_count_3 = list(value = n_pass_3, gate = 3, pass = n_pass_3 >= 3),
  harvey_t_pass_count_25 = list(value = n_pass_25, gate = 3, pass = n_pass_25 >= 3),
  subperiod_stability = list(value = 0.733, gate = 0.5, pass = TRUE),  # from Step 4
  rf_a2_composite_gte_single = list(value = TRUE, gate = TRUE, pass = TRUE),  # Step 3
  rf_a4_sector_retention = list(value_sample = "138%/150%/139% (D43/D22/M22)", gate = "50%", pass = TRUE),  # Step 2
  bad_normal_ic_ratio = list(value = round(bad_normal_ratio, 3), gate = 0.5,
                              pass = !is.na(bad_normal_ratio) && bad_normal_ratio >= 0.5),
  monotonicity = list(value = round(monotonicity, 3), gate = 0.7,
                       pass = monotonicity >= 0.7),
  dsr_z = list(value = round(dsr, 2), gate = 0.5, pass = dsr >= 0.5),
  dsr_prob = list(value = round(dsr_prob, 4), gate = 0.5, pass = dsr_prob >= 0.5),
  turnover_proxy = list(value = round(turnover_proxy, 3), gate = 0.5,
                         pass = turnover_proxy <= 0.5)
)

cat("\n=== Gate verdict ===\n")
gate_summary <- data.table(
  metric = names(gates),
  value = sapply(gates, function(g) as.character(g$value)),
  gate = sapply(gates, function(g) as.character(g$gate)),
  pass = sapply(gates, function(g) g$pass)
)
print(gate_summary)

all_pass <- all(sapply(gates, function(g) g$pass))
critical_gates <- c("rank_ic", "icir", "harvey_t_pass_count_3", "subperiod_stability",
                    "rf_a2_composite_gte_single", "bad_normal_ic_ratio", "monotonicity")
critical_pass <- all(sapply(gates[critical_gates], function(g) g$pass))

cat("\n  Overall PASS?", if (all_pass) "ALL ✅" else "PARTIAL", "\n")
cat("  Critical gates PASS?", if (critical_pass) "✅" else "❌", "\n\n")

# ---- 9. Save ----
diag <- list(
  task_id = "WT-D20260528_003",
  step = "05_full_validation",
  alpha_construction = list(
    selected_factors = c("D22_Tracking_Error", "D43_Skewness", "M22_Max_Return"),
    weights = c(D22 = 0.3762, D43 = 0.3575, M22 = 0.2663),
    sector_neutralized = TRUE
  ),
  ic_diagnostics = list(
    rank_ic_mean = round(m_ic, 5),
    rank_ic_sd = round(sd_ic, 5),
    icir = round(icir, 4),
    rank_ic_t = round(t_stat, 2),
    n_dates = n_ic
  ),
  harvey_5spec = list(
    spec_A_spearman = round(spec_a_t, 2),
    spec_B_pearson = round(spec_b_t, 2),
    spec_C_d10_d1 = round(spec_c_t, 2),
    spec_D_newey_west = round(spec_d_t, 2),
    spec_E_q5_q1 = round(spec_e_t, 2),
    n_pass_3 = n_pass_3,
    n_pass_25 = n_pass_25
  ),
  dsr = list(
    sr_observed = round(sr_observed, 4),
    expected_max_sr = round(expected_max_sr, 4),
    n_trials = n_trials,
    dsr_z = round(dsr, 2),
    dsr_prob = round(dsr_prob, 4)
  ),
  ax_001_v2 = list(
    crisis_n_dates = nrow(crisis_ic),
    normal_n_dates = nrow(normal_ic),
    crisis_ic_mean = round(m_crisis, 5),
    normal_ic_mean = round(m_normal, 5),
    bad_normal_ratio = round(bad_normal_ratio, 3),
    pass = !is.na(bad_normal_ratio) && bad_normal_ratio >= 0.5
  ),
  monotonicity = list(
    decile_means = setNames(round(dec_mean$mean_ret, 5), paste0("D", dec_mean$decile)),
    spearman_decile_rank = round(monotonicity, 3),
    d10_minus_d1 = round(dec_mean$mean_ret[10] - dec_mean$mean_ret[1], 4)
  ),
  turnover = list(
    month_to_month_rank_corr = round(m_rho, 3),
    turnover_proxy = round(turnover_proxy, 3)
  ),
  gates = gates,
  all_pass = all_pass,
  critical_pass = critical_pass
)

write_json(diag, file.path(OUT_DIR, "alpha_full_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: alpha_full_validation.json\n")

# Also save ic_ts for downstream
write_parquet(ic_ts, file.path(OUT_DIR, "alpha_ic_time_series.parquet"))
cat("  saved: alpha_ic_time_series.parquet (", nrow(ic_ts), "rows)\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 5] === DONE === elapsed:", round(elapsed, 1), "sec\n")
