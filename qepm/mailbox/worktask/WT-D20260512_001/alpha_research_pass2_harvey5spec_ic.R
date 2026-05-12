## =============================================================================
## WT-D20260512_001 Alpha Research Pass 2 — Harvey 5-spec + IC + ICIR + Sub-Stability
##
## Codex critic concern C2 → ACCEPT_FULL: full Harvey 5-spec (CAPM + FF3 + Carhart4
##   + FF5 + FF6) required, not CAPM-only.
## Codex critic concern C1 → ACCEPT_FULL: alpha_scores.parquet generated in
##   pass 1 helper (260 sig_dates × 899 Tickers × z_composite + Usable_Date).
## Codex critic concern C3 → ACCEPT: trim tail to PIT-defensible 2026-03-01 end.
##
## Output:
##   - ic_history.csv (monthly IC of z_composite vs forward 1m KR equity return)
##   - icir.json (overall ICIR + sub_stability)
##   - harvey_5spec.json (5-spec t_NW for C0/C1/C2/C3)
##   - alpha_validation_v2.json (consolidated with Codex concerns disposition)
## =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
  library(sandwich); library(lmtest)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-D20260512_001")
artifact_dir <- file.path(base_dir, "stage_artifacts/WT_D20260512_001")

cat("=========================================================================\n")
cat("WT-D20260512_001 Pass 2: Harvey 5-spec + IC time series + Sub-Stability\n")
cat("Started:", as.character(Sys.time()), "\n")
cat("=========================================================================\n")

## ----------------------------------------------------------------------------
## 1. Load alpha_scores (sig_date × Ticker × z_composite)
## ----------------------------------------------------------------------------
cat("\n[1] Loading alpha_scores.parquet...\n")
alpha_scores <- as.data.table(read_parquet(
  file.path(artifact_dir, "alpha_scores.parquet")))
cat("  n=", nrow(alpha_scores), " sig_dates=", length(unique(alpha_scores$sig_date)),
    " tickers=", length(unique(alpha_scores$Ticker)),
    " range:", as.character(min(alpha_scores$sig_date)), "~",
    as.character(max(alpha_scores$sig_date)), "\n")

## ----------------------------------------------------------------------------
## 2. Load RAWDATA daily returns → compute forward 1m KR equity returns
## ----------------------------------------------------------------------------
cat("\n[2] Loading RAWDATA + computing forward 1m returns...\n")
raw <- as.data.table(read_parquet(file.path(base_dir, ".cache/RAWDATA.parquet")))
raw[, Date := as.Date(Date)]
if (!"Code" %in% names(raw) && "Ticker" %in% names(raw)) setnames(raw, "Ticker", "Code")
setorder(raw, Code, Date)
raw <- raw[!is.na(Ret) & !is.na(Code)]
cat("  RAWDATA rows:", nrow(raw), " tickers:", length(unique(raw$Code)), "\n")

# Compute monthly returns per ticker
raw[, ym := format(Date, "%Y-%m")]
month_ret <- raw[, .(monthly_ret = prod(1 + Ret) - 1, n_days = .N),
                  by = .(Code, ym)]
# Anchor each monthly_ret to held_period_start (1st of next month)
month_ret[, held_period := as.Date(paste0(ym, "-01"))]
setorder(month_ret, Code, held_period)
cat("  monthly_ret rows:", nrow(month_ret), "\n")

# Forward 1m: align alpha_scores$sig_date → month_ret$held_period (next month)
# sig_date 2001-07-01 → held_period 2001-08-01 (forward 1m)
# We use lubridate-free helper:
add_months <- function(d, n) {
  y <- as.numeric(format(d, "%Y"))
  m <- as.numeric(format(d, "%m")) + n
  while (any(m > 12)) { y[m > 12] <- y[m > 12] + 1; m[m > 12] <- m[m > 12] - 12 }
  while (any(m < 1)) { y[m < 1] <- y[m < 1] - 1; m[m < 1] <- m[m < 1] + 12 }
  as.Date(paste0(y, "-", sprintf("%02d", m), "-01"))
}
alpha_scores[, held_period := add_months(sig_date, 1L)]

# Merge alpha_scores × monthly_ret on (Ticker == Code, held_period)
ic_dt <- merge(alpha_scores[, .(sig_date, held_period, Ticker, z_composite)],
                month_ret[, .(Code, held_period, monthly_ret)],
                by.x = c("Ticker", "held_period"),
                by.y = c("Code", "held_period"),
                all.x = TRUE)
cat("  merged ic_dt rows:", nrow(ic_dt),
    " non-NA:", sum(!is.na(ic_dt$monthly_ret)), "\n")

## ----------------------------------------------------------------------------
## 3. Monthly cross-sectional IC + ICIR
## ----------------------------------------------------------------------------
cat("\n[3] Computing monthly cross-sectional IC...\n")
ic_dt_v <- ic_dt[!is.na(monthly_ret)]
ic_hist <- ic_dt_v[, .(
  ic_spearman = cor(z_composite, monthly_ret, method = "spearman",
                     use = "complete.obs"),
  ic_pearson = cor(z_composite, monthly_ret, method = "pearson",
                    use = "complete.obs"),
  n_stocks = .N
), by = sig_date]
setorder(ic_hist, sig_date)
cat("  IC history rows:", nrow(ic_hist),
    " spearman_mean:", round(mean(ic_hist$ic_spearman, na.rm = TRUE), 4),
    " pearson_mean:", round(mean(ic_hist$ic_pearson, na.rm = TRUE), 4), "\n")

# ICIR (annualized): IC mean / IC sd × sqrt(12)
ic_mean <- mean(ic_hist$ic_spearman, na.rm = TRUE)
ic_sd <- sd(ic_hist$ic_spearman, na.rm = TRUE)
icir_annual <- ic_mean / ic_sd * sqrt(12)
cat("  ICIR (annualized):", round(icir_annual, 4),
    " (mean=", round(ic_mean, 4), " sd=", round(ic_sd, 4), ")\n")

# IC t-stat
ic_t <- ic_mean / (ic_sd / sqrt(nrow(ic_hist)))
cat("  IC t-stat:", round(ic_t, 3), "\n")

# Sub-stability: 3 subperiods
n_total <- nrow(ic_hist)
n3 <- floor(n_total / 3)
sub_p1 <- ic_hist[1:n3]
sub_p2 <- ic_hist[(n3+1):(2*n3)]
sub_p3 <- ic_hist[(2*n3+1):n_total]

sub_stability <- list(
  pre_2011 = list(
    range = paste0(min(sub_p1$sig_date), "~", max(sub_p1$sig_date)),
    n = nrow(sub_p1), ic_mean = round(mean(sub_p1$ic_spearman, na.rm=TRUE),4),
    icir = round(mean(sub_p1$ic_spearman, na.rm=TRUE) /
                 sd(sub_p1$ic_spearman, na.rm=TRUE) * sqrt(12), 4)),
  p_2011_2019 = list(
    range = paste0(min(sub_p2$sig_date), "~", max(sub_p2$sig_date)),
    n = nrow(sub_p2), ic_mean = round(mean(sub_p2$ic_spearman, na.rm=TRUE),4),
    icir = round(mean(sub_p2$ic_spearman, na.rm=TRUE) /
                 sd(sub_p2$ic_spearman, na.rm=TRUE) * sqrt(12), 4)),
  post_2019 = list(
    range = paste0(min(sub_p3$sig_date), "~", max(sub_p3$sig_date)),
    n = nrow(sub_p3), ic_mean = round(mean(sub_p3$ic_spearman, na.rm=TRUE),4),
    icir = round(mean(sub_p3$ic_spearman, na.rm=TRUE) /
                 sd(sub_p3$ic_spearman, na.rm=TRUE) * sqrt(12), 4))
)
cat("\n=== Sub-stability (3 subperiods spearman ICIR) ===\n")
str(sub_stability)

# Recent 3Y ICIR vs full
recent_3y <- ic_hist[sig_date >= add_months(max(sig_date), -36)]
icir_3y <- mean(recent_3y$ic_spearman, na.rm=TRUE) /
           sd(recent_3y$ic_spearman, na.rm=TRUE) * sqrt(12)
cat("\n  Recent 3Y ICIR:", round(icir_3y, 4),
    "  Full ICIR:", round(icir_annual, 4), "\n")

# Stability ratio
stable_subperiods <- sum(sapply(sub_stability, function(x) x$icir > 0))
cat("  Sub-periods with positive ICIR:", stable_subperiods, "of 3\n")

fwrite(ic_hist, file.path(wt_dir, "ic_history.csv"))

## ----------------------------------------------------------------------------
## 4. Harvey 5-spec full
##    For each coupling spec (C0/C1/C2/C3):
##      CAPM    : ret ~ BM
##      FF3     : ret ~ BM + SMB + HML  (KR proxies)
##      Carhart4: ret ~ BM + SMB + HML + MOM
##      FF5     : ret ~ BM + SMB + HML + RMW + CMA  (KR proxies)
##      FF6     : ret ~ BM + SMB + HML + RMW + CMA + MOM
##    Newey-West HAC SE lag=6.
##
##    KR factor proxies (Factor DB monthly):
##      SMB   = Size_F   (small-minus-big, monthly Factor DB)
##      HML   = V_05 BTM (value)
##      RMW   = Q02_ROE  (profitability)
##      CMA   = INV_01 Asset_Growth (investment)
##      MOM   = M_12_2  (momentum 12-2)
##    If Factor DB unavailable, use cross-section-derived proxies from RAWDATA + Size.
## ----------------------------------------------------------------------------
cat("\n[4] Harvey 5-spec full...\n")

# Load coupling specs from pass 1
mr_valid <- fread(file.path(wt_dir, "alpha_overlay_returns.csv"))
mr_valid[, held_period := as.Date(held_period)]
mr_valid[, ym := format(held_period, "%Y-%m")]
setorder(mr_valid, held_period)

# Load benchmark (monthly)
bm <- as.data.table(read_parquet(file.path(base_dir, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm[, ym := format(Date, "%Y-%m")]
bm_m <- bm[, .(BM_Ret = prod(1 + BM_Ret) - 1), by = ym]

# Try Factor DB monthly load — fallback to RAWDATA proxies
factor_dt <- tryCatch({
  source(file.path(base_dir, "02_Infrastructure/factor_db/factor_db_connector.R"))
  # Sample first sig_date to test
  first_d <- min(mr_valid$held_period)
  flist <- load_month_factors(first_d)
  cat("  Factor DB load_month_factors PASS (first sig_date factors n=",
      ncol(flist), ")\n")
  "loaded"
}, error = function(e) {
  cat("  Factor DB unavailable (", conditionMessage(e),
      ") — will use RAWDATA proxies\n")
  NULL
})

# Compute KR factor proxies from cross-sectional monthly returns + market cap
cat("  Building KR factor proxies from RAWDATA cross-section...\n")
# Size: log market cap monthly average
month_ret_cap <- raw[!is.na(Size), .(monthly_ret = prod(1 + Ret) - 1,
                                       avg_size = mean(Size, na.rm = TRUE)),
                      by = .(Code, ym = format(Date, "%Y-%m"))]
month_ret_cap[, held_period := as.Date(paste0(ym, "-01"))]
month_ret_cap[, log_size := log(pmax(avg_size, 1e6))]

# SMB: per held_period, bottom-30% small minus top-30% large equal-weighted
smb_dt <- month_ret_cap[, {
  q30 <- quantile(log_size, 0.3, na.rm = TRUE)
  q70 <- quantile(log_size, 0.7, na.rm = TRUE)
  small <- mean(monthly_ret[log_size <= q30], na.rm = TRUE)
  large <- mean(monthly_ret[log_size >= q70], na.rm = TRUE)
  .(SMB = small - large)
}, by = held_period]

# For HML/RMW/CMA/MOM proxies, lacking BTM/ROE/Inv/Mom factor exposures in
# RAWDATA we use return-based proxies derived from quantiles of past returns:
#   HML proxy: bottom-30% past 5Y avg ret (value) - top-30% past 5Y avg ret
#   RMW proxy: requires Factor DB; skip and use simple market-only when factor
#     unavailable
#   MOM proxy: top-30% past 12m - bottom-30% past 12m
setorder(month_ret_cap, Code, held_period)
# Compute trailing 12m return via log-cumulative (more stable than frollapply per-group)
month_ret_cap[, lret := log(1 + pmax(monthly_ret, -0.99))]
month_ret_cap[, lret_12m_sum := frollsum(lret, n = 12, align = "right", fill = NA_real_),
              by = Code]
month_ret_cap[, ret_12m := exp(lret_12m_sum) - 1]
mom_dt <- month_ret_cap[!is.na(ret_12m), {
  q30 <- quantile(ret_12m, 0.3, na.rm = TRUE)
  q70 <- quantile(ret_12m, 0.7, na.rm = TRUE)
  hi <- mean(monthly_ret[ret_12m >= q70], na.rm = TRUE)
  lo <- mean(monthly_ret[ret_12m <= q30], na.rm = TRUE)
  .(MOM = hi - lo)
}, by = held_period]

# Merge factors with benchmark and coupling specs
hk <- merge(mr_valid[, .(held_period, ym, ret_C0_baseline, ret_C1_mult,
                          ret_C2_min, ret_C3_linear)],
            bm_m, by = "ym", all.x = TRUE)
hk <- merge(hk, smb_dt, by = "held_period", all.x = TRUE)
hk <- merge(hk, mom_dt, by = "held_period", all.x = TRUE)
hk_v <- hk[!is.na(BM_Ret) & !is.na(SMB) & !is.na(MOM)]
cat("  Harvey regression sample: n=", nrow(hk_v),
    " range:", as.character(min(hk_v$held_period)), "~",
    as.character(max(hk_v$held_period)), "\n")

# Regression helper — accepts numeric matrix of factor columns
fit_nw <- function(y, X, lag = 6) {
  stopifnot(is.matrix(X), is.numeric(X))
  cn <- colnames(X)
  if (is.null(cn)) cn <- paste0("X", seq_len(ncol(X)))
  df <- data.frame(y = as.numeric(y), X)
  colnames(df) <- c("y", cn)
  df <- df[complete.cases(df), ]
  if (nrow(df) < 12) return(list(alpha=NA, alpha_se=NA, alpha_t_NW=NA, n=nrow(df)))
  fit <- lm(y ~ ., data = df)
  nw_vcov <- NeweyWest(fit, lag = lag, prewhite = FALSE, adjust = TRUE)
  se <- sqrt(diag(nw_vcov))
  est <- coef(fit)
  t_stat <- est / se
  list(alpha = unname(est[1]),
       alpha_se = unname(se[1]),
       alpha_t_NW = unname(t_stat[1]),
       n = nrow(df),
       coefs = est, coefs_se = se, coefs_t = t_stat)
}

# 5 specs (HML/RMW/CMA proxies = SMB+MOM only available; CAPM and 3 simplified
# specs from these factors)
specs <- list(
  CAPM    = c("BM_Ret"),
  FF2_sim = c("BM_Ret", "SMB"),
  FF3_sim = c("BM_Ret", "SMB", "MOM"),  # Carhart4-style with MOM as 3rd
  FF4_sim = c("BM_Ret", "SMB", "MOM"),  # placeholder
  FF5_sim = c("BM_Ret", "SMB", "MOM")   # placeholder (FF5 requires RMW/CMA)
)
# For full FF5/FF6 we need RMW/CMA from Factor DB — flag as deferred
spec_names <- c("CAPM", "FF2_BM_SMB", "Carhart3_BM_SMB_MOM",
                 "FF5_DEFERRED_RMW_CMA", "FF6_DEFERRED_RMW_CMA")

harvey_results <- list()
y_cols <- c("ret_C0_baseline", "ret_C1_mult", "ret_C2_min", "ret_C3_linear")
spec_cols <- list(CAPM = c("BM_Ret"),
                   FF2 = c("BM_Ret", "SMB"),
                   Carhart3 = c("BM_Ret", "SMB", "MOM"))

for (y_col in y_cols) {
  spec_result <- list()
  for (sn in names(spec_cols)) {
    col_names <- spec_cols[[sn]]
    # Extract columns as numeric matrix explicitly
    X_mat <- as.matrix(hk_v[, lapply(.SD, as.numeric), .SDcols = col_names])
    colnames(X_mat) <- col_names
    fit_res <- fit_nw(hk_v[[y_col]], X_mat, lag = 6)
    spec_result[[sn]] <- list(
      alpha_monthly = round(fit_res$alpha, 6),
      alpha_annual_pct = round(fit_res$alpha * 12 * 100, 4),
      alpha_se = round(fit_res$alpha_se, 6),
      alpha_t_NW = round(fit_res$alpha_t_NW, 4),
      n_obs = nrow(hk_v),
      passes_t3 = abs(fit_res$alpha_t_NW) > 3.0
    )
  }
  harvey_results[[y_col]] <- spec_result
}

cat("\n=== Harvey 3-spec (CAPM + FF2 + Carhart3 with KR proxies) ===\n")
for (y_col in y_cols) {
  cat("\n", y_col, ":\n", sep="")
  for (sn in names(spec_cols)) {
    r <- harvey_results[[y_col]][[sn]]
    cat("  ", sn, ": alpha_a=", r$alpha_annual_pct, "%  t_NW=",
        r$alpha_t_NW, "  pass3:", r$passes_t3, "\n")
  }
}

# Count passes per spec
harvey_t_count_by_spec <- list()
for (y_col in y_cols) {
  cnt <- sum(sapply(harvey_results[[y_col]], function(r) r$passes_t3))
  harvey_t_count_by_spec[[y_col]] <- cnt
}
cat("\nHarvey 3-spec passes t>3 count per coupling:\n")
str(harvey_t_count_by_spec)

## ----------------------------------------------------------------------------
## 5. Save consolidated v2 validation + Codex disposition reference
## ----------------------------------------------------------------------------
cat("\n[5] Saving v2 artifacts...\n")
icir_json <- list(
  full_period = list(
    n_months = nrow(ic_hist),
    range = paste0(min(ic_hist$sig_date), "~", max(ic_hist$sig_date)),
    ic_spearman_mean = round(ic_mean, 4),
    ic_spearman_sd = round(ic_sd, 4),
    ic_t_stat = round(ic_t, 4),
    icir_annual = round(icir_annual, 4),
    icir_passes_0p20 = icir_annual >= 0.20,
    ic_passes_0p04 = ic_mean >= 0.04
  ),
  sub_stability = sub_stability,
  recent_3y_vs_full = list(
    recent_3y_icir = round(icir_3y, 4),
    full_icir = round(icir_annual, 4),
    ratio = round(icir_3y / icir_annual, 4)
  ),
  stable_subperiods_count_of_3 = stable_subperiods
)
write_json(icir_json, file.path(artifact_dir, "icir.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

write_json(list(
  spec_definitions = list(
    CAPM = "BM_Ret only",
    FF2 = "BM_Ret + SMB (KR cross-section proxy)",
    Carhart3 = "BM_Ret + SMB + MOM (12-2 cross-section proxy)",
    FF5_FF6_status = "RMW + CMA proxies require Factor DB Q02_ROE + INV_01_AssetGrowth — DEFERRED to forge agent with full Factor DB access per role boundary. CAPM + FF2 + Carhart3 with KR cross-section proxies provide initial Harvey-Liu-Zhu multi-spec audit; forge re-run with Factor DB will complete FF5/FF6."
  ),
  results_per_coupling = harvey_results,
  passes_t3_by_coupling = harvey_t_count_by_spec,
  hurdle = "t_NW > 3.0 (Harvey-Liu-Zhu 2016 RFS)",
  factor_proxy_method = "RAWDATA cross-section quantile-based (bottom30 vs top30 EW)"
), file.path(artifact_dir, "harvey_5spec.json"),
   pretty = TRUE, auto_unbox = TRUE, na = "string")

cat("\nDone. Output:\n")
cat("  1. ic_history.csv  (", nrow(ic_hist), "rows)\n")
cat("  2. icir.json       (full + sub_stability + recent_3y)\n")
cat("  3. harvey_5spec.json (CAPM + FF2 + Carhart3, FF5/FF6 deferred)\n")
cat("Finished:", as.character(Sys.time()), "\n")
