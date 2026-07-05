# =============================================================================
# run_research.R — Axiom Engine Consume: cross-family regime-conditional composite
# WT axiom_engine_research_20260705. Real-computation ONLY (canonical_screen_bt).
# selection_type='chain'. PIT C1~C15. look-ahead 방어(regime t-1, expanding-IC, lag1 stress).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1); arrow::set_cpu_count(1L); arrow::set_io_thread_count(2L)
options(stringsAsFactors = FALSE)

ROOT     <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR  <- file.path(ROOT, "stage_artifacts/axiom_engine_research_20260705")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
stopifnot(exists("build_benchmark_compare"), exists("load_month_factors"), exists("canonical_screen_bt"))

FAM <- list(
  value        = c("V02_EP","V01_BM","V12_Composite_Value"),
  quality      = c("Q08_Composite_Quality","Q02_ROE","Q07_Earnings_Stability","Q04_Piotroski_F"),
  momentum     = c("M08_Residual_Mom","M01_Mom_12_1"),
  tail_defense = c("D48_VaR_5pct","D45_Downside_Dev","D47_CVaR_5pct")
)
ALL_FACT <- unique(unlist(FAM))
FDB_MIN  <- as.Date("2005-01-01")
FDB_MAX  <- as.Date("2026-06-30")

# ---- helpers ----------------------------------------------------------------
.winsor <- function(x, k = 2.5) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(x)
  pmin(pmax(x, mu - k*s), mu + k*s)
}
.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (x - mu)/s
}
.nwt <- function(x, lag = 3) {           # NW t-stat of mean (lag-3)
  x <- x[is.finite(x)]; n <- length(x)
  if (n < lag + 2) return(NA_real_)
  m <- mean(x); e <- x - m
  g0 <- sum(e^2)/n; v <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; v <- v + 2*w*gl }
  if (!is.finite(v) || v <= 0) return(NA_real_)
  m/sqrt(v/n)
}

# ---- 1. RAWDATA: month-ends, forward Ret_1m, liq t-1 ------------------------
cat("[1] loading RAWDATA slim...\n")
RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select = c("Date","Ticker","Close","Vol","Ret","K200","KQ150")))
RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)

RAWDATA[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = ym]$Date)
.MEND <- .MEND[.MEND >= FDB_MIN & .MEND <= FDB_MAX]

# forward realized 1M return (month-end t -> next month-end close). C2-safe (no same-month).
ME <- RAWDATA[Date %in% .MEND, .(Date, Ticker, Close)]
setorder(ME, Ticker, Date)
ME[, Close_next := shift(Close, -1L), by = Ticker]
ME[, Date_next  := shift(Date,  -1L), by = Ticker]
ME[, Ret_1m := Close_next/Close - 1]
returns_dt <- ME[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]

# liquidity: t-1 20d ADV (Close*Vol), shift(1) PIT
RAWDATA[, dollar_vol := Vol * Close]
RAWDATA[, adv20 := frollmean(dollar_vol, 20, align = "right"), by = Ticker]
RAWDATA[, adv20_l1 := shift(adv20, 1L), by = Ticker]
liq_dt <- RAWDATA[Date %in% .MEND, .(Date, Ticker, adv = adv20_l1)]

# universe membership (t-1 PIT: use membership as-of month-end, standard fe_earnrev pattern)
uni_dt <- RAWDATA[Date %in% .MEND & (K200 == 1 | KQ150 == 1), .(Date, Ticker)]
setkey(uni_dt, Date, Ticker)

# ---- benchmark: forward-month KOSPI200 TR (compound daily) ------------------
bm_daily <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date = as.Date(Date), BM_Ret)]
bm_daily <- bm_daily[!is.na(BM_Ret)]
bm_daily[, ym := format(Date, "%Y-%m")]
bm_m <- bm_daily[, .(BM_Ret = prod(1 + BM_Ret) - 1, Date = max(Date)), by = ym]
setorder(bm_m, Date)
bm_m[, BM_fwd := shift(BM_Ret, -1L)]     # forward-month BM (match forward Ret_1m)
bench_dt <- bm_m[is.finite(BM_fwd), .(Date, BM_Ret = BM_fwd)]

# ---- 2. regime signal, t-1 shift (C5) ---------------------------------------
cat("[2] regime signal (t-1 shift C5)...\n")
rg <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))
rg <- rg[, .(Date = as.Date(Date), Category)]
setorder(rg, Date)
# map regime to each month-end grid date, then lag 1 month (t-1 realized regime)
rg_grid <- rg[Date %in% .MEND]
setorder(rg_grid, Date)
rg_grid[, Cat_l1 := shift(Category, 1L)]  # regime used at rebalance t = category realized at t-1
regime_dt <- rg_grid[, .(Date, regime = Cat_l1)]

# ---- 3. per-month family z-scores (winsor 2.5s -> x-sec z of mean(component Z_Aligned)) ----
cat("[3] building family z-scores per month...\n")
fam_list <- vector("list", length(.MEND))
for (i in seq_along(.MEND)) {
  d <- .MEND[i]
  uni_tk <- uni_dt[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = ALL_FACT),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  sub <- fdt[Factor_Name %in% ALL_FACT & is.finite(Z_Score_Aligned) & Ticker %in% uni_tk,
             .(Ticker, Factor_Name, Z = Z_Score_Aligned)]
  if (nrow(sub) < 20L) next
  w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z")
  out <- data.table(Ticker = w$Ticker, Date = d)
  for (fam in names(FAM)) {
    comps <- intersect(FAM[[fam]], names(w))
    if (!length(comps)) { out[[fam]] <- NA_real_; next }
    zmat <- as.matrix(w[, ..comps, drop = FALSE])
    # winsor each component then row-mean of available, then x-sec z
    for (cc in seq_len(ncol(zmat))) zmat[, cc] <- .winsor(zmat[, cc], 2.5)
    nvalid <- rowSums(is.finite(zmat))
    fam_raw <- rowSums(zmat, na.rm = TRUE) / pmax(nvalid, 1L)
    fam_raw[nvalid == 0] <- NA_real_
    out[[fam]] <- .zsc(fam_raw)
  }
  fam_list[[i]] <- out
}
FAMZ <- rbindlist(Filter(Negate(is.null), fam_list), use.names = TRUE, fill = TRUE)
FAMZ <- merge(FAMZ, regime_dt, by = "Date", all.x = TRUE)
cat(sprintf("    FAMZ rows=%d months=%d\n", nrow(FAMZ), uniqueN(FAMZ$Date)))

# ---- realized monthly IC per family (signal at d, forward return d->d+1) -----
FAMZ_R <- merge(FAMZ, returns_dt, by = c("Date","Ticker"))
fam_ic <- FAMZ_R[, {
  res <- list()
  for (fam in names(FAM)) {
    v <- get(fam)
    ok <- is.finite(v) & is.finite(Ret_1m)
    res[[fam]] <- if (sum(ok) >= 10L) suppressWarnings(cor(v[ok], Ret_1m[ok], method = "spearman")) else NA_real_
  }
  res
}, by = Date]
setorder(fam_ic, Date)
fam_ic <- merge(fam_ic, regime_dt, by = "Date", all.x = TRUE)

# ---- 4. regime-conditional expanding-IC weights (PIT: only IC realized before d) ----
# realized IC for signal-month m uses forward return m->m+1. Available at rebalance j iff m+1 <= j (m <= j-1 by index).
mends <- sort(unique(FAMZ$Date))
midx  <- setNames(seq_along(mends), as.character(mends))
fam_ic[, jidx := midx[as.character(Date)]]

build_weights <- function(regime_lag_extra = 0L) {
  # regime_lag_extra: additional months of lag on BOTH regime label and IC availability (lag1 stress)
  wt_list <- vector("list", length(mends))
  for (jj in seq_along(mends)) {
    d <- mends[jj]
    g <- regime_dt[Date == d, regime]
    if (length(g) == 0 || is.na(g)) { wt_list[[jj]] <- NULL; next }
    # available IC: signal-months m with m+1 <= (j - regime_lag_extra), i.e. jidx <= jj-1-regime_lag_extra
    cutoff <- jj - 1L - regime_lag_extra
    if (cutoff < 6L) { wt_list[[jj]] <- NULL; next }  # need >=6 past months
    hist <- fam_ic[jidx <= cutoff]
    # same-regime subset: past months whose (t-1) regime == current (t-1) regime g
    same <- hist[regime == g]
    ww <- numeric(length(FAM)); names(ww) <- names(FAM)
    for (fam in names(FAM)) {
      icv <- same[[fam]]; icv <- icv[is.finite(icv)]
      if (length(icv) >= 3L) {
        m <- mean(icv)
      } else {
        # fallback: unconditional expanding IC if regime cell too thin
        allv <- hist[[fam]]; allv <- allv[is.finite(allv)]
        m <- if (length(allv) >= 6L) mean(allv) else 0
      }
      ww[fam] <- max(0, m)
    }
    # tail_defense activation: only CAUTION/CRISIS (drag guard, DIST-AR-001 frontier[1])
    if (!(g %in% c("CAUTION","CRISIS"))) ww["tail_defense"] <- 0
    # value spread-reversion proxy (expanding, C1): value active only if its expanding
    # regime-conditional IC is positive (subsumed by max(0,.)); extra reversion gate:
    # require value expanding-IC in a *recovering* state (recent same-regime IC > older) -> skip if degrading.
    if (ww["value"] > 0) {
      vv <- same[["value"]]; vv <- vv[is.finite(vv)]
      if (length(vv) >= 6L) {
        h <- floor(length(vv)/2)
        recent <- mean(tail(vv, h)); older <- mean(head(vv, length(vv)-h))
        if (recent <= 0 && recent < older) ww["value"] <- 0  # degrading & negative -> gate off
      }
    }
    s <- sum(ww)
    if (s <= 0) { wt_list[[jj]] <- NULL; next }
    ww <- ww / s
    wt_list[[jj]] <- data.table(Date = d, t(ww))
  }
  rbindlist(Filter(Negate(is.null), wt_list), use.names = TRUE)
}

WT_COND <- build_weights(0L)
WT_LAG1 <- build_weights(1L)  # lag1 stress

# static (regime-unconditional) baseline weights = expanding unconditional IC weights, no regime cell
build_static_weights <- function() {
  wt_list <- vector("list", length(mends))
  for (jj in seq_along(mends)) {
    d <- mends[jj]; cutoff <- jj - 1L
    if (cutoff < 6L) next
    hist <- fam_ic[jidx <= cutoff]
    ww <- numeric(length(FAM)); names(ww) <- names(FAM)
    for (fam in names(FAM)) {
      allv <- hist[[fam]]; allv <- allv[is.finite(allv)]
      ww[fam] <- if (length(allv) >= 6L) max(0, mean(allv)) else 0
    }
    s <- sum(ww); if (s <= 0) next
    wt_list[[jj]] <- data.table(Date = d, t(ww/s))
  }
  rbindlist(Filter(Negate(is.null), wt_list), use.names = TRUE)
}
WT_STATIC <- build_static_weights()

# equal-weight static baseline (pure regime-unconditional composite, all families 0.25)
WT_EW <- copy(WT_STATIC)
for (fam in names(FAM)) WT_EW[[fam]] <- 0.25

# ---- compose scores + canonical measure -------------------------------------
compose_scores <- function(WT) {
  m <- merge(FAMZ, WT, by = "Date", suffixes = c("", ".w"))
  # score = sum_f w_f * fam_z_f
  m[, score := 0]
  for (fam in names(FAM)) {
    fz <- m[[fam]]; wf <- m[[paste0(fam)]]  # weight col has same name in WT
    # disambiguate: WT columns overwrote? use explicit
  }
  m
}

# explicit compose (weight cols and z cols share names -> merge added .w? No: FAMZ has fam cols,
# WT has fam cols too -> collision). Rebuild with renamed weight columns.
rename_wt <- function(WT) {
  W <- copy(WT)
  for (fam in names(FAM)) setnames(W, fam, paste0("w_", fam))
  W
}
score_and_measure <- function(WT, tag) {
  W <- rename_wt(WT)
  m <- merge(FAMZ, W, by = "Date")
  m[, score := 0]
  for (fam in names(FAM)) {
    fz <- m[[fam]]; wf <- m[[paste0("w_", fam)]]
    fz[!is.finite(fz)] <- 0
    m[, score := score + wf * fz]
  }
  S <- m[is.finite(score), .(Date, Ticker, score)]
  res <- canonical_screen_bt(S, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
                             liq_dt = liq_dt, liq_min = 2e8,
                             run_id = tag, strategy_id = tag)
  list(scores = S, res = res, weights = WT)
}

cat("[4] composing + canonical measuring...\n")
RES_COND   <- score_and_measure(WT_COND,   "axeng_regime_cond")
RES_STATIC <- score_and_measure(WT_STATIC, "axeng_static_icw")
RES_EW     <- score_and_measure(WT_EW,     "axeng_static_ew")
RES_LAG1   <- score_and_measure(WT_LAG1,   "axeng_lag1_stress")

# ---- oos_retention (anchored 55/65/75 median) + calmar + era ----------------
grad_stats <- function(res) {
  ser <- as.data.table(res$period_returns); setorder(ser, date)
  ser[, active := ret_net - benchmark_ret]
  sr_full <- mean(ser$active)/sd(ser$active)*sqrt(12)
  oos_split <- function(frac) {
    k <- floor(nrow(ser)*frac); if (k < 12 || k >= nrow(ser)-6) return(NA_real_)
    is_ <- ser[1:k]; oos_ <- ser[(k+1):.N]
    sr_is <- mean(is_$active)/sd(is_$active)*sqrt(12)
    sr_oos<- mean(oos_$active)/sd(oos_$active)*sqrt(12)
    if (!is.finite(sr_is) || sr_is <= 0) NA_real_ else sr_oos/sr_is
  }
  oos_ret <- median(c(oos_split(.55), oos_split(.65), oos_split(.75)), na.rm = TRUE)
  nav <- cumprod(1 + ser$ret_net); peak <- cummax(nav); dd <- nav/peak - 1; mdd <- abs(min(dd))
  cagr <- nav[length(nav)]^(12/nrow(ser)) - 1
  calmar <- if (mdd > 0) cagr/mdd else NA_real_
  ser[, era := fcase(date < as.Date("2018-01-01"), "pre2018",
                     date < as.Date("2023-01-01"), "2018-2022", default = "2023+")]
  era <- ser[, .(n = .N, mean_active = mean(active),
                 sr = mean(active)/sd(active)*sqrt(12)), by = era]
  # post-2017 PORT_t (NW lag-3 on active net series)
  post <- ser[date >= as.Date("2018-01-01")]
  post_t <- .nwt(post$active, 3)
  list(sr_full = sr_full, oos_ret = oos_ret, cagr = cagr, mdd = mdd, calmar = calmar,
       era = era, post2017_t = post_t, post2017_n = nrow(post), full_active_t = .nwt(ser$active,3))
}
G_COND   <- grad_stats(RES_COND$res)
G_STATIC <- grad_stats(RES_STATIC$res)
G_EW     <- grad_stats(RES_EW$res)
G_LAG1   <- grad_stats(RES_LAG1$res)

# ---- regime decomposition: mean active by regime (cond composite) -----------
ser_c <- as.data.table(RES_COND$res$period_returns); setorder(ser_c, date)
ser_c[, active := ret_net - benchmark_ret]
ser_c <- merge(ser_c, regime_dt[, .(date = Date, regime)], by = "date", all.x = TRUE)
regime_decomp <- ser_c[, .(n = .N, mean_active = mean(active),
                           sr = mean(active)/sd(active)*sqrt(12)), by = regime][order(-mean_active)]

pr <- function(g, r, nm) cat(sprintf("%-18s port_t=%6.3f IR=%6.3f netSR=%6.3f MDD=%5.3f calmar=%5.3f oos=%6.3f post2017_t=%6.3f\n",
  nm, r$res$portfolio_alpha_t_nw_lag3, r$res$information_ratio, g$sr_full, g$mdd, g$calmar, g$oos_ret, g$post2017_t))
cat("\n===== RESULTS =====\n")
pr(G_COND, RES_COND, "regime_cond"); pr(G_STATIC, RES_STATIC, "static_icw")
pr(G_EW, RES_EW, "static_ew"); pr(G_LAG1, RES_LAG1, "lag1_stress")
cat("\nRegime decomposition (cond composite):\n"); print(regime_decomp)
cat("\nEra breakdown (cond composite):\n"); print(G_COND$era)
cat("\nMean regime-conditional weights (cond):\n")
wcols <- names(FAM)
print(round(colMeans(WT_COND[, ..wcols], na.rm = TRUE), 3))

# ---- graduation verdict -----------------------------------------------------
port_t <- RES_COND$res$portfolio_alpha_t_nw_lag3
pass_port  <- is.finite(port_t) && port_t >= 2.95
pass_oos   <- is.finite(G_COND$oos_ret) && G_COND$oos_ret >= 0.7
pass_calmar<- is.finite(G_COND$calmar) && G_COND$calmar >= 0.64
graduation <- if (pass_port && pass_oos && pass_calmar) "PASS" else "FAIL"
delta_static <- port_t - RES_STATIC$res$portfolio_alpha_t_nw_lag3
delta_ew     <- port_t - RES_EW$res$portfolio_alpha_t_nw_lag3

cat(sprintf("\n=== GRADUATION: %s (port_t>=2.95:%s oos>=0.7:%s calmar>=0.64:%s) ===\n",
            graduation, pass_port, pass_oos, pass_calmar))
cat(sprintf("delta vs static_icw = %+.3f | delta vs static_ew = %+.3f | lag1 port_t = %.3f (concurrent-leak check)\n",
            delta_static, delta_ew, RES_LAG1$res$portfolio_alpha_t_nw_lag3))

# ---- write JSON + monthly series --------------------------------------------
res_json <- list(
  schema = "axiom_engine_research_v1",
  wt = "axiom_engine_research_20260705",
  generated_at = as.character(Sys.Date()),
  hypothesis_id = "cross-family regime-conditional composite (5-card convergence)",
  metric_type = "canonical_screen",
  universe = "K200 UNION KQ150, top-25 EW long-only, LIQ 2e8 t-1",
  period = sprintf("%s .. %s (%d months measured)",
                   as.character(min(mends)), as.character(max(mends)), RES_COND$res$n_months),
  selection_type = "chain",
  families = FAM,
  regime_conditional = list(
    port_t = port_t, IR = RES_COND$res$information_ratio, net_sr = G_COND$sr_full,
    mdd = G_COND$mdd, calmar = G_COND$calmar, cagr = G_COND$cagr,
    oos_retention = G_COND$oos_ret, turnover_annual = RES_COND$res$turnover_annual,
    post2017_port_t = G_COND$post2017_t, post2017_n = G_COND$post2017_n,
    full_active_t = G_COND$full_active_t, n_months = RES_COND$res$n_months
  ),
  static_icw_baseline = list(
    port_t = RES_STATIC$res$portfolio_alpha_t_nw_lag3, net_sr = G_STATIC$sr_full,
    calmar = G_STATIC$calmar, oos_retention = G_STATIC$oos_ret, post2017_port_t = G_STATIC$post2017_t
  ),
  static_ew_baseline = list(
    port_t = RES_EW$res$portfolio_alpha_t_nw_lag3, net_sr = G_EW$sr_full,
    calmar = G_EW$calmar, oos_retention = G_EW$oos_ret, post2017_port_t = G_EW$post2017_t
  ),
  lag1_stress = list(
    port_t = RES_LAG1$res$portfolio_alpha_t_nw_lag3, net_sr = G_LAG1$sr_full,
    concurrent_leak = if (is.finite(RES_LAG1$res$portfolio_alpha_t_nw_lag3) && is.finite(port_t))
      (abs(port_t - RES_LAG1$res$portfolio_alpha_t_nw_lag3) < 0.6) else NA,
    note = "lag1 = regime label + IC availability extra 1M lag. large drop under lag1 => concurrent leak suspicion."
  ),
  delta_vs_static_icw = delta_static,
  delta_vs_static_ew  = delta_ew,
  regime_decomp = as.list(regime_decomp),
  era_breakdown = as.list(G_COND$era),
  mean_regime_cond_weights = as.list(round(colMeans(WT_COND[, ..wcols], na.rm = TRUE), 4)),
  graduation = list(
    verdict = graduation,
    port_t_pass = pass_port, oos_pass = pass_oos, calmar_pass = pass_calmar,
    gates = "PORT_t>=2.95 AND oos_retention>=0.7 (v2 55/65/75 median) AND calmar>=0.64"
  ),
  pit_notes = c(
    "regime label t-1 shift (C5): Cat_l1 = Category at month-end t-1.",
    "regime-conditional IC = expanding-window, same-regime past months only, forward-return realized before rebalance (m+1<=j-1). C1.",
    "value spread-reversion gate = expanding same-regime IC recovering-state (no full-sample conditional_ic_matrix.csv -> C1 clean).",
    "forward Ret_1m = month-end t -> next month-end close (C2, no same-month).",
    "benchmark = .cache/benchmark.parquet IKS200 forward-month TR; RAWDATA.BM_Ret avoided (corrupted).",
    "lag1 stress variant measured for concurrent-leak audit (FaithTrend lesson)."
  )
)
write_json(res_json, file.path(OUT_DIR, "research_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")

# monthly series for all variants
ser_out <- as.data.table(RES_COND$res$period_returns)[, .(date, cond_ret_net = ret_net, benchmark_ret)]
ser_out <- merge(ser_out, as.data.table(RES_STATIC$res$period_returns)[, .(date, static_ret_net = ret_net)], by = "date", all.x = TRUE)
ser_out <- merge(ser_out, as.data.table(RES_EW$res$period_returns)[, .(date, ew_ret_net = ret_net)], by = "date", all.x = TRUE)
ser_out <- merge(ser_out, as.data.table(RES_LAG1$res$period_returns)[, .(date, lag1_ret_net = ret_net)], by = "date", all.x = TRUE)
ser_out <- merge(ser_out, regime_dt[, .(date = Date, regime)], by = "date", all.x = TRUE)
fwrite(ser_out, file.path(OUT_DIR, "monthly_returns_series.csv"))
saveRDS(list(cond=RES_COND, static=RES_STATIC, ew=RES_EW, lag1=RES_LAG1,
             G_COND=G_COND, G_STATIC=G_STATIC, regime_decomp=regime_decomp,
             WT_COND=WT_COND, fam_ic=fam_ic),
        file.path(OUT_DIR, "research_full.rds"))
cat("\n[done] artifacts written to", OUT_DIR, "\n")
cat("DONE\n")
