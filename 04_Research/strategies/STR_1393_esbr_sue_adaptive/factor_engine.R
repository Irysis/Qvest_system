# STR_1393: ESBR + SUE Adaptive IC Weight (GR02+Q17+Q23) — Factor Engine
# MF_09: FC_2c BayesShrinkage + Quality trending 3F
# Academic: Novy-Marx(2013) profitability. L-549/551: EW OOS 붕괴 → Bayes 필요.
cat("[factor_engine] STR_1393: ESBR + SUE Adaptive IC Weight...\n")
set.seed(1393)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD  <- 2e8
NEEDED_FACTORS <- c("C04_ESBR", "C01_SUE")
WARMUP_MONTHS  <- 36L  # minimum expanding window

# ── Factor DB: Arrow Dataset ──
ds <- open_dataset(file.path(CACHE_DIR, "factor_db"), format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | %d factors\n", nrow(FDB_ALL), uniqueN(FDB_ALL$Factor_Name)))

# ── Monthly signal dates ──
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]

# ── Liquidity (t-1 lagged, C10) ──
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# ── Triple Gate ──
RAWDATA[, TradeDay := as.integer(!is.na(Close) & Close > 0)]
RAWDATA[, DaysInv252 := shift(frollsum(TradeDay, n = 252L, align = "right"),
                               n = 1L, type = "lag"), by = Ticker]
RAWDATA[, Ret42d := shift(Close, n = 0L, type = "lag") /
                    shift(Close, n = 42L, type = "lag") - 1, by = Ticker]
RAWDATA[, Ret42d_lag := shift(Ret42d, n = 1L, type = "lag"), by = Ticker]

# ── Pre-compute: for each month, collect Z-scores + next-month returns ──
# Used by BayesShrinkage expanding OLS
fdb_dates <- sort(unique(FDB_ALL$Date))
monthly_z_ret <- vector("list", length(monthly_dates))

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) next
  fdt <- FDB_ALL[Date == max(valid_fdb) & Coverage == TRUE]
  if (nrow(fdt) == 0L) next
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Merge liquidity
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, DaysInv252, Ret42d_lag)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  fdt_wide <- fdt_wide[!is.na(DaysInv252) & DaysInv252 >= 227L]
  if (sum(!is.na(fdt_wide$Ret42d_lag)) >= 20L) {
    q05 <- quantile(fdt_wide$Ret42d_lag, 0.05, na.rm = TRUE)
    fdt_wide <- fdt_wide[is.na(Ret42d_lag) | Ret42d_lag >= q05]
  }

  # Next-month return (t -> t+1, for expanding OLS training data)
  if (i < length(monthly_dates)) {
    next_d <- as.Date(monthly_dates[i + 1])
    fwd_ret <- RAWDATA[Date == next_d, .(Ticker, Fwd_Ret = Ret)]
    fdt_wide <- merge(fdt_wide, fwd_ret, by = "Ticker", all.x = TRUE)
  } else {
    fdt_wide[, Fwd_Ret := NA_real_]
  }

  fdt_wide[, Date_idx := i]
  fdt_wide[, Date := sig_d]
  monthly_z_ret[[i]] <- fdt_wide
}

ALL_ZR <- rbindlist(monthly_z_ret[!sapply(monthly_z_ret, is.null)], fill = TRUE)
cat(sprintf("  Monthly Z+Ret: %d rows, %d months\n", nrow(ALL_ZR), uniqueN(ALL_ZR$Date_idx)))

# ── BayesShrinkage: expanding window OLS + lambda from expanding CV ──
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  cur_idx <- i

  # Need WARMUP_MONTHS of prior data for OLS
  if (cur_idx <= WARMUP_MONTHS) { n_skipped <- n_skipped + 1L; next }

  # Current month universe
  cur <- ALL_ZR[Date == sig_d]
  if (nrow(cur) < 30L) { n_skipped <- n_skipped + 1L; next }

  # Expanding training data: months 1 to (i-1), using REALIZED returns
  # Note: we only use data where we KNOW the outcome (past months) — NO future reference
  train <- ALL_ZR[Date_idx < cur_idx & !is.na(Fwd_Ret)]
  if (nrow(train) < 60L) { n_skipped <- n_skipped + 1L; next }

  # Check factor availability
  avail_factors <- intersect(NEEDED_FACTORS, names(train))
  avail_factors <- avail_factors[sapply(avail_factors, function(f) sum(!is.na(train[[f]])) >= 30L)]
  if (length(avail_factors) == 0L) { n_skipped <- n_skipped + 1L; next }

  # OLS: Fwd_Ret ~ factors (expanding window, NO future data)
  X_train <- as.matrix(train[, ..avail_factors])
  X_train[is.na(X_train)] <- 0
  y_train <- train$Fwd_Ret

  ols_fit <- tryCatch({
    fit <- .lm.fit(cbind(1, X_train), y_train)
    coefs <- fit$coefficients[-1]  # drop intercept
    names(coefs) <- avail_factors
    coefs[is.na(coefs)] <- 0
    coefs
  }, error = function(e) setNames(rep(0, length(avail_factors)), avail_factors))

  # Lambda: expanding CV (last 12 months OOS MSE comparison)
  # EW weights vs OLS weights — lambda controls shrinkage toward EW
  n_cv <- min(12L, cur_idx - WARMUP_MONTHS - 1L)
  if (n_cv >= 6L) {
    ew_w <- setNames(rep(1 / length(avail_factors), length(avail_factors)), avail_factors)
    cv_mse_ols <- 0; cv_mse_ew <- 0

    for (cv_j in seq_len(n_cv)) {
      cv_idx <- cur_idx - cv_j
      cv_data <- ALL_ZR[Date_idx == cv_idx & !is.na(Fwd_Ret)]
      if (nrow(cv_data) < 10L) next

      X_cv <- as.matrix(cv_data[, ..avail_factors])
      X_cv[is.na(X_cv)] <- 0
      y_cv <- cv_data$Fwd_Ret

      pred_ols <- X_cv %*% ols_fit[avail_factors]
      pred_ew  <- X_cv %*% ew_w[avail_factors]

      cv_mse_ols <- cv_mse_ols + mean((y_cv - pred_ols)^2)
      cv_mse_ew  <- cv_mse_ew  + mean((y_cv - pred_ew)^2)
    }

    # lambda: 0 = pure OLS, 1 = pure EW
    if (cv_mse_ols + cv_mse_ew > 0) {
      lambda <- cv_mse_ols / (cv_mse_ols + cv_mse_ew)
    } else {
      lambda <- 0.5
    }
    lambda <- pmax(0.1, pmin(0.9, lambda))
  } else {
    lambda <- 0.5  # default before enough CV data
  }

  # Posterior weights: (1-lambda)*OLS + lambda*EW
  ew_w <- setNames(rep(1 / length(avail_factors), length(avail_factors)), avail_factors)
  w_post <- (1 - lambda) * ols_fit[avail_factors] + lambda * ew_w[avail_factors]
  # Normalize to sum to 1 (preserving direction from Z_Score_Aligned)
  w_post <- w_post / sum(abs(w_post))

  # Score current universe
  X_cur <- as.matrix(cur[, ..avail_factors])
  X_cur[is.na(X_cur)] <- 0
  cur[, Score := as.numeric(X_cur %*% w_post[avail_factors])]

  cur[, Date := sig_d]
  factor_list[[i]] <- cur[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# Cleanup
for (col in c("YM", "TradingValue", "AvgTV20", "TradeDay", "DaysInv252",
              "Ret42d", "Ret42d_lag"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL, ds, ALL_ZR); gc(verbose = FALSE)
cat(sprintf("[factor_engine] STR_1393 ESBRSUEAdaptive: %d rows | %d dates (skipped %d, lambda last=%.2f)\n",
            nrow(FACTORS), n_done, n_skipped, lambda))
