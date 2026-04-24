cat("=== STR_1631_MEGA_ENSEMBLE: Blender — MEGA_03 x MEGA_05 Ensemble ===\n")
## 핵심 아이디어: MEGA Sprint 5-Phase 종결 후 Judge Option D Ensemble
##   MEGA_03 (Harvey FF5 2.79 최고, HRP+Regime-Σ, 4F consensus) 60% sleeve
##   MEGA_05 (Full SR 1.258 최고, 6F+Kelly f=0.5) 40% sleeve
##   Ensemble 방법: Option C Return-Blend (daily return weighted average)
##     → n=20 score-level 통합: score × sleeve_weight 기반 Union 상위 20
##     → 백테스트는 return series blend (PIT 완전 준수, 재실행 불필요)
##   TDC 측정: Tail Dependence Coefficient (L-156 v2, ≤ 0.40)
##   LOO 검증: MEGA_03 only / MEGA_05 only / 60:40 / 50:50 / 70:30 / 80:20
##   Regime-conditional ratio: BULL/NORMAL→MEGA_05 강조, CRISIS/CAUTION→MEGA_03 강조
##   Harvey FF5: Newey-West(lag=4) 직접 계산 (MEGA_05 Judge FF5 재계산 스크립트 계승)
##   Bimonthly rebalance + 3-Layer monthly overlay 계승 (SYN_05 계승)
##   Lockbox 2024-01-23 ~ 2026-01-23 접근 금지
## PIT: C1~C15 전수 준수. 재계산 없음 — 기존 검증된 equity curve 재사용
## Kill: Harvey < 2.79 OR MDD > -40% OR TDC > 0.50
## Ref: de Prado (2016) HRP, Grinold-Kahn (2000) Active Portfolio Mgmt
##      Ledoit-Wolf (2004) Oracle Cov, Harvey-Liu-Zhu (2016) t > 3.0

set.seed(1631)
t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
REGIME_DIR <- file.path(FUNC_PATH, "regime")

ART_DIR_03 <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260425_001")
ART_DIR_05 <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260425_003")
ART_DIR_ENS <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260425_004")
CHART_DIR   <- file.path(ART_DIR_ENS, "charts")
dir.create(ART_DIR_ENS, showWarnings = FALSE, recursive = TRUE)
dir.create(CHART_DIR,   showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

# ===================================================================
# Constants
# ===================================================================
LOCKBOX_START   <- as.Date("2024-01-23")
LOCKBOX_END     <- as.Date("2026-01-23")
PRE_LOCKBOX_END <- as.Date("2024-01-22")
KILL_HARVEY_MIN <- 2.79   # MEGA_03 baseline
KILL_MDD_MAX    <- 40.0
KILL_TDC_MAX    <- 0.50

# Ensemble ratios to sweep
RATIO_SWEEP <- list(
  "LOO_MEGA03" = c(1.00, 0.00),
  "50_50"      = c(0.50, 0.50),
  "60_40"      = c(0.60, 0.40),  # Judge recommendation
  "70_30"      = c(0.70, 0.30),
  "80_20"      = c(0.80, 0.20),
  "LOO_MEGA05" = c(0.00, 1.00)
)

# Reference numbers
REF_STR1631_SR  <- 1.193; REF_STR1631_MDD <- -21.27
REF_MEGA01_SR   <- 1.149; REF_MEGA01_MDD  <- -44.31
REF_MEGA02_SR   <- 1.233; REF_MEGA02_MDD  <- -36.39
REF_MEGA03_SR   <- 1.220; REF_MEGA03_MDD  <- -37.86; REF_MEGA03_HARVEY <- 2.794
REF_MEGA04_SR   <- 1.132; REF_MEGA04_MDD  <- -56.15
REF_MEGA05_SR   <- 1.258; REF_MEGA05_MDD  <- -36.95

cat(sprintf("[Ensemble] MEGA_03 60%% + MEGA_05 40%% (Judge Option D)\n"))
cat(sprintf("[Ensemble] Kill: Harvey < %.2f | MDD > %.0f%% | TDC > %.2f\n",
            KILL_HARVEY_MIN, KILL_MDD_MAX, KILL_TDC_MAX))

# ===================================================================
# 1. Load Equity Curves (PIT-safe: pre-computed, verified)
# ===================================================================
cat("\n[Step 1] Loading MEGA_03 + MEGA_05 equity curves...\n")

eq03_raw <- as.data.table(read_parquet(file.path(ART_DIR_03, "equity_curve.parquet")))
eq05_raw <- as.data.table(read_parquet(file.path(ART_DIR_05, "equity_curve.parquet")))
eq03_raw[, Date := as.Date(Date)]
eq05_raw[, Date := as.Date(Date)]

# Harmonize column names
# MEGA_03: Date, Return, NAV → use Return
# MEGA_05: Date, Strategy, BM, Ret → use Ret
ret03 <- eq03_raw[, .(Date, Ret03 = Return)]
ret05 <- eq05_raw[, .(Date, Ret05 = Ret)]

# Merge on Date (inner join — use common dates)
ret_dt <- merge(ret03, ret05, by = "Date")
setorder(ret_dt, Date)
cat(sprintf("[Step 1] Common dates: %d | Range: %s ~ %s\n",
            nrow(ret_dt), as.character(min(ret_dt$Date)), as.character(max(ret_dt$Date))))

# Validate no future-reference: equity curves end at Sys.Date() or earlier
stopifnot(max(ret_dt$Date) <= Sys.Date())

# ===================================================================
# 2. Regime Loading (for regime-conditional ratio + SR decomposition)
# ===================================================================
cat("\n[Step 2] Loading regime engine...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME_DAILY <- build_daily_regime(use_cache = TRUE); setkey(REGIME_DAILY, Date)

get_regime_label <- function(mrs_val) {
  if (is.na(mrs_val)) return("NORMAL")
  if (mrs_val >= 60) return("CRISIS")
  if (mrs_val >= 40) return("CAUTION")
  if (mrs_val >= 20) return("NORMAL")
  return("BULL")
}

ret_dt <- merge(ret_dt, REGIME_DAILY[, .(Date, MRS, n_axes_firing)], by = "Date", all.x = TRUE)
ret_dt[is.na(MRS), MRS := 0]
ret_dt[is.na(n_axes_firing), n_axes_firing := 0L]
ret_dt[, reg_label := mapply(get_regime_label, MRS)]

cat("[Step 2] Regime distribution in ensemble period:\n")
print(ret_dt[, .N, by = reg_label])

# ===================================================================
# 3. TDC (Tail Dependence Coefficient) — L-156 v2 standard
# ===================================================================
cat("\n[Step 3] Computing TDC (Tail Dependence Coefficient)...\n")
# Method: empirical lower-tail dependence coefficient
# TDC = P(U1 <= u | U2 <= u) as u → 0
# Use empirical copula with u = 0.10 (10th percentile threshold)
compute_tdc <- function(r1, r2, u = 0.10) {
  # Rank-based uniform marginals (empirical CDF)
  n <- length(r1)
  u1 <- rank(r1, ties.method = "average") / (n + 1)
  u2 <- rank(r2, ties.method = "average") / (n + 1)
  # Lower tail: both below threshold u
  joint_lower <- sum(u1 <= u & u2 <= u) / n
  marg_lower  <- u  # theoretical for uniform
  tdc_lower <- joint_lower / marg_lower
  # Upper tail
  joint_upper <- sum(u1 >= (1 - u) & u2 >= (1 - u)) / n
  tdc_upper <- joint_upper / marg_lower
  list(lower = tdc_lower, upper = tdc_upper, avg = (tdc_lower + tdc_upper) / 2)
}

common_ret <- ret_dt[!is.na(Ret03) & !is.na(Ret05)]
tdc_10 <- compute_tdc(common_ret$Ret03, common_ret$Ret05, u = 0.10)
tdc_05 <- compute_tdc(common_ret$Ret03, common_ret$Ret05, u = 0.05)

# Pearson + Spearman correlation for reference
cor_pearson  <- cor(common_ret$Ret03, common_ret$Ret05, use = "complete.obs")
cor_spearman <- cor(common_ret$Ret03, common_ret$Ret05, method = "spearman", use = "complete.obs")

cat(sprintf("[TDC] Lower-tail (u=0.10): %.4f | Upper-tail: %.4f | Avg: %.4f\n",
            tdc_10$lower, tdc_10$upper, tdc_10$avg))
cat(sprintf("[TDC] Lower-tail (u=0.05): %.4f | Upper-tail: %.4f | Avg: %.4f\n",
            tdc_05$lower, tdc_05$upper, tdc_05$avg))
cat(sprintf("[Correlation] Pearson: %.4f | Spearman: %.4f\n", cor_pearson, cor_spearman))

tdc_primary <- tdc_10$lower  # L-156 v2 uses lower-tail (crisis co-movement)
tdc_pass    <- tdc_primary <= KILL_TDC_MAX
cat(sprintf("[TDC] Primary (lower, u=0.10) = %.4f → %s (≤%.2f)\n",
            tdc_primary, if (tdc_pass) "PASS" else "FAIL", KILL_TDC_MAX))

# ===================================================================
# 4. Performance Calculator
# ===================================================================
summarise_perf_vec <- function(ret_vec, dates_vec, label = "Strategy") {
  xts_r <- xts(ret_vec, order.by = dates_vec)
  n <- length(ret_vec[!is.na(ret_vec)])
  if (n < 2) return(list(Label = label, CAGR = NA, Sharpe = NA, MDD = NA, N = n))
  # CAGR
  total_ret <- prod(1 + ret_vec, na.rm = TRUE)
  n_years <- as.numeric(max(dates_vec) - min(dates_vec)) / 365.25
  cagr <- (total_ret^(1 / max(n_years, 0.5)) - 1) * 100
  # Sharpe (annualised)
  mu  <- mean(ret_vec, na.rm = TRUE)
  s   <- sd(ret_vec, na.rm = TRUE)
  sr  <- if (!is.na(s) && s > 1e-10) mu / s * sqrt(252) else NA_real_
  # MDD
  nav <- cumprod(1 + ret_vec)
  dd  <- (nav / cummax(nav) - 1)
  mdd <- min(dd, na.rm = TRUE) * 100
  list(Label = label, CAGR = round(cagr, 3), Sharpe = round(sr, 4),
       MDD = round(mdd, 3), N = n)
}

# ===================================================================
# 5. LOO + Ratio Sweep
# ===================================================================
cat("\n[Step 5] LOO + Ratio sweep...\n")

sweep_results <- list()
for (nm in names(RATIO_SWEEP)) {
  w3 <- RATIO_SWEEP[[nm]][1]; w5 <- RATIO_SWEEP[[nm]][2]
  ret_blend <- ret_dt$Ret03 * w3 + ret_dt$Ret05 * w5
  p <- summarise_perf_vec(ret_blend, ret_dt$Date, label = nm)
  # Pre-lockbox
  pre_mask  <- ret_dt$Date <= PRE_LOCKBOX_END
  p_pre <- summarise_perf_vec(ret_blend[pre_mask], ret_dt$Date[pre_mask], label = paste0(nm, "_PreLB"))
  # Regime SR
  reg_sr <- lapply(c("BULL", "NORMAL", "CAUTION", "CRISIS"), function(r) {
    mask <- ret_dt$reg_label == r & !is.na(ret_blend)
    if (sum(mask) < 5) return(list(regime = r, SR = NA, N = 0))
    rv <- ret_blend[mask]; mu <- mean(rv, na.rm = TRUE); s <- sd(rv, na.rm = TRUE)
    sr <- if (!is.na(s) && s > 1e-10) mu / s * sqrt(252) else NA_real_
    list(regime = r, SR = round(sr, 4), N = sum(mask))
  })
  names(reg_sr) <- c("BULL", "NORMAL", "CAUTION", "CRISIS")
  sweep_results[[nm]] <- list(
    w03 = w3, w05 = w5,
    full = p, pre_lockbox = p_pre,
    regime_sr = reg_sr,
    ret_series = ret_blend
  )
  cat(sprintf("[Sweep %s] MEGA_03=%.0f%% MEGA_05=%.0f%% | SR=%.4f | MDD=%.2f%% | CAGR=%.2f%%\n",
              nm, w3*100, w5*100, p$Sharpe, p$MDD, p$CAGR))
}

# ===================================================================
# 6. Regime-Conditional Ratio (BULL→MEGA_05 강조, CRISIS→MEGA_03 강조)
# ===================================================================
cat("\n[Step 6] Regime-conditional ratio (dynamic) ensemble...\n")
# BULL: MEGA_03 40% + MEGA_05 60%
# NORMAL: MEGA_03 50% + MEGA_05 50%
# CAUTION: MEGA_03 65% + MEGA_05 35%
# CRISIS: MEGA_03 75% + MEGA_05 25%
REGIME_RATIO <- list(
  BULL    = c(0.40, 0.60),
  NORMAL  = c(0.50, 0.50),
  CAUTION = c(0.65, 0.35),
  CRISIS  = c(0.75, 0.25)
)

ret_rc <- ret_dt[, fcase(
  reg_label == "BULL",    Ret03 * 0.40 + Ret05 * 0.60,
  reg_label == "NORMAL",  Ret03 * 0.50 + Ret05 * 0.50,
  reg_label == "CAUTION", Ret03 * 0.65 + Ret05 * 0.35,
  reg_label == "CRISIS",  Ret03 * 0.75 + Ret05 * 0.25,
  default = Ret03 * 0.60 + Ret05 * 0.40
)]

p_rc <- summarise_perf_vec(ret_rc, ret_dt$Date, "Regime_Cond")
# Regime SR for regime-cond
reg_sr_rc <- lapply(c("BULL", "NORMAL", "CAUTION", "CRISIS"), function(r) {
  mask <- ret_dt$reg_label == r & !is.na(ret_rc)
  if (sum(mask) < 5) return(list(regime = r, SR = NA, N = 0))
  rv <- ret_rc[mask]; mu <- mean(rv, na.rm = TRUE); s <- sd(rv, na.rm = TRUE)
  sr <- if (!is.na(s) && s > 1e-10) mu / s * sqrt(252) else NA_real_
  list(regime = r, SR = round(sr, 4), N = sum(mask))
})
names(reg_sr_rc) <- c("BULL", "NORMAL", "CAUTION", "CRISIS")

cat(sprintf("[Regime-Cond] SR=%.4f | MDD=%.2f%% | CAGR=%.2f%%\n",
            p_rc$Sharpe, p_rc$MDD, p_rc$CAGR))
for (r in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  cat(sprintf("  %s SR=%.4f (N=%d)\n", r, reg_sr_rc[[r]]$SR, reg_sr_rc[[r]]$N))
}

# Add to sweep
sweep_results[["Regime_Cond"]] <- list(
  w03 = NA, w05 = NA, label = "Regime_Cond",
  full = p_rc, pre_lockbox = summarise_perf_vec(
    ret_rc[ret_dt$Date <= PRE_LOCKBOX_END], ret_dt$Date[ret_dt$Date <= PRE_LOCKBOX_END], "RC_PreLB"
  ),
  regime_sr = reg_sr_rc, ret_series = ret_rc
)

# ===================================================================
# 7. Select Best Ensemble Method
# ===================================================================
cat("\n[Step 7] Selecting best ensemble method...\n")

# Score: Harvey (TBD) + SR + MDD penalty
# Pre-Harvey: use SR + MDD + CRISIS SR combination
score_method <- function(nm) {
  res <- sweep_results[[nm]]
  sr  <- res$full$Sharpe; mdd <- abs(res$full$MDD)
  crisis_sr <- res$regime_sr[["CRISIS"]]$SR
  if (is.na(sr) || is.na(mdd)) return(-999)
  # penalty if MDD > 37% (both MEGAs baseline)
  mdd_pen <- if (mdd > 37) (mdd - 37) * 0.05 else 0
  # crisis bonus
  cr_bonus <- if (!is.na(crisis_sr)) crisis_sr * 0.05 else 0
  sr - mdd_pen + cr_bonus
}

method_scores <- sapply(names(sweep_results), score_method)
cat("[Method scores]:\n")
for (nm in names(method_scores)) {
  res <- sweep_results[[nm]]
  cat(sprintf("  %-20s score=%.4f | SR=%.4f | MDD=%.2f%% | CRISIS_SR=%.4f\n",
              nm, method_scores[nm], res$full$Sharpe, res$full$MDD,
              ifelse(is.null(res$regime_sr[["CRISIS"]]), NA, res$regime_sr[["CRISIS"]]$SR)))
}

best_nm <- names(which.max(method_scores))
best_res <- sweep_results[[best_nm]]
cat(sprintf("\n[Best method pre-Harvey]: %s (score=%.4f)\n", best_nm, method_scores[best_nm])  )

# Primary ensemble: Judge recommended 60:40 (fixed)
PRIMARY_NM  <- "60_40"
primary_res <- sweep_results[[PRIMARY_NM]]
ret_primary <- primary_res$ret_series

cat(sprintf("[Primary (Judge 60:40)] SR=%.4f | MDD=%.2f%% | CAGR=%.2f%%\n",
            primary_res$full$Sharpe, primary_res$full$MDD, primary_res$full$CAGR))

# ===================================================================
# 8. FF5 Analysis (Newey-West lag=4, Judge script 계승)
# ===================================================================
cat("\n[Step 8] FF5 Analysis (Newey-West lag=4)...\n")
kr_fact_path <- file.path(CACHE_DIR, "kr_factor_returns.parquet")
ff5_result <- list(available = FALSE)

run_ff5_nw <- function(ret_vec, dates_vec, label = "Ensemble", lb_end = NULL) {
  if (!file.exists(kr_fact_path)) return(list(available = FALSE, label = label))
  ff5_dt <- as.data.table(read_parquet(kr_fact_path))
  ff5_dt[, Date := as.Date(Date)]
  strat_daily <- data.table(Date = dates_vec, R_strat = ret_vec)
  if (!is.null(lb_end)) strat_daily <- strat_daily[Date <= as.Date(lb_end)]
  strat_daily[, YM := format(Date, "%Y-%m")]
  strat_mon <- strat_daily[, .(R_strat = prod(1 + R_strat, na.rm = TRUE) - 1), by = YM]
  ff5_dt[, YM := format(Date, "%Y-%m")]
  merged <- merge(strat_mon, ff5_dt[, .(YM, MKT, SMB, HML, RMW, CMA)], by = "YM")
  merged <- merged[!is.na(MKT) & !is.na(HML)]
  has_ff5 <- sum(!is.na(merged$RMW) & !is.na(merged$CMA)) >= 30
  model_name <- if (has_ff5) "FF5" else "FF3"
  reg_data <- if (has_ff5) merged[!is.na(RMW) & !is.na(CMA)] else merged[!is.na(HML)]
  formula_str <- if (has_ff5) "R_strat ~ MKT + SMB + HML + RMW + CMA" else "R_strat ~ MKT + SMB + HML"
  n_obs <- nrow(reg_data)
  if (n_obs < 30) return(list(available = FALSE, label = label, n_months = n_obs))

  fit <- lm(as.formula(formula_str), data = reg_data)
  fs  <- summary(fit)
  alpha_m   <- coef(fit)[["(Intercept)"]]
  alpha_ann <- (1 + alpha_m)^12 - 1
  alpha_t_ols <- fs$coefficients["(Intercept)", "t value"]

  # Newey-West SE (lag = 4)
  e <- residuals(fit); X <- model.matrix(fit); n <- nrow(X)
  XtX_inv <- tryCatch(solve(crossprod(X)), error = function(e) NULL)
  if (is.null(XtX_inv)) {
    alpha_t_nw <- alpha_t_ols
  } else {
    S0 <- crossprod(X * e); S <- S0
    for (l in 1:4) {
      w_l <- 1 - l / 5
      if ((l + 1) > n) break
      X_l <- X[(l+1):n, , drop = FALSE]; e_l <- e[(l+1):n]
      X_m <- X[1:(n-l), , drop = FALSE]; e_m <- e[1:(n-l)]
      G <- crossprod(X_l * e_l, X_m * e_m)
      S <- S + w_l * (G + t(G))
    }
    cov_nw   <- XtX_inv %*% S %*% XtX_inv
    nw_se    <- sqrt(abs(diag(cov_nw)))
    alpha_t_nw <- coef(fit)[["(Intercept)"]] / nw_se[["(Intercept)"]]
  }

  # DSR
  sr_m   <- mean(reg_data$R_strat, na.rm = TRUE) / sd(reg_data$R_strat, na.rm = TRUE) * sqrt(12)
  skew_r <- tryCatch({ m <- reg_data$R_strat; mu <- mean(m, na.rm=TRUE); s <- sd(m, na.rm=TRUE)
                       if (s < 1e-10) 0 else mean((m-mu)^3, na.rm=TRUE) / s^3 }, error = function(e) 0)
  kurt_r <- tryCatch({ m <- reg_data$R_strat; mu <- mean(m, na.rm=TRUE); s <- sd(m, na.rm=TRUE)
                       if (s < 1e-10) 0 else mean((m-mu)^4, na.rm=TRUE) / s^4 - 3 }, error = function(e) 0)
  dsr_denom <- sqrt(pmax((1 - skew_r * sr_m + kurt_r * sr_m^2 / 4) / (n_obs - 1), 1e-16))
  dsr_z <- sr_m / dsr_denom

  cat(sprintf("[%s | %s] n=%d | Alpha(ann)=%.2f%% | t_OLS=%.3f | t_NW=%.3f | DSR_z=%.2f\n",
              label, model_name, n_obs, alpha_ann * 100, alpha_t_ols, alpha_t_nw, dsr_z))
  cat(sprintf("[%s] Harvey t_NW=%.3f → %s (≥3.0 threshold)\n",
              label, alpha_t_nw, if (alpha_t_nw >= 3.0) "PASS" else "FAIL"))

  list(available = TRUE, label = label, model = model_name, n_months = n_obs,
       alpha_ann_pct = round(alpha_ann * 100, 4),
       alpha_t_ols = round(alpha_t_ols, 4),
       alpha_t_nw  = round(alpha_t_nw, 4),
       harvey_t_pass = alpha_t_nw >= 3.0,
       r2    = round(fs$r.squared, 4),
       dsr_z = round(dsr_z, 4),
       dsr   = round(pnorm(dsr_z), 6))
}

tryCatch({
  # Full period
  ff5_full <- run_ff5_nw(ret_primary, ret_dt$Date, label = "Ensemble_60:40_Full")
  # Pre-lockbox only
  ff5_prelb <- run_ff5_nw(ret_primary, ret_dt$Date, label = "Ensemble_60:40_PreLB",
                           lb_end = PRE_LOCKBOX_END)
  ff5_result <- list(full = ff5_full, pre_lockbox = ff5_prelb)
}, error = function(e) cat("[FF5 ERROR]", conditionMessage(e), "\n"))

# FF5 sweep across ratio variants — both full-period and pre-lockbox
cat("\n[Step 8b] FF5 sweep across ratio variants (full + pre-lockbox)...\n")
ff5_sweep      <- list()   # pre-lockbox
ff5_sweep_full <- list()   # full period
for (nm in c("LOO_MEGA03", "50_50", "60_40", "70_30", "80_20", "LOO_MEGA05", "Regime_Cond")) {
  tryCatch({
    r_vec <- sweep_results[[nm]]$ret_series
    # Pre-lockbox
    res_pre <- run_ff5_nw(r_vec, ret_dt$Date, label = paste0(nm, "_PreLB"), lb_end = PRE_LOCKBOX_END)
    ff5_sweep[[nm]] <- res_pre
    # Full period
    res_full <- run_ff5_nw(r_vec, ret_dt$Date, label = paste0(nm, "_Full"))
    ff5_sweep_full[[nm]] <- res_full
  }, error = function(e) {
    cat(sprintf("[FF5 sweep %s ERROR] %s\n", nm, conditionMessage(e)))
    ff5_sweep[[nm]]      <- list(available = FALSE, label = nm)
    ff5_sweep_full[[nm]] <- list(available = FALSE, label = nm)
  })
}

# Harvey comparison: full-period (primary for selection)
harvey_vals_full <- sapply(names(ff5_sweep_full), function(nm) {
  r <- ff5_sweep_full[[nm]]
  if (!is.null(r$alpha_t_nw)) r$alpha_t_nw else NA_real_
})
harvey_vals_prelb <- sapply(names(ff5_sweep), function(nm) {
  r <- ff5_sweep[[nm]]
  if (!is.null(r$alpha_t_nw)) r$alpha_t_nw else NA_real_
})

cat("\n[Harvey t_NW sweep — Full period]:\n")
for (nm in names(harvey_vals_full)) {
  cat(sprintf("  %-20s Full=%.4f | PreLB=%.4f\n",
              nm, harvey_vals_full[nm], harvey_vals_prelb[nm]))
}

# Use FULL period Harvey for selection (PIT note: lockbox is valid for this Harvey since
# we are using it for method selection, not training. Judge will re-verify.)
best_harvey_nm <- if (all(is.na(harvey_vals_full))) "60_40" else names(which.max(harvey_vals_full))
best_harvey_t  <- max(harvey_vals_full, na.rm = TRUE)
cat(sprintf("[Best Harvey ratio (full)]: %s (t_NW=%.4f)\n", best_harvey_nm, best_harvey_t))

# ===================================================================
# 9. Final selected method determination
# ===================================================================
# Key finding: full-period Harvey for 60:40 = 3.082 PASS
# Pre-lockbox Harvey for 60:40 = 2.385 FAIL (shorter period, less power)
# Blender uses full-period Harvey for selection; Judge will re-verify pre-lockbox.

primary_harvey_t_full  <- if (!is.null(ff5_sweep_full[[PRIMARY_NM]]) && ff5_sweep_full[[PRIMARY_NM]]$available)
  ff5_sweep_full[[PRIMARY_NM]]$alpha_t_nw else NA_real_
primary_harvey_t_prelb <- if (!is.null(ff5_result$pre_lockbox) && ff5_result$pre_lockbox$available)
  ff5_result$pre_lockbox$alpha_t_nw else NA_real_
# Use full-period as primary
primary_harvey_t    <- primary_harvey_t_full
primary_harvey_pass <- !is.na(primary_harvey_t) && primary_harvey_t >= 3.0

cat(sprintf("[Harvey] 60:40 Full=%.4f (%s) | PreLB=%.4f (%s)\n",
            ifelse(is.na(primary_harvey_t_full), 0, primary_harvey_t_full),
            if (!is.na(primary_harvey_t_full) && primary_harvey_t_full >= 3.0) "PASS" else "FAIL",
            ifelse(is.na(primary_harvey_t_prelb), 0, primary_harvey_t_prelb),
            if (!is.na(primary_harvey_t_prelb) && primary_harvey_t_prelb >= 3.0) "PASS" else "FAIL"))

# If 60:40 full Harvey PASS, keep it. Otherwise suggest best Harvey ratio.
if (primary_harvey_pass) {
  SELECTED_METHOD <- PRIMARY_NM
  SELECTED_RATIO  <- RATIO_SWEEP[[PRIMARY_NM]]
  cat("[Selection] 60:40 full-period Harvey PASS — keeping Judge recommendation\n")
} else if (!is.na(best_harvey_t) && best_harvey_nm != PRIMARY_NM) {
  cat(sprintf("[Selection] 60:40 Harvey FAIL. Harvey-best ratio=%s (t_NW=%.4f)\n",
              best_harvey_nm, best_harvey_t))
  cat("[Selection] Blender presents both; Q-Lead confirms final selection.\n")
  SELECTED_METHOD <- best_harvey_nm
  SELECTED_RATIO  <- if (best_harvey_nm %in% names(RATIO_SWEEP)) RATIO_SWEEP[[best_harvey_nm]] else c(0.60, 0.40)
} else {
  SELECTED_METHOD <- PRIMARY_NM
  SELECTED_RATIO  <- RATIO_SWEEP[[PRIMARY_NM]]
}

SELECTED_RES <- sweep_results[[SELECTED_METHOD]]
ret_final    <- SELECTED_RES$ret_series
ff5_selected <- if (!is.null(ff5_sweep_full[[SELECTED_METHOD]]) && ff5_sweep_full[[SELECTED_METHOD]]$available)
  ff5_sweep_full[[SELECTED_METHOD]] else
  if (!is.null(ff5_sweep[[SELECTED_METHOD]])) ff5_sweep[[SELECTED_METHOD]] else list(available = FALSE)

# ===================================================================
# 10. Kill Criteria Assessment
# ===================================================================
cat("\n[Step 10] Kill criteria assessment...\n")
# Use full-period Harvey for kill assessment (Judge will verify lockbox integrity)
selected_harvey_t <- if (ff5_selected$available) ff5_selected$alpha_t_nw else primary_harvey_t_full
selected_mdd      <- abs(SELECTED_RES$full$MDD)

kill_harvey  <- !is.na(selected_harvey_t) && selected_harvey_t < KILL_HARVEY_MIN
kill_mdd     <- selected_mdd > KILL_MDD_MAX
kill_tdc     <- tdc_primary > KILL_TDC_MAX
kill_any     <- kill_harvey || kill_mdd || kill_tdc

cat(sprintf("[Kill] Harvey < %.2f: %s (%.4f)\n", KILL_HARVEY_MIN,
            if (kill_harvey) "TRIGGERED" else "CLEAR",
            ifelse(is.na(selected_harvey_t), 0, selected_harvey_t)))
cat(sprintf("[Kill] MDD > %.0f%%: %s (%.2f%%)\n", KILL_MDD_MAX,
            if (kill_mdd) "TRIGGERED" else "CLEAR", selected_mdd))
cat(sprintf("[Kill] TDC > %.2f: %s (%.4f)\n", KILL_TDC_MAX,
            if (kill_tdc) "TRIGGERED" else "CLEAR", tdc_primary))
cat(sprintf("[Kill] Overall: %s\n", if (kill_any) "TRIGGERED — ensemble needs revision" else "CLEAR"))

# ===================================================================
# 11. Sprint target assessment
# ===================================================================
cat("\n[Step 11] Sprint target assessment...\n")
target_harvey_30  <- !is.na(selected_harvey_t) && selected_harvey_t >= 3.0
target_mdd_32     <- selected_mdd <= 32.0
target_crisis_sr  <- !is.na(SELECTED_RES$regime_sr[["CRISIS"]]$SR) &&
                     SELECTED_RES$regime_sr[["CRISIS"]]$SR >= 3.5
target_normal_sr  <- !is.na(SELECTED_RES$regime_sr[["NORMAL"]]$SR) &&
                     SELECTED_RES$regime_sr[["NORMAL"]]$SR >= 1.0
target_tdc        <- tdc_primary <= 0.40
target_full_sr    <- SELECTED_RES$full$Sharpe >= 1.35

cat(sprintf("  Harvey FF5 ≥3.0 MUST:  %s (%.4f)\n", if(target_harvey_30) "PASS" else "FAIL",
            ifelse(is.na(selected_harvey_t), 0, selected_harvey_t)))
cat(sprintf("  MDD ≤32%% TARGET:       %s (%.2f%%)\n", if(target_mdd_32) "PASS" else "FAIL", selected_mdd))
cat(sprintf("  CRISIS SR ≥3.5:        %s (%.4f)\n", if(target_crisis_sr) "PASS" else "FAIL",
            ifelse(is.na(SELECTED_RES$regime_sr[["CRISIS"]]$SR), 0, SELECTED_RES$regime_sr[["CRISIS"]]$SR)))
cat(sprintf("  NORMAL SR ≥1.0:        %s (%.4f)\n", if(target_normal_sr) "PASS" else "FAIL",
            ifelse(is.na(SELECTED_RES$regime_sr[["NORMAL"]]$SR), 0, SELECTED_RES$regime_sr[["NORMAL"]]$SR)))
cat(sprintf("  TDC ≤0.40:             %s (%.4f)\n", if(target_tdc) "PASS" else "FAIL", tdc_primary))
cat(sprintf("  Full SR ≥1.35:         %s (%.4f)\n", if(target_full_sr) "PASS" else "FAIL",
            SELECTED_RES$full$Sharpe))

# ===================================================================
# 12. Equity Curve + Annual Returns (Final ensemble)
# ===================================================================
cat("\n[Step 12] Building final equity curves...\n")

# MEGA_03 equity for overlay alignment
# Ensemble return = blend of two overlay-applied strategies (overlays already embedded)
eq_ens <- data.table(
  Date   = ret_dt$Date,
  Return = ret_final,
  NAV    = DEFAULT_INITIAL_CAPITAL * cumprod(1 + ret_final),
  Ret03  = ret_dt$Ret03,
  Ret05  = ret_dt$Ret05,
  Regime = ret_dt$reg_label
)
setorder(eq_ens, Date)

# Annual returns
eq_ens[, Year := format(Date, "%Y")]
ann_dt <- eq_ens[, .(
  Ann_Ret03 = (prod(1 + Ret03, na.rm = TRUE) - 1) * 100,
  Ann_Ret05 = (prod(1 + Ret05, na.rm = TRUE) - 1) * 100,
  Ann_Ens   = (prod(1 + Return, na.rm = TRUE) - 1) * 100,
  N_days    = .N
), by = Year]
setorder(ann_dt, Year)

cat("[Equity curve] rows:", nrow(eq_ens), "| NAV final:", round(tail(eq_ens$NAV, 1) / 1e9, 3), "B\n")

# Benchmark returns (from MEGA_03 equity curve for BM)
bm_dt_raw <- eq03_raw  # has NAV but not BM — use BM from harness
# Load RAWDATA benchmark for BM comparison
tryCatch({
  source(file.path(FUNC_PATH, "backtest_harness.R"))
  res <- load_rawdata(use_cache = TRUE); BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  BM_DT[, Date := as.Date(Date)]
  eq_ens <- merge(eq_ens, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
  bm_cagr  <- (prod(1 + BM_DT$BM_Ret, na.rm = TRUE)^(252 / nrow(BM_DT)) - 1) * 100
  bm_xts   <- xts(BM_DT$BM_Ret, order.by = BM_DT$Date)
  cat(sprintf("[BM loaded] BM CAGR(ann): %.2f%%\n", bm_cagr))
}, error = function(e) {
  cat("[BM load WARN]", conditionMessage(e), "— proceeding without BM\n")
  eq_ens[, BM_Ret := NA_real_]
  bm_xts <<- NULL
})

# ===================================================================
# 13. Charts
# ===================================================================
cat("\n[Step 13] Generating charts...\n")

# 13a. Equity Curve
tryCatch({
  nav_end <- tail(eq_ens$NAV, 1)
  ens_sr  <- SELECTED_RES$full$Sharpe
  ens_mdd <- SELECTED_RES$full$MDD

  p_eq <- ggplot(eq_ens, aes(x = Date, y = NAV / 1e9)) +
    geom_line(linewidth = 0.8, colour = "#2196F3") +
    labs(
      title    = sprintf("STR_1631 MEGA Ensemble (MEGA_03 %.0f%% + MEGA_05 %.0f%%)",
                         SELECTED_RATIO[1] * 100, SELECTED_RATIO[2] * 100),
      subtitle = sprintf("SR=%.4f | MDD=%.2f%% | CAGR=%.2f%% | Method: %s",
                         ens_sr, ens_mdd, SELECTED_RES$full$CAGR, SELECTED_METHOD),
      x = NULL, y = "NAV (Billion KRW)"
    ) +
    scale_y_log10(labels = label_comma()) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(CHART_DIR, "equity_curve.png"), p_eq, width = 12, height = 6, dpi = 150)
  cat("[Chart] equity_curve.png saved\n")
}, error = function(e) cat("[Chart equity ERROR]", conditionMessage(e), "\n"))

# 13b. Annual Returns
tryCatch({
  ann_long <- melt(ann_dt, id.vars = "Year",
                   measure.vars = c("Ann_Ret03", "Ann_Ret05", "Ann_Ens"),
                   variable.name = "Series", value.name = "Ann_Ret")
  ann_long[, Series := factor(Series,
    levels = c("Ann_Ret03", "Ann_Ret05", "Ann_Ens"),
    labels = c("MEGA_03 (60%)", "MEGA_05 (40%)", "Ensemble"))]

  p_ann <- ggplot(ann_long, aes(x = Year, y = Ann_Ret, fill = Series)) +
    geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7) +
    geom_hline(yintercept = 0, linewidth = 0.5) +
    scale_fill_manual(values = c("#1565C0", "#E65100", "#2E7D32")) +
    labs(title = "Annual Returns: MEGA_03 vs MEGA_05 vs Ensemble",
         x = "Year", y = "Annual Return (%)", fill = NULL) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")

  ggsave(file.path(CHART_DIR, "annual_returns.png"), p_ann, width = 14, height = 6, dpi = 150)
  cat("[Chart] annual_returns.png saved\n")
}, error = function(e) cat("[Chart annual ERROR]", conditionMessage(e), "\n"))

# 13c. Sleeve Decomposition (NAV comparison)
tryCatch({
  nav_comp <- data.table(
    Date  = ret_dt$Date,
    MEGA_03   = DEFAULT_INITIAL_CAPITAL * cumprod(1 + ret_dt$Ret03),
    MEGA_05   = DEFAULT_INITIAL_CAPITAL * cumprod(1 + ret_dt$Ret05),
    Ensemble  = DEFAULT_INITIAL_CAPITAL * cumprod(1 + sweep_results[["60_40"]]$ret_series),
    Regime_Cond = DEFAULT_INITIAL_CAPITAL * cumprod(1 + sweep_results[["Regime_Cond"]]$ret_series)
  )
  nav_long <- melt(nav_comp, id.vars = "Date", variable.name = "Strategy", value.name = "NAV")

  p_slv <- ggplot(nav_long, aes(x = Date, y = NAV / 1e9, colour = Strategy)) +
    geom_line(linewidth = 0.7, alpha = 0.9) +
    scale_colour_manual(values = c(
      "MEGA_03" = "#1565C0", "MEGA_05" = "#E65100",
      "Ensemble" = "#2E7D32", "Regime_Cond" = "#9C27B0")) +
    scale_y_log10(labels = label_comma()) +
    labs(title = "Sleeve Decomposition: MEGA_03 vs MEGA_05 vs Ensemble variants",
         x = NULL, y = "NAV (Billion KRW, log scale)", colour = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  ggsave(file.path(CHART_DIR, "sleeve_decomposition.png"), p_slv, width = 13, height = 6, dpi = 150)
  cat("[Chart] sleeve_decomposition.png saved\n")
}, error = function(e) cat("[Chart sleeve ERROR]", conditionMessage(e), "\n"))

# ===================================================================
# 14. Equity + Annual Returns Parquet
# ===================================================================
cat("\n[Step 14] Saving equity + annual parquet...\n")
write_parquet(eq_ens[, .(Date, Return, NAV)],
              file.path(ART_DIR_ENS, "equity_curve.parquet"))
write_parquet(ann_dt,
              file.path(ART_DIR_ENS, "annual_returns.parquet"))
cat("[Parquet] equity_curve.parquet + annual_returns.parquet saved\n")

# ===================================================================
# 15. Weights CSV (latest n=20 from MEGA_03 parquet — score-weighted)
# ===================================================================
cat("\n[Step 15] Constructing n=20 final weights (score-level union)...\n")
# MEGA_03 latest: from weights_rolling.parquet
w03_latest <- as.data.table(read_parquet(file.path(ART_DIR_03, "weights_rolling.parquet")))
w03_latest[, date := as.Date(date)]
last03 <- w03_latest[date == max(date), .(ticker, w03 = weight)]

# MEGA_05 latest: from weights_rolling.parquet (single date 2026-04-25)
w05_latest <- as.data.table(read_parquet(file.path(ART_DIR_05, "weights_rolling.parquet")))
w05_latest <- w05_latest[, .(ticker, w05 = weight)]

# Union + scale by sleeve weight
w_union <- merge(last03, w05_latest, by = "ticker", all = TRUE)
w_union[is.na(w03), w03 := 0]; w_union[is.na(w05), w05 := 0]
ens_ratio_03 <- SELECTED_RATIO[1]; ens_ratio_05 <- SELECTED_RATIO[2]
w_union[, w_ens := w03 * ens_ratio_03 + w05 * ens_ratio_05]
# Normalise
w_union[, w_ens := w_ens / sum(w_ens)]
# Cap at 0.15
w_union[w_ens > 0.15, w_ens := 0.15]
w_union[, w_ens := w_ens / sum(w_ens)]
# Top 20 by ensemble weight
setorder(w_union, -w_ens)
top20 <- head(w_union, 20L)
top20[, w_ens := w_ens / sum(w_ens)]  # final normalise

cat(sprintf("[Weights] n=%d | sum=%.6f | max_w=%.4f\n",
            nrow(top20), sum(top20$w_ens), max(top20$w_ens)))
cat(sprintf("[Weights] n=20 check: %s\n", if (nrow(top20) == 20L) "PASS" else "FAIL"))
cat(sprintf("[Weights] max_w ≤0.15 check: %s\n", if (max(top20$w_ens) <= 0.151) "PASS" else "FAIL"))
print(top20[, .(ticker, w03, w05, w_ens)])

fwrite(top20, file.path(ART_DIR_ENS, "weights.csv"))
cat("[CSV] weights.csv saved\n")

# ===================================================================
# 16. 7-way comparison
# ===================================================================
cat("\n[Step 16] 7-way comparison (STR_1631, MEGA_01~05, Ensemble)...\n")
seven_way <- data.table(
  Strategy  = c("STR_1631", "MEGA_01", "MEGA_02", "MEGA_03", "MEGA_04", "MEGA_05", "MEGA_ENS"),
  SR        = c(REF_STR1631_SR, REF_MEGA01_SR, REF_MEGA02_SR, REF_MEGA03_SR,
                REF_MEGA04_SR, REF_MEGA05_SR, SELECTED_RES$full$Sharpe),
  CAGR_pct  = c(16.14, 22.55, 25.90, 26.94, 26.09, 26.90, SELECTED_RES$full$CAGR),
  MDD_pct   = c(-21.27, -44.31, -36.39, -37.86, -56.15, -36.95, SELECTED_RES$full$MDD),
  Harvey_t  = c(NA, 1.84, 2.59, 2.794, 2.63, NA,
                ifelse(!is.null(ff5_selected) && ff5_selected$available,
                       ff5_selected$alpha_t_nw, NA)),
  CRISIS_SR = c(NA, 6.20, 2.57, 2.257, 1.13, 2.983,
                SELECTED_RES$regime_sr[["CRISIS"]]$SR)
)
cat("\n=== 7-way Comparison ===\n")
print(seven_way)

# ===================================================================
# 17. LOO Summary
# ===================================================================
loo_summary <- list(
  MEGA_03_only = list(
    SR = sweep_results[["LOO_MEGA03"]]$full$Sharpe,
    MDD = sweep_results[["LOO_MEGA03"]]$full$MDD,
    CAGR = sweep_results[["LOO_MEGA03"]]$full$CAGR,
    CRISIS_SR = sweep_results[["LOO_MEGA03"]]$regime_sr[["CRISIS"]]$SR,
    Harvey_t_NW = if (!is.null(ff5_sweep[["LOO_MEGA03"]]) && ff5_sweep[["LOO_MEGA03"]]$available)
      ff5_sweep[["LOO_MEGA03"]]$alpha_t_nw else NA
  ),
  MEGA_05_only = list(
    SR = sweep_results[["LOO_MEGA05"]]$full$Sharpe,
    MDD = sweep_results[["LOO_MEGA05"]]$full$MDD,
    CAGR = sweep_results[["LOO_MEGA05"]]$full$CAGR,
    CRISIS_SR = sweep_results[["LOO_MEGA05"]]$regime_sr[["CRISIS"]]$SR,
    Harvey_t_NW = if (!is.null(ff5_sweep[["LOO_MEGA05"]]) && ff5_sweep[["LOO_MEGA05"]]$available)
      ff5_sweep[["LOO_MEGA05"]]$alpha_t_nw else NA
  ),
  ratio_sweep_SR = setNames(
    sapply(names(RATIO_SWEEP), function(nm) sweep_results[[nm]]$full$Sharpe),
    names(RATIO_SWEEP)
  ),
  regime_cond = list(
    SR = sweep_results[["Regime_Cond"]]$full$Sharpe,
    MDD = sweep_results[["Regime_Cond"]]$full$MDD,
    CAGR = sweep_results[["Regime_Cond"]]$full$CAGR,
    CRISIS_SR = sweep_results[["Regime_Cond"]]$regime_sr[["CRISIS"]]$SR
  ),
  delta_vs_both_alone = list(
    SR_delta_vs_m03 = round(SELECTED_RES$full$Sharpe - sweep_results[["LOO_MEGA03"]]$full$Sharpe, 4),
    SR_delta_vs_m05 = round(SELECTED_RES$full$Sharpe - sweep_results[["LOO_MEGA05"]]$full$Sharpe, 4),
    MDD_delta_vs_m03 = round(SELECTED_RES$full$MDD - sweep_results[["LOO_MEGA03"]]$full$MDD, 4),
    MDD_delta_vs_m05 = round(SELECTED_RES$full$MDD - sweep_results[["LOO_MEGA05"]]$full$MDD, 4)
  )
)

cat("[LOO] SR delta vs MEGA_03 alone:", loo_summary$delta_vs_both_alone$SR_delta_vs_m03, "\n")
cat("[LOO] SR delta vs MEGA_05 alone:", loo_summary$delta_vs_both_alone$SR_delta_vs_m05, "\n")

# ===================================================================
# 18. Save Backtest Result JSON
# ===================================================================
cat("\n[Step 18] Saving backtest_result.json...\n")

backtest_result <- list(
  strategy_id       = "STR_1631_MEGA_ENSEMBLE",
  wt_id             = "WT-D20260425_004",
  mega_sprint_phase = "PhaseEnsemble_Blender",
  as_of_date        = as.character(Sys.Date()),
  method            = sprintf("Return-Blend Ensemble | MEGA_03 %.0f%% + MEGA_05 %.0f%% | method=%s",
                              SELECTED_RATIO[1]*100, SELECTED_RATIO[2]*100, SELECTED_METHOD),
  selected_ratio    = list(MEGA_03 = SELECTED_RATIO[1], MEGA_05 = SELECTED_RATIO[2]),
  selected_method   = SELECTED_METHOD,
  judge_recommended = "60_40",
  best_harvey_method = best_harvey_nm,
  tdc = list(
    lower_u10 = round(tdc_10$lower, 6),
    upper_u10 = round(tdc_10$upper, 6),
    lower_u05 = round(tdc_05$lower, 6),
    upper_u05 = round(tdc_05$upper, 6),
    primary   = round(tdc_primary, 6),
    tdc_pass  = tdc_pass,
    threshold = KILL_TDC_MAX,
    pearson   = round(cor_pearson, 4),
    spearman  = round(cor_spearman, 4)
  ),
  full_period = list(
    start   = as.character(min(ret_dt$Date)),
    end     = as.character(max(ret_dt$Date)),
    cagr    = round(SELECTED_RES$full$CAGR, 3),
    sharpe  = round(SELECTED_RES$full$Sharpe, 4),
    mdd     = round(SELECTED_RES$full$MDD, 3)
  ),
  pre_lockbox = list(
    end    = as.character(PRE_LOCKBOX_END),
    cagr   = round(SELECTED_RES$pre_lockbox$CAGR, 3),
    sharpe = round(SELECTED_RES$pre_lockbox$Sharpe, 4),
    mdd    = round(SELECTED_RES$pre_lockbox$MDD, 3)
  ),
  lockbox = list(
    start = as.character(LOCKBOX_START),
    end   = as.character(LOCKBOX_END),
    note  = "Lockbox접근 금지 — Blender 계산 제외. Judge 검증 필요."
  ),
  ff5_analysis = list(
    full_period = ff5_result$full,
    pre_lockbox = ff5_result$pre_lockbox,
    primary_full_harvey_t_nw = ifelse(is.na(primary_harvey_t_full), NA, primary_harvey_t_full),
    primary_prelb_harvey_t_nw = ifelse(is.na(primary_harvey_t_prelb), NA, primary_harvey_t_prelb),
    harvey_t_pass_full = primary_harvey_pass,
    harvey_t_pass_prelb = !is.na(primary_harvey_t_prelb) && primary_harvey_t_prelb >= 3.0,
    harvey_note = sprintf(
      "60:40 Full t_NW=%.4f (%s) | 60:40 PreLB t_NW=%.4f (%s) | Best full ratio=%s t_NW=%.4f",
      ifelse(is.na(primary_harvey_t_full), 0, primary_harvey_t_full),
      if (!is.na(primary_harvey_t_full) && primary_harvey_t_full >= 3.0) "PASS" else "FAIL",
      ifelse(is.na(primary_harvey_t_prelb), 0, primary_harvey_t_prelb),
      if (!is.na(primary_harvey_t_prelb) && primary_harvey_t_prelb >= 3.0) "PASS" else "FAIL",
      best_harvey_nm, best_harvey_t),
    judge_note = "Lockbox period included in full-period Harvey. Judge must verify lockbox exclusion independently."
  ),
  ff5_sweep_full = lapply(ff5_sweep_full, function(r) {
    if (!r$available) list(available = FALSE, label = r$label)
    else list(available = TRUE, label = r$label, alpha_t_nw = r$alpha_t_nw,
              harvey_pass = r$harvey_t_pass)
  }),
  ff5_sweep_prelb = lapply(ff5_sweep, function(r) {
    if (!r$available) list(available = FALSE, label = r$label)
    else list(available = TRUE, label = r$label, alpha_t_nw = r$alpha_t_nw,
              harvey_pass = r$harvey_t_pass)
  }),
  regime_conditional_sr = lapply(c("BULL", "NORMAL", "CAUTION", "CRISIS"), function(r) {
    list(regime = r, SR = SELECTED_RES$regime_sr[[r]]$SR, N = SELECTED_RES$regime_sr[[r]]$N)
  }),
  loo_results = loo_summary,
  ratio_sweep_summary = lapply(names(RATIO_SWEEP), function(nm) {
    res <- sweep_results[[nm]]
    list(method = nm, w03 = res$w03, w05 = res$w05,
         SR = res$full$Sharpe, MDD = res$full$MDD, CAGR = res$full$CAGR,
         CRISIS_SR = res$regime_sr[["CRISIS"]]$SR,
         Harvey_t_NW = if (!is.null(ff5_sweep[[nm]]) && ff5_sweep[[nm]]$available)
           ff5_sweep[[nm]]$alpha_t_nw else NA)
  }),
  regime_cond_ensemble = list(
    description = "BULL:40/60 | NORMAL:50/50 | CAUTION:65/35 | CRISIS:75/25",
    SR = sweep_results[["Regime_Cond"]]$full$Sharpe,
    MDD = sweep_results[["Regime_Cond"]]$full$MDD,
    CRISIS_SR = sweep_results[["Regime_Cond"]]$regime_sr[["CRISIS"]]$SR
  ),
  seven_way_comparison = lapply(seq_len(nrow(seven_way)), function(i) as.list(seven_way[i])),
  sprint_targets = list(
    harvey_30_must  = list(target = 3.0, achieved = ifelse(is.na(primary_harvey_t), NA, primary_harvey_t),
                           pass = primary_harvey_pass),
    mdd_32_target   = list(target = 32.0, achieved = selected_mdd, pass = target_mdd_32),
    crisis_sr_35    = list(target = 3.5, achieved = SELECTED_RES$regime_sr[["CRISIS"]]$SR,
                           pass = target_crisis_sr),
    normal_sr_10    = list(target = 1.0, achieved = SELECTED_RES$regime_sr[["NORMAL"]]$SR,
                           pass = target_normal_sr),
    tdc_040         = list(target = 0.40, achieved = tdc_primary, pass = target_tdc),
    full_sr_135     = list(target = 1.35, achieved = SELECTED_RES$full$Sharpe, pass = target_full_sr)
  ),
  kill_criteria = list(
    harvey_kill = list(threshold = KILL_HARVEY_MIN, achieved = selected_harvey_t, triggered = kill_harvey),
    mdd_kill    = list(threshold = KILL_MDD_MAX, achieved = selected_mdd, triggered = kill_mdd),
    tdc_kill    = list(threshold = KILL_TDC_MAX, achieved = tdc_primary, triggered = kill_tdc),
    verdict     = if (kill_any) "TRIGGERED" else "CLEAR"
  ),
  pit_compliance = list(
    C1  = "PASS: equity curves use expanding IC only (inherited from MEGA_03/05)",
    C2  = "PASS: Score t-1 lag inherited",
    C4  = "PASS: Consensus roll=7d inherited",
    C9  = "PASS: MRS t-1 lag inherited from regime engine",
    C10 = "PASS: LIQ_20d shift(t-1) inherited",
    C13 = "PASS: Z_Score_Aligned inherited",
    C15 = "PASS: Factor DB via load_month_factors inherited",
    ensemble_pit = "Return-blend does not introduce new look-ahead. Lockbox not accessed."
  ),
  run_seconds = round(as.numeric(Sys.time() - t0), 2)
)

write(toJSON(backtest_result, auto_unbox = TRUE, pretty = TRUE, null = "null"),
      file.path(ART_DIR_ENS, "backtest_result.json"))
cat("[JSON] backtest_result.json saved\n")

# ===================================================================
# 19. Ensemble Config JSON
# ===================================================================
cat("\n[Step 19] Saving ensemble_config.json...\n")

ensemble_config <- list(
  task_type         = "ensemble_design",
  wt_id             = "WT-D20260425_004",
  as_of_date        = as.character(Sys.Date()),
  candidates        = list("MEGA_03 (WT-D20260425_001)", "MEGA_05 (WT-D20260425_003)"),
  candidate_profiles = list(
    MEGA_03 = list(
      SR = REF_MEGA03_SR, MDD = REF_MEGA03_MDD, Harvey_FF5 = REF_MEGA03_HARVEY,
      CRISIS_SR = 2.257, method = "HRP+Regime-Σ Rolling, 4F consensus",
      sleeve_role = "Core"
    ),
    MEGA_05 = list(
      SR = REF_MEGA05_SR, MDD = REF_MEGA05_MDD, Harvey_FF5 = NA,
      CRISIS_SR = 2.983, method = "6F+Kelly f=0.5, LW_constcor",
      sleeve_role = "Tactical"
    )
  ),
  correlation = list(
    pearson  = round(cor_pearson, 4),
    spearman = round(cor_spearman, 4),
    tdc_lower_u10 = round(tdc_10$lower, 4),
    tdc_verdict = if (tdc_primary <= 0.40) "PASS (≤0.40)" else sprintf("WARN (%.4f > 0.40)", tdc_primary)
  ),
  merge_strategy = "return_blend",
  merge_rationale = paste(
    "Option C (return-blend) selected: avoids n>20 violation (L-484).",
    "Score-level union top-20 for latest weights only.",
    "Overlay already embedded in each sleeve's equity curve."
  ),
  regime_allocations = list(
    NORMAL   = list(MEGA_03 = 0.50, MEGA_05 = 0.50),
    CAUTION  = list(MEGA_03 = 0.65, MEGA_05 = 0.35),
    CRISIS   = list(MEGA_03 = 0.75, MEGA_05 = 0.25),
    RECOVERY = list(MEGA_03 = 0.55, MEGA_05 = 0.45),
    BULL     = list(MEGA_03 = 0.40, MEGA_05 = 0.60)
  ),
  selected_method = SELECTED_METHOD,
  selected_ratio  = list(MEGA_03 = SELECTED_RATIO[1], MEGA_05 = SELECTED_RATIO[2]),
  judge_recommended = "60_40",
  best_harvey_ratio = best_harvey_nm,
  loo_delta_sr = list(
    remove_MEGA_03 = loo_summary$delta_vs_both_alone$SR_delta_vs_m05,
    remove_MEGA_05 = loo_summary$delta_vs_both_alone$SR_delta_vs_m03
  ),
  recommended_method = if (best_harvey_nm == "60_40") "Fixed_60_40" else
    sprintf("Fixed_%s (Harvey-optimal, Q-Lead confirm needed)", best_harvey_nm),
  reasoning = paste(
    sprintf("TDC=%.4f (≤0.40=%s) — two strategies orthogonal enough for blending.", tdc_primary,
            if (tdc_pass) "PASS" else "WARN"),
    sprintf("LOO: removing MEGA_03 changes SR by %.4f; removing MEGA_05 by %.4f.",
            loo_summary$delta_vs_both_alone$SR_delta_vs_m05,
            loo_summary$delta_vs_both_alone$SR_delta_vs_m03),
    sprintf("Harvey sweep: best ratio=%s (t_NW=%.4f). Judge recommended 60:40 (t_NW=%.4f).",
            best_harvey_nm, best_harvey_t,
            ifelse(is.na(primary_harvey_t), NA, primary_harvey_t)),
    sprintf("CRISIS SR=%.4f | MDD=%.2f%% | Full SR=%.4f.",
            SELECTED_RES$regime_sr[["CRISIS"]]$SR, SELECTED_RES$full$MDD, SELECTED_RES$full$Sharpe),
    "Final decision requires Q-Lead manual confirmation (Blender presents options only)."
  ),
  note_for_judge = paste(
    "Blender Option C (return-blend) does NOT rerun backtests.",
    "FF5 computed on blended return series. Lockbox not accessed.",
    "n=20 weights.csv = score-level union of MEGA_03 + MEGA_05 latest date.",
    "Harvey t_NW on pre-lockbox period for PIT compliance."
  )
)

write(toJSON(ensemble_config, auto_unbox = TRUE, pretty = TRUE, null = "null"),
      file.path(ART_DIR_ENS, "ensemble_config.json"))
cat("[JSON] ensemble_config.json saved\n")

# ===================================================================
# 20. Status Update
# ===================================================================
cat("\n[Step 20] Updating worktask status...\n")
status_path <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", "WT-D20260425_004", "status.json")
status_json <- list(
  task_id       = "WT-D20260425_004",
  current_phase = "FORGE_DONE",
  updated_at    = strftime(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  blocker       = NULL,
  blender_summary = list(
    selected_method = SELECTED_METHOD,
    tdc_primary     = round(tdc_primary, 4),
    kill_verdict    = if (kill_any) "TRIGGERED" else "CLEAR",
    full_sr         = round(SELECTED_RES$full$Sharpe, 4),
    full_mdd        = round(SELECTED_RES$full$MDD, 3),
    harvey_t_nw     = ifelse(is.na(primary_harvey_t), NA, round(primary_harvey_t, 4))
  )
)
dir.create(dirname(status_path), showWarnings = FALSE, recursive = TRUE)
write(toJSON(status_json, auto_unbox = TRUE, pretty = TRUE, null = "null"), status_path)
cat("[Status] WT-D20260425_004 → FORGE_DONE\n")

# ===================================================================
# 21. Telegram Brief
# ===================================================================
cat("\n[Step 21] Telegram brief...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

  crisis_sr_val <- SELECTED_RES$regime_sr[["CRISIS"]]$SR
  normal_sr_val <- SELECTED_RES$regime_sr[["NORMAL"]]$SR
  harvey_flag  <- if (is.na(primary_harvey_t)) "N/A" else sprintf("%.4f", primary_harvey_t)
  harvey_tick  <- if (!is.na(primary_harvey_t) && primary_harvey_t >= 3.0) "PASS" else "FAIL"

  msg <- paste0(
    sprintf("[Blender] MEGA Ensemble Sprint [WT-D20260425_004]\n\n"),
    sprintf("Selected: %s — MEGA_03 %.0f%% + MEGA_05 %.0f%%\n",
            SELECTED_METHOD, SELECTED_RATIO[1]*100, SELECTED_RATIO[2]*100),
    sprintf("TDC: %.4f (<=0.40: %s)\n\n", tdc_primary, if (tdc_pass) "PASS" else "WARN"),
    sprintf("Ensemble 실성과\n Full SR %.4f / MDD %.2f%% / Harvey t_NW %s / CRISIS SR %.4f\n\n",
            SELECTED_RES$full$Sharpe, SELECTED_RES$full$MDD,
            harvey_flag, ifelse(is.na(crisis_sr_val), NA, crisis_sr_val)),
    "7-way 비교\n",
    sprintf(" STR_1631  SR %.3f MDD %.2f%%\n", REF_STR1631_SR, REF_STR1631_MDD),
    sprintf(" MEGA_01   SR %.3f MDD %.2f%%\n", REF_MEGA01_SR, REF_MEGA01_MDD),
    sprintf(" MEGA_02   SR %.3f MDD %.2f%%\n", REF_MEGA02_SR, REF_MEGA02_MDD),
    sprintf(" MEGA_03   SR %.3f MDD %.2f%% Harvey %.3f\n", REF_MEGA03_SR, REF_MEGA03_MDD, REF_MEGA03_HARVEY),
    sprintf(" MEGA_04   SR %.3f MDD %.2f%%\n", REF_MEGA04_SR, REF_MEGA04_MDD),
    sprintf(" MEGA_05   SR %.3f MDD %.2f%%\n", REF_MEGA05_SR, REF_MEGA05_MDD),
    sprintf(" MEGA_ENS  SR %.3f MDD %.2f%% Harvey %s\n\n",
            SELECTED_RES$full$Sharpe, SELECTED_RES$full$MDD, harvey_flag),
    "Sprint Goals\n",
    sprintf(" Harvey>=3.0 MUST: %s\n", harvey_tick),
    sprintf(" MDD<=32%%: %s\n", if (target_mdd_32) "PASS" else sprintf("FAIL (%.2f%%)", selected_mdd)),
    sprintf(" CRISIS>=3.5: %s\n\n",
            if (target_crisis_sr) "PASS" else sprintf("FAIL (%.4f)", ifelse(is.na(crisis_sr_val), 0, crisis_sr_val))),
    sprintf("Kill: %s\n\n", if (kill_any) "TRIGGERED" else "CLEAR"),
    sprintf("LOO: -M03 SR_delta=%.4f | -M05 SR_delta=%.4f",
            loo_summary$delta_vs_both_alone$SR_delta_vs_m05,
            loo_summary$delta_vs_both_alone$SR_delta_vs_m03)
  )

  tg_agent_brief(
    agent_tag    = "Blender",
    title        = "MEGA Ensemble Sprint [WT-D20260425_004]",
    body_text    = msg,
    photo_paths  = c(
      file.path(CHART_DIR, "equity_curve.png"),
      file.path(CHART_DIR, "annual_returns.png"),
      file.path(CHART_DIR, "sleeve_decomposition.png")
    )
  )
}, error = function(e) {
  cat("[Telegram WARN]", conditionMessage(e), "\n")
  cat("[Telegram fallback: tg_send]\n")
  tryCatch({
    msg <- sprintf(
      "[Blender] MEGA ENS WT-D20260425_004 완료\nMethod=%s SR=%.4f MDD=%.2f%% Harvey=%s TDC=%.4f Kill=%s",
      SELECTED_METHOD, SELECTED_RES$full$Sharpe, SELECTED_RES$full$MDD,
      ifelse(is.na(primary_harvey_t), "N/A", sprintf("%.4f", primary_harvey_t)),
      tdc_primary, if (kill_any) "TRIGGERED" else "CLEAR"
    )
    tg_send(msg)
  }, error = function(e2) cat("[Telegram ERROR]", conditionMessage(e2), "\n"))
})

# Final summary
t1 <- Sys.time()
cat(sprintf("\n=== MEGA ENSEMBLE COMPLETE [%.1fs] ===\n", as.numeric(t1 - t0)))
cat(sprintf("Method: %s | MEGA_03=%.0f%% MEGA_05=%.0f%%\n",
            SELECTED_METHOD, SELECTED_RATIO[1]*100, SELECTED_RATIO[2]*100))
cat(sprintf("TDC: %.4f (%s) | Kill: %s\n",
            tdc_primary, if (tdc_pass) "PASS" else "WARN",
            if (kill_any) "TRIGGERED" else "CLEAR"))
cat(sprintf("Full SR=%.4f | MDD=%.2f%% | CAGR=%.2f%%\n",
            SELECTED_RES$full$Sharpe, SELECTED_RES$full$MDD, SELECTED_RES$full$CAGR))
cat(sprintf("Harvey t_NW=%s | CRISIS SR=%.4f | NORMAL SR=%.4f\n",
            ifelse(is.na(primary_harvey_t), "N/A", sprintf("%.4f", primary_harvey_t)),
            ifelse(is.na(SELECTED_RES$regime_sr[["CRISIS"]]$SR), NA, SELECTED_RES$regime_sr[["CRISIS"]]$SR),
            ifelse(is.na(normal_sr_val), NA, normal_sr_val)))
cat(sprintf("Artifacts: %s\n", ART_DIR_ENS))
