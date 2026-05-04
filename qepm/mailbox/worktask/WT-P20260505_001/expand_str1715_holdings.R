## ============================================================================
## STR_1715 sleeve expansion — factor_engine equivalent (Codex C3 fix)
## per-date 20 stock-level holdings using alpha_scores.parquet
## Output: str1715_expanded_holdings.csv (one row per (date, ticker))
## ============================================================================

suppressMessages({library(arrow); library(data.table); library(jsonlite)})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260505_001")

# ─── Inputs ───────────────────────────────────────────────────────────────────
alpha_scores <- as.data.table(read_parquet(
  file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
setkey(alpha_scores, Date, Ticker)

weights <- fread(file.path(WT_DIR, "weights.csv"))
weights[, as_of_date := as.Date(as_of_date)]
schedule_dates <- sort(unique(weights$as_of_date))

raw_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
if (file.exists(raw_path)) {
  raw <- as.data.table(read_parquet(raw_path))
  setkey(raw, Date, Ticker)
} else {
  raw <- NULL
}

# Load STR_1715 strategy parameters
LAMBDA <- 1.5
TOPHI  <- 3
MAX_NAMES <- 20
UB_WEIGHT <- 0.20
LIQ_THRESHOLD <- 2e8
COMMISSION_BPS <- 15

# Helper: normalize weights to sum to 1 with bounds
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) return(rep(target_sum / length(w), length(w)))
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) { w <- w * (target_sum / sum(w)); break }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = 0.20) {
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
  blend <- phi / (1 + phi)
  w_final <- (1 - blend) * w_tilt + blend * wp
  w_final <- normalize_long_only(w_final, lb = lb, ub = ub, target_sum = 1)
  names(w_final) <- names(w_tilt)
  w_final
}

# ─── Build per-date stock-level holdings ──────────────────────────────────────
cat(sprintf("[STR1715-expand] %d schedule dates | alpha_scores %d unique dates\n",
            length(schedule_dates), length(unique(alpha_scores$Date))))

holdings_long <- vector("list", length(schedule_dates))
w_prev <- NULL
prev_dt <- NULL

for (i in seq_along(schedule_dates)) {
  dt_i <- schedule_dates[i]
  panel <- alpha_scores[Date == dt_i & !is.na(score_eff)]
  if (nrow(panel) == 0) {
    # Fallback: nearest prior date
    prior_d <- alpha_scores[Date <= dt_i & !is.na(score_eff), max(Date)]
    if (is.finite(prior_d)) panel <- alpha_scores[Date == prior_d & !is.na(score_eff)]
  }
  if (nrow(panel) == 0) next

  setorder(panel, -score_eff)
  N_target <- min(MAX_NAMES, nrow(panel))
  picks <- panel[seq_len(N_target)]
  alpha_t <- setNames(picks$score_eff, picks$Ticker)

  # Liquidity filter (PIT t-30..t-1) — using Vol*Close as proxy for TradingAmt
  if (!is.null(raw)) {
    liq_window <- raw[Date >= (dt_i - 30L) & Date < dt_i,
                       .(AvgTradingAmt = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
    liquid_ts <- liq_window[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
    tickers_liq <- intersect(names(alpha_t), liquid_ts)
    if (length(tickers_liq) >= 5) alpha_t <- alpha_t[tickers_liq]
  }
  if (length(alpha_t) < 5) next

  # Crisis weight shrinkage
  regime_i <- panel[1L, regime_state]
  ub_use <- if (!is.na(regime_i) && regime_i == "CRISIS") 0.10 else UB_WEIGHT

  # Linear Tilt + TOphi penalty
  w_risk <- tryCatch({
    linear_tilt_to_penalty_qd(alpha_t, lambda = LAMBDA, w_prev = w_prev, phi = TOPHI,
                                lb = 0, ub = ub_use)
  }, error = function(e) {
    linear_tilt_qd(alpha_t, lambda = LAMBDA, lb = 0, ub = ub_use)
  })
  names(w_risk) <- names(alpha_t)
  w_risk <- normalize_long_only(w_risk, lb = 0, ub = ub_use, target_sum = 1)

  # Save (within-sleeve weights summing to 1)
  holdings_long[[i]] <- data.table(
    date = dt_i,
    ticker = names(w_risk),
    weight_within_sleeve = as.numeric(w_risk),
    score_eff = alpha_t[names(w_risk)],
    regime = regime_i
  )

  w_prev <- w_risk
  prev_dt <- dt_i
}

holdings_dt <- rbindlist(holdings_long, fill = TRUE)
cat(sprintf("[STR1715-expand] Generated %d (date, ticker) rows | %d unique dates | %d unique tickers\n",
            nrow(holdings_dt), uniqueN(holdings_dt$date), uniqueN(holdings_dt$ticker)))

# Verify time-varying composition (Codex C3): unique stocks per date should differ
sample_dates <- c(as.Date("2010-01-01"), as.Date("2015-01-02"), as.Date("2020-01-02"), as.Date("2026-05-01"))
for (sd in sample_dates) {
  td <- holdings_dt[date == sd | (date == max(holdings_dt$date[holdings_dt$date <= sd]) & !any(holdings_dt$date == sd))]
  if (nrow(td) > 0) {
    cat(sprintf("  Sample date %s: top 5 = %s\n",
                  sd, paste(head(td$ticker, 5), collapse = ", ")))
  }
}

# Save
fwrite(holdings_dt, file.path(WT_DIR, "str1715_expanded_holdings.csv"))
cat(sprintf("[STR1715-expand] Saved: %s/str1715_expanded_holdings.csv\n", WT_DIR))

# Stats: how many distinct tickers across all dates?
all_tickers <- unique(holdings_dt$ticker)
cat(sprintf("[STR1715-expand] Total distinct tickers across 256m walk-forward: %d\n", length(all_tickers)))
