# =============================================================================
# trackv_engine.R — Track V variation measurement engine (Cycle 1b, prereg FROZEN)
#
# Single engine for ALL 38 preregistered runs (prereg_variations.json):
#   selection rules (top-N / banding / smoothing / quarterly / liquidity floor)
#   -> PerformanceAnalytics::Return.portfolio (NO self-synthesized compounding)
#   -> v2.4_kr_retail_15bps DELTA cost: cost_t = 0.0015 * sum|d weight notional|
#      (buy leg + sell leg each 15bps, holding continuation netted, initial
#       entry = full buy leg; drift-aware via Return.portfolio BOP/EOP weights)
#   -> contract build_benchmark_compare for Portfolio_Alpha_t_NW_lag3 / IR.
#
# Weight timing (empirically verified, probe_env.R): weights indexed at signal
# month-end t apply to the NEXT return row (realization month-end t+1) —
# the b1-verified interleaved construction. PIT-safe (t-1 information only).
#
# metric_type = "canonical_screen" for every number produced here.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
}))

COST_ONEWAY <- 0.0015   # 15bps per leg (v2.4 delta: buys and sells each charged)

# ---- smoothing: 3m mean of score per ticker on the signal-date grid ----
#   (calendar-grid aware: missing months stay NA; min 2 non-NA of {t, t-1, t-2})
tv_smooth_scores <- function(S) {
  grid <- sort(unique(S$Date))
  gidx <- data.table(Date = grid, gi = seq_along(grid))
  X <- merge(S, gidx, by = "Date")
  full <- CJ(gi = gidx$gi, Ticker = unique(X$Ticker))
  full <- merge(full, X[, .(gi, Ticker, score)], by = c("gi", "Ticker"), all.x = TRUE)
  setorder(full, Ticker, gi)
  full[, s1 := shift(score, 1L), by = Ticker]
  full[, s2 := shift(score, 2L), by = Ticker]
  m <- as.matrix(full[, .(score, s1, s2)])
  nv <- rowSums(is.finite(m))
  sm <- rowSums(m, na.rm = TRUE) / nv
  full[, score_s := ifelse(nv >= 2L, sm, NA_real_)]
  out <- merge(X, full[, .(gi, Ticker, score_s)], by = c("gi", "Ticker"), all.x = TRUE)
  out[, gi := NULL]
  out
}

# ---- holdings schedule (sequential; banding needs incumbent state) ----
# S: data.table(Date, Ticker, score [, N] [, adv] [, ret_ok])
# cfg: list(n_fixed=NULL, band=NULL ("number"|"mult:<x>"), smooth=FALSE,
#           liq_floor=NULL, quarterly=FALSE)
# ret_ok: TRUE if forward return exists at selection (driver-identical drop rule).
tv_build_holdings <- function(S, cfg) {
  S <- copy(S)
  if (isTRUE(cfg$smooth)) {
    S <- tv_smooth_scores(S)
    S <- S[is.finite(score_s)]
    S[, score_use := score_s]
  } else S[, score_use := score]
  if (!is.null(cfg$liq_floor)) {
    stopifnot("adv" %in% names(S))
    S <- S[!is.na(adv) & adv >= cfg$liq_floor]
  }
  rb_dates <- sort(unique(S$Date))
  if (isTRUE(cfg$quarterly)) rb_dates <- rb_dates[as.integer(format(rb_dates, "%m")) %in% c(3L, 6L, 9L, 12L)]
  has_N <- "N" %in% names(S)
  held <- character(0)
  out <- vector("list", length(rb_dates))
  for (i in seq_along(rb_dates)) {
    d <- rb_dates[i]
    cs <- S[Date == d & is.finite(score_use)]
    if (nrow(cs) < 10L) next
    setorder(cs, -score_use, Ticker)             # deterministic tie-break
    cs[, rnk := .I]
    N_native <- if (has_N) as.integer(cs$N[1]) else NA_integer_
    N_t <- if (!is.null(cfg$n_fixed)) cfg$n_fixed else N_native
    if (!is.finite(N_t) || N_t < 1L) next
    N_t <- min(N_t, nrow(cs))
    if (!is.null(cfg$band)) {
      band_t <- if (is.character(cfg$band) && startsWith(cfg$band, "mult:")) {
        as.integer(ceiling(as.numeric(sub("mult:", "", cfg$band)) * N_t))
      } else as.integer(cfg$band)
      kept <- cs[Ticker %in% held & rnk <= band_t]
      setorder(kept, rnk)
      if (nrow(kept) > N_t) kept <- kept[1:N_t]
      n_new <- N_t - nrow(kept)
      newc <- cs[!(Ticker %in% kept$Ticker)]
      setorder(newc, rnk)
      sel <- rbind(kept, head(newc, n_new))
    } else {
      sel <- head(cs, N_t)
    }
    if ("ret_ok" %in% names(sel)) sel <- sel[ret_ok == TRUE]   # driver drop rule
    if (nrow(sel) < 2L) next
    held <- sel$Ticker
    out[[i]] <- data.table(Date = d, Ticker = sel$Ticker, w = 1 / nrow(sel))
  }
  rbindlist(Filter(Negate(is.null), out))
}

# ---- run: holdings -> Return.portfolio -> v2.4 delta net series ----
# H: holdings (Date=sig month-end label, Ticker, w)
# RET: data.table(Date(sig grid), Ticker, ret_fwd, r_idx) — forward 1M return of
#      month following Date, realized at r_idx. Must cover ALL months (for drift).
# Returns list(series=data.table(Date=r_idx, ym, gross, traded, cost, net),
#              diag=list(avg_n, n_rebalances, na_fill_cells, na_fill_share))
tv_run_portfolio <- function(H, RET) {
  stopifnot(nrow(H) > 0)
  tks <- sort(unique(H$Ticker))
  rb  <- sort(unique(H$Date))
  grid <- sort(unique(RET$Date))
  grid <- grid[grid >= min(rb)]                 # months from first rebalance
  R <- RET[Ticker %in% tks & Date %in% grid, .(Date, Ticker, ret_fwd, r_idx)]
  # full month x ticker matrix (NA -> 0, counted below for held cells only)
  Rw <- dcast(R, r_idx ~ Ticker, value.var = "ret_fwd")
  miss_tk <- setdiff(tks, names(Rw))
  for (tk in miss_tk) Rw[, (tk) := NA_real_]
  setcolorder(Rw, c("r_idx", tks))
  rmat <- as.matrix(Rw[, -1, with = FALSE])
  # held-cell NA accounting: which names are held during return row m?
  #   holding period of rebalance k = return rows in (rb_k, next_rb_k]
  ridx <- Rw$r_idx
  rb_map <- findInterval(as.numeric(ridx) - 0.5, as.numeric(rb))  # row m belongs to rebalance rb_map[m]
  na_cells <- 0L; held_cells <- 0L
  Hl <- split(H$Ticker, H$Date)
  for (m in seq_along(ridx)) {
    k <- rb_map[m]
    if (k < 1L) next
    hn <- Hl[[as.character(rb[k])]]
    if (is.null(hn)) next
    held_cells <- held_cells + length(hn)
    na_cells <- na_cells + sum(is.na(rmat[m, hn]))
  }
  rmat[is.na(rmat)] <- 0
  Rx <- xts(rmat, order.by = ridx)
  Wd <- dcast(H, Date ~ Ticker, value.var = "w", fill = 0)
  for (tk in setdiff(tks, names(Wd))) Wd[, (tk) := 0]
  setcolorder(Wd, c("Date", tks))
  Wx <- xts(as.matrix(Wd[, -1, with = FALSE]), order.by = Wd$Date)
  pf <- Return.portfolio(R = Rx, weights = Wx, verbose = TRUE)
  gross <- pf$returns
  bop <- pf$BOP.Weight; eop <- pf$EOP.Weight
  nT <- nrow(gross)
  traded <- numeric(nT)
  traded[1] <- sum(abs(as.numeric(bop[1, ])))   # initial entry = full buy leg (=1)
  if (nT > 1) for (m in 2:nT) traded[m] <- sum(abs(as.numeric(bop[m, ]) - as.numeric(eop[m - 1, ])))
  series <- data.table(Date = index(gross), gross = as.numeric(gross), traded = traded)
  series[, cost := traded * COST_ONEWAY]        # v2.4 delta: 15bps per traded leg unit
  series[, net := gross - cost]
  series[, ym := format(Date, "%Y-%m")]
  avg_n <- mean(H[, .N, by = Date]$N)
  list(series = series,
       diag = list(avg_n = round(avg_n, 2), n_rebalances = length(rb),
                   na_fill_cells = na_cells,
                   na_fill_share = if (held_cells > 0) round(na_cells / held_cells, 5) else NA_real_))
}

# ---- windowed metrics (PerformanceAnalytics standard + contract NW t) ----
tv_metrics <- function(series, bm_m, run_id, windows = list(
    FULL = c("1900-01-01", "2100-01-01"),
    IS   = c("1900-01-01", "2018-12-31"),
    OOS  = c("2019-01-01", "2100-01-01"),
    R2017 = c("2017-01-01", "2100-01-01"))) {
  s <- merge(series, bm_m[, .(ym, BM_Ret_m)], by = "ym", all.x = TRUE)
  setorder(s, Date)
  n_bm_na <- s[, sum(is.na(BM_Ret_m))]
  s[is.na(BM_Ret_m), BM_Ret_m := 0]
  out <- list()
  for (wn in names(windows)) {
    lo <- as.Date(windows[[wn]][1]); hi <- as.Date(windows[[wn]][2])
    w <- s[Date >= lo & Date <= hi]
    if (nrow(w) < 12L) { out[[wn]] <- list(n_months = nrow(w)); next }
    nx <- xts(w$net, order.by = w$Date)
    gx <- xts(w$gross, order.by = w$Date)
    act <- w$net - w$BM_Ret_m
    prt <- data.table(date = w$Date, ret_net = w$net, frequency = "monthly")
    brt <- data.table(date = w$Date, benchmark_ret = w$BM_Ret_m, benchmark_id = "KOSPI200")
    bc <- tryCatch(build_benchmark_compare(prt, brt, run_id = paste0(run_id, "_", wn),
                                           strategy_id = run_id, annualization_factor = 12),
                   error = function(e) NULL)
    getbc <- function(nm) {
      if (is.null(bc)) return(NA_real_)
      v <- as.data.table(bc)[metric_name == nm, active_value]
      if (length(v) == 0) NA_real_ else as.numeric(v[1])
    }
    out[[wn]] <- list(
      n_months   = nrow(w),
      sr_net     = round(as.numeric(SharpeRatio.annualized(nx, Rf = 0, scale = 12)), 4),
      sr_gross   = round(as.numeric(SharpeRatio.annualized(gx, Rf = 0, scale = 12)), 4),
      cagr_net   = round(as.numeric(Return.annualized(nx, scale = 12)), 5),
      mdd_net    = round(as.numeric(maxDrawdown(nx)), 5),
      calmar     = round(as.numeric(Return.annualized(nx, scale = 12)) /
                         max(as.numeric(maxDrawdown(nx)), 1e-9), 4),
      to_oneway_ann   = round(mean(w$traded / 2) * 12, 4),   # one-way TO (B0 convention: (buys+sells)/2)
      to_traded_ann   = round(mean(w$traded) * 12, 4),       # both-legs traded (cost base)
      cost_ann_pct    = round(mean(w$cost) * 12 * 100, 4),   # = 15bps x to_traded_ann
      gross_ann       = round(as.numeric(Return.annualized(gx, scale = 12)), 5),
      active_sr  = round(mean(act) / sd(act) * sqrt(12), 4),
      port_t_nw  = round(getbc("Portfolio_Alpha_t_NW_lag3"), 4),
      net_ir     = round(getbc("Information_Ratio"), 4),
      alpha_ann  = round(getbc("Alpha_Annualized"), 5)
    )
  }
  attr(out, "n_bm_na") <- n_bm_na
  out
}

# ---- one preregistered run ----
tv_run_variant <- function(run_id, S, RET, bm_m, cfg) {
  H <- tv_build_holdings(S, cfg)
  if (nrow(H) == 0) return(list(run_id = run_id, error = "no holdings"))
  pr <- tv_run_portfolio(H, RET)
  met <- tv_metrics(pr$series, bm_m, run_id)
  list(run_id = run_id, cfg = cfg, metric_type = "canonical_screen",
       windows = met, diag = pr$diag, series = pr$series)
}

# ---- driver-replication mode (diagnostic ONLY — base reproduction check) ----
# Replicates driver_str1715v2_lo.R / driver_lo_screen.R verbatim construction:
#   same-grid dcast (weights AND returns both indexed at ret_date) +
#   net = gross - oneway_turnover * 15bps (target-to-target |dw|/2, to[1]=1).
# NOT part of n_trials (engine diagnostic, not a strategy candidate).
tv_repro_driver <- function(S, RET, n_cap = NULL) {
  has_N <- "N" %in% names(S)
  sig_dates <- sort(unique(S$Date))
  L <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    fd <- S[Date == d & is.finite(score)]
    if (nrow(fd) < 10L) next
    n_sel <- if (!is.null(n_cap)) n_cap else if (has_N) as.integer(fd$N[1]) else max(5L, ceiling(nrow(fd) * 0.1))
    n_sel <- min(n_sel, nrow(fd))
    setorder(fd, -score)
    sel <- head(fd, n_sel)
    mp <- RET[.(sel$Ticker, d), .(Ticker, ret_fwd, r_idx), nomatch = 0L]
    mp <- mp[is.finite(ret_fwd) & !is.na(r_idx)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]
    L[[i]] <- mp[, .(Date = r_idx, Ticker, ret = ret_fwd, w)]
  }
  lg <- rbindlist(Filter(Negate(is.null), L))
  Rw <- dcast(lg, Date ~ Ticker, value.var = "ret", fill = 0)
  Ww <- dcast(lg, Date ~ Ticker, value.var = "w",   fill = 0)
  Rx <- xts(as.matrix(Rw[, -1, with = FALSE]), order.by = Rw$Date)
  Wx <- xts(as.matrix(Ww[, -1, with = FALSE]), order.by = Ww$Date)
  gross_x <- suppressWarnings(Return.portfolio(R = Rx, weights = Wx))
  to_mat <- as.matrix(Ww[, -1, with = FALSE])
  to_vec <- numeric(nrow(to_mat)); to_vec[1] <- 1.0
  if (nrow(to_mat) >= 2) for (i in 2:nrow(to_mat)) to_vec[i] <- sum(abs(to_mat[i, ] - to_mat[i - 1, ])) / 2
  dt <- merge(data.table(Date = index(gross_x), gross = as.numeric(gross_x)),
              data.table(Date = Ww$Date, turnover = to_vec), by = "Date", all.x = TRUE)
  dt[is.na(turnover), turnover := 0]
  dt[, Strategy_Ret := gross - turnover * 0.0015]
  setorder(dt, Date)
  nx <- xts(dt$Strategy_Ret, order.by = dt$Date)
  list(sharpe = round(as.numeric(SharpeRatio.annualized(nx, Rf = 0, scale = 12)), 4),
       cagr = round(as.numeric(Return.annualized(nx, scale = 12)), 5),
       mdd = round(as.numeric(maxDrawdown(nx)), 5),
       n_months = nrow(dt))
}

cat("[trackv_engine] loaded\n")
