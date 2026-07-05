# run.R — DISCOVERY PROBE: long-side harvest battery (screening-tier, NOT a WT)
#
# MILESTONE QUESTION: does a long-side-harvestable alpha exist in KR large-cap deployment
#   universe (K200 U KQ150, top-N EW long-only, 15bps, monthly)?
#
# Fixed axes: 25 names, long-only w>=0, [0,0.20], Sw=1, K200uKQ150, 15bps, PIT C1-C15.
# canonical measurement ONLY (canonical_screen_bt / build_benchmark_compare). NO proxy hand-calc.
#
# Battery (all long-side lens):
#   A1 tp_upside     (target-price implied upside)          -- untested long-side signal
#   A2 dps_growth    (dividend growth)                       -- untested long-side signal
#   A2b dps_init     (dividend initiation flag)              -- untested long-side signal
#   B  ls_composite  (long-side-realized-alpha-weighted factor composite)  -- novel construction
#      vs  ic_composite (standard full-IC EW composite = score_eff ~0.97 anchor)
#   Controls: dps_yield (tested-dead value level -> must be weak/negative), placebo (random)
#
# Per candidate: full + recent2017 PORT_t (top-25 EW canonical) ; long-side (top-quintile) vs
#   short-side (bottom-quintile) net-active NW-t ; beta-residual net-active t ; placebo ; lag1 PIT.

suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); arrow::set_cpu_count(1)
set.seed(20260705L)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROBE <- file.path(ROOT, "stage_artifacts/probe_longside_harvest_20260705")
PAN  <- file.path(PROBE, "panel")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

NMAX <- 25L; BPS <- 15; LIQ_MIN <- 2e8; PPY <- 12L
REC_FROM <- as.Date("2017-01-01")

# ---- load panel ----
rets  <- as.data.table(read_parquet(file.path(PAN, "returns_monthly.parquet")))     # Date, Ticker, Ret_1m
bench <- as.data.table(read_parquet(file.path(PAN, "benchmark_monthly.parquet")))   # Date, BM_Ret
uni   <- as.data.table(read_parquet(file.path(PAN, "universe_flags.parquet")))      # Date, Ticker, in_univ, adv20, Close, Size
sigc  <- as.data.table(read_parquet(file.path(PAN, "signals_consensus.parquet")))   # Date, Ticker, tp_upside, dps_growth, dps_init, dps_yield
feat  <- as.data.table(read_parquet(file.path(PAN, "features_monthly.parquet")))    # Date, Ticker, <Z cols>

rets[, Date := as.Date(Date)]; bench[, Date := as.Date(Date)]; uni[, Date := as.Date(Date)]
sigc[, Date := as.Date(Date)]; feat[, Date := as.Date(Date)]

# liquidity table for canonical_screen_bt (adv at t = adv20 ending month-end t)
liq <- uni[, .(Date, Ticker, adv = adv20)]

# ================================================================================
# Helpers
# ================================================================================

# canonical top-25 EW long-only bt (contract-grade). scores_dt: Date,Ticker,score (higher=better)
run_canon <- function(scores_dt, tag, from = NULL) {
  d <- copy(scores_dt)[!is.na(score)]
  if (!is.null(from)) d <- d[Date >= from]
  # restrict to universe + valid forward return
  d <- merge(d, uni[, .(Date, Ticker)], by = c("Date","Ticker"))
  canonical_screen_bt(d, rets, bench, top_n = NMAX, cost_bps_oneway = BPS,
                      liq_dt = liq, liq_min = LIQ_MIN,
                      run_id = tag, strategy_id = tag, periods_per_year = PPY)
}

# LONG-SIDE / SHORT-SIDE lens: quantile net-active NW-t (vs benchmark), EW within quantile,
#   liquidity-filtered, gross (attribution lens; cost is second-order for direction diagnosis).
#   q = 5 (quintiles). long = top quintile, short = bottom quintile.
#   Returns list(long_t, short_t, long_mean_ann, short_mean_ann, n).
lens_quantile <- function(scores_dt, q = 5L, from = NULL) {
  d <- merge(copy(scores_dt)[!is.na(score)], uni[, .(Date, Ticker, adv20)], by = c("Date","Ticker"))
  d <- d[is.na(adv20) | adv20 >= LIQ_MIN]
  d <- merge(d, rets, by = c("Date","Ticker"))       # forward Ret_1m
  if (!is.null(from)) d <- d[Date >= from]
  # per-month quantile bucket
  d[, bkt := {
    n <- .N
    if (n < q) rep(NA_integer_, n) else as.integer(cut(frank(score, ties.method="first"),
                                                       breaks = quantile(frank(score, ties.method="first"),
                                                                         probs = seq(0,1,length.out=q+1)),
                                                       include.lowest = TRUE, labels = FALSE))
  }, by = Date]
  # long = top bucket (q), short = bottom bucket (1). EW within bucket.
  longp  <- d[bkt == q, .(pr = mean(Ret_1m)), by = Date]
  shortp <- d[bkt == 1, .(pr = mean(Ret_1m)), by = Date]
  lb <- merge(longp,  bench, by = "Date"); lb[,  act := pr - BM_Ret]
  sb <- merge(shortp, bench, by = "Date"); sb[,  act := pr - BM_Ret]
  list(long_t  = .nw_t_mean(lb$act, 3L),  short_t = .nw_t_mean(sb$act, 3L),
       long_mean_ann  = mean(lb$act) * PPY, short_mean_ann = mean(sb$act) * PPY,
       n = nrow(lb))
}

# BETA-ARTIFACT control: is the top-25 net-active alpha just a market-beta tilt?
#   CAPM regression ret_net ~ benchmark_ret. The INTERCEPT is the beta-neutral monthly alpha
#   (removes the (beta-1)*BM_Ret drift embedded in raw net-active). Report intercept's NW(lag3)
#   HAC t-stat computed directly from the alpha series a_t = ret_net_t - beta*benchmark_ret_t
#   (a_t has the intercept as its mean; NW-t of a_t = HAC t of the CAPM alpha).
beta_resid_t <- function(canon_res) {
  pr <- canon_res$period_returns
  if (is.null(pr) || nrow(pr) < 12) return(list(beta = NA, capm_alpha_ann = NA, capm_alpha_t = NA))
  fit <- stats::lm(ret_net ~ benchmark_ret, data = pr)
  b   <- as.numeric(coef(fit)["benchmark_ret"])
  a0  <- as.numeric(coef(fit)["(Intercept)"])            # monthly beta-neutral alpha
  a_series <- pr$ret_net - b * pr$benchmark_ret          # mean(a_series) == a0
  list(beta = b, capm_alpha_ann = a0 * PPY, capm_alpha_t = .nw_t_mean(a_series, 3L))
}

# PLACEBO: random score, same universe/liquidity, top-25 canonical, PORT_t distribution
placebo_port_t <- function(n_seed = 30L, from = NULL) {
  base <- uni[, .(Date, Ticker)]
  if (!is.null(from)) base <- base[Date >= from]
  ts <- numeric(n_seed)
  for (s in seq_len(n_seed)) {
    set.seed(1000L + s)
    d <- copy(base); d[, score := runif(.N)]
    r <- run_canon(d, sprintf("placebo_%d", s), from = from)
    ts[s] <- r$portfolio_alpha_t_nw_lag3
  }
  ts
}

# small-cap tilt check: median Size (market cap) of held names vs universe median
size_tilt <- function(scores_dt, from = NULL) {
  d <- merge(copy(scores_dt)[!is.na(score)], uni[, .(Date, Ticker, adv20, Size)], by = c("Date","Ticker"))
  d <- d[is.na(adv20) | adv20 >= LIQ_MIN]
  if (!is.null(from)) d <- d[Date >= from]
  setorder(d, Date, -score)
  held <- d[, head(.SD, NMAX), by = Date]
  univ_med <- d[, .(um = median(Size, na.rm=TRUE)), by = Date]
  held_med <- held[, .(hm = median(Size, na.rm=TRUE)), by = Date]
  m <- merge(held_med, univ_med, by = "Date")
  # ratio < 1 => small-cap tilt
  list(med_size_ratio = median(m$hm / m$um, na.rm = TRUE))
}

# ================================================================================
# BATTERY A: consensus long-side signals
# ================================================================================
results <- list()
adv <- list()

candidates <- list(
  A1_tp_upside  = sigc[!is.na(tp_upside),  .(Date, Ticker, score = tp_upside)],
  A2_dps_growth = sigc[!is.na(dps_growth), .(Date, Ticker, score = dps_growth)],
  A2b_dps_init  = sigc[!is.na(dps_init),   .(Date, Ticker, score = as.numeric(dps_init))],
  CTRL_dps_yield= sigc[!is.na(dps_yield),  .(Date, Ticker, score = dps_yield)]   # tested-dead value level
)

for (nm in names(candidates)) {
  sc <- candidates[[nm]]
  full <- run_canon(sc, nm)
  rec  <- run_canon(sc, paste0(nm,"_rec"), from = REC_FROM)
  lens_f <- lens_quantile(sc, q = 5L)
  lens_r <- lens_quantile(sc, q = 5L, from = REC_FROM)
  br <- beta_resid_t(full)
  st <- size_tilt(sc)
  results[[nm]] <- data.table(
    candidate = nm,
    full_PORT_t = full$portfolio_alpha_t_nw_lag3, full_IR = full$information_ratio,
    full_n = full$n_months, TO_yr = full$turnover_annual,
    rec2017_PORT_t = rec$portfolio_alpha_t_nw_lag3, rec2017_n = rec$n_months,
    longside_t_full = lens_f$long_t, shortside_t_full = lens_f$short_t,
    longside_ann = lens_f$long_mean_ann, shortside_ann = lens_f$short_mean_ann,
    longside_t_rec = lens_r$long_t, shortside_t_rec = lens_r$short_t,
    beta = br$beta, capm_alpha_ann = br$capm_alpha_ann, capm_alpha_t = br$capm_alpha_t,
    med_size_ratio = st$med_size_ratio
  )
  cat(sprintf("[%s] full PORT_t=%.3f rec2017=%.3f | LONG_t=%.3f SHORT_t=%.3f | beta=%.2f CAPMa_t=%.3f | sizeR=%.2f\n",
      nm, full$portfolio_alpha_t_nw_lag3, rec$portfolio_alpha_t_nw_lag3,
      lens_f$long_t, lens_f$short_t, br$beta, br$capm_alpha_t, st$med_size_ratio))
}

# ================================================================================
# BATTERY B: long-side-weighted composite vs standard full-IC composite
# ================================================================================
# Standard full-IC EW composite: equal-weight the 14 Z factors (score_eff ~0.97 anchor).
fcols <- setdiff(names(feat), c("Date","Ticker"))
feat_m <- merge(feat, uni[, .(Date, Ticker)], by = c("Date","Ticker"))

# ic_composite = row-mean of available Z factors (EW)
feat_m[, ic_score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
ic_sc <- feat_m[is.finite(ic_score), .(Date, Ticker, score = ic_score)]

# ls_composite: weight each factor by its LONG-SIDE realized net-active t (top-quintile), EXPANDING-window
#   PIT: at rebalance month t, weights use only long-side t estimated on data up to t-1 (expanding).
#   Implementation: for each factor, compute month-by-month top-quintile net-active series (gross),
#     then expanding NW-t up to t-1 -> weight_f(t) = max(long_t_{<=t-1}, 0). Combine Z * weight.
cat("[B] building factor long-side series (expanding weights)...\n")
# precompute per-factor per-month top-quintile net-active (gross)
fac_ls_series <- function(fcol) {
  d <- feat_m[is.finite(get(fcol)), .(Date, Ticker, score = get(fcol))]
  d <- merge(d, uni[, .(Date, Ticker, adv20)], by = c("Date","Ticker"))
  d <- d[is.na(adv20) | adv20 >= LIQ_MIN]
  d <- merge(d, rets, by = c("Date","Ticker"))
  d[, bkt := {
    n <- .N
    if (n < 5L) rep(NA_integer_, n) else as.integer(cut(frank(score, ties.method="first"),
        breaks = quantile(frank(score, ties.method="first"), probs = seq(0,1,length.out=6)),
        include.lowest = TRUE, labels = FALSE))
  }, by = Date]
  lp <- d[bkt == 5L, .(pr = mean(Ret_1m)), by = Date]
  lp <- merge(lp, bench, by = "Date"); lp[, act := pr - BM_Ret]
  setorder(lp, Date)
  lp[, .(Date, act)]
}
ls_series <- lapply(fcols, fac_ls_series); names(ls_series) <- fcols

all_months <- sort(unique(feat_m$Date))
# expanding long-side t per factor at each month (using data strictly < month)
wt_dt <- data.table(Date = all_months)
for (fc in fcols) {
  s <- ls_series[[fc]]
  w <- sapply(all_months, function(mo) {
    a <- s[Date < mo, act]
    if (length(a) < 24L) return(NA_real_)   # need >=24 months to estimate
    t <- .nw_t_mean(a, 3L); if (is.na(t)) 0 else max(t, 0)   # long-only weight (no negative)
  })
  wt_dt[[fc]] <- w
}

# build ls_composite score = sum_f Z_f(t) * w_f(t) / sum_f w_f(t)
ls_list <- vector("list", length(all_months))
for (i in seq_along(all_months)) {
  mo <- all_months[i]
  wv <- unlist(wt_dt[Date == mo, ..fcols])
  if (all(is.na(wv)) || sum(wv, na.rm=TRUE) <= 0) next
  wv[is.na(wv)] <- 0
  fm <- feat_m[Date == mo]
  Z <- as.matrix(fm[, ..fcols]); Z[is.na(Z)] <- 0
  present <- as.matrix(!is.na(as.matrix(fm[, ..fcols])) & TRUE)  # availability mask
  # weighted mean over available factors: numerator Z%*%wv, denom present%*%wv
  num <- as.numeric(Z %*% wv)
  den <- as.numeric((!is.na(as.matrix(fm[, ..fcols]))) %*% wv)
  sc  <- ifelse(den > 0, num / den, NA_real_)
  ls_list[[i]] <- data.table(Date = mo, Ticker = fm$Ticker, score = sc)
}
ls_sc <- rbindlist(ls_list)[is.finite(score)]

for (nm in c("ic_composite","ls_composite")) {
  sc <- if (nm == "ic_composite") ic_sc else ls_sc
  full <- run_canon(sc, nm)
  rec  <- run_canon(sc, paste0(nm,"_rec"), from = REC_FROM)
  lens_f <- lens_quantile(sc, q = 5L)
  lens_r <- lens_quantile(sc, q = 5L, from = REC_FROM)
  br <- beta_resid_t(full); st <- size_tilt(sc)
  results[[nm]] <- data.table(
    candidate = nm,
    full_PORT_t = full$portfolio_alpha_t_nw_lag3, full_IR = full$information_ratio,
    full_n = full$n_months, TO_yr = full$turnover_annual,
    rec2017_PORT_t = rec$portfolio_alpha_t_nw_lag3, rec2017_n = rec$n_months,
    longside_t_full = lens_f$long_t, shortside_t_full = lens_f$short_t,
    longside_ann = lens_f$long_mean_ann, shortside_ann = lens_f$short_mean_ann,
    longside_t_rec = lens_r$long_t, shortside_t_rec = lens_r$short_t,
    beta = br$beta, capm_alpha_ann = br$capm_alpha_ann, capm_alpha_t = br$capm_alpha_t,
    med_size_ratio = st$med_size_ratio
  )
  cat(sprintf("[%s] full PORT_t=%.3f rec2017=%.3f | LONG_t=%.3f SHORT_t=%.3f | beta=%.2f CAPMa_t=%.3f | sizeR=%.2f\n",
      nm, full$portfolio_alpha_t_nw_lag3, rec$portfolio_alpha_t_nw_lag3,
      lens_f$long_t, lens_f$short_t, br$beta, br$capm_alpha_t, st$med_size_ratio))
}

res_dt <- rbindlist(results, fill = TRUE)
fwrite(res_dt, file.path(PROBE, "candidate_results.csv"))

# ================================================================================
# PLACEBO null distribution (top-25 canonical PORT_t under random scores)
# ================================================================================
cat("\n[placebo] running 30-seed random-score null (full + recent2017)...\n")
pl_full <- placebo_port_t(30L)
pl_rec  <- placebo_port_t(30L, from = REC_FROM)
placebo <- data.table(
  window = c("full","recent2017"),
  mean_t = c(mean(pl_full, na.rm=TRUE), mean(pl_rec, na.rm=TRUE)),
  sd_t   = c(sd(pl_full,   na.rm=TRUE), sd(pl_rec,   na.rm=TRUE)),
  q95_t  = c(quantile(pl_full, 0.95, na.rm=TRUE), quantile(pl_rec, 0.95, na.rm=TRUE)),
  max_t  = c(max(pl_full, na.rm=TRUE), max(pl_rec, na.rm=TRUE))
)
fwrite(placebo, file.path(PROBE, "placebo_null.csv"))
# best candidate vs placebo p-value (fraction of placebo >= best observed full PORT_t)
best_full <- max(res_dt$full_PORT_t, na.rm = TRUE)
p_placebo <- mean(pl_full >= best_full, na.rm = TRUE)
cat(sprintf("[placebo] full null mean_t=%.3f sd=%.3f q95=%.3f | best candidate full_PORT_t=%.3f -> p(placebo>=best)=%.3f\n",
    mean(pl_full,na.rm=TRUE), sd(pl_full,na.rm=TRUE), quantile(pl_full,0.95,na.rm=TRUE), best_full, p_placebo))

# ================================================================================
# LAG-1 PIT graceful check (on strongest long-side candidate: tp_upside)
#   Use t-1 signal to decide month-t portfolio. A true leak shows a cliff drop; graceful = no leak.
# ================================================================================
lag1_check <- function(sc) {
  d <- copy(sc); setorder(d, Ticker, Date)
  d[, score_lag1 := shift(score, 1L), by = Ticker]
  d2 <- d[!is.na(score_lag1), .(Date, Ticker, score = score_lag1)]
  r  <- run_canon(d2, "tp_upside_lag1")
  r$portfolio_alpha_t_nw_lag3
}
tp_lag1_t <- lag1_check(candidates$A1_tp_upside)
tp_base_t <- res_dt[candidate == "A1_tp_upside", full_PORT_t]
cat(sprintf("[lag1 PIT] tp_upside base PORT_t=%.3f -> lag1 PORT_t=%.3f (graceful if not a cliff drop)\n",
    tp_base_t, tp_lag1_t))

saveRDS(list(results = res_dt, wt_dt = wt_dt, placebo_full = pl_full, placebo_rec = pl_rec,
             tp_lag1_t = tp_lag1_t, tp_base_t = tp_base_t),
        file.path(PROBE, "phase1_results.rds"))
cat("\nSAVED candidate_results.csv + placebo_null.csv\n")
print(res_dt[, .(candidate, full_PORT_t, rec2017_PORT_t, longside_t_full, shortside_t_full,
                 capm_alpha_t, med_size_ratio)])
print(placebo)
