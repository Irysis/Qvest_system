# =============================================================================
# Phase 1b — PREDICTIVE-GATE inverse-ETF hedge backtest (clean retry of Phase 1 P2)
#   Gate = Regime Forecaster v1 CHAMPION (.cache/regime_forecast_series.parquet)
#          forecast_regime is the PIT-safe NEXT-month prediction (ym = target month).
#   P3a: -2x KODEX 252670, CRISIS-gated, 2016+ window, w_h in {0.05,0.10,0.15}
#   P3b: -1x KODEX 114800, CRISIS-gated, 2009+ window, same grid (continuity/robustness)
#   ALL policies ex-2026 (cut 2025-12).
#
#   Rules: Return.portfolio combination; build_bt_result/audit/save (metric_type label);
#          cost = hedge self-trade |Δw_h|×15bps only (ETF internal drag in series);
#          PIT: forecast_regime[ym==m] applied to return-month m directly (NO extra shift).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
arrow::set_io_thread_count(2); setDTthreads(1)
options(stringsAsFactors = FALSE)

PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT  <- file.path(PROJ, "04_Research/asset_allocation/inverse_hedge_phase1b")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJ, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJ, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJ, "02_Infrastructure/contracts/save_bt_result.R"))

`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || all(is.na(a))) b else a
EX2026_CUT <- "2025-12"   # all policies ex-2026

# ---------------------------------------------------------------------------
# 1. Book + benchmark (Phase 1 aligned inputs reuse)
# ---------------------------------------------------------------------------
ai <- fread(file.path(PROJ, "04_Research/asset_allocation/inverse_hedge_phase1/aligned_inputs.csv"))
ai <- ai[, .(ym, regime_book = regime, ret_book, bm_ret, hedge_avail_1x = hedge_avail)]
ai[, ym_date := as.Date(paste0(ym, "-01"))]
setorder(ai, ym)

# ---------------------------------------------------------------------------
# 2. Forecaster gate (CHAMPION). PIT: ym = forecast TARGET month -> use directly.
# ---------------------------------------------------------------------------
fc <- as.data.table(read_parquet(file.path(PROJ, ".cache/regime_forecast_series.parquet")))
fc[, ym := paste0(substr(ym,1,4), "-", substr(ym,5,6))]   # 200912 -> 2009-12
ai <- merge(ai, fc[, .(ym, forecast_regime)], by = "ym", all.x = TRUE)
setorder(ai, ym)
# Risk-off gate = forecast_regime == CRISIS (champion realizes only {RISK_ON,NEUTRAL,CAUTION,CRISIS};
#   no RISK_OFF in data; CRISIS is the defensive argmax state).
ai[, gate_on := !is.na(forecast_regime) & forecast_regime == "CRISIS"]

# ---------------------------------------------------------------------------
# 3. Hedge ETF series -> monthly compound on book grid
# ---------------------------------------------------------------------------
compound_monthly <- function(csv_path, date_col, ret_col) {
  d <- fread(csv_path)
  d[[date_col]] <- as.Date(d[[date_col]])
  d <- d[!is.na(get(ret_col))]
  d[, ym := format(get(date_col), "%Y-%m")]
  d[, .(ret_h = prod(1 + get(ret_col)) - 1), by = ym]   # daily compound within month
}
h2x <- compound_monthly(file.path(PROJ, ".cache/kodex_inverse2x_252670.csv"), "Date", "Ret_Inv2x")
h1x <- compound_monthly(file.path(PROJ, ".cache/kodex_inverse_114800.csv"),   "Date", "Ret_Inv")
setnames(h2x, "ret_h", "ret_h2x"); setnames(h1x, "ret_h", "ret_h1x")
ai <- merge(ai, h2x, by = "ym", all.x = TRUE)
ai <- merge(ai, h1x, by = "ym", all.x = TRUE)
setorder(ai, ym)

# ---------------------------------------------------------------------------
# 4. Gate predictive-fit pre-check (does CRISIS forecast predict forward weakness?)
# ---------------------------------------------------------------------------
gate_fit <- function(dt, ret_col, label) {
  d <- dt[!is.na(get(ret_col))]
  on  <- d[gate_on == TRUE]
  off <- d[gate_on == FALSE]
  list(
    label = label, n_total = nrow(d), n_on = nrow(on), n_off = nrow(off),
    mean_fwd_on  = mean(on[[ret_col]]),  mean_fwd_off = mean(off[[ret_col]]),
    neg_share_on = mean(on[[ret_col]] < 0), neg_share_off = mean(off[[ret_col]] < 0),
    min_on = if (nrow(on)>0) min(on[[ret_col]]) else NA,
    # hit: did gate-on months catch the worst months? share of bottom-decile months that are gated-on
    worst_decile_capture = {
      thr <- quantile(d[[ret_col]], 0.10)
      worst <- d[get(ret_col) <= thr]
      mean(worst$gate_on)
    }
  )
}

# ---------------------------------------------------------------------------
# 5. Backtest engine: Return.portfolio (book + hedge sleeve), monthly rebal,
#    hedge self-trade cost |Δw_h|×15bps. Long-only each leg, Σw=1.
# ---------------------------------------------------------------------------
COST_BPS <- 15

run_policy <- function(dt, ret_hedge_col, w_h_target, gated, win_start, policy_id) {
  d <- copy(dt)
  d <- d[ym <= EX2026_CUT]                                 # ex-2026
  d <- d[ym >= win_start]                                  # instrument window
  d <- d[!is.na(ret_book) & !is.na(get(ret_hedge_col))]    # require both legs
  setorder(d, ym)

  # weight schedule (decided at month start from PIT-safe forecast for this month)
  if (gated) d[, w_h := ifelse(gate_on, w_h_target, 0)] else d[, w_h := w_h_target]
  d[, w_book := 1 - w_h]

  # Return.portfolio: two-asset MONTHLY REBALANCE to target each month (no drift).
  #   PerformanceAnalytics convention: a weights row dated t is the rebalance applied at
  #   t, governing the NEXT period's return; RP also drops the first input period. To get a
  #   full-length, DATE-ALIGNED series with beginning-of-period target weights, we run RP on
  #   each month independently (1-row weight applied to that month's 2-asset returns). For a
  #   monthly rebalance this equals the standard per-period weighted return (no multi-month
  #   drift), and uses Return.portfolio (PerformanceAnalytics) for the combination — not a
  #   hand-rolled (w*r) sum. We verify row-for-row date alignment via merge below.
  R <- xts(cbind(book = d$ret_book, hedge = d[[ret_hedge_col]]), order.by = d$ym_date)
  pg <- numeric(nrow(d))
  for (i in seq_len(nrow(d))) {
    Ri <- R[i, ]
    Wi <- xts(matrix(c(d$w_book[i], d$w_h[i]), nrow = 1, dimnames = list(NULL, c("book","hedge"))),
              order.by = index(Ri))
    # single-period: supply weights dated one step before the return so RP returns that period
    Wi_lag <- Wi; index(Wi_lag) <- index(Ri) - 1
    Rseq <- rbind(Ri, Ri)                       # 2-row so RP yields >=1 output row
    index(Rseq)[2] <- index(Ri) + 1
    pgi <- Return.portfolio(Rseq, weights = Wi_lag, verbose = FALSE)
    pg[i] <- as.numeric(pgi[1])
  }
  port_gross <- pg

  # ALIGNMENT GUARD: when w_h==0 the portfolio return MUST equal the book return exactly.
  zero_h <- d$w_h == 0
  if (any(zero_h)) {
    align_err <- max(abs(port_gross[zero_h] - d$ret_book[zero_h]))
    if (align_err > 1e-9) stop(sprintf("[run_policy %s] ALIGNMENT FAIL: w_h=0 port!=book, max err=%.3e", policy_id, align_err))
  }

  # hedge self-trade cost: |Δw_h| each rebalance × 15bps (one-way on the traded notional delta)
  w_h_vec <- as.numeric(d$w_h)
  dwh <- abs(diff(c(0, w_h_vec)))           # first period trades from 0 to w_h[1]
  cost_vec <- dwh * (COST_BPS / 1e4)
  port_net_ret <- port_gross - cost_vec

  # build monthly NAV
  navd <- data.table(Date = d$ym_date,
                     NAV       = cumprod(1 + port_net_ret),
                     NAV_gross = cumprod(1 + port_gross))
  strat_xts <- xts(port_net_ret, order.by = d$ym_date)
  bm_xts    <- xts(d$bm_ret,     order.by = d$ym_date)

  sim_result <- list(
    DAILY_NAV_DT = navd,
    strategy_xts = strat_xts,
    bm_xts       = bm_xts,
    HOLDINGS_LOG = NULL,
    PORTFOLIO_LOG = NULL
  )
  strategy_spec <- list(
    strategy_name = policy_id,
    description = sprintf("Predictive-gate inverse-ETF hedge: %s, w_h=%.2f, gated=%s, win>=%s, ex-2026",
                          ret_hedge_col, w_h_target, gated, win_start),
    universe = "STR_1715_AR_on_M4_R05_overlay_PG2 (book) + KODEX inverse sleeve",
    rebalance = "monthly",
    lookahead_prevention = "forecast_regime[ym==m] = NEXT-month prediction emitted at m-1 from <=m-1 data (Regime Forecaster v1 walk-forward); applied to return-month m directly, no extra shift. ETF daily returns compounded within month (no cross-month leak). Beginning-of-period weights via Return.portfolio.",
    survivorship_bias_control = "N/A — two-instrument sleeve (book NAV + single ETF); no cross-sectional universe selection. ETF series are realized listed prices.",
    pit_checklist_reference = "C1-C15 (.claude/rules/pit.md); C5 overlay t-1 satisfied by forecast emit-at-m-1; C9 dd-lag N/A (no DD overlay here)."
  )

  bt <- build_bt_result(
    sim_result, strategy_spec,
    run_id = paste0(policy_id, "_", format(Sys.time(), "%Y%m%d%H%M%S")),
    strategy_id = policy_id, strategy_version = "phase1b",
    benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
    transaction_cost_bps = COST_BPS, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "book_plus_inverse_sleeve",
    code_version = "phase1b_run_v1", created_by_agent = "Q-Lead"
  )
  bt <- audit_bt_result(bt)

  # diagnostics for frontier analysis
  diag <- data.table(
    ym = d$ym, ret_book = d$ret_book, ret_hedge = d[[ret_hedge_col]],
    w_h = d$w_h, gate_on = d$gate_on, port_gross = as.numeric(port_gross),
    cost = cost_vec, port_net = port_net_ret, bm_ret = d$bm_ret,
    forecast_regime = d$forecast_regime
  )
  list(bt = bt, diag = diag, navd = navd, n_months = nrow(d),
       mean_w_h = mean(w_h_vec), n_gate_on = sum(d$gate_on))
}

# headline extractor from bt_result metrics
hl <- function(bt) {
  m <- bt$metrics
  getv <- function(nm) { v <- m[metric_name == nm]$metric_value; if (length(v)) as.numeric(v[1]) else NA_real_ }
  data.table(
    CAGR   = getv("CAGR"),
    Sharpe = getv("Sharpe"),
    MDD    = getv("MDD"),
    Calmar = getv("Calmar"),
    Vol    = getv("Annualized_Volatility")
  )
}

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------
results <- list()

# ---- Gate fit pre-check (over the -1x window 2009-09+ ex-2026, and -2x window) ----
ai_1xwin <- ai[ym >= "2009-09" & ym <= EX2026_CUT & !is.na(ret_h1x)]
ai_2xwin <- ai[ym >= "2016-09" & ym <= EX2026_CUT & !is.na(ret_h2x)]
gf <- list(
  book_fwd_1xwin = gate_fit(ai_1xwin, "ret_book", "book fwd (2009-09+ -1x win)"),
  bm_fwd_1xwin   = gate_fit(ai_1xwin, "bm_ret",   "bm fwd (2009-09+ -1x win)"),
  book_fwd_2xwin = gate_fit(ai_2xwin, "ret_book", "book fwd (2016-09+ -2x win)"),
  bm_fwd_2xwin   = gate_fit(ai_2xwin, "bm_ret",   "bm fwd (2016-09+ -2x win)")
)
write_json(gf, file.path(OUT, "gate_fit_precheck.json"), auto_unbox = TRUE, pretty = TRUE, digits = 5)
cat("\n========== GATE PREDICTIVE-FIT PRE-CHECK ==========\n")
for (k in names(gf)) {
  g <- gf[[k]]
  cat(sprintf("[%s] n=%d on=%d off=%d | fwd mean ON=%+.4f OFF=%+.4f | neg-share ON=%.2f OFF=%.2f | worst-decile capture=%.2f | min_on=%+.3f\n",
              g$label, g$n_total, g$n_on, g$n_off, g$mean_fwd_on, g$mean_fwd_off,
              g$neg_share_on, g$neg_share_off, g$worst_decile_capture, g$min_on))
}

# ---- P0 baseline (book 100%), measured on BOTH windows for fair bleed comparison ----
# P0 on -2x window (2016-09+) and -1x window (2009-09+), ex-2026
P0_2x <- run_policy(ai, "ret_h2x", 0.0, gated = TRUE, win_start = "2016-09", policy_id = "P0_book100_2xwin")
P0_1x <- run_policy(ai, "ret_h1x", 0.0, gated = TRUE, win_start = "2009-09", policy_id = "P0_book100_1xwin")
results[["P0_book100_2xwin"]] <- P0_2x
results[["P0_book100_1xwin"]] <- P0_1x

# ---- P3a: -2x, CRISIS-gated, 2016-09+ ----
for (w in c(0.05, 0.10, 0.15)) {
  id <- sprintf("P3a_inv2x_gated_%02d", round(w*100))
  results[[id]] <- run_policy(ai, "ret_h2x", w, gated = TRUE, win_start = "2016-09", policy_id = id)
}
# ---- P3b: -1x, CRISIS-gated, 2009-09+ ----
for (w in c(0.05, 0.10, 0.15)) {
  id <- sprintf("P3b_inv1x_gated_%02d", round(w*100))
  results[[id]] <- run_policy(ai, "ret_h1x", w, gated = TRUE, win_start = "2009-09", policy_id = id)
}

# ---- save artifacts + headline table ----
headline <- rbindlist(lapply(names(results), function(id) {
  r <- results[[id]]
  cbind(data.table(policy = id, n_months = r$n_months, mean_w_h = round(r$mean_w_h,4),
                   n_gate_on = r$n_gate_on), hl(r$bt))
}))
fwrite(headline, file.path(OUT, "summary_headline.csv"))

cat("\n========== HEADLINE (ex-2026, net, in-window) ==========\n")
print(headline)

# save each bt_result + diag
for (id in names(results)) {
  r <- results[[id]]
  d <- file.path(OUT, id); dir.create(d, showWarnings = FALSE)
  saveRDS(r$bt, file.path(d, "bt_result.rds"))
  fwrite(r$diag, file.path(d, "diag_monthly.csv"))
  tryCatch(save_bt_result(r$bt, d, save_xlsx = FALSE),
           error = function(e) cat(sprintf("[save_bt_result skip %s] %s\n", id, conditionMessage(e))))
}

# ---- crisis-window conditional + V-recovery give-back (AX-001) ----
# in-window crisis windows (book era): 2018Q4, 2020-COVID, 2022-bear
crisis_windows <- list(
  "2018Q4"      = c("2018-10","2018-12"),
  "2020_COVID"  = c("2020-02","2020-05"),
  "2022_bear"   = c("2022-01","2022-10")
)
crisis_tbl <- rbindlist(lapply(names(results), function(id) {
  r <- results[[id]]; dg <- r$diag
  rbindlist(lapply(names(crisis_windows), function(cw) {
    w <- crisis_windows[[cw]]
    sub <- dg[ym >= w[1] & ym <= w[2]]
    if (nrow(sub) == 0) return(NULL)
    base_cum <- prod(1 + sub$ret_book) - 1
    pol_cum  <- prod(1 + sub$port_net) - 1
    # within-window MDD (net portfolio) vs book-only
    mdd <- function(rv) { nv <- cumprod(1+rv); min(nv/cummax(nv)-1) }
    data.table(policy = id, window = cw, n = nrow(sub),
               book_cum = base_cum, policy_cum = pol_cum,
               protection_pp = (pol_cum - base_cum)*100,
               book_mdd = mdd(sub$ret_book), policy_mdd = mdd(sub$port_net),
               mdd_relief_pp = (mdd(sub$port_net) - mdd(sub$ret_book))*100,
               n_gate_on = sum(sub$gate_on))
  }))
}))
fwrite(crisis_tbl, file.path(OUT, "crisis_windows.csv"))

# V-recovery give-back 2020-03 -> 2020-08
recov_tbl <- rbindlist(lapply(names(results), function(id) {
  r <- results[[id]]; dg <- r$diag
  sub <- dg[ym >= "2020-03" & ym <= "2020-08"]
  if (nrow(sub) == 0) return(NULL)
  data.table(policy = id, window = "2020-03_to_08", n = nrow(sub),
             book_cum = prod(1+sub$ret_book)-1, policy_cum = prod(1+sub$port_net)-1,
             giveback_pp = (prod(1+sub$port_net)-1 - (prod(1+sub$ret_book)-1))*100)
}))
fwrite(recov_tbl, file.path(OUT, "recovery_giveback.csv"))

cat("\n========== CRISIS WINDOWS (AX-001) ==========\n"); print(crisis_tbl)
cat("\n========== V-RECOVERY GIVE-BACK ==========\n"); print(recov_tbl)

# ---- OOS retention: IS/OOS split of net Sharpe per policy (50/50 by month) ----
oos_tbl <- rbindlist(lapply(names(results), function(id) {
  r <- results[[id]]; dg <- r$diag
  n <- nrow(dg); if (n < 24) return(NULL)
  k <- floor(n/2)
  shp <- function(rv) if (sd(rv)>0) mean(rv)/sd(rv)*sqrt(12) else NA_real_
  is_s <- shp(dg$port_net[1:k]); oos_s <- shp(dg$port_net[(k+1):n])
  data.table(policy = id, n = n, IS_sharpe = is_s, OOS_sharpe = oos_s,
             oos_retention = if (!is.na(is_s) && is_s != 0) oos_s/is_s else NA_real_)
}))
fwrite(oos_tbl, file.path(OUT, "oos_retention.csv"))
cat("\n========== OOS RETENTION (50/50 split) ==========\n"); print(oos_tbl)

# ---------------------------------------------------------------------------
# 6. ROBUSTNESS: leave-COVID-out. Does the MDD/Calmar win survive without the single
#    lucky 2020-03 gated hedge gain? Recompute headline on diag dropping 2020-02..2020-08.
# ---------------------------------------------------------------------------
shp <- function(rv) if (sd(rv)>0) mean(rv)/sd(rv)*sqrt(12) else NA_real_
mddv <- function(rv){ nv<-cumprod(1+rv); min(nv/cummax(nv)-1) }
cagrv <- function(rv){ prod(1+rv)^(12/length(rv))-1 }
loco_tbl <- rbindlist(lapply(names(results), function(id) {
  dg <- results[[id]]$diag
  full <- dg$port_net
  xcov <- dg[!(ym >= "2020-02" & ym <= "2020-08")]$port_net   # drop COVID crash+rebound
  data.table(policy = id,
             Sharpe_full = shp(full), Sharpe_exCOVID = shp(xcov),
             MDD_full = mddv(full),   MDD_exCOVID = mddv(xcov),
             Calmar_full = cagrv(full)/abs(mddv(full)),
             Calmar_exCOVID = cagrv(xcov)/abs(mddv(xcov)))
}))
fwrite(loco_tbl, file.path(OUT, "robustness_leave_covid_out.csv"))
cat("\n========== ROBUSTNESS: LEAVE-COVID-OUT (2020-02..08 dropped) ==========\n")
print(loco_tbl)

# ---------------------------------------------------------------------------
# 7. SECONDARY DIAGNOSTIC (metric_type=proxy): proxy -2x over FULL 1990+ window,
#    CRISIS-gated, to see whether gate-conditional hedge ever delivered robust
#    protection across 2000/2008 crises (which real ETFs cannot test). NOT capital-grade.
# ---------------------------------------------------------------------------
prox <- as.data.table(read_parquet(file.path(PROJ, ".cache/inverse2x_proxy.parquet")))
prox[, Date := as.Date(Date)]
prox[, ym := format(Date, "%Y-%m")]
proxm <- prox[!is.na(r_inv2x_proxy), .(ret_h2x_proxy = prod(1 + r_inv2x_proxy) - 1), by = ym]
ai_px <- merge(ai, proxm, by = "ym", all.x = TRUE)
setorder(ai_px, ym)
P3prox <- tryCatch(
  run_policy(ai_px, "ret_h2x_proxy", 0.15, gated = TRUE, win_start = "2004-02", policy_id = "P3prox_inv2x_gated_15_PROXY"),
  error = function(e) { cat("[proxy run skip]", conditionMessage(e), "\n"); NULL })
if (!is.null(P3prox)) {
  P0prox <- run_policy(ai_px, "ret_h2x_proxy", 0.0, gated = TRUE, win_start = "2004-02", policy_id = "P0prox_book100_PROXY")
  proxhl <- rbind(
    cbind(data.table(policy="P0prox_book100 (PROXY)", n=P0prox$n_months, n_gate_on=P0prox$n_gate_on), hl(P0prox$bt)),
    cbind(data.table(policy="P3prox_inv2x_gated_15 (PROXY)", n=P3prox$n_months, n_gate_on=P3prox$n_gate_on), hl(P3prox$bt))
  )
  fwrite(proxhl, file.path(OUT, "proxy_fullwindow_diagnostic.csv"))
  d <- file.path(OUT, "P3prox_inv2x_gated_15_PROXY"); dir.create(d, showWarnings=FALSE)
  fwrite(P3prox$diag, file.path(d, "diag_monthly.csv"))
  cat("\n========== PROXY -2x FULL-WINDOW DIAGNOSTIC (metric_type=proxy, ex-2026, gated 15%) ==========\n")
  print(proxhl)
  cat("(NOTE: proxy = -2*futures_beta*r_kospi200 - 114bps/yr; metric_type=proxy, NOT capital-grade.)\n")
}

cat("\n[done] artifacts -> ", OUT, "\n")
