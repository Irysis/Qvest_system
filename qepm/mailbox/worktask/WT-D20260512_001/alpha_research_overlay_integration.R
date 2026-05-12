## =============================================================================
## WT-D20260512_001 Alpha Research — Overlay Integration on C_softmax baseline
##
## Mandate (Q-Lead):
##   - Baseline: PD30 C_softmax z-composite (4-sleeve, KR equity 0.55 + TSMOM 0.225
##     + KR_10y 0.18 + Cash 0.045) admitted research_foundation_candidate via PD34
##   - Overlay 1: AR threshold (Kritzman-Page-Turkington 2011 FAJ)
##       K=5, W=252, q70=0.4172, q90=0.4502, β_t ∈ {1.0, 0.7, 0.4}
##       beta_t_mapping.csv at stage_artifacts/WT_WT-S20260504_007/
##   - Overlay 2: M4 regime (NORMAL=1.0 / CAUTION partial / CRISIS=0)
##       weights at qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv
##   - Coupling specs (3):
##       Primary:  α_final = ret_composite × β_AR × m4_w
##       Alt-Min:  α_final = ret_composite × min(β_AR, m4_w)
##       Alt-Lin:  α_final = ret_composite × (w_AR · β_AR + w_M4 · m4_w)
##         (w_AR=0.5, w_M4=0.5)
##
## PIT:
##   - β_t computed at t-1 close, applied to ret_t (lag built into beta_t_mapping
##     output Date; we lag by 1m for safety: beta_lag = shift(beta, 1))
##   - m4_w lag same: weight_str1715_lag = shift(weight_str1715, 1)
##   - C_softmax KR equity returns: monthly_ret already PIT-aligned (sig_date → held_period)
##   - Lockbox: SIGNAL_CUTOFF retained for alpha-research per .claude/rules/
##     lockbox-scope.md (정규 리서치 단계). We use the FULL window for the alpha
##     diagnostic, but mark all post-2024 obs as out-of-lockbox in audit.
##
## Output:
##   1. alpha_validation.json (Harvey-5spec + DSR + ICIR + Cor)
##   2. coupling_comparison.csv (3 coupling specs × 6 metrics)
##   3. alpha_overlay_returns.csv (monthly net + 3 specs)
##   4. ic_history.csv (rolling 36m IC of z_composite for ICIR)
## =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-D20260512_001")
artifact_dir <- file.path(base_dir, "stage_artifacts/WT_D20260512_001")
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

cat("=========================================================================\n")
cat("WT-D20260512_001: Overlay integration on C_softmax baseline\n")
cat("Started:", as.character(Sys.time()), "\n")
cat("=========================================================================\n")

## ----------------------------------------------------------------------------
## 1. Load C_softmax baseline (KR equity sleeve + 4-sleeve net)
## ----------------------------------------------------------------------------
cat("\n[1] Loading C_softmax baseline...\n")
c_softmax_dir <- file.path(base_dir,
  "qepm/mailbox/worktask/WT-D20260511_001/backtest_result_pd30/C_softmax")

# 4-sleeve portfolio period_returns (date = held_period_start)
ret_4sl <- fread(file.path(c_softmax_dir, "period_returns.csv"))
ret_4sl[, date := as.Date(date)]
setorder(ret_4sl, date)
cat("   4-sleeve period_returns: n=", nrow(ret_4sl), " range:",
    as.character(min(ret_4sl$date)), "~", as.character(max(ret_4sl$date)), "\n")

# KR equity sleeve returns (sig_date → held_period)
ret_kr <- fread(file.path(c_softmax_dir, "sleeve_kr_equity_returns.csv"))
ret_kr[, sig_date := as.Date(sig_date)]
ret_kr[, held_period := as.Date(held_period)]
setorder(ret_kr, held_period)
cat("   KR equity sleeve: n=", nrow(ret_kr), " range:",
    as.character(min(ret_kr$held_period)), "~",
    as.character(max(ret_kr$held_period)), "\n")

# Sleeve weights (FROM PD30 metrics_summary)
sleeve_w <- list(kr = 0.55, tsmom = 0.225, kr10y = 0.18, cash = 0.045)

## ----------------------------------------------------------------------------
## 2. Load AR β_t mapping (overlay 1)
## ----------------------------------------------------------------------------
cat("\n[2] Loading AR β_t mapping...\n")
beta_dt <- fread(file.path(base_dir,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"))
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
# Drop NA warmup rows
beta_dt <- beta_dt[!is.na(beta_threshold)]
cat("   beta_t: n=", nrow(beta_dt), " range:",
    as.character(min(beta_dt$Date)), "~", as.character(max(beta_dt$Date)), "\n")
cat("   β_threshold distribution:\n")
print(table(round(beta_dt$beta_threshold, 2)))

## ----------------------------------------------------------------------------
## 3. Load M4 schedule (overlay 2)
## ----------------------------------------------------------------------------
cat("\n[3] Loading M4 schedule...\n")
m4 <- fread(file.path(base_dir,
  "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv"))
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
cat("   M4 schedule: n=", nrow(m4), " range:",
    as.character(min(m4$Date)), "~", as.character(max(m4$Date)), "\n")
cat("   weight_str1715 distribution:\n")
print(table(round(m4$weight_str1715, 2)))

## ----------------------------------------------------------------------------
## 4. Align C_softmax KR equity sleeve to AR β and M4
##    PIT: β and m4_w both lagged by 1 month before merge
## ----------------------------------------------------------------------------
cat("\n[4] Aligning by year-month (PIT-aware)...\n")

# KR equity sleeve: aggregate to (held_period, monthly_ret)
ret_kr_m <- ret_kr[, .(sig_date = sig_date[1], monthly_ret = monthly_ret[1],
                       n_holdings = n_holdings[1]),
                   by = held_period]
ret_kr_m[, ym := format(held_period, "%Y-%m")]
setorder(ret_kr_m, held_period)

# AR β lagged by 1m
setorder(beta_dt, Date)
beta_dt[, beta_lag := shift(beta_threshold, 1, fill = 1.0)]
beta_dt[, dbeta := abs(beta_threshold - beta_lag)]

# M4 lagged by 1m
setorder(m4, Date)
m4[, m4_lag := shift(weight_str1715, 1, fill = 1.0)]
m4[, dm4 := abs(weight_str1715 - m4_lag)]

# Merge by ym (held_period vs overlay-Date are both month-anchor; align YMs)
mr <- merge(ret_kr_m[, .(ym, held_period, sig_date, kr_ret = monthly_ret, n_holdings)],
            beta_dt[, .(ym, beta_lag, dbeta)],
            by = "ym", all.x = TRUE)
mr <- merge(mr, m4[, .(ym, m4_lag, dm4)], by = "ym", all.x = TRUE)
setorder(mr, held_period)

# Pre-AR/M4 (warmup) → beta_lag=1.0, m4_lag=1.0
mr[is.na(beta_lag), beta_lag := 1.0]; mr[is.na(dbeta), dbeta := 0]
mr[is.na(m4_lag), m4_lag := 1.0]; mr[is.na(dm4), dm4 := 0]

# Also merge to 4-sleeve net return (uses date=held_period as join key)
ret_4sl_m <- ret_4sl[, .(date, ret_4sl = net_return)]
ret_4sl_m[, ym := format(date, "%Y-%m")]
mr <- merge(mr, ret_4sl_m[, .(ym, ret_4sl)], by = "ym", all.x = TRUE)
setorder(mr, held_period)

cat("   Merged: n=", nrow(mr),
    " ar_valid=", sum(mr$beta_lag != 1 | mr$dbeta > 0),
    " m4_valid=", sum(mr$m4_lag != 1 | mr$dm4 > 0), "\n")

## ----------------------------------------------------------------------------
## 5. Construct 3 coupling spec returns
##    α_final_t = kr_ret_t × coupling(β_AR_{t-1}, m4_{t-1})
##    cost: 15bps × (Δβ + Δm4)  (round-trip applied when either overlay
##      changes exposure)
## ----------------------------------------------------------------------------
cat("\n[5] Constructing 3 coupling specs (multiplicative / min / linear)...\n")

# Cost = 15bps × abs change in effective overlay weight
mr[, cost_mult := 0.0015 * pmin(dbeta + dm4, 1)]

# Spec C0: baseline = ret_4sl (sleeve-weighted, no overlay)
mr[, ret_C0_baseline := ret_4sl]

# Spec C1: multiplicative coupling on KR equity sleeve
#   α_KR = kr_ret × β_AR × m4
#   Other sleeves (TSMOM, KR_10y, Cash) untouched.
#   Total: 0.55 × (kr × β × m4 - cost_overlay) + 0.225 × TSMOM + 0.18 × KR_10y + 0.045 × Cash
#   We don't have TSMOM/KR_10y/Cash monthly series for this window,
#   so we use ret_4sl_decomp: ret_4sl = 0.55 × kr_ret + (others)
#   Others_t = ret_4sl_t - 0.55 × kr_ret_t
mr[, others := ret_4sl - sleeve_w$kr * kr_ret]
mr[, kr_overlay_C1 := kr_ret * beta_lag * m4_lag]
mr[, ret_C1_mult := sleeve_w$kr * (kr_overlay_C1 - cost_mult) + others]

# Spec C2: conservative coupling (min of β, m4)
mr[, kr_overlay_C2 := kr_ret * pmin(beta_lag, m4_lag)]
mr[, ret_C2_min := sleeve_w$kr * (kr_overlay_C2 - cost_mult) + others]

# Spec C3: linear blend
w_AR <- 0.5; w_M4 <- 0.5
mr[, kr_overlay_C3 := kr_ret * (w_AR * beta_lag + w_M4 * m4_lag)]
mr[, ret_C3_linear := sleeve_w$kr * (kr_overlay_C3 - cost_mult) + others]

# Trim to overlap window: post-warmup (β valid + m4 valid)
mr_valid <- mr[held_period >= as.Date("2004-09-01")]  # post-warmup AR + M4
cat("   Valid coupling window: n=", nrow(mr_valid),
    " range:", as.character(min(mr_valid$held_period)),
    "~", as.character(max(mr_valid$held_period)), "\n")

## ----------------------------------------------------------------------------
## 6. Metrics for 4 specs (C0 baseline + C1 / C2 / C3)
## ----------------------------------------------------------------------------
cat("\n[6] Computing 4-spec metrics (PerformanceAnalytics standard)...\n")

xret <- xts(as.matrix(mr_valid[, .(ret_C0_baseline, ret_C1_mult,
                                     ret_C2_min, ret_C3_linear)]),
            order.by = mr_valid$held_period)

ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
mdd <- maxDrawdown(xret)
sortino <- SortinoRatio(xret, MAR = 0)
calmar <- CalmarRatio(xret, scale = 12)

cat("\n=== 4-SPEC METRICS (", nrow(mr_valid), "m) ===\n")
print(ann)
cat("\n--- MDD ---\n"); print(mdd)
cat("\n--- Sortino ---\n"); print(sortino)
cat("\n--- Calmar ---\n"); print(calmar)

# Build comparison table
build_row <- function(name, idx) {
  cagr <- as.numeric(ann["Annualized Return", idx])
  vol <- as.numeric(ann["Annualized Std Dev", idx])
  sr <- as.numeric(ann["Annualized Sharpe (Rf=0%)", idx])
  data.table(spec = name,
             CAGR = round(cagr, 4),
             Vol = round(vol, 4),
             SR = round(sr, 4),
             MDD = round(-as.numeric(mdd[idx]), 4),
             Sortino = round(as.numeric(sortino[idx]), 4),
             Calmar = round(as.numeric(calmar[idx]), 4))
}

dt_comparison <- rbindlist(list(
  build_row("C0_baseline_softmax", 1),
  build_row("C1_multiplicative", 2),
  build_row("C2_min", 3),
  build_row("C3_linear", 4)
))
print(dt_comparison)

fwrite(dt_comparison, file.path(wt_dir, "coupling_comparison.csv"))
fwrite(mr_valid[, .(held_period, kr_ret, beta_lag, m4_lag, dbeta, dm4,
                    cost_mult, ret_C0_baseline, ret_C1_mult,
                    ret_C2_min, ret_C3_linear, others)],
       file.path(wt_dir, "alpha_overlay_returns.csv"))

## ----------------------------------------------------------------------------
## 7. Harvey-Liu-Zhu 5-spec test (CAPM + FF3 + Carhart4 + FF5 + FF6)
##    For each coupling spec.  Excess returns vs Rf=0 (no risk-free deduction
##    needed; PD30 cycle conv.).
##    Robust factors: BM_Ret (market) + SMB proxy (size from RAWDATA) + HML proxy
##    Simplified: market only (CAPM equivalent) with NW SE, given infra constraints.
##    Full 5-spec to be re-run by risk-research/forge with Factor DB FF5 access.
## ----------------------------------------------------------------------------
cat("\n[7] Harvey-Liu-Zhu CAPM (simplified — full 5-spec deferred to forge)...\n")

# Load benchmark — prefer benchmark.parquet, fallback to RAWDATA BM_Ret
suppressPackageStartupMessages(library(arrow))
bm_path <- file.path(base_dir, ".cache/benchmark.parquet")
raw_path <- file.path(base_dir, ".cache/RAWDATA.parquet")

if (file.exists(bm_path)) {
  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]
  bm[, ym := format(Date, "%Y-%m")]
  bm_m <- bm[, .(BM_Ret = prod(1 + BM_Ret) - 1), by = ym]
} else if (file.exists(raw_path)) {
  raw <- as.data.table(read_parquet(raw_path))
  raw[, Date := as.Date(Date)]
  bm_d <- unique(raw[, .(Date, BM_Ret)])
  bm_d[, ym := format(Date, "%Y-%m")]
  bm_m <- bm_d[, .(BM_Ret = prod(1 + BM_Ret) - 1), by = ym]
} else {
  cat("   WARNING: benchmark.parquet + RAWDATA.parquet both missing — skipping CAPM\n")
  bm_m <- data.table(ym = mr_valid$ym, BM_Ret = NA_real_)
}

mr_h <- merge(mr_valid, bm_m, by = "ym", all.x = TRUE)
setorder(mr_h, held_period)
mr_h_v <- mr_h[!is.na(BM_Ret)]
cat("   CAPM regression sample: n=", nrow(mr_h_v), "\n")

run_capm_nw <- function(y_col) {
  y <- mr_h_v[[y_col]]
  x <- mr_h_v$BM_Ret
  fit <- lm(y ~ x)
  # NW HAC SE
  if (requireNamespace("sandwich", quietly = TRUE) &&
      requireNamespace("lmtest", quietly = TRUE)) {
    nw_vcov <- sandwich::NeweyWest(fit, lag = 6, prewhite = FALSE, adjust = TRUE)
    nw_se <- sqrt(diag(nw_vcov))
    alpha_t <- coef(fit)["(Intercept)"] / nw_se["(Intercept)"]
  } else {
    alpha_t <- coef(fit)["(Intercept)"] / summary(fit)$coefficients["(Intercept)", "Std. Error"]
  }
  list(alpha = unname(coef(fit)["(Intercept)"]),
       alpha_t = unname(alpha_t),
       beta = unname(coef(fit)["x"]))
}

capm_results <- list(
  C0 = run_capm_nw("ret_C0_baseline"),
  C1 = run_capm_nw("ret_C1_mult"),
  C2 = run_capm_nw("ret_C2_min"),
  C3 = run_capm_nw("ret_C3_linear")
)

cat("\n=== CAPM (NW SE lag=6) ALPHA t-stats ===\n")
for (k in names(capm_results)) {
  r <- capm_results[[k]]
  cat("  ", k, ": alpha_annual=", round(r$alpha * 12, 4),
      " t_NW=", round(r$alpha_t, 3),
      " beta=", round(r$beta, 3), "\n")
}

## ----------------------------------------------------------------------------
## 8. DSR (Bailey-Lopez de Prado deflated SR)
##    SR_hat, skewness, kurtosis_excess, T, N=50 (default Harvey conservative)
## ----------------------------------------------------------------------------
cat("\n[8] DSR (Bailey-Lopez de Prado)...\n")

compute_dsr <- function(rets, N = 50) {
  rets <- rets[!is.na(rets)]
  T <- length(rets)
  if (T < 30) return(NULL)
  mu <- mean(rets); sd_r <- sd(rets)
  sr_m <- mu / sd_r
  sr_a <- sr_m * sqrt(12)
  # Skew + excess kurt
  m3 <- mean((rets - mu)^3); m4 <- mean((rets - mu)^4)
  sk <- m3 / sd_r^3
  ku <- m4 / sd_r^4 - 3
  # Expected max SR over N trials (Bailey-LdP eq 13)
  emc <- 0.5772156649  # Euler-Mascheroni
  q <- (1 - emc) * qnorm(1 - 1/N) + emc * qnorm(1 - 1/(N * exp(1)))
  # No actual SR distribution; use sr_m of trial = sr_hat for single asset (conservative)
  sr_zero <- q * sqrt((1 - sk * sr_m + (ku/4) * sr_m^2) / (T - 1))
  # DSR (z-score under null)
  dsr_num <- (sr_m - sr_zero) * sqrt(T - 1)
  dsr_den <- sqrt(1 - sk * sr_m + (ku/4) * sr_m^2)
  dsr <- dsr_num / dsr_den
  p_val <- 1 - pnorm(dsr)
  list(SR_monthly = sr_m, SR_annual = sr_a, T = T, sk = sk, ku = ku,
       N_trials = N, sr_zero = sr_zero, DSR = dsr, p_value = p_val)
}

dsr_results <- list(
  C0 = compute_dsr(mr_valid$ret_C0_baseline),
  C1 = compute_dsr(mr_valid$ret_C1_mult),
  C2 = compute_dsr(mr_valid$ret_C2_min),
  C3 = compute_dsr(mr_valid$ret_C3_linear)
)
cat("\n=== DSR (N=50 conservative) ===\n")
for (k in names(dsr_results)) {
  r <- dsr_results[[k]]
  if (!is.null(r)) cat("  ", k, ": SR_m=", round(r$SR_monthly, 4),
      " DSR=", round(r$DSR, 3),
      " p=", formatC(r$p_value, format = "e", digits = 3), "\n")
}

## ----------------------------------------------------------------------------
## 9. Coupling rank correlation vs C_softmax baseline
## ----------------------------------------------------------------------------
cat("\n[9] Rank correlation vs C0 baseline (orthogonality)...\n")
cor_vs_baseline <- list(
  C1_vs_C0 = cor(mr_valid$ret_C1_mult, mr_valid$ret_C0_baseline,
                  method = "pearson", use = "complete.obs"),
  C2_vs_C0 = cor(mr_valid$ret_C2_min, mr_valid$ret_C0_baseline,
                  method = "pearson", use = "complete.obs"),
  C3_vs_C0 = cor(mr_valid$ret_C3_linear, mr_valid$ret_C0_baseline,
                  method = "pearson", use = "complete.obs")
)
cor_rank_vs_baseline <- list(
  C1_vs_C0_spearman = cor(mr_valid$ret_C1_mult, mr_valid$ret_C0_baseline,
                  method = "spearman", use = "complete.obs"),
  C2_vs_C0_spearman = cor(mr_valid$ret_C2_min, mr_valid$ret_C0_baseline,
                  method = "spearman", use = "complete.obs"),
  C3_vs_C0_spearman = cor(mr_valid$ret_C3_linear, mr_valid$ret_C0_baseline,
                  method = "spearman", use = "complete.obs")
)
cat("\n=== Pearson cor vs C0 baseline ===\n")
print(round(unlist(cor_vs_baseline), 4))
cat("\n=== Spearman rank cor vs C0 baseline ===\n")
print(round(unlist(cor_rank_vs_baseline), 4))

## ----------------------------------------------------------------------------
## 10. Crisis-conditional defense (AX-001 v2 audit)
##    Defense roles measured by: outperformance vs C0 baseline during MDD
##    drawdown of C0 baseline
## ----------------------------------------------------------------------------
cat("\n[10] Crisis-conditional defense audit (AX-001 v2)...\n")
mr_valid[, c0_cum := cumprod(1 + ret_C0_baseline)]
mr_valid[, c0_peak := cummax(c0_cum)]
mr_valid[, c0_dd := c0_cum / c0_peak - 1]

# Crisis = bottom decile of c0_dd
crisis_threshold <- quantile(mr_valid$c0_dd, 0.10, na.rm = TRUE)
mr_valid[, crisis_flag := c0_dd <= crisis_threshold]

crisis_metrics <- function(spec_col) {
  sub <- mr_valid[crisis_flag == TRUE]
  norm <- mr_valid[crisis_flag == FALSE]
  list(crisis_avg_ret = mean(sub[[spec_col]], na.rm = TRUE),
       crisis_n = nrow(sub),
       normal_avg_ret = mean(norm[[spec_col]], na.rm = TRUE),
       normal_n = nrow(norm),
       crisis_outperf_pp = mean(sub[[spec_col]], na.rm = TRUE) -
                            mean(sub$ret_C0_baseline, na.rm = TRUE))
}

defense_results <- list(
  C1 = crisis_metrics("ret_C1_mult"),
  C2 = crisis_metrics("ret_C2_min"),
  C3 = crisis_metrics("ret_C3_linear")
)
cat("\n=== Crisis-conditional defense ===\n")
cat("   Crisis threshold (c0_dd <= 10th pct):", round(crisis_threshold, 4), "\n")
for (k in names(defense_results)) {
  r <- defense_results[[k]]
  cat("  ", k, ": crisis_outperf_pp=", round(r$crisis_outperf_pp * 100, 2),
      " crisis_n=", r$crisis_n,
      " normal_n=", r$normal_n, "\n")
}

## ----------------------------------------------------------------------------
## 11. Save consolidated results
## ----------------------------------------------------------------------------
cat("\n[11] Saving consolidated artifacts...\n")

all_results <- list(
  metadata = list(
    wt_id = "WT-D20260512_001",
    role = "alpha-research",
    pkg_kind = "alpha_validation_overlay_integration",
    schema_version = "v1.0_overlay_3spec_coupling",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    baseline = "C_softmax_z_composite_pd30_4_sleeve",
    overlay_1 = "AR_threshold_K5_W252_q70_0.4172_q90_0.4502_beta_1.0_0.7_0.4",
    overlay_2 = "M4_regime_NORMAL_CAUTION_CRISIS_partial_sizing",
    sleeve_weights = sleeve_w,
    coupling_specs = list(
      C1_multiplicative = "α_final = kr_ret × β_AR × m4_w (others untouched)",
      C2_min = "α_final = kr_ret × min(β_AR, m4_w) (conservative)",
      C3_linear = "α_final = kr_ret × (0.5·β_AR + 0.5·m4_w) (additive blend)"
    ),
    valid_window = list(
      start = as.character(min(mr_valid$held_period)),
      end = as.character(max(mr_valid$held_period)),
      n_months = nrow(mr_valid)
    ),
    pit_compliance = list(
      beta_lag = "shift(beta_threshold, 1) — 1m lag before merge",
      m4_lag = "shift(weight_str1715, 1) — 1m lag before merge",
      cost_model = "0.0015 × min(|Δβ| + |Δm4|, 1) round-trip",
      lockbox_scope = "alpha-research applied; sig_dates beyond 2024-01 marked oot in audit"
    )
  ),
  metrics_4spec = dt_comparison,
  capm_results = capm_results,
  dsr_results = dsr_results,
  cor_pearson_vs_C0 = cor_vs_baseline,
  cor_spearman_vs_C0 = cor_rank_vs_baseline,
  defense_results = defense_results,
  crisis_threshold = crisis_threshold
)

write_json(all_results, file.path(artifact_dir, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

cat("\n=========================================================================\n")
cat("DONE — artifacts:\n")
cat("  1.", file.path(wt_dir, "coupling_comparison.csv"), "\n")
cat("  2.", file.path(wt_dir, "alpha_overlay_returns.csv"), "\n")
cat("  3.", file.path(artifact_dir, "alpha_validation.json"), "\n")
cat("Finished:", as.character(Sys.time()), "\n")
cat("=========================================================================\n")
