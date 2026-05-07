# =============================================================================
# Cycle 5 — Axis 3: Crowding evolution forward simulation
# =============================================================================
# 1) 현 admit 3-source pairwise correlation forward projection (DCC-GARCH 1-step
#    forecast + simulation)
# 2) TSMOM = KR market momentum factor (참여자 다수). 시간 따른 crowding intensity
# 3) 6/12/24개월 horizon crowding evolution 시나리오
# 4) Position-level capacity (ADV breach) forward simulation
#
# Methodology:
# - DCC-GARCH(1,1) (Engle 2002 JBES) — 사이클 4 inheritance, 정합 path
# - Crowding intensity proxy: pairwise corr 절대값 평균 + 상위 1 quantile cor
# - TSMOM 12m signal autocorrelation forward decay
# - Stambaugh-Yu-Yuan 2015 RFS — anomaly attenuation with publication
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

# 3-source admit
ret_3src <- post2015[, .(r_AR, r_TSMOM, r_KR10y)]
n_obs <- nrow(ret_3src)
cat("3-source post-2015 sample:", n_obs, "\n")

# ---- 2. Static + 12m rolling pairwise correlation history ----
# Time-varying correlation track 측정
roll_corr_12m <- function(x, y, k = 12L) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in k:n) {
    out[i] <- cor(x[(i - k + 1L):i], y[(i - k + 1L):i])
  }
  out
}

post2015[, cor12m_AR_TSMOM := roll_corr_12m(r_AR, r_TSMOM, 12L)]
post2015[, cor12m_AR_KR10y := roll_corr_12m(r_AR, r_KR10y, 12L)]
post2015[, cor12m_TSMOM_KR10y := roll_corr_12m(r_TSMOM, r_KR10y, 12L)]

# Static (post-2015 full sample)
static_cor <- cor(ret_3src)
cat("\nStatic (post-2015) 3-source pairwise cor:\n")
print(static_cor)

# Recent 12m rolling cor (last 12 months)
recent_cor_12m <- post2015[!is.na(cor12m_AR_TSMOM)][.N, .(
  cor12m_AR_TSMOM, cor12m_AR_KR10y, cor12m_TSMOM_KR10y
)]
cat("\nRecent 12m rolling cor (latest):\n")
print(recent_cor_12m)

# ---- 3. DCC-GARCH(1,1) dynamic correlation forecast ----
# 사이클 4 axis 2 inheritance. DCC fit + 12-step forward simulation
have_rmgarch <- requireNamespace("rmgarch", quietly = TRUE) && requireNamespace("rugarch", quietly = TRUE)
cat("\nrmgarch available:", have_rmgarch, "\n")

dcc_results <- NULL

if (have_rmgarch) {
  library(rugarch)
  library(rmgarch)

  # Univariate GARCH spec
  uspec <- ugarchspec(
    variance.model = list(model = "sGARCH", garchOrder = c(1L, 1L)),
    mean.model = list(armaOrder = c(0L, 0L), include.mean = TRUE),
    distribution.model = "std"  # Student-t
  )

  multispec <- multispec(replicate(3L, uspec))

  dcc_spec <- dccspec(
    uspec = multispec,
    dccOrder = c(1L, 1L),
    distribution = "mvt"
  )

  ret_mat <- as.matrix(ret_3src)
  colnames(ret_mat) <- c("AR", "TSMOM", "KR10y")

  fit <- tryCatch(
    dccfit(dcc_spec, data = ret_mat, fit.control = list(eval.se = FALSE)),
    error = function(e) {
      cat("DCC fit error:", conditionMessage(e), "\n")
      NULL
    }
  )

  if (!is.null(fit)) {
    # Extract dynamic correlation history
    cor_array <- rcor(fit)  # 3 × 3 × T
    T_dim <- dim(cor_array)[3]
    dyn_cor <- data.table(
      t = 1:T_dim,
      cor_AR_TSMOM = cor_array["AR", "TSMOM", ],
      cor_AR_KR10y = cor_array["AR", "KR10y", ],
      cor_TSMOM_KR10y = cor_array["TSMOM", "KR10y", ]
    )

    # 12-step forward forecast
    fc <- tryCatch(
      dccforecast(fit, n.ahead = 12L),
      error = function(e) {
        cat("DCC forecast error:", conditionMessage(e), "\n")
        NULL
      }
    )

    if (!is.null(fc)) {
      cor_fc <- rcor(fc)  # list of 3×3 forecast matrices
      # cor_fc[[1]] is 3×3×12 array
      fc_array <- cor_fc[[1]]
      forward_cor <- data.table(
        h_month = 1:12,
        cor_AR_TSMOM_fc = fc_array["AR", "TSMOM", ],
        cor_AR_KR10y_fc = fc_array["AR", "KR10y", ],
        cor_TSMOM_KR10y_fc = fc_array["TSMOM", "KR10y", ]
      )

      cat("\nDCC-GARCH 12m forward correlation forecast:\n")
      print(forward_cor)

      # 1000-trial Monte Carlo simulation forward (using filtered DCC + bootstrap)
      # Simplified: re-sample DCC innovations + apply DCC-GARCH dynamics
      sim <- tryCatch(
        dccsim(fit, n.sim = 12L, m.sim = 1000L,
               startMethod = "sample"),
        error = function(e) {
          cat("DCC sim error:", conditionMessage(e), "\n")
          NULL
        }
      )

      if (!is.null(sim)) {
        # Extract simulated returns
        sim_ret <- fitted(sim)  # array (n.sim × n.assets × m.sim) typical
        if (length(dim(sim_ret)) == 3L) {
          # compute forward 12m mean cor across simulations
          mc_cor_AR_TSMOM <- numeric(1000L)
          mc_cor_AR_KR10y <- numeric(1000L)
          mc_cor_TSMOM_KR10y <- numeric(1000L)
          for (m in 1:1000L) {
            r_m <- sim_ret[, , m]
            mc_cor_AR_TSMOM[m] <- cor(r_m[, 1], r_m[, 2])
            mc_cor_AR_KR10y[m] <- cor(r_m[, 1], r_m[, 3])
            mc_cor_TSMOM_KR10y[m] <- cor(r_m[, 2], r_m[, 3])
          }
          dcc_mc_summary <- data.table(
            pair = c("AR_TSMOM", "AR_KR10y", "TSMOM_KR10y"),
            cor_static = c(static_cor[1, 2], static_cor[1, 3], static_cor[2, 3]),
            cor_mc_q025 = c(quantile(mc_cor_AR_TSMOM, 0.025),
                           quantile(mc_cor_AR_KR10y, 0.025),
                           quantile(mc_cor_TSMOM_KR10y, 0.025)),
            cor_mc_q500 = c(quantile(mc_cor_AR_TSMOM, 0.500),
                           quantile(mc_cor_AR_KR10y, 0.500),
                           quantile(mc_cor_TSMOM_KR10y, 0.500)),
            cor_mc_q975 = c(quantile(mc_cor_AR_TSMOM, 0.975),
                           quantile(mc_cor_AR_KR10y, 0.975),
                           quantile(mc_cor_TSMOM_KR10y, 0.975)),
            pr_cor_gt_05 = c(mean(abs(mc_cor_AR_TSMOM) > 0.5),
                            mean(abs(mc_cor_AR_KR10y) > 0.5),
                            mean(abs(mc_cor_TSMOM_KR10y) > 0.5))
          )
          fwrite(dcc_mc_summary, file.path(hybrid_dir, "axis3_dcc_mc_12m_forward.csv"))
          cat("\nDCC Monte Carlo 12m forward (1000 trials):\n")
          print(dcc_mc_summary)
        } else {
          cat("Sim ret dim:", dim(sim_ret), "\n")
        }
      }

      fwrite(dyn_cor, file.path(hybrid_dir, "axis3_dcc_history.csv"))
      fwrite(forward_cor, file.path(hybrid_dir, "axis3_dcc_forward12m.csv"))

      dcc_results <- list(
        history_csv = "axis3_dcc_history.csv",
        forward_csv = "axis3_dcc_forward12m.csv",
        mc_csv = "axis3_dcc_mc_12m_forward.csv",
        dcc_alpha = coef(fit)["[Joint]dcca1"],
        dcc_beta = coef(fit)["[Joint]dccb1"]
      )
    }
  }
}

# Fallback if rmgarch unavailable: use 12m rolling correlation forward extrapolation
if (is.null(dcc_results)) {
  cat("Falling back to 12m rolling correlation extrapolation\n")
  rolling_cor_dt <- post2015[!is.na(cor12m_AR_TSMOM),
                              .(ym, cor12m_AR_TSMOM, cor12m_AR_KR10y, cor12m_TSMOM_KR10y)]
  fwrite(rolling_cor_dt, file.path(hybrid_dir, "axis3_rolling12m_history.csv"))

  # AR(1) forward extrapolation per pair
  forward_ar1 <- function(x, h = 12L) {
    fit <- tryCatch(arima(x[!is.na(x)], order = c(1L, 0L, 0L)), error = function(e) NULL)
    if (is.null(fit)) return(rep(mean(x, na.rm = TRUE), h))
    pred <- predict(fit, n.ahead = h)
    pred$pred
  }

  fc_AR_TSMOM <- forward_ar1(rolling_cor_dt$cor12m_AR_TSMOM, 12L)
  fc_AR_KR10y <- forward_ar1(rolling_cor_dt$cor12m_AR_KR10y, 12L)
  fc_TSMOM_KR10y <- forward_ar1(rolling_cor_dt$cor12m_TSMOM_KR10y, 12L)

  forward_cor <- data.table(
    h_month = 1:12,
    cor_AR_TSMOM_ar1 = as.numeric(fc_AR_TSMOM),
    cor_AR_KR10y_ar1 = as.numeric(fc_AR_KR10y),
    cor_TSMOM_KR10y_ar1 = as.numeric(fc_TSMOM_KR10y)
  )
  fwrite(forward_cor, file.path(hybrid_dir, "axis3_ar1_forward12m.csv"))
  cat("\nAR(1) forward 12m correlation:\n")
  print(forward_cor)

  dcc_results <- list(
    history_csv = "axis3_rolling12m_history.csv",
    forward_csv = "axis3_ar1_forward12m.csv",
    mc_csv = NA,
    method = "AR1_fallback"
  )
}

# ---- 4. Crowding intensity proxy ----
# Crowding: 사이클 4 RF-R3 inheritance
# Proxy:
#   (a) abs pairwise corr 평균 (3-pair)
#   (b) max abs corr (3-pair)
#   (c) Stambaugh-Yu-Yuan 2015 RFS - anomaly attenuation rate
#       TSMOM 12m lookback = published anomaly (Moskowitz-Ooi-Pedersen 2012)
#       → publication 후 attenuation rate 0.32~0.58 (literature)
post2015[, abs_avg_cor_12m := (abs(cor12m_AR_TSMOM) + abs(cor12m_AR_KR10y) + abs(cor12m_TSMOM_KR10y)) / 3]
post2015[, max_abs_cor_12m := pmax(abs(cor12m_AR_TSMOM), abs(cor12m_AR_KR10y), abs(cor12m_TSMOM_KR10y))]

crowd_intensity_dt <- post2015[!is.na(abs_avg_cor_12m), .(ym, abs_avg_cor_12m, max_abs_cor_12m)]
fwrite(crowd_intensity_dt, file.path(hybrid_dir, "axis3_crowd_intensity_history.csv"))

crowd_summary <- list(
  pair_avg_abs_static = mean(abs(c(static_cor[1,2], static_cor[1,3], static_cor[2,3]))),
  pair_max_abs_static = max(abs(c(static_cor[1,2], static_cor[1,3], static_cor[2,3]))),
  recent_12m_avg_abs = recent_cor_12m[1, mean(abs(c(cor12m_AR_TSMOM, cor12m_AR_KR10y, cor12m_TSMOM_KR10y)))],
  recent_12m_max_abs = recent_cor_12m[1, max(abs(c(cor12m_AR_TSMOM, cor12m_AR_KR10y, cor12m_TSMOM_KR10y)))]
)

# ---- 5. TSMOM publication attenuation projection ----
# Moskowitz-Ooi-Pedersen 2012 — Time Series Momentum 12m lookback
# Stambaugh-Yu-Yuan 2015 RFS — anomaly returns 약 1/3~1/2 attenuation post-publication
# Hwang-Rubesam 2024 (working) — momentum factor decayed 0.42 in past 10y
# 보수적 가정: TSMOM published 2012 → 12y elapsed → 추가 6/12/24m horizon
#
# TSMOM contribution (15% weight × SR_TSMOM standalone)
# 만약 TSMOM SR_decay rate annualized 0.10 (보수)~0.25 (Stambaugh empirical)

# 최근 12m TSMOM standalone 측정
tsmom_recent_12m <- tail(post2015$r_TSMOM, 12L)
sr_tsmom_recent <- mean(tsmom_recent_12m) * 12 / (sd(tsmom_recent_12m) * sqrt(12))

# Full sample TSMOM SR (post-2015)
sr_tsmom_full <- mean(post2015$r_TSMOM) * 12 / (sd(post2015$r_TSMOM) * sqrt(12))

cat("\nTSMOM SR analysis:\n")
cat(sprintf("  Full sample (post-2015): %.4f\n", sr_tsmom_full))
cat(sprintf("  Recent 12m: %.4f\n", sr_tsmom_recent))

# Decay scenarios
tsmom_decay_scenarios <- data.table(
  scenario = c("optimistic", "neutral", "Stambaugh_2015_empirical", "pessimistic"),
  annual_decay_rate = c(0.05, 0.15, 0.30, 0.50),
  sr_baseline = sr_tsmom_full,
  sr_h6m = sr_tsmom_full * (1 - c(0.05, 0.15, 0.30, 0.50) / 2),  # 6m
  sr_h12m = sr_tsmom_full * (1 - c(0.05, 0.15, 0.30, 0.50)),
  sr_h24m = sr_tsmom_full * (1 - c(0.05, 0.15, 0.30, 0.50))^2
)
fwrite(tsmom_decay_scenarios, file.path(hybrid_dir, "axis3_tsmom_decay_scenarios.csv"))

# Hybrid impact: TSMOM weight 15%, Hybrid SR contribution
# 단순화: Hybrid SR sensitivity to TSMOM SR decay
# 사이클 4 inheritance: 256m Hybrid SR = 1.665, mctv_AR ~0.987 → AR dominant
# TSMOM 15% weight × decay → marginal Hybrid SR drop

# Estimate: SR_hybrid ≈ Σ w_i × SR_i × ρ_i (approximation)
# Hybrid SR decay sensitivity = 0.15 × ΔSR_TSMOM × correction_for_correlation
# 실증: TSMOM standalone SR contribution to Hybrid through 15% allocation
tsmom_hybrid_impact <- data.table(
  scenario = tsmom_decay_scenarios$scenario,
  annual_decay_rate = tsmom_decay_scenarios$annual_decay_rate,
  sr_tsmom_h12m = tsmom_decay_scenarios$sr_h12m,
  sr_hybrid_estimate_h12m = 1.665 - 0.15 * (sr_tsmom_full - tsmom_decay_scenarios$sr_h12m)
)
fwrite(tsmom_hybrid_impact, file.path(hybrid_dir, "axis3_tsmom_hybrid_impact.csv"))

cat("\nTSMOM decay → Hybrid SR impact:\n")
print(tsmom_hybrid_impact)

# ---- 6. Position-level capacity (placeholder; Cycle 1 sector 진단 inheritance) ----
# 사이클 1 ar_top20_sector_distribution.csv: 반도체 9개 / Capacity worst ADV breach 2 stocks
# Forward simulation: 시간 따른 ADV 변화 + position size 변화
capacity_inheritance_note <- list(
  source = "사이클 1 ar_top20_sector_distribution.csv",
  current_breach = "ADV worst 6.61% breach 2 stocks (실투 가능)",
  forward_proj_method = "정식 lifecycle scope (alpha-research WT)",
  marginal_recommendation = "TSMOM ETF rotation 15% — ETF 기반이므로 stock-level capacity 영향 외부, ETF 자체 turnover 모니터링 의무. AR 70% block은 사이클 1 KR top 20 + ADV worst 진단 inheritance."
)

# ---- 7. Save Axis 3 summary ----
axis3_summary <- list(
  axis = "axis_3_crowding_evolution_forward",
  static_3src_correlation = list(
    cor_AR_TSMOM = static_cor[1, 2],
    cor_AR_KR10y = static_cor[1, 3],
    cor_TSMOM_KR10y = static_cor[2, 3]
  ),
  recent_12m_correlation = as.list(recent_cor_12m[1]),
  dcc_garch_results = if (is.null(dcc_results)) NA else dcc_results,
  crowd_intensity_summary = crowd_summary,
  tsmom_decay_csv = "axis3_tsmom_decay_scenarios.csv",
  tsmom_hybrid_impact_csv = "axis3_tsmom_hybrid_impact.csv",
  position_capacity_note = capacity_inheritance_note,
  alert_thresholds = list(
    pair_corr_warning = 0.50,
    pair_corr_critical = 0.70,
    crowd_intensity_warning = 0.40,
    rationale = "사이클 4 Commodity-VRP CRISIS 0.811 standard"
  ),
  citations = c(
    "Engle 2002 JBES (DCC-GARCH)",
    "Moskowitz-Ooi-Pedersen 2012 JFE (TSMOM 12m)",
    "Stambaugh-Yu-Yuan 2015 RFS (anomaly attenuation)",
    "Hwang-Rubesam 2024 working (momentum decay)",
    "Brunnermeier-Pedersen 2009 RFS (crowding)"
  )
)

write_json(axis3_summary, file.path(hybrid_dir, "axis3_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Axis 3] DONE\n")
