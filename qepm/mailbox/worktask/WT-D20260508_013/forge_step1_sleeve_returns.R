#==============================================================================
# WT-D20260508_013 Forge Step 1 — Sleeve returns walk-forward 256m
#
# Pure Function v6.1 R12: alpha_scores.parquet immutable.
# Walk-forward: at each sig_date t, select top20 by c4_rcomp (Optimizer-selected
# alpha method), AlphaWeighted positive scores normalized to Σw=1, hold for
# 1m, realize ret_net = ret_gross - 2*to*0.0015 (15bps round-trip cost).
#
# Inputs:
#   stage_artifacts/WT-D20260508_013/alpha_scores.parquet
#     (Date, Ticker, c4_rcomp, fwd_ret_1m, adv_20d_won, ...)
#
# Method:
#   - Optimizer selected: AlphaWeighted_top20 (cost-adj SR 0.655)
#   - Long-only top20 long bound [0, 0.20]
#   - Liquidity filter: adv_20d_won >= 2e8 (LIQ_THRESHOLD)
#   - At each sig_date, weights w_i = max(0, c4_rcomp_i) / sum if positive
#     Note: top20 by c4_rcomp; if mix of positive+negative top20, use
#     AlphaWeighted_top20 (positive-shift then normalize).
#   - Cost: 15bps one-way → 30bps round-trip if turnover happens
#
# Output:
#   stage_artifacts/WT-D20260508_013/forge/sleeve_returns_256m.csv
#     (Date, ret_gross, turnover, ret_net, n_holdings, total_alpha_weight)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_013"
SA_DIR <- file.path("stage_artifacts", WT_ID)
FORGE_DIR <- file.path(SA_DIR, "forge")

ALPHA_PARQUET <- file.path(SA_DIR, "alpha_scores.parquet")
LIQ_THRESHOLD <- 2e8     # 2억원 KRW
COST_BPS_ONE_WAY <- 0.0015
TOP_K <- 20

cat("================================================================\n")
cat("[FORGE STEP 1] WT-D20260508_013 sleeve walk-forward 256m\n")
cat("================================================================\n")

dt <- as.data.table(read_parquet(ALPHA_PARQUET))
cat("Loaded alpha_scores: rows=", nrow(dt), " cols=", ncol(dt), "\n")
cat("Sig dates:", uniqueN(dt$Date), " range=",
    as.character(min(dt$Date)), "~", as.character(max(dt$Date)), "\n")

# Use c4_rcomp (Optimizer-selected alpha method)
# At sig_date 2026-05-08 fwd_ret is NA — drop that row from backtest
# (still keep for portfolio construction in deployment, but exclude from realized)
sig_dates <- sort(unique(dt$Date))
n_sig <- length(sig_dates)
cat("Total sig_dates:", n_sig, "\n")

# Verify last sig_date has NA fwd_ret (portfolio construction snapshot)
last_d <- max(sig_dates)
n_na_last <- sum(is.na(dt[Date == last_d]$fwd_ret_1m))
cat("Last sig_date", as.character(last_d), "NA fwd_ret count:", n_na_last,
    "(", round(100*n_na_last/nrow(dt[Date == last_d]),1), "%)\n")

# Realized (return-realizable) sig_dates: exclude any with all NA fwd_ret
realized_sig_dates <- sig_dates[
  sapply(sig_dates, function(d) sum(!is.na(dt[Date == d]$fwd_ret_1m)) > 0)
]
cat("Realized sig_dates (with non-NA fwd_ret_1m):", length(realized_sig_dates), "\n")

# Walk-forward: build top20 portfolio per sig_date + realize 1m fwd_ret
# Methods:
#   1) Top20 selection by c4_rcomp DESC after liquidity filter
#   2) AlphaWeighted: w_i = pos(c4_rcomp_i) / sum(pos(c4_rcomp))
#      Cap each weight at 0.20 (request hard constraint), Σw = 1
#   3) Realize 1m return = sum(w_i * fwd_ret_1m_i)
#   4) Turnover = 0.5 * sum(|w_t - w_{t-1}|)
#   5) Cost = turnover * 2 * 15bps (round-trip)
#   6) ret_net = ret_gross - cost

prior_w <- list()  # ticker -> weight
out <- vector("list", length(realized_sig_dates))

for (i in seq_along(realized_sig_dates)) {
  d <- realized_sig_dates[i]
  d_dt <- dt[Date == d & !is.na(c4_rcomp) & !is.na(fwd_ret_1m) &
             !is.na(adv_20d_won) & adv_20d_won >= LIQ_THRESHOLD]

  if (nrow(d_dt) < TOP_K) {
    # Fallback: relax liquidity if < 20 names available
    d_dt <- dt[Date == d & !is.na(c4_rcomp) & !is.na(fwd_ret_1m)]
  }

  setorder(d_dt, -c4_rcomp)
  top <- d_dt[1:min(TOP_K, nrow(d_dt))]

  # AlphaWeighted: positive-shift c4_rcomp, normalize, cap at 0.20
  shift_a <- top$c4_rcomp - min(top$c4_rcomp) + 1e-6  # ensure all positive
  raw_w <- shift_a / sum(shift_a)
  # Cap at 0.20 and re-normalize
  capped <- pmin(raw_w, 0.20)
  if (sum(capped) > 0) {
    capped <- capped / sum(capped)
  }
  # Iterate to enforce cap (should converge in 2-3 iters)
  for (iter_cap in 1:5) {
    if (max(capped) <= 0.2001) break
    capped <- pmin(capped, 0.20)
    capped <- capped / sum(capped)
  }
  top[, weight := capped]

  # Realize gross return
  ret_gross <- sum(top$weight * top$fwd_ret_1m)

  # Turnover vs prior
  cur_w <- setNames(top$weight, top$Ticker)
  all_tk <- union(names(prior_w), names(cur_w))
  prior_full <- numeric(length(all_tk)); names(prior_full) <- all_tk
  cur_full   <- numeric(length(all_tk)); names(cur_full) <- all_tk
  prior_idx <- match(names(prior_w), all_tk)
  cur_idx <- match(names(cur_w), all_tk)
  if (length(prior_w) > 0) prior_full[prior_idx] <- unlist(prior_w)
  cur_full[cur_idx] <- as.numeric(cur_w)
  to <- 0.5 * sum(abs(cur_full - prior_full))

  # Net return
  cost <- to * 2 * COST_BPS_ONE_WAY  # round-trip
  ret_net <- ret_gross - cost

  out[[i]] <- data.table(
    Date = d,
    n_holdings = nrow(top),
    ret_gross = ret_gross,
    turnover = to,
    cost = cost,
    ret_net = ret_net,
    sum_w = sum(top$weight),
    max_w = max(top$weight),
    min_w = min(top$weight)
  )

  prior_w <- as.list(cur_w)
}

sleeve_ret <- rbindlist(out)
cat("\nSleeve walk-forward summary:\n")
cat("  N periods:", nrow(sleeve_ret), "\n")
cat("  Date range:", as.character(min(sleeve_ret$Date)), "~",
    as.character(max(sleeve_ret$Date)), "\n")
cat("  ret_net mean (per month):", round(mean(sleeve_ret$ret_net), 6), "\n")
cat("  ret_net sd (per month):", round(sd(sleeve_ret$ret_net), 6), "\n")
cat("  Annualized SR (raw):",
    round(mean(sleeve_ret$ret_net) / sd(sleeve_ret$ret_net) * sqrt(12), 4), "\n")
cat("  Avg turnover:", round(mean(sleeve_ret$turnover), 4), "\n")
cat("  Avg cost (per period):", round(mean(sleeve_ret$cost), 6), "\n")
cat("  Holdings range:", min(sleeve_ret$n_holdings), "~", max(sleeve_ret$n_holdings), "\n")

# Save
fwrite(sleeve_ret, file.path(FORGE_DIR, "sleeve_returns_256m.csv"))
cat("\n[saved]", file.path(FORGE_DIR, "sleeve_returns_256m.csv"), "\n")

# Sanity test: compute basic SR/MDD via PerformanceAnalytics
suppressPackageStartupMessages(library(PerformanceAnalytics))
library(xts)
sleeve_xts <- xts(sleeve_ret$ret_net, order.by = sleeve_ret$Date)
sr_perfa <- as.numeric(SharpeRatio.annualized(sleeve_xts, scale = 12))
cagr <- as.numeric(Return.annualized(sleeve_xts, scale = 12))
mdd  <- as.numeric(maxDrawdown(sleeve_xts))
cat("\nPerformanceAnalytics standalone sleeve metrics (256m):\n")
cat("  SR_a:", round(sr_perfa, 4), "\n")
cat("  CAGR:", round(cagr, 4), "\n")
cat("  MDD:", round(mdd, 4), "\n")

# Recent 60m subset
sleeve60 <- sleeve_ret[Date >= as.Date("2021-05-01")]
if (nrow(sleeve60) >= 30) {
  sleeve60_xts <- xts(sleeve60$ret_net, order.by = sleeve60$Date)
  cat("\nRecent 60m subset (n=", nrow(sleeve60), "):\n")
  cat("  SR_a:", round(as.numeric(SharpeRatio.annualized(sleeve60_xts, scale=12)), 4), "\n")
  cat("  CAGR:", round(as.numeric(Return.annualized(sleeve60_xts, scale=12)), 4), "\n")
  cat("  MDD:", round(as.numeric(maxDrawdown(sleeve60_xts)), 4), "\n")
}

cat("\n[FORGE STEP 1] DONE\n")
