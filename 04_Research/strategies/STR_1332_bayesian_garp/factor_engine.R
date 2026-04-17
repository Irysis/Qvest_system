#==============================================================================
# STR_1332 — Bayesian Shrinkage GARP (Growth at Reasonable Price)
#
# 핵심아이디어: V×Q interaction (§6B 미시도).
#   Core 75% (Bayesian Shrinkage): V02_EP + Q04_Piotroski_F + Q07_EarnStab + GR01_RevGrowth
#   Defense 25% (Fixed): D01_IdioVol
#   w_post = (1-lambda)*w_OLS + lambda*w_EW
#   lambda = expanding window CV. w_OLS = expanding Fama-MacBeth cross-section regression
#
# PIT: C1(expanding only), C12(lambda expanding CV), C13/C14/C15
# Academic: Novy-Marx(2013), Ledoit&Wolf(2004), Asness et al.(2019)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

cat("[factor_engine] STR_1332: Bayesian Shrinkage GARP...\n")

# ---- Constants ----
CORE_FACTORS   <- c("V02_EP", "Q04_Piotroski_F", "Q07_Earnings_Stability", "GR01_Revenue_Growth")
DEFENSE_FACTOR <- "D01_IdioVol"
GATE_FACTOR    <- "D47_CVaR_5pct"
ALL_FACTORS    <- c(CORE_FACTORS, DEFENSE_FACTOR, GATE_FACTOR)

DEFENSE_WEIGHT <- 0.25
CORE_WEIGHT    <- 0.75
GATE_QUANTILE  <- 0.10  # bottom 10% CVaR exclude (worst tail risk)
MIN_OBS_FM     <- 36L   # minimum months for Fama-MacBeth

# ---- History for Fama-MacBeth expanding window ----
.fm_history <- list()  # sig_date -> dt(Ticker, factor scores, fwd_ret)

record_fm_data <- function(sig_d, score_dt) {
  .fm_history[[as.character(sig_d)]] <<- copy(score_dt)
}

#' Expanding window Fama-MacBeth cross-section regression
#' Returns OLS weights (beta coefficients normalized to sum=1)
compute_fm_weights <- function(sig_d, factor_cols) {
  past_dates <- sort(as.Date(names(.fm_history)))
  usable <- past_dates[past_dates <= (sig_d - 25)]

  k <- length(factor_cols)
  ew <- setNames(rep(1/k, k), factor_cols)

  if (length(usable) < MIN_OBS_FM) return(list(w_post = ew, lambda = 1.0))

  # Collect cross-sectional regressions
  betas_list <- list()
  for (ud in usable) {
    scores_k <- .fm_history[[as.character(ud)]]
    if (is.null(scores_k) || nrow(scores_k) < 30) next

    next_dates <- past_dates[past_dates > ud]
    if (length(next_dates) == 0) next
    next_d <- next_dates[1]

    fwd_ret <- RAWDATA[Date > ud & Date <= next_d,
                       .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    merged <- merge(scores_k, fwd_ret, by = "Ticker")
    merged <- merged[!is.na(fwd_ret) & is.finite(fwd_ret)]
    if (nrow(merged) < 30) next

    # Cross-section OLS: fwd_ret ~ factor1 + factor2 + ...
    x_mat <- as.matrix(merged[, factor_cols, with = FALSE])
    x_mat[is.na(x_mat)] <- 0
    y <- merged$fwd_ret

    fit <- tryCatch(.lm.fit(cbind(1, x_mat), y), error = function(e) NULL)
    if (!is.null(fit)) {
      betas <- fit$coefficients[-1]  # exclude intercept
      names(betas) <- factor_cols
      betas_list[[length(betas_list) + 1L]] <- betas
    }
  }

  if (length(betas_list) < MIN_OBS_FM) return(list(w_post = ew, lambda = 1.0))

  beta_mat <- do.call(rbind, betas_list)
  w_ols <- colMeans(beta_mat, na.rm = TRUE)
  w_ols <- pmax(w_ols, 0)  # non-negative constraint
  if (sum(w_ols) < 1e-8) return(list(w_post = ew, lambda = 1.0))
  w_ols <- w_ols / sum(w_ols)

  # Lambda via expanding window cross-validation
  # Simple shrinkage intensity: lambda = 1 / (1 + T/k)
  # where T = number of months, k = number of factors
  T_months <- length(betas_list)
  lambda <- k / (k + T_months)
  lambda <- pmin(pmax(lambda, 0.1), 0.9)  # bound [0.1, 0.9]

  w_post <- (1 - lambda) * w_ols + lambda * ew

  list(w_post = w_post, lambda = lambda)
}

compute_bayesian_garp_scores <- function(sig_d, fdb_month, rawdata_snap) {
  avail <- fdb_month[Factor_Name %in% ALL_FACTORS]
  avail_factors <- unique(avail$Factor_Name)

  if (sum(CORE_FACTORS %in% avail_factors) < 2L) return(NULL)
  if (!(DEFENSE_FACTOR %in% avail_factors)) return(NULL)

  scores_wide <- dcast(avail, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Liquidity filter
  liq_tickers <- rawdata_snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD, Ticker]
  scores_wide <- scores_wide[Ticker %in% liq_tickers]
  if (nrow(scores_wide) < 30L) return(NULL)

  # Gate: CVaR bottom 10% exclude (worst tail risk)
  if (GATE_FACTOR %in% names(scores_wide)) {
    cvar_vals <- scores_wide[[GATE_FACTOR]]
    if (sum(!is.na(cvar_vals)) > 50) {
      cvar_thr <- quantile(cvar_vals[!is.na(cvar_vals)], GATE_QUANTILE)
      scores_wide <- scores_wide[is.na(get(GATE_FACTOR)) | get(GATE_FACTOR) >= cvar_thr]
    }
  }
  if (nrow(scores_wide) < 30L) return(NULL)

  avail_core <- intersect(CORE_FACTORS, names(scores_wide))

  # Record for FM
  fm_record <- scores_wide[, c("Ticker", avail_core), with = FALSE]
  record_fm_data(sig_d, fm_record)

  # Bayesian shrinkage weights
  fm_result <- compute_fm_weights(sig_d, avail_core)
  w_post <- fm_result$w_post[avail_core]
  w_post <- w_post / sum(w_post)

  # Core score
  core_mat <- as.matrix(scores_wide[, avail_core, with = FALSE])
  core_mat[is.na(core_mat)] <- 0
  scores_wide[, core_score := as.numeric(core_mat %*% w_post)]

  # Defense
  scores_wide[, defense_score := get(DEFENSE_FACTOR)]
  scores_wide[is.na(defense_score), defense_score := 0]

  # Combined
  scores_wide[, Score := CORE_WEIGHT * core_score + DEFENSE_WEIGHT * defense_score]
  scores_wide <- scores_wide[!is.na(Score)]
  if (nrow(scores_wide) < 30L) return(NULL)

  # Sector neutral
  sector_map <- rawdata_snap[, .(Ticker, Sector)]
  scores_wide <- merge(scores_wide, sector_map, by = "Ticker", all.x = TRUE)
  scores_wide[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]

  scores_wide[, Date := sig_d]
  scores_wide[, .(Date, Ticker, Score)]
}

cat("[factor_engine] Ready: compute_bayesian_garp_scores()\n")
