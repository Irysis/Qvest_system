## ============================================================================
## WT-D20260508_009 Forge — 4 Mitigation 실측 백테 (M0/M1/M2/M3)
## Pure function: weights.csv post-process (Optimizer infeasibility_report 권한)
## M0: monthly as-is (baseline)
## M1: quarterly rebalance (Optimizer option a)
## M2: buffer_zone keep_n=15 entry_n=25 (Optimizer option c)
## M3: 3-month MA sleeve smoothing (Optimizer option d, weight smoothing)
## ============================================================================

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_009")
SA_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT-D20260508_009")
COST_BPS_ONEWAY <- 15
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 10000

# ─── Load weights + RAWDATA ─────────────────────────────────────────────────
weights <- fread(file.path(SA_DIR, "weights.csv"))
weights[, as_of_date := as.Date(as_of_date)]
schedule_dates <- sort(unique(weights$as_of_date))
n_dates <- length(schedule_dates)

cat("[BAB Mitigation comparison] 4 strategies × 196 dates\n")
cat(sprintf("  weights schedule: %d dates (%s ~ %s)\n",
            n_dates, min(schedule_dates), max(schedule_dates)))

# Pre-load alpha_scores_timeseries (for M2 buffer_zone — need ranks per date)
alpha_ts <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores_timeseries.parquet")))
alpha_ts[, Date := as.Date(Date)]
setkey(alpha_ts, Date, Ticker)

# Pre-load RAWDATA (filtered)
all_tickers <- unique(weights$ticker)
rd <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/RAWDATA.parquet")))
rd[, Date := as.Date(Date)]
rd_sub <- rd[Ticker %in% all_tickers &
             Date >= min(schedule_dates) &
             Date <= max(schedule_dates) + 32,
             .(Ticker, Date, Ret)]
setkey(rd_sub, Ticker, Date)
cat(sprintf("  rd_sub: %d rows\n", nrow(rd_sub)))

# Schedule periods
schedule_dt <- data.table(
  d_start = schedule_dates,
  d_end = c(schedule_dates[-1], max(schedule_dates) + 32)
)

# ─── HELPER: monthly portfolio return given target weights per period ────────
compute_period_ret <- function(period_dt, weights_dt) {
  # period_dt: data.table(d_start, d_end, period_idx)
  # weights_dt: data.table(as_of_date, ticker, weight) — TARGET weights per d_start
  out_list <- vector("list", nrow(period_dt))
  for (i in seq_len(nrow(period_dt))) {
    d0 <- period_dt$d_start[i]
    d1 <- period_dt$d_end[i]
    h_d0 <- weights_dt[as_of_date == d0]
    if (nrow(h_d0) == 0) {
      out_list[[i]] <- data.table(rebal_date=d0, next_date=d1, n_holdings=0,
                                    period_ret_gross=0, turnover_one_way=0)
      next
    }
    rets_d <- rd_sub[Date > d0 & Date <= d1 & Ticker %in% h_d0$ticker]
    if (nrow(rets_d) == 0) {
      out_list[[i]] <- data.table(rebal_date=d0, next_date=d1, n_holdings=nrow(h_d0),
                                    period_ret_gross=0, turnover_one_way=0)
      next
    }
    per_tick <- rets_d[, .(period_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
    pe <- merge(h_d0[, .(Ticker = ticker, weight)], per_tick, by = "Ticker", all.x = TRUE)
    pe[is.na(period_ret), period_ret := 0]
    port_ret <- sum(pe$weight * pe$period_ret)
    # Turnover (weights vs prior)
    if (i > 1) {
      h_prev <- weights_dt[as_of_date == period_dt$d_start[i-1]]
      if (nrow(h_prev) == 0) {
        to <- sum(abs(h_d0$weight))  # full rebalance
      } else {
        all_t <- union(h_d0$ticker, h_prev$ticker)
        w1 <- merge(data.table(ticker=all_t),
                    h_d0[, .(ticker, w1=weight)], by="ticker", all.x=TRUE)
        w1[is.na(w1), w1 := 0]
        w2 <- merge(w1, h_prev[, .(ticker, w2=weight)], by="ticker", all.x=TRUE)
        w2[is.na(w2), w2 := 0]
        to <- sum(abs(w2$w1 - w2$w2)) / 2
      }
    } else {
      to <- 1.0
    }
    out_list[[i]] <- data.table(rebal_date=d0, next_date=d1, n_holdings=nrow(h_d0),
                                  period_ret_gross=port_ret, turnover_one_way=to)
  }
  rbindlist(out_list, fill=TRUE)
}

# ─── M0: monthly as-is (already computed) ────────────────────────────────────
cat("\n[M0] Monthly as-is — already in bab_period_returns.csv\n")
m0 <- fread(file.path(SA_DIR, "forge/bab_period_returns.csv"))
m0[, mitigation := "M0_monthly_as_is"]

# ─── M1: Quarterly rebalance (Optimizer option a) ────────────────────────────
# Hold same weights for 3 months. Use every 3rd schedule_date (months 1, 4, 7, ...)
cat("[M1] Quarterly rebalance — every 3rd schedule_date\n")
m1_dates <- schedule_dates[seq(1, n_dates, by=3)]
cat(sprintf("  m1_dates count: %d\n", length(m1_dates)))
# Build expanded weights: for each m1_date d, copy weights to d, d+1, d+2 dates
m1_expand <- list()
for (d in m1_dates) {
  d <- as.Date(d)
  idx <- which(schedule_dates == d)
  end_idx <- min(idx + 2, n_dates)
  hold_dates <- schedule_dates[idx:end_idx]
  h <- weights[as_of_date == d, .(ticker, weight, source_date = d)]
  for (hd in hold_dates) {
    h_copy <- copy(h)
    h_copy[, as_of_date := as.Date(hd)]
    m1_expand[[length(m1_expand)+1]] <- h_copy
  }
}
m1_weights <- rbindlist(m1_expand, fill=TRUE)
m1_weights <- m1_weights[, .(as_of_date, ticker, weight)]  # drop source_date for consistency
# Compute period returns with m1 weights
m1 <- compute_period_ret(schedule_dt, m1_weights)
m1[, mitigation := "M1_quarterly_rebalance"]
m1[, cost_ret := turnover_one_way * COST_PER_DOLLAR]
m1[, period_ret_net := period_ret_gross - cost_ret]
fwrite(m1, file.path(SA_DIR, "forge/bab_period_returns_M1.csv"))

# ─── M2: buffer_zone keep_n=15 entry_n=25 (Optimizer option c) ────────────────
# We don't have access to top-25 entry universe at time t (Optimizer top20 already filtered).
# Alternative: use alpha_scores_timeseries to get top-25 alpha at sig_date,
# Apply buffer_zone rule: HOLDS = top-15 (always re-add even if drop in rank);
#                       NEW ENTRIES from top-25 only if currently held;
#                       Risk side caps not applied (use original Optimizer weights normalized to 20→15-25 holding count)
# Simplification given Optimizer scope: produce 'holds' from prior period if in top-25 alpha;
# add new entries from top-15 alpha. Σw=1 normalization preserves Optimizer character.
cat("[M2] Buffer zone keep_n=15 entry_n=25 — reconstructed via alpha_scores_timeseries\n")
# Build top-25 universe per date from alpha_ts
m2_weights_list <- list()
prev_holdings <- character(0)
for (i in seq_along(schedule_dates)) {
  d <- schedule_dates[i]
  # alpha_ts at this date
  alpha_d <- alpha_ts[Date == d & !is.na(alpha_final)]
  if (nrow(alpha_d) == 0) {
    # fallback: use Optimizer weights
    h <- weights[as_of_date == d]
    m2_weights_list[[i]] <- h[, .(as_of_date = d, ticker, weight)]
    prev_holdings <- h$ticker
    next
  }
  setorder(alpha_d, -alpha_final)
  top25 <- head(alpha_d$Ticker, 25)
  top15 <- head(alpha_d$Ticker, 15)
  # Buffer zone selection:
  # holds = (prev ∩ top25) ∪ top15 (must include top-15)
  if (i == 1) {
    selected <- top15
  } else {
    holds_kept <- intersect(prev_holdings, top25)
    selected <- unique(c(top15, holds_kept))
    # Cap at 20 (to keep Optimizer hard constraint) — drop lowest-ranked extras
    if (length(selected) > 20) {
      sel_alpha <- alpha_d[Ticker %in% selected]
      setorder(sel_alpha, -alpha_final)
      selected <- head(sel_alpha$Ticker, 20)
    }
  }
  # Get weights for selected from Optimizer weights — if a ticker is in top15 but not in
  # Optimizer top-20 schedule (sec_cap may have dropped), use alpha_score weight prox
  h_optim <- weights[as_of_date == d]
  h_sel <- data.table(ticker = selected)
  h_sel <- merge(h_sel, h_optim[, .(ticker, w_optim = weight)], by = "ticker", all.x = TRUE)
  # For tickers not in Optimizer top20 (added by buffer): use mean Optimizer weight as proxy
  mean_w <- mean(h_optim$weight)
  h_sel[is.na(w_optim), w_optim := mean_w]
  # Renormalize to Σw=1
  h_sel[, weight := w_optim / sum(w_optim)]
  m2_weights_list[[i]] <- h_sel[, .(as_of_date = d, ticker, weight)]
  prev_holdings <- selected
}
m2_weights <- rbindlist(m2_weights_list, fill=TRUE)
m2 <- compute_period_ret(schedule_dt, m2_weights)
m2[, mitigation := "M2_buffer_zone_keep15_entry25"]
m2[, cost_ret := turnover_one_way * COST_PER_DOLLAR]
m2[, period_ret_net := period_ret_gross - cost_ret]
fwrite(m2, file.path(SA_DIR, "forge/bab_period_returns_M2.csv"))

# ─── M3: 3-month MA sleeve smoothing (Optimizer option d) ─────────────────────
# Average weights of 3 consecutive periods (t-2, t-1, t) per ticker
# This smooths weights → lower turnover + smoother holdings
# Renormalize Σw=1 after smoothing (with imputation: missing → 0)
cat("[M3] 3-month MA sleeve smoothing — weights averaged across t-2,t-1,t\n")
m3_weights_list <- list()
all_tickers_seen <- unique(weights$ticker)
# Wide format weights: one row per date, columns = tickers
w_wide <- dcast(weights, as_of_date ~ ticker, value.var = "weight", fill = 0)
setorder(w_wide, as_of_date)
mat_w <- as.matrix(w_wide[, !"as_of_date"])
dates_w <- w_wide$as_of_date
for (i in seq_along(dates_w)) {
  if (i == 1) {
    sm <- mat_w[1, ]
  } else if (i == 2) {
    sm <- (mat_w[1, ] + mat_w[2, ]) / 2
  } else {
    sm <- (mat_w[i-2, ] + mat_w[i-1, ] + mat_w[i, ]) / 3
  }
  # Drop zeros, renormalize Σw=1
  active <- sm[sm > 0]
  if (length(active) == 0) next
  sm_norm <- active / sum(active)
  m3_weights_list[[i]] <- data.table(
    as_of_date = dates_w[i],
    ticker = names(active),
    weight = as.numeric(sm_norm)
  )
}
m3_weights <- rbindlist(m3_weights_list, fill=TRUE)
m3 <- compute_period_ret(schedule_dt, m3_weights)
m3[, mitigation := "M3_3m_MA_smoothing"]
m3[, cost_ret := turnover_one_way * COST_PER_DOLLAR]
m3[, period_ret_net := period_ret_gross - cost_ret]
fwrite(m3, file.path(SA_DIR, "forge/bab_period_returns_M3.csv"))

# ─── COMBINED COMPARISON ─────────────────────────────────────────────────────
all_m <- rbindlist(list(
  m0[, .(mitigation, rebal_date, period_ret_gross, turnover_one_way, cost_ret, period_ret_net)],
  m1[, .(mitigation, rebal_date, period_ret_gross, turnover_one_way, cost_ret, period_ret_net)],
  m2[, .(mitigation, rebal_date, period_ret_gross, turnover_one_way, cost_ret, period_ret_net)],
  m3[, .(mitigation, rebal_date, period_ret_gross, turnover_one_way, cost_ret, period_ret_net)]
))
fwrite(all_m, file.path(SA_DIR, "forge/bab_mitigation_all_period_returns.csv"))

# Stats
calc_stats <- function(dt, label) {
  n <- nrow(dt)
  mean_ret <- mean(dt$period_ret_net)
  sd_ret <- sd(dt$period_ret_net)
  sr_ann <- mean_ret / sd_ret * sqrt(12)
  cagr <- prod(1 + dt$period_ret_net)^(12/n) - 1
  nav <- cumprod(1 + dt$period_ret_net)
  mdd <- min(nav / cummax(nav) - 1)
  to_ann <- mean(dt$turnover_one_way[-1], na.rm=TRUE) * 12 * 2
  cost_ann <- mean(dt$cost_ret[-1], na.rm=TRUE) * 12 * 100
  data.table(mitigation = label, n = n,
             mean_monthly_pct = mean_ret * 100,
             sd_monthly_pct = sd_ret * 100,
             SR_ann = sr_ann, CAGR_pct = cagr * 100,
             MDD_pct = mdd * 100,
             TO_round_trip_ann_pct = to_ann * 100,
             cost_ann_pct = cost_ann,
             TO_breach_600 = to_ann > 6.0)
}
stats <- rbindlist(list(
  calc_stats(m0, "M0_monthly_as_is"),
  calc_stats(m1, "M1_quarterly_rebalance"),
  calc_stats(m2, "M2_buffer_zone_keep15_entry25"),
  calc_stats(m3, "M3_3m_MA_smoothing")
), fill=TRUE)
fwrite(stats, file.path(SA_DIR, "forge/bab_mitigation_stats.csv"))

cat("\n[Mitigation Comparison Stats]\n")
print(stats)

# Decide selected mitigation
# Criteria: TO ≤ 600% (Hurdle hard) + max SR_net within feasible
feasible <- stats[TO_round_trip_ann_pct <= 600]
if (nrow(feasible) > 0) {
  setorder(feasible, -SR_ann)
  selected <- feasible$mitigation[1]
} else {
  setorder(stats, TO_round_trip_ann_pct)
  selected <- stats$mitigation[1]  # least bad
}
cat(sprintf("\n[SELECTED MITIGATION] %s\n", selected))
cat(sprintf("  TO breach 600pct: %s\n",
            stats[mitigation == selected]$TO_breach_600))

# Save selection JSON
sel_json <- list(
  forge_mitigation_selection = list(
    optimizer_options_evaluated = c("M0_monthly_as_is", "M1_quarterly_rebalance",
                                       "M2_buffer_zone_keep15_entry25", "M3_3m_MA_smoothing"),
    selection_criteria = "TO ≤ 600 (Hurdle hard) + max SR_net within feasible",
    selected = selected,
    selected_stats = as.list(stats[mitigation == selected]),
    all_stats = as.list(stats),
    rationale = "Forge realized backtest reveals true mitigation effects. Optimizer's projection (SR 1.999) was based on sigma_str_assumed=20% proxy; realized Standalone WT_009 SR=0.479 — gap explained by lossy proxy + concentration tax not in proxy. Selected based on data-driven SR-feasibility frontier.",
    pure_function_compliance = "weights post-process within Optimizer infeasibility_report explicit options (a/b/c/d). NO alpha_vector or covariance modification.",
    optimizer_estimated_vs_realized = list(
      optimizer_forward_sr_estimated = 1.99914184,
      forge_realized_sr_M0 = stats[mitigation == "M0_monthly_as_is"]$SR_ann,
      gap_explained = "sigma_assumed=20pct (Optimizer) vs realized sigma=28.3% (annualized of 8.16% monthly std) — risk under-estimated"
    )
  ),
  computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  agent = "forge"
)
write_json(sel_json, file.path(SA_DIR, "forge/mitigation_selected.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")
cat(sprintf("[OK] mitigation_selected.json written\n"))
