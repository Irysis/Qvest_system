## ============================================================
## WT-H20260512_001 — STR_1715_ZSC_v1 Z-Score Composite Grid Sweep
## ============================================================
## 도훈 mandate 2026-05-12 Session 80:
##   현 STR_1715_AR_on_M4_PG2 alpha building blocks 그대로 + 결합방식만
##   sleeve-blend (score_eff) → Z-Score Composite redesign.
##
## Pure Function boundary:
##   - alpha_scores.parquet read-only (Date, Ticker, score_core_z,
##     score_defense_z, regime_state, Ret_1m 만 사용)
##   - score_eff / theta_core / theta_defense 사용 금지 (replaced)
##   - score_core_z + score_defense_z 값 변경 금지 (alpha lineage invariance)
##
## 5 Variants:
##   V1: equal_norm_sqrt2   z = (z_core + z_def) / sqrt(2)
##   V2: equal_simple_50_50 z = 0.5 * z_core + 0.5 * z_def
##   V3: ic_weighted_exp    z = w_IC_core(t) * z_core + w_IC_def(t) * z_def
##                          (expanding IC rolling, t-1 lag PIT C14)
##   V4: regime_4state      z = α(r) * z_core + (1-α(r)) * z_def
##                          BULL 0.7/0.3, NORMAL 0.5/0.5, CAUTION 0.3/0.7, CRISIS 0.2/0.8
##   V5: defense_amplifier  z = z_core + κ(r) * z_def
##                          κ BULL 0.3, NORMAL 0.7, CAUTION 1.5, CRISIS 2.5
##
## Selection: Top20 → Iter31 linear_tilt_to_penalty_qd(λ=1.5, phi=3, ub=0.20)
## Cost: 15bps each side (commission=0.0015), monthly t-1 lag
##
## Backtest convention: PerformanceAnalytics geometric strict
##   - Return.portfolio / table.AnnualizedReturns / maxDrawdown /
##     SortinoRatio / CalmarRatio 만 사용
##   - prod(1+r)-1 / cumprod(1+r) 자체 합성 금지 (NAV display 외)
##
## Horizon:
##   - Raw cover 267m: 2004-02 ~ 2026-04 (max range)
##   - Admit-comparable 256m: 2005-02 onwards (align baseline)
##
## PIT 준수: C1 / C2 / C9 / C10 / C13 / C14 (Usable_Date <= sig_date inherit)
## ============================================================

cat("============================================================\n")
cat("STR_1715_ZSC_v1 — Z-Score Composite Grid Sweep (5 variants)\n")
cat("WT-H20260512_001 — Forge 2026-05-12\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
  library(lubridate)
  library(e1071)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-H20260512_001"
STR_ID   <- "STR_1715_ZSC_v1"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
BT_DIR   <- file.path(WT_DIR, "backtest_result")
OUT_DIR  <- file.path(WT_DIR, "output")

dir.create(BT_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Source paths (read-only)
ALPHA_SCORES_PATH <- file.path(BASE_DIR, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
RAW_PATH          <- file.path(BASE_DIR, ".cache/rawdata.parquet")
BM_PATH           <- file.path(BASE_DIR, ".cache/benchmark.parquet")
FF5_PATH          <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")

# ============================================================
# 1. Hash audit — alpha_scores.parquet immutability
# ============================================================
cat("[1] Hash audit — alpha building blocks immutability\n")

alpha_md5_pre <- as.character(tools::md5sum(ALPHA_SCORES_PATH))
cat(sprintf("    alpha_scores.parquet MD5 (pre): %s\n", substr(alpha_md5_pre, 1, 16)))

# ============================================================
# 2. Load alpha_scores + RAWDATA + Benchmark
# ============================================================
cat("\n[2] Load inputs (read-only)\n")

alpha_scores <- as.data.table(read_parquet(ALPHA_SCORES_PATH))
setkey(alpha_scores, Date, Ticker)
cat(sprintf("    alpha_scores: %s rows | %d unique Date\n",
            format(nrow(alpha_scores), big.mark = ","),
            length(unique(alpha_scores$Date))))
cat(sprintf("    Date range: %s ~ %s\n",
            as.character(min(alpha_scores$Date)),
            as.character(max(alpha_scores$Date))))

# Validate columns required
required_cols <- c("Date","Ticker","score_core_z","score_defense_z","regime_state","Ret_1m")
miss_cols <- setdiff(required_cols, names(alpha_scores))
if (length(miss_cols) > 0) stop("Missing required cols: ", paste(miss_cols, collapse=","))

raw <- as.data.table(read_parquet(RAW_PATH,
                                   col_select = c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("    RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark = ","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

bm <- as.data.table(read_parquet(BM_PATH))
setorder(bm, Date)
cat(sprintf("    Benchmark: %d rows\n", nrow(bm)))

ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
setorder(ff5_v2, Date)

# sig_dates available (where any score is non-NA)
sig_dates_all <- sort(unique(alpha_scores[
  !is.na(score_core_z) | !is.na(score_defense_z),
  Date
]))
cat(sprintf("    sig_dates available: %d (range: %s ~ %s)\n",
            length(sig_dates_all),
            as.character(min(sig_dates_all)), as.character(max(sig_dates_all))))

# ============================================================
# 3. Optimizer helper — Iter31 linear_tilt_to_penalty_qd (Pure Function)
# ============================================================
cat("\n[3] Build Iter31 weighting helper (linear_tilt_to_penalty_qd λ=1.5 phi=3 ub=0.20)\n")

normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w)
    return(rep(target_sum / n, n))
  }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w))
      break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)   # phi=3 → blend=0.75 toward w_prev
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# ============================================================
# 4. Z-Score Composite functions (5 variants)
# ============================================================
cat("\n[4] Define 5 z-score composite variants\n")

# V1: (z_core + z_def) / sqrt(2)
zsc_V1 <- function(dt) {
  out <- dt[!is.na(score_core_z) & !is.na(score_defense_z)]
  out[, z_comp := (score_core_z + score_defense_z) / sqrt(2)]
  out
}

# V2: 0.5 * z_core + 0.5 * z_def
zsc_V2 <- function(dt) {
  out <- dt[!is.na(score_core_z) & !is.na(score_defense_z)]
  out[, z_comp := 0.5 * score_core_z + 0.5 * score_defense_z]
  out
}

# V3: IC-weighted expanding (PIT t-1 lag, C14)
#   Needs precomputed (w_IC_core(t), w_IC_def(t)) per Date from expanding history.
#   Use rank IC (Spearman) of each z vs forward Ret_1m, expanded through t-1.
#   Lag 1 month enforced.
compute_ic_weights_expanding <- function(alpha_dt, min_obs = 24) {
  # For each Date, compute IC_core and IC_def using all (Date', Ret_1m, score_z)
  # where Date' < Date (strict t-1 lag).
  cat("    [V3 prep] Computing expanding IC weights (Spearman) ...\n")
  ad <- alpha_dt[!is.na(Ret_1m)]
  # Per-date IC contribution
  ic_per_date <- ad[, .(
    ic_core = if (sum(!is.na(score_core_z)) >= 5)
                 cor(score_core_z, Ret_1m, use="pairwise.complete.obs", method="spearman")
               else NA_real_,
    ic_def  = if (sum(!is.na(score_defense_z)) >= 5)
                 cor(score_defense_z, Ret_1m, use="pairwise.complete.obs", method="spearman")
               else NA_real_,
    n_obs = .N
  ), by = Date]
  setorder(ic_per_date, Date)
  # Expanding mean of IC up to (but excluding) date t
  ic_per_date[, ic_core_exp := cumsum(ifelse(is.na(ic_core), 0, ic_core)) /
                                pmax(cumsum(!is.na(ic_core)), 1)]
  ic_per_date[, ic_def_exp  := cumsum(ifelse(is.na(ic_def), 0, ic_def)) /
                                pmax(cumsum(!is.na(ic_def)), 1)]
  # Lag 1 row (use prior-period expanding IC for current sig_date weighting)
  ic_per_date[, ic_core_lag := shift(ic_core_exp, 1, type = "lag")]
  ic_per_date[, ic_def_lag  := shift(ic_def_exp,  1, type = "lag")]
  # Warm-up: first min_obs months use equal weight
  ic_per_date[, valid_t := cumsum(!is.na(ic_core_lag) & !is.na(ic_def_lag))]
  ic_per_date[, use_equal := seq_len(.N) <= min_obs]
  ic_per_date[, w_core := fifelse(use_equal | is.na(ic_core_lag) | is.na(ic_def_lag),
                                  0.5,
                                  pmax(ic_core_lag, 0) /
                                  pmax(pmax(ic_core_lag, 0) + pmax(ic_def_lag, 0), 1e-9))]
  ic_per_date[w_core < 0.1, w_core := 0.1]  # floor
  ic_per_date[w_core > 0.9, w_core := 0.9]  # ceiling
  ic_per_date[, w_def := 1 - w_core]
  ic_per_date[, .(Date, w_core, w_def, ic_core_lag, ic_def_lag)]
}

zsc_V3_factory <- function(alpha_dt) {
  ic_weights <- compute_ic_weights_expanding(alpha_dt)
  function(dt) {
    out <- merge(dt, ic_weights, by = "Date", all.x = TRUE)
    out <- out[!is.na(score_core_z) & !is.na(score_defense_z)]
    # Fallback to 0.5/0.5 if weights missing
    out[is.na(w_core), w_core := 0.5]
    out[is.na(w_def),  w_def  := 0.5]
    out[, z_comp := w_core * score_core_z + w_def * score_defense_z]
    out
  }
}

# V4: regime-conditional 4-state
zsc_V4 <- function(dt) {
  out <- dt[!is.na(score_core_z) & !is.na(score_defense_z)]
  out[, w_core := fcase(
    regime_state == "BULL",    0.7,
    regime_state == "NORMAL",  0.5,
    regime_state == "CAUTION", 0.3,
    regime_state == "CRISIS",  0.2,
    default                  = 0.5
  )]
  out[, w_def := 1 - w_core]
  out[, z_comp := w_core * score_core_z + w_def * score_defense_z]
  out
}

# V5: defense amplifier (additive, asymmetric)
zsc_V5 <- function(dt) {
  out <- dt[!is.na(score_core_z) & !is.na(score_defense_z)]
  out[, kappa := fcase(
    regime_state == "BULL",    0.3,
    regime_state == "NORMAL",  0.7,
    regime_state == "CAUTION", 1.5,
    regime_state == "CRISIS",  2.5,
    default                  = 0.7
  )]
  out[, z_comp := score_core_z + kappa * score_defense_z]
  out
}

variants <- list(
  V1_equal_norm_sqrt2   = list(fn = zsc_V1, desc = "(z_core + z_def) / sqrt(2)"),
  V2_equal_simple_50_50 = list(fn = zsc_V2, desc = "0.5*z_core + 0.5*z_def"),
  V3_ic_weighted_exp    = list(fn = zsc_V3_factory(alpha_scores),
                                desc = "expanding IC weighted (PIT t-1)"),
  V4_regime_4state      = list(fn = zsc_V4,
                                desc = "regime-conditional 4-state BULL 0.7 -> CRISIS 0.2"),
  V5_defense_amplifier  = list(fn = zsc_V5,
                                desc = "additive z_core + kappa(r)*z_def")
)

# ============================================================
# 5. Backtest loop function (per variant)
# ============================================================
cat("\n[5] Build backtest loop (per variant, walk-forward monthly)\n\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 5L
UB_WEIGHT      <- 0.20
LAMBDA         <- 1.5
TOPHI          <- 3.0

run_zsc_backtest <- function(variant_name, variant_fn) {
  cat(sprintf("--- Backtest: %s ---\n", variant_name))

  # Compute z_comp for entire alpha_scores
  scored <- variant_fn(alpha_scores)
  scored <- scored[!is.na(z_comp)]
  if (nrow(scored) == 0L) stop("No valid z_comp for ", variant_name)

  # Per-date sig_dates available
  sig_dates_v <- sort(unique(scored$Date))

  monthly <- vector("list", length(sig_dates_v) - 1L)
  w_prev_named <- NULL
  weights_log  <- list()

  for (i in seq_len(length(sig_dates_v) - 1L)) {
    sig_label <- sig_dates_v[i]
    next_sig  <- sig_dates_v[i + 1L]

    start_d <- min(raw[Date >= sig_label]$Date)
    if (length(start_d) == 0L || is.na(start_d) || is.infinite(start_d)) next
    end_d   <- min(raw[Date >= next_sig]$Date)
    if (length(end_d) == 0L || is.na(end_d) || is.infinite(end_d)) end_d <- max(raw$Date)

    panel_t <- scored[Date == sig_label]
    if (nrow(panel_t) == 0L) next

    regime_i <- panel_t$regime_state[1L]

    # Top20 by z_comp descending
    setorder(panel_t, -z_comp)
    N_eligible <- nrow(panel_t)
    N_target   <- min(MAX_NAMES, N_eligible)
    if (N_target < MIN_NAMES) next

    picks <- panel_t[seq_len(N_target)]
    tickers_t <- picks$Ticker
    alpha_t   <- picks$z_comp
    names(alpha_t) <- tickers_t

    # Liquidity filter (t-30 .. t-1, PIT C10)
    liq_window_start <- start_d - 30L
    liq_data <- raw[Date >= liq_window_start & Date < start_d,
                    .(AvgTradingAmt = mean(TradingAmt, na.rm = TRUE)), by = Ticker]
    liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
    tickers_liq <- intersect(tickers_t, liquid_tickers)
    if (length(tickers_liq) < MIN_NAMES) {
      tickers_liq <- tickers_t   # fallback
    }
    alpha_t_liq <- alpha_t[tickers_liq]
    if (length(alpha_t_liq) < MIN_NAMES) next

    # Crisis shrinkage
    ub_use <- if (!is.na(regime_i) && regime_i == "CRISIS") min(UB_WEIGHT, 0.10) else UB_WEIGHT

    # Iter31 linear_tilt + TOphi penalty
    w_risk <- tryCatch(
      linear_tilt_to_penalty_qd(alpha_t_liq, lambda = LAMBDA, w_prev = w_prev_named,
                                 phi = TOPHI, lb = 0, ub = ub_use),
      error = function(e) linear_tilt_qd(alpha_t_liq, lambda = LAMBDA, lb = 0, ub = ub_use)
    )
    names(w_risk) <- names(alpha_t_liq)
    w_risk <- normalize_long_only(w_risk, lb = 0, ub = ub_use, target_sum = 1)

    # Log weights
    weights_log[[length(weights_log) + 1L]] <- data.table(
      sig_date = sig_label,
      start_d  = start_d,
      end_d    = end_d,
      ticker   = names(w_risk),
      weight   = as.numeric(w_risk),
      regime   = regime_i
    )

    # Period returns (C2: > start_d, <= end_d)
    period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
    if (nrow(period_data) == 0L) next

    stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    merged <- merge(
      data.table(ticker = names(w_risk), weight = as.numeric(w_risk)),
      stock_rets, by.x = "ticker", by.y = "Ticker", all.x = TRUE
    )
    merged[is.na(stock_ret), stock_ret := 0]

    port_ret_gross <- sum(merged$weight * merged$stock_ret, na.rm = TRUE)

    # Turnover (L1 / 2)
    if (is.null(w_prev_named) || length(w_prev_named) == 0L) {
      turnover_est <- 1.0
    } else {
      all_names <- union(names(w_risk), names(w_prev_named))
      w_now_a   <- setNames(rep(0, length(all_names)), all_names)
      w_prev_a  <- setNames(rep(0, length(all_names)), all_names)
      w_now_a[names(w_risk)]      <- w_risk
      w_prev_a[names(w_prev_named)] <- w_prev_named
      turnover_est <- sum(abs(w_now_a - w_prev_a)) / 2
    }
    # Round-trip cost: 15bps * turnover * 2 (buy + sell)
    cost <- (COMMISSION_BPS / 1e4) * turnover_est * 2
    port_ret_net <- port_ret_gross - cost

    monthly[[i]] <- data.table(
      sig_date     = sig_label,
      period_start = start_d,
      period_end   = end_d,
      ret_gross    = port_ret_gross,
      ret_net      = port_ret_net,
      turnover     = turnover_est,
      cost_ret     = cost,
      n_holdings   = nrow(merged),
      regime       = regime_i
    )

    w_prev_named <- setNames(as.numeric(w_risk), names(w_risk))
  }

  bt_dt <- rbindlist(monthly, use.names = TRUE, fill = TRUE)
  bt_dt <- bt_dt[!is.na(ret_net)]
  setorder(bt_dt, period_end)

  weights_dt <- rbindlist(weights_log, use.names = TRUE, fill = TRUE)
  setorder(weights_dt, sig_date, -weight)

  list(period_returns = bt_dt, weights = weights_dt, variant = variant_name)
}

# ============================================================
# 6. Run all 5 variants
# ============================================================
cat("[6] Run all 5 variants\n\n")

all_results <- list()
for (vname in names(variants)) {
  res <- run_zsc_backtest(vname, variants[[vname]]$fn)
  all_results[[vname]] <- res
  cat(sprintf("  %s: %d periods | avg n_held=%.1f | avg TO=%.4f | TO ann=%.1f%%\n",
              vname, nrow(res$period_returns),
              mean(res$period_returns$n_holdings),
              mean(res$period_returns$turnover),
              mean(res$period_returns$turnover) * 12 * 100))
}

# ============================================================
# 7. Performance metrics (PerformanceAnalytics strict)
# ============================================================
cat("\n[7] Compute metrics — PerformanceAnalytics strict (geometric)\n\n")

# RF (zero for KR retail standard)
RF_MONTHLY <- 0

compute_perf_strict <- function(period_returns, label, horizon_filter = NULL,
                                  freq = "monthly") {
  pr <- period_returns
  if (!is.null(horizon_filter)) {
    pr <- pr[period_end >= horizon_filter]
  }
  if (nrow(pr) < 12) return(NULL)

  # Build xts (PerformanceAnalytics standard)
  ret_xts <- xts(pr[, .(ret_net)], order.by = pr$period_end)

  # Use table.AnnualizedReturns (geometric)
  tar <- PerformanceAnalytics::table.AnnualizedReturns(ret_xts, scale = 12,
                                                         Rf = RF_MONTHLY,
                                                         geometric = TRUE)

  cagr <- as.numeric(tar["Annualized Return", 1])
  vol  <- as.numeric(tar["Annualized Std Dev", 1])
  sr   <- as.numeric(tar["Annualized Sharpe (Rf=0%)", 1])
  if (is.na(sr)) {
    # Try other Rf-formatted row
    sr_row <- grep("Sharpe", rownames(tar), value = TRUE)[1]
    sr <- as.numeric(tar[sr_row, 1])
  }

  mdd <- as.numeric(PerformanceAnalytics::maxDrawdown(ret_xts, geometric = TRUE))
  sortino <- as.numeric(PerformanceAnalytics::SortinoRatio(ret_xts, MAR = 0)) * sqrt(12)
  calmar  <- as.numeric(PerformanceAnalytics::CalmarRatio(ret_xts))

  # Hit rate via raw (not metric synthesis)
  hit <- mean(pr$ret_net > 0, na.rm = TRUE)

  list(
    label     = label,
    n_months  = nrow(pr),
    CAGR      = round(cagr, 4),
    Vol       = round(vol, 4),
    Sharpe    = round(sr, 4),
    MDD       = round(-abs(mdd), 4),   # PerformanceAnalytics maxDrawdown returns positive value
    Sortino   = round(sortino, 4),
    Calmar    = round(calmar, 4),
    HitRate   = round(hit, 4)
  )
}

# Lockbox split
LB_START <- as.Date("2024-01-23")
ADMIT_BASELINE_256m <- as.Date("2005-02-01")
RAW_COVER_267m      <- as.Date("2004-02-01")

summary_rows <- list()
for (vname in names(all_results)) {
  pr_v <- all_results[[vname]]$period_returns

  p_full   <- compute_perf_strict(pr_v, sprintf("%s_267m_raw_cover", vname),
                                    horizon_filter = RAW_COVER_267m)
  p_256m   <- compute_perf_strict(pr_v, sprintf("%s_256m_admit_comparable", vname),
                                    horizon_filter = ADMIT_BASELINE_256m)
  p_prelb  <- compute_perf_strict(pr_v[period_end <  LB_START],
                                    sprintf("%s_preLB", vname),
                                    horizon_filter = ADMIT_BASELINE_256m)
  p_lb     <- compute_perf_strict(pr_v[period_end >= LB_START],
                                    sprintf("%s_lockbox_OOS", vname))

  for (p in list(p_full, p_256m, p_prelb, p_lb)) {
    if (is.null(p)) next
    summary_rows[[length(summary_rows) + 1L]] <- as.data.table(p)
  }
}

summary_dt <- rbindlist(summary_rows, use.names = TRUE, fill = TRUE)
setorder(summary_dt, label)

cat("\n=== Performance Summary (all variants, all panels) ===\n\n")
print(summary_dt)

# ============================================================
# 8. Baseline comparison (Layer 1 same-mechanism + admit overlay reference)
# ============================================================
cat("\n[8] Baseline comparison\n")

# Same-mechanism comparable (no overlay) — Layer 1 from production audit
baseline_layer1_267m <- list(
  panel = "267m_raw_cover",
  Sharpe = 1.6315, MDD = -0.4074, CAGR = 0.4351, Vol = 0.2667, Sortino = 0.8738, Calmar = 1.0682
)
baseline_layer1_255m_admit <- list(
  panel = "255m_admit_baseline",
  Sharpe = 1.6620, MDD = -0.4074, CAGR = 0.4428, Vol = 0.2664, Sortino = 0.8818, Calmar = 1.0869
)

# Admit baseline (overlay-inclusive M4+AR) — REFERENCE only (not direct comparable)
baseline_admit_overlay_257m_str_1715 <- list(
  panel = "256m_admit_overlay_inclusive",
  Sharpe = 1.7758, MDD = -0.2515
)
baseline_production_267m <- list(
  panel = "267m_raw_cover_overlay_inclusive",
  Sharpe = 1.6957, MDD = -0.2481, CAGR = 0.3770
)

# Compute deltas for 267m raw cover
cat("\n=== ΔSharpe vs Baseline (267m raw cover, same-mechanism Layer 1) ===\n")
delta_rows <- list()
for (vname in names(all_results)) {
  row_267 <- summary_dt[label == sprintf("%s_267m_raw_cover", vname)]
  if (nrow(row_267) == 0L) next
  delta_rows[[length(delta_rows) + 1L]] <- data.table(
    variant = vname,
    panel   = "267m_raw_cover",
    Sharpe_zsc = row_267$Sharpe,
    Sharpe_baseline_L1 = baseline_layer1_267m$Sharpe,
    delta_Sharpe_vs_L1 = round(row_267$Sharpe - baseline_layer1_267m$Sharpe, 4),
    MDD_zsc = row_267$MDD,
    MDD_baseline_L1 = baseline_layer1_267m$MDD,
    delta_MDD_pp_vs_L1 = round((row_267$MDD - baseline_layer1_267m$MDD) * 100, 4),
    Sharpe_admit_overlay = baseline_admit_overlay_257m_str_1715$Sharpe,
    delta_Sharpe_vs_admit = round(row_267$Sharpe - baseline_admit_overlay_257m_str_1715$Sharpe, 4)
  )
}
delta_dt <- rbindlist(delta_rows, use.names = TRUE)
print(delta_dt)

cat("\n=== ΔSharpe vs Baseline (256m admit-comparable, Layer 1) ===\n")
delta_rows_256 <- list()
for (vname in names(all_results)) {
  row_256 <- summary_dt[label == sprintf("%s_256m_admit_comparable", vname)]
  if (nrow(row_256) == 0L) next
  delta_rows_256[[length(delta_rows_256) + 1L]] <- data.table(
    variant = vname,
    panel   = "256m_admit_comparable",
    Sharpe_zsc = row_256$Sharpe,
    Sharpe_baseline_L1_255m = baseline_layer1_255m_admit$Sharpe,
    delta_Sharpe_vs_L1 = round(row_256$Sharpe - baseline_layer1_255m_admit$Sharpe, 4),
    MDD_zsc = row_256$MDD,
    delta_MDD_pp_vs_L1 = round((row_256$MDD - baseline_layer1_255m_admit$MDD) * 100, 4),
    delta_Sharpe_vs_admit_overlay = round(row_256$Sharpe - baseline_admit_overlay_257m_str_1715$Sharpe, 4)
  )
}
delta_dt_256 <- rbindlist(delta_rows_256, use.names = TRUE)
print(delta_dt_256)

# ============================================================
# 9. Best variant selection — primary score: SR - 0.5*|MDD|
# ============================================================
cat("\n[9] Best variant selection\n")

LAMBDA_MDD <- 0.5
best_panel <- "267m_raw_cover"

scoring_rows <- list()
for (vname in names(all_results)) {
  row <- summary_dt[label == sprintf("%s_%s", vname, best_panel)]
  if (nrow(row) == 0L) next
  scoring_rows[[length(scoring_rows) + 1L]] <- data.table(
    variant   = vname,
    Sharpe    = row$Sharpe,
    MDD       = row$MDD,
    CAGR      = row$CAGR,
    Sortino   = row$Sortino,
    Calmar    = row$Calmar,
    score     = row$Sharpe - LAMBDA_MDD * abs(row$MDD)
  )
}
scoring_dt <- rbindlist(scoring_rows, use.names = TRUE)
setorder(scoring_dt, -score)
cat(sprintf("Scoring (SR - %.2f * |MDD|, %s):\n", LAMBDA_MDD, best_panel))
print(scoring_dt)

BEST_VARIANT <- scoring_dt$variant[1]
cat(sprintf("\n>>> BEST VARIANT: %s | score=%.4f <<<\n",
            BEST_VARIANT, scoring_dt$score[1]))

# ============================================================
# 10. Save artifacts (period_returns, weights, summary per variant)
# ============================================================
cat("\n[10] Save artifacts\n")

# Save period_returns + weights per variant
for (vname in names(all_results)) {
  res <- all_results[[vname]]
  fwrite(res$period_returns, file.path(BT_DIR, sprintf("period_returns_%s.csv", vname)))
  fwrite(res$weights,        file.path(BT_DIR, sprintf("weights_%s.csv", vname)))
}

# Save summary tables
fwrite(summary_dt, file.path(BT_DIR, "metrics_grid_all_variants.csv"))
fwrite(delta_dt,   file.path(BT_DIR, "delta_vs_baseline_267m.csv"))
fwrite(delta_dt_256, file.path(BT_DIR, "delta_vs_baseline_256m_admit.csv"))
fwrite(scoring_dt, file.path(BT_DIR, "scoring_best_variant.csv"))

cat(sprintf("    Saved to: %s\n", BT_DIR))

# ============================================================
# 11. Harvey-t / DSR / regime stats — best variant only
# ============================================================
cat("\n[11] Harvey-t / DSR / FF5 regression — best variant\n")

suppressPackageStartupMessages({
  library(sandwich); library(lmtest)
})

pr_best <- all_results[[BEST_VARIANT]]$period_returns
pr_best[, YM := format(period_end, "%Y-%m")]
ff5_v2_dt <- copy(ff5_v2)
ff5_v2_dt[, YM := format(Date, "%Y-%m")]

merged_ff5 <- merge(pr_best[, .(YM, period_end, ret_net)],
                     ff5_v2_dt[, .(YM, MKT, SMB, HML, WML, RMW, CMA, RF)],
                     by = "YM", all.x = TRUE)
merged_ff5[, excess_ret := ret_net - RF]
merged_ff5 <- merged_ff5[!is.na(excess_ret)]
setorder(merged_ff5, period_end)

# Subset to admit baseline (256m)
combined_admit <- merged_ff5[period_end >= ADMIT_BASELINE_256m]

nw_t_stat <- function(model, lag = NULL) {
  n <- length(residuals(model))
  if (is.null(lag)) lag <- floor(4 * (n / 100)^(2/9))
  lag <- max(1L, as.integer(lag))
  tryCatch({
    nw_vcov <- NeweyWest(model, lag = lag, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(model, vcov = nw_vcov)
    list(alpha = ct["(Intercept)", "Estimate"],
         t_nw  = ct["(Intercept)", "t value"],
         p_nw  = ct["(Intercept)", "Pr(>|t|)"],
         lag = lag, n = n)
  }, error = function(e) list(alpha=NA, t_nw=NA, p_nw=NA, lag=lag, n=n))
}

run_5spec <- function(dt, label) {
  results <- list()
  specs <- list(
    CAPM     = c("MKT"),
    Carhart3 = c("MKT","SMB","HML"),
    Carhart4 = c("MKT","SMB","HML","WML"),
    FF5      = c("MKT","SMB","HML","RMW","CMA"),
    FF6      = c("MKT","SMB","HML","WML","RMW","CMA")
  )
  for (sp in names(specs)) {
    vars <- specs[[sp]]
    sub  <- dt[rowSums(!is.na(dt[, ..vars])) == length(vars)]
    if (nrow(sub) < 20) next
    fml  <- as.formula(paste("excess_ret ~", paste(vars, collapse = " + ")))
    mod  <- lm(fml, data = sub)
    res  <- nw_t_stat(mod)
    res$spec  <- sp
    res$n_eff <- nrow(sub)
    results[[sp]] <- res
  }
  cat(sprintf("  [%s] 5-spec NW Harvey-t (gate t>=3.0):\n", label))
  pass_n <- 0
  for (sp in names(results)) {
    r <- results[[sp]]
    g <- if (!is.na(r$t_nw) && r$t_nw >= 3.0) " <<HARVEY PASS>>" else
         if (!is.na(r$t_nw) && r$t_nw >= 2.0) " [borderline]" else " [fail]"
    cat(sprintf("    %-12s: alpha=%.4f%% t_NW=%.3f n=%d lag=%d%s\n",
                sp, r$alpha * 100, r$t_nw, r$n_eff, r$lag, g))
    if (!is.na(r$t_nw) && r$t_nw >= 3.0) pass_n <- pass_n + 1
  }
  cat(sprintf("  Harvey-t PASS count: %d/5\n", pass_n))
  results
}

cat("\n--- BEST VARIANT 5-spec FF5 (256m admit-comparable) ---\n")
res_admit <- run_5spec(combined_admit, sprintf("%s_256m_admit", BEST_VARIANT))

# DSR
compute_dsr <- function(returns, n_candidates = 10, pen_per = 0.05) {
  r <- returns[!is.na(returns)]
  n <- length(r)
  if (n < 12) return(list(dsr_raw=NA, dsr_post=NA, sr_ann=NA))
  sr_m   <- mean(r) / sd(r)
  sr_ann <- sr_m * sqrt(12)
  skew   <- tryCatch(e1071::skewness(r), error = function(e) 0)
  kurt   <- tryCatch(e1071::kurtosis(r) + 3, error = function(e) 3)
  denom  <- sqrt((1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2) / (n - 1))
  dsr_raw  <- if (!is.na(denom) && denom > 1e-10) sr_ann / (denom * sqrt(12)) else NA
  dsr_post <- if (!is.na(dsr_raw)) dsr_raw - n_candidates * pen_per else NA
  list(dsr_raw = round(dsr_raw, 4), dsr_post = round(dsr_post, 4),
       sr_ann = round(sr_ann, 4))
}

# DSR cumulative penalty: 5 variants tested + cumulative chain ~25 prior
DSR_CANDIDATES <- 30L
DSR_PER        <- 0.05

dsr_best <- compute_dsr(pr_best[period_end >= ADMIT_BASELINE_256m]$ret_net,
                          n_candidates = DSR_CANDIDATES, pen_per = DSR_PER)
cat(sprintf("\n  DSR (256m admit, n_cands=%d): dsr_raw=%.4f dsr_post=%.4f sr_ann=%.4f\n",
            DSR_CANDIDATES, dsr_best$dsr_raw, dsr_best$dsr_post, dsr_best$sr_ann))

# ============================================================
# 12. Per-regime decomposition (best variant)
# ============================================================
cat("\n[12] Per-regime decomposition (best variant)\n")

regime_perf <- pr_best[, .(
  n_months = .N,
  mean_ret = mean(ret_net),
  sd_ret   = sd(ret_net),
  hit_rate = mean(ret_net > 0)
), by = regime]
regime_perf[, sr_ann := mean_ret / sd_ret * sqrt(12)]
regime_perf[, ann_ret := mean_ret * 12]
setorder(regime_perf, -n_months)
cat("\n  Per-regime metrics:\n")
print(regime_perf)

fwrite(regime_perf, file.path(BT_DIR, sprintf("regime_decomposition_%s.csv", BEST_VARIANT)))

# ============================================================
# 13. Final hash audit
# ============================================================
cat("\n[13] Final hash audit\n")
alpha_md5_post <- as.character(tools::md5sum(ALPHA_SCORES_PATH))
cat(sprintf("    alpha_scores.parquet MD5 (pre):  %s\n", substr(alpha_md5_pre, 1, 16)))
cat(sprintf("    alpha_scores.parquet MD5 (post): %s\n", substr(alpha_md5_post, 1, 16)))
hash_match <- (alpha_md5_pre == alpha_md5_post)
cat(sprintf("    Hash match (alpha lineage invariance): %s\n",
            if (hash_match) "PASS" else "FAIL"))

# ============================================================
# 14. Build forge_summary.json for orchestrator consumption
# ============================================================
cat("\n[14] Build forge_summary.json\n")

forge_summary <- list(
  task_id = WT_ID,
  strategy_label = STR_ID,
  best_variant = BEST_VARIANT,
  best_variant_description = variants[[BEST_VARIANT]]$desc,
  selection_score = scoring_dt$score[1],
  selection_lambda_mdd = LAMBDA_MDD,
  selection_panel = best_panel,
  variants_grid = lapply(names(variants), function(v) {
    list(name = v, description = variants[[v]]$desc)
  }),
  metrics_grid_267m = lapply(names(all_results), function(v) {
    row <- summary_dt[label == sprintf("%s_267m_raw_cover", v)]
    if (nrow(row) == 0L) return(NULL)
    as.list(row)
  }),
  metrics_grid_256m = lapply(names(all_results), function(v) {
    row <- summary_dt[label == sprintf("%s_256m_admit_comparable", v)]
    if (nrow(row) == 0L) return(NULL)
    as.list(row)
  }),
  baseline_comparison = list(
    same_mechanism_layer1_267m = baseline_layer1_267m,
    same_mechanism_layer1_255m_admit = baseline_layer1_255m_admit,
    admit_overlay_inclusive_256m = baseline_admit_overlay_257m_str_1715,
    production_267m_overlay_inclusive = baseline_production_267m
  ),
  harvey_t_5spec_best_256m = lapply(res_admit, function(r) {
    list(spec = r$spec, alpha_pct = r$alpha * 100, t_NW = r$t_nw,
         n_eff = r$n_eff, lag = r$lag)
  }),
  dsr_best_256m = dsr_best,
  alpha_lineage_invariance = list(
    pre_md5  = alpha_md5_pre,
    post_md5 = alpha_md5_post,
    hash_match = hash_match
  )
)

write_json(forge_summary, file.path(BT_DIR, "forge_summary.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null")

cat(sprintf("    Saved: %s/forge_summary.json\n", BT_DIR))

cat("\n============================================================\n")
cat("STR_1715_ZSC_v1 Grid Sweep — COMPLETE\n")
cat(sprintf("Best variant: %s\n", BEST_VARIANT))
cat(sprintf("Hash audit: %s\n", if (hash_match) "PASS (alpha immutable)" else "FAIL"))
cat("============================================================\n")
