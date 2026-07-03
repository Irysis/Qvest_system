# ============================================================================
# test_canonical_screen_bt.R - contract regression for canonical_screen_bt()
# Target (read-only): 02_Infrastructure/contracts/canonical_screen_bt.R
#                     (+ backtest_result_contract.R::build_benchmark_compare)
# Covered branches:
#   - top-N EW long-only construction == PerformanceAnalytics::Return.portfolio
#   - delta-based turnover/cost convention (traded = sum|w_t - w_{t-1}|,
#     one-way bps per traded notional)
#   - net_sr == PerformanceAnalytics::SharpeRatio.annualized (geometric=FALSE)
#   - IR / Portfolio_Alpha_t_NW_lag3 vs independent Bartlett NW-lag3 t
#   - liquidity filter exclusion, top_n > N available, missing return -> 0
# ============================================================================

suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})

.this_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.here <- dirname(normalizePath(.this_file, winslash = "/"))
source(file.path(.here, "helpers.R"))
ROOT <- t_root()

source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

# ---------------------------------------------------------------------------
# Deterministic fixture: 3 tickers x 8 months, top_n = 2
# months 1-3 select {A,B}; months 4-8 select {A,C}
# ---------------------------------------------------------------------------
months <- seq(as.Date("2021-01-01"), by = "month", length.out = 8)
rA <- c( 0.020, 0.010,  0.030, -0.010,  0.020, 0.015, 0.005,  0.020)
rB <- c( 0.005, 0.020, -0.010,  0.010,  0.000, 0.010, 0.020, -0.005)
rC <- c(-0.010, 0.005,  0.010,  0.030, -0.020, 0.005, 0.015,  0.010)
rBM <- c(0.010, 0.005,  0.020, -0.005,  0.010, 0.000, 0.010,  0.005)

sc <- function(m, sA, sB, sC) data.table(Date = months[m],
                                         Ticker = c("A", "B", "C"),
                                         score = c(sA, sB, sC))
scores_dt <- rbindlist(c(lapply(1:3, sc, sA = 3, sB = 2, sC = 1),
                         lapply(4:8, sc, sA = 3, sB = 1, sC = 2)))
returns_dt <- rbindlist(lapply(seq_along(months), function(m)
  data.table(Date = months[m], Ticker = c("A", "B", "C"),
             Ret_1m = c(rA[m], rB[m], rC[m]))))
bench_dt <- data.table(Date = months, BM_Ret = rBM)

res <- canonical_screen_bt(scores_dt, returns_dt, bench_dt,
                           top_n = 2L, cost_bps_oneway = 15)

# Expected (hand-derived, mathematically evident):
exp_gross  <- c((rA + rB)[1:3] / 2, (rA + rC)[4:8] / 2)
exp_traded <- c(1, 0, 0, 1, 0, 0, 0, 0)   # entry, hold, hold, B->C swap, hold...
exp_net    <- exp_gross - exp_traded * 15 / 1e4
exp_active <- exp_net - rBM

# --- CB01: net returns = EW top-2 gross - delta-based cost -------------------
t_check("canonical:CB01_topN_EW_net_returns_exact",
        t_near(res$period_returns$ret_net, exp_net, tol = 1e-12))

# --- CB02: gross construction == PerformanceAnalytics::Return.portfolio -----
R_xts <- xts(cbind(A = rA, B = rB, C = rC), order.by = months)
W <- rbind(matrix(rep(c(0.5, 0.5, 0.0), 3), ncol = 3, byrow = TRUE),
           matrix(rep(c(0.5, 0.0, 0.5), 5), ncol = 3, byrow = TRUE))
W_xts <- xts(W, order.by = months - 1)   # weights effective for next period
colnames(W_xts) <- c("A", "B", "C")
pa_port <- as.numeric(Return.portfolio(R_xts, weights = W_xts, geometric = TRUE))
t_check("canonical:CB02_matches_Return.portfolio",
        length(pa_port) == 8L && t_near(pa_port, exp_gross, tol = 1e-12) &&
        t_near(res$period_returns$ret_net + exp_traded * 15 / 1e4, pa_port,
               tol = 1e-12))

# --- CB03: net_sr == SharpeRatio.annualized(active, geometric=FALSE) --------
act_xts <- xts(exp_active, order.by = months)
pa_sr <- as.numeric(SharpeRatio.annualized(act_xts, scale = 12, geometric = FALSE))
t_check("canonical:CB03_net_sr_matches_PerformanceAnalytics",
        t_near(res$net_sr, pa_sr, tol = 1e-10))

# --- CB04: NW lag-3 t vs independent Bartlett implementation ----------------
nw_t_ref <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  mu <- mean(x); e <- x - mu
  s <- sum(e^2) / n
  for (l in 1:lag) s <- s + 2 * (1 - l / (lag + 1)) * sum(e[(l + 1):n] * e[1:(n - l)]) / n
  mu / sqrt(s / n)
}
t_check("canonical:CB04_port_alpha_t_nw_lag3_matches_reference",
        t_near(res$portfolio_alpha_t_nw_lag3, nw_t_ref(exp_active), tol = 1e-10))

# --- CB05: cost/turnover convention ------------------------------------------
t_check("canonical:CB05_turnover_annual_and_first_cost",
        t_near(res$turnover_annual, mean(exp_traded) * 12, tol = 1e-12) &&
        t_near(res$period_returns$ret_net[1], exp_gross[1] - 0.0015, tol = 1e-12))

# --- CB06: labels / shape -----------------------------------------------------
t_check("canonical:CB06_metric_type_and_n_months",
        identical(res$metric_type, "canonical_screen") &&
        identical(res$n_months, 8L) && identical(res$top_n, 2L))

# --- CB09: IR equals mean/sd*sqrt(12) of net active --------------------------
t_check("canonical:CB09_information_ratio_formula",
        t_near(res$information_ratio,
               mean(exp_active) / sd(exp_active) * sqrt(12), tol = 1e-10))

# --- CB07: liquidity filter (C below 2e8 at month 4 -> {A,B} kept) -----------
liq_dt <- rbindlist(lapply(seq_along(months), function(m)
  data.table(Date = months[m], Ticker = c("A", "B", "C"),
             adv = c(1e9, 1e9, if (m == 4L) 1e8 else 1e9))))
res_liq <- canonical_screen_bt(scores_dt, returns_dt, bench_dt,
                               top_n = 2L, cost_bps_oneway = 15, liq_dt = liq_dt)
exp_gross_liq  <- exp_gross;  exp_gross_liq[4] <- (rA[4] + rB[4]) / 2
exp_traded_liq <- c(1, 0, 0, 0, 1, 0, 0, 0)   # swap deferred to month 5
exp_net_liq    <- exp_gross_liq - exp_traded_liq * 15 / 1e4
t_check("canonical:CB07_liquidity_filter_changes_selection",
        t_near(res_liq$period_returns$ret_net, exp_net_liq, tol = 1e-12))

# --- CB08: top_n greater than available -> EW over all -----------------------
res_all <- canonical_screen_bt(scores_dt, returns_dt, bench_dt,
                               top_n = 5L, cost_bps_oneway = 15)
exp_gross_all <- (rA + rB + rC) / 3
t_check("canonical:CB08_topn_gt_universe_ew_all",
        t_near(res_all$period_returns$ret_net + c(1, rep(0, 7)) * 15 / 1e4,
               exp_gross_all, tol = 1e-12))

# --- CB10: missing forward return treated as 0 --------------------------------
returns_gap <- returns_dt[!(Date == months[2] & Ticker == "A")]
res_gap <- canonical_screen_bt(scores_dt, returns_gap, bench_dt,
                               top_n = 2L, cost_bps_oneway = 15)
exp_gross_gap <- exp_gross; exp_gross_gap[2] <- (0 + rB[2]) / 2
t_check("canonical:CB10_missing_return_zero_filled",
        t_near(res_gap$period_returns$ret_net[2], exp_gross_gap[2], tol = 1e-12))

t_summary("test_canonical_screen_bt")
