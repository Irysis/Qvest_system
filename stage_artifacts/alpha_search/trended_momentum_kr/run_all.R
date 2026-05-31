#!/usr/bin/env Rscript
#==============================================================================
# Trended Momentum (KR) — Alpha-Searching lean-lane PoC
# Paper: Cai, Li, Keasey (2024) "Trended Momentum" (SSRN 4740445)
#
# Spec (paper §4.1 p.12):
#   PRET = cumulative return t-11..t-1 (12m skip last month)
#   TC   = R^2 of regression of DAILY stock price on date-sequence over an
#          11-month formation window; require >= 200 days.
#   Sort = stocks sorted into PRET quintiles, then within (independent) TC
#          quintiles. "Trended momentum" = top PRET quintile (winners) AND
#          top TC quintile. Long-only long leg.
#   Weight = paper reports BOTH equal- and value-weighted. Long leg here uses
#            EQUAL-WEIGHT (Σw=1, w∈[0,0.20]); see report caveat (weight assumption).
#   Rebalance = monthly. Cost = 15bps one-way.
#
# Output: this script writes sim_result.rds (handoff to measurement step).
#   PIT: C1 (rolling only), C2 (no same-day), C10 (LIQ t-1), C14.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)
})

# ---- paths (relative / PROJECT_ROOT, no normalizePath) ----
PROJECT_ROOT <- Sys.getenv("QM_ROOT", unset = getwd())
# walk up to project root if launched from strategy dir
.find_root <- function(start) {
  d <- start
  for (i in 1:8) {
    if (file.exists(file.path(d, "02_Infrastructure", "config.R"))) return(d)
    d <- dirname(d)
  }
  start
}
PROJECT_ROOT <- .find_root(getwd())
cat("[run_all] PROJECT_ROOT =", PROJECT_ROOT, "\n")
source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "backtest_harness.R"))

OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", "trended_momentum_kr")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- params ----
LIQ_THRESHOLD <- 2e8       # 20d avg turnover-value (KRW)
LIQ_WINDOW    <- 20L
MAX_N         <- 25L       # production max holdings
W_CAP         <- 0.20
PRET_SKIP     <- 21L       # ~1 month (trading days)
PRET_LOOKBACK <- 252L      # ~12 months
TC_WINDOW     <- 231L      # ~11 months formation
TC_MIN_DAYS   <- 200L      # paper requirement
COST_BPS      <- 15        # one-way
SIGNAL_CUTOFF <- NULL      # lean discovery = full sample (precondition: paper KR untested)
START_BUILD   <- as.Date("2002-01-01")  # need ~1y warmup; KR universe meaningful post-2001

# ---- load data (cache, preloaded once) ----
rd <- load_rawdata(use_cache = TRUE)
RAWDATA <- rd$RAWDATA; BM_DT <- rd$BM_DT
setDT(RAWDATA); setDT(BM_DT)
RAWDATA[, Date := as.Date(Date)]
BM_DT[, Date := as.Date(Date)]
setkey(RAWDATA, Ticker, Date)

# universe membership flag (time-varying, PIT-safe as-of each date)
RAWDATA[, in_univ := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
# turnover value for liquidity (Vol shares * Close price)
RAWDATA[, turnover_val := as.numeric(Vol) * as.numeric(Close)]

all_dates <- sort(unique(RAWDATA$Date))

# ---- monthly signal dates = last trading day of each month ----
date_dt <- data.table(Date = all_dates)
date_dt[, ym := format(Date, "%Y-%m")]
sig_dates <- date_dt[, .(Date = max(Date)), by = ym]$Date
sig_dates <- sort(sig_dates[sig_dates >= START_BUILD])
cat(sprintf("[run_all] sig_dates: %d (%s .. %s)\n",
            length(sig_dates), min(sig_dates), max(sig_dates)))

# precompute per-ticker date index position for fast windowing
setorder(RAWDATA, Ticker, Date)
RAWDATA[, ridx := seq_len(.N), by = Ticker]

#------------------------------------------------------------------------------
# Signal computation at one sig_date (uses ONLY data <= sig_date) — C1/C2/C14
#------------------------------------------------------------------------------
compute_signals_at <- function(sd) {
  # snapshot up to and INCLUDING sig_date (sig_date = decision date, prices known EOD)
  snap <- RAWDATA[Date <= sd]
  # universe = members as-of sig_date
  univ_tk <- snap[Date == sd & in_univ == TRUE, unique(Ticker)]
  if (length(univ_tk) == 0) return(NULL)

  # liquidity filter: 20d avg turnover_val over days STRICTLY BEFORE sig_date (t-1, C10)
  liq <- snap[Date < sd & Ticker %in% univ_tk,
              {
                v <- tail(turnover_val, LIQ_WINDOW)
                .(liq_avg = if (length(v) >= LIQ_WINDOW) mean(v, na.rm = TRUE) else NA_real_)
              }, by = Ticker]
  liq_tk <- liq[is.finite(liq_avg) & liq_avg >= LIQ_THRESHOLD, Ticker]
  if (length(liq_tk) < 10) return(NULL)

  # per-ticker PRET (t-11..t-1) and TC (R^2 over 11m formation), data <= sig_date
  res <- snap[Ticker %in% liq_tk,
    {
      cl <- Close; n <- .N
      pret <- NA_real_; tc <- NA_real_
      # PRET: Close[n-PRET_SKIP] / Close[n-PRET_LOOKBACK] - 1   (skip most recent ~1m)
      if (n >= PRET_LOOKBACK + 1L) {
        p_end   <- cl[n - PRET_SKIP]       # ~t-1 month
        p_start <- cl[n - PRET_LOOKBACK]   # ~t-12 month
        if (is.finite(p_end) && is.finite(p_start) && p_start > 0)
          pret <- p_end / p_start - 1
      }
      # TC: R^2 of price ~ date_index over last TC_WINDOW days (>= TC_MIN_DAYS valid)
      w_from <- max(1L, n - TC_WINDOW + 1L)
      pw <- cl[w_from:n]
      ok <- is.finite(pw)
      if (sum(ok) >= TC_MIN_DAYS) {
        y <- pw[ok]; x <- seq_along(pw)[ok]
        # R^2 = cor(x,y)^2 for simple linear regression (price on date)
        cc <- suppressWarnings(cor(x, y))
        if (is.finite(cc)) tc <- cc^2
      }
      .(PRET = pret, TC = tc)
    }, by = Ticker]

  res <- res[is.finite(PRET) & is.finite(TC)]
  if (nrow(res) < 10) return(NULL)

  # double sort: PRET quintile (5=winners) and TC quintile (5=clearest trend)
  res[, pret_q := cut(PRET, breaks = quantile(PRET, probs = seq(0,1,0.2), na.rm = TRUE),
                      labels = FALSE, include.lowest = TRUE)]
  res[, tc_q   := cut(TC,   breaks = quantile(TC,   probs = seq(0,1,0.2), na.rm = TRUE),
                      labels = FALSE, include.lowest = TRUE)]
  res[, sig_date := sd]
  res
}

#------------------------------------------------------------------------------
# Build monthly target portfolios
#------------------------------------------------------------------------------
sig_list <- lapply(sig_dates, compute_signals_at)
names(sig_list) <- as.character(sig_dates)
sig_list <- sig_list[!sapply(sig_list, is.null)]
cat(sprintf("[run_all] valid signal months: %d\n", length(sig_list)))

# selection: top PRET quintile AND top TC quintile ("trended momentum"),
# if > MAX_N keep highest TC; if (rare) selection empty, fall back to winners ranked by TC.
build_targets <- function(res) {
  sel <- res[pret_q == 5 & tc_q == 5]
  if (nrow(sel) == 0) sel <- res[pret_q == 5][order(-TC)]
  setorder(sel, -TC)                      # rank clearest trend first
  if (nrow(sel) > MAX_N) sel <- sel[1:MAX_N]
  n <- nrow(sel)
  w <- rep(1/n, n)                        # equal weight long leg (paper EW)
  w <- pmin(w, W_CAP); w <- w / sum(w)    # cap [0,0.20] + renormalize
  data.table(sig_date = sel$sig_date[1], Ticker = sel$Ticker, Weight = w,
             Score = sel$TC, PRET = sel$PRET, TC = sel$TC)
}
targets <- rbindlist(lapply(sig_list, build_targets))
setorder(targets, sig_date, -Weight)

# execution date = first trading day of NEXT month after sig_date (no same-day, C2)
exec_map <- data.table(sig_date = sort(unique(targets$sig_date)))
exec_map[, exec_date := as.Date(sapply(sig_date, function(s) as.character(get_execution_date(s, all_dates))))]
targets <- merge(targets, exec_map, by = "sig_date")
targets <- targets[is.finite(exec_date)]
cat(sprintf("[run_all] target months with exec date: %d | avg holdings: %.1f\n",
            uniqueN(targets$sig_date), targets[, .N, by=sig_date][, mean(N)]))

#------------------------------------------------------------------------------
# Daily NAV via Return.portfolio (drift-aware), net of 15bps turnover cost.
#------------------------------------------------------------------------------
# build daily wide return matrix for held tickers over backtest window
exec_dates <- sort(unique(targets$exec_date))
bt_start <- min(exec_dates)
bt_end   <- max(all_dates)
held_tk  <- sort(unique(targets$Ticker))

ret_long <- RAWDATA[Ticker %in% held_tk & Date >= bt_start & Date <= bt_end,
                    .(Date, Ticker, Ret)]
ret_long[!is.finite(Ret), Ret := 0]
R_wide <- dcast(ret_long, Date ~ Ticker, value.var = "Ret", fill = 0)
setorder(R_wide, Date)
R_dates <- R_wide$Date
R_mat <- as.matrix(R_wide[, -1, with = FALSE])
R_xts <- xts(R_mat, order.by = R_dates)

# weights xts: rows = exec_dates, cols = same tickers as R_xts (0 for non-held)
tk_cols <- colnames(R_xts)
W_mat <- matrix(0, nrow = length(exec_dates), ncol = length(tk_cols),
                dimnames = list(NULL, tk_cols))
for (i in seq_along(exec_dates)) {
  ed <- exec_dates[i]
  tg <- targets[exec_date == ed]
  W_mat[i, match(tg$Ticker, tk_cols)] <- tg$Weight
}
W_xts <- xts(W_mat, order.by = exec_dates)

# Return.portfolio: drift-aware, rebalanced on exec_dates (weights rows)
rp <- Return.portfolio(R = R_xts, weights = W_xts, rebalance_on = NA, verbose = TRUE)
gross_xts <- rp$returns          # daily gross portfolio return (pre-cost)

# turnover cost: at each rebalance, sum|w_target - w_drifted_before| * cost
# Return.portfolio verbose gives BOP/EOP weights; compute turnover at rebal dates
bop <- rp$BOP.Weight              # beginning-of-period weights (post-rebalance target on rebal days)
eop <- rp$EOP.Weight
# turnover on each exec date = sum |BOP(t) - EOP(t-1)| ; first = sum|BOP|
turn <- rep(0, length(exec_dates))
W_aligned <- W_mat  # target weights
prev_eop <- rep(0, ncol(W_mat))
eop_dates <- index(eop)
for (i in seq_along(exec_dates)) {
  ed <- exec_dates[i]
  # drifted weights just before rebalance = EOP weight on last day < ed
  prior_idx <- which(eop_dates < ed)
  drift_w <- if (length(prior_idx)) as.numeric(eop[max(prior_idx), ]) else rep(0, ncol(W_mat))
  tgt_w <- W_mat[i, ]
  turn[i] <- sum(abs(tgt_w - drift_w))
}
cost_on_exec <- turn * (COST_BPS / 1e4)   # one-way cost charged on turnover

# net daily return = gross, minus cost on exec dates
net_xts <- gross_xts
for (i in seq_along(exec_dates)) {
  ed <- exec_dates[i]
  pos <- which(index(net_xts) == ed)
  if (length(pos)) net_xts[pos] <- as.numeric(net_xts[pos]) - cost_on_exec[i]
}

# daily NAV (gross + net) — uses cumulative product of (1+r) which is the
# definition of NAV path (PerformanceAnalytics Return.portfolio output chained).
nav_gross <- as.numeric(cumprod(1 + as.numeric(gross_xts)))
nav_net   <- as.numeric(cumprod(1 + as.numeric(net_xts)))
nav_dates <- index(gross_xts)

DAILY_NAV_DT <- data.table(Date = as.Date(nav_dates),
                           NAV = nav_net, NAV_gross = nav_gross)

# benchmark daily xts aligned to nav window
bm_sub <- BM_DT[Date >= min(nav_dates) & Date <= max(nav_dates)]
bm_ret_col <- if ("BM_Ret" %in% names(bm_sub)) "BM_Ret" else
              intersect(c("Ret","benchmark_ret"), names(bm_sub))[1]
bm_xts <- xts(as.numeric(bm_sub[[bm_ret_col]]), order.by = bm_sub$Date)
bm_xts <- bm_xts[!is.na(bm_xts)]

# holdings log (target weights per exec date)
HOLDINGS_LOG <- targets[, .(Exec_Date = exec_date, Ticker, Weight, Score, target_weight = Weight)]
PORTFOLIO_LOG <- data.table(Signal_Date = sort(unique(targets$sig_date)),
                            Exec_Date = exec_dates[match(sort(unique(targets$sig_date)),
                                                         exec_map$sig_date)])

sim_result <- list(
  strategy_xts  = net_xts,             # daily NET return (Return.portfolio-derived)
  DAILY_NAV_DT  = DAILY_NAV_DT,
  bm_xts        = bm_xts,
  HOLDINGS_LOG  = list(HOLDINGS_LOG),
  PORTFOLIO_LOG = PORTFOLIO_LOG
)

strategy_spec <- list(
  strategy_id   = "TRENDED_MOM_KR",
  name          = "Trended Momentum (KR PoC)",
  signal        = "PRET(t-11..t-1) double-sorted with TC = R^2(price~date, 11m, >=200d); top PRET ∩ top TC quintile",
  weight_method = "equal_weight (paper EW long leg)",
  universe      = "KOSPI200 ∪ KOSDAQ150",
  rebalance     = "monthly",
  cost_bps      = COST_BPS,
  max_holdings  = MAX_N,
  liq_threshold = LIQ_THRESHOLD,
  paper         = "Cai-Li-Keasey 2024 SSRN 4740445"
)

saveRDS(list(sim_result = sim_result, strategy_spec = strategy_spec,
             targets = targets, COST_BPS = COST_BPS),
        file.path(OUT_DIR, "sim_result.rds"))
cat(sprintf("[run_all] DONE. NAV days: %d (%s .. %s) | net total ret: %.1f%% | avg turnover/rebal: %.2f\n",
            length(nav_net), min(nav_dates), max(nav_dates),
            (tail(nav_net,1)-1)*100, mean(turn)))
