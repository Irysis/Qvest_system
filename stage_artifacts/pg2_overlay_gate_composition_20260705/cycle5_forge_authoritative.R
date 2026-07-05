## 사이클 5 — mega-cap 앵커 forge-authoritative escalation (production LinearTilt fidelity)
## cycle3 EW-fill 근사 → production STR_1715 LinearTilt λ1.5·φ3.0 (strategy_tilt_weights.R verbatim)로 교체.
## 판정: C2 앵커가 production 가중서도 자본급(PORT_t>=2.95 · oos band · calmar>=0.64) 유지하는가.
## 측정: build_benchmark_compare(authoritative PORT_t NW lag-3) + PerformanceAnalytics(calmar) + oos 3-split + post2017 NW.
## 적대: placebo(random anchor) + lag1(PIT). book-marginal ΔIR vs incumbent 1.416.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1); set.seed(20260706)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))
COST <- 0.0015; INCUMBENT_IR <- 1.416

sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
dts <- sort(unique(sp$Date))

## cap-weighted benchmark aligned (cycle3 beta-scan offset verbatim)
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2; for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]

## build book: anchor top-K by size at anch_w; fill (N-K) by production LinearTilt on score_eff scaled to (1-K*anch_w).
## mode: "alpha" (score_eff fill), "placebo" (random fill of same N), lag: return realization lag (PIT test).
build_book <- function(K, anch_w, N=20L, mode="alpha", lag=0){
  prevfill<-NULL; prevtk<-NULL; prevw<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]
    if(nrow(m)<N) next
    setorder(m,-size); anch<-if(K>0) m$Ticker[1:K] else character(0)
    ma<-m[!Ticker %in% anch]; nfill<-N-K
    if(mode=="placebo"){ sel<-ma[sample(.N, min(nfill,.N))] } else { setorder(ma,-score_eff); sel<-ma[1:nfill] }
    a_t<-sel$score_eff; names(a_t)<-sel$Ticker
    fw<-linear_tilt_to_penalty_qd(a_t, lambda=1.5, w_prev=prevfill, phi=3.0, lb=0, ub=0.20)
    fill_total<-1 - K*anch_w
    tk<-c(anch, names(fw)); w<-c(rep(anch_w,K), as.numeric(fw)*fill_total)
    rr<-c(m[match(anch,Ticker),Ret_1m], sel$Ret_1m[match(names(fw),sel$Ticker)])
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk,w[match(allt,tk)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[i]<-sum(w*rr)-turn*COST; prevfill<-fw; prevtk<-tk; prevw<-w }
  bk<-out[is.finite(ret)]
  if(lag>0){ bk<-copy(bk); bk[, ret := shift(ret, lag)]; bk<-bk[is.finite(ret)] }  # PIT: realize with lag
  bk
}

metr <- function(bk, tag){
  pr<-merge(bk, bench, by="Date"); if(nrow(pr)<50) return(NULL)
  prt<-data.table(date=pr$Date, ret_net=pr$ret, frequency="monthly")
  brt<-data.table(date=pr$Date, benchmark_ret=pr$BM_Ret, benchmark_id="KOSPI200")
  bc<-build_benchmark_compare(prt, brt, tag, tag, annualization_factor=12)
  gv<-function(n){v<-bc[metric_name==n,active_value]; if(length(v)) as.numeric(v[1]) else NA_real_}
  act<-pr$ret-pr$BM_Ret; n<-nrow(pr)
  oos<-median(sapply(c(0.55,0.65,0.75),function(q){cut<-floor(n*q);(mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE)
  p2<-pr[Date>=as.Date("2017-01-01")]; a2<-p2$ret-p2$BM_Ret; m2<-mean(a2); dm<-a2-m2; nn<-length(a2)
  g0<-sum(dm^2)/nn; gs<-0; for(L in 1:3){wt<-1-L/4; gs<-gs+2*wt*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn}; p17<-m2/sqrt((g0+gs)/nn)
  rx<-xts(pr$ret, order.by=pr$Date)
  cagr<-as.numeric(Return.annualized(rx, scale=12)); mdd<-as.numeric(maxDrawdown(rx)); calmar<-if(mdd>0) cagr/mdd else NA_real_
  data.table(tag=tag, n=n, PORT_t=gv("Portfolio_Alpha_t_NW_lag3"), IR=gv("Information_Ratio"),
    net_active_sr=mean(act)/sd(act)*sqrt(12), oos_ret=oos, post2017_t=p17,
    cagr=cagr, mdd=mdd, calmar=calmar) }

## ── C0 production baseline (LinearTilt, no anchor) vs C2 anchor(top-2) ──
res<-rbindlist(list(
  metr(build_book(0,0.0),  "C0_LT_baseline"),
  metr(build_book(2,0.20), "C2_LT_anchor2"),
  metr(build_book(1,0.20), "C1_LT_anchor1"),
  metr(build_book(3,0.20), "C3_LT_anchor3")
), fill=TRUE)
## placebo: random-fill anchor2 (20 draws) — anchor value must exceed placebo null
plc<-sapply(1:20, function(s){ set.seed(s); r<-metr(build_book(2,0.20,mode="placebo"),"plc"); if(is.null(r)) NA_real_ else r$PORT_t })
## lag1 PIT
lag1<-metr(build_book(2,0.20,lag=1),"C2_lag1")
res[, c("gate_PORT_2.95","gate_calmar_0.64") := .(is.finite(PORT_t)&PORT_t>=2.95, is.finite(calmar)&calmar>=0.64)]
res[, oos_band := fifelse(oos_ret>=0.7,"PASS", fifelse(oos_ret>=0.5,"BAND[0.5,0.7)","FAIL(<0.5)"))]
print(res[, .(tag,n,PORT_t=round(PORT_t,3),IR=round(IR,3),oos_ret=round(oos_ret,3),oos_band,post2017_t=round(post2017_t,3),calmar=round(calmar,3),gate_PORT_2.95,gate_calmar_0.64)])
c2<-res[tag=="C2_LT_anchor2"]; c0<-res[tag=="C0_LT_baseline"]
PG("[VERIFY] C2 PORT_t=%.3f vs placebo null mean=%.3f sd=%.3f  p=%.3f", c2$PORT_t, mean(plc,na.rm=T), sd(plc,na.rm=T), mean(plc>=c2$PORT_t,na.rm=T))
PG("[VERIFY] C2 lag1 PORT_t=%.3f (PIT: graceful if not collapsed/reversed)", if(!is.null(lag1)) lag1$PORT_t else NA)
PG("[BOOK-MARGINAL] C2 net_active IR=%.3f vs incumbent %.3f  ΔIR=%.3f (>=0.05 admit-eligible)", c2$IR, INCUMBENT_IR, c2$IR-INCUMBENT_IR)
PG("[Δvs baseline] ΔPORT_t=%.3f Δoos=%.3f Δpost2017_t=%.3f (anchor lever over production LinearTilt)", c2$PORT_t-c0$PORT_t, c2$oos_ret-c0$oos_ret, c2$post2017_t-c0$post2017_t)
fwrite(res, file.path(WD,"cycle5_forge_authoritative_results.csv"))
saveRDS(list(res=res, placebo=plc, lag1=lag1), file.path(WD,"cycle5_full.rds"))
PG("[DONE] cycle5. MILESTONE if C2: gate_PORT & (oos>=0.7 or band+2/3) & calmar>=0.64 & ΔIR>=0.05 & placebo p<0.05")
