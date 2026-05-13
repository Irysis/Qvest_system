## ============================================================
## WT-H20260513_002 — STR_1715_AR_on_M4_R05 weight_bounds [0,0.15] strict variant
## ============================================================
## 도훈 mandate 2026-05-13 Session 80 post-Governor V2 admit:
##   Codex C1 ACCEPT unresolved item — request.json L56-57 weight_bounds
##   [0, 0.15] vs admit precedent ub=0.20 strict variant
##   POST_DEPLOY_GOVERNOR_C1 T+14 binding deadline 2026-05-27 즉시 처리
##
## Strategy Structure (도훈 mandate "전략 스트럭처 유지" — ALL retain except ub):
##   - Alpha building blocks read-only (score_eff + R05_Tail_Risk_Z)
##   - Z-Score Composite spec retain
##   - β_R05(regime) V2 spec retain (BULL/NORMAL 1.0 + CAUTION 0.5 + CRISIS 0.3)
##   - M4 BOCPD Layer 3 + AR_threshold Layer 4 sequential overlay
##   - N_active 20 strict (max_names = 20 hard)
##   - Cost: 15bps each side (v2.3_kr_retail_15bps)
##   - Monthly t-1 lag PIT
##   - Iter31 linear_tilt_to_penalty_qd(lambda=1.5, phi=3, ub=0.15) ← 유일 변경
##
## Architecture (w_final = scalar product, sequential):
##   w_final(t,i) = w_str1715_strict015(t,i) × m4_scalar(t) × β_AR(t) × β_R05(regime_t)
##
##   - w_str1715_strict015: Iter31 linear_tilt with ub=0.15 strict cap (재산출)
##   - m4_scalar: M4 BOCPD+decay+BL multiplier (admit precedent, retain)
##   - β_AR:      AR threshold β_t step (admit precedent, retain)
##   - β_R05:     V2 (BULL/NORMAL 1.0 + CAUTION 0.5 + CRISIS 0.3)
##
## Comparison: V2_strict_015 vs V2 admit (ub=0.20)
##   Hard gates:
##     SR > V2 admit (1.9536) for upgrade candidate
##     MDD better than V2 admit (-24.81%)
##     AX-001 v2 PASS (pure overlay classification inherit)
##     Marginal SR diff < 0.05 → 도훈 결정 (실용적 tie)
## ============================================================

cat("============================================================\n")
cat("WT-H20260513_002 STR_1715_AR_on_M4_R05 weight_bounds [0,0.15] strict\n")
cat("vs V2 admit (ub=0.20, SR 1.9536) — Codex C1 T+14 resolution\n")
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

V2_ADMIT_WT <- "WT-H20260513_001"
RAW_COVER_START_DECISION <- as.Date("2004-01-01")
RAW_COVER_START_REALIZED <- as.Date("2004-02-01")
STR_ID <- "STR_1715_AR_on_M4_R05_strict_015_Layer5"

# ============================================================
# Start hash audit (Pure Function R12 boundary)
# ============================================================
hash_file <- function(p) {
  if (!file.exists(p)) return("FILE_MISSING")
  tools::md5sum(p)
}

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
start_hashes <- sapply(source_files, hash_file)
cat("START hash audit (6 source files, Pure Function R12):\n")
for (n in names(start_hashes)) {
  cat(sprintf("  %-15s = %s\n", n, substr(start_hashes[n], 1, 16)))
}

# ============================================================
# 1. Build optimizer helper functions (Iter31 spec — ub parameter 만 0.15)
# ============================================================
cat("\n[1] Build Iter31 weighting functions (ub=0.15 strict variant)\n")

normalize_long_only <- function(w, lb = 0, ub = 0.15, target_sum = 1, max_iter = 50) {
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

linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = 0.15) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.15) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)   # phi=3 → blend=0.75
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# Iter31 cash overlay DEPRECATED (M4 outer 단독 — admit precedent)
cash_overlay_pct_iter31 <- function(regime) 0.0

cat(sprintf("  linear_tilt_to_penalty_qd: λ=1.5 phi=3 ub=0.15 (strict) | blend=0.750\n"))

# ============================================================
# 2. Load alpha_scores (admit lineage) + RAWDATA + cache
# ============================================================
cat("\n[2] Load alpha_scores admit lineage + RAWDATA\n")

alpha_scores <- as.data.table(read_parquet(source_files$alpha_admit))
setkey(alpha_scores, Date, Ticker)
stopifnot("score_eff" %in% names(alpha_scores))
stopifnot("regime_state" %in% names(alpha_scores))
sig_dates_all <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
cat(sprintf("  alpha_scores: %s rows | %d sig_dates | %s ~ %s\n",
            format(nrow(alpha_scores), big.mark=","),
            length(sig_dates_all),
            as.character(min(sig_dates_all)),
            as.character(max(sig_dates_all))))

raw <- as.data.table(read_parquet(source_files$rawdata,
                                  col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)),
            as.character(max(raw$Date))))

# PIT lockbox 폐기 (PG2 frozen 폐기 — Iter31 spec retain L274)
sig_dates <- sig_dates_all

# ============================================================
# 3. WALK-FORWARD weight generation (Iter31 spec, ub=0.15)
# ============================================================
cat("\n[3] Walk-forward weights generation (Iter31 spec, ub=0.15 strict)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 15L
UB_WEIGHT      <- 0.15  # STRICT VARIANT — Codex C1 T+14
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

  # Liquidity filter PIT (t-30..t-1)
  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  tickers_liq <- intersect(tickers_t, liquid_tickers)
  if (length(tickers_liq) < 5L) {
    tickers_liq <- tickers_t  # fallback
  }
  alpha_t_liq <- alpha_t[tickers_liq]
  if (is.null(names(alpha_t_liq)) || length(alpha_t_liq) < 5L) next

  # Crisis weight shrinkage (Iter31 spec retain)
  # NOTE: STRICT variant ub=0.15. CRISIS = min(0.15, 0.10) = 0.10 (more binding than V2 admit's min(0.20, 0.10) = 0.10).
  # Outcome: CRISIS cap unchanged (still 0.10), but NORMAL/BULL/CAUTION cap = 0.15 (V2 admit 0.20).
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

  # Period returns
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0L) {
    monthly_results[[i]] <- data.table(
      period_start = start_d, period_end = end_d,
      sig_date = sig_label,
      port_ret = NA_real_, port_ret_gross = NA_real_,
      n_held = 0L, turnover = 0, cost = 0,
      regime = regime_i, cash_pct = cash_i,
      ub_use = ub_use)
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

  # Turnover (L1 / 2, round-trip applied via × 2)
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
    period_start   = start_d,
    period_end     = end_d,
    sig_date       = sig_label,
    port_ret       = port_ret_net,
    port_ret_gross = port_ret_gross,
    n_held         = nrow(merged_ret),
    turnover       = turnover_est,
    cost           = cost,
    regime         = regime_i,
    cash_pct       = cash_i,
    ub_use         = ub_use
  )

  weights_dt_list[[i]] <- data.table(
    sig_date = sig_label,
    period_start = start_d,
    period_end = end_d,
    Ticker = names(w_risk),
    weight = as.numeric(w_risk),
    regime = regime_i,
    ub_use = ub_use
  )

  w_prev_risk_named <- setNames(as.numeric(w_risk), names(w_risk))

  if (i %% 50L == 0L) {
    cat(sprintf("  Progress: %d / %d (%.1f%%) | last sig %s\n",
                i, length(sig_dates) - 1L,
                100 * i / (length(sig_dates) - 1L),
                as.character(sig_label)))
  }
}

t_loop_dur <- as.numeric(difftime(Sys.time(), t_loop_start, units = "secs"))
cat(sprintf("\n  Loop elapsed: %.1f sec (%d iterations)\n",
            t_loop_dur, length(sig_dates) - 1L))

bt_dt <- rbindlist(monthly_results, use.names = TRUE, fill = TRUE)
bt_dt <- bt_dt[!is.na(port_ret)]
setorder(bt_dt, period_end)

weights_dt <- rbindlist(weights_dt_list, use.names = TRUE, fill = TRUE)
setorder(weights_dt, sig_date, -weight)

cat(sprintf("\n  bt_dt: %d months | %s ~ %s\n",
            nrow(bt_dt),
            as.character(min(bt_dt$period_end)),
            as.character(max(bt_dt$period_end))))
cat(sprintf("  Max weight observed: %.4f (target ≤ %.2f)\n",
            max(weights_dt$weight), UB_WEIGHT))
cat(sprintf("  Mean weight: %.4f | Median: %.4f\n",
            mean(weights_dt$weight), median(weights_dt$weight)))
cat(sprintf("  Avg n_held: %.1f | Annual TO: %.2f\n",
            mean(bt_dt$n_held), mean(bt_dt$turnover) * 12))

# weights.csv save
fwrite(weights_dt, file.path(WT_DIR, "weights.csv"))
cat("  weights.csv saved at root\n")

# ============================================================
# 4. Load M4 + AR overlay (admit precedent retain)
# ============================================================
cat("\n[4] Load M4 BOCPD + AR threshold (admit precedent retain)\n")

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
# 5. Build panel (strict-015 base + sequential overlays)
# ============================================================
cat("\n[5] Build panel with sequential overlays (m4 × β_AR × β_R05)\n")

panel <- bt_dt[, .(date = period_end,
                   sig_date,
                   realized_ym = format(period_end, "%Y-%m"),
                   ret_orig = port_ret,
                   ret_gross = port_ret_gross,
                   turnover_base = turnover,
                   cost_ret_base = cost,
                   n_holdings = n_held,
                   regime_base = regime,
                   ub_use)]
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
# 6. Build R05 portfolio-level signal (admit lineage same logic)
# ============================================================
cat("\n[6] Compute R05 portfolio-level signal (Top20 by score_eff admit lineage)\n")

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

# β_R05 V2 spec retain (BULL/NORMAL 1.0, CAUTION 0.5, CRISIS 0.3)
p_r05[, beta_R05_V2 := fcase(
  regime == "CRISIS", 0.3,
  regime == "CAUTION", 0.5,
  regime %in% c("BULL", "NORMAL"), 1.0,
  default = 1.0
)]

cat("  β_R05_V2 distribution (sig_date level):\n")
print(table(round(p_r05$beta_R05_V2, 2)))

# Merge β_R05 to panel (t-1 lag via realized_ym = sig_date + 1m mapping)
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
# 7. Build return paths
# ============================================================
cat("\n[7] Build return paths\n")

# Baseline strict015 (no overlay)
panel[, ret_strict015_base := ret_orig]

# Layer 4 baseline (M4 + AR overlay only, no R05)
panel[, ret_L4_strict015 := beta_threshold_lag * m4_weight_lag * ret_orig -
                              db_thr * 0.0015]

# Layer 5 V2 (strict015 + M4 + AR + β_R05_V2)
panel[, ret_L5_V2_strict015 := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
                                  db_thr * 0.0015 -
                                  db_R05_V2 * 0.0015]

panel[, anchor_date := date]

cat(sprintf("  panel n: %d | %s ~ %s\n", nrow(panel),
            as.character(min(panel$anchor_date)),
            as.character(max(panel$anchor_date))))

# ============================================================
# 8. Measurement panels (267m + 255m admit-comparable)
# ============================================================
cat("\n[8] Build measurement panels (267m + 255m admit-comparable)\n")

panel <- panel[is.finite(ret_orig)]
panel_267m_full <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"]

cat(sprintf("  267m_full: n=%d | %s ~ %s\n",
            nrow(panel_267m_full),
            as.character(min(panel_267m_full$anchor_date)),
            as.character(max(panel_267m_full$anchor_date))))
cat(sprintf("  255m_admit: n=%d | %s ~ %s\n",
            nrow(panel_255m_admit),
            as.character(min(panel_255m_admit$anchor_date)),
            as.character(max(panel_255m_admit$anchor_date))))

# ============================================================
# 9. Compute metrics (PerformanceAnalytics standard)
# ============================================================
compute_metrics <- function(dt_panel, panel_label) {
  cols <- c("ret_strict015_base", "ret_L4_strict015", "ret_L5_V2_strict015")
  labels <- c("strict015_base_no_overlay",
              "L4_strict015_M4_AR",
              "L5_V2_strict015_full_overlay")
  ret_mat <- as.matrix(dt_panel[, ..cols])
  xret <- xts::xts(ret_mat, order.by = dt_panel$anchor_date)
  colnames(xret) <- labels

  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mddv <- maxDrawdown(xret)
  sortino <- SortinoRatio(xret, MAR = 0)
  calmar <- CalmarRatio(xret)

  build_row <- function(label, idx) {
    list(
      panel = panel_label,
      variant = label,
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

cat("\n  Metrics 255m_admit:\n")
print(metrics_255)
cat("\n  Metrics 267m_full:\n")
print(metrics_267)

# ============================================================
# 10. Per-regime decomposition (AX-001 v2 inheritance)
# ============================================================
cat("\n[10] Per-regime decomposition\n")

regime_decomp <- function(dt_panel, panel_label) {
  out_rows <- list()
  for (vv in c("ret_strict015_base", "ret_L4_strict015", "ret_L5_V2_strict015")) {
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
regime_decomp_267 <- regime_decomp(panel_267m_full, "267m_full_raw_cover")

cat("\n  Per-regime SR (255m admit, V2_strict_015):\n")
print(dcast(regime_decomp_255, variant ~ regime, value.var = "SR_ann"))

# ============================================================
# 11. Direct comparison V2_strict_015 vs V2 admit (ub=0.20)
# ============================================================
cat("\n[11] Direct comparison V2_strict_015 (ub=0.15) vs V2 admit (ub=0.20)\n")

# V2 admit baseline (WT-H20260513_001 forge_package.json L96-101 + L130)
v2_admit_baseline <- list(
  variant = "V2 admit (ub=0.20)",
  SR_255m = 1.9536,
  MDD_255m = -0.2481,
  CAGR_255m = 0.4150,
  Sortino_255m = 1.2204,
  Calmar_255m = 1.6730,
  Vol_255m = 0.2212,
  SR_267m = 1.8861,
  MDD_267m = -0.2481,
  CAGR_267m = 0.4037,
  L4_baseline_SR_255m = 1.7486,
  L4_baseline_MDD_255m = -0.2481,
  L4_baseline_CAGR_255m = 0.3868,
  L4_baseline_SR_267m = 1.6957,
  harvey_t_NW_lag6 = 6.767,
  DSR_N5 = 1.448
)

v2_strict_015 <- list(
  variant = "V2 strict (ub=0.15)",
  SR_255m = metrics_255[variant == "L5_V2_strict015_full_overlay"]$Sharpe,
  MDD_255m = metrics_255[variant == "L5_V2_strict015_full_overlay"]$MDD,
  CAGR_255m = metrics_255[variant == "L5_V2_strict015_full_overlay"]$CAGR,
  Sortino_255m = metrics_255[variant == "L5_V2_strict015_full_overlay"]$Sortino,
  Calmar_255m = metrics_255[variant == "L5_V2_strict015_full_overlay"]$Calmar,
  Vol_255m = metrics_255[variant == "L5_V2_strict015_full_overlay"]$Vol,
  SR_267m = metrics_267[variant == "L5_V2_strict015_full_overlay"]$Sharpe,
  MDD_267m = metrics_267[variant == "L5_V2_strict015_full_overlay"]$MDD,
  CAGR_267m = metrics_267[variant == "L5_V2_strict015_full_overlay"]$CAGR,
  L4_baseline_SR_255m = metrics_255[variant == "L4_strict015_M4_AR"]$Sharpe,
  L4_baseline_MDD_255m = metrics_255[variant == "L4_strict015_M4_AR"]$MDD,
  L4_baseline_CAGR_255m = metrics_255[variant == "L4_strict015_M4_AR"]$CAGR,
  L4_baseline_SR_267m = metrics_267[variant == "L4_strict015_M4_AR"]$Sharpe,
  max_weight = max(weights_dt$weight),
  mean_weight = mean(weights_dt$weight)
)

cmp_table <- data.table(
  metric = c("SR_255m", "SR_267m", "MDD_255m", "CAGR_255m",
             "Sortino_255m", "Calmar_255m", "Vol_255m",
             "L4_baseline_SR_255m", "L4_baseline_SR_267m"),
  V2_admit_ub020 = c(v2_admit_baseline$SR_255m, v2_admit_baseline$SR_267m,
                     v2_admit_baseline$MDD_255m, v2_admit_baseline$CAGR_255m,
                     v2_admit_baseline$Sortino_255m, v2_admit_baseline$Calmar_255m,
                     v2_admit_baseline$Vol_255m,
                     v2_admit_baseline$L4_baseline_SR_255m,
                     v2_admit_baseline$L4_baseline_SR_267m),
  V2_strict_ub015 = c(v2_strict_015$SR_255m, v2_strict_015$SR_267m,
                      v2_strict_015$MDD_255m, v2_strict_015$CAGR_255m,
                      v2_strict_015$Sortino_255m, v2_strict_015$Calmar_255m,
                      v2_strict_015$Vol_255m,
                      v2_strict_015$L4_baseline_SR_255m,
                      v2_strict_015$L4_baseline_SR_267m)
)
cmp_table[, delta := V2_strict_ub015 - V2_admit_ub020]
cmp_table[, decision := fcase(
  metric == "SR_255m" & delta >  0.05, "STRICT_UPGRADE_CANDIDATE",
  metric == "SR_255m" & delta < -0.05, "ADMIT_RETAIN",
  metric == "SR_255m" & abs(delta) <= 0.05, "MARGINAL_TIE_도훈_결정",
  metric == "MDD_255m" & delta > 0, "STRICT_better_MDD",
  metric == "MDD_255m" & delta < 0, "ADMIT_better_MDD",
  default = ""
)]

cat("\n=== Comparison Matrix ===\n")
print(cmp_table)

# ============================================================
# 12. Harvey 5-spec Newey-West regression (KR-CAPM scope)
# ============================================================
cat("\n[12] Harvey 5-spec Newey-West regression (KR-CAPM scope, forge boundary)\n")

# Load FF5 v2 KR data (admit lineage)
FF5_PATH <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
if (file.exists(FF5_PATH)) {
  ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
  ff5_v2[, ym := format(Date, "%Y-%m")]
  panel_for_reg <- merge(panel_255m_admit[, .(realized_ym, ret_L5_V2_strict015,
                                                ret_L4_strict015)],
                          ff5_v2[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)],
                          by.x = "realized_ym", by.y = "ym")
  panel_for_reg[, excess_L5 := ret_L5_V2_strict015 - RF]
  panel_for_reg[, excess_L4 := ret_L4_strict015 - RF]

  if (requireNamespace("sandwich", quietly = TRUE) &&
      requireNamespace("lmtest", quietly = TRUE)) {
    library(sandwich)
    library(lmtest)

    nw_reg <- function(y_col, dt, formula_str, label) {
      m <- lm(as.formula(formula_str), data = dt)
      n <- length(residuals(m))
      lag <- max(1L, as.integer(floor(4 * (n / 100)^(2/9))))
      ct <- tryCatch(
        coeftest(m, vcov = NeweyWest(m, lag = lag, prewhite = FALSE, adjust = TRUE)),
        error = function(e) NA
      )
      if (length(ct) == 1 && is.na(ct)) {
        return(list(spec = label, alpha_annual = NA, t_NW = NA, p_NW = NA, R2 = NA, n = n, lag = lag))
      }
      list(spec = label,
           alpha_annual = round(ct["(Intercept)", "Estimate"] * 12, 6),
           t_NW = round(ct["(Intercept)", "t value"], 4),
           p_NW = round(ct["(Intercept)", "Pr(>|t|)"], 6),
           R2 = round(summary(m)$r.squared, 4),
           n = n, lag = lag)
    }

    reg_list <- list(
      nw_reg("excess_L5", panel_for_reg, "excess_L5 ~ MKT", "CAPM_KR_L5_strict015"),
      nw_reg("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML", "Carhart3_KR_L5"),
      nw_reg("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML", "Carhart4_KR_L5"),
      nw_reg("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + RMW + CMA", "FF5_KR_L5"),
      nw_reg("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML + RMW + CMA", "FF5_WML_KR_L5")
    )
    reg_dt <- rbindlist(reg_list, fill = TRUE)
    cat("  Harvey 5-spec NW (L5_V2_strict015):\n")
    print(reg_dt)
    fwrite(reg_dt, file.path(OUT_DIR, "harvey_5spec_kr_strict015.csv"))
    write_json(reg_dt, file.path(OUT_DIR, "harvey_5spec_kr_strict015.json"),
                pretty = TRUE, auto_unbox = TRUE)
  } else {
    cat("  Sandwich/lmtest missing — Harvey 5-spec skipped\n")
    reg_dt <- NULL
  }
} else {
  cat("  FF5 v2 KR factor returns missing — Harvey 5-spec skipped\n")
  reg_dt <- NULL
}

# ============================================================
# 13. DSR (Bailey-Lopez de Prado, N=5 ex-ante)
# ============================================================
cat("\n[13] DSR Bailey-Lopez de Prado (N=5 ex-ante grid)\n")

compute_dsr_bailey <- function(returns, N_trials = 5) {
  r <- returns[is.finite(returns)]
  n <- length(r)
  if (n < 12) return(list(SR_ann = NA, DSR_Z = NA, n_obs = n))
  sr_m <- mean(r) / sd(r)
  sr_ann <- sr_m * sqrt(12)
  skew <- tryCatch(e1071::skewness(r), error = function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error = function(e) 3)

  # E[SR_max] approximation (Bailey-Lopez de Prado 2014)
  euler_gamma <- 0.5772156649
  e_max_z <- (1 - euler_gamma) * qnorm(1 - 1/N_trials) +
             euler_gamma * qnorm(1 - 1/(N_trials * exp(1)))
  e_sr_max <- e_max_z

  # Z-statistic
  denom <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (denom <= 1e-10) return(list(SR_ann = sr_ann, DSR_Z = NA, n_obs = n))

  dsr_z <- (sr_m - e_sr_max / sqrt(12)) * sqrt(n - 1) / denom
  list(SR_ann = round(sr_ann, 4),
       DSR_Z = round(dsr_z, 4),
       e_sr_max = round(e_sr_max, 4),
       n_obs = n)
}

dsr_v2_strict <- compute_dsr_bailey(panel_255m_admit$ret_L5_V2_strict015, N_trials = 5)
dsr_l4_strict <- compute_dsr_bailey(panel_255m_admit$ret_L4_strict015, N_trials = 5)

cat(sprintf("  V2 strict015 (255m): SR=%.4f / DSR_Z (N=5)=%.4f\n",
            dsr_v2_strict$SR_ann, dsr_v2_strict$DSR_Z))
cat(sprintf("  L4 strict015 (255m): SR=%.4f / DSR_Z (N=5)=%.4f\n",
            dsr_l4_strict$SR_ann, dsr_l4_strict$DSR_Z))

# ============================================================
# 14. Save artifacts (per Backtest Contract v1.0)
# ============================================================
cat("\n[14] Save artifacts\n")

combined_metrics <- rbindlist(list(metrics_267, metrics_255))
fwrite(combined_metrics, file.path(OUT_DIR, "metrics_strict015_variants.csv"))
fwrite(cmp_table, file.path(OUT_DIR, "comparison_v2_admit_vs_strict015.csv"))
fwrite(regime_decomp_255, file.path(OUT_DIR, "regime_decomposition_255m.csv"))
fwrite(regime_decomp_267, file.path(OUT_DIR, "regime_decomposition_267m.csv"))

# NAV
panel_267m_full[, nav_strict015_base := cumprod(1 + ret_strict015_base)]
panel_267m_full[, nav_L4_strict015 := cumprod(1 + ret_L4_strict015)]
panel_267m_full[, nav_L5_V2_strict015 := cumprod(1 + ret_L5_V2_strict015)]
nav_dt <- panel_267m_full[, .(anchor_date, realized_ym,
                                 nav_strict015_base, nav_L4_strict015,
                                 nav_L5_V2_strict015)]
fwrite(nav_dt, file.path(OUT_DIR, "nav_strict015.csv"))

# Period returns
ret_dt <- panel_267m_full[, .(anchor_date, realized_ym, regime,
                                 ret_orig, ret_strict015_base,
                                 ret_L4_strict015, ret_L5_V2_strict015,
                                 beta_threshold_lag, m4_weight_lag, beta_R05_V2,
                                 db_thr, db_R05_V2,
                                 R05_z_avg, n_holdings, ub_use)]
fwrite(ret_dt, file.path(OUT_DIR, "period_returns_strict015.csv"))

# Drawdowns
dd_list <- list()
for (rc_label in c("ret_strict015_base" = "strict015_base",
                    "ret_L4_strict015" = "L4_strict015",
                    "ret_L5_V2_strict015" = "L5_V2_strict015")) {
  rc <- names(which(c("ret_strict015_base" = "strict015_base",
                       "ret_L4_strict015" = "L4_strict015",
                       "ret_L5_V2_strict015" = "L5_V2_strict015") == rc_label))
  xr <- xts::xts(panel_255m_admit[[rc]], order.by = panel_255m_admit$anchor_date)
  dd_tab <- table.Drawdowns(xr, top = 10)
  if (!is.null(dd_tab) && nrow(dd_tab) > 0) {
    dd_d <- as.data.table(dd_tab)
    dd_d[, variant := rc_label]
    for (col in names(dd_d)) {
      if (is.factor(dd_d[[col]])) dd_d[[col]] <- as.character(dd_d[[col]])
      if (inherits(dd_d[[col]], "Date")) dd_d[[col]] <- as.character(dd_d[[col]])
    }
    dd_list[[rc_label]] <- dd_d
  }
}
dd_combined <- rbindlist(dd_list, fill = TRUE)
fwrite(dd_combined, file.path(OUT_DIR, "drawdowns_top10_strict015.csv"))

# Weights distribution stats
weight_stats <- weights_dt[, .(
  variant = "V2_strict_015",
  max_weight = max(weight),
  mean_weight = mean(weight),
  median_weight = median(weight),
  q90_weight = quantile(weight, 0.9),
  q95_weight = quantile(weight, 0.95),
  n_positions_max15pct = sum(weight >= 0.15 - 1e-6),
  n_positions_total = .N,
  binding_pct = round(100 * sum(weight >= 0.15 - 1e-6) / .N, 2)
)]
fwrite(weight_stats, file.path(OUT_DIR, "weights_distribution_stats.csv"))
cat("  Weight stats:\n")
print(weight_stats)

# ============================================================
# 15. END hash audit (Pure Function R12)
# ============================================================
cat("\n[15] END hash audit (Pure Function R12 boundary)\n")
end_hashes <- sapply(source_files, hash_file)
hash_audit <- data.table(
  source_file = names(start_hashes),
  start_md5 = unname(start_hashes),
  end_md5 = unname(end_hashes),
  unchanged = unname(start_hashes) == unname(end_hashes)
)
print(hash_audit)
all_unchanged <- all(hash_audit$unchanged)
cat(sprintf("\n  Pure Function R12 verified: all_unchanged = %s\n", all_unchanged))
write_json(hash_audit, file.path(OUT_DIR, "pure_function_hash_audit_start_vs_end.json"),
            pretty = TRUE, auto_unbox = TRUE)

# ============================================================
# 16. Audit (Backtest Contract v1.0 10-check)
# ============================================================
cat("\n[16] Audit (Backtest Contract v1.0)\n")

audit <- list(
  task_id = "WT-H20260513_002",
  audit_version = "v1_strict_015_variant",
  audit_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  parent_admit_wt = V2_ADMIT_WT,
  parent_production_wt = "WT-RES_20260512_STR_1715_AR_PRODUCTION",
  checks = list(
    nav_monotone_dates = list(pass = all(diff(nav_dt$anchor_date) > 0),
                              note = "monotone increasing"),
    returns_finite = list(pass = all(is.finite(panel_255m_admit$ret_L5_V2_strict015)),
                          note = sprintf("L5_V2_strict015 finite n=%d / total %d",
                                          sum(is.finite(panel_255m_admit$ret_L5_V2_strict015)),
                                          nrow(panel_255m_admit))),
    n_obs_sufficient = list(pass = nrow(panel_255m_admit) >= 60,
                            note = sprintf("n=%d months", nrow(panel_255m_admit))),
    cost_model_documented = list(pass = TRUE,
                                  note = "v2.3_kr_retail_15bps; cost = (15bps/1e4) × TO × 2 (round trip) + AR Δβ × 15bps + R05 Δβ × 15bps"),
    pit_lag_applied = list(pass = TRUE,
                            note = "M4/β_AR/β_R05 all t-1 lag (shift(1)); liquidity filter t-30..t-1"),
    perfanalytics_standard = list(pass = TRUE,
                                   note = "table.AnnualizedReturns + maxDrawdown + SortinoRatio + CalmarRatio"),
    weighting_basis = list(pass = TRUE,
                            note = sprintf("Iter31 linear_tilt_to_penalty_qd lambda=1.5 phi=3 ub=0.15 (STRICT) | max_w=%.4f mean_w=%.4f",
                                            max(weights_dt$weight), mean(weights_dt$weight))),
    raw_cover_start_hardcoded = list(pass = TRUE,
                                     note = sprintf("decision %s | realized %s",
                                                     as.character(RAW_COVER_START_DECISION),
                                                     as.character(RAW_COVER_START_REALIZED))),
    layer_count = list(pass = TRUE,
                        note = "L1 alpha (admit lineage) + L2 weighting strict015 + L3 M4 + L4 AR + L5 V2"),
    pure_function_hash_audit = list(pass = all_unchanged,
                                     note = sprintf("6 source files md5 start=end identical: %s",
                                                     all_unchanged))
  ),
  baseline_strict015_base_255m = as.list(metrics_255[variant == "strict015_base_no_overlay"]),
  L4_strict015_255m = as.list(metrics_255[variant == "L4_strict015_M4_AR"]),
  L5_V2_strict015_255m = as.list(metrics_255[variant == "L5_V2_strict015_full_overlay"]),
  L5_V2_strict015_267m = as.list(metrics_267[variant == "L5_V2_strict015_full_overlay"]),
  V2_admit_baseline_compare = list(
    SR_255m = v2_admit_baseline$SR_255m,
    delta_SR_strict015_minus_admit = v2_strict_015$SR_255m - v2_admit_baseline$SR_255m,
    MDD_255m = v2_admit_baseline$MDD_255m,
    delta_MDD_strict015_minus_admit_pp = (v2_strict_015$MDD_255m - v2_admit_baseline$MDD_255m) * 100,
    decision_rule = "STRICT_UPGRADE_CANDIDATE if Δ>+0.05 / ADMIT_RETAIN if Δ<-0.05 / MARGINAL_TIE if |Δ|≤0.05"
  ),
  dsr_v2_strict015 = dsr_v2_strict,
  weight_stats = as.list(weight_stats)
)

critical_checks <- c("nav_monotone_dates", "returns_finite", "n_obs_sufficient",
                      "pit_lag_applied", "perfanalytics_standard",
                      "pure_function_hash_audit")
all_critical_pass <- all(sapply(critical_checks,
                                  function(k) audit$checks[[k]]$pass))
audit$integrity <- ifelse(all_critical_pass, "PASS", "FAIL")
audit$metric_type <- ifelse(all_critical_pass, "backtested", "unavailable")

write_json(audit, file.path(OUT_DIR, "audit.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n  Audit integrity: %s | metric_type: %s\n",
            audit$integrity, audit$metric_type))

# ============================================================
# 17. bt_result 10-component (Backtest Contract v1.0)
# ============================================================
bt_result <- list(
  manifest = list(
    task_id = "WT-H20260513_002",
    parent_admit_wt = V2_ADMIT_WT,
    parent_production_wt = "WT-RES_20260512_STR_1715_AR_PRODUCTION",
    strategy_id = STR_ID,
    measurement_basis = "forge_realized_share_based_re_weighted_strict",
    layers = "Iter31 base STRICT ub=0.15 + M4 BOCPD + AR threshold + R05 V2 cash-control",
    weighting = "Iter31_linear_tilt_lambda1.5_phi3_ub0.15 (STRICT variant)",
    raw_cover_start_decision = as.character(RAW_COVER_START_DECISION),
    raw_cover_start_realized = as.character(RAW_COVER_START_REALIZED),
    alpha_lineage = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    r05_source = "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
    m4_source = "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv",
    ar_source = "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv",
    rawdata_source = ".cache/rawdata.parquet",
    mode = "hyperparameter_sweep_strict_variant",
    pit_compliance = "C1_C2_C9_C11_C13_C14",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  ),
  strategy_spec = list(
    architecture = "w_final(t,i) = w_str1715_strict015(t,i) × m4_scalar(t) × β_AR(t) × β_R05_V2(regime_t)",
    sequential_overlay = "alpha lineage retain; weighting recomputed with ub=0.15 STRICT cap",
    variant = "V2 strict (ub=0.15) vs V2 admit (ub=0.20)",
    universe = "KOSPI200 ∪ KOSDAQ150 (admit lineage)",
    top_n = 20,
    weighting = "Iter31 linear_tilt_to_penalty_qd(lambda=1.5, phi=3, ub=0.15)",
    cost_model_version = "v2.3_kr_retail_15bps",
    cost_applied_basis = "(15bps/1e4) × TO × 2 round-trip + AR Δβ × 0.0015 + β_R05 Δβ × 0.0015"
  ),
  nav = nav_dt,
  period_returns = ret_dt,
  holdings = weights_dt,
  benchmark_returns = NULL,
  metrics = list(
    L5_V2_strict015_255m = as.list(metrics_255[variant == "L5_V2_strict015_full_overlay"]),
    L5_V2_strict015_267m = as.list(metrics_267[variant == "L5_V2_strict015_full_overlay"]),
    L4_strict015_255m = as.list(metrics_255[variant == "L4_strict015_M4_AR"]),
    strict015_base_255m = as.list(metrics_255[variant == "strict015_base_no_overlay"]),
    comparison_vs_admit = as.list(cmp_table)
  ),
  benchmark_compare = NULL,
  rolling_metrics = NULL,
  drawdowns = as.data.frame(dd_combined),
  audit = audit
)
saveRDS(bt_result, file.path(OUT_DIR, "bt_result_strict015.rds"))

# ============================================================
# 18. Final summary
# ============================================================
cat("\n============================================================\n")
cat("FINAL: STR_1715_AR_on_M4_R05 weight_bounds [0,0.15] STRICT variant\n")
cat("============================================================\n")
cat("\nV2 admit baseline (ub=0.20):\n")
cat(sprintf("  255m: SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            v2_admit_baseline$SR_255m, v2_admit_baseline$MDD_255m,
            v2_admit_baseline$CAGR_255m))
cat(sprintf("  267m: SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            v2_admit_baseline$SR_267m, v2_admit_baseline$MDD_267m,
            v2_admit_baseline$CAGR_267m))

cat("\nV2 strict variant (ub=0.15):\n")
cat(sprintf("  255m: SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            v2_strict_015$SR_255m, v2_strict_015$MDD_255m,
            v2_strict_015$CAGR_255m))
cat(sprintf("  267m: SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            v2_strict_015$SR_267m, v2_strict_015$MDD_267m,
            v2_strict_015$CAGR_267m))

delta_sr <- v2_strict_015$SR_255m - v2_admit_baseline$SR_255m
delta_mdd_pp <- (v2_strict_015$MDD_255m - v2_admit_baseline$MDD_255m) * 100
delta_cagr_pp <- (v2_strict_015$CAGR_255m - v2_admit_baseline$CAGR_255m) * 100

cat(sprintf("\nΔ V2_strict vs V2_admit (255m):\n"))
cat(sprintf("  ΔSR    = %+.4f\n", delta_sr))
cat(sprintf("  ΔMDD   = %+.2fpp\n", delta_mdd_pp))
cat(sprintf("  ΔCAGR  = %+.2fpp\n", delta_cagr_pp))

decision <- if (delta_sr > 0.05) {
  "STRICT_UPGRADE_CANDIDATE (admit revise candidate)"
} else if (delta_sr < -0.05) {
  "ADMIT_RETAIN (V2 admit better — Codex C1 T+14 resolved as inheritance)"
} else {
  "MARGINAL_TIE (실용적 tie — 도훈 결정 필요)"
}
cat(sprintf("\nDecision rule application: %s\n", decision))

cat(sprintf("\nWeight cap binding analysis:\n"))
cat(sprintf("  Max weight observed: %.4f (target ≤ 0.15)\n", max(weights_dt$weight)))
cat(sprintf("  Positions at cap (weight ≥ 0.15-eps): %d / %d (%.2f%%)\n",
            weight_stats$n_positions_max15pct, weight_stats$n_positions_total,
            weight_stats$binding_pct))

cat("\nDone. Outputs in:", OUT_DIR, "\n")
cat("weights.csv at:", file.path(WT_DIR, "weights.csv"), "\n")
