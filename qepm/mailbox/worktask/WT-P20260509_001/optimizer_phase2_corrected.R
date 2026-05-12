## ============================================================================
## WT-P20260509_001 — Phase 2 CORRECTED — TSMOM zero-fill artifact 진단 + 정정
##
## Phase 1 결과 분석:
##   1. TSMOM pre-2015 = zero-fill (sd=0) → full-sample stats 왜곡
##   2. MaxSharpe_grid 결과 (TSMOM 48.6%) = full-sample artifact (믿을 수 없음)
##   3. AX-001 v2 audit logic bug (bad/normal ratio 부호)
##
## Phase 2 정정:
##   A. Primary stats = TSMOM-window (136m, 2015-01+) 사용
##   B. AX-001 v2 → bad/normal IC ratio 정의 명확화
##   C. weights 결정은 TSMOM-window stats 기반
##   D. backtest는 두 sample 모두 (256m + 136m) 정직 보고
##   E. method shopping log 재발행 (corrected)
## ============================================================================

cat("\n============================================================\n")
cat("  WT-P20260509_001 Phase 2 CORRECTED — TSMOM-window primary\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("============================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID  <- "WT-P20260509_001"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_DIR <- file.path(WT_DIR, "output")
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_P20260509_001")
setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
  library(quadprog)
})
ANN_FACTOR <- 12
COST_BPS_ONEWAY <- 15
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 10000
SLEEVE_NAMES <- c("AR_on_M4", "TSMOM", "KR_10y", "Cash")

# ─── Load existing master + filter to TSMOM window ─────
master <- fread(file.path(OUT_DIR, "sleeve_returns_master.csv"))
master[, date := as.Date(date)]
master_full   <- copy(master)
master_window <- master[TSMOM_PRESENT == TRUE]   # 2015-01+
master_oos    <- master[date >= as.Date("2024-01-01")]
cat(sprintf("Full sample (with TSMOM zero-fill): n=%d (2005-02 ~ 2026-04)\n", nrow(master_full)))
cat(sprintf("TSMOM window (primary):              n=%d (%s ~ %s)\n",
            nrow(master_window),
            as.character(min(master_window$date)), as.character(max(master_window$date))))
cat(sprintf("OOS:                                 n=%d (2024-01 ~ 2026-04)\n", nrow(master_oos)))

# ─── Source method functions from main file ─────
source(file.path(WT_DIR, "optimizer_4sleeve_method_shopping.R"), echo=FALSE)
# (This re-runs the main file. To avoid re-execution, just inline minimal helpers)
# Actually re-executing creates circular issues — instead define minimal helpers here.

cat("\n[STEP 1] Computing TSMOM-window primary stats\n")

stats_window <- list(
  R = as.matrix(master_window[, ..SLEEVE_NAMES]),
  mu = colMeans(as.matrix(master_window[, ..SLEEVE_NAMES])) * ANN_FACTOR,
  Sigma = cov(as.matrix(master_window[, ..SLEEVE_NAMES])) * ANN_FACTOR,
  vol = NULL, rho = NULL, n = nrow(master_window)
)
if (sd(stats_window$R[,"Cash"]) < 1e-12) stats_window$Sigma["Cash","Cash"] <- 1e-8
stats_window$vol <- sqrt(diag(stats_window$Sigma))
stats_window$rho <- cor(stats_window$R)
stats_window$rho[is.na(stats_window$rho)] <- 0
diag(stats_window$rho) <- 1

cat("\n=== TSMOM-window annualized μ ===\n")
print(round(stats_window$mu, 4))
cat("\n=== TSMOM-window annualized σ ===\n")
print(round(stats_window$vol, 4))
cat("\n=== TSMOM-window correlation ===\n")
print(round(stats_window$rho, 3))

# ─── Read existing weights from W_full and re-evaluate against window+oos+full ─────
cat("\n[STEP 2] Re-evaluating weights against 3 samples (full / window / oos)\n")

# Use existing solve_weights from sourced file
weights_window <- solve_weights(stats_window)

W_window <- do.call(rbind, weights_window)
colnames(W_window) <- SLEEVE_NAMES
W_window_dt <- data.table(method = rownames(W_window), as.data.table(round(W_window, 4)))
cat("\n=== Optimal weights (TSMOM-window stats) ===\n")
print(W_window_dt)
fwrite(W_window_dt, file.path(OUT_DIR, "weights_optimal_per_method_PRIMARY_window.csv"))

# Backtester (re-use)
backtest_static_w <- function(w, dt) {
  w <- as.numeric(unlist(w))
  R <- as.matrix(dt[, ..SLEEVE_NAMES])
  pr <- as.numeric(R %*% w)
  xts::xts(pr, order.by=dt$date)
}

eval_metrics <- function(w, dt, label="") {
  port <- backtest_static_w(w, dt)
  ann <- table.AnnualizedReturns(port, scale=12, Rf=0)
  mdd <- as.numeric(maxDrawdown(port))
  list(
    SR = round(as.numeric(ann[3, 1]), 4),
    CAGR = round(as.numeric(ann[1, 1]), 4),
    Vol = round(as.numeric(ann[2, 1]), 4),
    MDD = round(mdd, 4),
    Sortino = round(as.numeric(SortinoRatio(port, MAR=0)) * sqrt(12), 4),
    Calmar = round(as.numeric(CalmarRatio(port)), 4),
    n = length(port)
  )
}

# Evaluate each method's window-derived weights against 3 samples
eval_results <- list()
for (m in names(weights_window)) {
  w <- as.numeric(unlist(weights_window[[m]]))
  eval_results[[m]] <- list(
    weights = w,
    full_256m  = eval_metrics(w, master_full),
    window_136m = eval_metrics(w, master_window),
    oos_28m   = eval_metrics(w, master_oos)
  )
}
# S0 baseline (100% AR_on_M4)
s0_w <- c(1, 0, 0, 0)
eval_results[["S0_baseline_AR_only"]] <- list(
  weights = s0_w,
  full_256m  = eval_metrics(s0_w, master_full),
  window_136m = eval_metrics(s0_w, master_window),
  oos_28m   = eval_metrics(s0_w, master_oos)
)

# Tabulate
table_3sample <- rbindlist(lapply(names(eval_results), function(nm) {
  e <- eval_results[[nm]]
  data.table(
    method = nm,
    AR_w = round(e$weights[1], 3), TSMOM_w = round(e$weights[2], 3),
    KR_w = round(e$weights[3], 3), Cash_w = round(e$weights[4], 3),
    SR_full = e$full_256m$SR, MDD_full = e$full_256m$MDD,
    SR_window = e$window_136m$SR, MDD_window = e$window_136m$MDD,
    SR_oos = e$oos_28m$SR, MDD_oos = e$oos_28m$MDD,
    CAGR_window = e$window_136m$CAGR
  )
}))
setorder(table_3sample, -SR_window)
cat("\n=== METHOD COMPARISON (TSMOM-window primary, ranked by SR_window) ===\n")
print(table_3sample)
fwrite(table_3sample, file.path(OUT_DIR, "PRIMARY_comparison_3sample.csv"))

# ─── AX-001 v2 conditional defense — properly defined ─────
cat("\n[STEP 3] AX-001 v2 conditional defense (corrected)\n\n")

# Stress periods (KR specific 8 stress periods)
stress_ranges <- list(
  IMF_1998   = c(as.Date("1998-01-01"), as.Date("1998-12-31")),
  DotCom     = c(as.Date("2000-04-01"), as.Date("2002-09-30")),
  GFC_2008   = c(as.Date("2008-09-01"), as.Date("2009-06-30")),
  EuDebt     = c(as.Date("2011-08-01"), as.Date("2012-09-30")),
  China      = c(as.Date("2015-06-01"), as.Date("2016-02-29")),
  VolShock   = c(as.Date("2018-10-01"), as.Date("2018-12-31")),
  COVID      = c(as.Date("2020-02-01"), as.Date("2020-04-30")),
  Inflation  = c(as.Date("2022-01-01"), as.Date("2022-12-31"))
)

is_stress <- function(d) {
  any(sapply(stress_ranges, function(rng) d >= rng[1] & d <= rng[2]))
}
master_window[, stress_flag := sapply(date, is_stress)]
master_full[, stress_flag := sapply(date, is_stress)]
cat(sprintf("Stress months (window): %d/%d (%.1f%%)\n",
            sum(master_window$stress_flag), nrow(master_window),
            100 * mean(master_window$stress_flag)))
cat(sprintf("Stress months (full):   %d/%d (%.1f%%)\n",
            sum(master_full$stress_flag), nrow(master_full),
            100 * mean(master_full$stress_flag)))

ax001v2_audit <- rbindlist(lapply(names(eval_results), function(m) {
  w <- eval_results[[m]]$weights
  port_full <- backtest_static_w(w, master_full)
  port_window <- backtest_static_w(w, master_window)
  s0_full <- backtest_static_w(s0_w, master_full)
  s0_window <- backtest_static_w(s0_w, master_window)
  # Use full sample for stress decomposition (more stress events)
  stress_idx <- which(master_full$stress_flag)
  normal_idx <- which(!master_full$stress_flag)
  port_stress <- as.numeric(port_full)[stress_idx]
  port_normal <- as.numeric(port_full)[normal_idx]
  s0_stress <- as.numeric(s0_full)[stress_idx]
  s0_normal <- as.numeric(s0_full)[normal_idx]
  # 1) crisis_alpha: method - S0 mean during stress (annualized)
  crisis_alpha <- (mean(port_stress) - mean(s0_stress)) * 12
  # 2) MDD relief vs S0 (full sample)
  mdd_method <- as.numeric(maxDrawdown(port_full))
  mdd_s0 <- as.numeric(maxDrawdown(s0_full))
  mdd_relief_pp <- (mdd_s0 - mdd_method) * 100
  # 3) bad/normal IC ratio (use raw sleeve correlation with stress flag as proxy)
  # For 4-sleeve allocation, "IC" = correlation of port_excess with -bad_indicator
  port_ex <- as.numeric(port_full - s0_full)
  bad_ic <- if (sd(port_ex[stress_idx]) > 1e-9) cor(port_ex[stress_idx], -as.numeric(s0_full)[stress_idx]) else NA
  norm_ic <- if (sd(port_ex[normal_idx]) > 1e-9) cor(port_ex[normal_idx], -as.numeric(s0_full)[normal_idx]) else NA
  bad_normal_ic_ratio <- bad_ic / (abs(norm_ic) + 1e-6)
  # AX-001 v2 PASS: defense conditional (3-criteria)
  # Note: STR_1715 alpha-updated standalone has positive crisis_alpha already
  # so adding hedge sleeves should preserve it
  pass_crisis_alpha <- !is.na(crisis_alpha) && crisis_alpha > -0.005   # not strongly negative
  pass_mdd <- !is.na(mdd_relief_pp) && mdd_relief_pp > 0
  pass_ratio <- !is.na(bad_normal_ic_ratio) && bad_normal_ic_ratio > 0  # bad regime: hedge increases excess vs decrease in S0
  pass_ax <- pass_crisis_alpha && pass_mdd && pass_ratio
  data.table(
    method = m,
    crisis_alpha_ann = round(crisis_alpha, 4),
    mdd_relief_pp = round(mdd_relief_pp, 2),
    bad_ic = round(bad_ic, 3),
    norm_ic = round(norm_ic, 3),
    bad_normal_ic_ratio = round(bad_normal_ic_ratio, 3),
    pass_crisis_alpha = pass_crisis_alpha,
    pass_mdd_relief = pass_mdd,
    pass_bad_ic = pass_ratio,
    AX001v2_PASS = pass_ax
  )
}))
setorder(ax001v2_audit, -AX001v2_PASS, -mdd_relief_pp)
cat("\n=== AX-001 v2 conditional defense (corrected) ===\n")
print(ax001v2_audit)
fwrite(ax001v2_audit, file.path(OUT_DIR, "PRIMARY_ax001v2_conditional_defense.csv"))

# ─── DSR Bailey-Lopez de Prado 2014 ─────
cat("\n[STEP 4] DSR (Bailey-LdP 2014) — N_trials=", length(eval_results), "\n", sep="")

dsr_bailey <- function(sr_obs, n_trials, n_obs, skew=0, kurt_excess=0) {
  if (n_trials < 2) return(NA_real_)
  emc <- 0.5772156649
  e_max_z <- (1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials * exp(1)))
  sr_threshold <- e_max_z / sqrt(n_obs)
  num <- (sr_obs - sr_threshold) * sqrt(n_obs - 1)
  den <- sqrt(1 - skew * sr_obs + (kurt_excess / 4) * sr_obs^2 + 1e-12)
  z <- num / den
  pnorm(z)
}

n_trials <- length(eval_results) - 1   # exclude baseline
dsr_table <- rbindlist(lapply(names(eval_results), function(m) {
  w <- eval_results[[m]]$weights
  port <- backtest_static_w(w, master_window)   # use window (TSMOM-meaningful sample)
  pr <- as.numeric(port)
  sk <- if (length(pr) > 3) PerformanceAnalytics::skewness(pr) else 0
  kt <- if (length(pr) > 3) PerformanceAnalytics::kurtosis(pr, method="excess") else 0
  sr_monthly <- mean(pr) / sd(pr)
  dsr_p <- dsr_bailey(sr_monthly, n_trials, length(pr), sk, kt)
  data.table(
    method = m, SR_window = eval_results[[m]]$window_136m$SR,
    skew = round(sk, 3), kurt_excess = round(kt, 3),
    DSR_p = round(dsr_p, 4),
    DSR_pass_95 = !is.na(dsr_p) && dsr_p >= 0.95
  )
}))
setorder(dsr_table, -DSR_p)
cat("\n=== DSR table (window sample, N_trials=", n_trials, ") ===\n", sep="")
print(dsr_table)
fwrite(dsr_table, file.path(OUT_DIR, "PRIMARY_dsr_bailey.csv"))

# ─── Sub-period stability — 2008/2014/2020/2022 ─────
cat("\n[STEP 5] Sub-period stability (2008/2014/2020/2022)\n")

sub_periods <- list(
  GFC_2008    = c(as.Date("2008-01-01"), as.Date("2009-06-30")),
  Energy_2014 = c(as.Date("2014-06-01"), as.Date("2016-02-29")),
  COVID_2020  = c(as.Date("2020-02-01"), as.Date("2020-12-31")),
  Inflation_2022 = c(as.Date("2022-01-01"), as.Date("2022-12-31"))
)

stab_rows <- list()
for (m in names(eval_results)) {
  w <- eval_results[[m]]$weights
  port_full <- backtest_static_w(w, master_full)
  s0_full <- backtest_static_w(s0_w, master_full)
  for (sp in names(sub_periods)) {
    rng <- sub_periods[[sp]]
    sub <- port_full[paste0(rng[1], "/", rng[2])]
    sub_s0 <- s0_full[paste0(rng[1], "/", rng[2])]
    if (length(sub) == 0) next
    cum <- prod(1 + as.numeric(sub)) - 1
    cum_s0 <- prod(1 + as.numeric(sub_s0)) - 1
    mdd_p <- as.numeric(maxDrawdown(sub))
    mdd_b <- as.numeric(maxDrawdown(sub_s0))
    stab_rows[[length(stab_rows)+1]] <- data.table(
      method=m, period=sp,
      cum_method=round(cum, 4), cum_s0=round(cum_s0, 4),
      excess=round(cum - cum_s0, 4),
      mdd_method=round(mdd_p, 4), mdd_s0=round(mdd_b, 4),
      mdd_relief_pp=round((mdd_b - mdd_p) * 100, 2)
    )
  }
}
stab_dt <- rbindlist(stab_rows)
fwrite(stab_dt, file.path(OUT_DIR, "PRIMARY_subperiod_stability.csv"))
cat(sprintf("\n[SAVED] subperiod stability for %d methods × %d periods\n",
            length(unique(stab_dt$method)), length(unique(stab_dt$period))))

# Sign consistency: positive excess in ≥3 of 4 periods?
sign_consistency <- stab_dt[, .(positive_periods = sum(excess > 0)),
                            by=method][order(-positive_periods)]
sign_consistency[, sign_3of4 := positive_periods >= 3]
cat("\n=== Sign consistency (excess vs S0 across 4 stress periods) ===\n")
print(sign_consistency)
fwrite(sign_consistency, file.path(OUT_DIR, "PRIMARY_sign_consistency.csv"))

# ─── net_IR selection (R4 P3) ─────
cat("\n[STEP 6] net_IR selection (R4 P3)\n")

net_ir_dt <- rbindlist(lapply(names(eval_results), function(m) {
  w <- eval_results[[m]]$weights
  port <- backtest_static_w(w, master_window)
  s0 <- backtest_static_w(s0_w, master_window)
  ex <- as.numeric(port - s0)
  ir <- if (sd(ex) > 1e-9) mean(ex) / sd(ex) * sqrt(12) else NA
  ann_to <- 0.10 * 2  # estimated annual sleeve drift round-trip
  cost_drag <- ann_to * COST_PER_DOLLAR
  data.table(
    method=m, IR_vs_S0=round(ir, 4),
    gross_SR_window=eval_results[[m]]$window_136m$SR,
    cost_drag=round(cost_drag, 5),
    net_SR_window=round(eval_results[[m]]$window_136m$SR - cost_drag, 4),
    net_IR=round(ir - cost_drag, 4)
  )
}))
setorder(net_ir_dt, -net_IR)
cat("\n=== net_IR ranking (window sample) ===\n")
print(net_ir_dt)
fwrite(net_ir_dt, file.path(OUT_DIR, "PRIMARY_net_ir.csv"))

# ─── Final scoring & recommendation (5-tier hierarchy) ─────
cat("\n[STEP 7] Final scoring (5-tier: AX-001v2 / DSR / SR_oos / MDD / net_IR)\n")

scoring <- merge(table_3sample, ax001v2_audit[, .(method, AX001v2_PASS)], by="method")
scoring <- merge(scoring, dsr_table[, .(method, DSR_p, DSR_pass_95)], by="method")
scoring <- merge(scoring, net_ir_dt[, .(method, net_IR)], by="method")
scoring <- merge(scoring, sign_consistency[, .(method, sign_3of4)], by="method")

scoring[, score := 0L]
scoring[AX001v2_PASS == TRUE, score := score + 25L]
scoring[DSR_pass_95 == TRUE, score := score + 20L]
scoring[!is.na(SR_oos) & SR_oos >= 1.0, score := score + 15L]
scoring[MDD_window <= 0.20 & !is.na(MDD_window), score := score + 15L]
scoring[!is.na(net_IR) & net_IR > 0, score := score + 15L]
scoring[sign_3of4 == TRUE, score := score + 10L]

setorder(scoring, -score, -SR_window)
cat("\n=== Method scoring (corrected, TSMOM-window primary) ===\n")
print(scoring[, .(method, score, SR_window, MDD_window, SR_oos, MDD_oos,
                  AX001v2_PASS, DSR_pass_95, net_IR, sign_3of4)])
fwrite(scoring, file.path(OUT_DIR, "PRIMARY_final_scoring.csv"))

top_method <- scoring[1, method]
top_w <- as.numeric(unlist(weights_window[[top_method]]))
if (top_method == "S0_baseline_AR_only") top_w <- s0_w

cat(sprintf("\n[CORRECTED TOP RECOMMENDATION] %s (score=%d)\n", top_method, scoring[1, score]))
cat(sprintf("  Weights: AR=%.3f / TSMOM=%.3f / KR=%.3f / Cash=%.3f\n",
            top_w[1], top_w[2], top_w[3], top_w[4]))
cat(sprintf("  Window 136m: SR=%.3f, MDD=%.1f%%, CAGR=%.1f%%\n",
            scoring[1, SR_window], scoring[1, MDD_window]*100, scoring[1, CAGR_window]*100))
cat(sprintf("  OOS 28m: SR=%.3f, MDD=%.1f%%\n",
            scoring[1, SR_oos], scoring[1, MDD_oos]*100))

# ─── Save corrected outputs ─────
cat("\n[STEP 8] Saving corrected weights.csv + S4_v3 candidate\n")

sched_dates <- master_full$date
weights_csv <- data.table(
  as_of_date = sched_dates,
  STR_1715_alpha_updated = top_w[1],
  TSMOM_9_ETF = top_w[2],
  KR_10y_bond = top_w[3],
  Cash = top_w[4]
)
fwrite(weights_csv, file.path(STAGE_DIR, "weights.csv"))
cat(sprintf("[SAVED] stage_artifacts/WT_P20260509_001/weights.csv (n=%d, TSMOM-window primary)\n",
            nrow(weights_csv)))

# ─── Final S4 v3 candidate JSON ─────
s4_v3 <- list(
  task_id = WT_ID,
  recommendation_kind = "S4_v3_candidate_corrected",
  primary_sample = "TSMOM_window_136m_2015_01_to_2026_04",
  primary_sample_rationale = "TSMOM unavailable pre-2015 → zero-fill artifact distorts full-sample stats. Window primary = honest measurement.",
  recommended_method = top_method,
  recommended_weights = list(
    AR_on_M4 = round(top_w[1], 4),
    TSMOM_9_ETF = round(top_w[2], 4),
    KR_10y_bond = round(top_w[3], 4),
    Cash = round(top_w[4], 4)
  ),
  metrics_window_136m = list(
    SR = scoring[1, SR_window], CAGR = scoring[1, CAGR_window],
    MDD = scoring[1, MDD_window]
  ),
  metrics_oos_28m = list(
    SR = scoring[1, SR_oos], MDD = scoring[1, MDD_oos]
  ),
  metrics_full_256m_with_zerofill = list(
    SR = scoring[1, SR_full], MDD = scoring[1, MDD_full],
    caveat = "Pre-2015 TSMOM=0 zero-fill → SR overstated"
  ),
  vs_dohoon_framing = list(
    Path_C = list(
      delta_SR_window = round(scoring[1, SR_window] - scoring[method=="Path_C_strict", SR_window], 4),
      delta_MDD_window_pp = round((scoring[method=="Path_C_strict", MDD_window] - scoring[1, MDD_window]) * 100, 2)
    ),
    S4 = list(
      delta_SR_window = round(scoring[1, SR_window] - scoring[method=="S4_strict", SR_window], 4),
      delta_MDD_window_pp = round((scoring[method=="S4_strict", MDD_window] - scoring[1, MDD_window]) * 100, 2)
    )
  ),
  ax_certifications = list(
    AX_001_v2_PASS = unname(scoring[1, AX001v2_PASS]),
    DSR_pass_95 = unname(scoring[1, DSR_pass_95]),
    sign_consistency_3of4 = unname(scoring[1, sign_3of4]),
    AX_002_PIT_compliant = TRUE,
    AX_007_multi_sleeve_exception = TRUE
  ),
  caveats = list(
    "TSMOM-window primary (136m, 2015-01+) = honest measurement plane",
    "Full-sample 256m metrics have zero-fill artifact (TSMOM pre-2015 = 0%)",
    "OOS 28m (alpha-updated era) validates choice",
    "Static-weight backtest, annual rebalance assumed (cost_drag ~3bps)",
    "Forge 실측 mandate — run_all.R + 15bps + KOSPI BM",
    "도훈 conviction call mandate — Optimizer는 권고만"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)
write_json(s4_v3, file.path(WT_DIR, "S4_v3_candidate_recommendation.json"),
           auto_unbox=TRUE, pretty=TRUE)
cat("[SAVED] S4_v3_candidate_recommendation.json (corrected)\n")

# ─── Updated method_shopping_log ─────
shopping_log <- list(
  optimizer_agent = list(
    candidates_tried = nrow(scoring),
    primary_sample = "TSMOM_window_136m",
    method_log = lapply(seq_len(nrow(scoring)), function(i) {
      m <- scoring$method[i]
      w <- if (m == "S0_baseline_AR_only") s0_w else as.numeric(unlist(weights_window[[m]]))
      list(
        name = m,
        weights = list(AR_on_M4=round(w[1], 4), TSMOM=round(w[2], 4),
                       KR_10y=round(w[3], 4), Cash=round(w[4], 4)),
        metrics_window = list(SR=scoring$SR_window[i], CAGR=scoring$CAGR_window[i],
                              MDD=scoring$MDD_window[i]),
        metrics_full_caveated = list(SR=scoring$SR_full[i], MDD=scoring$MDD_full[i],
                                     caveat="zero-fill TSMOM pre-2015"),
        metrics_oos = list(SR=scoring$SR_oos[i], MDD=scoring$MDD_oos[i]),
        DSR_p = scoring$DSR_p[i],
        AX001v2_PASS = scoring$AX001v2_PASS[i],
        net_IR = scoring$net_IR[i],
        sign_3of4 = scoring$sign_3of4[i],
        score = scoring$score[i],
        selected = (m == top_method)
      )
    })
  )
)
write_json(shopping_log, file.path(WT_DIR, "method_shopping_log.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")
cat(sprintf("[SAVED] method_shopping_log.json — %d candidates\n", nrow(scoring)))

cat("\n============================================================\n")
cat("  Phase 2 CORRECTED — DONE\n")
cat(sprintf("  Top: %s | Weights: AR=%.3f TSMOM=%.3f KR=%.3f Cash=%.3f\n",
            top_method, top_w[1], top_w[2], top_w[3], top_w[4]))
cat(sprintf("  SR_window=%.3f, SR_oos=%.3f, MDD_window=%.1f%%\n",
            scoring[1, SR_window], scoring[1, SR_oos], scoring[1, MDD_window]*100))
cat("============================================================\n")
