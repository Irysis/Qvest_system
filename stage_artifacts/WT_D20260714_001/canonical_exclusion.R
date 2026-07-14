#!/usr/bin/env Rscript
# Contract-grade canonical_screen_bt exclusion: base top-25 (cap-tilt) vs exclude distress-flagged.
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260714_001")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
LIQ <- 2e8

raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
        col_select=c("Date","Ticker","Close","Size","K200","KQ150","Vol")))
raw[, Date := as.Date(Date)]; raw <- raw[!is.na(Close)&Close>0]; setorder(raw,Ticker,Date)
raw[, TV := Close*Vol]; raw[, ADV20 := frollmean(TV,20L,align="right"), by=Ticker]
raw[, ym := format(Date,"%Y-%m")]
me_dates <- raw[, .(me=max(Date)), by=ym]$me
me <- raw[Date %in% me_dates]; setorder(me,Ticker,Date)
me[, Close_next := shift(Close,1L,type="lead"), by=Ticker]
me[, Date_next  := shift(Date,1L,type="lead"), by=Ticker]
me[, Ret_1m := Close_next/Close-1]; me[, gap := as.integer(Date_next-Date)]
me[!is.na(gap)&gap>45, Ret_1m := NA_real_]
me[, eligible := (K200==TRUE|KQ150==TRUE)&!is.na(ADV20)&ADV20>=LIQ]
me[, Ticker := as.character(Ticker)]; setnames(me,"Date","sig_date")

bm <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[Date %in% me_dates]; setorder(bm,Date)
bm[, BM_Close_next := shift(BM_Close,1L,type="lead")]; bm[, BM_fwd := BM_Close_next/BM_Close-1]
bench_dt <- bm[!is.na(BM_fwd), .(Date=Date, BM_Ret=BM_fwd)]

ap <- as.data.table(read_parquet(file.path(OUT,"audit_signal_panel.parquet")))
ap[, rcept_dt := as.Date(rcept_dt)]; ap[, Ticker := as.character(ticker)]
sig_dates <- sort(unique(me$sig_date))
grid <- CJ(Ticker=unique(me$Ticker), sig_date=sig_dates)
ap2 <- ap[, .(Ticker,rcept_dt,nonclean,gc,has_emphs)]; setkey(ap2,Ticker,rcept_dt); setkey(grid,Ticker,sig_date)
aud <- ap2[grid, on=.(Ticker,rcept_dt=sig_date), roll=TRUE]; setnames(aud,"rcept_dt","sig_date")
P <- merge(me[,.(sig_date,Ticker,Ret_1m,Size,eligible)], aud, by=c("Ticker","sig_date"), all.x=TRUE)
for (c in c("nonclean","gc","has_emphs")) P[is.na(get(c)),(c):=0]
P <- P[eligible==TRUE & !is.na(Ret_1m) & sig_date>=as.Date("2016-01-31")]

returns_dt <- P[, .(Date=sig_date, Ticker, Ret_1m)]
size_dt    <- P[, .(Date=sig_date, Ticker, Size)]

run_case <- function(distress_col=NULL, label="base") {
  S <- P[, .(Date=sig_date, Ticker, score=Size)]  # cap-tilt selection (deploy proxy)
  if (!is.null(distress_col)) {
    ex <- P[get(distress_col)>=1, .(Date=sig_date, Ticker, ex=1L)]
    S <- merge(S, ex, by=c("Date","Ticker"), all.x=TRUE)
    S <- S[is.na(ex)]; S[, ex := NULL]   # drop distress-flagged from eligible set
  }
  r <- canonical_screen_bt(S, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                           size_dt=size_dt, run_id=label, strategy_id=label)
  list(label=label, n_months=r$n_months, port_t_nw_lag3=r$portfolio_alpha_t_nw_lag3,
       port_t_pvalue=r$portfolio_alpha_t_pvalue, ir=r$information_ratio,
       alpha_ann=r$alpha_annualized, net_sr=r$net_sr, turnover=r$turnover_annual)
}
res <- list(
  base       = run_case(NULL, "base_capw_top25"),
  excl_gc    = run_case("gc", "excl_goingconcern_top25"),
  excl_ncln  = run_case("nonclean", "excl_nonclean_top25")
)
for (k in names(res)) { x<-res[[k]]
  cat(sprintf("%-26s PORT_t=%.3f (p=%.3f) IR=%.3f alpha_ann=%.4f netSR=%.3f TO=%.2f n=%d\n",
      x$label, x$port_t_nw_lag3, x$port_t_pvalue, x$ir, x$alpha_ann, x$net_sr, x$turnover, x$n_months)) }
write_json(res, file.path(OUT,"canonical_exclusion.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
cat("[saved] canonical_exclusion.json\n")
