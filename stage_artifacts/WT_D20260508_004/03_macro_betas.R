#==============================================================================
# WT-D20260508_004 — Step 3: Per-stock × per-macro Rolling β (PIT-safe)
#
# For each (Ticker, macro_shock_j, month t):
#   y_i,τ = α_i + β_mkt_i × R_mkt,τ + β_j_i × shock_j,τ + ε,  τ ∈ [t-23, t]
#   → β_j_i,t : sensitivity of stock i to unexpected macro shock j as of t-end
#
# PIT contract:
#   - β_j_i,t uses τ ∈ [t-23, t]  (returns and shocks at same τ are concurrent
#     RISK exposure; not lookahead because we use β_t-1 to predict R_t+1).
#   - In Step 4 we lag β by 1 month: predictor at t = β_j_i,(t-1)
#     → forecasts FwdRet_1M[t] (return month t→t+1).
#
# Output: macro_betas_monthly.parquet
#         (Ticker, ym, beta_<macro>, R2_partial, n_obs)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")

cat("[03] loading panel + shocks …\n")
panel <- as.data.table(read_parquet(file.path(OUT, "panel_monthly.parquet")))
shocks <- as.data.table(read_parquet(file.path(OUT, "macro_shocks_monthly.parquet")))

# Build benchmark (KOSPI200) monthly return = average of in_univ_eom==1 K200=1 ticker EW
# Simpler: use BM_Ret from rawdata if available, monthly aggregate
rd_bm <- as.data.table(read_parquet(file.path(PROJ, ".cache", "rawdata.parquet"),
                                    col_select = c("Date","Ticker","BM_Ret")))
rd_bm[, Date := as.Date(Date)]
rd_bm <- unique(rd_bm[!is.na(BM_Ret), .(Date, BM_Ret)])
setorder(rd_bm, Date)
rd_bm[, ym := format(Date, "%Y-%m")]
# Compound daily into monthly
bm_m <- rd_bm[, .(Date_eom = max(Date), BM_Ret_M = prod(1 + BM_Ret) - 1), by = ym]
cat("[03] BM monthly:", nrow(bm_m), "months, range",
    as.character(min(bm_m$Date_eom)), "-", as.character(max(bm_m$Date_eom)), "\n")

# Merge shocks + bm
setorder(shocks, Date)
shocks[, ym := format(Date, "%Y-%m")]
mac <- merge(shocks[, .SD, .SDcols = c("ym", grep("_resid$", names(shocks), value=TRUE))],
             bm_m[, .(ym, BM_Ret_M)], by = "ym", all.x = TRUE)

shock_cols <- grep("_resid$", names(mac), value = TRUE)
cat("[03] shock columns:", length(shock_cols), "\n")

# Subset panel: post-2010 + Ret_1M present
panel_use <- panel[!is.na(Ret_1M) & ym >= "2008-01"]  # earlier for burn-in

# Merge stock returns + bm + macro shocks
panel_use <- merge(panel_use, mac, by = "ym", all.x = TRUE)
setorder(panel_use, Ticker, ym)

# ---- Rolling 24M cross-section regressions per ticker ----
WINDOW <- 24L
MIN_OBS <- 18L
result_chunks <- list()

cat("[03] computing rolling β for", uniqueN(panel_use$Ticker), "tickers,",
    length(shock_cols), "macros, window =", WINDOW, "months …\n")

# Run per-macro because we want univariate β with mkt control:
# y = α + b_mkt * x_mkt + b_j * x_j + ε (per-macro per-ticker rolling 24M)
ticker_list <- unique(panel_use$Ticker)
n_t <- length(ticker_list)

t0 <- Sys.time()
res_list <- list()

# Vectorized per-ticker: build matrix of monthly Ret_1M, BM_Ret_M, and 12 shocks
# Then for each ticker, slide window and solve OLS via lm.fit (fast).
for (ti in seq_along(ticker_list)) {
  tk <- ticker_list[ti]
  sub <- panel_use[Ticker == tk]
  n_sub <- nrow(sub)
  if (n_sub < WINDOW + 1) next

  # Pre-extract numeric vectors
  y    <- sub$Ret_1M
  xmkt <- sub$BM_Ret_M
  ym_v <- sub$ym
  shock_mat <- as.matrix(sub[, ..shock_cols])

  # For each end-month idx in [WINDOW, n_sub], compute β for all shocks via partial
  # OLS. We do per-shock loop since shocks may have NA in different positions.
  n_shocks <- ncol(shock_mat)
  beta_mat <- matrix(NA_real_, nrow = n_sub, ncol = n_shocks)
  colnames(beta_mat) <- paste0("beta_", sub("_resid$", "", shock_cols))

  for (idx in WINDOW:n_sub) {
    rng <- (idx - WINDOW + 1):idx
    yw <- y[rng]; xm <- xmkt[rng]
    # Skip if too many NA in y or xm
    if (sum(!is.na(yw) & !is.na(xm)) < MIN_OBS) next

    for (j in seq_len(n_shocks)) {
      xs <- shock_mat[rng, j]
      ok <- !is.na(yw) & !is.na(xm) & !is.na(xs)
      if (sum(ok) < MIN_OBS) next
      X <- cbind(1, xm[ok], xs[ok])
      yy <- yw[ok]
      # OLS via solve(X'X) X'y
      XtX <- crossprod(X)
      Xty <- crossprod(X, yy)
      bhat <- tryCatch(solve(XtX, Xty), error = function(e) NULL)
      if (is.null(bhat) || !all(is.finite(bhat))) next
      beta_mat[idx, j] <- bhat[3]  # coefficient on shock_j
    }
  }
  # Bind back
  beta_dt <- as.data.table(beta_mat)
  beta_dt[, Ticker := tk]
  beta_dt[, ym := ym_v]
  res_list[[ti]] <- beta_dt

  if (ti %% 100 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta <- elapsed * (n_t - ti) / max(ti, 1)
    cat(sprintf("[03] %d/%d tickers (%.1fs elapsed, ETA %.1fs)\n",
                ti, n_t, elapsed, eta))
  }
}

beta_all <- rbindlist(res_list, fill = TRUE)
cat("[03] β panel rows:", nrow(beta_all), "\n")

# Drop rows with all-NA betas
beta_cols <- grep("^beta_", names(beta_all), value = TRUE)
beta_all[, has_any := rowSums(!is.na(.SD)) > 0, .SDcols = beta_cols]
beta_all <- beta_all[has_any == TRUE]
beta_all[, has_any := NULL]

# Save
write_parquet(beta_all, file.path(OUT, "macro_betas_monthly.parquet"))
cat("[03] saved macro_betas_monthly.parquet:", nrow(beta_all), "rows,",
    length(beta_cols), "β columns\n")
cat("[03] elapsed:", round(as.numeric(difftime(Sys.time(), t0, units="mins")),2), "min\n")

# Coverage diagnostic post-2010
cov_post <- beta_all[ym >= "2010-01", lapply(.SD, function(x) round(mean(!is.na(x)),3)),
                     .SDcols = beta_cols]
cat("[03] β coverage 2010+:\n"); print(cov_post)
