#==============================================================================
# Factor Research Pipeline v2.0
#
# S0-S7 프로세스의 핵심 계산 함수.
# 원칙: "Standalone 성과가 아니라 Marginal Contribution으로 판단한다."
#
# Functions:
#   compute_base_portfolio_sharpe()  — S4: active factor pool base Sharpe
#   compute_delta_sharpe()           — S4: 신규 팩터 추가 시 ΔSharpe
#   compute_ic_marginal()            — S4 단축: IC_marginal 스크리닝
#   compute_factor_orthogonality()   — S3: 288개 대비 직교성 분석
#   compute_spanning_test()          — S3: factor spanning regression
#   update_factor_lifecycle()        — S7: registry lifecycle 갱신
#
# PIT: 모든 함수는 sig_date 기준 Usable_Date IC만 사용.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ---- Paths ----
if (!exists("CACHE_DIR")) {
  source(file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure", "config.R"
  ))
}

FACTOR_REG_PATH <- file.path(FUNC_PATH, "factor_db", "factor_registry.json")

#==============================================================================
# S3: Orthogonality Scan
#==============================================================================

#' Compute orthogonality of a new factor against the existing factor pool.
#'
#' @param new_factor_z Named numeric vector (Ticker → Z_Score) of the new factor
#' @param sig_date Date. Signal date for loading existing factors
#' @param active_only Logical. Only compare against active factors? (default TRUE)
#' @return list:
#'   $pairwise_corr: data.table(Factor_Name, Corr) — correlation with each existing factor
#'   $max_corr: numeric — maximum absolute correlation
#'   $max_corr_factor: character — which existing factor is most correlated
#'   $category_corr: data.table(Category, Max_Corr) — max corr per category
#'   $independence: "independent" (<0.3) / "partial" (0.3-0.6) / "redundant" (>0.6)
compute_factor_orthogonality <- function(new_factor_z, sig_date, active_only = TRUE) {
  source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

  # Load existing factors
  fdt <- load_month_factors(sig_date, coverage_min = 0.01)

  # Filter to active if requested
  if (active_only) {
    reg <- jsonlite::fromJSON(FACTOR_REG_PATH)
    active_factors <- names(reg)[sapply(reg, function(x) {
      lc <- x$lifecycle
      is.null(lc) || lc$status == "active"
    })]
    fdt <- fdt[Factor_Name %in% active_factors]
  }

  # Pivot existing to wide: Ticker × Factor
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # New factor as data.table
  new_dt <- data.table(Ticker = names(new_factor_z), New_Z = as.numeric(new_factor_z))

  # Merge
  merged <- merge(fdt_wide, new_dt, by = "Ticker")
  if (nrow(merged) < 30) {
    return(list(pairwise_corr = data.table(), max_corr = NA, independence = "unknown"))
  }

  # Pairwise Spearman correlation
  factor_cols <- setdiff(names(merged), c("Ticker", "New_Z"))
  corr_list <- lapply(factor_cols, function(fc) {
    valid <- !is.na(merged[[fc]]) & !is.na(merged$New_Z)
    if (sum(valid) < 20) return(data.table(Factor_Name = fc, Corr = NA_real_))
    data.table(
      Factor_Name = fc,
      Corr = cor(merged[[fc]][valid], merged$New_Z[valid], method = "spearman")
    )
  })
  pairwise <- rbindlist(corr_list)
  pairwise <- pairwise[!is.na(Corr)]

  if (nrow(pairwise) == 0) {
    return(list(pairwise_corr = pairwise, max_corr = NA, independence = "unknown"))
  }

  # Max correlation
  max_idx <- which.max(abs(pairwise$Corr))
  max_corr <- abs(pairwise$Corr[max_idx])
  max_factor <- pairwise$Factor_Name[max_idx]

  # Independence classification
  independence <- if (max_corr < 0.3) "independent"
  else if (max_corr < 0.6) "partial"
  else "redundant"

  # Category-level max correlation
  pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
  cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm = TRUE)), by = Category]
  setorder(cat_corr, -Max_Corr)

  list(
    pairwise_corr = pairwise,
    max_corr = max_corr,
    max_corr_factor = max_factor,
    category_corr = cat_corr,
    independence = independence,
    n_compared = nrow(pairwise)
  )
}


#==============================================================================
# S3: Spanning Test
#==============================================================================

#' Factor spanning test: regress new factor on same-category factors.
#' If alpha (intercept) is significant, the new factor has unique information.
#'
#' @param new_factor_ic Numeric vector of monthly IC for the new factor
#' @param existing_ic_mat Matrix of monthly IC for existing factors (rows=months, cols=factors)
#' @return list: alpha, t_alpha, R2
compute_spanning_test <- function(new_factor_ic, existing_ic_mat) {
  valid <- !is.na(new_factor_ic) & complete.cases(existing_ic_mat)
  if (sum(valid) < 24) {
    return(list(alpha = NA, t_alpha = NA, R2 = NA))
  }

  y <- new_factor_ic[valid]
  X <- existing_ic_mat[valid, , drop = FALSE]

  fit <- tryCatch(lm(y ~ X), error = function(e) NULL)
  if (is.null(fit)) return(list(alpha = NA, t_alpha = NA, R2 = NA))

  coefs <- summary(fit)$coefficients
  list(
    alpha = coefs[1, 1],
    t_alpha = coefs[1, 3],
    R2 = summary(fit)$r.squared
  )
}


#==============================================================================
# S4: IC Marginal (quick screening)
#==============================================================================

#' Compute marginal IC contribution of a new factor.
#' IC_marginal = IC_new - Σ(β_i × IC_i) where β_i = corr(new, factor_i)
#'
#' @param new_factor_name Character. New factor ID
#' @param sig_date Date.
#' @return list: ic_marginal, ic_raw, passes_threshold (>0.005)
compute_ic_marginal <- function(new_factor_name, sig_date) {
  source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

  ic_all <- compute_rolling_ic_all(sig_date, min_months = 24)
  if (nrow(ic_all) == 0) return(list(ic_marginal = NA, passes = FALSE))

  new_ic <- ic_all[Factor_Name == new_factor_name]
  if (nrow(new_ic) == 0) return(list(ic_marginal = NA, passes = FALSE))

  ic_new <- new_ic$Mean_IC

  # Get pairwise correlations with existing factors
  # Use IC time-series correlation as proxy
  ic_hist <- as.data.table(read_parquet(
    file.path(CACHE_DIR, "factor_db", "factor_ic_monthly.parquet")
  ))
  ic_hist[, Date := as.Date(Date)]
  if ("Usable_Date" %in% names(ic_hist)) {
    ic_hist <- ic_hist[Usable_Date <= sig_date]
  } else {
    ic_hist <- ic_hist[Date < sig_date]
  }

  # New factor's IC time series
  new_ts <- ic_hist[Factor_Name == new_factor_name, .(Date, IC)]
  if (nrow(new_ts) < 24) return(list(ic_marginal = ic_new, passes = ic_new > 0.005))

  # Other factors' IC time series
  other_factors <- setdiff(ic_all$Factor_Name, new_factor_name)
  if (length(other_factors) == 0) return(list(ic_marginal = ic_new, passes = ic_new > 0.005))

  # Compute β_i (correlation with new factor's IC series)
  betas <- ic_hist[Factor_Name %in% other_factors, {
    merged <- merge(
      data.table(Date = Date, IC_other = IC),
      new_ts, by = "Date"
    )
    if (nrow(merged) < 12) list(beta = 0)
    else list(beta = cor(merged$IC_other, merged$IC, use = "complete.obs"))
  }, by = Factor_Name]

  # IC_marginal = IC_new - Σ(β_i × IC_i)
  other_ic <- ic_all[Factor_Name %in% other_factors, .(Factor_Name, Mean_IC)]
  betas <- merge(betas, other_ic, by = "Factor_Name")
  explained <- sum(betas$beta * betas$Mean_IC, na.rm = TRUE)

  ic_marginal <- ic_new - explained

  list(
    ic_raw = ic_new,
    ic_marginal = ic_marginal,
    ic_explained = explained,
    passes = ic_marginal > 0.005
  )
}


#==============================================================================
# S4: Delta Sharpe (full backtest)
#==============================================================================

#' Compute ΔSharpe from adding a new factor to the active pool.
#' Base = EW composite of active factors → run_monthly_simulation()
#' Extended = Base + new factor
#'
#' @param new_factor_dt data.table(Date, Ticker, Score) for the new factor
#' @param sig_dates Date vector. Signal dates to test
#' @param base_sharpe Numeric. Pre-computed base Sharpe (NULL = compute)
#' @return list: base_sharpe, extended_sharpe, delta_sharpe
compute_delta_sharpe <- function(new_factor_dt, sig_dates = NULL, base_sharpe = NULL) {
  # This function requires backtest infrastructure
  source(file.path(FUNC_PATH, "backtest_harness.R"))
  source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

  if (is.null(sig_dates)) {
    sig_dates <- sort(unique(new_factor_dt$Date))
  }

  # Base portfolio: EW composite of all active factors
  if (is.null(base_sharpe)) {
    cat("[S4] Computing base portfolio Sharpe...\n")
    base_factors <- rbindlist(lapply(sig_dates, function(sd) {
      fdt <- tryCatch(load_month_factors(sd), error = function(e) NULL)
      if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
      # EW composite across all factors
      scores <- fdt[, .(Score = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]
      scores[, Date := sd]
      scores[, .(Date, Ticker, Score)]
    }))

    if (nrow(base_factors) < 100) {
      return(list(base_sharpe = NA, extended_sharpe = NA, delta_sharpe = NA))
    }

    base_sim <- tryCatch(
      run_monthly_simulation(RAWDATA, BM_DT, base_factors,
                              n_holdings = 30, weight_method = "equal",
                              commission = 0.0015),
      error = function(e) NULL
    )
    if (is.null(base_sim)) return(list(base_sharpe = NA, extended_sharpe = NA, delta_sharpe = NA))

    base_perf <- summarise_perf(base_sim$strategy_xts, "base")
    base_sharpe <- base_perf$Sharpe
    cat(sprintf("[S4] Base Sharpe: %.3f\n", base_sharpe))
  }

  # Extended portfolio: base + new factor
  cat("[S4] Computing extended portfolio Sharpe...\n")
  ext_factors <- rbindlist(lapply(sig_dates, function(sd) {
    fdt <- tryCatch(load_month_factors(sd), error = function(e) NULL)
    if (is.null(fdt) || nrow(fdt) == 0) return(NULL)

    # EW composite of existing factors
    base_scores <- fdt[, .(Base_Score = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]

    # Add new factor (equal weight with base)
    new_month <- new_factor_dt[Date == sd, .(Ticker, New_Score = Score)]
    merged <- merge(base_scores, new_month, by = "Ticker", all.x = TRUE)
    merged[is.na(New_Score), New_Score := 0]
    merged[, Score := 0.5 * Base_Score + 0.5 * New_Score]  # 50/50 blend
    merged[, Date := sd]
    merged[, .(Date, Ticker, Score)]
  }))

  ext_sim <- tryCatch(
    run_monthly_simulation(RAWDATA, BM_DT, ext_factors,
                            n_holdings = 30, weight_method = "equal",
                            commission = 0.0015),
    error = function(e) NULL
  )

  if (is.null(ext_sim)) {
    return(list(base_sharpe = base_sharpe, extended_sharpe = NA, delta_sharpe = NA))
  }

  ext_perf <- summarise_perf(ext_sim$strategy_xts, "extended")
  ext_sharpe <- ext_perf$Sharpe
  delta <- ext_sharpe - base_sharpe

  cat(sprintf("[S4] Extended Sharpe: %.3f | ΔSharpe: %+.3f\n", ext_sharpe, delta))

  # KOSPI benchmark Sharpe
  bm_perf <- summarise_perf(ext_sim$bm_xts, "KOSPI")
  kospi_sharpe <- bm_perf$Sharpe
  beats_kospi <- ext_sharpe > kospi_sharpe

  cat(sprintf("[S4] KOSPI Sharpe: %.3f | Beats KOSPI: %s\n", kospi_sharpe, beats_kospi))
  cat(sprintf("[S4] Verdict: %s\n",
      if (!beats_kospi) "KOSPI 미달 → S5 변형 필수"
      else if (delta > 0.1) "강력 통합 후보 → S6"
      else if (delta > 0) "통합 후보 → S6"
      else "Marginal 기여 없음 → S5 변형"))

  list(
    base_sharpe = base_sharpe,
    extended_sharpe = ext_sharpe,
    delta_sharpe = delta,
    kospi_sharpe = kospi_sharpe,
    beats_kospi = beats_kospi
  )
}


#==============================================================================
# S6: Complexity Penalty Validation
#==============================================================================

#' Validate complexity penalty per Tier.
#' Higher tier methods require stricter OOS criteria.
#'
#' @param is_sharpe Numeric. In-sample Sharpe
#' @param oos_sharpe Numeric. Out-of-sample Sharpe
#' @param tier Integer or character. 1/2/3 for FC, "A"/"B"/"C"/"D" for WD
#' @param baseline_oos_icir Numeric. Tier 1/A baseline OOS ICIR
#' @return list: pass, gap_pct, required_gap, red_flags
validate_complexity_penalty <- function(is_sharpe, oos_sharpe, tier,
                                         baseline_oos_icir = NULL) {
  gap_pct <- if (abs(is_sharpe) > 1e-8) (1 - oos_sharpe / is_sharpe) * 100 else NA

  # Tier-specific thresholds
  fc_thresholds <- list(
    `1` = list(max_gap = 50, min_oos_improvement = 0),
    `2` = list(max_gap = 50, min_oos_improvement = 0.05),
    `3` = list(max_gap = 30, min_oos_improvement = 0.10)
  )
  wd_thresholds <- list(
    A = list(max_gap = 50, min_oos_improvement = 0),
    B = list(max_gap = 50, min_oos_improvement = 0.05),
    C = list(max_gap = 40, min_oos_improvement = 0.05),
    D = list(max_gap = 40, min_oos_improvement = 0.05)
  )

  tier_key <- as.character(tier)
  thresh <- fc_thresholds[[tier_key]]
  if (is.null(thresh)) thresh <- wd_thresholds[[tier_key]]
  if (is.null(thresh)) thresh <- list(max_gap = 50, min_oos_improvement = 0)

  # Red flags
  red_flags <- character(0)
  if (!is.na(is_sharpe) && is_sharpe > 3.0) red_flags <- c(red_flags, "IS Sharpe > 3.0 (unrealistic)")
  if (!is.na(gap_pct) && gap_pct > 50) red_flags <- c(red_flags, "IS-OOS gap > 50%")
  if (!is.na(gap_pct) && tier_key == "3" && gap_pct > 30) red_flags <- c(red_flags, "Tier 3 gap > 30%")

  # Check OOS improvement vs baseline
  oos_improvement <- if (!is.null(baseline_oos_icir) && !is.na(oos_sharpe)) {
    oos_sharpe - baseline_oos_icir
  } else NA

  pass <- TRUE
  if (!is.na(gap_pct) && gap_pct > thresh$max_gap) pass <- FALSE
  if (!is.na(oos_improvement) && oos_improvement < thresh$min_oos_improvement) pass <- FALSE
  if (length(red_flags) > 0) pass <- FALSE

  list(
    pass = pass,
    gap_pct = gap_pct,
    required_max_gap = thresh$max_gap,
    oos_improvement = oos_improvement,
    required_improvement = thresh$min_oos_improvement,
    red_flags = red_flags,
    tier = tier_key
  )
}


#==============================================================================
# S7: Lifecycle Management
#==============================================================================

#' Update a factor's lifecycle in factor_registry.json
#'
#' @param factor_id Character. Factor ID (e.g., "XF_Q01_GPA")
#' @param status Character. "active" / "candidate" / "archived" / "deprecated"
#' @param stage Character. Research stage "S0"~"S7"
#' @param reason Character. Reason for status change (NULL if not applicable)
#' @param mutation_count Integer. Number of mutations tested
update_factor_lifecycle <- function(factor_id, status, stage = NULL,
                                     reason = NULL, mutation_count = NULL) {
  reg <- jsonlite::fromJSON(FACTOR_REG_PATH)

  if (!factor_id %in% names(reg)) {
    cat(sprintf("[lifecycle] Factor %s not in registry. Skipping.\n", factor_id))
    return(invisible(NULL))
  }

  if (is.null(reg[[factor_id]]$lifecycle)) {
    reg[[factor_id]]$lifecycle <- list(
      status = "active", research_stage = "S0",
      mutation_count = 0, added_date = as.character(Sys.Date()),
      last_validated = NULL, deprecation_reason = NULL, mutation_parent = NULL
    )
  }

  reg[[factor_id]]$lifecycle$status <- status
  if (!is.null(stage)) reg[[factor_id]]$lifecycle$research_stage <- stage
  if (!is.null(reason)) reg[[factor_id]]$lifecycle$deprecation_reason <- reason
  if (!is.null(mutation_count)) reg[[factor_id]]$lifecycle$mutation_count <- mutation_count
  reg[[factor_id]]$lifecycle$last_validated <- as.character(Sys.Date())

  jsonlite::write_json(reg, FACTOR_REG_PATH, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[lifecycle] %s → status=%s, stage=%s\n", factor_id, status, stage))
}


cat("[factor_research_pipeline] Loaded. Functions:\n")
cat("  compute_factor_orthogonality(), compute_spanning_test(),\n")
cat("  compute_ic_marginal(), compute_delta_sharpe(),\n")
cat("  update_factor_lifecycle()\n")
