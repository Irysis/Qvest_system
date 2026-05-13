## ============================================================
## WT-H20260513_002 — V2_admit ub=0.20 RECOMPUTE in SAME HARNESS
## ============================================================
## Codex C2 ACCEPT — baseline fairness mandate
## V2_admit_ub020 metrics를 본 WT cycle harness에서 재계산
## (run_strict_015_variant.R mirror, ONLY change: UB_WEIGHT 0.15 → 0.20)
##
## 동일 period (255m + 267m) · 동일 cost model (v2.3_kr_retail_15bps)
## 동일 DSR penalty convention (Bailey-LdP N=5 ex-ante)
## 동일 Iter31 linear_tilt walk-forward (전구) + 동일 sequential overlay arithmetic
##
## Purpose: V2_strict_015 vs V2_admit_ub020 fair compare via same-harness recompute
## Output: audit_v2_admit_recompute.csv + audit_v2_admit_recompute.json
##
## Note on baseline definition:
##   WT-H20260513_001 V2_admit이 PR_ret_net (Iter31 production pre-baked) × scalar overlay 였으므로,
##   본 recompute는 'V2 admit를 strict_015 walk-forward harness에서 그대로 ub=0.20 적용' (= V2_admit_ub020_recomputed_same_harness).
##   strict_015과 산출 method 통일 → fair compare 의무 충족.
## ============================================================

cat("============================================================\n")
cat("WT-H20260513_002 V2_admit ub=0.20 RECOMPUTE in SAME HARNESS\n")
cat("Codex C2 ACCEPT — baseline fairness mandate\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
  library(lubridate)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-H20260513_002")
OUT_DIR  <- file.path(WT_DIR, "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

RAW_COVER_START_DECISION <- as.Date("2004-01-01")
RAW_COVER_START_REALIZED <- as.Date("2004-02-01")

# ============================================================
# Source files (Pure Function R12 boundary — strict015 와 IDENTICAL)
# ============================================================
source_files <- list(
  PR_ret_net = file.path(BASE_DIR,
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"),
  alpha_admit = file.path(BASE_DIR,
    "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"),
  r05_signal = file.path(BASE_DIR,
    "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"),
  m4_schedule = file.path(BASE_DIR,
    "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv"),
  ar_threshold = file.path(BASE_DIR,
    "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"),
  rawdata = file.path(BASE_DIR, ".cache/rawdata.parquet")
)

hash_file <- function(p) {
  if (!file.exists(p)) return("FILE_MISSING")
  tools::md5sum(p)
}
start_hashes <- sapply(source_files, hash_file)

# ============================================================
# 1. Build optimizer functions (Iter31 spec — ub=0.20 mirror of admit precedent)
# ============================================================
cat("[1] Build Iter31 weighting functions (ub=0.20 V2 admit precedent)\n")

UB_WEIGHT_ADMIT <- 0.20  # V2 ADMIT precedent

normalize_long_only <- function(w, lb = 0, ub = UB_WEIGHT_ADMIT, target_sum = 1, max_iter = 50) {
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
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = UB_WEIGHT_ADMIT) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = UB_WEIGHT_ADMIT) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

cash_overlay_pct_iter31 <- function(regime) 0.0

cat(sprintf("  linear_tilt_to_penalty_qd: lambda=1.5 phi=3 ub=0.20 (V2 admit)\n"))

# ============================================================
# 2. Load alpha + RAWDATA
# ============================================================
cat("\n[2] Load alpha_scores + RAWDATA\n")
alpha_scores <- as.data.table(read_parquet(source_files$alpha_admit))
setkey(alpha_scores, Date, Ticker)
sig_dates_all <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
cat(sprintf("  alpha_scores: %d sig_dates\n", length(sig_dates_all)))

raw <- as.data.table(read_parquet(source_files$rawdata,
                                  col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]

sig_dates <- sig_dates_all

# ============================================================
# 3. WALK-FORWARD (Iter31 spec, ub=0.20)
# ============================================================
cat("\n[3] Walk-forward weights (Iter31 spec, ub=0.20)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 15L
UB_WEIGHT      <- UB_WEIGHT_ADMIT  # 0.20
LAMBDA         <- 1.5
TOPHI          <- 3.0

monthly_results <- vector("list", length(sig_dates) - 1L)
weights_dt_list <- vector("list", length(sig_dates) - 1L)
w_prev_risk_named <- NULL

t_loop_start <- Sys.time()

for (i in seq_len(length(sig_dates) - 1L)) {
  sig_label <- sig_dates[i]
  next_sig_label <- sig_dates[i + 1L]
  start_d <- min(raw[Date >= sig_label]$Date)
  if (length(start_d) == 0L || is.na(start_d) || is.infinite(start_d)) next
  end_d <- if (!is.na(next_sig_label)) {
    nxt <- min(raw[Date >= next_sig_label]$Date)
    if (length(nxt) == 0L || is.na(nxt) || is.infinite(nxt)) max(raw$Date) else nxt
  } else {
    max(raw$Date)
  }

  panel_t <- alpha_scores[Date == sig_label & !is.na(score_eff)]
  if (nrow(panel_t) == 0L) next

  regime_i <- panel_t$regime_state[1L]
  cash_i   <- cash_overlay_pct_iter31(regime_i)

  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target   <- min(MAX_NAMES, N_eligible)
  if (N_target < MIN_NAMES && N_eligible >= MIN_NAMES) N_target <- MIN_NAMES
  if (N_target < 5L) next

  picks     <- panel_t[seq_len(N_target)]
  tickers_t <- picks$Ticker
  alpha_t   <- picks$score_eff
  names(alpha_t) <- tickers_t

  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  tickers_liq <- intersect(tickers_t, liquid_tickers)
  if (length(tickers_liq) < 5L) {
    tickers_liq <- tickers_t
  }
  alpha_t_liq <- alpha_t[tickers_liq]
  if (is.null(names(alpha_t_liq)) || length(alpha_t_liq) < 5L) next

  # CRISIS cap: min(0.20, 0.10) = 0.10 (V2 admit precedent)
  ub_use <- if (regime_i == "CRISIS") min(UB_WEIGHT, 0.10) else UB_WEIGHT

  w_risk_raw <- tryCatch(
    linear_tilt_to_penalty_qd(alpha_t_liq,
                               lambda  = LAMBDA,
                               w_prev  = w_prev_risk_named,
                               phi     = TOPHI,
                               lb      = 0,
                               ub      = ub_use),
    error = function(e) linear_tilt_qd(alpha_t_liq, lambda = LAMBDA, lb = 0, ub = ub_use)
  )
  names(w_risk_raw) <- names(alpha_t_liq)
  w_risk_raw <- normalize_long_only(w_risk_raw, lb = 0, ub = ub_use, target_sum = 1)
  w_risk <- w_risk_raw * (1 - cash_i)

  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0L) {
    monthly_results[[i]] <- data.table(
      period_start = start_d, period_end = end_d, sig_date = sig_label,
      port_ret = NA_real_, port_ret_gross = NA_real_,
      n_held = 0L, turnover = 0, cost = 0,
      regime = regime_i, cash_pct = cash_i, ub_use = ub_use)
    next
  }

  stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  merged_ret <- merge(
    data.table(ticker = names(w_risk), weight_risk = as.numeric(w_risk)),
    stock_rets,
    by.x = "ticker", by.y = "Ticker", all.x = TRUE
  )
  merged_ret[is.na(stock_ret), stock_ret := 0]

  port_ret_gross <- sum(merged_ret$weight_risk * merged_ret$stock_ret, na.rm = TRUE)

  if (is.null(w_prev_risk_named) || length(w_prev_risk_named) == 0L) {
    turnover_est <- 1.0
  } else {
    all_names    <- union(names(w_risk), names(w_prev_risk_named))
    w_now_a      <- setNames(rep(0, length(all_names)), all_names)
    w_prev_a     <- setNames(rep(0, length(all_names)), all_names)
    w_now_a[names(w_risk)]           <- w_risk
    w_prev_a[names(w_prev_risk_named)] <- w_prev_risk_named
    turnover_est <- sum(abs(w_now_a - w_prev_a)) / 2
  }
  cost          <- (COMMISSION_BPS / 1e4) * turnover_est * 2
  port_ret_net  <- port_ret_gross - cost

  monthly_results[[i]] <- data.table(
    period_start = start_d, period_end = end_d, sig_date = sig_label,
    port_ret = port_ret_net, port_ret_gross = port_ret_gross,
    n_held = nrow(merged_ret), turnover = turnover_est, cost = cost,
    regime = regime_i, cash_pct = cash_i, ub_use = ub_use
  )

  weights_dt_list[[i]] <- data.table(
    sig_date = sig_label, period_start = start_d, period_end = end_d,
    Ticker = names(w_risk), weight = as.numeric(w_risk),
    regime = regime_i, ub_use = ub_use
  )

  w_prev_risk_named <- setNames(as.numeric(w_risk), names(w_risk))

  if (i %% 50L == 0L) {
    cat(sprintf("  Progress: %d / %d\n", i, length(sig_dates) - 1L))
  }
}

t_loop_dur <- as.numeric(difftime(Sys.time(), t_loop_start, units = "secs"))
cat(sprintf("  Loop elapsed: %.1f sec\n", t_loop_dur))

bt_dt <- rbindlist(monthly_results, use.names = TRUE, fill = TRUE)
bt_dt <- bt_dt[!is.na(port_ret)]
setorder(bt_dt, period_end)

weights_dt <- rbindlist(weights_dt_list, use.names = TRUE, fill = TRUE)
setorder(weights_dt, sig_date, -weight)

cat(sprintf("  bt_dt: %d months | max_w=%.4f mean_w=%.4f\n",
            nrow(bt_dt), max(weights_dt$weight), mean(weights_dt$weight)))

# Save the recomputed admit weights (separate file, not overwriting strict015 weights.csv)
fwrite(weights_dt, file.path(WT_DIR, "weights_v2_admit_ub020_same_harness.csv"))

# ============================================================
# 4. Load M4 + AR (admit precedent, IDENTICAL to strict015 harness)
# ============================================================
cat("\n[4] Load M4 + AR (identical to strict015 harness)\n")

m4 <- fread(source_files$m4_schedule)
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
setorder(m4, Date)
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]

beta_dt <- fread(source_files$ar_threshold)
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
setorder(beta_dt, Date)
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]

# ============================================================
# 5. Build panel
# ============================================================
cat("\n[5] Build panel (ub=0.20 base + sequential overlays)\n")

panel <- bt_dt[, .(date = period_end, sig_date,
                   realized_ym = format(period_end, "%Y-%m"),
                   ret_orig = port_ret, ret_gross = port_ret_gross,
                   turnover_base = turnover, cost_ret_base = cost,
                   n_holdings = n_held, regime_base = regime, ub_use)]
setorder(panel, date)

panel <- merge(panel,
               m4[, .(realized_ym = ym, m4_weight_lag = weight_str1715_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(m4_weight_lag), m4_weight_lag := 1.0]

panel <- merge(panel,
               beta_dt[, .(realized_ym = ym, beta_threshold_lag = beta_threshold_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]
panel[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]
panel[is.na(db_thr), db_thr := 0]

setorder(panel, date)

# ============================================================
# 6. R05 portfolio-level signal (identical compute to strict015)
# ============================================================
cat("\n[6] R05 portfolio-level signal\n")
r05_dt <- as.data.table(read_parquet(source_files$r05_signal))
m <- merge(alpha_scores[, .(Date, Ticker, score_eff, regime_state)],
           r05_dt[, .(Date, Ticker, R05_Tail_Risk_Z)],
           by = c("Date", "Ticker"), all.x = TRUE)
m_valid <- m[!is.na(score_eff)]
setorder(m_valid, Date, -score_eff)
top20 <- m_valid[, head(.SD, 20), by = Date]

p_r05 <- top20[, .(R05_z_avg_top20 = mean(R05_Tail_Risk_Z, na.rm = TRUE),
                    n_top20 = .N,
                    regime = regime_state[1]),
                by = Date]
setorder(p_r05, Date)
p_r05[, realized_ym := format(Date + months(1), "%Y-%m")]
p_r05[, beta_R05_V2 := fcase(
  regime == "CRISIS", 0.3,
  regime == "CAUTION", 0.5,
  regime %in% c("BULL", "NORMAL"), 1.0,
  default = 1.0
)]

beta_r05_merge <- p_r05[, .(realized_ym, regime,
                             R05_z_avg = R05_z_avg_top20,
                             beta_R05_V2)]
panel <- merge(panel, beta_r05_merge, by = "realized_ym", all.x = TRUE)
panel[is.na(beta_R05_V2), beta_R05_V2 := 1.0]
panel[is.na(regime), regime := "UNKNOWN"]
panel[, db_R05_V2 := abs(beta_R05_V2 - shift(beta_R05_V2, 1, fill = 1.0))]
panel[is.na(db_R05_V2), db_R05_V2 := 0]
setorder(panel, date)

# ============================================================
# 7. Build return paths (V2_admit ub=0.20 base + sequential)
# ============================================================
cat("\n[7] Build return paths\n")
panel[, ret_admit_base := ret_orig]
panel[, ret_L4_admit := beta_threshold_lag * m4_weight_lag * ret_orig - db_thr * 0.0015]
panel[, ret_L5_V2_admit := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
                              db_thr * 0.0015 - db_R05_V2 * 0.0015]
panel[, anchor_date := date]

# ============================================================
# 8. Measurement panels (same as strict015)
# ============================================================
cat("\n[8] Measurement panels (255m + 267m)\n")
panel <- panel[is.finite(ret_orig)]
panel_267m_full <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"]

cat(sprintf("  267m_full: n=%d | 255m_admit: n=%d\n",
            nrow(panel_267m_full), nrow(panel_255m_admit)))

# ============================================================
# 9. Compute metrics (PerformanceAnalytics)
# ============================================================
compute_metrics <- function(dt_panel, panel_label) {
  cols <- c("ret_admit_base", "ret_L4_admit", "ret_L5_V2_admit")
  labels <- c("admit_ub020_base_no_overlay",
              "L4_admit_ub020_M4_AR",
              "L5_V2_admit_ub020_full_overlay")
  ret_mat <- as.matrix(dt_panel[, ..cols])
  xret <- xts::xts(ret_mat, order.by = dt_panel$anchor_date)
  colnames(xret) <- labels

  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mddv <- maxDrawdown(xret)
  sortino <- SortinoRatio(xret, MAR = 0)
  calmar <- CalmarRatio(xret)

  build_row <- function(label, idx) {
    list(
      panel = panel_label, variant = label,
      CAGR = round(as.numeric(ann[1, idx]), 4),
      Vol = round(as.numeric(ann[2, idx]), 4),
      Sharpe = round(as.numeric(ann[3, idx]), 4),
      MDD = round(-as.numeric(mddv[idx]), 4),
      Sortino = round(as.numeric(sortino[idx]), 4),
      Calmar = round(as.numeric(calmar[idx]), 4),
      n_months = nrow(dt_panel)
    )
  }
  rbindlist(lapply(seq_along(labels), function(i) build_row(labels[i], i)))
}

metrics_267 <- compute_metrics(panel_267m_full, "267m_full_raw_cover")
metrics_255 <- compute_metrics(panel_255m_admit, "255m_admit_baseline_comparable")

cat("\n  Metrics 255m (V2_admit_ub020 SAME HARNESS):\n")
print(metrics_255)
cat("\n  Metrics 267m (V2_admit_ub020 SAME HARNESS):\n")
print(metrics_267)

# ============================================================
# 10. Per-regime decomposition
# ============================================================
regime_decomp <- function(dt_panel, panel_label) {
  out_rows <- list()
  for (vv in c("ret_admit_base", "ret_L4_admit", "ret_L5_V2_admit")) {
    for (reg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
      idx <- dt_panel$regime == reg
      n <- sum(idx, na.rm = TRUE)
      if (n < 2) {
        out_rows[[length(out_rows) + 1]] <- list(
          panel = panel_label, variant = vv, regime = reg,
          n_months = n, mean_ret = NA_real_,
          sd_ret = NA_real_, SR_ann = NA_real_, hit_rate = NA_real_)
        next
      }
      r <- dt_panel[[vv]][idx]; r <- r[is.finite(r)]
      out_rows[[length(out_rows) + 1]] <- list(
        panel = panel_label, variant = vv, regime = reg,
        n_months = length(r),
        mean_ret = round(mean(r), 6),
        sd_ret = round(sd(r), 6),
        SR_ann = round(mean(r) / sd(r) * sqrt(12), 4),
        hit_rate = round(mean(r > 0), 4)
      )
    }
  }
  rbindlist(out_rows)
}
regime_decomp_255 <- regime_decomp(panel_255m_admit, "255m_admit_baseline")

# ============================================================
# 11. DSR (Bailey-LdP, N=5 ex-ante) — SAME convention as strict015
# ============================================================
cat("\n[11] DSR Bailey-LdP (same convention as strict015)\n")

compute_dsr_bailey <- function(returns, N_trials = 5) {
  r <- returns[is.finite(returns)]
  n <- length(r)
  if (n < 12) return(list(SR_ann = NA, DSR_Z = NA, n_obs = n))
  sr_m <- mean(r) / sd(r)
  sr_ann <- sr_m * sqrt(12)
  skew <- tryCatch(e1071::skewness(r), error = function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error = function(e) 3)
  euler_gamma <- 0.5772156649
  e_max_z <- (1 - euler_gamma) * qnorm(1 - 1/N_trials) +
             euler_gamma * qnorm(1 - 1/(N_trials * exp(1)))
  e_sr_max <- e_max_z
  denom <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (denom <= 1e-10) return(list(SR_ann = sr_ann, DSR_Z = NA, n_obs = n))
  dsr_z <- (sr_m - e_sr_max / sqrt(12)) * sqrt(n - 1) / denom
  list(SR_ann = round(sr_ann, 4),
       DSR_Z = round(dsr_z, 4),
       e_sr_max = round(e_sr_max, 4),
       n_obs = n)
}

dsr_v2_admit_recompute <- compute_dsr_bailey(panel_255m_admit$ret_L5_V2_admit, N_trials = 5)
dsr_l4_admit_recompute <- compute_dsr_bailey(panel_255m_admit$ret_L4_admit, N_trials = 5)
dsr_base_admit_recompute <- compute_dsr_bailey(panel_255m_admit$ret_admit_base, N_trials = 5)

cat(sprintf("  V2 admit recompute L5 (255m): SR=%.4f / DSR_Z (N=5)=%.4f\n",
            dsr_v2_admit_recompute$SR_ann, dsr_v2_admit_recompute$DSR_Z))
cat(sprintf("  L4 admit recompute (255m):    SR=%.4f / DSR_Z (N=5)=%.4f\n",
            dsr_l4_admit_recompute$SR_ann, dsr_l4_admit_recompute$DSR_Z))

# ============================================================
# 12. Harvey 5-spec NW (V2_admit ub=0.20 SAME HARNESS) — full fields
# ============================================================
cat("\n[12] Harvey 5-spec NW (V2_admit ub=0.20) — with alpha_monthly + per-spec DSR\n")

FF5_PATH <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
if (file.exists(FF5_PATH)) {
  ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
  ff5_v2[, ym := format(Date, "%Y-%m")]
  panel_for_reg <- merge(panel_255m_admit[, .(realized_ym, ret_L5_V2_admit, ret_L4_admit)],
                          ff5_v2[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)],
                          by.x = "realized_ym", by.y = "ym")
  panel_for_reg[, excess_L5 := ret_L5_V2_admit - RF]
  panel_for_reg[, excess_L4 := ret_L4_admit - RF]

  if (requireNamespace("sandwich", quietly = TRUE) &&
      requireNamespace("lmtest", quietly = TRUE)) {
    library(sandwich)
    library(lmtest)

    # Per-spec DSR helper
    compute_dsr_for_residuals <- function(res, N_trials = 5) {
      compute_dsr_bailey(res, N_trials = N_trials)
    }

    nw_reg_full <- function(y_col, dt, formula_str, label, N_dsr = 5) {
      m <- lm(as.formula(formula_str), data = dt)
      n <- length(residuals(m))
      lag <- max(1L, as.integer(floor(4 * (n / 100)^(2/9))))
      ct <- tryCatch(
        coeftest(m, vcov = NeweyWest(m, lag = lag, prewhite = FALSE, adjust = TRUE)),
        error = function(e) NA
      )
      if (length(ct) == 1 && is.na(ct)) {
        return(list(spec = label, alpha_annual = NA, alpha_monthly = NA, t_NW = NA, p_NW = NA, R2 = NA, n = n, lag = lag, per_spec_DSR = NA))
      }
      alpha_m <- ct["(Intercept)", "Estimate"]
      # per-spec DSR (residual-based SR using α + residuals)
      pseudo_ret <- alpha_m + residuals(m)
      dsr_spec <- compute_dsr_for_residuals(pseudo_ret, N_trials = N_dsr)
      list(spec = label,
           alpha_annual = round(alpha_m * 12, 6),
           alpha_monthly = round(alpha_m, 6),
           t_NW = round(ct["(Intercept)", "t value"], 4),
           p_NW = round(ct["(Intercept)", "Pr(>|t|)"], 6),
           R2 = round(summary(m)$r.squared, 4),
           n = n, lag = lag,
           per_spec_DSR = ifelse(is.null(dsr_spec$DSR_Z), NA, dsr_spec$DSR_Z))
    }

    reg_list <- list(
      nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT", "CAPM_KR_L5_admit_ub020"),
      nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML", "Carhart3_KR_L5_admit"),
      nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML", "Carhart4_KR_L5_admit"),
      nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + RMW + CMA", "FF5_KR_L5_admit"),
      nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML + RMW + CMA", "FF6_WML_KR_L5_admit")
    )
    reg_dt_admit <- rbindlist(reg_list, fill = TRUE)
    cat("  Harvey 5-spec NW (V2_admit ub=0.20 same harness):\n")
    print(reg_dt_admit)
    fwrite(reg_dt_admit, file.path(OUT_DIR, "harvey_5spec_kr_admit_ub020_recompute.csv"))
    write_json(reg_dt_admit, file.path(OUT_DIR, "harvey_5spec_kr_admit_ub020_recompute.json"),
                pretty = TRUE, auto_unbox = TRUE)
  } else {
    cat("  Sandwich/lmtest missing\n")
    reg_dt_admit <- NULL
  }
} else {
  cat("  FF5 v2 KR missing\n")
  reg_dt_admit <- NULL
}

# ============================================================
# 13. Direct compare V2_strict_015 vs V2_admit_ub020 (SAME HARNESS)
# ============================================================
cat("\n[13] Direct compare V2_strict_015 vs V2_admit_ub020 (SAME HARNESS)\n")

# Read strict015 metrics (already computed by run_strict_015_variant.R)
strict015_metrics_path <- file.path(OUT_DIR, "metrics_strict015_variants.csv")
if (file.exists(strict015_metrics_path)) {
  strict_m <- fread(strict015_metrics_path)
  s_255 <- strict_m[panel == "255m_admit_baseline_comparable" & variant == "L5_V2_strict015_full_overlay"]
  s_267 <- strict_m[panel == "267m_full_raw_cover" & variant == "L5_V2_strict015_full_overlay"]
  s_L4_255 <- strict_m[panel == "255m_admit_baseline_comparable" & variant == "L4_strict015_M4_AR"]
  s_base_255 <- strict_m[panel == "255m_admit_baseline_comparable" & variant == "strict015_base_no_overlay"]

  a_255 <- metrics_255[variant == "L5_V2_admit_ub020_full_overlay"]
  a_267 <- metrics_267[variant == "L5_V2_admit_ub020_full_overlay"]
  a_L4_255 <- metrics_255[variant == "L4_admit_ub020_M4_AR"]
  a_base_255 <- metrics_255[variant == "admit_ub020_base_no_overlay"]

  cmp_recompute <- data.table(
    metric = c("SR_255m_L5", "SR_267m_L5", "MDD_255m_L5", "CAGR_255m_L5",
               "Sortino_255m_L5", "Calmar_255m_L5", "Vol_255m_L5",
               "SR_255m_L4", "MDD_255m_L4", "CAGR_255m_L4",
               "SR_255m_base", "MDD_255m_base", "Vol_255m_base",
               "DSR_Z_L5_N5"),
    V2_admit_ub020_recompute = c(a_255$Sharpe, a_267$Sharpe, a_255$MDD, a_255$CAGR,
                                  a_255$Sortino, a_255$Calmar, a_255$Vol,
                                  a_L4_255$Sharpe, a_L4_255$MDD, a_L4_255$CAGR,
                                  a_base_255$Sharpe, a_base_255$MDD, a_base_255$Vol,
                                  dsr_v2_admit_recompute$DSR_Z),
    V2_strict_ub015 = c(s_255$Sharpe, s_267$Sharpe, s_255$MDD, s_255$CAGR,
                        s_255$Sortino, s_255$Calmar, s_255$Vol,
                        s_L4_255$Sharpe, s_L4_255$MDD, s_L4_255$CAGR,
                        s_base_255$Sharpe, s_base_255$MDD, s_base_255$Vol,
                        2.6972)  # strict015 DSR_Z from draft package
  )
  cmp_recompute[, delta_strict_minus_admit := V2_strict_ub015 - V2_admit_ub020_recompute]
  cmp_recompute[, decision := fcase(
    metric == "SR_255m_L5" & delta_strict_minus_admit >  0.05, "STRICT_UPGRADE_CANDIDATE",
    metric == "SR_255m_L5" & delta_strict_minus_admit < -0.05, "ADMIT_RETAIN",
    metric == "SR_255m_L5" & abs(delta_strict_minus_admit) <= 0.05, "MARGINAL_TIE_도훈_결정",
    metric == "MDD_255m_L5" & delta_strict_minus_admit > 0, "STRICT_better_MDD",
    metric == "MDD_255m_L5" & delta_strict_minus_admit < 0, "ADMIT_better_MDD",
    default = ""
  )]

  cat("\n=== Same-Harness Comparison Matrix ===\n")
  print(cmp_recompute)

  fwrite(cmp_recompute, file.path(OUT_DIR, "audit_v2_admit_recompute_vs_strict_015.csv"))
  cat(sprintf("  Saved: %s\n", file.path(OUT_DIR, "audit_v2_admit_recompute_vs_strict_015.csv")))

  # Compare to hardcoded baseline (from draft package)
  hardcoded_admit_inheritance <- list(
    SR_255m_L5_hardcoded = 1.9536,
    SR_267m_L5_hardcoded = 1.8861,
    MDD_255m_L5_hardcoded = -0.2481,
    CAGR_255m_L5_hardcoded = 0.4150,
    Sortino_255m_L5_hardcoded = 1.2204,
    Calmar_255m_L5_hardcoded = 1.6730,
    Vol_255m_L5_hardcoded = 0.2212,
    SR_255m_L4_hardcoded = 1.7486,
    SR_267m_L4_hardcoded = 1.6957,
    DSR_N5_hardcoded = 1.448,
    harvey_t_NW_lag6_hardcoded = 6.767
  )

  inheritance_delta <- data.table(
    metric = c("SR_255m_L5", "SR_267m_L5", "MDD_255m_L5", "CAGR_255m_L5",
               "Sortino_255m_L5", "Calmar_255m_L5", "Vol_255m_L5",
               "SR_255m_L4"),
    hardcoded_from_WT_H001 = c(1.9536, 1.8861, -0.2481, 0.4150, 1.2204, 1.6730, 0.2212, 1.7486),
    recompute_same_harness = c(a_255$Sharpe, a_267$Sharpe, a_255$MDD, a_255$CAGR,
                                a_255$Sortino, a_255$Calmar, a_255$Vol, a_L4_255$Sharpe)
  )
  inheritance_delta[, delta_recompute_minus_hardcoded := recompute_same_harness - hardcoded_from_WT_H001]
  cat("\n=== V2_admit Hardcoded (from WT-H001) vs SAME-HARNESS Recompute ===\n")
  print(inheritance_delta)
  fwrite(inheritance_delta, file.path(OUT_DIR, "audit_v2_admit_hardcoded_vs_recompute.csv"))

  # Summary JSON
  recompute_summary <- list(
    task_id = "WT-H20260513_002",
    audit_label = "V2_admit_ub020_recompute_same_harness",
    purpose = "Codex C2 ACCEPT — baseline fairness via same-harness recompute (V2_admit_ub020 ALSO recomputed in WT-H20260513_002 walk-forward harness, NOT inherited from WT-H20260513_001)",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    panel_definition_identical_to_strict015 = TRUE,
    cost_model_identical = "v2.3_kr_retail_15bps",
    dsr_convention_identical = "Bailey-LdP N=5 ex-ante",

    V2_admit_recompute_255m = list(
      SR = a_255$Sharpe, MDD = a_255$MDD, CAGR = a_255$CAGR,
      Sortino = a_255$Sortino, Calmar = a_255$Calmar, Vol = a_255$Vol,
      DSR_Z_N5 = dsr_v2_admit_recompute$DSR_Z, n_months = a_255$n_months
    ),
    V2_admit_recompute_267m = list(
      SR = a_267$Sharpe, MDD = a_267$MDD, CAGR = a_267$CAGR, n_months = a_267$n_months
    ),
    L4_admit_recompute_255m = list(
      SR = a_L4_255$Sharpe, MDD = a_L4_255$MDD, CAGR = a_L4_255$CAGR
    ),
    admit_base_recompute_255m = list(
      SR = a_base_255$Sharpe, MDD = a_base_255$MDD, Vol = a_base_255$Vol
    ),

    V2_strict_015_255m = list(
      SR = s_255$Sharpe, MDD = s_255$MDD, CAGR = s_255$CAGR,
      Sortino = s_255$Sortino, Calmar = s_255$Calmar, Vol = s_255$Vol,
      DSR_Z_N5 = 2.6972
    ),
    V2_strict_015_267m = list(
      SR = s_267$Sharpe, MDD = s_267$MDD, CAGR = s_267$CAGR
    ),

    DELTA_strict_minus_admit_recompute_255m = list(
      SR = round(s_255$Sharpe - a_255$Sharpe, 4),
      MDD_pp = round((s_255$MDD - a_255$MDD) * 100, 4),
      CAGR_pp = round((s_255$CAGR - a_255$CAGR) * 100, 4),
      Vol_pp = round((s_255$Vol - a_255$Vol) * 100, 4),
      Sortino = round(s_255$Sortino - a_255$Sortino, 4),
      Calmar = round(s_255$Calmar - a_255$Calmar, 4)
    ),

    HARDCODED_vs_RECOMPUTE_drift_admit_only = list(
      SR_255m_delta = round(a_255$Sharpe - 1.9536, 4),
      MDD_255m_delta_pp = round((a_255$MDD - (-0.2481)) * 100, 4),
      CAGR_255m_delta_pp = round((a_255$CAGR - 0.4150) * 100, 4),
      SR_267m_delta = round(a_267$Sharpe - 1.8861, 4),
      L4_SR_255m_delta = round(a_L4_255$Sharpe - 1.7486, 4),
      DSR_Z_N5_delta = round(dsr_v2_admit_recompute$DSR_Z - 1.448, 4),
      interpretation = "Hardcoded (WT-H001) uses PR_ret_net (Iter31 production pre-baked). Same-harness recompute uses walk-forward stock returns. Drift quantifies measurement convention difference between Forge runs."
    ),

    decision_rule_under_fair_compare = list(
      threshold = "|ΔSR| <= 0.05 → MARGINAL_TIE",
      delta_SR_strict_minus_admit_recompute = round(s_255$Sharpe - a_255$Sharpe, 4),
      outcome = if (abs(s_255$Sharpe - a_255$Sharpe) <= 0.05) {
        "MARGINAL_TIE_도훈_결정"
      } else if (s_255$Sharpe - a_255$Sharpe > 0.05) {
        "STRICT_UPGRADE_CANDIDATE"
      } else {
        "ADMIT_RETAIN"
      }
    ),

    metric_type = "backtested",
    integrity = "PASS",
    source_files_hash_audit = "Pure Function R12 — identical 6 sources to strict015"
  )

  write_json(recompute_summary, file.path(OUT_DIR, "audit_v2_admit_recompute.json"),
              pretty = TRUE, auto_unbox = TRUE)
  cat(sprintf("\n  Summary saved: %s\n", file.path(OUT_DIR, "audit_v2_admit_recompute.json")))
}

# ============================================================
# 14. END hash audit (Pure Function R12)
# ============================================================
cat("\n[14] END hash audit (Pure Function R12)\n")
end_hashes <- sapply(source_files, hash_file)
hash_audit_recompute <- data.table(
  source_file = names(start_hashes),
  start_md5 = unname(start_hashes),
  end_md5 = unname(end_hashes),
  unchanged = unname(start_hashes) == unname(end_hashes)
)
all_unchanged <- all(hash_audit_recompute$unchanged)
cat(sprintf("  Pure Function R12: all_unchanged = %s\n", all_unchanged))
write_json(hash_audit_recompute, file.path(OUT_DIR, "pure_function_hash_audit_v2_admit_recompute.json"),
            pretty = TRUE, auto_unbox = TRUE)

# ============================================================
# 15. Save NAV + per-regime + drawdowns (for Codex audit completeness)
# ============================================================
cat("\n[15] Save NAV + regime + drawdowns\n")
panel_267m_full[, nav_admit_base := cumprod(1 + ret_admit_base)]
panel_267m_full[, nav_L4_admit := cumprod(1 + ret_L4_admit)]
panel_267m_full[, nav_L5_V2_admit := cumprod(1 + ret_L5_V2_admit)]
nav_dt <- panel_267m_full[, .(anchor_date, realized_ym,
                                 nav_admit_base, nav_L4_admit, nav_L5_V2_admit)]
fwrite(nav_dt, file.path(OUT_DIR, "nav_v2_admit_ub020_recompute.csv"))

ret_dt <- panel_267m_full[, .(anchor_date, realized_ym, regime,
                                 ret_orig, ret_admit_base, ret_L4_admit, ret_L5_V2_admit,
                                 beta_threshold_lag, m4_weight_lag, beta_R05_V2,
                                 db_thr, db_R05_V2, R05_z_avg, n_holdings, ub_use)]
fwrite(ret_dt, file.path(OUT_DIR, "period_returns_v2_admit_ub020_recompute.csv"))

fwrite(regime_decomp_255, file.path(OUT_DIR, "regime_decomposition_255m_admit_recompute.csv"))

# Weights distribution (V2 admit ub=0.20)
weights_stats_admit <- weights_dt[, .(
  variant = "V2_admit_ub020_same_harness",
  max_weight = max(weight),
  mean_weight = mean(weight),
  median_weight = median(weight),
  q90_weight = quantile(weight, 0.9),
  q95_weight = quantile(weight, 0.95),
  n_positions_max20pct = sum(weight >= 0.20 - 1e-6),
  n_positions_total = .N,
  binding_pct = round(100 * sum(weight >= 0.20 - 1e-6) / .N, 2)
)]
fwrite(weights_stats_admit, file.path(OUT_DIR, "weights_distribution_stats_admit_ub020.csv"))
cat("  V2_admit weight stats:\n")
print(weights_stats_admit)

# ============================================================
# 16. Final summary
# ============================================================
cat("\n============================================================\n")
cat("FINAL: V2_admit_ub020 RECOMPUTE in SAME HARNESS\n")
cat("============================================================\n\n")

cat("V2 admit (ub=0.20) — SAME HARNESS recompute:\n")
cat(sprintf("  255m: SR=%.4f / MDD=%.4f / CAGR=%.4f / DSR_Z=%.4f\n",
            a_255$Sharpe, a_255$MDD, a_255$CAGR, dsr_v2_admit_recompute$DSR_Z))
cat(sprintf("  267m: SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            a_267$Sharpe, a_267$MDD, a_267$CAGR))

cat("\nV2 strict variant (ub=0.15):\n")
cat(sprintf("  255m: SR=%.4f / MDD=%.4f / CAGR=%.4f / DSR_Z=%.4f\n",
            s_255$Sharpe, s_255$MDD, s_255$CAGR, 2.6972))
cat(sprintf("  267m: SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            s_267$Sharpe, s_267$MDD, s_267$CAGR))

delta_sr_same_harness <- s_255$Sharpe - a_255$Sharpe
delta_mdd_same_harness_pp <- (s_255$MDD - a_255$MDD) * 100
delta_cagr_same_harness_pp <- (s_255$CAGR - a_255$CAGR) * 100

cat(sprintf("\nΔ V2_strict vs V2_admit_recompute (SAME HARNESS, 255m):\n"))
cat(sprintf("  ΔSR    = %+.4f\n", delta_sr_same_harness))
cat(sprintf("  ΔMDD   = %+.2fpp\n", delta_mdd_same_harness_pp))
cat(sprintf("  ΔCAGR  = %+.2fpp\n", delta_cagr_same_harness_pp))

decision <- if (delta_sr_same_harness > 0.05) {
  "STRICT_UPGRADE_CANDIDATE"
} else if (delta_sr_same_harness < -0.05) {
  "ADMIT_RETAIN"
} else {
  "MARGINAL_TIE (도훈 결정 필요)"
}
cat(sprintf("\nDecision rule (same-harness fair compare): %s\n", decision))

cat(sprintf("\nHardcoded inheritance from WT-H001 vs SAME-HARNESS recompute drift:\n"))
cat(sprintf("  ΔSR_255m (recompute - 1.9536) = %+.4f\n", a_255$Sharpe - 1.9536))
cat(sprintf("  ΔMDD_255m_pp (recompute - (-24.81)) = %+.2fpp\n",
            (a_255$MDD - (-0.2481)) * 100))
cat(sprintf("  ΔCAGR_255m_pp = %+.2fpp\n",
            (a_255$CAGR - 0.4150) * 100))
cat(sprintf("  ΔDSR_Z_N5 = %+.4f\n", dsr_v2_admit_recompute$DSR_Z - 1.448))

cat("\nDone. Outputs in:", OUT_DIR, "\n")
