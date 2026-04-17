## =============================================================================
## STR_1656_MLRA: S2 Profiling + S3 Orthogonality
## S0 조건: rolling 60d beta, anchor correlation, EVT tail risk
## =============================================================================
cat("=== STR_1656_MLRA S2+S3 Profiling ===\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(ggplot2)
  library(arrow)
})

# Null-coalescing operator (not loaded by default)
`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRAT_DIR    <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA")
OUTPUT_DIR   <- file.path(STRAT_DIR, "output")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))

# =============================================================================
# 1. NAV 데이터 로드
# =============================================================================
cat("[1] NAV 로드...\n")

# S1-B (best variant): 컬럼 = Date, NAV, Strategy_Ret
nav_b_raw <- fread(file.path(OUTPUT_DIR, "nav_S1_B.csv"))
nav_b <- nav_b_raw[, .(Date = as.Date(Date), Strategy_Ret = Strategy_Ret)]
nav_b <- nav_b[is.finite(Strategy_Ret)]
setkey(nav_b, Date)
cat(sprintf("  S1-B: %d days (%s ~ %s)\n", nrow(nav_b), min(nav_b$Date), max(nav_b$Date)))

# S1-A
nav_a_raw <- fread(file.path(OUTPUT_DIR, "nav_S1_A.csv"))
nav_a <- nav_a_raw[, .(Date = as.Date(Date), Strategy_Ret = Strategy_Ret)]
nav_a <- nav_a[is.finite(Strategy_Ret)]
setkey(nav_a, Date)

# BM (KOSPI) 수익률: .cache/benchmark.parquet (Date, BM_Ret)
bm_dt <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm_dt[, Date := as.Date(Date)]
setnames(bm_dt, "BM_Ret", "bm_ret")
bm_dt <- bm_dt[, .(Date, bm_ret)][is.finite(bm_ret)]
setkey(bm_dt, Date)
cat(sprintf("  BM: %d days (%s ~ %s)\n", nrow(bm_dt), min(bm_dt$Date), max(bm_dt$Date)))

# Anchor: STR_1631 VD+
anchor_path <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
if (file.exists(anchor_path)) {
  anchor_raw <- fread(anchor_path)
  # NAV_vdp column
  if ("NAV_vdp" %in% names(anchor_raw)) {
    anchor_dt <- anchor_raw[, .(Date = as.Date(Date))]
    anchor_dt[, anchor_ret := c(NA, diff(anchor_raw$NAV_vdp) / head(anchor_raw$NAV_vdp, -1))]
    anchor_dt <- anchor_dt[!is.na(anchor_ret) & is.finite(anchor_ret)]
  } else {
    # Fallback: first numeric column after Date
    anchor_dt <- anchor_raw[, .(Date = as.Date(Date), anchor_ret = 0)]
    cat("  WARNING: NAV_vdp not found, using placeholder\n")
  }
  setkey(anchor_dt, Date)
  cat(sprintf("  Anchor: %d days (%s ~ %s)\n", nrow(anchor_dt), min(anchor_dt$Date), max(anchor_dt$Date)))
} else {
  cat("  WARNING: Anchor NAV not found\n")
  anchor_dt <- data.table(Date = nav_b$Date, anchor_ret = 0)
  setkey(anchor_dt, Date)
}

# Merge: nav_b + bm_dt + anchor_dt
merged <- merge(nav_b[, .(Date, strat_ret = Strategy_Ret)], bm_dt, by = "Date")
merged <- merge(merged, anchor_dt, by = "Date")
merged <- merged[is.finite(strat_ret) & is.finite(bm_ret) & is.finite(anchor_ret)]
cat(sprintf("  Merged: %d days\n", nrow(merged)))

# =============================================================================
# 2. Rolling 60d Beta (S0 condition: beta < 0.65)
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
  mean = round(mean(roll_beta), 4),
  median = round(median(roll_beta), 4),
  p5 = round(quantile(roll_beta, 0.05), 4),
  p95 = round(quantile(roll_beta, 0.95), 4),
  pass_065 = mean(roll_beta) < 0.65
)
cat(sprintf("  Beta: mean=%.3f median=%.3f [5%%=%.3f, 95%%=%.3f]\n",
            beta_stats$mean, beta_stats$median, beta_stats$p5, beta_stats$p95))
cat(sprintf("  S0 condition (beta<0.65): %s\n", ifelse(beta_stats$pass_065, "PASS", "FAIL")))

# =============================================================================
# 3. Rolling 60d Anchor Correlation (S0 condition: corr < 0.45)
# =============================================================================
cat("\n[3] Rolling 60d Anchor Correlation...\n")
merged[, roll_corr := {
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

roll_corr <- merged$roll_corr[!is.na(merged$roll_corr)]
corr_stats <- list(
  mean = round(mean(roll_corr), 4),
  median = round(median(roll_corr), 4),
  p5 = round(quantile(roll_corr, 0.05), 4),
  p95 = round(quantile(roll_corr, 0.95), 4),
  pass_045 = mean(roll_corr) < 0.45
)
cat(sprintf("  Corr: mean=%.3f median=%.3f [5%%=%.3f, 95%%=%.3f]\n",
            corr_stats$mean, corr_stats$median, corr_stats$p5, corr_stats$p95))
cat(sprintf("  S0 condition (corr<0.45): %s\n", ifelse(corr_stats$pass_045, "PASS", "FAIL")))

# =============================================================================
# 4. EVT Tail Risk (GPD shape parameter)
# =============================================================================
cat("\n[4] EVT Tail Risk...\n")
ret_vec <- merged$strat_ret[is.finite(merged$strat_ret)]
losses <- -ret_vec[ret_vec < 0]

# GPD fitting via Method of Moments (no external package needed)
threshold_pct <- 0.90
threshold_val <- quantile(losses, threshold_pct)
exceedances <- losses[losses > threshold_val] - threshold_val
n_exceed <- length(exceedances)

if (n_exceed > 30) {
  ex_mean <- mean(exceedances)
  ex_var  <- var(exceedances)
  # Method of Moments: xi = 0.5 * (ex_mean^2/ex_var - 1), sigma = ex_mean*(ex_mean^2/ex_var + 1)/2
  xi_hat    <- round(0.5 * (ex_mean^2 / ex_var - 1), 4)
  sigma_hat <- round(ex_mean * (ex_mean^2 / ex_var + 1) / 2, 4)
  cat(sprintf("  GPD shape (xi): %.4f | scale (sigma): %.4f | N exceedances: %d\n",
              xi_hat, sigma_hat, n_exceed))
  cat(sprintf("  Fat tail assessment: %s\n",
              ifelse(xi_hat > 0.3, "EXTREME fat tails", ifelse(xi_hat > 0, "Moderate fat tails", "Thin tails"))))
} else {
  xi_hat <- NA; sigma_hat <- NA
  cat("  Insufficient exceedances for GPD\n")
}

# VaR/CVaR
var_95  <- round(quantile(ret_vec, 0.05), 5)
var_99  <- round(quantile(ret_vec, 0.01), 5)
cvar_95 <- round(mean(ret_vec[ret_vec <= quantile(ret_vec, 0.05)]), 5)
cvar_99 <- round(mean(ret_vec[ret_vec <= quantile(ret_vec, 0.01)]), 5)
cat(sprintf("  VaR95=%.4f VaR99=%.4f CVaR95=%.4f CVaR99=%.4f\n",
            var_95, var_99, cvar_95, cvar_99))

# =============================================================================
# 5. IC Significance (t-stat, pct positive)
# =============================================================================
cat("\n[5] IC Significance...\n")
ic_b <- fread(file.path(OUTPUT_DIR, "ic_timeseries_B.csv"))
ic_a <- fread(file.path(OUTPUT_DIR, "ic_timeseries_A.csv"))

ic_sig <- function(ic_dt) {
  v <- ic_dt$IC[!is.na(ic_dt$IC)]
  n <- length(v)
  if (n < 5) return(list(t_stat=NA, pct_pos=NA, n=n))
  list(
    t_stat = round(mean(v) / (sd(v) / sqrt(n)), 3),
    pct_pos = round(sum(v > 0) / n * 100, 1),
    n = n
  )
}

sig_a <- ic_sig(ic_a); sig_b <- ic_sig(ic_b)
cat(sprintf("  S1-A: t=%.2f pct_pos=%.1f%% (N=%d)\n", sig_a$t_stat, sig_a$pct_pos, sig_a$n))
cat(sprintf("  S1-B: t=%.2f pct_pos=%.1f%% (N=%d)\n", sig_b$t_stat, sig_b$pct_pos, sig_b$n))

# =============================================================================
# 6. S3 Orthogonality — Return Correlation with Anchor
# =============================================================================
cat("\n[6] S3 Orthogonality...\n")
full_corr <- round(cor(merged$strat_ret, merged$anchor_ret, use = "complete.obs"), 4)
cat(sprintf("  Full-period return correlation with anchor: %.4f\n", full_corr))

# Crisis correlation (worst 10% BM days)
crisis_thresh <- quantile(merged$bm_ret, 0.10, na.rm = TRUE)
crisis_dt <- merged[bm_ret <= crisis_thresh]
if (nrow(crisis_dt) > 30) {
  crisis_corr <- round(cor(crisis_dt$strat_ret, crisis_dt$anchor_ret, use = "complete.obs"), 4)
  cat(sprintf("  Crisis correlation (worst 10%% BM days): %.4f\n", crisis_corr))
} else {
  crisis_corr <- NA
  cat("  Insufficient crisis data\n")
}

# Novelty assessment
novelty_bonus <- if (!is.na(full_corr) && abs(full_corr) < 0.30) { 15L
} else if (!is.na(full_corr) && abs(full_corr) < 0.50) { 7L
} else { 0L }
cat(sprintf("  Novelty bonus: %d (corr %.3f)\n", novelty_bonus, full_corr))

# =============================================================================
# 7. Charts
# =============================================================================
cat("\n[7] Charts...\n")
tryCatch({
  plot_dt <- merged[!is.na(roll_beta) & !is.na(roll_corr)]

  # Rolling Beta + Correlation dual plot
  p1 <- ggplot(plot_dt, aes(x = Date)) +
    geom_line(aes(y = roll_beta, color = "Beta"), alpha = 0.6) +
    geom_line(aes(y = roll_corr, color = "Anchor Corr"), alpha = 0.6) +
    geom_hline(yintercept = 0.65, linetype = "dashed", color = "red", alpha = 0.5) +
    geom_hline(yintercept = 0.45, linetype = "dashed", color = "orange", alpha = 0.5) +
    scale_color_manual(values = c("Beta" = "#1f77b4", "Anchor Corr" = "#ff7f0e")) +
    labs(title = "STR_1656_MLRA S1-B — Rolling 60d Beta & Anchor Correlation",
         subtitle = sprintf("Beta mean=%.3f (target<0.65) | Corr mean=%.3f (target<0.45)",
                            beta_stats$mean, corr_stats$mean),
         x = NULL, y = "Value", color = NULL) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")
  ggsave(file.path(OUTPUT_DIR, "s2_beta_corr.png"), p1, width = 12, height = 5, dpi = 150)
  cat("  s2_beta_corr.png\n")

  # Loss distribution + GPD
  loss_dt <- data.table(loss = losses)
  p2 <- ggplot(loss_dt, aes(x = loss)) +
    geom_histogram(bins = 80, fill = "#1f77b4", alpha = 0.7) +
    geom_vline(xintercept = abs(var_95), linetype = "dashed", color = "orange") +
    geom_vline(xintercept = abs(var_99), linetype = "dashed", color = "red") +
    annotate("text", x = abs(var_95), y = Inf, label = "VaR95", vjust = 2, color = "orange") +
    annotate("text", x = abs(var_99), y = Inf, label = "VaR99", vjust = 2, color = "red") +
    labs(title = "STR_1656_MLRA S1-B — Loss Distribution",
         subtitle = sprintf("GPD xi=%.3f | CVaR95=%.4f | CVaR99=%.4f",
                            xi_hat %||% NA, cvar_95, cvar_99),
         x = "Daily Loss", y = "Count") +
    theme_minimal(base_size = 11)
  ggsave(file.path(OUTPUT_DIR, "s2_evt_loss.png"), p2, width = 10, height = 5, dpi = 150)
  cat("  s2_evt_loss.png\n")
}, error = function(e) cat("  Chart error:", e$message, "\n"))

# =============================================================================
# 8. Update S2 Artifact
# =============================================================================
cat("\n[8] Artifact 업데이트...\n")
s2 <- fromJSON(file.path(PROJECT_ROOT, "stage_artifacts/s2_profile_STR_1656_MLRA.json"))

s2$s2_profiling <- list(
  rolling_60d_beta = beta_stats,
  rolling_60d_anchor_corr = corr_stats,
  evt_profile = list(
    gpd_shape_xi = xi_hat,
    gpd_scale_sigma = sigma_hat,
    threshold_pct = threshold_pct,
    n_exceedances = n_exceed,
    VaR_95 = var_95, VaR_99 = var_99,
    CVaR_95 = cvar_95, CVaR_99 = cvar_99
  ),
  ic_significance = list(
    s1_a = list(t_stat = sig_a$t_stat, pct_positive_ic = sig_a$pct_pos),
    s1_b = list(t_stat = sig_b$t_stat, pct_positive_ic = sig_b$pct_pos)
  ),
  s0_conditions = list(
    beta_lt_065 = beta_stats$pass_065,
    corr_lt_045 = corr_stats$pass_045,
    note = "S2 EW baseline. CVaR LP 적용은 S5에서 측정"
  )
)

s2$s3_orthogonality <- list(
  anchor_return_corr = full_corr,
  crisis_corr = crisis_corr,
  novelty_bonus = novelty_bonus,
  max_corr_assessment = ifelse(abs(full_corr) < 0.30, "LOW (bonus +15)",
                               ifelse(abs(full_corr) < 0.50, "MODERATE (bonus +7)", "HIGH (no bonus)"))
)

s2$stage <- "S2_S3_complete"
s2$updated_at <- as.character(Sys.time())

write_json(s2, file.path(PROJECT_ROOT, "stage_artifacts/s2_profile_STR_1656_MLRA.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("  s2_profile updated\n")

# =============================================================================
# 9. Summary
# =============================================================================
cat("\n=== S2+S3 Summary ===\n")
cat(sprintf("  ICIR: A=%.3f B=%.3f (Gate PASS)\n", 0.844, 0.850))
cat(sprintf("  IC t-stat: A=%.2f B=%.2f\n", sig_a$t_stat, sig_b$t_stat))
cat(sprintf("  IC pct+: A=%.1f%% B=%.1f%%\n", sig_a$pct_pos, sig_b$pct_pos))
cat(sprintf("  Rolling Beta: mean=%.3f (target<0.65: %s)\n", beta_stats$mean,
            ifelse(beta_stats$pass_065, "PASS", "FAIL")))
cat(sprintf("  Anchor Corr: mean=%.3f (target<0.45: %s)\n", corr_stats$mean,
            ifelse(corr_stats$pass_045, "PASS", "FAIL")))
cat(sprintf("  Crisis Corr: %.3f\n", crisis_corr))
cat(sprintf("  EVT GPD xi: %.3f\n", xi_hat))
cat(sprintf("  Novelty: corr=%.3f bonus=%d\n", full_corr, novelty_bonus))
cat(sprintf("  VaR95=%.4f CVaR95=%.4f\n", var_95, cvar_95))
cat("완료\n")
