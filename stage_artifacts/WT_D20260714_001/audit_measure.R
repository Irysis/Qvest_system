#!/usr/bin/env Rscript
# R25 FQ-004 audit-metadata signal measurement — WT-D20260714_001
# Single-thread, arrow io=2, file-based. canonical_screen_bt / build_benchmark_compare (contract).
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260714_001")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
LIQ <- 2e8
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||is.na(a)) b else a

## ---- 1. RAWDATA -> month-end panel with forward return, size, membership, liq ----
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"),
        col_select = c("Date","Ticker","Close","Size","K200","KQ150","Vol")))
raw[, Date := as.Date(Date)]
raw <- raw[!is.na(Close) & Close > 0]
setorder(raw, Ticker, Date)
raw[, TV := Close * Vol]
raw[, ADV20 := frollmean(TV, 20L, align = "right"), by = Ticker]
raw[, ym := format(Date, "%Y-%m")]
# global month-end trading dates
me_dates <- raw[, .(me = max(Date)), by = ym]$me
me <- raw[Date %in% me_dates]
setorder(me, Ticker, Date)
# forward 1M return = next month-end Close / this Close - 1 (per ticker)
me[, Close_next := shift(Close, 1L, type = "lead"), by = Ticker]
me[, Date_next  := shift(Date,  1L, type = "lead"), by = Ticker]
me[, Ret_1m := Close_next / Close - 1]
# only keep consecutive months (guard gaps > ~45d)
me[, gap := as.integer(Date_next - Date)]
me[!is.na(gap) & gap > 45, Ret_1m := NA_real_]
me[, eligible := (K200 == TRUE | KQ150 == TRUE) & !is.na(ADV20) & ADV20 >= LIQ]
me[, Ticker := as.character(Ticker)]
setnames(me, "Date", "sig_date")
panel_me <- me[, .(sig_date, Ticker, Ret_1m, Size, eligible, K200, KQ150)]

## ---- 2. benchmark monthly (cap-w authoritative) ----
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[Date %in% me_dates]
setorder(bm, Date)
bm[, BM_Close_next := shift(BM_Close, 1L, type = "lead")]
bm[, BM_fwd := BM_Close_next / BM_Close - 1]
bench_dt <- bm[!is.na(BM_fwd), .(Date = Date, BM_Ret = BM_fwd)]  # forward BM over holding month

## ---- 3. audit + correction signal panels ----
ap <- as.data.table(read_parquet(file.path(OUT, "audit_signal_panel.parquet")))
ap[, rcept_dt := as.Date(rcept_dt)]
ap[, Ticker := as.character(ticker)]
cc <- as.data.table(read_parquet(file.path(OUT, "correction_panel.parquet")))
cc[, corr_first_dt := as.Date(corr_first_dt)]
cc[, Ticker := as.character(ticker)]

## ---- 4. PIT as-of join: at sig_date, carry latest FY audit with rcept_dt <= sig_date ----
sig_dates <- sort(unique(panel_me$sig_date))
# audit: rolling join
ap2 <- ap[, .(Ticker, rcept_dt, nonclean, has_emphs, gc, has_kam, kam_count)]
setkey(ap2, Ticker, rcept_dt)
grid <- CJ(Ticker = unique(panel_me$Ticker), sig_date = sig_dates)
setkey(grid, Ticker, sig_date)
aud <- ap2[grid, on = .(Ticker, rcept_dt = sig_date), roll = TRUE]
setnames(aud, "rcept_dt", "sig_date")
# correction: as-of on corr_first_dt (rounds known once first correction filed)
cc2 <- cc[, .(Ticker, corr_first_dt, corr_rounds)]
setkey(cc2, Ticker, corr_first_dt)
crj <- cc2[grid, on = .(Ticker, corr_first_dt = sig_date), roll = TRUE]
setnames(crj, "corr_first_dt", "sig_date")

P <- merge(panel_me, aud, by = c("Ticker","sig_date"), all.x = TRUE)
P <- merge(P, crj[, .(Ticker, sig_date, corr_rounds)], by = c("Ticker","sig_date"), all.x = TRUE)
# flags: NA (no audit known yet) => 0 (not flagged)
for (c in c("nonclean","has_emphs","gc","has_kam","kam_count","corr_rounds")) P[is.na(get(c)), (c) := 0]
# restrict to eligible deploy universe + valid forward return
P <- P[eligible == TRUE & !is.na(Ret_1m)]
# start at 2015-07 (first audit signals knowable ~mid 2016 for FY2015; require signal coverage)
P <- P[sig_date >= as.Date("2016-01-31")]
cat(sprintf("[panel] eligible rows=%d  months=%d  tickers=%d  range %s..%s\n",
            nrow(P), uniqueN(P$sig_date), uniqueN(P$Ticker), min(P$sig_date), max(P$sig_date)))

## ---- helper: EW group monthly return -> build_benchmark_compare active PORT_t ----
size_dt_full <- P[, .(Date = sig_date, Ticker, Size)]
grp_active <- function(dt_flag_col, min_flag = 1, subset_dt = P, bench = bench_dt, label = "grp") {
  D <- copy(subset_dt)
  D[, flg := as.integer(get(dt_flag_col) >= min_flag)]
  # flagged EW monthly return
  fl <- D[flg == 1, .(ret = mean(Ret_1m)), by = .(date = sig_date)]
  if (nrow(fl) < 12) return(list(label = label, n_months = nrow(fl), note = "too few months"))
  pr <- merge(fl, bench[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  prt <- data.table(date = pr$date, ret_net = pr$ret, frequency = "monthly")
  brt <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret, benchmark_id = "capw")
  bc <- build_benchmark_compare(prt, brt, run_id = label, strategy_id = label, annualization_factor = 12L)
  g <- function(nm){v <- bc[metric_name==nm, active_value]; if(length(v)==0) NA_real_ else as.numeric(v[1])}
  n_flagged_avg <- mean(D[, sum(flg), by = sig_date]$V1)
  list(label = label, n_months = nrow(pr), n_flagged_avg = round(n_flagged_avg,1),
       port_t_nw_lag3 = g("Portfolio_Alpha_t_NW_lag3"), port_t_pvalue = g("Portfolio_Alpha_t_pvalue"),
       alpha_annualized = g("Alpha_Annualized"), information_ratio = g("Information_Ratio"),
       mean_active = mean(pr$ret - pr$benchmark_ret))
}

## ---- helper: EW-universe basis (diagnostic) via paired spread flagged vs unflagged ----
nw_t <- function(x, lag = 3L) { if(exists(".nw_t_mean",mode="function")) .nw_t_mean(x, lag=lag) else NA_real_ }

spread_flagged_vs_unflagged <- function(flag_col, min_flag = 1, subset_dt = P, label="sp") {
  D <- copy(subset_dt); D[, flg := as.integer(get(flag_col) >= min_flag)]
  m <- D[, .(fl = mean(Ret_1m[flg==1]), un = mean(Ret_1m[flg==0]),
             nfl = sum(flg==1), nun = sum(flg==0)), by = .(date = sig_date)]
  m <- m[nfl >= 1 & nun >= 1 & is.finite(fl) & is.finite(un)]
  if (nrow(m) < 12) return(list(label=label, n_months=nrow(m), note="too few"))
  sp <- m$fl - m$un  # flagged minus unflagged (EW-universe basis). negative = flagged underperform
  list(label=label, n_months=nrow(m), mean_spread=mean(sp), spread_t_nw=nw_t(sp),
       mean_n_flagged=round(mean(m$nfl),1))
}

## ---- helper: size-tier flagged-vs-unflagged spread ----
size_tier_spread <- function(flag_col, min_flag=1, subset_dt=P) {
  D <- copy(subset_dt); D[, flg := as.integer(get(flag_col) >= min_flag)]
  setorder(D, sig_date, -Size)
  D[, cap_rank := seq_len(.N), by = sig_date]
  D[, tier := fifelse(cap_rank<=10,"MEGA", fifelse(cap_rank<=30,"MID","SMALL"))]
  res <- list()
  for (tt in c("MEGA","MID","SMALL")) {
    Dt <- D[tier==tt]
    m <- Dt[, .(fl=mean(Ret_1m[flg==1]), un=mean(Ret_1m[flg==0]),
                nfl=sum(flg==1)), by=.(date=sig_date)]
    m <- m[nfl>=1 & is.finite(fl) & is.finite(un)]
    if (nrow(m) < 12) { res[[tt]] <- list(tier=tt, n_months=nrow(m), note="too few flagged in tier"); next }
    sp <- m$fl - m$un
    res[[tt]] <- list(tier=tt, n_months=nrow(m), mean_n_flagged=round(mean(m$nfl),2),
                      mean_spread=mean(sp), spread_t_nw=nw_t(sp))
  }
  res
}

## ---- helper: exclusion-form (EW-universe base vs base-ex-flagged, paired NW-t) ----
exclusion_paired <- function(flag_col, min_flag=1, subset_dt=P, label="excl") {
  D <- copy(subset_dt); D[, flg := as.integer(get(flag_col) >= min_flag)]
  base <- D[, .(base = mean(Ret_1m)), by=.(date=sig_date)]
  excl <- D[flg==0, .(excl = mean(Ret_1m)), by=.(date=sig_date)]
  m <- merge(base, excl, by="date")
  m <- m[is.finite(base) & is.finite(excl)]
  diff <- m$excl - m$base   # positive => excluding flagged helps
  list(label=label, n_months=nrow(m), mean_diff=mean(diff), diff_t_nw=nw_t(diff),
       ann_diff_bps=mean(diff)*12*1e4)
}

## ---- deploy relevance: flagged in top-25 by Size per month ----
deploy_relevance <- function(flag_col, min_flag=1, subset_dt=P) {
  D <- copy(subset_dt); D[, flg := as.integer(get(flag_col) >= min_flag)]
  setorder(D, sig_date, -Size)
  top25 <- D[, .SD[seq_len(min(25,.N))], by=sig_date]
  list(mean_flagged_in_top25 = round(mean(top25[, sum(flg), by=sig_date]$V1),3),
       pct_months_any_flagged_top25 = round(mean(top25[, as.integer(sum(flg)>0), by=sig_date]$V1),3))
}

## ---- run all surfaces ----
surfaces <- list(
  S1_nonclean   = list(col="nonclean",  min=1, full_period=TRUE),
  S2_emphs      = list(col="has_emphs", min=1, full_period=TRUE),
  S3_gc         = list(col="gc",        min=1, full_period=TRUE),
  S4_kam3       = list(col="kam_count", min=3, full_period=FALSE), # FY2019+ only
  S5_corr2      = list(col="corr_rounds", min=2, full_period=TRUE) # frequency-adjacent robustness
)
results <- list()
for (sn in names(surfaces)) {
  s <- surfaces[[sn]]
  sub <- if (s$full_period) P else P[sig_date >= as.Date("2020-01-31")] # KAM knowable FY2019 filed 2020
  cat(sprintf("\n=== %s (col=%s min=%d) ===\n", sn, s$col, s$min))
  ga_cap <- grp_active(s$col, s$min, subset_dt=sub, bench=bench_dt, label=paste0(sn,"_capw"))
  ews    <- spread_flagged_vs_unflagged(s$col, s$min, subset_dt=sub, label=paste0(sn,"_ew"))
  sts    <- size_tier_spread(s$col, s$min, subset_dt=sub)
  exc    <- exclusion_paired(s$col, s$min, subset_dt=sub, label=paste0(sn,"_excl"))
  dep    <- deploy_relevance(s$col, s$min, subset_dt=sub)
  results[[sn]] <- list(surface=sn, flag_col=s$col, min_flag=s$min,
                        full_period=s$full_period,
                        signal_capw=ga_cap, signal_ew_diag=ews, size_tier=sts,
                        exclusion_paired=exc, deploy_relevance=dep)
  cat(sprintf("  signal capw PORT_t=%.2f (p=%.3f, alpha_ann=%.3f, nflag~%.0f) | ew spread_t=%.2f\n",
      ga_cap$port_t_nw_lag3 %||% NA, ga_cap$port_t_pvalue %||% NA, ga_cap$alpha_annualized %||% NA,
      ga_cap$n_flagged_avg %||% NA, ews$spread_t_nw %||% NA))
  cat(sprintf("  exclusion paired diff_t=%.2f (ann %.1f bps) | deploy: flagged in top25 avg=%.3f (%.0f%% months)\n",
      exc$diff_t_nw %||% NA, exc$ann_diff_bps %||% NA,
      dep$mean_flagged_in_top25, 100*dep$pct_months_any_flagged_top25))
  for (tt in names(sts)) {
    x <- sts[[tt]]
    cat(sprintf("    tier %-5s spread_t=%s (nflag~%s)\n", tt,
        ifelse(is.null(x$spread_t_nw),"NA",sprintf("%.2f",x$spread_t_nw)),
        ifelse(is.null(x$mean_n_flagged),x$note,as.character(x$mean_n_flagged))))
  }
}

write_json(results, file.path(OUT,"measurement_results.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
# alpha_scores.parquet: latest sig_date signals as scores (score = -flag severity, higher=cleaner)
latest <- P[sig_date == max(sig_date)]
latest[, severity := nonclean*8 + gc*4 + has_emphs*2 + as.integer(kam_count>=3)]
alpha_scores <- latest[, .(as_of_date = sig_date, Ticker, Size,
                           nonclean, has_emphs, gc, kam_count, corr_rounds, severity,
                           score = -severity)]
write_parquet(alpha_scores, file.path(OUT,"alpha_scores.parquet"))
cat(sprintf("\n[saved] measurement_results.json + alpha_scores.parquet (%d names)\n", nrow(alpha_scores)))
