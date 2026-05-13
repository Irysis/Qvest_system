#==============================================================================
# WT-D20260512_003 Optimizer Step 2b — Alpha-rank-only methods (FAST)
#
# 4 alpha-rank methods × 268m walk-forward (no rolling cov reconstruction).
# 이전 Step 2 fail recovery: Σ-based methods 별도 Step 2c로 분리.
#
# Methods:
#   1. Iter31_LinearTilt (STR_1715 admit baseline)
#   2. AlphaSort_EW (top20 equal weight)
#   3. AlphaSoftmax_T05 (softmax temperature 0.5)
#   4. WinsorTilt (alpha winsor ±2σ → linear_tilt λ=1.5)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step2b] Alpha-rank-only 268m Walk-Forward\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
mailbox <- file.path("qepm/mailbox/worktask", WT)
stage <- file.path("stage_artifacts", "WT_D20260512_003")

ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
setkey(asc, Date, Ticker)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

MAX_NAMES <- 20L
MIN_NAMES <- 5L
UB <- 0.20
LB <- 0.0
TARGET_SUM <- 1.0
LIQ_THRESHOLD <- 5e7
COMMISSION_BPS <- 15

sig_dates <- sort(unique(asc$Date))
cat(sprintf("sig_dates: %d (%s ~ %s)\n",
            length(sig_dates),
            as.character(min(sig_dates)),
            as.character(max(sig_dates))))

# ─── Helpers ────────────────────────────────────────────────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0
  w[w < lb] <- lb
  if (sum(w) == 0) {
    w <- rep(target_sum / length(w), length(w))
    return(w)
  }
  w <- w / sum(w) * target_sum
  iter <- 0
  while (any(w > ub + 1e-12) && sum(w) > 0 && iter < 100) {
    excess_idx <- which(w > ub)
    excess <- sum(w[excess_idx]) - length(excess_idx) * ub
    w[excess_idx] <- ub
    free <- setdiff(seq_along(w), excess_idx)
    if (length(free) == 0) break
    if (sum(w[free]) == 0) {
      w[free] <- excess / length(free)
    } else {
      w[free] <- w[free] + excess * (w[free] / sum(w[free]))
    }
    w <- w / sum(w) * target_sum
    iter <- iter + 1
  }
  w
}

linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  names(w) <- names(alpha_t)
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
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

alpha_sort_ew <- function(alpha_t, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  w <- rep(1/N, N)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

alpha_softmax <- function(alpha_t, temperature = 0.5, lb = 0, ub = 0.20) {
  ax <- alpha_t / temperature
  ax <- ax - max(ax)
  w_raw <- exp(ax)
  w <- w_raw / sum(w_raw)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

winsor_tilt <- function(alpha_t, winsor = 2.0, lambda = 1.5, lb = 0, ub = 0.20) {
  mu <- mean(alpha_t, na.rm = TRUE)
  sg <- sd(alpha_t, na.rm = TRUE)
  if (is.na(sg) || sg == 0) return(linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub))
  cap <- winsor * sg
  ax <- pmax(pmin(alpha_t - mu, cap), -cap) + mu
  linear_tilt_qd(setNames(ax, names(alpha_t)), lambda = lambda, lb = lb, ub = ub)
}

# ─── Walk-forward loop (light, no cov rebuild) ──────────────────
run_walk_forward <- function(weight_fn, weight_fn_name = "method") {
  monthly <- vector("list", length(sig_dates) - 1L)
  w_prev <- NULL
  weight_records <- vector("list", length(sig_dates) - 1L)

  for (i in seq_len(length(sig_dates) - 1L)) {
    sig_label <- sig_dates[i]
    next_sig_label <- sig_dates[i + 1L]
    start_d <- raw[Date >= sig_label, Date[1L]]
    if (is.na(start_d)) next
    end_d <- raw[Date >= next_sig_label, Date[1L]]
    if (is.na(end_d)) end_d <- max(raw$Date)

    panel_t <- asc[Date == sig_label]
    if (nrow(panel_t) == 0L) next

    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -z_blend_composite)
    N_target <- min(MAX_NAMES, nrow(panel_t))
    if (N_target < 5L) next
    picks <- panel_t[seq_len(N_target)]
    alpha_t <- picks$z_blend_composite
    names(alpha_t) <- picks$Ticker

    # Liquidity filter (t-30..t-1)
    liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                     .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
    tickers_liq <- intersect(names(alpha_t), liquid_tk)
    if (length(tickers_liq) < 5L) tickers_liq <- names(alpha_t)
    alpha_t_liq <- alpha_t[tickers_liq]

    # Apply method
    ub_use <- if (regime_i == "CRISIS") min(UB, 0.10) else UB
    w_risk <- weight_fn(alpha_t_liq, w_prev = w_prev, ub = ub_use)
    if (is.null(w_risk) || any(is.na(w_risk)) || abs(sum(w_risk) - 1) > 0.01) {
      w_risk <- alpha_sort_ew(alpha_t_liq, lb = LB, ub = ub_use)
    }

    # Period returns
    period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
    stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1),
                               by = Ticker]
    merged <- merge(
      data.table(ticker = names(w_risk), w = as.numeric(w_risk)),
      stock_rets, by.x = "ticker", by.y = "Ticker", all.x = TRUE
    )
    merged[is.na(stock_ret), stock_ret := 0]
    port_ret_gross <- sum(merged$w * merged$stock_ret, na.rm = TRUE)

    # Turnover
    to <- if (is.null(w_prev)) sum(w_risk) else {
      all_tk <- union(names(w_risk), names(w_prev))
      w_new_f <- setNames(rep(0, length(all_tk)), all_tk)
      w_prev_f <- setNames(rep(0, length(all_tk)), all_tk)
      w_new_f[names(w_risk)] <- w_risk
      w_prev_f[names(w_prev)] <- w_prev
      sum(abs(w_new_f - w_prev_f))
    }
    cost <- to * COMMISSION_BPS / 10000
    port_ret_net <- port_ret_gross - cost

    monthly[[i]] <- data.table(
      sig_date = sig_label, start_d = start_d, end_d = end_d,
      port_ret_gross = port_ret_gross, port_ret_net = port_ret_net,
      turnover = to, n_held = length(w_risk),
      regime = regime_i, method = weight_fn_name, cost = cost
    )
    # Save weight records (for HHI + holdings audit)
    weight_records[[i]] <- data.table(
      sig_date = sig_label,
      ticker = names(w_risk),
      weight = as.numeric(w_risk),
      regime = regime_i,
      method = weight_fn_name
    )
    w_prev <- w_risk
  }

  list(
    monthly = rbindlist(monthly, fill = TRUE),
    weights = rbindlist(weight_records, fill = TRUE)
  )
}

# ─── Method wrappers ───────────────────────────────────────────
wf_iter31 <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  linear_tilt_to_penalty_qd(alpha_t_liq, lambda = 1.5, w_prev = w_prev,
                             phi = 3.0, lb = 0, ub = ub)
}
wf_ew <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  alpha_sort_ew(alpha_t_liq, lb = LB, ub = ub)
}
wf_softmax <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  alpha_softmax(alpha_t_liq, temperature = 0.5, lb = LB, ub = ub)
}
wf_winsor <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  winsor_tilt(alpha_t_liq, winsor = 2.0, lambda = 1.5, lb = LB, ub = ub)
}

methods <- list(
  Iter31_LinearTilt = wf_iter31,
  AlphaSort_EW = wf_ew,
  AlphaSoftmax_T05 = wf_softmax,
  WinsorTilt_2sigma = wf_winsor
)

cat(sprintf("\n[Method shopping] %d alpha-rank-only methods\n", length(methods)))

t0 <- Sys.time()
results_raw <- list()
for (m in names(methods)) {
  cat(sprintf("  Running %s ... ", m))
  t1 <- Sys.time()
  out <- run_walk_forward(methods[[m]], weight_fn_name = m)
  elapsed <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  cat(sprintf("%d periods | %.1fs\n", nrow(out$monthly), elapsed))
  results_raw[[m]] <- out
}
total_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\nTotal walk-forward time: %.1f sec\n", total_secs))

saveRDS(results_raw, file.path(stage, "opt_method_shopping_alpha_rank.rds"))
cat(sprintf("Saved: %s\n", file.path(stage, "opt_method_shopping_alpha_rank.rds")))
cat("[OPT-Step2b] DONE\n")
