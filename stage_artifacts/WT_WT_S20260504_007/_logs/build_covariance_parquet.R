## Build covariance.parquet for state_machine compliance.
## Pure overlay role — covariance is INFORMATIVE-ONLY (not used by Optimizer for weight optimization).
## Records 18 STR_1715 active tickers x 18 cov at last rebalance date 2026-05-01 (252-day rolling).

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_007"
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
setwd(PROJECT_ROOT)

# Load STR_1715 active tickers @ 2026-05-01
w <- fread("04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv")
active_tickers <- w[Weight > 0, Ticker]
cat(sprintf("STR_1715 active tickers: %d\n", length(active_tickers)))

# Load RAWDATA, 252-day window ending strictly < 2026-05-01
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]

end_date <- as.Date("2026-05-01")
# t-1 close: trading dates strictly < end_date
trading_dates <- sort(unique(raw[!is.na(Ret), Date]))
pre_dates <- trading_dates[trading_dates < end_date]
window_end <- pre_dates[length(pre_dates)]
cat(sprintf("PIT window end (t-1): %s\n", window_end))

W <- 252L
end_idx <- length(pre_dates)
start_idx <- end_idx - W + 1L
window_dates <- pre_dates[start_idx:end_idx]
cat(sprintf("Window: %s ~ %s (%d days)\n", min(window_dates), max(window_dates), length(window_dates)))

# Build return matrix for STR_1715 active tickers
sub <- raw[Date %in% window_dates & Ticker %in% active_tickers & !is.na(Ret), .(Date, Ticker, Ret)]
rw <- dcast(sub, Date ~ Ticker, value.var = "Ret")
rmat <- as.matrix(rw[, -1])
rmat[is.na(rmat)] <- 0
cat(sprintf("Return matrix: %d x %d\n", nrow(rmat), ncol(rmat)))

# Sample covariance (daily)
cov_mat <- cov(rmat)
# Annualize (252 trading days)
cov_annual <- cov_mat * 252

# LONG format save
n <- ncol(cov_annual)
ticker_names <- colnames(cov_annual)
long_dt <- data.table(
  Ticker_i = rep(ticker_names, each = n),
  Ticker_j = rep(ticker_names, n),
  Sigma_ij = as.vector(cov_annual),
  sigma_method = "sample_252d_rolling_annualized_overlay_diagnostic_only"
)
write_parquet(long_dt, file.path(STAGE_DIR, "covariance.parquet"))
cat(sprintf("Wrote covariance.parquet: %d rows\n", nrow(long_dt)))

# Audit: condition + PSD
eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values
cn <- max(eig) / max(min(eig), 1e-12)
psd <- all(eig >= -1e-10)
cat(sprintf("PSD: %s, min eig: %.2e, max eig: %.4e, cond: %.2f\n",
            psd, min(eig), max(eig), cn))

# Save audit metadata
suppressPackageStartupMessages({library(jsonlite)})
audit <- list(
  task_id = WT_ID,
  role = "diagnostic_only_for_state_machine_compliance",
  optimizer_use = "DO NOT use for weight optimization (sizing_only WT, STR_1715 weights fixed)",
  n_assets = ncol(cov_annual),
  n_obs_days = nrow(rmat),
  window_end_t_minus_1 = as.character(window_end),
  rebalance_date = as.character(end_date),
  pit_compliance = "STRICT_TMINUS_1",
  estimator = "sample covariance (252-day rolling, annualized × 252)",
  psd_verified = psd,
  min_eigenvalue = min(eig),
  max_eigenvalue = max(eig),
  condition_number = cn,
  cond_below_500 = (cn < 500)
)
write_json(audit, file.path(STAGE_DIR, "covariance_parquet_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("Wrote covariance_parquet_audit.json\n")
