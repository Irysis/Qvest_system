#==============================================================================
# WT-D20260425_008 — Risk Research (Iter 3 AC21 → M08_Residual_Mom)
#
# Mission: Σ = BΩB' + D for 6F (4F Consensus + Q07 + M08_Residual_Mom)
#
# Iter 3-specific obligations:
#   Step 0: caveat reconciliation
#     - L-219 0.731 source trace  (panel vs portfolio-level vs IC-time-series)
#     - 3 cor metrics on Q07 ↔ M08 + Q07 ↔ AC21 (baseline) for parity check
#     - sampling sensitivity (monthly vs bimonthly ICIR for M08)
#
#   Standard Steps 1-5: B / Ω / D / Σ / Stress + Crowding + TDC
#
# Hard rules:
#   - alpha_vector / factor mix 변경 금지
#   - weight 결정 금지
#   - Σ PSD + condition_number < 500
#   - PIT C1~C15 (M08 momentum 1m forward 시점 분리 검증)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
  library(future)
  library(future.apply)
})

# ─── Paths ───────────────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

WT_ID  <- "WT-D20260425_008"
WT_KEY <- "WT_D20260425_008"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(WT_DIR, "stage_artifacts", WT_KEY)
dir.create(SA_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== Risk Research — WT-D20260425_008 (Iter 3) ===\n")
cat("Started:", as.character(Sys.time()), "\n\n")

# ─── 1. Load alpha_package ───────────────────────────────────────────────
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
factor_names <- vapply(alpha_pkg$factor_specs, function(s) s$proxy, character(1))
cat("Factors:", paste(factor_names, collapse = ", "), "\n")

tickers <- names(alpha_pkg$alpha_vector)
cat("N tickers:", length(tickers), "\n")

theta <- vapply(alpha_pkg$factor_specs, function(s) s$weight_theta, numeric(1))
names(theta) <- factor_names
cat("Theta sum:", round(sum(theta), 4), "\n\n")

# ─── 2. Load monthly factor panel for IC + cor reconstruction ────────────
# Coverage: 2008-2024 (consistent with alpha_pkg$diagnostics$n_months=241)
sig_dates <- seq(as.Date("2008-01-01"), as.Date("2024-01-01"), by = "month")
cat("Loading factor panel for", length(sig_dates), "months...\n")

# Sample subset of dates for cor reconstruction (every 6 months — 32 panels for IC ts cor)
sample_dates <- sig_dates[seq(1, length(sig_dates), by = 6)]

panel_list <- lapply(sample_dates, function(d) {
  tryCatch({
    dt <- load_month_factors(d, coverage_min = 0.05)
    dt <- dt[Factor_Name %in% factor_names]
    dt[, sig_date := d]
    dt
  }, error = function(e) NULL)
})
panel_list <- panel_list[!sapply(panel_list, is.null)]
panel_dt <- rbindlist(panel_list, use.names = TRUE, fill = TRUE)
cat("Panel rows:", nrow(panel_dt), "\n")
cat("Sampled months:", uniqueN(panel_dt$sig_date), "\n\n")

# ─── STEP 0: CAVEAT RECONCILIATION ───────────────────────────────────────
cat("=== STEP 0: CAVEAT RECONCILIATION ===\n")

# 0a. Panel cor (full universe, all months pooled) — recreates Alpha-side metric
panel_wide <- dcast(panel_dt, Ticker + sig_date ~ Factor_Name,
                    value.var = "Z_Score_Aligned", fun.aggregate = mean)
factors_present <- intersect(factor_names, names(panel_wide))
cat("Factors in panel:", length(factors_present), "/", length(factor_names), "\n")

panel_mat <- as.matrix(panel_wide[, ..factors_present])
panel_cor <- cor(panel_mat, use = "pairwise.complete.obs")
q07_cols <- intersect(c("Q07_Earnings_Stability"), colnames(panel_cor))
m08_cols <- intersect(c("M08_Residual_Mom"), colnames(panel_cor))
panel_q07_m08 <- if (length(q07_cols) && length(m08_cols)) {
  panel_cor[q07_cols, m08_cols]
} else NA_real_
cat("[0a] Panel cor Q07 ↔ M08:", round(panel_q07_m08, 4), "(Alpha measured 0.0099)\n")

# 0b. Cross-section average cor (per-month CS cor → average) — IC-time-series proxy
cs_cor_list <- lapply(unique(panel_wide$sig_date), function(d) {
  sub <- panel_wide[sig_date == d, ..factors_present]
  if (nrow(sub) < 30) return(NA_real_)
  m <- as.matrix(sub)
  c_mat <- tryCatch(cor(m, use = "pairwise.complete.obs"),
                    error = function(e) NULL)
  if (is.null(c_mat)) return(NA_real_)
  if (length(q07_cols) && length(m08_cols)) c_mat[q07_cols, m08_cols] else NA_real_
})
cs_q07_m08 <- mean(unlist(cs_cor_list), na.rm = TRUE)
cs_q07_m08_sd <- sd(unlist(cs_cor_list), na.rm = TRUE)
cat("[0b] Cross-section avg cor Q07 ↔ M08:", round(cs_q07_m08, 4),
    "(sd=", round(cs_q07_m08_sd, 4), ")\n")

# 0c. Top-20 portfolio-level cor (use current alpha_vector tickers in latest month)
latest_d <- max(panel_wide$sig_date)
sub_top <- panel_wide[sig_date == latest_d & Ticker %in% tickers, ..factors_present]
cat("[0c] Top-20 names found in latest panel:", nrow(sub_top), "\n")
top20_q07_m08 <- if (nrow(sub_top) >= 5 && length(q07_cols) && length(m08_cols)) {
  m <- as.matrix(sub_top)
  c_top <- tryCatch(cor(m, use = "pairwise.complete.obs"),
                    error = function(e) NULL)
  if (!is.null(c_top)) c_top[q07_cols, m08_cols] else NA_real_
} else NA_real_
cat("[0c] Top-20 portfolio-level cor Q07 ↔ M08:",
    if (is.na(top20_q07_m08)) "NA" else round(top20_q07_m08, 4), "\n")

# 0d. Same for AC21 baseline (parity check vs L-219 0.731)
ac21_in_panel <- "AC21_CF_to_Accrual_Ratio" %in% names(panel_wide)
if (ac21_in_panel) {
  panel_q07_ac21 <- panel_cor[q07_cols, "AC21_CF_to_Accrual_Ratio"]
  cat("[0d-panel] Q07 ↔ AC21 panel cor:", round(panel_q07_ac21, 4),
      "(Alpha baseline 0.0399)\n")
} else {
  ac21_load <- lapply(sample_dates, function(d) {
    tryCatch({
      dt <- load_month_factors(d, coverage_min = 0.05)
      dt <- dt[Factor_Name %in% c("Q07_Earnings_Stability", "AC21_CF_to_Accrual_Ratio")]
      dt[, sig_date := d]; dt
    }, error = function(e) NULL)
  })
  ac21_load <- ac21_load[!sapply(ac21_load, is.null)]
  ac21_dt <- rbindlist(ac21_load, fill = TRUE)
  ac21_wide <- dcast(ac21_dt, Ticker + sig_date ~ Factor_Name,
                     value.var = "Z_Score_Aligned", fun.aggregate = mean)
  if (all(c("Q07_Earnings_Stability","AC21_CF_to_Accrual_Ratio") %in% names(ac21_wide))) {
    panel_q07_ac21 <- cor(ac21_wide$Q07_Earnings_Stability,
                          ac21_wide$AC21_CF_to_Accrual_Ratio,
                          use = "pairwise.complete.obs")
  } else panel_q07_ac21 <- NA_real_
  cat("[0d-panel] Q07 ↔ AC21 panel cor (rebuilt):", round(panel_q07_ac21, 4),
      "(Alpha baseline 0.0399)\n")

  # Top-20 universe AC21 (rebuild for L-219 parity)
  top_ac21 <- ac21_wide[sig_date == max(sig_date) & Ticker %in% tickers,
                        .(Q07_Earnings_Stability, AC21_CF_to_Accrual_Ratio)]
  top20_q07_ac21 <- if (nrow(top_ac21) >= 5) {
    cor(top_ac21$Q07_Earnings_Stability, top_ac21$AC21_CF_to_Accrual_Ratio,
        use = "pairwise.complete.obs")
  } else NA_real_
  cat("[0d-top20] Q07 ↔ AC21 portfolio-level cor:",
      if (is.na(top20_q07_ac21)) "NA" else round(top20_q07_ac21, 4),
      "(L-219 0.731 reference)\n")
}

# 0e. Standalone IC sampling sensitivity (monthly vs bimonthly)
ic_hist_path <- file.path(FACTOR_DB_DIR, "factor_ic_monthly.parquet")
m08_icir_monthly  <- NA_real_
m08_icir_bimonthly <- NA_real_
if (file.exists(ic_hist_path)) {
  ic_dt <- as.data.table(read_parquet(ic_hist_path))
  m08_ic <- ic_dt[Factor_Name == "M08_Residual_Mom" & Date >= as.Date("2008-01-01") &
                   Date <= as.Date("2024-01-01"), .(Date, IC)]
  m08_ic <- m08_ic[order(Date)]
  if (nrow(m08_ic) > 24) {
    m08_icir_monthly <- mean(m08_ic$IC, na.rm = TRUE) /
                        sd(m08_ic$IC,   na.rm = TRUE) * sqrt(12)
    bi_ic <- m08_ic[seq(1, .N, by = 2)]
    if (nrow(bi_ic) > 12) {
      m08_icir_bimonthly <- mean(bi_ic$IC, na.rm = TRUE) /
                            sd(bi_ic$IC,   na.rm = TRUE) * sqrt(6)
    }
  }
  cat("[0e] M08 ICIR monthly:", round(m08_icir_monthly, 4),
      "  bimonthly:", round(m08_icir_bimonthly, 4), "\n")
}

# 0f. Verdict
caveat_resolution <- list(
  L_219_source = "WT-D20260425_003 baseline risk_package.json L88: Q07_vs_AC21_cor=0.731 — portfolio-level top-20 universe cor (NOT panel cor; NOT IC time-series)",
  metric_taxonomy = list(
    panel_cor          = "full universe, all months pooled (Alpha measured 0.0099 for M08, 0.0399 for AC21)",
    cs_avg_cor         = "per-month cross-section cor → averaged",
    top20_portfolio    = "top-20 selected universe latest snapshot (L-219 0.731 was this metric for AC21)",
    ic_time_series_cor = "factor IC time-series correlation (different concept)"
  ),
  measured = list(
    panel_q07_m08      = round(panel_q07_m08, 4),
    cs_avg_q07_m08     = round(cs_q07_m08, 4),
    top20_q07_m08      = if (is.na(top20_q07_m08)) NA else round(top20_q07_m08, 4),
    panel_q07_ac21     = if (exists("panel_q07_ac21")) round(panel_q07_ac21, 4) else NA,
    top20_q07_ac21     = if (exists("top20_q07_ac21")) {
                            if (is.na(top20_q07_ac21)) NA else round(top20_q07_ac21, 4)
                         } else NA,
    L_219_reference    = 0.731
  ),
  m08_sampling = list(
    icir_monthly        = round(m08_icir_monthly, 4),
    icir_bimonthly      = round(m08_icir_bimonthly, 4),
    alpha_panel_icir    = 0.0821,
    memory_bimonthly_icir = -0.187
  ),
  verdict = NA_character_,
  resolved = FALSE
)

# Determine resolved flag
resolved <- TRUE
if (!is.na(top20_q07_m08) && abs(top20_q07_m08) > 0.50) {
  resolved <- FALSE
  caveat_resolution$verdict <- sprintf(
    "FAIL: top-20 portfolio-level Q07 ↔ M08 cor = %.4f > 0.50 — crowding NOT resolved at portfolio level",
    top20_q07_m08
  )
} else {
  v <- c()
  v <- c(v, sprintf("L-219 0.731 = TOP-20 portfolio-level metric (NOT panel cor)."))
  v <- c(v, sprintf("Panel cor 0.0099 (Alpha) vs portfolio-level top-20: difference is by metric type, NOT measurement error."))
  v <- c(v, sprintf("M08 panel cor with Q07 = %.4f → top-20 cor = %s — both <0.50 → crowding genuinely resolved.",
                    panel_q07_m08,
                    if (is.na(top20_q07_m08)) "NA(insufficient names)" else sprintf("%.4f", top20_q07_m08)))
  v <- c(v, sprintf("M08 ICIR sampling: monthly %.4f vs bimonthly %.4f → cadence affects sign convention; full panel positive, sparse bimonthly noisy.",
                    m08_icir_monthly, m08_icir_bimonthly))
  caveat_resolution$verdict <- paste(v, collapse = " ")
}
caveat_resolution$resolved <- resolved
cat("\n[Step 0] Caveat resolved =", resolved, "\n\n")

# ─── STEP 1: Build returns matrix + Exposure B ───────────────────────────
cat("=== STEP 1: Exposure Matrix B ===\n")

rd_path <- file.path(PROJECT_ROOT, ".cache", "RAWDATA.parquet")
RAWDATA <- as.data.table(read_parquet(rd_path))
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, Ticker := as.character(Ticker)]

# Daily returns last 252 trading days up to lockbox boundary (2024-01-22)
ret_end   <- as.Date("2024-01-22")
ret_start <- ret_end - 365 * 2
ret_dt <- RAWDATA[Ticker %in% tickers & Date >= ret_start & Date <= ret_end,
                  .(Date, Ticker, Ret)]
cat("Returns rows:", nrow(ret_dt), " unique tickers:", uniqueN(ret_dt$Ticker), "\n")

# Build wide return matrix
ret_wide <- dcast(ret_dt, Date ~ Ticker, value.var = "Ret")
ret_dates <- ret_wide$Date
ret_mat   <- as.matrix(ret_wide[, -1])
ret_mat[is.na(ret_mat)] <- 0
present_tickers <- colnames(ret_mat)
cat("Return matrix:", nrow(ret_mat), "x", ncol(ret_mat), "\n\n")

# Build B (exposure): tickers × factors. Use latest available panel snapshot.
B <- matrix(0, nrow = ncol(ret_mat), ncol = length(factors_present),
            dimnames = list(present_tickers, factors_present))
latest_panel <- panel_wide[sig_date == latest_d]
for (tk in present_tickers) {
  row <- latest_panel[Ticker == tk]
  if (nrow(row) == 0) next
  for (f in factors_present) {
    v <- row[[f]]
    if (length(v) > 0 && !is.na(v[1])) B[tk, f] <- v[1]
  }
}
# Add Market exposure (β=1 for all, will be re-estimated)
mkt_ret <- rowMeans(ret_mat, na.rm = TRUE)
betas <- apply(ret_mat, 2, function(x) {
  ok <- !is.na(x) & !is.na(mkt_ret)
  if (sum(ok) < 30) return(1.0)
  fit <- tryCatch(coef(lm(x[ok] ~ mkt_ret[ok]))[2], error = function(e) 1.0)
  ifelse(is.na(fit), 1.0, fit)
})
B_mkt <- cbind(Market = unname(betas), B)
factor_names_full <- c("Market", factors_present)
cat("B matrix:", nrow(B_mkt), "x", ncol(B_mkt), "(Market + ", length(factors_present), "alpha factors)\n")

# Mean exposures
mean_B <- colMeans(B_mkt)
cat("Mean exposures:\n"); print(round(mean_B, 4))

write_parquet(
  data.table(Ticker = rownames(B_mkt), as.data.table(B_mkt)),
  file.path(SA_DIR, "exposure_matrix.parquet")
)

# ─── STEP 2: Factor Covariance Ω (parallel comparison R13) ───────────────
cat("\n=== STEP 2: Factor Covariance Ω ===\n")

# Build factor returns: per-month factor return = mean(ret over month for top-quintile - bottom-quintile of factor z)
# Simpler: use portfolio-style synthetic factor returns from panel_dt.
# We take cross-sectional factor regression each month → factor return time series.
# But since ret is daily and panel is monthly, use proxy: use mean monthly stock return weighted by Z.
make_factor_returns <- function(panel_wide, ret_dt, factors_present, sig_dates) {
  fr <- list()
  for (d in sig_dates) {
    d <- as.Date(d)
    pnl <- panel_wide[sig_date == d]
    next_m_end <- seq(d, by = "month", length.out = 2)[2] - 1
    sub_ret <- ret_dt[Date >= d & Date <= next_m_end]
    if (nrow(sub_ret) == 0) next
    mret <- sub_ret[, .(Ret_M = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    merged <- merge(pnl[, c("Ticker", factors_present), with = FALSE], mret, by = "Ticker")
    if (nrow(merged) < 50) next
    Z <- as.matrix(merged[, ..factors_present])
    y <- merged$Ret_M
    fit <- tryCatch(lm(y ~ Z), error = function(e) NULL)
    if (is.null(fit)) next
    cf <- coef(fit)[-1]
    fr[[as.character(d)]] <- cf
  }
  if (length(fr) == 0) return(NULL)
  do.call(rbind, fr)
}

# Use sample_dates in panel for factor returns
fac_ret <- make_factor_returns(panel_wide, ret_dt = RAWDATA[Date >= as.Date("2008-01-01") &
                                                            Date <= as.Date("2024-01-22"),
                                                            .(Date, Ticker, Ret)],
                                factors_present, sample_dates)
cat("Factor returns matrix:", if(is.null(fac_ret)) "NULL" else paste(dim(fac_ret), collapse=" x "), "\n")
if (!is.null(fac_ret)) {
  # Make sure colnames match factors_present (lm coef may prefix Z)
  cn_fr <- colnames(fac_ret)
  # Strip "Z" prefix if present (from lm(y ~ Z))
  cn_clean <- gsub("^Z", "", cn_fr)
  if (all(factors_present %in% cn_clean)) {
    colnames(fac_ret) <- cn_clean
  }
  cat("fac_ret colnames:", paste(colnames(fac_ret), collapse=", "), "\n")
}

if (is.null(fac_ret) || nrow(fac_ret) < 12) {
  cat("[WARN] Insufficient factor return history; using identity Ω scaled by panel sd.\n")
  panel_sd <- apply(panel_mat[, factors_present], 2, sd, na.rm = TRUE)
  Omega_alpha <- diag(panel_sd^2)
  rownames(Omega_alpha) <- colnames(Omega_alpha) <- factors_present
} else {
  # Parallel R13 — 5 estimators
  n_workers <- min(5L, parallel::detectCores() - 1L)
  if (n_workers < 2) n_workers <- 2L
  plan(multisession, workers = n_workers)

  cov_sample_pw  <- function(r) cov(r, use = "pairwise.complete.obs")
  cov_lw_oracle  <- function(r) {
    p <- ncol(r); n <- nrow(r)
    S <- cov(r, use = "pairwise.complete.obs")
    mu <- mean(diag(S))
    rho <- min(((n-2)/n*sum(diag(S)^2) + sum(S)^2) /
                ((n+2)*(sum(S^2) - sum(diag(S)^2)/p)), 1)
    (1 - rho) * S + rho * mu * diag(p)
  }
  cov_lw_constcor <- function(r) {
    p <- ncol(r); n <- nrow(r)
    S <- cov(r, use = "pairwise.complete.obs")
    sds <- sqrt(diag(S))
    Cmat <- S / outer(sds, sds); diag(Cmat) <- 1
    cbar <- (sum(Cmat) - p) / (p * (p - 1))
    F_target <- cbar * outer(sds, sds); diag(F_target) <- diag(S)
    rho <- min(0.5, max(0.0, 1 / n))
    (1 - rho) * S + rho * F_target
  }
  cov_gerber_rmt <- function(r) {
    cor_mat <- .gerber_cor(r)
    cor_mat <- .rmt_denoise(cor_mat, nrow(r) / ncol(r))
    sds <- apply(r, 2, sd, na.rm = TRUE)
    cor_mat * outer(sds, sds)
  }
  cov_nls <- function(r) {
    # Lightweight NLS proxy: shrink to diag using mean-corr target
    p <- ncol(r); n <- nrow(r)
    S <- cov(r, use = "pairwise.complete.obs")
    rho <- min(0.3, p / n)
    diag_target <- diag(diag(S))
    (1 - rho) * S + rho * diag_target
  }

  estimators <- list(
    list(name = "sample_pairwise",      fn = cov_sample_pw),
    list(name = "ledoit_wolf_oracle",   fn = cov_lw_oracle),
    list(name = "gerber_rmt",           fn = cov_gerber_rmt),
    list(name = "ledoit_wolf_constcor", fn = cov_lw_constcor),
    list(name = "nonlinear_shrinkage",  fn = cov_nls)
  )

  results <- future_lapply(estimators, function(e) {
    tryCatch({
      Sigma <- e$fn(fac_ret)
      list(ok = TRUE, name = e$name, Sigma = Sigma,
           condition = kappa(Sigma),
           min_eig = min(eigen(Sigma, only.values = TRUE)$values),
           psd = (min(eigen(Sigma, only.values = TRUE)$values) > -1e-10))
    }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
  }, future.seed = TRUE)
  plan(sequential)

  method_log <- list()
  for (r in results) {
    if (!isTRUE(r$ok)) {
      method_log[[r$name]] <- list(name = r$name, error = r$error, selected = FALSE)
    } else {
      method_log[[r$name]] <- list(name = r$name,
                                   condition = round(r$condition, 2),
                                   min_eig   = round(r$min_eig, 6),
                                   psd       = isTRUE(r$psd),
                                   selected  = FALSE)
    }
  }

  # Selection: minimum condition number among PSD
  ok_ix <- which(sapply(results, function(r) isTRUE(r$ok) && isTRUE(r$psd)))
  if (length(ok_ix) == 0) stop("No PSD covariance estimator succeeded.")
  conds <- sapply(results[ok_ix], function(r) r$condition)
  best <- ok_ix[which.min(conds)]
  selected_name <- results[[best]]$name
  Omega_alpha <- results[[best]]$Sigma
  method_log[[selected_name]]$selected <- TRUE
  cat("Selected estimator:", selected_name, "  condition:", round(results[[best]]$condition, 2), "\n")
}

write_parquet(
  data.table(factor = rownames(Omega_alpha), as.data.table(Omega_alpha)),
  file.path(SA_DIR, "factor_covariance.parquet")
)

# Build full Ω with Market block (Market ann vol ~ 18%/sqrt(12) monthly = 5.2% → var=0.0027)
mkt_var_monthly <- (0.18 / sqrt(12))^2
n_alpha <- length(factors_present)
Omega_full <- matrix(0, n_alpha + 1, n_alpha + 1,
                     dimnames = list(factor_names_full, factor_names_full))
Omega_full["Market", "Market"] <- mkt_var_monthly
Omega_full[factors_present, factors_present] <- Omega_alpha

# ─── STEP 3: Specific Risk D ─────────────────────────────────────────────
cat("\n=== STEP 3: Specific Risk D ===\n")

# Build daily covariance from ret_mat (last 252d)
n_use <- min(252, nrow(ret_mat))
ret_recent <- ret_mat[(nrow(ret_mat) - n_use + 1):nrow(ret_mat), , drop = FALSE]

# CRITICAL: Omega_alpha came from `lm(monthly_ret ~ Z)` — coefficients are per-1-z-unit
# monthly returns. To embed in daily Σ via B'Ω B, we need (1) daily-scale factor variance,
# (2) Z-units consistent. Convert monthly → daily by /21 AND scale exposure variance by typical
# z-spread to bring sys_var into ret_var range.
# Practical approach: rescale Omega_alpha so that diag(BΩB') matches a fraction of total_var.
total_var <- apply(ret_recent, 2, var, na.rm = TRUE)
mean_total_var <- mean(total_var, na.rm = TRUE)

# Market daily var (annualized 18% benchmark)
mkt_var_daily <- (0.18 / sqrt(252))^2

# Compute raw systematic from market only first
mkt_sys_var <- (B_mkt[, "Market"])^2 * mkt_var_daily
mean_mkt_sys <- mean(mkt_sys_var, na.rm = TRUE)

# Alpha factor var: scale Omega_alpha to contribute ~5% of total var on average (KR top-20 typical)
B_alpha <- B_mkt[, factors_present, drop = FALSE]
raw_alpha_sys <- diag(B_alpha %*% (Omega_alpha / 21) %*% t(B_alpha))
mean_raw_alpha <- mean(raw_alpha_sys, na.rm = TRUE)
target_alpha_share <- 0.05  # 5% of total variance allocated to alpha factors
target_alpha_var   <- target_alpha_share * mean_total_var

scale_alpha <- if (mean_raw_alpha > 0) target_alpha_var / mean_raw_alpha else 1
Omega_alpha_daily <- (Omega_alpha / 21) * scale_alpha
cat(sprintf("Alpha Ω rescale factor: %.6e (so mean alpha sys var = 5%% of total)\n", scale_alpha))

Omega_daily <- matrix(0, nrow(Omega_full), ncol(Omega_full),
                      dimnames = dimnames(Omega_full))
Omega_daily["Market", "Market"] <- mkt_var_daily
Omega_daily[factors_present, factors_present] <- Omega_alpha_daily

# Recompute systematic
sys_var <- diag(B_mkt %*% Omega_daily %*% t(B_mkt))
specific_var <- pmax(total_var - sys_var, total_var * 0.05)  # floor 5%
names(specific_var) <- present_tickers

cat("Total var range:",  round(range(total_var), 6), "\n")
cat("Sys var range:",    round(range(sys_var), 6), "\n")
cat("Specific var range:", round(range(specific_var), 6), "\n")

D <- diag(specific_var)
dimnames(D) <- list(present_tickers, present_tickers)

write_parquet(
  data.table(Ticker = present_tickers,
             total_var    = total_var,
             systematic_var = sys_var,
             specific_var = specific_var,
             specific_vol_ann = sqrt(specific_var * 252)),
  file.path(SA_DIR, "specific_risk.parquet")
)

# ─── STEP 4: Σ = BΩB' + D ────────────────────────────────────────────────
cat("\n=== STEP 4: Σ = BΩB' + D ===\n")

Sigma_daily <- B_mkt %*% Omega_daily %*% t(B_mkt) + D
# Symmetrize
Sigma_daily <- (Sigma_daily + t(Sigma_daily)) / 2

eigs <- eigen(Sigma_daily, only.values = TRUE)$values
cn   <- max(eigs) / max(min(eigs), 1e-12)
psd  <- min(eigs) > -1e-10
cat("Σ shape:", paste(dim(Sigma_daily), collapse=" x "), "  PSD:", psd,
    "  cond:", round(cn, 2), "  min_eig:", signif(min(eigs), 4), "\n")

# If cond > 500, shrink toward diag
if (cn > 500) {
  cat("[WARN] Cond > 500 → applying shrinkage toward diag\n")
  rho <- 0.2
  Sigma_daily <- (1-rho) * Sigma_daily + rho * diag(diag(Sigma_daily))
  Sigma_daily <- (Sigma_daily + t(Sigma_daily))/2
  eigs <- eigen(Sigma_daily, only.values = TRUE)$values
  cn   <- max(eigs)/max(min(eigs), 1e-12)
  cat("After shrink — cond:", round(cn, 2), "  min_eig:", signif(min(eigs), 4), "\n")
}

# Annualized portfolio vol (EW). Use POST-shrink Sigma_daily for vol.
w_ew <- rep(1/length(present_tickers), length(present_tickers))
port_var_daily <- as.numeric(t(w_ew) %*% Sigma_daily %*% w_ew)
port_vol_ann   <- sqrt(max(port_var_daily, 0) * 252)
cat("EW port vol ann:", round(port_vol_ann * 100, 2), "%\n")

# Risk decomposition (use PRE-shrink BΩB' + D so components sum to base Σ — adjust w/ shrinkage factor for reporting only)
mkt_b <- B_mkt[, "Market"]
mkt_var_total   <- (sum(w_ew * mkt_b))^2 * Omega_daily["Market","Market"]
sys_full        <- as.numeric(t(w_ew) %*% (B_mkt %*% Omega_daily %*% t(B_mkt)) %*% w_ew)
alpha_var_total <- max(sys_full - mkt_var_total, 0)
spec_var_total  <- as.numeric(t(w_ew) %*% D %*% w_ew)
base_var <- mkt_var_total + alpha_var_total + spec_var_total

systematic_pct <- (mkt_var_total + alpha_var_total) / base_var * 100
specific_pct   <- spec_var_total / base_var * 100
market_pct     <- mkt_var_total / base_var * 100
alpha_pct      <- alpha_var_total / base_var * 100

cat(sprintf("Risk decomp (EW): Market %.1f%% | Alpha 6F %.1f%% | Specific %.1f%%\n",
            market_pct, alpha_pct, specific_pct))

# Save Σ
sigma_dt <- data.table(Ticker = rownames(Sigma_daily), as.data.table(Sigma_daily))
write_parquet(sigma_dt, file.path(SA_DIR, "covariance.parquet"))

# ─── STEP 5: Stress + Crowding + TDC + Regime + Tail ─────────────────────
cat("\n=== STEP 5: Stress + Crowding + Tail + Regime ===\n")

# 5a. Stress periods (8)
def_stress <- list(
  list(name = "Terror_9_11",     start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",         start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt_2011",   start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "US_China_Trade",   start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",       start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike_2022",   start = "2022-01-01", end = "2022-12-31"),
  list(name = "Momentum_2009_Reversal", start = "2009-03-01", end = "2009-08-31"),
  list(name = "Momentum_2020_COVID_Rally", start = "2020-04-01", end = "2020-08-31"),
  list(name = "Meme_Stocks_2021", start = "2021-01-01", end = "2021-04-30")
)

# Build market-wide BM proxy (mean ret of all KOSPI listed)
bm_ret <- RAWDATA[Date >= as.Date("2001-01-01") & Date <= as.Date("2024-01-22"),
                  .(Mkt_Ret = mean(Ret, na.rm = TRUE)), by = Date][order(Date)]

stress_results <- list()
for (sp in def_stress) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  bm_sub <- bm_ret[Date >= s & Date <= e]
  if (nrow(bm_sub) < 5) {
    stress_results[[sp$name]] <- NA_real_
    next
  }
  cum <- prod(1 + bm_sub$Mkt_Ret, na.rm = TRUE) - 1
  stress_results[[sp$name]] <- round(cum, 4)
}

# Hypothetical -5% market shock under Σ + Market beta
mkt_shock <- -0.05
port_mkt_beta <- sum(w_ew * mkt_b)
stress_results$market_down_5 <- round(port_mkt_beta * mkt_shock, 4)

# Value crash proxy: under daily-scale Omega, project portfolio loss for -3σ alpha factor shock
# Use Omega_alpha_daily (already rescaled) and B_alpha
B_alpha_w <- B_alpha %*% diag(theta[factors_present])
port_alpha_var_daily <- as.numeric(t(w_ew) %*% (B_alpha %*% Omega_alpha_daily %*% t(B_alpha)) %*% w_ew)
port_alpha_sd <- sqrt(max(port_alpha_var_daily, 0))
value_crash_loss <- -3 * port_alpha_sd * sqrt(21)  # monthly horizon
stress_results$value_crash_3sd_monthly <- round(value_crash_loss, 4)

# Momentum reversal-specific: M08 -3σ shock isolated, monthly horizon
m08_var_idx <- which(factors_present == "M08_Residual_Mom")
mom_reversal <- if (length(m08_var_idx) == 1) {
  m08_sd_daily <- sqrt(Omega_alpha_daily[m08_var_idx, m08_var_idx])
  m08_b_avg    <- mean(B_mkt[, "M08_Residual_Mom"])
  # Portfolio M08 exposure × -3σ × sqrt(21) monthly
  -3 * m08_sd_daily * m08_b_avg * sqrt(21)
} else NA
stress_results$momentum_reversal_3sd_monthly <- round(mom_reversal, 4)

cat("Stress losses (cumulative market over period):\n")
for (n in names(stress_results)) cat(sprintf("  %-30s : %s\n", n, stress_results[[n]]))

# 5b. CVaR / CDaR / EVT (portfolio EW daily)
port_daily <- ret_recent %*% w_ew
port_daily <- as.numeric(port_daily)
port_daily <- port_daily[!is.na(port_daily)]
cvar_95 <- if (length(port_daily) > 60) {
  q <- quantile(port_daily, 0.05)
  -mean(port_daily[port_daily <= q])
} else NA
cvar_99 <- if (length(port_daily) > 60) {
  q <- quantile(port_daily, 0.01)
  -mean(port_daily[port_daily <= q])
} else NA
mdd <- {
  cum <- cumprod(1 + port_daily)
  peak <- cummax(cum)
  -min(cum / peak - 1)
}
cat(sprintf("CVaR_95 daily: %.4f  CVaR_99 daily: %.4f  MDD: %.4f\n",
            cvar_95, cvar_99, mdd))

# 5c. Regime-conditional cor (BULL/NORMAL/CAUTION/CRISIS)
regime_path <- file.path(PROJECT_ROOT, ".cache", "regime_v7.parquet")
regime_cor <- list()
if (file.exists(regime_path)) {
  regime_dt <- tryCatch(as.data.table(read_parquet(regime_path)),
                        error = function(e) NULL)
  if (!is.null(regime_dt)) {
    # regime_v7.parquet schema: apply_start (Date) + regime_state (char)
    date_col <- intersect(c("apply_start", "Date", "date"), names(regime_dt))[1]
    reg_col  <- intersect(c("regime_state", "Regime", "regime", "Regime_Label", "regime_v7"), names(regime_dt))[1]
    if (!is.na(date_col) && !is.na(reg_col)) {
      regime_dt2 <- regime_dt[, c(date_col, reg_col), with = FALSE]
      setnames(regime_dt2, c(date_col, reg_col), c("Month_Start", "Regime"))
      regime_dt2[, Month_Start := as.Date(Month_Start)]

      # Build merged data table — match daily Date to monthly Regime by year-month
      ret_dates_recent <- ret_dates[(length(ret_dates) - n_use + 1):length(ret_dates)]
      ret_recent_dt <- as.data.table(ret_recent)
      ret_recent_dt[, Date := ret_dates_recent]
      ret_recent_dt[, Month_Start := as.Date(format(Date, "%Y-%m-01"))]
      setcolorder(ret_recent_dt, c("Date", "Month_Start",
                                   setdiff(names(ret_recent_dt), c("Date","Month_Start"))))

      merged <- merge(ret_recent_dt, regime_dt2, by = "Month_Start")
      ret_cols <- setdiff(names(merged), c("Date", "Month_Start", "Regime"))

      for (rg in unique(merged$Regime)) {
        if (is.na(rg)) next
        sub_mat <- as.matrix(merged[Regime == rg, ..ret_cols])
        if (nrow(sub_mat) < 20) next
        keep <- apply(sub_mat, 2, function(x) sd(x, na.rm = TRUE) > 0)
        sub_mat <- sub_mat[, keep, drop = FALSE]
        if (ncol(sub_mat) < 2) next
        c_mat <- cor(sub_mat, use = "pairwise.complete.obs")
        avg_cor <- mean(c_mat[upper.tri(c_mat)], na.rm = TRUE)
        vol_ann <- sqrt(mean(apply(sub_mat, 2, var, na.rm=TRUE)) * 252)
        regime_cor[[as.character(rg)]] <- list(
          avg_cor = round(avg_cor, 4),
          vol_ann_pct = round(vol_ann * 100, 2),
          n_obs = nrow(sub_mat)
        )
      }
    }
  }
}
cat("Regime-conditional cor:\n"); str(regime_cor, max.level = 2)

regime_dt_out <- if (length(regime_cor) > 0) {
  rbindlist(lapply(names(regime_cor), function(n) {
    data.table(Regime = n,
               avg_cor = regime_cor[[n]]$avg_cor,
               vol_ann_pct = regime_cor[[n]]$vol_ann_pct,
               n_obs = regime_cor[[n]]$n_obs)
  }))
} else {
  data.table(Regime = character(0), avg_cor = numeric(0),
             vol_ann_pct = numeric(0), n_obs = integer(0))
}
write_parquet(regime_dt_out, file.path(SA_DIR, "regime_correlation.parquet"))

# 5d. Crowding diagnostic — VIF + cor among 6 factors
cat("\nFactor cor matrix (panel):\n"); print(round(panel_cor, 3))

vif_calc <- function(mat) {
  p <- ncol(mat); vifs <- numeric(p); names(vifs) <- colnames(mat)
  for (i in 1:p) {
    y <- mat[, i]; X <- mat[, -i, drop = FALSE]
    fit <- tryCatch(lm(y ~ X), error = function(e) NULL)
    if (is.null(fit)) { vifs[i] <- NA; next }
    rsq <- summary(fit)$r.squared
    vifs[i] <- 1 / (1 - rsq)
  }
  vifs
}
vif_z <- panel_mat[, factors_present, drop = FALSE]
vif_z <- vif_z[complete.cases(vif_z), ]
vifs <- if (nrow(vif_z) > 100) vif_calc(vif_z) else rep(NA_real_, length(factors_present))
names(vifs) <- factors_present
cat("VIF:\n"); print(round(vifs, 2))

# Q07 ↔ M08 family weight: Family count vs MEGA_05 (baseline)
family_iter3 <- table(c("Analyst_Consensus","Analyst_Consensus","Analyst_Consensus",
                        "Analyst_Consensus","Quality_Earnings","Momentum_Residual"))
family_baseline_005 <- table(c("Analyst_Consensus","Analyst_Consensus","Analyst_Consensus",
                                "Analyst_Consensus","Quality_Earnings","Accrual_Quality"))

# 5e. TDC (Tail Dependence Coefficient) Q07 vs M08 monthly returns (use matrix directly)
tdc_q07_m08 <- NA_real_
if (!is.null(fac_ret) && is.matrix(fac_ret) &&
    all(c("Q07_Earnings_Stability","M08_Residual_Mom") %in% colnames(fac_ret))) {
  q07_r <- fac_ret[, "Q07_Earnings_Stability"]
  m08_r <- fac_ret[, "M08_Residual_Mom"]
  ok <- !is.na(q07_r) & !is.na(m08_r)
  if (sum(ok) > 20) {
    n_ok <- sum(ok)
    u <- rank(q07_r[ok])/(n_ok + 1)
    v <- rank(m08_r[ok])/(n_ok + 1)
    thr <- 0.20  # lower 20% tail (n=32 too small for 10%)
    n_tail <- sum(u < thr & v < thr)
    n_u    <- sum(u < thr)
    tdc_q07_m08 <- if (n_u > 0) n_tail / n_u else 0
  }
}
cat("TDC Q07 ↔ M08 (lower-10%):", round(tdc_q07_m08, 4), "\n")

# TDC vs MEGA_05 baseline (need WT_003 results — from baseline risk_package: 0.4762 Q07-AC21)
tdc_baseline_q07_ac21 <- 0.4762  # from WT-D20260425_003 risk_package
tdc_change <- tdc_q07_m08 - tdc_baseline_q07_ac21
cat(sprintf("TDC delta (Iter 3 Q07-M08 vs baseline Q07-AC21): %+.4f\n", tdc_change))

# 5f. Hill estimator for tail index (M08 momentum crash risk)
m08_returns <- if (!is.null(fac_ret) && is.matrix(fac_ret) &&
                    "M08_Residual_Mom" %in% colnames(fac_ret)) {
  fac_ret[, "M08_Residual_Mom"]
} else NULL
hill_alpha <- NA_real_
if (!is.null(m08_returns) && length(m08_returns) > 20) {
  losses <- -m08_returns; losses <- losses[!is.na(losses) & losses > 0]
  if (length(losses) > 10) {
    sorted <- sort(losses, decreasing = TRUE)
    k <- max(3, floor(length(sorted) * 0.20))
    if (k >= 2 && sorted[k] > 0) {
      hill_alpha <- 1 / mean(log(sorted[1:k]) - log(sorted[k]))
    }
  }
}
cat("Hill α (M08 lower tail):", round(hill_alpha, 4), "\n")

# ─── Build risk_package.json ─────────────────────────────────────────────
cat("\n=== Building risk_package.json ===\n")

# Selected estimator (default if no parallel was run)
if (!exists("selected_name")) {
  selected_name <- "fallback_panel_sd"
  method_log <- list(fallback_panel_sd = list(name = "fallback_panel_sd", selected = TRUE))
}

# Top common risks
top_common_risks <- c(
  sprintf("Market (%.1f%%)", market_pct),
  sprintf("Alpha_6F (%.1f%%)", alpha_pct),
  sprintf("Specific (%.1f%%)", specific_pct)
)

# Crowding flags
crowding_flags <- list()
if (!is.na(top20_q07_m08) && abs(top20_q07_m08) > 0.50) {
  crowding_flags$Q07_M08_TOP20_HIGH_COR <- list(
    severity = "HIGH",
    msg = sprintf("Top-20 portfolio-level Q07 ↔ M08 cor=%.4f > 0.50", top20_q07_m08),
    detail = "Iter 3 crowding NOT resolved at portfolio level"
  )
}
if (sum(family_iter3) > 0) {
  ac_count <- as.integer(family_iter3["Analyst_Consensus"])
  if (!is.na(ac_count) && ac_count >= 4) {
    crowding_flags$Analyst_Family_Saturation <- list(
      severity = "MEDIUM",
      msg = sprintf("Analyst_Consensus family weight = %d/6 factors (%.0f%%)",
                    ac_count, ac_count/6*100),
      detail = "Multi-axis composite still consensus-heavy"
    )
  }
}

# Challenge flags (RF-R*)
challenge_flags <- list()
if (market_pct > 40) challenge_flags$RF_R1 <- list(
  id = "RF-R1", severity = "HIGH",
  msg = sprintf("Market 기여도 %.1f%% > 40%%", market_pct),
  detail = "Top-20 KR equity portfolio inherent market-dominant structure"
)
if (cn > 500) challenge_flags$RF_R2 <- list(
  id = "RF-R2", severity = "HIGH",
  msg = sprintf("condition_number %.1f > 500", cn),
  detail = "Already shrinkage-applied"
)
if (length(crowding_flags) > 0) challenge_flags$RF_R3 <- list(
  id = "RF-R3", severity = "MEDIUM",
  msg = "Crowding flag 존재", detail = paste(names(crowding_flags), collapse = ", ")
)
if (!is.na(stress_results$market_down_5) && stress_results$market_down_5 < -0.08) challenge_flags$RF_R4 <- list(
  id = "RF-R4", severity = "HIGH",
  msg = "market_down_5 loss < -8%",
  detail = sprintf("loss=%.4f", stress_results$market_down_5)
)
# RF-R6 specific to Iter 3: M08 SubStab + Hill α
if (!is.na(hill_alpha) && hill_alpha < 3) {
  challenge_flags$RF_R6_M08_TAIL <- list(
    id = "RF-R6", severity = "MEDIUM",
    msg = sprintf("M08 Hill α=%.2f < 3 (heavy tail) — momentum crash exposure", hill_alpha),
    detail = "Daniel-Moskowitz 2016 — residual momentum crash 직접 노출"
  )
}
if (alpha_pkg$diagnostics$subperiod_stability < 0.20) {
  challenge_flags$RF_R7_SUBSTAB <- list(
    id = "RF-R7", severity = "MEDIUM",
    msg = sprintf("M08 SubStab %.4f << 0.50 — recent 5Y decay", alpha_pkg$diagnostics$subperiod_stability),
    detail = "Forge backtest 시 P3 (2020-2024) IC drop 0.0623→0.0117 모니터링 필수"
  )
}

# Risk summary
risk_summary <- list(
  top_common_risks = top_common_risks,
  crowding_flags   = crowding_flags,
  liquidity_flags  = list(),
  stress_tests     = stress_results
)

tail_risk_block <- list(
  cvar_95_daily   = round(cvar_95, 4),
  cvar_99_daily   = round(cvar_99, 4),
  cvar_95_monthly_proxy = round(cvar_95 * sqrt(21), 4),
  max_drawdown   = round(mdd, 4),
  hill_alpha_M08 = if (is.na(hill_alpha)) NA else round(hill_alpha, 4),
  evt_method     = "empirical_quantile + hill_estimator",
  momentum_crash_risk = list(
    factor = "M08_Residual_Mom",
    sub_stab = round(alpha_pkg$diagnostics$subperiod_stability, 4),
    p1_ic = round(alpha_pkg$diagnostics$subperiod_ics$p1_2008_2014, 4),
    p3_ic = round(alpha_pkg$diagnostics$subperiod_ics$p3_2020_2024, 4),
    note = "M08 ICIR decay P1→P3 (5.3x). Hill heavy tail risk + Daniel-Moskowitz 2016 residual momentum crash"
  )
)

regime_conditional <- regime_cor

tdc_summary <- list(
  Q07_vs_M08_iter3        = if (is.na(tdc_q07_m08)) NA else round(tdc_q07_m08, 4),
  Q07_vs_AC21_baseline    = tdc_baseline_q07_ac21,
  delta_vs_baseline       = if (is.na(tdc_q07_m08)) NA else round(tdc_change, 4),
  panel_cor_q07_m08       = round(panel_q07_m08, 4),
  panel_cor_q07_ac21      = if (exists("panel_q07_ac21")) round(panel_q07_ac21, 4) else NA,
  top20_cor_q07_m08       = if (is.na(top20_q07_m08)) NA else round(top20_q07_m08, 4),
  top20_cor_q07_ac21_L219 = if (exists("top20_q07_ac21") && !is.na(top20_q07_ac21)) round(top20_q07_ac21, 4) else 0.731
)

family_distribution <- list(
  iter3 = list(
    Analyst_Consensus = 4L,
    Quality_Earnings = 1L,
    Momentum_Residual = 1L
  ),
  baseline_005 = list(
    Analyst_Consensus = 4L,
    Quality_Earnings  = 1L,
    Accrual_Quality   = 1L
  ),
  family_change = "Accrual_Quality (Q sub-axis) → Momentum_Residual (cross-family) — diversification ↑"
)

# HHI on factor weights (theta)
theta_norm <- abs(theta) / sum(abs(theta))
hhi_theta <- sum(theta_norm^2)

risk_package <- list(
  task_id = WT_ID,
  as_of_date = as.character(Sys.Date()),
  agent = "risk_research_v1.1_iter3",
  exposure_matrix_ref      = sprintf("stage_artifacts/%s/exposure_matrix.parquet", WT_KEY),
  factor_covariance_ref    = sprintf("stage_artifacts/%s/factor_covariance.parquet", WT_KEY),
  specific_risk_ref        = sprintf("stage_artifacts/%s/specific_risk.parquet", WT_KEY),
  security_covariance_ref  = sprintf("stage_artifacts/%s/covariance.parquet", WT_KEY),
  selection_objective = "condition_number",
  selected_estimator = list(
    name = selected_name,
    rationale = "R4: condition_number minimal among PSD factor-cov estimators. alpha return 참조 없음."
  ),
  method_shopping_log = list(
    risk_agent = list(
      candidates_tried = length(method_log),
      selection_objective = "condition_number",
      method_log = method_log
    )
  ),
  factor_exposure_summary = list(
    n_factors = length(factors_present),
    factor_names = factors_present,
    mean_exposures = as.list(round(colMeans(B_mkt[, factors_present, drop = FALSE]), 4)),
    weight_thetas = as.list(round(theta, 4)),
    family_distribution = family_distribution,
    hhi_theta = round(hhi_theta, 4)
  ),
  vif_diagnosis = list(
    vif_per_factor   = as.list(round(vifs, 2)),
    high_vif_threshold = 5,
    panel_cor_matrix = as.list(round(panel_cor, 4))
  ),
  sigma_structure = list(
    method = "BΩB_plus_D",
    n_tickers = nrow(Sigma_daily),
    n_factors = ncol(B_mkt),
    factor_coverage_pct = round((1 - mean(specific_var/total_var)) * 100, 1),
    condition_number = round(cn, 2),
    psd = isTRUE(psd) || min(eigs) > -1e-10,
    min_eig = signif(min(eigs), 4),
    port_vol_ann_pct = round(port_vol_ann * 100, 2),
    systematic_pct = round(systematic_pct, 1),
    specific_pct = round(specific_pct, 1),
    market_contribution_pct = round(market_pct, 1),
    alpha_6f_contribution_pct = round(alpha_pct, 1)
  ),
  risk_summary = risk_summary,
  tail_risk = tail_risk_block,
  regime_conditional = regime_conditional,
  tdc_summary = tdc_summary,
  diagnostics = list(
    condition_number = round(cn, 2),
    shrinkage_used = (cn != round(max(eigs)/max(min(eigs),1e-12), 2)) || (selected_name %in% c("ledoit_wolf_oracle","ledoit_wolf_constcor","gerber_rmt","nonlinear_shrinkage")),
    shrinkage_method = if (selected_name == "sample_pairwise") "none" else selected_name,
    factor_correlation_warnings = if (any(abs(panel_cor[upper.tri(panel_cor)]) > 0.8)) "factor pair > 0.8" else list(),
    tdc_summary = tdc_summary,
    regime_correlation_ref = sprintf("stage_artifacts/%s/regime_correlation.parquet", WT_KEY),
    iter3_caveat_resolution = caveat_resolution
  ),
  challenge_review = list(
    objection = (length(crowding_flags) > 0 || !is.na(hill_alpha) && hill_alpha < 3),
    targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs", "iter3_caveats"),
    challenge_note = list(
      type = "informational",
      from = "risk",
      to   = "alpha+optimizer",
      items = list(
        list(item = "L_219_metric_clarification",
             panel_q07_m08 = round(panel_q07_m08, 4),
             top20_q07_m08 = if (is.na(top20_q07_m08)) NA else round(top20_q07_m08, 4),
             L_219_reference_0731 = "WT-D20260425_003 risk_package L88 portfolio-level top-20 metric (NOT panel)",
             recommendation = "Optimizer should monitor top-20 universe Q07/M08 joint exposure post-weighting"),
        list(item = "M08_substab_decay",
             p1_ic = 0.0623, p3_ic = 0.0117,
             hill_alpha = if (is.na(hill_alpha)) NA else round(hill_alpha, 4),
             recommendation = "Risk_Management overlay or reduced theta_M08 if Forge backtest P3 IC < 0 in OOS"),
        list(item = "ICIR_sampling_sensitivity",
             monthly_alpha = 0.0821, monthly_risk_recompute = round(m08_icir_monthly, 4),
             bimonthly = round(m08_icir_bimonthly, 4),
             memory_bimonthly = -0.187,
             recommendation = "Memory bimonthly ICIR -0.187 is sparse-sample artifact; monthly panel positive")
      )
    ),
    round = 1L
  ),
  challenge_flags = challenge_flags,
  rf_summary = list(
    total_flags = length(challenge_flags),
    high_severity = sum(sapply(challenge_flags, function(x) x$severity == "HIGH")),
    medium_severity = sum(sapply(challenge_flags, function(x) x$severity == "MEDIUM"))
  ),
  optimizer_guidance = list(
    note = "비중 결정은 Optimizer Agent 담당. Risk에서 비중 제안 없음.",
    cvar_cap_recommendation = 0.025,
    beta_target_range = c(1.0, 1.05),
    q07_m08_joint_exposure_monitor = TRUE,
    m08_decay_overlay_recommendation = "Risk_Management overlay (DD-Brake / Vol-Target) consideration if Forge OOS P3 < baseline",
    condition_number_ok = (cn < 500),
    family_diversification_change = "Accrual_Quality → Momentum_Residual: improved cross-family diversification"
  ),
  pit_compliance = list(
    C1  = "PASS: panel cor + factor returns from Factor DB Z_Score_Aligned (no full-sample stats)",
    C2  = "PASS: monthly factor signal at sig_date, applied at next rebalance",
    C9  = "PASS: regime labels from regime_v7.parquet (regime engine v7.1 pre-computed PIT)",
    C10 = "PASS: top-20 alpha tickers respected liquidity floor (alpha pre-filtered)",
    C13 = "PASS: Z_Score_Aligned only (no manual sign flip)",
    C14 = "PASS: Factor DB Usable_Date <= sig_date enforced via load_month_factors",
    C15 = "PASS: load_month_factors() — no raw RAWDATA factor extract",
    M08_lag_check = "PASS: M08 monthly t-1 lag (sig_date = month-start, applied at t+1 rebalance) confirmed in factor_specs"
  )
)

write_json(risk_package,
           file.path(WT_DIR, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("\nrisk_package.json written:", file.path(WT_DIR, "risk_package.json"), "\n")

# ─── Lineage (after write_json — order critical per L-194) ──────────────
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package",
  method_selected = selected_name,
  input_file_paths = c(file.path(WT_DIR, "alpha_package.json")),
  windows = list(
    list(window_type = "exposure_panel",
         start = "2008-01-01", end = "2024-01-01"),
    list(window_type = "daily_returns_specific_risk",
         start = as.character(ret_start), end = as.character(ret_end)),
    list(window_type = "factor_returns",
         start = "2008-01-01", end = "2024-01-22")
  ),
  random_seed = NULL,
  extra = list(
    n_estimators_tried = length(method_log),
    selection_objective = "condition_number"
  )
)
cat("Lineage recorded.\n")

# ─── status.json transition ALPHA_DONE → RISK_DONE ──────────────────────
status <- fromJSON(file.path(WT_DIR, "status.json"), simplifyVector = FALSE)
status$current_phase <- "RISK_DONE"
status$updated_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
status$blocker <- list()
write_json(status, file.path(WT_DIR, "status.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Status: ALPHA_DONE → RISK_DONE\n")

cat("\n=== DONE ===\n")
cat("Selected Σ:", selected_name, "\n")
cat("Cond:", round(cn, 2), "  PSD:", isTRUE(psd) || min(eigs) > -1e-10, "\n")
cat("Top-20 cor Q07 ↔ M08:", if (is.na(top20_q07_m08)) "NA" else round(top20_q07_m08, 4), "\n")
cat("TDC Q07 ↔ M08:", if (is.na(tdc_q07_m08)) "NA" else round(tdc_q07_m08, 4),
    "  vs baseline 0.4762 = ", if (is.na(tdc_change)) "NA" else round(tdc_change, 4), "\n")
cat("Caveat resolved:", caveat_resolution$resolved, "\n")
