## ============================================================
## STR_1715 Frozen-Alpha OOS Buy-and-Hold (decomposition aid)
## ============================================================
## 목적:
##   - admit M4 SR 1.6399는 alpha frozen 2023-12 + 27M fresh returns hybrid
##   - 본 script은 그 hybrid 측정을 decomposition:
##     (a) Pre-LB frozen walk-forward 240m (alpha schedule 2004-01~2023-12)
##     (b) Post-LB frozen weights buy-and-hold 27M (alpha 2023-12 freeze, weights freeze 후 단순 carry)
##   - fresh-alpha full re-backtest (SR 1.5726)와 같은 period (268m) match
##
## Note: 본 script은 정확한 admit M4 reproduction이 아닌 decomposition aid.
##       admit M4의 정식 SR 1.6399는 governor_admission.json IMMUTABLE.
## ============================================================

cat("=== STR_1715 Frozen-Alpha OOS Buy-and-Hold (decomposition aid) ===\n\n")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-P20260429_002")
ITER5_STAGE <- file.path(BASE_DIR, "stage_artifacts/WT_D20260425_010")
FORGE_DIR <- file.path(WT_DIR, "forge_may2026")
OUT_DIR   <- file.path(FORGE_DIR, "output_full_rebacktest")
dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)

# ─────────────────────────────────────────────────────────
# 1. Load original frozen alpha (Iter5 schedule end 2023-12)
# ─────────────────────────────────────────────────────────
cat("[1] Load original Iter5 frozen alpha\n")
alpha_frozen_path <- file.path(ITER5_STAGE, "alpha_scores.parquet")
alpha_frozen <- as.data.table(read_parquet(alpha_frozen_path))
setkey(alpha_frozen, Date, Ticker)
sig_dates_frozen <- sort(unique(alpha_frozen[!is.na(score_eff), Date]))
cat(sprintf("  frozen sig_dates: %d (%s ~ %s)\n", length(sig_dates_frozen),
            as.character(min(sig_dates_frozen)), as.character(max(sig_dates_frozen))))

# ─────────────────────────────────────────────────────────
# 2. Load RAWDATA
# ─────────────────────────────────────────────────────────
cat("\n[2] Load RAWDATA\n")
raw <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/rawdata.parquet"),
                                  col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]

# ─────────────────────────────────────────────────────────
# 3. Iter31 best params + helper functions (replica)
# ─────────────────────────────────────────────────────────
opt_pkg <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)
LAMBDA <- as.numeric(opt_pkg$best_combo$lambda %||% 1.5)
TOPHI  <- as.numeric(opt_pkg$best_combo$tophi %||% 3)
CASH_NORMAL  <- as.numeric(opt_pkg$best_combo$cash_normal  %||% 0.10)
CASH_CAUTION <- as.numeric(opt_pkg$best_combo$cash_caution %||% 0.20)
CASH_CRISIS  <- as.numeric(opt_pkg$best_combo$cash_crisis  %||% 0.40)
CASH_BULL    <- 0.0

normalize_long_only <- function(w, lb=0, ub=0.20, target_sum=1, max_iter=50) {
  w[!is.finite(w)] <- 0; w[w < lb] <- lb; w[w > ub] <- ub
  s <- sum(w); if (s <= 1e-12) return(rep(target_sum/length(w), length(w)))
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub); w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) { w <- w * (target_sum / sum(w)); break }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}
linear_tilt_qd <- function(alpha_t, lambda=1.0, lb=0, ub=0.20) {
  N <- length(alpha_t); if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method="average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb=lb, ub=ub, target_sum=1)
}
linear_tilt_to_penalty_qd <- function(alpha_t, lambda=1.5, w_prev=NULL, phi=3.0, lb=0, ub=0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda=lambda, lb=lb, ub=ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb=lb, ub=ub, target_sum=1)
}
cash_overlay_iter31 <- function(rg) switch(as.character(rg),
  "BULL"=CASH_BULL, "NORMAL"=CASH_NORMAL,
  "CAUTION"=CASH_CAUTION, "CRISIS"=CASH_CRISIS, CASH_NORMAL)

# ─────────────────────────────────────────────────────────
# 4. Walk-forward (frozen alpha) Pre-LB only
# ─────────────────────────────────────────────────────────
cat("\n[3] Walk-forward Pre-LB (frozen alpha 240 sig_dates 2004-01~2023-12)\n")

LB_START <- as.Date("2024-01-23")
sig_dates <- sig_dates_frozen[sig_dates_frozen < LB_START]
cat(sprintf("  pre-LB sig_dates: %d\n", length(sig_dates)))

LIQ_THRESHOLD <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES <- 20L; MIN_NAMES <- 15L; UB_WEIGHT <- 0.20

monthly_results <- vector("list", length(sig_dates) - 1L)
w_prev_risk_named <- NULL
last_w_named <- NULL
last_sig_date <- NA

for (i in seq_len(length(sig_dates) - 1L)) {
  sig_label <- sig_dates[i]
  next_sig_label <- if (i < length(sig_dates)) sig_dates[i + 1L] else NA
  start_d_set <- raw[Date >= sig_label]$Date
  if (length(start_d_set) == 0L) next
  start_d <- min(start_d_set)
  if (is.na(start_d)) next
  if (!is.na(next_sig_label)) {
    nxt_set <- raw[Date >= next_sig_label]$Date
    end_d <- if (length(nxt_set) == 0L) max(raw$Date) else min(nxt_set)
  } else end_d <- max(raw$Date)

  panel_t <- alpha_frozen[Date == sig_label & !is.na(score_eff)]
  if (nrow(panel_t) == 0L) next

  regime_i <- panel_t$regime_state[1L]
  cash_i   <- cash_overlay_iter31(regime_i)
  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target <- min(MAX_NAMES, N_eligible)
  if (N_target < MIN_NAMES && N_eligible >= MIN_NAMES) N_target <- MIN_NAMES
  if (N_target < 5L) next

  picks <- panel_t[seq_len(N_target)]
  alpha_t <- setNames(picks$score_eff, picks$Ticker)

  liq_data <- raw[Date >= start_d - 30L & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  tickers_liq <- intersect(names(alpha_t), liquid_tickers)
  if (length(tickers_liq) < 5L) tickers_liq <- names(alpha_t)
  alpha_t_liq <- alpha_t[tickers_liq]
  if (length(alpha_t_liq) < 5L) next

  ub_use <- if (regime_i == "CRISIS") min(UB_WEIGHT, 0.10) else UB_WEIGHT

  w_risk <- tryCatch(
    linear_tilt_to_penalty_qd(alpha_t_liq, lambda=LAMBDA, w_prev=w_prev_risk_named,
                               phi=TOPHI, lb=0, ub=ub_use),
    error = function(e) linear_tilt_qd(alpha_t_liq, lambda=LAMBDA, lb=0, ub=ub_use)
  )
  names(w_risk) <- names(alpha_t_liq)
  w_risk <- normalize_long_only(w_risk, lb=0, ub=ub_use, target_sum=1)
  w_risk_scaled <- w_risk * (1 - cash_i)

  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0L) next
  stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  merged_ret <- merge(
    data.table(ticker=names(w_risk_scaled), weight=as.numeric(w_risk_scaled)),
    stock_rets, by.x="ticker", by.y="Ticker", all.x=TRUE
  )
  merged_ret[is.na(stock_ret), stock_ret := 0]
  port_ret_gross <- sum(merged_ret$weight * merged_ret$stock_ret, na.rm=TRUE)

  if (is.null(w_prev_risk_named)) turnover_est <- 1.0
  else {
    all_n <- union(names(w_risk), names(w_prev_risk_named))
    a <- setNames(rep(0, length(all_n)), all_n)
    b <- setNames(rep(0, length(all_n)), all_n)
    a[names(w_risk)] <- w_risk
    b[names(w_prev_risk_named)] <- w_prev_risk_named
    turnover_est <- sum(abs(a - b)) / 2
  }
  cost <- (COMMISSION_BPS / 1e4) * turnover_est * 2
  port_ret_net <- port_ret_gross - cost

  monthly_results[[i]] <- data.table(
    sig_date=sig_label, period_start=start_d, period_end=end_d,
    port_ret=port_ret_net, port_ret_gross=port_ret_gross,
    n_held=nrow(merged_ret), turnover=turnover_est, cost=cost,
    regime=regime_i, cash_pct=cash_i)
  w_prev_risk_named <- setNames(as.numeric(w_risk), names(w_risk))
  last_w_named <- w_risk_scaled
  last_sig_date <- sig_label
}

bt_dt_prelb <- rbindlist(monthly_results, use.names=TRUE, fill=TRUE)
bt_dt_prelb <- bt_dt_prelb[!is.na(port_ret)]
setorder(bt_dt_prelb, period_end)

cat(sprintf("  Pre-LB walk-forward: n=%d (%s ~ %s)\n",
            nrow(bt_dt_prelb),
            as.character(min(bt_dt_prelb$period_end)),
            as.character(max(bt_dt_prelb$period_end))))

# ─────────────────────────────────────────────────────────
# 5. Post-LB frozen weights buy-and-hold
# ─────────────────────────────────────────────────────────
cat("\n[4] Post-LB frozen weights buy-and-hold (alpha 2023-12 freeze, monthly rebalance off)\n")

oos_end <- max(raw$Date)  # 2026-05-01
oos_dates_seq <- seq.Date(as.Date("2024-01-01"), oos_end, by="month")
oos_dates_seq <- as.Date(format(oos_dates_seq, "%Y-%m-01"))
oos_dates_seq <- sort(unique(c(oos_dates_seq, oos_end)))

oos_periods <- list()
prev_d <- last_sig_date
last_tickers <- names(last_w_named)
last_w_vec <- as.numeric(last_w_named)

for (k in seq_along(oos_dates_seq)) {
  d_curr <- oos_dates_seq[k]
  if (d_curr <= prev_d) next
  pdat <- raw[Date > prev_d & Date <= d_curr & Ticker %in% last_tickers,
              .(Date, Ticker, Ret)]
  if (nrow(pdat) == 0) { prev_d <- d_curr; next }
  stock_r <- pdat[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  m_w <- merge(
    data.table(ticker=last_tickers, weight=last_w_vec),
    stock_r, by.x="ticker", by.y="Ticker", all.x=TRUE
  )
  m_w[is.na(stock_ret), stock_ret := 0]
  port_ret_oos <- sum(m_w$weight * m_w$stock_ret, na.rm=TRUE)
  oos_periods[[length(oos_periods)+1]] <-
    data.table(period_end=d_curr, port_ret=port_ret_oos, n_held=nrow(m_w))
  prev_d <- d_curr
}
oos_dt_buyhold <- rbindlist(oos_periods)
setorder(oos_dt_buyhold, period_end)
cat(sprintf("  Post-LB buy-and-hold: n=%d (%s ~ %s)\n",
            nrow(oos_dt_buyhold),
            as.character(min(oos_dt_buyhold$period_end)),
            as.character(max(oos_dt_buyhold$period_end))))

# ─────────────────────────────────────────────────────────
# 6. Combined hybrid (frozen-alpha admit basis approximation)
# ─────────────────────────────────────────────────────────
cat("\n[5] Combined hybrid (frozen pre-LB walk + frozen-weight buy-hold OOS)\n")

hybrid_full <- rbind(
  bt_dt_prelb[, .(Date=period_end, port_ret)],
  oos_dt_buyhold[, .(Date=period_end, port_ret)]
)
setorder(hybrid_full, Date)
hybrid_full[, YM := format(Date, "%Y-%m")]
hybrid_full <- unique(hybrid_full, by="YM")

compute_perf_pa <- function(r) {
  r <- r[!is.na(r)]
  n <- length(r); if (n < 6) return(list(sr=NA, cagr=NA, mdd=NA, vol=NA, n_months=n))
  cagr <- prod(1 + r)^(12/n) - 1
  vol <- sd(r) * sqrt(12)
  sr <- mean(r) / sd(r) * sqrt(12)
  cum <- cumprod(1 + r)
  mdd <- min(cum / cummax(cum) - 1, na.rm=TRUE)
  list(sr=round(sr,4), cagr=round(cagr,4), mdd=round(mdd,4),
       vol=round(vol,4), n_months=n)
}

p_hybrid <- compute_perf_pa(hybrid_full$port_ret)
p_prelb_frozen <- compute_perf_pa(bt_dt_prelb$port_ret)
p_oos_buyhold  <- compute_perf_pa(oos_dt_buyhold$port_ret)

cat(sprintf("  Hybrid full (n=%d): SR=%.4f CAGR=%.4f MDD=%.4f\n",
            p_hybrid$n_months, p_hybrid$sr, p_hybrid$cagr, p_hybrid$mdd))
cat(sprintf("  Pre-LB frozen WF (n=%d): SR=%.4f CAGR=%.4f MDD=%.4f\n",
            p_prelb_frozen$n_months, p_prelb_frozen$sr,
            p_prelb_frozen$cagr, p_prelb_frozen$mdd))
cat(sprintf("  Post-LB frozen buy-hold (n=%d): SR=%.4f CAGR=%.4f MDD=%.4f\n",
            p_oos_buyhold$n_months, p_oos_buyhold$sr,
            p_oos_buyhold$cagr, p_oos_buyhold$mdd))

# ─────────────────────────────────────────────────────────
# 7. Decomposition vs admit M4 SR 1.6399
# ─────────────────────────────────────────────────────────
cat("\n[6] Decomposition vs admit M4 SR 1.6399\n")

SR_ADMIT_M4 <- 1.6399

cat(sprintf("  Method ADMIT_M4         : SR = 1.6399 (governor_admission.json IMMUTABLE, M4 BOCPD schedule)\n"))
cat(sprintf("  Method HYBRID_REPLICA   : SR = %.4f (frozen WF Pre-LB + frozen buy-hold OOS, this script)\n",
            p_hybrid$sr))
cat(sprintf("  Method FRESH_FULL_WF    : SR = 1.5726 (fresh alpha 269 sig walk-forward, 05_str1715_fresh)\n"))

decomposition <- list(
  admit_m4_sr_immutable = SR_ADMIT_M4,
  hybrid_replica_pre_LB_walk_240m = list(
    sr = p_prelb_frozen$sr, cagr = p_prelb_frozen$cagr,
    mdd = p_prelb_frozen$mdd, n = p_prelb_frozen$n_months,
    note = "frozen alpha 2004-01~2023-12 walk-forward, alpha schedule cutoff 2023-12 reproduce"
  ),
  hybrid_replica_post_LB_buy_hold_OOS = list(
    sr = p_oos_buyhold$sr, cagr = p_oos_buyhold$cagr,
    mdd = p_oos_buyhold$mdd, n = p_oos_buyhold$n_months,
    note = "frozen weights at last sig 2023-12 buy-and-hold 2024-01~2026-05 (no rebalance)"
  ),
  hybrid_replica_full_combined = list(
    sr = p_hybrid$sr, cagr = p_hybrid$cagr,
    mdd = p_hybrid$mdd, n = p_hybrid$n_months,
    note = "concat 240m WF + 27m buy-hold = 267m hybrid (period overlap with admit M4 240m + 28 fresh return overlay)"
  ),
  fresh_full_walk_forward_270m = list(
    sr = 1.5726, cagr = 0.4088, mdd = -0.3556, n = 268,
    note = "fresh alpha 269 sig 2004-01~2026-05 walk-forward (05_str1715_fresh_full_rebacktest.R)"
  ),
  comparison = list(
    admit_vs_hybrid_replica = round(SR_ADMIT_M4 - p_hybrid$sr, 4),
    admit_vs_fresh_full = round(SR_ADMIT_M4 - 1.5726, 4),
    hybrid_replica_vs_fresh_full = round(p_hybrid$sr - 1.5726, 4)
  ),
  generated_at = as.character(Sys.time())
)
write(toJSON(decomposition, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT_DIR, "decomposition_admit_vs_fresh.json"))
cat("  decomposition_admit_vs_fresh.json saved\n")

cat("\n══════════════════════════════════════════════════════════\n")
cat("DECOMPOSITION COMPLETE\n")
cat(sprintf("  Δ admit vs hybrid_replica = %+.4f (admit M4 측정 reproduction)\n",
            SR_ADMIT_M4 - p_hybrid$sr))
cat(sprintf("  Δ admit vs fresh_full     = %+.4f (admit hybrid - fresh schedule difference)\n",
            SR_ADMIT_M4 - 1.5726))
cat(sprintf("  Δ hybrid vs fresh         = %+.4f (frozen vs fresh alpha contribution)\n",
            p_hybrid$sr - 1.5726))
cat("══════════════════════════════════════════════════════════\n")
