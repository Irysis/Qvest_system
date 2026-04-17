#==============================================================================
# MSM Monthly Update — Research Script
# Production 코드(05_Production/) 수정 없이 MSM df_hybrid를 최신화
#
# 로직: MSM.R Mode B와 동일
#   1. K_Fractal_Master에서 파라미터 로드
#   2. KOSPI200 BM 데이터로 log return 산출
#   3. C++ extract_msm_path()로 일간 Crisis_Prob 산출
#   4. EMA200 트렌드 + 월간 Avg_Prob → Hybrid Regime
#   5. 결과를 .RData + .parquet로 저장
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/backtest_harness.R")
#   source("04_Research/regime_comparison/msm_update.R")
#==============================================================================
cat("[msm_update] Starting MSM data update...\n")

suppressPackageStartupMessages({
  library(Rcpp)
  library(RcppArmadillo)
  library(openxlsx)
  library(xts)
  library(zoo)
  library(TTR)
  library(data.table)
  library(PerformanceAnalytics)
})

#──────────────────────────────────────────────────────────────────────────────
# 1. C++ Kernel (copied from MSM.R Section 1 — read-only reference)
#──────────────────────────────────────────────────────────────────────────────
if (!exists("extract_msm_path")) {
  cat("[msm_update] Compiling C++ kernel...\n")
  msm_cpp_code <- '
// [[Rcpp::depends(RcppArmadillo)]]
#include <RcppArmadillo.h>
#include <cmath>
using namespace Rcpp;
using namespace arma;

mat compute_transition_matrix(int k_bar, double b, double gamma_1) {
    mat A = { {1.0 - 0.5 * gamma_1, 0.5 * gamma_1},
              {0.5 * gamma_1, 1.0 - 0.5 * gamma_1} };
    for(int k = 2; k <= k_bar; k++) {
        double gamma_k = 1.0 - pow(1.0 - gamma_1, pow(b, k - 1));
        mat Q_k = { {1.0 - 0.5 * gamma_k, 0.5 * gamma_k},
                    {0.5 * gamma_k, 1.0 - 0.5 * gamma_k} };
        A = kron(A, Q_k);
    }
    return A;
}

vec compute_state_space(int k_bar, double m0, double sigma) {
    vec states = {m0, 2.0 - m0};
    for(int k = 2; k <= k_bar; k++) {
        vec next_states = {m0, 2.0 - m0};
        states = kron(states, next_states);
    }
    return sigma * sqrt(states);
}

// [[Rcpp::export]]
DataFrame extract_msm_path(vec returns, int k_bar, double m0, double sigma, double b, double gamma_1) {
    int T = returns.n_elem;
    int n_states = pow(2, k_bar);

    mat A = compute_transition_matrix(k_bar, b, gamma_1);
    vec s_vals = compute_state_space(k_bar, m0, sigma);

    rowvec pi = ones<rowvec>(n_states) / n_states;
    NumericVector vol_est(T);
    NumericVector crisis_prob(T);

    uvec crisis_indices = find(s_vals > sigma);

    for(int t = 0; t < T; t++) {
        pi = pi * A;
        vec densities = (1.0 / (sqrt(2.0 * M_PI) * s_vals)) % exp(-0.5 * square(returns(t) / s_vals));
        rowvec likelihoods = pi % densities.t();
        double sum_likelihood = sum(likelihoods);
        if(sum_likelihood < 1e-10) sum_likelihood = 1e-10;
        pi = likelihoods / sum_likelihood;

        vol_est(t) = sum(pi % s_vals.t());
        double cp = 0.0;
        for(unsigned int i=0; i < crisis_indices.n_elem; i++) {
            cp += pi(crisis_indices(i));
        }
        crisis_prob(t) = cp;
    }
    return DataFrame::create(Named("Vol") = vol_est, Named("CrisisProb") = crisis_prob);
}
'
  sourceCpp(code = msm_cpp_code)
  cat("[msm_update] C++ kernel compiled.\n")
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Load MSM parameters from latest K_Fractal_Master
#──────────────────────────────────────────────────────────────────────────────
msm_dir <- file.path(PROJECT_ROOT, "05_Production", "1.Regime_Def_Model", "1-1.MSM")
master_files <- list.files(msm_dir, pattern = "^K_Fractal_Master_.*\\.xlsx$", full.names = TRUE)

if (length(master_files) == 0) {
  # Try alternative path
  alt_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant Module/1.Stratagy/1.Factor Model/1-5.MSM"
  master_files <- list.files(alt_dir, pattern = "^K_Fractal_Master_.*\\.xlsx$", full.names = TRUE)
}

if (length(master_files) == 0) stop("[msm_update] No K_Fractal_Master file found!")

# Use the latest by modification time
file_info <- file.info(master_files)
latest_master <- master_files[which.max(file_info$mtime)]
cat(sprintf("[msm_update] Loading params from: %s\n", basename(latest_master)))

params_df <- read.xlsx(latest_master, sheet = "Model_Parameters")
PARAMS <- setNames(params_df$Value, params_df$Parameter)
cat(sprintf("  m0=%.4f, sigma=%.6f, b=%.4f, gamma_1=%.6f\n",
            PARAMS["m0"], PARAMS["sigma"], PARAMS["b"], PARAMS["gamma_1"]))

#──────────────────────────────────────────────────────────────────────────────
# 3. Load latest KOSPI200 benchmark data
#──────────────────────────────────────────────────────────────────────────────
cat("[msm_update] Loading benchmark data...\n")

# Use backtest_harness load_rawdata() if available
if (!exists("BM_DT") || !is.data.table(BM_DT)) {
  if (exists("load_rawdata")) {
    res <- load_rawdata()
    BM_DT <- res$BM_DT
  } else {
    # Direct parquet load
    bm_cache <- file.path(PROJECT_ROOT, ".cache", "benchmark.parquet")
    BM_DT <- as.data.table(arrow::read_parquet(bm_cache))
  }
}

# Build price xts for KOSPI200
bm_dt <- BM_DT[!is.na(BM_Close) & BM_Close > 0][order(Date)]
price_xts <- xts(bm_dt$BM_Close, order.by = bm_dt$Date)
colnames(price_xts) <- "IKS200"

cat(sprintf("[msm_update] BM data: %s ~ %s (%d days)\n",
            as.character(min(bm_dt$Date)),
            as.character(max(bm_dt$Date)),
            nrow(bm_dt)))

#──────────────────────────────────────────────────────────────────────────────
# 4. Compute log returns (de-meaned, matching MSM.R logic exactly)
#──────────────────────────────────────────────────────────────────────────────
ret_xts <- Return.calculate(price_xts, method = "log")
ret_vec <- as.numeric(ret_xts[-1])
ret_vec <- ret_vec - mean(ret_vec, na.rm = TRUE)  # De-meaning

cat(sprintf("[msm_update] Returns: %d observations\n", length(ret_vec)))

#──────────────────────────────────────────────────────────────────────────────
# 5. Run MSM path extraction (C++ Hamilton filter)
#──────────────────────────────────────────────────────────────────────────────
cat("[msm_update] Running C++ Hamilton filter (k_bar=10)...\n")
t0 <- Sys.time()

msm_path <- extract_msm_path(
  ret_vec,
  k_bar   = 10L,
  m0      = PARAMS["m0"],
  sigma   = PARAMS["sigma"],
  b       = PARAMS["b"],
  gamma_1 = PARAMS["gamma_1"]
)

elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
cat(sprintf("[msm_update] Hamilton filter complete (%.1fs)\n", elapsed))

# Daily dataframe
op_df_daily <- data.table(
  Date       = index(ret_xts)[-1],
  Price      = as.numeric(price_xts)[-1],
  Vol_Est    = msm_path$Vol,
  Crisis_Prob = msm_path$CrisisProb
)

#──────────────────────────────────────────────────────────────────────────────
# 6. Hybrid Regime: Monthly Avg_Prob + EMA200 Trend
#──────────────────────────────────────────────────────────────────────────────
prob_xts  <- xts(op_df_daily$Crisis_Prob, order.by = op_df_daily$Date)
price_xts2 <- xts(op_df_daily$Price, order.by = op_df_daily$Date)

# Monthly average crisis probability
monthly_prob <- apply.monthly(prob_xts, colMeans)
colnames(monthly_prob) <- "Avg_Prob"

# EMA200 trend at month-end
daily_ema <- EMA(price_xts2, n = 200)
ep <- endpoints(price_xts2, on = "months")
monthly_trend <- (price_xts2 > daily_ema)[ep]
colnames(monthly_trend) <- "Is_Uptrend"

# Merge
merged_monthly <- merge(monthly_prob, monthly_trend)
merged_monthly <- na.omit(merged_monthly)

# Build df_hybrid (same structure as MSM.R Mode B output)
df_hybrid <- data.table(
  Date       = as.Date(index(merged_monthly)),
  Avg_Prob   = as.numeric(coredata(merged_monthly$Avg_Prob)),
  Is_Uptrend = as.logical(coredata(merged_monthly$Is_Uptrend))
)

# Regime classification (matching MSM.R Mode B exactly)
df_hybrid[, Regime := fcase(
  Avg_Prob >= 0.6, "Crisis",
  Avg_Prob < 0.2 & Is_Uptrend, "Stable",
  default = "Caution"
)]

df_hybrid[, Target_Weight := fcase(
  Regime == "Stable",  1.0,
  Regime == "Caution", 0.5,
  Regime == "Crisis",  0.0,
  default = 0.5
)]

cat(sprintf("[msm_update] df_hybrid: %d months (%s ~ %s)\n",
            nrow(df_hybrid),
            as.character(min(df_hybrid$Date)),
            as.character(max(df_hybrid$Date))))
cat(sprintf("  Regime counts: Crisis=%d, Caution=%d, Stable=%d\n",
            sum(df_hybrid$Regime == "Crisis"),
            sum(df_hybrid$Regime == "Caution"),
            sum(df_hybrid$Regime == "Stable")))
cat(sprintf("  Alerts (non-Stable): %d\n", sum(df_hybrid$Regime != "Stable")))

#──────────────────────────────────────────────────────────────────────────────
# 7. Save updated results
#──────────────────────────────────────────────────────────────────────────────
output_dir <- file.path(PROJECT_ROOT, "research_output", "regime_comparison", "output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Save as .RData (compatible with existing loaders)
msm_rdata_path <- file.path(output_dir, sprintf("MSM_updated_%s.RData",
                                                  format(Sys.Date(), "%Y%m%d")))
save(df_hybrid, op_df_daily, PARAMS, file = msm_rdata_path)
cat(sprintf("[msm_update] Saved: %s\n", basename(msm_rdata_path)))

# Save as parquet for fast loading
msm_parquet_path <- file.path(PROJECT_ROOT, ".cache", "msm_hybrid_latest.parquet")
arrow::write_parquet(df_hybrid, msm_parquet_path)
cat(sprintf("[msm_update] Saved: %s\n", msm_parquet_path))

# Daily data parquet
msm_daily_path <- file.path(PROJECT_ROOT, ".cache", "msm_daily_latest.parquet")
arrow::write_parquet(op_df_daily, msm_daily_path)
cat(sprintf("[msm_update] Saved: %s\n", msm_daily_path))

#──────────────────────────────────────────────────────────────────────────────
# 8. Report
#──────────────────────────────────────────────────────────────────────────────
last_row <- tail(df_hybrid, 1)
trend_str <- ifelse(last_row$Is_Uptrend, "UPTREND", "DOWNTREND")
regime_icon <- switch(last_row$Regime,
                      "Stable" = "[STABLE]",
                      "Caution" = "[CAUTION]",
                      "Crisis" = "[CRISIS]",
                      "[UNKNOWN]")

cat(sprintf("\n======================================================
 [MSM Monthly Report — Updated]
 Date         : %s
 Price        : %.2f
 Trend        : %s (EMA200)
 MSM Prob     : %.1f%%
 REGIME       : %s %s
 Target Weight: %.0f%%
======================================================\n",
    as.character(last_row$Date),
    tail(op_df_daily$Price, 1),
    trend_str,
    last_row$Avg_Prob * 100,
    regime_icon, last_row$Regime,
    last_row$Target_Weight * 100))

cat("[msm_update] Complete.\n")
