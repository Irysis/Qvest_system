# 04_stress.R — reconcile drag vs REAL benchmark, anchor-vs-alpha final separation, and
#   sub-period robustness of the near-miss V4 (Anchor2 EW-fill). Uses REAL BM_Ret (KOSPI200 TR).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/selfdev_c1_benchaware_construction")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/weighted_screen_bt.R"))

P <- as.data.table(read_parquet(file.path(WD,"panel/panel_monthly.parquet"))); P[,Date:=as.Date(Date)]
bench <- as.data.table(read_parquet(file.path(WD,"panel/benchmark_monthly.parquet"))); bench[,Date:=as.Date(Date)]
P <- P[Date>=as.Date("2005-01-01") & Date<=as.Date("2026-06-01")]
P <- P[is.finite(adv20_t)&adv20_t>=2e8 & is.finite(mom_12_1)&is.finite(Ret_1m)&is.finite(mcap_t)]
dts <- sort(unique(P$Date)); WMAX<-0.20; TOP_N<-25L
cap_renorm <- function(w,wmax=WMAX){ w<-pmax(w,0); if(sum(w)==0) return(w); w<-w/sum(w)
  for(it in 1:50){over<-w>wmax+1e-12; if(!any(over))break; ex<-sum(w[over]-wmax); w[over]<-wmax
    fr<- !over&w>0; if(!any(fr)){w[over]<-wmax;break}; w[fr]<-w[fr]+ex*w[fr]/sum(w[fr])}; w/sum(w) }
bench_dt <- bench[,.(Date,BM_Ret)]

# builder for anchor2 with configurable fill
mk_anchor <- function(K=2L, fill="ew"){
  out<-vector("list",length(dts))
  for(i in seq_along(dts)){ D<-dts[i]; m<-P[Date==D]; if(nrow(m)<TOP_N) next
    setorder(m,-mcap_t); anch<-m$Ticker[1:K]; rest<-m[!Ticker%in%anch]; setorder(rest,-mom_12_1)
    sel<-rest[1:(TOP_N-K)]; rem<-1-0.20*K
    if(fill=="ew") wf<-rep(rem/(TOP_N-K),TOP_N-K)
    else { sc<-pmax(sel$mom_12_1-min(sel$mom_12_1)+1e-6,1e-6); wf<-rem*sc/sum(sc) }
    out[[i]]<-data.table(Date=D,Ticker=c(anch,sel$Ticker),w=cap_renorm(c(rep(0.20,K),wf))) }
  rbindlist(out)
}
mk_ew <- function(){ out<-vector("list",length(dts)); for(i in seq_along(dts)){D<-dts[i];m<-P[Date==D];if(nrow(m)<TOP_N)next
  setorder(m,-mom_12_1); s<-m$Ticker[1:TOP_N]; out[[i]]<-data.table(Date=D,Ticker=s,w=1/TOP_N)}; rbindlist(out) }

nw_t <- function(x){ m<-mean(x); dm<-x-m; nn<-length(x); g0<-sum(dm^2)/nn; gs<-0
  for(L in 1:3){ww<-1-L/4; gs<-gs+2*ww*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn}; m/sqrt((g0+gs)/nn) }

subperiods <- function(wdt, tag){
  r<-weighted_screen_bt(wdt, P[,.(Date,Ticker,Ret_1m)], bench_dt, cost_bps_oneway=15, run_id=tag, strategy_id=tag)
  pr<-r$period_returns; pr[,act:=ret_net-benchmark_ret]
  seg <- function(lo,hi){ s<-pr[date>=as.Date(lo)&date<as.Date(hi)]; if(nrow(s)<6) return(NA_real_); nw_t(s$act) }
  data.table(tag=tag, full_t=r$portfolio_alpha_t_nw_lag3,
    t_0510=seg("2005-01-01","2011-01-01"), t_1116=seg("2011-01-01","2017-01-01"),
    t_1722=seg("2017-01-01","2023-01-01"), t_2326=seg("2023-01-01","2027-01-01"),
    pre2023_t=seg("2005-01-01","2023-01-01"), post2023_t=seg("2023-01-01","2027-01-01")) }

# REAL-benchmark drag split for EW: active_i vs REAL BM_Ret. We can only split port side (which held names
#  contribute active); attribute active = sum_held w*(r_i - BM) ; anchor-underweight cost = -bm proxy not
#  available on real BM. So we report: EW active decomposed by held mega-cap presence.
ew_realbench_split <- function(){
  wdt<-mk_ew(); r<-weighted_screen_bt(wdt,P[,.(Date,Ticker,Ret_1m)],bench_dt,cost_bps_oneway=15)
  pr<-r$period_returns; # per-month: does EW hold any of top-2 cap? and active that month
  rows<-vector("list",length(dts))
  for(i in seq_along(dts)){D<-dts[i];m<-P[Date==D];if(nrow(m)<TOP_N)next
    setorder(m,-mom_12_1); sel<-m$Ticker[1:TOP_N]; setorder(m,-mcap_t); top2<-m$Ticker[1:2]
    held<-sum(top2%in%sel); rows[[i]]<-data.table(Date=D,held_top2=held)}
  hd<-rbindlist(rows); m<-merge(pr,hd,by.x="date",by.y="Date")
  m[,.(mean_active=mean(ret_net-benchmark_ret), n=.N), by=held_top2][order(held_top2)] }

cat("\n===== ANCHOR-vs-ALPHA final separation (REAL benchmark, PORT_t) =====\n")
sep <- rbindlist(list(
  subperiods(mk_ew(),                  "EW_top25 (no anchor)"),
  subperiods(mk_anchor(2L,"ew"),       "Anchor2 + EW-fill"),
  subperiods(mk_anchor(2L,"alpha"),    "Anchor2 + alpha-fill")
))
print(sep[,.(tag, full=round(full_t,2), y0510=round(t_0510,2), y1116=round(t_1116,2),
             y1722=round(t_1722,2), y2326=round(t_2326,2), pre23=round(pre2023_t,2), post23=round(post2023_t,2))])

cat("\n===== EW active by whether the book HELD the top-2 mega-caps that month (real BM) =====\n")
print(ew_realbench_split())

# fraction of months EW momentum book actually holds a top-2 mega cap
cat("\n[note] This shows: does momentum selection ever pick the mega-caps? If rarely, the anchor is forcing\n")
cat("       exposure momentum would not choose -> anchor lift is a benchmark-tracking effect, not alpha.\n")
cat("\n[stress] DONE\n")
