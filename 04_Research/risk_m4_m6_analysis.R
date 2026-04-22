##=============================================================================
## M4 + M6 Risk Manager Analysis
## Pairwise TDC Matrix + Regime Payoff Decomposition
## Risk Manager (L13 Risk Engine)
##=============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/config.R")
source("02_Infrastructure/portfolio/tail_risk_engine.R")
source("02_Infrastructure/regime/regime_garch.R")

cat("=== M4+M6 Risk Manager Analysis ===\n")
cat("Computed at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

##=============================================================================
## STEP 1: Load available daily return series
##=============================================================================

load_daily_returns <- function(strategy_id, strategy_dir) {
  base <- file.path(PROJECT_ROOT, "04_Research/strategies", strategy_dir, "output")

  # Priority 1: daily_returns_primary.csv
  f1 <- file.path(base, "daily_returns_primary.csv")
  if (file.exists(f1)) {
    dt <- fread(f1)
    ret_col <- intersect(names(dt), c("Strategy_Ret", "Return", "Ret", "ret"))
    if (length(ret_col) > 0) {
      setnames(dt, ret_col[1], "ret")
      dt[, Date := as.Date(Date)]
      return(dt[, .(Date, ret)])
    }
  }

  # Priority 2: daily_nav.csv
  f2 <- file.path(base, "daily_nav.csv")
  if (file.exists(f2)) {
    dt <- fread(f2)
    if ("Strategy_Ret" %in% names(dt)) {
      dt[, Date := as.Date(Date)]
      return(dt[, .(Date, ret = Strategy_Ret)])
    }
    if ("Ret_overlay" %in% names(dt)) {
      dt[, Date := as.Date(Date)]
      return(dt[, .(Date, ret = Ret_overlay)])
    }
    nav_col <- intersect(names(dt), c("NAV_overlay", "NAV_base", "NAV"))
    if (length(nav_col) > 0) {
      dt[, Date := as.Date(Date)]
      nav <- dt[[nav_col[1]]]
      ret <- c(0, diff(nav) / head(nav, -1))
      dt[, ret := ret]
      return(dt[, .(Date, ret)])
    }
  }

  # Priority 3: sim_result.rds
  f3 <- file.path(base, "sim_result.rds")
  if (file.exists(f3)) {
    sim <- readRDS(f3)
    if (!is.null(sim$daily_returns)) {
      dates <- if (!is.null(sim$dates)) as.Date(sim$dates) else seq.Date(as.Date("2003-01-01"), by = "day", length.out = length(sim$daily_returns))
      return(data.table(Date = dates, ret = as.numeric(sim$daily_returns)))
    }
    if (!is.null(sim$nav)) {
      nav <- as.numeric(sim$nav)
      ret <- c(0, diff(nav) / head(nav, -1))
      dates <- if (!is.null(sim$dates)) as.Date(sim$dates) else seq.Date(as.Date("2003-01-01"), by = "day", length.out = length(nav))
      return(data.table(Date = dates, ret = ret))
    }
  }

  return(NULL)
}

# Define 13-strategy universe
strategy_map <- list(
  STR_1631_SYN_05 = "STR_1631",
  STR_1071 = "STR_1071_noShortDD_mrs1225",
  STR_1562 = "STR_1562_gerber_dcc_hrp_c11fix",
  STR_1679v2 = "STR_1679_score_blend",
  STR_1684 = "STR_1684_residual_momentum",
  STR_1685 = "STR_1685_multi_source_defense_anchor",
  STR_1682 = "STR_1682_residual_consensus",
  STR_1683 = "STR_1683_distress_calmar_defense",
  STR_CASH_v1 = "STR_CASH_v1",
  STR_1687 = "STR_1687_q07_sector_neutral_defense"
)

cat("[Step 1] Loading daily returns...\n")
all_returns <- list()
for (sid in names(strategy_map)) {
  ret <- load_daily_returns(sid, strategy_map[[sid]])
  if (!is.null(ret) && nrow(ret) > 100) {
    all_returns[[sid]] <- ret
    cat(sprintf("  %-25s: %d obs (%s ~ %s)\n", sid, nrow(ret),
                min(ret$Date), max(ret$Date)))
  } else {
    cat(sprintf("  %-25s: NO DATA or insufficient\n", sid))
  }
}

available_ids <- names(all_returns)
n_avail <- length(available_ids)
cat(sprintf("\n[Data] %d / %d strategies have daily returns\n\n", n_avail, length(strategy_map)))

if (n_avail < 2) {
  stop("Insufficient data for pairwise analysis")
}

##=============================================================================
## STEP 2: M4 — Pairwise TDC Matrix (Clayton + Gumbel + Empirical)
##=============================================================================

cat("=== M4: Pairwise TDC Matrix ===\n")

# Build aligned return matrix for overlapping dates
common_dates <- Reduce(intersect, lapply(all_returns, function(x) as.character(x$Date)))
common_dates <- sort(as.Date(common_dates))
cat(sprintf("[M4] Common date range: %s ~ %s (%d trading days)\n",
            min(common_dates), max(common_dates), length(common_dates)))

ret_matrix <- do.call(cbind, lapply(available_ids, function(sid) {
  dt <- all_returns[[sid]]
  dt[Date %in% common_dates][order(Date)]$ret
}))
colnames(ret_matrix) <- available_ids
rownames(ret_matrix) <- as.character(common_dates)

# Remove any rows with NA
complete_mask <- complete.cases(ret_matrix)
ret_matrix <- ret_matrix[complete_mask, , drop = FALSE]
common_dates <- common_dates[complete_mask]
cat(sprintf("[M4] Complete cases: %d\n", nrow(ret_matrix)))

# --- 2a. Clayton TDC (lower tail) ---
cat("\n[M4-2a] Computing Clayton TDC (lower tail)...\n")
tdc_lower_mat <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))
tdc_upper_mat <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))
kendall_mat   <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))

for (i in seq_len(n_avail)) {
  for (j in seq_len(n_avail)) {
    if (i == j) {
      tdc_lower_mat[i, j] <- 1.0
      tdc_upper_mat[i, j] <- 1.0
      kendall_mat[i, j]   <- 1.0
      next
    }
    if (j < i) {
      tdc_lower_mat[i, j] <- tdc_lower_mat[j, i]
      tdc_upper_mat[i, j] <- tdc_upper_mat[j, i]
      kendall_mat[i, j]   <- kendall_mat[j, i]
      next
    }

    res_c <- tryCatch(
      compute_copula_tdc(ret_matrix[, i], ret_matrix[, j], method = "clayton"),
      error = function(e) list(tdc_lower = NA, tdc_upper = NA, kendall_tau = NA)
    )
    res_g <- tryCatch(
      compute_copula_tdc(ret_matrix[, i], ret_matrix[, j], method = "gumbel"),
      error = function(e) list(tdc_upper = NA)
    )

    tdc_lower_mat[i, j] <- res_c$tdc_lower
    tdc_upper_mat[i, j] <- res_g$tdc_upper
    kendall_mat[i, j]   <- res_c$kendall_tau
  }
}

cat("\n--- Clayton Lower TDC Matrix ---\n")
print(round(tdc_lower_mat, 3))
cat("\n--- Gumbel Upper TDC Matrix ---\n")
print(round(tdc_upper_mat, 3))

# --- 2b. Empirical TDC ---
cat("\n[M4-2b] Computing Empirical TDC...\n")
tdc_emp_lower <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))
tdc_emp_upper <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))

for (i in seq_len(n_avail)) {
  for (j in seq_len(n_avail)) {
    if (i == j) {
      tdc_emp_lower[i, j] <- 1.0
      tdc_emp_upper[i, j] <- 1.0
      next
    }
    if (j < i) {
      tdc_emp_lower[i, j] <- tdc_emp_lower[j, i]
      tdc_emp_upper[i, j] <- tdc_emp_upper[j, i]
      next
    }
    res_e <- tryCatch(
      compute_copula_tdc(ret_matrix[, i], ret_matrix[, j], method = "empirical"),
      error = function(e) list(tdc_lower = NA, tdc_upper = NA)
    )
    tdc_emp_lower[i, j] <- res_e$tdc_lower
    tdc_emp_upper[i, j] <- res_e$tdc_upper
  }
}

cat("\n--- Empirical Lower TDC Matrix ---\n")
print(round(tdc_emp_lower, 3))

# --- 2c. t-Copula TDC (bivariate fitCopula) ---
cat("\n[M4-2c] Computing t-Copula TDC...\n")
tcopula_tdc   <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))
tcopula_nu    <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))
tcopula_rho   <- matrix(NA, n_avail, n_avail, dimnames = list(available_ids, available_ids))

for (i in seq_len(n_avail)) {
  for (j in seq_len(n_avail)) {
    if (i == j) {
      tcopula_tdc[i, j] <- 1.0
      tcopula_nu[i, j]  <- NA
      tcopula_rho[i, j] <- 1.0
      next
    }
    if (j < i) {
      tcopula_tdc[i, j] <- tcopula_tdc[j, i]
      tcopula_nu[i, j]  <- tcopula_nu[j, i]
      tcopula_rho[i, j] <- tcopula_rho[j, i]
      next
    }

    tryCatch({
      u_data <- cbind(
        rank(ret_matrix[, i]) / (nrow(ret_matrix) + 1),
        rank(ret_matrix[, j]) / (nrow(ret_matrix) + 1)
      )
      tc <- copula::tCopula(dim = 2)
      fit <- copula::fitCopula(tc, u_data, method = "mpl")
      rho_t <- fit@estimate[1]
      nu_t  <- fit@estimate[2]

      # lambda = 2 * t_{nu+1}(-sqrt((nu+1)(1-rho)/(1+rho)))
      lambda_t <- 2 * pt(-sqrt((nu_t + 1) * (1 - rho_t) / (1 + rho_t)), df = nu_t + 1)

      tcopula_tdc[i, j] <- lambda_t
      tcopula_nu[i, j]  <- nu_t
      tcopula_rho[i, j] <- rho_t
    }, error = function(e) {
      cat(sprintf("  t-copula fail: %s vs %s: %s\n", available_ids[i], available_ids[j], e$message))
    })
  }
}

cat("\n--- t-Copula TDC (symmetric) ---\n")
print(round(tcopula_tdc, 4))
cat("\n--- t-Copula nu (degrees of freedom) ---\n")
print(round(tcopula_nu, 2))

# --- 2d. DCC-GARCH conditional rho (if enough strategies) ---
cat("\n[M4-2d] DCC-GARCH conditional correlation...\n")
dcc_result <- NULL
dcc_crisis_rho <- NULL

if (n_avail >= 2 && n_avail <= 6) {
  # DCC is feasible for small dimensions
  dcc_result <- tryCatch({
    fit_dcc_garch(ret_matrix, dist = "std", verbose = TRUE)
  }, error = function(e) {
    cat(sprintf("  DCC-GARCH failed: %s\n", e$message))
    NULL
  })

  if (!is.null(dcc_result)) {
    # Extract crisis-period conditional correlations
    # MRS >= 30 definition: use dates from regime_engine
    tv_cor <- dcc_result$time_varying_cor  # [K, K, T]
    T_dim <- dim(tv_cor)[3]

    # Full-sample average correlation
    avg_cor <- apply(tv_cor, c(1, 2), mean, na.rm = TRUE)
    colnames(avg_cor) <- rownames(avg_cor) <- available_ids
    cat("\n--- DCC-GARCH Average Conditional Correlation ---\n")
    print(round(avg_cor, 3))

    # Last 20% as proxy for crisis (recent MRS 63.1)
    crisis_start <- max(1, floor(T_dim * 0.8))
    crisis_cor <- apply(tv_cor[, , crisis_start:T_dim, drop = FALSE], c(1, 2), mean, na.rm = TRUE)
    colnames(crisis_cor) <- rownames(crisis_cor) <- available_ids
    cat("\n--- DCC-GARCH Crisis-Period Conditional Correlation (last 20%) ---\n")
    print(round(crisis_cor, 3))

    dcc_crisis_rho <- crisis_cor
  }
} else if (n_avail > 6) {
  cat("  DCC skipped for >6 strategies (pairwise instead)...\n")
  # Pairwise DCC for key pairs
  key_pairs <- list(
    c("STR_1631_SYN_05", "STR_1071"),
    c("STR_1631_SYN_05", "STR_1562"),
    c("STR_1631_SYN_05", "STR_1679v2"),
    c("STR_1071", "STR_1562")
  )
  for (pair in key_pairs) {
    if (all(pair %in% available_ids)) {
      idx <- match(pair, available_ids)
      sub_ret <- ret_matrix[, idx, drop = FALSE]
      res <- tryCatch(fit_dcc_garch(sub_ret, dist = "std", verbose = FALSE), error = function(e) NULL)
      if (!is.null(res)) {
        tv <- res$time_varying_cor
        T_d <- dim(tv)[3]
        avg_rho <- mean(tv[1, 2, ], na.rm = TRUE)
        crisis_rho <- mean(tv[1, 2, max(1, floor(T_d * 0.8)):T_d], na.rm = TRUE)
        cat(sprintf("  %s <-> %s: avg_rho=%.3f, crisis_rho=%.3f, spike=%.3f\n",
                    pair[1], pair[2], avg_rho, crisis_rho, crisis_rho - avg_rho))
      }
    }
  }
}

##=============================================================================
## STEP 3: M4 — Per-strategy EVT/GPD tail index
##=============================================================================

cat("\n=== M4: Per-Strategy EVT/GPD Tail Index ===\n")
evt_results <- list()
for (sid in available_ids) {
  ret_vec <- ret_matrix[, sid]
  evt <- tryCatch(
    compute_evt_var(ret_vec, p = 0.99, threshold_q = 0.95),
    error = function(e) list(shape_xi = NA, scale_beta = NA, var_evt = NA, es_evt = NA, method = "failed")
  )
  cf <- tryCatch(
    compute_cf_var(ret_vec, p = 0.99),
    error = function(e) list(var_cf = NA, skewness = NA, kurtosis = NA, cf_vs_normal_ratio = NA)
  )
  evt_results[[sid]] <- list(
    evt_var_99  = evt$var_evt,
    evt_es_99   = evt$es_evt,
    shape_xi    = evt$shape_xi,
    scale_beta  = evt$scale_beta,
    method      = evt$method,
    cf_var_99   = cf$var_cf,
    skewness    = cf$skewness,
    kurtosis    = cf$kurtosis,
    cf_vs_normal = cf$cf_vs_normal_ratio
  )
  cat(sprintf("  %-25s: xi=%.4f, EVT-VaR99=%.4f, CF-VaR99=%.4f, skew=%.3f, kurt=%.3f\n",
              sid,
              ifelse(is.null(evt$shape_xi) || is.na(evt$shape_xi), NA, evt$shape_xi),
              ifelse(is.null(evt$var_evt) || is.na(evt$var_evt), NA, evt$var_evt),
              ifelse(is.null(cf$var_cf) || is.na(cf$var_cf), NA, cf$var_cf),
              ifelse(is.null(cf$skewness) || is.na(cf$skewness), NA, cf$skewness),
              ifelse(is.null(cf$kurtosis) || is.na(cf$kurtosis), NA, cf$kurtosis)))
}

##=============================================================================
## STEP 4: M6 — Regime Payoff Decomposition (8 Stress Periods)
##=============================================================================

cat("\n=== M6: Regime Payoff Decomposition ===\n")

stress_periods <- list(
  list(label = "9/11",       start = "2001-09-01", end = "2001-12-31"),
  list(label = "GFC",        start = "2007-10-01", end = "2009-03-31"),
  list(label = "EuDebt",     start = "2011-07-01", end = "2011-12-31"),
  list(label = "ChinaShock", start = "2015-06-01", end = "2016-02-29"),
  list(label = "TradeWar",   start = "2018-03-01", end = "2018-12-31"),
  list(label = "COVID",      start = "2020-01-01", end = "2020-06-30"),
  list(label = "RateHike",   start = "2022-01-01", end = "2022-12-31"),
  list(label = "IranWar",    start = "2026-02-01", end = "2026-04-30")
)

# For each strategy, compute per-stress-period metrics
stress_results <- list()

for (sid in available_ids) {
  dt <- all_returns[[sid]]
  strat_stress <- list()

  for (sp in stress_periods) {
    sp_dates <- dt[Date >= as.Date(sp$start) & Date <= as.Date(sp$end)]

    if (nrow(sp_dates) < 5) {
      strat_stress[[sp$label]] <- list(
        n_obs = nrow(sp_dates),
        note = "insufficient data"
      )
      next
    }

    r <- sp_dates$ret
    nav <- cumprod(1 + r)

    # CVaR 95%
    var_95 <- as.numeric(quantile(r, 0.05))
    es_95 <- mean(r[r <= var_95])

    # MDD
    running_max <- cummax(nav)
    dd <- (nav - running_max) / running_max
    mdd <- min(dd)

    # Cumulative return
    cum_ret <- tail(nav, 1) - 1

    # GPD tail index
    gpd_res <- tryCatch({
      losses <- -r
      u <- as.numeric(quantile(losses, 0.90))
      exc <- losses[losses > u]
      if (length(exc) >= 10) {
        fit <- fExtremes::gpdFit(exc - u, type = "mle")
        as.numeric(fit@fit$par.ests["xi"])
      } else NA_real_
    }, error = function(e) NA_real_)

    strat_stress[[sp$label]] <- list(
      n_obs    = nrow(sp_dates),
      cum_ret  = round(cum_ret, 4),
      cvar_95  = round(es_95, 6),
      mdd      = round(mdd, 4),
      ann_vol  = round(sd(r) * sqrt(252), 4),
      gpd_xi   = round(gpd_res, 4)
    )
  }

  stress_results[[sid]] <- strat_stress
  cat(sprintf("\n[%s] Stress Decomposition:\n", sid))
  for (sp_name in names(strat_stress)) {
    s <- strat_stress[[sp_name]]
    if (is.null(s$note)) {
      cat(sprintf("  %-12s: CumRet=%+.2f%%, CVaR95=%.4f, MDD=%.2f%%, Vol=%.2f%%, GPD_xi=%s\n",
                  sp_name,
                  s$cum_ret * 100,
                  s$cvar_95,
                  s$mdd * 100,
                  s$ann_vol * 100,
                  ifelse(is.na(s$gpd_xi), "NA", sprintf("%.4f", s$gpd_xi))))
    } else {
      cat(sprintf("  %-12s: %s\n", sp_name, s$note))
    }
  }
}

##=============================================================================
## STEP 5: M6 — CDaR Analysis per strategy
##=============================================================================

cat("\n=== M6: CDaR Analysis ===\n")
cdar_results <- list()
for (sid in available_ids) {
  dt <- all_returns[[sid]]
  nav <- cumprod(1 + dt$ret)
  cdar_res <- tryCatch(
    compute_cdar(nav, alpha = 0.95),
    error = function(e) list(cdar = NA, max_dd = NA, avg_dd = NA, n_drawdowns = NA, recovery_ratio = NA)
  )
  cdar_results[[sid]] <- cdar_res
  cat(sprintf("  %-25s: CDaR95=%.4f, MaxDD=%.4f, AvgDD=%.4f, RecovRatio=%.3f\n",
              sid,
              ifelse(is.na(cdar_res$cdar), NA, cdar_res$cdar),
              ifelse(is.na(cdar_res$max_dd), NA, cdar_res$max_dd),
              ifelse(is.na(cdar_res$avg_dd), NA, cdar_res$avg_dd),
              ifelse(is.na(cdar_res$recovery_ratio), NA, cdar_res$recovery_ratio)))
}

##=============================================================================
## STEP 6: AX-001 v2 Defense Audit (for defense-tagged strategies)
##=============================================================================

cat("\n=== M6: AX-001 v2 Defense Audit ===\n")

defense_candidates <- c("STR_1685", "STR_1683", "STR_1687", "STR_CASH_v1")
defense_candidates <- intersect(defense_candidates, available_ids)

for (sid in defense_candidates) {
  dt <- all_returns[[sid]]
  cat(sprintf("\n[Defense Audit: %s]\n", sid))

  # Crisis alpha: positive return in at least 4/8 stress periods
  crisis_alpha_count <- 0
  crisis_total <- 0
  for (sp in stress_periods) {
    sp_data <- dt[Date >= as.Date(sp$start) & Date <= as.Date(sp$end)]
    if (nrow(sp_data) >= 5) {
      crisis_total <- crisis_total + 1
      cum_ret <- prod(1 + sp_data$ret) - 1
      if (cum_ret > 0) crisis_alpha_count <- crisis_alpha_count + 1
      cat(sprintf("  %-12s: %+.2f%% %s\n", sp$label, cum_ret * 100,
                  ifelse(cum_ret > 0, "ALPHA", "loss")))
    }
  }
  cat(sprintf("  Crisis Alpha: %d/%d (%s)\n", crisis_alpha_count, crisis_total,
              ifelse(crisis_alpha_count >= ceiling(crisis_total * 0.5), "PASS", "FAIL")))

  # Bad/Normal IC ratio (proxy using loss/normal return ratio)
  all_ret <- dt$ret
  bad_days <- all_ret[all_ret < quantile(all_ret, 0.20)]
  normal_days <- all_ret[all_ret >= quantile(all_ret, 0.20) & all_ret <= quantile(all_ret, 0.80)]
  bad_mean <- mean(bad_days)
  normal_mean <- mean(normal_days)
  ic_ratio <- abs(bad_mean) / max(abs(normal_mean), 1e-8)
  cat(sprintf("  Bad/Normal return ratio: %.3f (threshold >= 1.2: %s)\n",
              ic_ratio, ifelse(ic_ratio >= 1.2, "PASS", "FAIL")))
}

##=============================================================================
## STEP 7: Compile and save JSON results
##=============================================================================

cat("\n=== Compiling Results ===\n")

m4_result <- list(
  computed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_strategies = n_avail,
  strategy_ids = available_ids,
  common_dates = list(
    start = as.character(min(common_dates)),
    end   = as.character(max(common_dates)),
    n_trading_days = length(common_dates)
  ),
  clayton_lower_tdc = as.list(as.data.frame(round(tdc_lower_mat, 4))),
  gumbel_upper_tdc  = as.list(as.data.frame(round(tdc_upper_mat, 4))),
  empirical_lower_tdc = as.list(as.data.frame(round(tdc_emp_lower, 4))),
  empirical_upper_tdc = as.list(as.data.frame(round(tdc_emp_upper, 4))),
  t_copula_tdc      = as.list(as.data.frame(round(tcopula_tdc, 4))),
  t_copula_nu       = as.list(as.data.frame(round(tcopula_nu, 2))),
  t_copula_rho      = as.list(as.data.frame(round(tcopula_rho, 4))),
  kendall_tau       = as.list(as.data.frame(round(kendall_mat, 4))),
  evt_gpd_per_strategy = evt_results
)

m6_result <- list(
  computed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stress_periods = lapply(stress_periods, function(sp) list(label = sp$label, start = sp$start, end = sp$end)),
  stress_period_metrics = stress_results,
  cdar_analysis = cdar_results,
  defense_audit_strategies = defense_candidates
)

# Save
out_dir <- file.path(PROJECT_ROOT, "stage_artifacts")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

write_json(m4_result, file.path(out_dir, "risk_m4_tdc_matrix_20260419.json"),
           auto_unbox = TRUE, pretty = TRUE)
write_json(m6_result, file.path(out_dir, "risk_m6_regime_payoff_20260419.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("\n[DONE] M4 saved: stage_artifacts/risk_m4_tdc_matrix_20260419.json\n")
cat("[DONE] M6 saved: stage_artifacts/risk_m6_regime_payoff_20260419.json\n")

##=============================================================================
## STEP 8: Summary for Q-Lead
##=============================================================================

cat("\n\n========== RISK MANAGER M4+M6 SUMMARY ==========\n")
cat("\n--- M4: Key TDC Findings ---\n")

# Flag high TDC pairs (> 0.30 threshold from Admission Rule v3.0)
high_tdc_pairs <- list()
for (i in seq_len(n_avail - 1)) {
  for (j in (i + 1):n_avail) {
    tdc_val <- tcopula_tdc[i, j]
    if (!is.na(tdc_val) && tdc_val > 0.30) {
      high_tdc_pairs[[length(high_tdc_pairs) + 1]] <- list(
        pair = paste(available_ids[i], "<->", available_ids[j]),
        tdc = round(tdc_val, 4),
        kendall = round(kendall_mat[i, j], 4)
      )
    }
  }
}

if (length(high_tdc_pairs) > 0) {
  cat(sprintf("  WARNING: %d pairs exceed TDC 0.30 threshold:\n", length(high_tdc_pairs)))
  for (p in high_tdc_pairs) {
    cat(sprintf("    %s: TDC=%.4f, Kendall=%.4f\n", p$pair, p$tdc, p$kendall))
  }
} else {
  cat("  All pairs below TDC 0.30 threshold.\n")
}

cat("\n--- M6: Worst Stress Period per Strategy ---\n")
for (sid in available_ids) {
  worst_mdd <- 0
  worst_label <- "none"
  for (sp_name in names(stress_results[[sid]])) {
    s <- stress_results[[sid]][[sp_name]]
    if (!is.null(s$mdd) && !is.na(s$mdd) && s$mdd < worst_mdd) {
      worst_mdd <- s$mdd
      worst_label <- sp_name
    }
  }
  cat(sprintf("  %-25s: worst=%s (MDD=%.2f%%)\n", sid, worst_label, worst_mdd * 100))
}

cat("\n--- M6: EVT Tail Shape Summary ---\n")
for (sid in available_ids) {
  e <- evt_results[[sid]]
  xi <- e$shape_xi
  risk_level <- if (is.na(xi)) "unknown" else if (xi > 0.5) "HEAVY TAIL" else if (xi > 0.3) "moderate" else "light"
  cat(sprintf("  %-25s: xi=%.4f (%s), CF/Normal=%.2fx\n",
              sid,
              ifelse(is.na(xi), NA, xi),
              risk_level,
              ifelse(is.na(e$cf_vs_normal), NA, e$cf_vs_normal)))
}

cat("\n=== M4+M6 Analysis Complete ===\n")
