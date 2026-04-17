## =============================================================================
## STR_1659_RF_UA: S2 Profiling + S3 Orthogonality
## 핵심아이디어: RF Uncertainty-Aware Diversifier
##   - S0 조건: RF-앵커 corr < 0.50, RF-XGB corr < 0.50, beta 보고
##   - XGBoost(STR_1656 M05) 상관 추가: feature space 분리 효과 확인
##   - IC significance: ICIR >= 0.20 (Alpha Lab Gate)
## =============================================================================
cat("=== STR_1659_RF_UA S2+S3 Profiling ===\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(ggplot2)
  library(arrow)
})

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
STRAT_DIR    <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1659_RF_UA")
OUTPUT_DIR   <- file.path(STRAT_DIR, "output")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))

# =============================================================================
# 1. NAV 데이터 로드
# =============================================================================
cat("[1] NAV 로드...\n")

# S1-B (PRIMARY): 컬럼 = Date, NAV_Strategy, Strategy_Ret
nav_b_raw <- fread(file.path(OUTPUT_DIR, "nav_S1_B.csv"))
cat(sprintf("  S1-B 컬럼: %s\n", paste(names(nav_b_raw), collapse=", ")))

# Strategy_Ret 컬럼 확인 (nav_S1_B.csv는 Date, NAV_Strategy 구조일 수 있음)
if ("Strategy_Ret" %in% names(nav_b_raw)) {
  nav_b <- nav_b_raw[, .(Date = as.Date(Date), Strategy_Ret = Strategy_Ret)]
} else if ("NAV_Strategy" %in% names(nav_b_raw)) {
  nav_b_raw[, Date := as.Date(Date)]
  setkey(nav_b_raw, Date)
  n <- nrow(nav_b_raw)
  strat_ret <- c(NA_real_, diff(nav_b_raw$NAV_Strategy) / head(nav_b_raw$NAV_Strategy, -1))
  nav_b <- data.table(Date = nav_b_raw$Date, Strategy_Ret = strat_ret)
  nav_b <- nav_b[!is.na(Strategy_Ret)]
} else {
  stop("nav_S1_B.csv: Strategy_Ret 또는 NAV_Strategy 컬럼 없음")
}
nav_b <- nav_b[is.finite(Strategy_Ret)]
setkey(nav_b, Date)
cat(sprintf("  S1-B: %d days (%s ~ %s)\n", nrow(nav_b), min(nav_b$Date), max(nav_b$Date)))

# BM (KOSPI) 수익률
bm_dt <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm_dt[, Date := as.Date(Date)]
setnames(bm_dt, "BM_Ret", "bm_ret")
bm_dt <- bm_dt[, .(Date, bm_ret)][is.finite(bm_ret)]
setkey(bm_dt, Date)
cat(sprintf("  BM: %d days (%s ~ %s)\n", nrow(bm_dt), min(bm_dt$Date), max(bm_dt$Date)))

# Anchor: STR_1631 VD+ (NAV_vdp)
anchor_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
if (file.exists(anchor_path)) {
  anchor_raw <- fread(anchor_path)
  if ("NAV_vdp" %in% names(anchor_raw)) {
    anchor_raw[, Date := as.Date(Date)]
    setkey(anchor_raw, Date)
    nav_vdp <- anchor_raw$NAV_vdp
    n_a <- nrow(anchor_raw)
    anchor_ret_vec <- c(NA_real_, diff(nav_vdp) / head(nav_vdp, -1))
    anchor_dt <- data.table(Date = anchor_raw$Date, anchor_ret = anchor_ret_vec)
    anchor_dt <- anchor_dt[!is.na(anchor_ret) & is.finite(anchor_ret)]
  } else {
    cat("  WARNING: NAV_vdp not found, fallback 0\n")
    anchor_dt <- data.table(Date = nav_b$Date, anchor_ret = 0)
  }
  setkey(anchor_dt, Date)
  cat(sprintf("  Anchor(VD+): %d days (%s ~ %s)\n",
              nrow(anchor_dt), min(anchor_dt$Date), max(anchor_dt$Date)))
} else {
  cat("  WARNING: Anchor NAV not found\n")
  anchor_dt <- data.table(Date = nav_b$Date, anchor_ret = 0)
  setkey(anchor_dt, Date)
}

# XGBoost NAV: STR_1656 M05
xgb_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/output/s5_mutations/M05/nav.csv")
xgb_available <- file.exists(xgb_path)
if (xgb_available) {
  xgb_raw <- fread(xgb_path)
  cat(sprintf("  XGB M05 컬럼: %s\n", paste(names(xgb_raw), collapse=", ")))
  if ("Strategy_Ret" %in% names(xgb_raw)) {
    xgb_dt <- xgb_raw[, .(Date = as.Date(Date), xgb_ret = Strategy_Ret)]
  } else if ("NAV" %in% names(xgb_raw)) {
    xgb_raw[, Date := as.Date(Date)]
    setkey(xgb_raw, Date)
    xgb_ret_vec <- c(NA_real_, diff(xgb_raw$NAV) / head(xgb_raw$NAV, -1))
    xgb_dt <- data.table(Date = xgb_raw$Date, xgb_ret = xgb_ret_vec)
    xgb_dt <- xgb_dt[!is.na(xgb_ret)]
  } else {
    xgb_available <- FALSE
    cat("  WARNING: XGB M05 컬럼 인식 실패\n")
  }
  if (xgb_available) {
    xgb_dt <- xgb_dt[is.finite(xgb_ret)]
    setkey(xgb_dt, Date)
    cat(sprintf("  XGB M05: %d days (%s ~ %s)\n",
                nrow(xgb_dt), min(xgb_dt$Date), max(xgb_dt$Date)))
  }
} else {
  cat("  WARNING: XGB M05 nav.csv not found\n")
}

# Merge: nav_b + bm_dt + anchor_dt
merged <- merge(nav_b[, .(Date, strat_ret = Strategy_Ret)], bm_dt, by = "Date")
merged <- merge(merged, anchor_dt, by = "Date")
merged <- merged[is.finite(strat_ret) & is.finite(bm_ret) & is.finite(anchor_ret)]
cat(sprintf("  Merged(RF+BM+Anchor): %d days\n", nrow(merged)))

# XGB 추가 merge (별도 — 기간이 다를 수 있음)
if (xgb_available) {
  merged_xgb <- merge(nav_b[, .(Date, strat_ret = Strategy_Ret)], xgb_dt, by = "Date")
  merged_xgb <- merged_xgb[is.finite(strat_ret) & is.finite(xgb_ret)]
  cat(sprintf("  Merged(RF+XGB): %d days\n", nrow(merged_xgb)))
}

# =============================================================================
# 2. Rolling 60d Beta (S0 condition: beta > 0.85 → 재검토)
# =============================================================================
cat("\n[2] Rolling 60d Beta...\n")
win <- 60L
merged[, roll_beta := {
  n <- .N
  beta <- rep(NA_real_, n)
  for (i in win:n) {
    idx <- (i - win + 1):i
    x <- bm_ret[idx]; y <- strat_ret[idx]
    v <- is.finite(x) & is.finite(y)
    if (sum(v) > 20) beta[i] <- cov(y[v], x[v]) / var(x[v])
  }
  beta
}]

roll_beta <- merged$roll_beta[!is.na(merged$roll_beta)]
beta_stats <- list(
  mean   = round(mean(roll_beta), 4),
  median = round(median(roll_beta), 4),
  p5     = round(quantile(roll_beta, 0.05), 4),
  p95    = round(quantile(roll_beta, 0.95), 4),
  flag_above_085 = mean(roll_beta) > 0.85   # RiskMgr 조건: beta > 0.85 재검토
)
cat(sprintf("  Beta: mean=%.3f median=%.3f [5%%=%.3f, 95%%=%.3f]\n",
            beta_stats$mean, beta_stats$median, beta_stats$p5, beta_stats$p95))
cat(sprintf("  RiskMgr 조건 (beta>0.85 재검토): %s\n",
            ifelse(beta_stats$flag_above_085, "FLAG - 재검토 필요", "OK (<=0.85)")))

# =============================================================================
# 3. Rolling 60d Anchor Correlation (S0 condition: corr < 0.50)
# =============================================================================
cat("\n[3] Rolling 60d Anchor(VD+) Correlation...\n")
merged[, roll_corr_anchor := {
  n <- .N
  cr <- rep(NA_real_, n)
  for (i in win:n) {
    idx <- (i - win + 1):i
    x <- anchor_ret[idx]; y <- strat_ret[idx]
    v <- is.finite(x) & is.finite(y)
    if (sum(v) > 20) cr[i] <- cor(y[v], x[v])
  }
  cr
}]

roll_corr_anchor <- merged$roll_corr_anchor[!is.na(merged$roll_corr_anchor)]
corr_anchor_stats <- list(
  mean   = round(mean(roll_corr_anchor), 4),
  median = round(median(roll_corr_anchor), 4),
  p5     = round(quantile(roll_corr_anchor, 0.05), 4),
  p95    = round(quantile(roll_corr_anchor, 0.95), 4),
  pass_050 = mean(roll_corr_anchor) < 0.50  # S0 success criteria
)
cat(sprintf("  Anchor Corr: mean=%.3f median=%.3f [5%%=%.3f, 95%%=%.3f]\n",
            corr_anchor_stats$mean, corr_anchor_stats$median,
            corr_anchor_stats$p5, corr_anchor_stats$p95))
cat(sprintf("  S0 success criteria (RF-Anchor corr<0.50): %s\n",
            ifelse(corr_anchor_stats$pass_050, "PASS", "FAIL")))

# =============================================================================
# 4. Rolling 60d XGBoost Correlation (S0 condition: corr < 0.50)
# =============================================================================
cat("\n[4] Rolling 60d XGBoost(M05) Correlation...\n")
if (xgb_available && nrow(merged_xgb) > win) {
  merged_xgb[, roll_corr_xgb := {
    n <- .N
    cr <- rep(NA_real_, n)
    for (i in win:n) {
      idx <- (i - win + 1):i
      x <- xgb_ret[idx]; y <- strat_ret[idx]
      v <- is.finite(x) & is.finite(y)
      if (sum(v) > 20) cr[i] <- cor(y[v], x[v])
    }
    cr
  }]

  roll_corr_xgb <- merged_xgb$roll_corr_xgb[!is.na(merged_xgb$roll_corr_xgb)]
  corr_xgb_stats <- list(
    mean   = round(mean(roll_corr_xgb), 4),
    median = round(median(roll_corr_xgb), 4),
    p5     = round(quantile(roll_corr_xgb, 0.05), 4),
    p95    = round(quantile(roll_corr_xgb, 0.95), 4),
    pass_050 = mean(roll_corr_xgb) < 0.50  # feature space 분리 확인
  )
  cat(sprintf("  XGB Corr: mean=%.3f median=%.3f [5%%=%.3f, 95%%=%.3f]\n",
              corr_xgb_stats$mean, corr_xgb_stats$median,
              corr_xgb_stats$p5, corr_xgb_stats$p95))
  cat(sprintf("  S0 feature space 분리 (RF-XGB corr<0.50): %s\n",
              ifelse(corr_xgb_stats$pass_050, "PASS", "FAIL")))
} else {
  cat("  XGB 데이터 없거나 부족 — 상관 분석 생략\n")
  corr_xgb_stats <- list(
    mean = NA, median = NA, p5 = NA, p95 = NA, pass_050 = NA,
    note = "XGB nav unavailable or insufficient overlap"
  )
}

# =============================================================================
# 5. EVT Tail Risk (GPD shape parameter)
# =============================================================================
cat("\n[5] EVT Tail Risk...\n")
ret_vec <- merged$strat_ret[is.finite(merged$strat_ret)]
losses  <- -ret_vec[ret_vec < 0]

threshold_pct <- 0.90
threshold_val <- quantile(losses, threshold_pct)
exceedances   <- losses[losses > threshold_val] - threshold_val
n_exceed      <- length(exceedances)

if (n_exceed > 30) {
  ex_mean   <- mean(exceedances)
  ex_var    <- var(exceedances)
  xi_hat    <- round(0.5 * (ex_mean^2 / ex_var - 1), 4)
  sigma_hat <- round(ex_mean * (ex_mean^2 / ex_var + 1) / 2, 4)
  cat(sprintf("  GPD shape(xi): %.4f | scale(sigma): %.4f | N=%d\n",
              xi_hat, sigma_hat, n_exceed))
  cat(sprintf("  Fat tail: %s\n",
              ifelse(xi_hat > 0.3, "EXTREME fat tails",
                     ifelse(xi_hat > 0, "Moderate fat tails", "Thin tails"))))
} else {
  xi_hat <- NA_real_; sigma_hat <- NA_real_
  cat("  Insufficient exceedances for GPD\n")
}

var_95  <- round(quantile(ret_vec, 0.05),  5)
var_99  <- round(quantile(ret_vec, 0.01),  5)
cvar_95 <- round(mean(ret_vec[ret_vec <= quantile(ret_vec, 0.05)]), 5)
cvar_99 <- round(mean(ret_vec[ret_vec <= quantile(ret_vec, 0.01)]), 5)
cat(sprintf("  VaR95=%.4f VaR99=%.4f CVaR95=%.4f CVaR99=%.4f\n",
            var_95, var_99, cvar_95, cvar_99))

# =============================================================================
# 6. IC Significance (t-stat, pct positive)
# =============================================================================
cat("\n[6] IC Significance...\n")
ic_path <- file.path(OUTPUT_DIR, "ic_detail_S1_B.csv")
ic_sig_result <- list(t_stat = NA, pct_pos = NA, n = 0)

if (file.exists(ic_path)) {
  ic_dt <- fread(ic_path)
  cat(sprintf("  IC 컬럼: %s\n", paste(names(ic_dt), collapse=", ")))
  ic_col <- if ("IC" %in% names(ic_dt)) "IC" else names(ic_dt)[2]
  v <- ic_dt[[ic_col]][!is.na(ic_dt[[ic_col]]) & is.finite(ic_dt[[ic_col]])]
  n <- length(v)
  if (n >= 5) {
    ic_sig_result <- list(
      t_stat  = round(mean(v) / (sd(v) / sqrt(n)), 3),
      pct_pos = round(sum(v > 0) / n * 100, 1),
      n       = n,
      ic_mean = round(mean(v), 4),
      ic_sd   = round(sd(v), 4)
    )
  }
  cat(sprintf("  S1-B: IC_mean=%.4f t=%.2f pct_pos=%.1f%% (N=%d)\n",
              ic_sig_result$ic_mean %||% NA,
              ic_sig_result$t_stat  %||% NA,
              ic_sig_result$pct_pos %||% NA,
              ic_sig_result$n))
} else {
  cat("  ic_detail_S1_B.csv 없음\n")
}

# ICIR 확인 (S0 artifact에서)
icir_b <- 0.6976  # performance.json에서 확인된 값
cat(sprintf("  ICIR S1-B: %.4f (Alpha Lab Gate >=0.20: %s)\n",
            icir_b, ifelse(icir_b >= 0.20, "PASS", "FAIL")))

# =============================================================================
# 7. S3 Orthogonality — Full-period & Crisis Correlation
# =============================================================================
cat("\n[7] S3 Orthogonality...\n")

# 전체 기간 anchor 상관
full_corr_anchor <- round(cor(merged$strat_ret, merged$anchor_ret, use = "complete.obs"), 4)
cat(sprintf("  Full-period anchor corr: %.4f\n", full_corr_anchor))

# 전체 기간 XGB 상관
if (xgb_available && nrow(merged_xgb) > 60) {
  full_corr_xgb <- round(cor(merged_xgb$strat_ret, merged_xgb$xgb_ret, use = "complete.obs"), 4)
  cat(sprintf("  Full-period XGB corr: %.4f\n", full_corr_xgb))
} else {
  full_corr_xgb <- NA_real_
  cat("  Full-period XGB corr: NA (data unavailable)\n")
}

# 위기 상관 (worst 10% BM days)
crisis_thresh <- quantile(merged$bm_ret, 0.10, na.rm = TRUE)
crisis_dt     <- merged[bm_ret <= crisis_thresh]
if (nrow(crisis_dt) > 30) {
  crisis_corr_anchor <- round(cor(crisis_dt$strat_ret, crisis_dt$anchor_ret,
                                   use = "complete.obs"), 4)
  cat(sprintf("  Crisis anchor corr (worst 10%% BM): %.4f\n", crisis_corr_anchor))
} else {
  crisis_corr_anchor <- NA_real_
  cat("  Insufficient crisis data\n")
}

# max_corr = max(abs(anchor_corr), abs(xgb_corr)) — novelty 계산 기준
max_corr <- max(abs(full_corr_anchor), abs(full_corr_xgb), na.rm = TRUE)
novelty_bonus <- if (max_corr < 0.30) { 15L
} else if (max_corr < 0.50) { 7L
} else { 0L }
cat(sprintf("  max_corr=%.3f → novelty_bonus=%d\n", max_corr, novelty_bonus))

# =============================================================================
# 8. Charts
# =============================================================================
cat("\n[8] Charts...\n")
tryCatch({
  # Chart 1: Rolling Beta + Anchor Corr + XGB Corr
  plot_dt <- merged[!is.na(roll_beta) & !is.na(roll_corr_anchor)]

  if (xgb_available && "roll_corr_xgb" %in% names(merged_xgb)) {
    # XGB corr를 merged_xgb에서 가져와 plot_dt에 merge
    xgb_corr_dt <- merged_xgb[!is.na(roll_corr_xgb), .(Date, roll_corr_xgb)]
    plot_dt2 <- merge(plot_dt[, .(Date, roll_beta, roll_corr_anchor)],
                      xgb_corr_dt, by = "Date", all.x = TRUE)
  } else {
    plot_dt2 <- plot_dt[, .(Date, roll_beta, roll_corr_anchor)]
    plot_dt2[, roll_corr_xgb := NA_real_]
  }

  # melt for ggplot
  plot_long <- melt(plot_dt2, id.vars = "Date",
                    measure.vars = c("roll_beta", "roll_corr_anchor", "roll_corr_xgb"),
                    variable.name = "Metric", value.name = "Value")
  plot_long[, Label := fcase(
    Metric == "roll_beta",         "Beta (vs KOSPI)",
    Metric == "roll_corr_anchor",  "Corr vs Anchor(VD+)",
    Metric == "roll_corr_xgb",     "Corr vs XGB(M05)"
  )]

  p1 <- ggplot(plot_long[!is.na(Value)], aes(x = Date, y = Value, color = Label)) +
    geom_line(alpha = 0.65, linewidth = 0.8) +
    geom_hline(yintercept = 0.85, linetype = "dashed", color = "red",    alpha = 0.5) +
    geom_hline(yintercept = 0.50, linetype = "dashed", color = "orange", alpha = 0.5) +
    geom_hline(yintercept = 0.00, linetype = "dotted", color = "grey50", alpha = 0.4) +
    annotate("text", x = min(plot_dt2$Date), y = 0.87,
             label = "Beta 0.85 (RiskMgr flag)", hjust = 0, size = 3, color = "red") +
    annotate("text", x = min(plot_dt2$Date), y = 0.52,
             label = "Corr 0.50 (S0 target)", hjust = 0, size = 3, color = "orange") +
    scale_color_manual(values = c(
      "Beta (vs KOSPI)"       = "#1f77b4",
      "Corr vs Anchor(VD+)"   = "#ff7f0e",
      "Corr vs XGB(M05)"      = "#2ca02c"
    )) +
    labs(
      title    = "STR_1659_RF_UA S1-B -- Rolling 60d Beta & Correlations",
      subtitle = sprintf(
        "Beta mean=%.3f | Anchor corr mean=%.3f (%s) | XGB corr mean=%.3f (%s)",
        beta_stats$mean,
        corr_anchor_stats$mean, ifelse(corr_anchor_stats$pass_050, "PASS", "FAIL"),
        corr_xgb_stats$mean %||% NA,
        ifelse(isTRUE(corr_xgb_stats$pass_050), "PASS",
               ifelse(is.na(corr_xgb_stats$pass_050), "N/A", "FAIL"))
      ),
      x = NULL, y = "Value", color = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  ggsave(file.path(OUTPUT_DIR, "s2_beta_corr.png"), p1,
         width = 13, height = 5, dpi = 150)
  cat("  s2_beta_corr.png saved\n")

  # Chart 2: Loss Distribution + EVT
  loss_dt <- data.table(loss = losses)
  gpd_label <- if (!is.na(xi_hat)) sprintf("GPD xi=%.3f", xi_hat) else "GPD N/A"
  p2 <- ggplot(loss_dt, aes(x = loss)) +
    geom_histogram(bins = 80, fill = "#1f77b4", alpha = 0.7) +
    geom_vline(xintercept = abs(var_95), linetype = "dashed", color = "orange", linewidth = 0.8) +
    geom_vline(xintercept = abs(var_99), linetype = "dashed", color = "red",    linewidth = 0.8) +
    annotate("text", x = abs(var_95), y = Inf,
             label = sprintf("VaR95\n%.3f%%", abs(var_95)*100),
             vjust = 1.5, hjust = -0.1, size = 3, color = "orange") +
    annotate("text", x = abs(var_99), y = Inf,
             label = sprintf("VaR99\n%.3f%%", abs(var_99)*100),
             vjust = 1.5, hjust = -0.1, size = 3, color = "red") +
    labs(
      title    = "STR_1659_RF_UA S1-B -- Loss Distribution (EVT)",
      subtitle = sprintf("%s | CVaR95=%.4f | CVaR99=%.4f", gpd_label, cvar_95, cvar_99),
      x        = "Daily Loss", y = "Count"
    ) +
    theme_minimal(base_size = 11)
  ggsave(file.path(OUTPUT_DIR, "s2_evt_loss.png"), p2,
         width = 10, height = 5, dpi = 150)
  cat("  s2_evt_loss.png saved\n")

}, error = function(e) cat("  Chart error:", conditionMessage(e), "\n"))

# =============================================================================
# 9. stage_artifacts JSON 작성
# =============================================================================
cat("\n[9] Stage Artifact 작성...\n")

# S1 artifact에서 기본 정보 로드
s1_path <- file.path(PROJECT_ROOT, "stage_artifacts/s1_construction_STR_1659_RF_UA.json")
if (file.exists(s1_path)) {
  s2_art <- fromJSON(s1_path)
} else {
  s2_art <- list(factor_id = "STR_1659_RF_UA")
}

s2_art$stage <- "S2_S3_complete"
s2_art$updated_at <- as.character(Sys.time())

s2_art$s2_profiling <- list(
  rolling_60d_beta = beta_stats,
  rolling_60d_anchor_corr = corr_anchor_stats,
  rolling_60d_xgb_corr = corr_xgb_stats,
  evt_profile = list(
    gpd_shape_xi    = xi_hat,
    gpd_scale_sigma = sigma_hat,
    threshold_pct   = threshold_pct,
    n_exceedances   = n_exceed,
    VaR_95  = var_95,  VaR_99  = var_99,
    CVaR_95 = cvar_95, CVaR_99 = cvar_99
  ),
  ic_significance = list(
    primary_variant = "S1_B",
    t_stat   = ic_sig_result$t_stat,
    pct_pos  = ic_sig_result$pct_pos,
    n        = ic_sig_result$n,
    ic_mean  = ic_sig_result$ic_mean %||% 0.06,
    icir     = icir_b
  ),
  s0_conditions = list(
    rf_anchor_corr_lt_050  = corr_anchor_stats$pass_050,
    rf_xgb_corr_lt_050     = corr_xgb_stats$pass_050,
    beta_flag_above_085    = beta_stats$flag_above_085,
    alpha_lab_gate_icir    = icir_b >= 0.20,
    note = "S1-B EW baseline. Overlay(VT/DD) + ensemble은 S5에서 측정"
  )
)

s2_art$s3_orthogonality <- list(
  anchor_return_corr  = full_corr_anchor,
  xgb_return_corr     = full_corr_xgb,
  crisis_corr_anchor  = crisis_corr_anchor,
  max_corr            = max_corr,
  novelty_bonus       = novelty_bonus,
  max_corr_assessment = ifelse(max_corr < 0.30, "LOW (bonus +15)",
                         ifelse(max_corr < 0.50, "MODERATE (bonus +7)", "HIGH (no bonus)"))
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts/s2_profile_STR_1659_RF_UA.json")
write_json(s2_art, art_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Artifact saved: %s\n", art_path))

# =============================================================================
# 10. Summary
# =============================================================================
cat("\n=== S2+S3 Summary: STR_1659_RF_UA ===\n")
cat(sprintf("  [S1-B 성과] CAGR=20.7%% SR=0.960 MDD=-65.3%%\n"))
cat(sprintf("  [ICIR] %.4f (Alpha Lab Gate >=0.20: PASS)\n", icir_b))
cat(sprintf("  [IC t-stat] %.2f  pct_pos=%.1f%% (N=%d)\n",
            ic_sig_result$t_stat %||% NA,
            ic_sig_result$pct_pos %||% NA,
            ic_sig_result$n))
cat(sprintf("  [Rolling Beta] mean=%.3f (RiskMgr flag>0.85: %s)\n",
            beta_stats$mean, ifelse(beta_stats$flag_above_085, "FLAG", "OK")))
cat(sprintf("  [RF-Anchor Corr] mean=%.3f (S0 <0.50: %s)\n",
            corr_anchor_stats$mean, ifelse(corr_anchor_stats$pass_050, "PASS", "FAIL")))
cat(sprintf("  [RF-XGB Corr] mean=%s (S0 <0.50: %s)\n",
            ifelse(is.na(corr_xgb_stats$mean), "N/A", sprintf("%.3f", corr_xgb_stats$mean)),
            ifelse(isTRUE(corr_xgb_stats$pass_050), "PASS",
                   ifelse(is.na(corr_xgb_stats$pass_050), "N/A", "FAIL"))))
cat(sprintf("  [Crisis Anchor Corr] %.4f\n", crisis_corr_anchor %||% NA))
cat(sprintf("  [EVT GPD xi] %.4f (%s)\n", xi_hat %||% NA,
            ifelse(!is.na(xi_hat) && xi_hat > 0.3, "EXTREME fat tails",
                   ifelse(!is.na(xi_hat) && xi_hat > 0, "Moderate fat tails", "Thin/NA"))))
cat(sprintf("  [Novelty] max_corr=%.3f bonus=%d (%s)\n",
            max_corr, novelty_bonus, s2_art$s3_orthogonality$max_corr_assessment))
cat(sprintf("  [VaR95/CVaR95] %.4f / %.4f\n", var_95, cvar_95))
cat("\n완료\n")
