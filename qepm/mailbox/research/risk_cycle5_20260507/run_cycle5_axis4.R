# =============================================================================
# Cycle 5 — Axis 4: Signal decay simulation
# =============================================================================
# 1) AR threshold overlay (K=5/W=252/q70=0.4172/q90=0.4502) 시간 안정성
# 2) TSMOM 12개월 lookback signal Sharpe forward decay
# 3) KR_10y bond ETF carry yield 시계열 trend
# 4) 12m horizon signal decay > 30% 발동 확률
#
# Methodology:
# - Hwang-Rubesam (2024 working) — anomaly decay rate 측정 framework
# - Stambaugh-Yu-Yuan 2015 RFS — anomaly attenuation post-publication
# - SR_t Markov reversion model (Bailey-Lopez de Prado 2014 — DSR)
# - Rolling SR + change-point detection (Pettitt 1979)
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

# ---- 2. Rolling SR by source (24m, 36m, 60m windows) ----
roll_sr <- function(x, k) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in k:n) {
    win <- x[(i - k + 1L):i]
    if (sd(win, na.rm = TRUE) == 0) next
    out[i] <- (mean(win, na.rm = TRUE) * 12) / (sd(win, na.rm = TRUE) * sqrt(12))
  }
  out
}

post2015[, sr24m_AR := roll_sr(r_AR, 24L)]
post2015[, sr36m_AR := roll_sr(r_AR, 36L)]
post2015[, sr60m_AR := roll_sr(r_AR, 60L)]

post2015[, sr24m_TSMOM := roll_sr(r_TSMOM, 24L)]
post2015[, sr36m_TSMOM := roll_sr(r_TSMOM, 36L)]
post2015[, sr60m_TSMOM := roll_sr(r_TSMOM, 60L)]

post2015[, sr24m_KR10y := roll_sr(r_KR10y, 24L)]
post2015[, sr36m_KR10y := roll_sr(r_KR10y, 36L)]
post2015[, sr60m_KR10y := roll_sr(r_KR10y, 60L)]

# Hybrid 70/15/15 SR rolling
post2015[, r_Hybrid := 0.70 * r_AR + 0.15 * r_TSMOM + 0.15 * r_KR10y]
post2015[, sr24m_Hybrid := roll_sr(r_Hybrid, 24L)]
post2015[, sr36m_Hybrid := roll_sr(r_Hybrid, 36L)]
post2015[, sr60m_Hybrid := roll_sr(r_Hybrid, 60L)]

# Recent SR snapshot
recent_sr <- post2015[!is.na(sr60m_AR)][.N, .(
  ym, sr24m_AR, sr36m_AR, sr60m_AR,
  sr24m_TSMOM, sr36m_TSMOM, sr60m_TSMOM,
  sr24m_KR10y, sr36m_KR10y, sr60m_KR10y,
  sr24m_Hybrid, sr36m_Hybrid, sr60m_Hybrid
)]
cat("Recent SR snapshot:\n")
print(t(recent_sr))

# ---- 3. SR linear trend (Mann-Kendall) ----
mk_trend <- function(x) {
  x_clean <- x[!is.na(x)]
  if (length(x_clean) < 10L) return(list(tau = NA, p_value = NA))
  test <- tryCatch({
    if (requireNamespace("Kendall", quietly = TRUE)) {
      Kendall::MannKendall(x_clean)
    } else {
      cor.test(seq_along(x_clean), x_clean, method = "kendall")
    }
  }, error = function(e) NULL)
  if (is.null(test)) return(list(tau = NA, p_value = NA))
  if (inherits(test, "Kendall") || !is.null(test$tau)) {
    return(list(tau = as.numeric(test$tau), p_value = as.numeric(test$sl)))
  } else {
    return(list(tau = as.numeric(test$estimate), p_value = test$p.value))
  }
}

mk_results <- list()
for (sname in c("AR", "TSMOM", "KR10y", "Hybrid")) {
  for (k in c("24m", "36m", "60m")) {
    col <- paste0("sr", k, "_", sname)
    if (col %in% names(post2015)) {
      mk <- mk_trend(post2015[[col]])
      mk_results[[paste0(sname, "_", k)]] <- list(
        source = sname, window = k, tau = mk$tau, p_value = mk$p_value
      )
    }
  }
}
mk_dt <- rbindlist(lapply(mk_results, function(r) {
  data.table(source = r$source, window = r$window,
             kendall_tau = r$tau, p_value = r$p_value)
}))
fwrite(mk_dt, file.path(hybrid_dir, "axis4_mk_trend_test.csv"))
cat("\nMann-Kendall trend test (rolling SR):\n")
print(mk_dt)

# ---- 4. AR threshold overlay K=5/W=252 stability ----
# 사이클 4 inheritance: q70=0.4172, q90=0.4502
# Forward simulation: STR_1715_AR threshold values forward stability
# Actual implementation: rolling 252-day quantile of AR ranking signal
# Since we have monthly returns only, we proxy via:
#   monthly r_AR series → k-step (k=5) ranking percentile threshold

# 단순화: AR contribution rolling concentration (mctv proxy)
# 사이클 3 reported mctv_AR 0.987~1.001 → AR가 거의 전부 contribute
# Forward simulation: w_AR=0.70 가정 시 var contribution 동적 변화

# Compute rolling MCTV (marginal contribution to volatility) for AR in Hybrid
roll_mctv_AR <- function(r_AR, r_Hyb, w_AR, k = 36L) {
  n <- length(r_AR)
  out <- rep(NA_real_, n)
  for (i in k:n) {
    a <- r_AR[(i - k + 1L):i]
    h <- r_Hyb[(i - k + 1L):i]
    # MCTV_AR = w_AR × cov(r_AR, r_Hyb) / var(r_Hyb)
    out[i] <- w_AR * cov(a, h) / var(h)
  }
  out
}

post2015[, mctv_AR_36m := roll_mctv_AR(r_AR, r_Hybrid, 0.70, 36L)]
post2015[, mctv_AR_60m := roll_mctv_AR(r_AR, r_Hybrid, 0.70, 60L)]

mctv_recent <- post2015[!is.na(mctv_AR_60m)][.N, .(ym, mctv_AR_36m, mctv_AR_60m)]
cat("\nRecent MCTV_AR:\n")
print(mctv_recent)

# ---- 5. TSMOM SR forward decay scenarios ----
# Stambaugh-Yu-Yuan 2015 RFS: published anomalies decay 30~50% post-publication
# TSMOM published 2012 (Moskowitz-Ooi-Pedersen) → 14y elapsed
# Hybrid 70/15/15 6/1 발효 시점 보수적 가정: TSMOM 12m forward decay rate ∈ [10%, 30%]
# Note: 사이클 5 axis 3 inheritance: optimistic 5% / neutral 15% / Stambaugh 30% / pessimistic 50%

sr_TSMOM_full <- mean(post2015$r_TSMOM) * 12 / (sd(post2015$r_TSMOM) * sqrt(12))
sr_AR_full <- mean(post2015$r_AR) * 12 / (sd(post2015$r_AR) * sqrt(12))
sr_KR10y_full <- mean(post2015$r_KR10y) * 12 / (sd(post2015$r_KR10y) * sqrt(12))

cat(sprintf("\nFull-sample SR (post-2015):\n"))
cat(sprintf("  AR:    %.4f\n", sr_AR_full))
cat(sprintf("  TSMOM: %.4f\n", sr_TSMOM_full))
cat(sprintf("  KR10y: %.4f\n", sr_KR10y_full))

# Decay scenarios (annualized rate)
decay_scenarios <- data.table(
  scenario = c("optimistic", "neutral", "Stambaugh_2015", "pessimistic"),
  annual_decay_AR = c(0.02, 0.10, 0.20, 0.40),
  annual_decay_TSMOM = c(0.05, 0.15, 0.30, 0.50),
  annual_decay_KR10y = c(0.01, 0.05, 0.10, 0.20)
)

# 12m forward SR decay
decay_scenarios[, sr_AR_h12m := sr_AR_full * (1 - annual_decay_AR)]
decay_scenarios[, sr_TSMOM_h12m := sr_TSMOM_full * (1 - annual_decay_TSMOM)]
decay_scenarios[, sr_KR10y_h12m := sr_KR10y_full * (1 - annual_decay_KR10y)]

# 24m forward SR decay (compounding)
decay_scenarios[, sr_AR_h24m := sr_AR_full * (1 - annual_decay_AR)^2]
decay_scenarios[, sr_TSMOM_h24m := sr_TSMOM_full * (1 - annual_decay_TSMOM)^2]
decay_scenarios[, sr_KR10y_h24m := sr_KR10y_full * (1 - annual_decay_KR10y)^2]

# Hybrid SR estimate: dominated by AR (mctv ~0.987 사이클 3 inheritance)
# Approximation: SR_Hybrid_h12m ≈ Σ w_i × SR_i × correction
# Simplified linear: ΔSR_Hybrid ≈ Σ w_i × ΔSR_i
# Correction for correlation 무시 (보수)
sr_Hybrid_baseline <- 1.5070  # post-2015 sub-sample

# Actually use 256m baseline 1.665 (L-284 PerformanceAnalytics convention)
# But decay rate is per source SR, not Hybrid SR direct
# Hybrid SR_h12m estimate via weighted SR linear approximation
decay_scenarios[, sr_Hybrid_h12m := 1.665 * (
  0.70 * (1 - annual_decay_AR) +
  0.15 * (1 - annual_decay_TSMOM) +
  0.15 * (1 - annual_decay_KR10y)
)]
decay_scenarios[, sr_Hybrid_h24m := 1.665 * (
  0.70 * (1 - annual_decay_AR)^2 +
  0.15 * (1 - annual_decay_TSMOM)^2 +
  0.15 * (1 - annual_decay_KR10y)^2
)]

# decay > 30% trigger probability (12m horizon)
decay_scenarios[, hybrid_decay_pct_h12m := (1.665 - sr_Hybrid_h12m) / 1.665]
decay_scenarios[, hybrid_decay_gt_30_pct := hybrid_decay_pct_h12m > 0.30]

fwrite(decay_scenarios, file.path(hybrid_dir, "axis4_signal_decay_scenarios.csv"))
cat("\nSignal decay scenarios:\n")
print(decay_scenarios)

# ---- 6. KR_10y carry yield trend ----
# Recent 24m KR10y monthly mean (proxy for carry yield)
kr10y_recent_24m <- tail(post2015$r_KR10y, 24L)
kr10y_carry_recent_ann <- mean(kr10y_recent_24m) * 12
kr10y_carry_full_ann <- mean(post2015$r_KR10y) * 12

cat(sprintf("\nKR10y carry yield (annualized):\n"))
cat(sprintf("  Full sample (post-2015):  %.4f\n", kr10y_carry_full_ann))
cat(sprintf("  Recent 24m:               %.4f\n", kr10y_carry_recent_ann))

# Trend test
kr10y_trend <- mk_trend(post2015$r_KR10y)
cat(sprintf("  Mann-Kendall tau:         %.4f (p=%.4f)\n",
            kr10y_trend$tau, kr10y_trend$p_value))

# ---- 7. SR change-point detection (Pettitt 1979) ----
pettitt_test <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 20L) return(list(k_index = NA, k_stat = NA, p_value = NA))
  k_stats <- numeric(n - 1L)
  for (k in 1:(n - 1L)) {
    s_k <- 0
    for (i in 1:k) {
      for (j in (k + 1L):n) {
        s_k <- s_k + sign(x[j] - x[i])
      }
    }
    k_stats[k] <- abs(s_k)
  }
  k_max <- which.max(k_stats)
  K <- max(k_stats)
  p <- 2 * exp(-6 * K^2 / (n^3 + n^2))
  list(k_index = k_max, k_stat = K, p_value = min(1, p))
}

pettitt_results <- list()
for (sname in c("AR", "TSMOM", "KR10y", "Hybrid")) {
  col <- paste0("sr36m_", sname)
  pet <- pettitt_test(post2015[[col]])
  pettitt_results[[sname]] <- list(
    source = sname, k_index = pet$k_index, k_stat = pet$k_stat, p_value = pet$p_value
  )
}
pettitt_dt <- rbindlist(lapply(pettitt_results, function(r) {
  data.table(source = r$source, k_index = r$k_index, k_stat = r$k_stat, p_value = r$p_value)
}))
fwrite(pettitt_dt, file.path(hybrid_dir, "axis4_pettitt_changepoint.csv"))
cat("\nPettitt change-point test (rolling 36m SR):\n")
print(pettitt_dt)

# ---- 8. Save Axis 4 summary ----
axis4_summary <- list(
  axis = "axis_4_signal_decay_forward",
  rolling_sr_recent = as.list(recent_sr),
  mctv_recent = as.list(mctv_recent),
  full_sample_sr = list(
    AR = sr_AR_full,
    TSMOM = sr_TSMOM_full,
    KR10y = sr_KR10y_full,
    Hybrid_post2015 = 1.5070,
    Hybrid_256m_l284 = 1.665
  ),
  mann_kendall_csv = "axis4_mk_trend_test.csv",
  pettitt_csv = "axis4_pettitt_changepoint.csv",
  decay_scenarios_csv = "axis4_signal_decay_scenarios.csv",
  kr10y_carry = list(
    full_ann = kr10y_carry_full_ann,
    recent_24m_ann = kr10y_carry_recent_ann,
    mk_tau = kr10y_trend$tau,
    mk_p_value = kr10y_trend$p_value
  ),
  decay_30pct_trigger = list(
    optimistic = decay_scenarios[scenario == "optimistic"]$hybrid_decay_gt_30_pct,
    neutral = decay_scenarios[scenario == "neutral"]$hybrid_decay_gt_30_pct,
    Stambaugh_2015 = decay_scenarios[scenario == "Stambaugh_2015"]$hybrid_decay_gt_30_pct,
    pessimistic = decay_scenarios[scenario == "pessimistic"]$hybrid_decay_gt_30_pct
  ),
  alert_thresholds = list(
    sr_decay_warning_pct = 0.30,
    sr_decay_critical_pct = 0.50,
    rolling_sr_window = "36m or 60m",
    mk_p_threshold = 0.05,
    rationale = "Hwang-Rubesam 2024 + Stambaugh 2015 standard"
  ),
  citations = c(
    "Hwang-Rubesam 2024 working (momentum decay rate)",
    "Stambaugh-Yu-Yuan 2015 RFS (anomaly attenuation)",
    "Bailey-Lopez de Prado 2014 JPM (DSR)",
    "Pettitt 1979 (change-point detection)",
    "Moskowitz-Ooi-Pedersen 2012 JFE (TSMOM 12m)"
  )
)

write_json(axis4_summary, file.path(hybrid_dir, "axis4_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Axis 4] DONE\n")
