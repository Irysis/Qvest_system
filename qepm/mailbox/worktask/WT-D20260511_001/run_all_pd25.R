#==============================================================================
# WT-D20260511_001 PD25 — 3 weighting paths backtest comparison
#
# Mission (도훈 mandate 2026-05-12):
#   "동일가중 / B / C, 프로즌없이 전기간(분석가능한 기간 중 제일 빠른기간,
#    1991 ~ 2026.05) 백테스트해서 성과 비교"
#
# 3 Weighting paths (within KR-equity composite top20 sleeve, sleeve weight 0.55):
#   Path A — EW          : w_i_sleeve = 1/20  → portfolio = 2.75% per ticker
#   Path B — Z-linear    : w_i_sleeve = max(z_i,0) / Σ max(z_j,0)
#   Path C — Z-softmax   : w_i_sleeve = softmax(z_i / τ),  τ = median(|z_top20|)
#                          (autonomous τ selection — balance EW vs winner-take-all)
#
# Coverage decision (Forge autonomous):
#   - 도훈 mandate: 1991~2026.05 max coverage 시도
#   - 가용 constraint:
#     - STR_1715 Iter5 alpha     : 2004-01 ~ 2026-04 (268m, score_eff + Ret_1m)
#     - NEW PD24 ext alpha       : 1999-01 ~ 2026-04 (314m back-extended)
#     - sleeve_returns_master    : 2005-02 ~ 2026-04 (255m) ← HARDEST CONSTRAINT
#   - Conclusion: max realistic coverage = 2005-02 ~ 2026-04 (255m) — match PD20-B Path 2 baseline
#   - Active composite period   : 2011-01 ~ 2026-04 (184m) where z_NEW non-trivial
#   - Pre-2011 (2005-02~2010-12, 71m): redistribute to S4 v2 baseline (50/25/20/5)
#     where z_NEW=0 makes Path A=B=C collapse → 3 paths only differ post-2011.
#
# Lockbox 폐기 (forge stage, .claude/rules/lockbox-scope.md mandate 2026-05-09):
#   - Latest sig_dates 사용 (2026-04 inclusive)
#   - No SIGNAL_CUTOFF freeze
#
# Sleeve outer weights (inherited PD20-B Path 2):
#   COMPOSITE_KR_equity = 0.550
#   TSMOM               = 0.225
#   KR_10y              = 0.180
#   Cash                = 0.045
#   Σw = 1.000
#
# Pure function:
#   - alpha/risk/optimizer READ-ONLY (md5sum start/end audit)
#   - composite weights inherited from PD20-B (NOT re-derived)
#   - Only within-sleeve weighting differs across 3 paths
#
# Constraints:
#   - PerformanceAnalytics standard functions (geometric=TRUE, scale=12)
#   - 15bps round-trip turnover cost (per ticker weight delta, not just name swap)
#   - Σw = 1.000 strict
#   - Long-only (Path B max(z,0); Path C softmax positivity guaranteed)
#   - Single asset portfolio cap [0, 0.20] strict (Production Constraints)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR   <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR   <- "stage_artifacts/WT_D20260511_001"
ITER5    <- "stage_artifacts/WT_D20260425_010"
OUT_DIR  <- file.path(WT_DIR, "backtest_result_pd25")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== PD25 Forge — 3 weighting paths backtest ===\n")
cat(sprintf("Started: %s\n\n", format(Sys.time())))

#==============================================================================
# 1. 3-package md5sum START — Pure function audit
#==============================================================================
md5_start <- list(
  alpha = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk  = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt   = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("3-package md5sum START:\n")
cat("  alpha:", md5_start$alpha, "\n")
cat("  risk: ", md5_start$risk, "\n")
cat("  opt:  ", md5_start$opt, "\n\n")

#==============================================================================
# 2. Load source data
#==============================================================================
cat("=== Step 2: Load source data ===\n")

# Sleeve master (TSMOM/KR_10y/Cash/AR_on_M4 returns, 2005-02 ~ 2026-04)
sm <- fread("qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv")
sm[, Date := as.Date(date)]
setorder(sm, Date)
cat(sprintf("  sleeve_returns_master: %d rows, %s ~ %s\n",
            nrow(sm), as.character(min(sm$Date)), as.character(max(sm$Date))))

# Iter5 1715 alpha (score_eff + Ret_1m, 2004-01 ~ 2026-04, 268m × 846 tickers)
a1715 <- as.data.table(read_parquet(file.path(ITER5, "alpha_scores.parquet")))
a1715 <- a1715[, .(sig_date = Date, Ticker, score_eff, Ret_1m)]
cat(sprintf("  Iter5 1715 alpha: %d rows, %d sig_dates, %d tickers\n",
            nrow(a1715), length(unique(a1715$sig_date)), length(unique(a1715$Ticker))))

# NEW Vol/Skew alpha (PD18-vintage baseline, 2011-01 ~ 2026-04, 184m × 770 tickers)
# Use original (not PD24-extended) to match PD20-B baseline exactly
aNEW <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
setnames(aNEW, "alpha", "alpha_NEW")
aNEW <- aNEW[, .(sig_date, Ticker, alpha_NEW)]
cat(sprintf("  NEW Vol/Skew alpha: %d rows, %d sig_dates, %d tickers\n",
            nrow(aNEW), length(unique(aNEW$sig_date)), length(unique(aNEW$Ticker))))

#==============================================================================
# 3. Compute composite top20 per sig_date (within-sleeve selection)
#==============================================================================
cat("\n=== Step 3: Composite top20 selection (z-composite per sig_date) ===\n")

# z_1715 (cross-sectional z per sig_date)
a1715[, z_1715 := (score_eff - mean(score_eff, na.rm = TRUE)) /
        sd(score_eff, na.rm = TRUE), by = sig_date]
a1715[is.na(z_1715) | is.infinite(z_1715), z_1715 := 0]

# z_NEW (cross-sectional z per sig_date)
aNEW[, z_NEW := (alpha_NEW - mean(alpha_NEW, na.rm = TRUE)) /
       sd(alpha_NEW, na.rm = TRUE), by = sig_date]
aNEW[is.na(z_NEW) | is.infinite(z_NEW), z_NEW := 0]

# Merge KR equity universe (outer join — z_NEW may be NA pre-2011)
z_kr <- merge(a1715[, .(sig_date, Ticker, z_1715, Ret_1m)],
              aNEW[, .(sig_date, Ticker, z_NEW)],
              by = c("sig_date", "Ticker"), all.x = TRUE)
z_kr[is.na(z_NEW), z_NEW := 0]
z_kr[is.na(z_1715), z_1715 := 0]

# Composite z (PD20-B Path 2 weights retained: 0.818 * z_1715 + 0.182 * z_NEW)
W_1715 <- 0.818
W_NEW  <- 0.182
z_kr[, composite_z := W_1715 * z_1715 + W_NEW * z_NEW]

# Active composite period: only 2011-01 ~ 2026-04 (184m) where z_NEW present
active_sig_dates <- sort(unique(aNEW$sig_date))
cat(sprintf("  Active composite period: %d sig_dates, %s ~ %s\n",
            length(active_sig_dates),
            as.character(min(active_sig_dates)),
            as.character(max(active_sig_dates))))

# Top20 selection per sig_date (active composite period)
top20_list <- list()
for (sd in active_sig_dates) {
  sd_date <- as.Date(sd, origin = "1970-01-01")
  cand <- z_kr[sig_date == sd_date]
  setorder(cand, -composite_z)
  top20 <- head(cand, 20)
  top20[, sig_date := sd_date]
  top20[, rank := 1:.N]
  top20_list[[length(top20_list) + 1]] <- top20[, .(sig_date, Ticker, rank,
                                                     composite_z, z_1715, z_NEW, Ret_1m)]
}
holdings_dt <- rbindlist(top20_list)

cat(sprintf("  Total top20 holdings rows: %d\n", nrow(holdings_dt)))
cat(sprintf("  Sig_dates: %d, tickers per sig_date: %d (min=%d, max=%d)\n",
            length(unique(holdings_dt$sig_date)),
            as.integer(median(holdings_dt[, .N, by = sig_date]$N)),
            min(holdings_dt[, .N, by = sig_date]$N),
            max(holdings_dt[, .N, by = sig_date]$N)))
cat(sprintf("  Ret_1m present: %d / %d (%.1f%%)\n",
            sum(!is.na(holdings_dt$Ret_1m)), nrow(holdings_dt),
            100 * mean(!is.na(holdings_dt$Ret_1m))))

#==============================================================================
# 4. Within-sleeve weighting — 3 paths
#==============================================================================
cat("\n=== Step 4: Compute 3 weighting paths within KR-equity sleeve ===\n")

SLEEVE_W <- 0.550   # KR equity composite sleeve outer weight
N_STOCKS <- 20
W_CAP    <- 0.20    # Production Constraint: single asset portfolio cap

# Path A — EW within sleeve = 1/20 = 5% per ticker; portfolio = 2.75%
holdings_dt[, w_sleeve_A := 1 / N_STOCKS]
holdings_dt[, w_portfolio_A := w_sleeve_A * SLEEVE_W]

# Path B — Z-linear within sleeve
#   w_sleeve_i = max(composite_z_i, 0) / Σ max(composite_z_j, 0)
#   If all composite_z <= 0: fall back to EW (rare in top20 since they're chosen by max z)
compute_path_B <- function(z) {
  z_pos <- pmax(z, 0)
  s <- sum(z_pos, na.rm = TRUE)
  if (s <= 1e-9) {
    return(rep(1 / length(z), length(z)))   # EW fallback
  }
  z_pos / s
}
holdings_dt[, w_sleeve_B := compute_path_B(composite_z), by = sig_date]
holdings_dt[, w_portfolio_B := w_sleeve_B * SLEEVE_W]

# Path C — Z-softmax within sleeve
#   τ chosen autonomously per sig_date: τ = median(|composite_z_in_top20|)
#   This gives:
#     - low τ when concentrated z signals → more tilt toward winners
#     - high τ when flat z signals → more EW-like
#   softmax(z_i / τ) = exp(z_i/τ) / Σ exp(z_j/τ)
#   For numerical stability: subtract max before exp.
compute_path_C <- function(z) {
  tau <- median(abs(z), na.rm = TRUE)
  if (is.na(tau) || tau <= 1e-9) tau <- 1.0   # degeneracy guard
  z_scaled <- z / tau
  z_max <- max(z_scaled, na.rm = TRUE)
  e <- exp(z_scaled - z_max)
  e / sum(e, na.rm = TRUE)
}
holdings_dt[, w_sleeve_C := compute_path_C(composite_z), by = sig_date]
holdings_dt[, w_portfolio_C := w_sleeve_C * SLEEVE_W]

# Tau diagnostic (Path C)
tau_diag <- holdings_dt[, .(tau = median(abs(composite_z), na.rm = TRUE),
                             max_z = max(composite_z), min_z = min(composite_z)),
                        by = sig_date]
cat(sprintf("  Path C tau: median=%.4f, range=[%.4f, %.4f]\n",
            median(tau_diag$tau), min(tau_diag$tau), max(tau_diag$tau)))

# Single asset cap [0, 0.20] enforce — Paths B & C
# Note: portfolio-level cap. Path A 2.75% is already << 0.20 (no cap needed).
# For Path B/C, check per sig_date if any w_portfolio > 0.20; if so, cap & redistribute.
enforce_cap <- function(w_sleeve, cap_portfolio, sleeve_w) {
  # Convert portfolio cap to sleeve cap: cap_sleeve = cap_portfolio / sleeve_w
  cap_sleeve <- cap_portfolio / sleeve_w
  # Iterative cap + redistribute
  for (iter in 1:50) {
    over <- w_sleeve > cap_sleeve
    if (!any(over)) break
    excess <- sum(w_sleeve[over] - cap_sleeve)
    w_sleeve[over] <- cap_sleeve
    # Redistribute excess proportionally to non-capped stocks
    under <- !over
    if (sum(w_sleeve[under]) > 1e-9) {
      w_sleeve[under] <- w_sleeve[under] + excess * w_sleeve[under] / sum(w_sleeve[under])
    } else {
      # All capped — should not happen with 20 stocks and cap 0.3636
      break
    }
  }
  w_sleeve
}

# Apply cap to Paths B & C
n_capped_B <- 0L; n_capped_C <- 0L
holdings_dt[, w_sleeve_B_capped := {
  w <- enforce_cap(w_sleeve_B, W_CAP, SLEEVE_W)
  if (any(w_sleeve_B > W_CAP / SLEEVE_W)) n_capped_B <<- n_capped_B + 1L
  w
}, by = sig_date]
holdings_dt[, w_portfolio_B := w_sleeve_B_capped * SLEEVE_W]

holdings_dt[, w_sleeve_C_capped := {
  w <- enforce_cap(w_sleeve_C, W_CAP, SLEEVE_W)
  if (any(w_sleeve_C > W_CAP / SLEEVE_W)) n_capped_C <<- n_capped_C + 1L
  w
}, by = sig_date]
holdings_dt[, w_portfolio_C := w_sleeve_C_capped * SLEEVE_W]

cat(sprintf("  Path B cap activations: %d / %d sig_dates (%.1f%%)\n",
            n_capped_B, length(active_sig_dates), 100 * n_capped_B / length(active_sig_dates)))
cat(sprintf("  Path C cap activations: %d / %d sig_dates (%.1f%%)\n",
            n_capped_C, length(active_sig_dates), 100 * n_capped_C / length(active_sig_dates)))

# Sanity: Σw_sleeve = 1.0 per sig_date for each path
sum_check <- holdings_dt[, .(sum_A = sum(w_sleeve_A),
                              sum_B = sum(w_sleeve_B_capped),
                              sum_C = sum(w_sleeve_C_capped)), by = sig_date]
cat(sprintf("  Σw_sleeve check: A=%.6f (max dev %.2e), B=%.6f (max dev %.2e), C=%.6f (max dev %.2e)\n",
            mean(sum_check$sum_A), max(abs(sum_check$sum_A - 1)),
            mean(sum_check$sum_B), max(abs(sum_check$sum_B - 1)),
            mean(sum_check$sum_C), max(abs(sum_check$sum_C - 1))))

# Concentration diagnostic (Top 5 weight)
holdings_dt[, rank_in_sd := frank(-composite_z), by = sig_date]
top5_concentration <- holdings_dt[rank_in_sd <= 5,
                                   .(top5_A = sum(w_sleeve_A),
                                     top5_B = sum(w_sleeve_B_capped),
                                     top5_C = sum(w_sleeve_C_capped)), by = sig_date]
cat(sprintf("  Top5 concentration (sleeve weight): A=%.3f, B=%.3f (%.3f to %.3f), C=%.3f (%.3f to %.3f)\n",
            mean(top5_concentration$top5_A),
            mean(top5_concentration$top5_B), min(top5_concentration$top5_B), max(top5_concentration$top5_B),
            mean(top5_concentration$top5_C), min(top5_concentration$top5_C), max(top5_concentration$top5_C)))

#==============================================================================
# 5. Compute period returns per path
#==============================================================================
cat("\n=== Step 5: Period returns per path (sleeve-level) ===\n")

# Holding period return = Σ w_sleeve_i × Ret_1m_i (per sig_date)
holdings_dt[, ret_contrib_A := w_sleeve_A * Ret_1m]
holdings_dt[, ret_contrib_B := w_sleeve_B_capped * Ret_1m]
holdings_dt[, ret_contrib_C := w_sleeve_C_capped * Ret_1m]

period_ret_sleeve <- holdings_dt[, .(
  Composite_A = sum(ret_contrib_A, na.rm = TRUE),
  Composite_B = sum(ret_contrib_B, na.rm = TRUE),
  Composite_C = sum(ret_contrib_C, na.rm = TRUE),
  n_holdings = .N,
  n_with_ret = sum(!is.na(Ret_1m))
), by = sig_date]
setorder(period_ret_sleeve, sig_date)

cat(sprintf("  Sleeve-level returns (gross, no cost):\n"))
cat(sprintf("    Path A (EW)       : mean=%.4f, sd=%.4f\n",
            mean(period_ret_sleeve$Composite_A), sd(period_ret_sleeve$Composite_A)))
cat(sprintf("    Path B (Z-linear) : mean=%.4f, sd=%.4f\n",
            mean(period_ret_sleeve$Composite_B), sd(period_ret_sleeve$Composite_B)))
cat(sprintf("    Path C (Z-softmax): mean=%.4f, sd=%.4f\n",
            mean(period_ret_sleeve$Composite_C), sd(period_ret_sleeve$Composite_C)))

#==============================================================================
# 6. Turnover computation (ticker-weight delta, not just name swap)
#==============================================================================
cat("\n=== Step 6: Per-ticker turnover (weight delta sum / 2) ===\n")

# For each path, monthly one-way turnover = Σ |w_i,t - w_i,t-1| / 2 (over all tickers)
# Pre-rebalance weights (after market drift t-1 → t): w_i_drift = w_i,t-1 × (1+r_i,t-1) / Σ (...)
# Approximation: use post-rebalance weights for delta calc (simpler, slightly overstates)
# More precise: compute drift-adjusted weights; we use post-rebal for parity with prior work.

compute_turnover <- function(holdings, weight_col) {
  ud <- sort(unique(holdings$sig_date))
  to_seq <- numeric(length(ud))
  to_seq[1] <- 1.0   # initial entry
  for (i in 2:length(ud)) {
    curr <- holdings[sig_date == ud[i], .(Ticker, w = get(weight_col))]
    prev <- holdings[sig_date == ud[i - 1], .(Ticker, w_prev = get(weight_col))]
    merged <- merge(curr, prev, by = "Ticker", all = TRUE)
    merged[is.na(w), w := 0]
    merged[is.na(w_prev), w_prev := 0]
    to_seq[i] <- sum(abs(merged$w - merged$w_prev)) / 2
  }
  to_seq
}

to_A <- compute_turnover(holdings_dt, "w_sleeve_A")
to_B <- compute_turnover(holdings_dt, "w_sleeve_B_capped")
to_C <- compute_turnover(holdings_dt, "w_sleeve_C_capped")

cat(sprintf("  Mean one-way turnover (sleeve-level):\n"))
cat(sprintf("    Path A: %.4f (annual %.0f%%)\n", mean(to_A), mean(to_A) * 12 * 100))
cat(sprintf("    Path B: %.4f (annual %.0f%%)\n", mean(to_B), mean(to_B) * 12 * 100))
cat(sprintf("    Path C: %.4f (annual %.0f%%)\n", mean(to_C), mean(to_C) * 12 * 100))

ud_sorted <- sort(unique(holdings_dt$sig_date))
turnover_dt <- data.table(
  sig_date = ud_sorted,
  to_A = to_A, to_B = to_B, to_C = to_C
)

#==============================================================================
# 7. Apply 15bps cost embed (round-trip, ticker-level delta)
#==============================================================================
cat("\n=== Step 7: Cost embed (15bps round-trip, sleeve-level then portfolio) ===\n")

COST_BPS <- 0.0015   # 15bps one-way
period_ret_sleeve <- merge(period_ret_sleeve, turnover_dt, by = "sig_date")

# Cost drag at SLEEVE level: 2 × turnover_oneway × 15bps
period_ret_sleeve[, cost_A := 2 * to_A * COST_BPS]
period_ret_sleeve[, cost_B := 2 * to_B * COST_BPS]
period_ret_sleeve[, cost_C := 2 * to_C * COST_BPS]

period_ret_sleeve[, Composite_A_net := Composite_A - cost_A]
period_ret_sleeve[, Composite_B_net := Composite_B - cost_B]
period_ret_sleeve[, Composite_C_net := Composite_C - cost_C]

cat(sprintf("  Sleeve cost drag annual bps:\n"))
cat(sprintf("    Path A: %.2f bps/yr\n", mean(period_ret_sleeve$cost_A) * 12 * 1e4))
cat(sprintf("    Path B: %.2f bps/yr\n", mean(period_ret_sleeve$cost_B) * 12 * 1e4))
cat(sprintf("    Path C: %.2f bps/yr\n", mean(period_ret_sleeve$cost_C) * 12 * 1e4))

#==============================================================================
# 8. Composite portfolio returns (4-sleeve: KR equity 0.55 + TSMOM/KR_10y/Cash)
#==============================================================================
cat("\n=== Step 8: 4-sleeve portfolio returns per path ===\n")

W_TSMOM <- 0.225
W_KR    <- 0.180
W_CASH  <- 0.045

# Merge with sm by ym
period_ret_sleeve[, ym := format(sig_date, "%Y-%m")]
sm[, ym := format(Date, "%Y-%m")]

# Pre-2011: composite absent → use S4 v2 baseline (50/25/20/5) for ALL 3 paths
# Post-2011 (in period_ret_sleeve): use respective Composite_A/B/C_net
# Note: Composite_*_net is sleeve-level net return; multiply by 0.55 for portfolio contribution
# Other sleeves are unchanged (TSMOM/KR_10y/Cash baseline returns).

# Join full sm with sleeve returns
portfolio_dt <- merge(sm, period_ret_sleeve[, .(ym, Composite_A, Composite_B, Composite_C,
                                                 Composite_A_net, Composite_B_net, Composite_C_net,
                                                 to_A, to_B, to_C, cost_A, cost_B, cost_C)],
                      by = "ym", all.x = TRUE)
setorder(portfolio_dt, Date)

# Pre-2011 weights: S4 v2 baseline (50/25/20/5) — uniform for all 3 paths
# Post-2011 weights: 0.55 Composite + 0.225 TSMOM + 0.18 KR_10y + 0.045 Cash
portfolio_dt[, has_composite := !is.na(Composite_A)]

# Cost-free portfolio
portfolio_dt[, ret_path_A := ifelse(has_composite,
  0.55 * Composite_A + 0.225 * TSMOM + 0.180 * KR_10y + 0.045 * Cash,
  0.50 * AR_on_M4   + 0.250 * TSMOM + 0.200 * KR_10y + 0.050 * Cash)]
portfolio_dt[, ret_path_B := ifelse(has_composite,
  0.55 * Composite_B + 0.225 * TSMOM + 0.180 * KR_10y + 0.045 * Cash,
  0.50 * AR_on_M4   + 0.250 * TSMOM + 0.200 * KR_10y + 0.050 * Cash)]
portfolio_dt[, ret_path_C := ifelse(has_composite,
  0.55 * Composite_C + 0.225 * TSMOM + 0.180 * KR_10y + 0.045 * Cash,
  0.50 * AR_on_M4   + 0.250 * TSMOM + 0.200 * KR_10y + 0.050 * Cash)]

# Cost-embedded portfolio (cost is at sleeve level → portfolio drag = 0.55 × sleeve_cost)
# Plus baseline cost: ~10% sleeve TO at 15bps × 2 × 0.45 (other sleeves) ≈ 1.35bps/mo baseline
COST_BASELINE_PORTFOLIO_OTHER <- 0.10 * 0.0015 * 2 * 0.45   # ~1.35 bps/mo
portfolio_dt[, drag_path_A := ifelse(has_composite,
  0.55 * cost_A + COST_BASELINE_PORTFOLIO_OTHER,
  0.50 * 0.10 * 0.0015 * 2)]
portfolio_dt[, drag_path_B := ifelse(has_composite,
  0.55 * cost_B + COST_BASELINE_PORTFOLIO_OTHER,
  0.50 * 0.10 * 0.0015 * 2)]
portfolio_dt[, drag_path_C := ifelse(has_composite,
  0.55 * cost_C + COST_BASELINE_PORTFOLIO_OTHER,
  0.50 * 0.10 * 0.0015 * 2)]

portfolio_dt[, ret_path_A_net := ret_path_A - drag_path_A]
portfolio_dt[, ret_path_B_net := ret_path_B - drag_path_B]
portfolio_dt[, ret_path_C_net := ret_path_C - drag_path_C]

cat(sprintf("  Portfolio rows: %d (%s ~ %s)\n",
            nrow(portfolio_dt),
            as.character(min(portfolio_dt$Date)),
            as.character(max(portfolio_dt$Date))))
cat(sprintf("  Composite-active rows: %d (2011+)\n", sum(portfolio_dt$has_composite)))

#==============================================================================
# 9. Metrics computation (PerformanceAnalytics standard)
#==============================================================================
cat("\n=== Step 9: Metrics per path (255m total + 184m active sub-period) ===\n")

compute_metrics_pp <- function(rets, dates, label) {
  rets_clean <- rets[!is.na(rets)]
  dates_clean <- dates[!is.na(rets)]
  if (length(rets_clean) < 12) return(NULL)
  xt <- xts(rets_clean, order.by = dates_clean)
  list(
    label = label,
    N = length(rets_clean),
    start = as.character(min(dates_clean)),
    end = as.character(max(dates_clean)),
    SR_ann_geometric = as.numeric(SharpeRatio.annualized(xt, scale = 12, geometric = TRUE)),
    CAGR = as.numeric(Return.annualized(xt, scale = 12, geometric = TRUE)),
    MDD = as.numeric(maxDrawdown(xt, geometric = TRUE)),
    Sortino = as.numeric(SortinoRatio(xt, MAR = 0)) * sqrt(12),
    Calmar = as.numeric(CalmarRatio(xt, scale = 12)),
    CVaR_95 = as.numeric(ES(xt, p = 0.95, method = "historical")),
    CVaR_99 = as.numeric(ES(xt, p = 0.99, method = "historical")),
    hit_rate = mean(rets_clean > 0),
    vol_ann = as.numeric(StdDev.annualized(xt, scale = 12)),
    mean_ann = as.numeric(Return.annualized(xt, scale = 12, geometric = FALSE))
  )
}

# Full window (255m, 2005-02 ~ 2026-04)
m_A_full <- compute_metrics_pp(portfolio_dt$ret_path_A_net, portfolio_dt$Date, "Path_A_EW_full_255m")
m_B_full <- compute_metrics_pp(portfolio_dt$ret_path_B_net, portfolio_dt$Date, "Path_B_Zlinear_full_255m")
m_C_full <- compute_metrics_pp(portfolio_dt$ret_path_C_net, portfolio_dt$Date, "Path_C_Zsoftmax_full_255m")

# S4 v2 baseline (50/25/20/5) for full 255m
portfolio_dt[, ret_S4_v2 := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]
# S4 v2 cost: ~5% sleeve TO × 15bps × 2 round-trip ≈ 1.5 bps/m
portfolio_dt[, drag_S4 := 0.05 * 0.0015 * 2]
portfolio_dt[, ret_S4_v2_net := ret_S4_v2 - drag_S4]
m_S4_full <- compute_metrics_pp(portfolio_dt$ret_S4_v2_net, portfolio_dt$Date, "S4_v2_baseline_full_255m")

# Active composite sub-period (184m, 2011-01 ~ 2026-04)
portfolio_active <- portfolio_dt[has_composite == TRUE]
m_A_active <- compute_metrics_pp(portfolio_active$ret_path_A_net, portfolio_active$Date, "Path_A_active_184m")
m_B_active <- compute_metrics_pp(portfolio_active$ret_path_B_net, portfolio_active$Date, "Path_B_active_184m")
m_C_active <- compute_metrics_pp(portfolio_active$ret_path_C_net, portfolio_active$Date, "Path_C_active_184m")
m_S4_active <- compute_metrics_pp(portfolio_active$ret_S4_v2_net, portfolio_active$Date, "S4_v2_active_184m")

print_metrics <- function(m) {
  cat(sprintf("  [%s]\n", m$label))
  cat(sprintf("    N=%d (%s ~ %s)\n", m$N, m$start, m$end))
  cat(sprintf("    SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f, Sortino=%.4f, Calmar=%.4f, Hit=%.3f, Vol=%.4f\n",
              m$SR_ann_geometric, m$CAGR, m$MDD, m$CVaR_95, m$Sortino, m$Calmar, m$hit_rate, m$vol_ann))
}

cat("\n--- Full window 255m (2005-02 ~ 2026-04) ---\n")
print_metrics(m_A_full); print_metrics(m_B_full); print_metrics(m_C_full); print_metrics(m_S4_full)

cat("\n--- Active composite sub-period 184m (2011-01 ~ 2026-04) ---\n")
print_metrics(m_A_active); print_metrics(m_B_active); print_metrics(m_C_active); print_metrics(m_S4_active)

#==============================================================================
# 10. 4-axis strict improve test (Path X vs S4 v2 baseline, same period)
#==============================================================================
cat("\n=== Step 10: 4-axis strict improve test (each path vs S4 v2 full 255m) ===\n")

axis_test <- function(m, baseline, label) {
  list(
    label = label,
    SR_pass = m$SR_ann_geometric > baseline$SR_ann_geometric,
    delta_SR = m$SR_ann_geometric - baseline$SR_ann_geometric,
    CAGR_pass = m$CAGR > baseline$CAGR,
    delta_CAGR_pp = (m$CAGR - baseline$CAGR) * 100,
    MDD_pass = m$MDD < baseline$MDD,   # less negative = better (m$MDD already negative)
    delta_MDD_pp = (m$MDD - baseline$MDD) * 100,
    CVaR_pass = m$CVaR_95 > baseline$CVaR_95,   # less negative = better
    delta_CVaR_pp = (m$CVaR_95 - baseline$CVaR_95) * 100,
    n_pass = sum(c(m$SR_ann_geometric > baseline$SR_ann_geometric,
                   m$CAGR > baseline$CAGR,
                   m$MDD < baseline$MDD,
                   m$CVaR_95 > baseline$CVaR_95))
  )
}

axis_A <- axis_test(m_A_full, m_S4_full, "Path_A_EW")
axis_B <- axis_test(m_B_full, m_S4_full, "Path_B_Zlinear")
axis_C <- axis_test(m_C_full, m_S4_full, "Path_C_Zsoftmax")

print_axis <- function(a) {
  cat(sprintf("  [%s]  axes pass: %d / 4\n", a$label, a$n_pass))
  cat(sprintf("    SR     : %s (delta %+.4f)\n", ifelse(a$SR_pass, "PASS", "FAIL"), a$delta_SR))
  cat(sprintf("    CAGR   : %s (delta %+.4f pp)\n", ifelse(a$CAGR_pass, "PASS", "FAIL"), a$delta_CAGR_pp))
  cat(sprintf("    MDD    : %s (delta %+.4f pp)\n", ifelse(a$MDD_pass, "PASS", "FAIL"), a$delta_MDD_pp))
  cat(sprintf("    CVaR95 : %s (delta %+.4f pp)\n", ifelse(a$CVaR_pass, "PASS", "FAIL"), a$delta_CVaR_pp))
}

print_axis(axis_A); print_axis(axis_B); print_axis(axis_C)

#==============================================================================
# 11. Diebold-Mariano vs S4 v2 baseline (Newey-West lag 6)
#==============================================================================
cat("\n=== Step 11: Diebold-Mariano vs S4 v2 (full 255m) ===\n")

compute_dm <- function(rets_strat, rets_base, label) {
  diff <- rets_strat - rets_base
  diff <- diff[!is.na(diff)]
  N <- length(diff)
  if (N < 30) return(NULL)
  nw_lag <- 6
  m_diff <- mean(diff)
  nw_var <- var(diff)
  for (lag in 1:nw_lag) {
    weight <- 1 - lag / (nw_lag + 1)
    ac <- mean((diff[(lag + 1):N] - m_diff) * (diff[1:(N - lag)] - m_diff))
    nw_var <- nw_var + 2 * weight * ac
  }
  nw_se <- sqrt(nw_var / N)
  t_nw <- m_diff / nw_se
  p_nw <- 2 * pnorm(-abs(t_nw))
  list(label = label, N = N, mean_diff = m_diff, NW_lag6_SE = nw_se,
       t_NW = t_nw, p_value = p_nw, hlz_pass = abs(t_nw) > 3.0)
}

dm_A <- compute_dm(portfolio_dt$ret_path_A_net, portfolio_dt$ret_S4_v2_net, "Path_A_vs_S4")
dm_B <- compute_dm(portfolio_dt$ret_path_B_net, portfolio_dt$ret_S4_v2_net, "Path_B_vs_S4")
dm_C <- compute_dm(portfolio_dt$ret_path_C_net, portfolio_dt$ret_S4_v2_net, "Path_C_vs_S4")

print_dm <- function(d) {
  cat(sprintf("  [%s]  N=%d, mean_diff=%.6f, NW_SE=%.6f, t=%.4f, p=%.4f, Harvey3.0=%s\n",
              d$label, d$N, d$mean_diff, d$NW_lag6_SE, d$t_NW, d$p_value,
              ifelse(d$hlz_pass, "PASS", "FAIL")))
}
print_dm(dm_A); print_dm(dm_B); print_dm(dm_C)

#==============================================================================
# 12. Hurdle Gate v2.2/v2.3 check (TO < 600% strict; v2.3 TO < 800%)
#==============================================================================
cat("\n=== Step 12: Hurdle Gate TO check (v2.2 600%, v2.3 800%) ===\n")

# Portfolio-weighted round-trip TO per path
# Sleeve TO × sleeve weight × 2 round-trip + baseline TO contribution
to_A_portfolio_rt <- mean(to_A) * 2 * 0.55 * 12 + 0.10 * 2 * 0.45 * 12   # rough proxy
to_B_portfolio_rt <- mean(to_B) * 2 * 0.55 * 12 + 0.10 * 2 * 0.45 * 12
to_C_portfolio_rt <- mean(to_C) * 2 * 0.55 * 12 + 0.10 * 2 * 0.45 * 12

cat(sprintf("  Portfolio-weighted RT TO (annual):\n"))
cat(sprintf("    Path A: %.1f%% (Hurdle v2.2 %s, v2.3 %s)\n",
            to_A_portfolio_rt * 100,
            ifelse(to_A_portfolio_rt < 6.0, "PASS", "FAIL"),
            ifelse(to_A_portfolio_rt < 8.0, "PASS", "FAIL")))
cat(sprintf("    Path B: %.1f%% (Hurdle v2.2 %s, v2.3 %s)\n",
            to_B_portfolio_rt * 100,
            ifelse(to_B_portfolio_rt < 6.0, "PASS", "FAIL"),
            ifelse(to_B_portfolio_rt < 8.0, "PASS", "FAIL")))
cat(sprintf("    Path C: %.1f%% (Hurdle v2.2 %s, v2.3 %s)\n",
            to_C_portfolio_rt * 100,
            ifelse(to_C_portfolio_rt < 6.0, "PASS", "FAIL"),
            ifelse(to_C_portfolio_rt < 8.0, "PASS", "FAIL")))

#==============================================================================
# 13. Save outputs (Backtest Contract v1.0)
#==============================================================================
cat("\n=== Step 13: Save outputs ===\n")

# period_returns.csv (3 paths + S4 baseline + cost components)
period_out <- portfolio_dt[, .(
  Date, ym, has_composite,
  ret_path_A, ret_path_A_net, drag_path_A,
  ret_path_B, ret_path_B_net, drag_path_B,
  ret_path_C, ret_path_C_net, drag_path_C,
  ret_S4_v2, ret_S4_v2_net,
  AR_on_M4, TSMOM, KR_10y, Cash,
  Composite_A, Composite_B, Composite_C
)]
fwrite(period_out, file.path(OUT_DIR, "period_returns.csv"))

# NAV per path
nav_dt <- portfolio_dt[, .(Date,
                            ret_A = ret_path_A_net,
                            ret_B = ret_path_B_net,
                            ret_C = ret_path_C_net,
                            ret_S4 = ret_S4_v2_net)]
nav_dt[, nav_A := cumprod(1 + ifelse(is.na(ret_A), 0, ret_A))]
nav_dt[, nav_B := cumprod(1 + ifelse(is.na(ret_B), 0, ret_B))]
nav_dt[, nav_C := cumprod(1 + ifelse(is.na(ret_C), 0, ret_C))]
nav_dt[, nav_S4 := cumprod(1 + ifelse(is.na(ret_S4), 0, ret_S4))]
fwrite(nav_dt, file.path(OUT_DIR, "nav.csv"))

# Holdings.csv (with weights per path)
holdings_out <- holdings_dt[, .(sig_date, Ticker, rank, composite_z, z_1715, z_NEW, Ret_1m,
                                 w_sleeve_A, w_portfolio_A,
                                 w_sleeve_B = w_sleeve_B_capped, w_portfolio_B,
                                 w_sleeve_C = w_sleeve_C_capped, w_portfolio_C)]
fwrite(holdings_out, file.path(OUT_DIR, "holdings.csv"))

# Metrics CSV (full + active windows, all paths + S4)
metrics_list <- list(
  PathA_full = m_A_full, PathB_full = m_B_full, PathC_full = m_C_full, S4_full = m_S4_full,
  PathA_active = m_A_active, PathB_active = m_B_active, PathC_active = m_C_active, S4_active = m_S4_active
)
metrics_csv <- data.table()
for (nm in names(metrics_list)) {
  m <- metrics_list[[nm]]
  if (!is.null(m)) {
    dt <- data.table(
      window = nm,
      label = m$label,
      N = m$N,
      start = m$start, end = m$end,
      SR = m$SR_ann_geometric, CAGR = m$CAGR, MDD = m$MDD,
      Sortino = m$Sortino, Calmar = m$Calmar,
      CVaR_95 = m$CVaR_95, CVaR_99 = m$CVaR_99,
      hit_rate = m$hit_rate, vol_ann = m$vol_ann, mean_ann = m$mean_ann
    )
    metrics_csv <- rbind(metrics_csv, dt)
  }
}
fwrite(metrics_csv, file.path(OUT_DIR, "metrics.csv"))

# 4-axis strict improve summary
axis_csv <- data.table(
  path = c("Path_A_EW", "Path_B_Zlinear", "Path_C_Zsoftmax"),
  SR = c(m_A_full$SR_ann_geometric, m_B_full$SR_ann_geometric, m_C_full$SR_ann_geometric),
  CAGR = c(m_A_full$CAGR, m_B_full$CAGR, m_C_full$CAGR),
  MDD = c(m_A_full$MDD, m_B_full$MDD, m_C_full$MDD),
  CVaR_95 = c(m_A_full$CVaR_95, m_B_full$CVaR_95, m_C_full$CVaR_95),
  baseline_SR = m_S4_full$SR_ann_geometric,
  baseline_CAGR = m_S4_full$CAGR,
  baseline_MDD = m_S4_full$MDD,
  baseline_CVaR_95 = m_S4_full$CVaR_95,
  delta_SR = c(axis_A$delta_SR, axis_B$delta_SR, axis_C$delta_SR),
  delta_CAGR_pp = c(axis_A$delta_CAGR_pp, axis_B$delta_CAGR_pp, axis_C$delta_CAGR_pp),
  delta_MDD_pp = c(axis_A$delta_MDD_pp, axis_B$delta_MDD_pp, axis_C$delta_MDD_pp),
  delta_CVaR_pp = c(axis_A$delta_CVaR_pp, axis_B$delta_CVaR_pp, axis_C$delta_CVaR_pp),
  axes_pass = c(axis_A$n_pass, axis_B$n_pass, axis_C$n_pass),
  all_4_pass = c(axis_A$n_pass == 4, axis_B$n_pass == 4, axis_C$n_pass == 4)
)
fwrite(axis_csv, file.path(OUT_DIR, "4axis_strict_improve.csv"))

# Diebold-Mariano CSV
dm_csv <- data.table(
  path = c("Path_A_EW", "Path_B_Zlinear", "Path_C_Zsoftmax"),
  N = c(dm_A$N, dm_B$N, dm_C$N),
  mean_diff = c(dm_A$mean_diff, dm_B$mean_diff, dm_C$mean_diff),
  NW_lag6_SE = c(dm_A$NW_lag6_SE, dm_B$NW_lag6_SE, dm_C$NW_lag6_SE),
  t_NW = c(dm_A$t_NW, dm_B$t_NW, dm_C$t_NW),
  p_value = c(dm_A$p_value, dm_B$p_value, dm_C$p_value),
  Harvey_3_pass = c(dm_A$hlz_pass, dm_B$hlz_pass, dm_C$hlz_pass)
)
fwrite(dm_csv, file.path(OUT_DIR, "diebold_mariano.csv"))

# Hurdle CSV
hurdle_csv <- data.table(
  path = c("Path_A_EW", "Path_B_Zlinear", "Path_C_Zsoftmax"),
  sleeve_oneway_TO_pct_annual = c(mean(to_A)*12*100, mean(to_B)*12*100, mean(to_C)*12*100),
  portfolio_RT_TO_pct_annual = c(to_A_portfolio_rt*100, to_B_portfolio_rt*100, to_C_portfolio_rt*100),
  cost_drag_bps_annual = c(mean(period_ret_sleeve$cost_A)*12*1e4 * 0.55,
                            mean(period_ret_sleeve$cost_B)*12*1e4 * 0.55,
                            mean(period_ret_sleeve$cost_C)*12*1e4 * 0.55),
  hurdle_v22_600_pass = c(to_A_portfolio_rt < 6.0,
                            to_B_portfolio_rt < 6.0,
                            to_C_portfolio_rt < 6.0),
  hurdle_v23_800_pass = c(to_A_portfolio_rt < 8.0,
                            to_B_portfolio_rt < 8.0,
                            to_C_portfolio_rt < 8.0)
)
fwrite(hurdle_csv, file.path(OUT_DIR, "hurdle_result.csv"))

# Tau diagnostic (Path C)
fwrite(tau_diag, file.path(OUT_DIR, "tau_diagnostic_pathC.csv"))

# Cap diagnostic
cap_diag <- holdings_dt[, .(
  max_w_sleeve_B = max(w_sleeve_B_capped),
  max_w_sleeve_C = max(w_sleeve_C_capped),
  max_w_portfolio_B = max(w_portfolio_B),
  max_w_portfolio_C = max(w_portfolio_C),
  cap_active_B = any(w_sleeve_B > W_CAP / SLEEVE_W),
  cap_active_C = any(w_sleeve_C > W_CAP / SLEEVE_W)
), by = sig_date]
fwrite(cap_diag, file.path(OUT_DIR, "cap_diagnostic.csv"))

#==============================================================================
# 14. 3-package md5sum END — Pure function audit
#==============================================================================
md5_end <- list(
  alpha = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk  = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt   = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
md5_match <- all(c(md5_start$alpha == md5_end$alpha,
                   md5_start$risk == md5_end$risk,
                   md5_start$opt == md5_end$opt))
cat(sprintf("\n3-package md5sum END:\n"))
cat("  alpha:", md5_end$alpha, "\n")
cat("  risk: ", md5_end$risk, "\n")
cat("  opt:  ", md5_end$opt, "\n")
cat(sprintf("Pure function audit: %s\n", ifelse(md5_match, "PASS", "FAIL")))

md5_audit <- data.table(
  package = c("alpha", "risk", "optimization"),
  md5_start = c(md5_start$alpha, md5_start$risk, md5_start$opt),
  md5_end = c(md5_end$alpha, md5_end$risk, md5_end$opt),
  match = c(md5_start$alpha == md5_end$alpha,
            md5_start$risk == md5_end$risk,
            md5_start$opt == md5_end$opt)
)
fwrite(md5_audit, file.path(OUT_DIR, "pure_function_audit.csv"))

#==============================================================================
# 15. Save final RDS bundle
#==============================================================================
saveRDS(list(
  metrics = list(
    full_255m = list(A = m_A_full, B = m_B_full, C = m_C_full, S4 = m_S4_full),
    active_184m = list(A = m_A_active, B = m_B_active, C = m_C_active, S4 = m_S4_active)
  ),
  axis_test = list(A = axis_A, B = axis_B, C = axis_C),
  DM = list(A = dm_A, B = dm_B, C = dm_C),
  hurdle = hurdle_csv,
  turnover = list(A = to_A, B = to_B, C = to_C),
  tau_diagnostic = tau_diag,
  pure_function = list(md5_start = md5_start, md5_end = md5_end, match = md5_match),
  design = list(
    sleeve_w_KR_equity = SLEEVE_W,
    sleeve_w_TSMOM = W_TSMOM,
    sleeve_w_KR_10y = W_KR,
    sleeve_w_Cash = W_CASH,
    cap_portfolio = W_CAP,
    composite_z_weights = list(W_1715 = W_1715, W_NEW = W_NEW),
    coverage_full = c("2005-02-01", "2026-04-01"),
    coverage_active = c("2011-01-01", "2026-04-01"),
    pre_2011_redistribute = "S4_v2_baseline_50_25_20_5"
  )
), file.path(OUT_DIR, "metrics_pd25.rds"))

cat("\n=== PD25 DONE ===\n")
cat(sprintf("Outputs in: %s\n", OUT_DIR))
cat(sprintf("Finished: %s\n", format(Sys.time())))
