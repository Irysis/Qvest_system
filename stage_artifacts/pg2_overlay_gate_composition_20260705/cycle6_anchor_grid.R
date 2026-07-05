## 사이클 6 — 앵커 K×weight 그리드: calmar-oos tradeoff 스위트스팟 탐색.
## C1(K1,0.20): calmar 0.664✓ oos 0.415✗ / C2(K2,0.20): calmar 0.580✗ oos 0.894✓ → 중간 config가 양 HARD 동시통과?
## 게이트(자본급): PORT_t>=2.95 ∧ oos_ret>=0.7 ∧ calmar>=0.64 (selection 레이어, 오버레이 前 보수적).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))
COST <- 0.0015
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE); dts <- sort(unique(sp$Date))
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2; for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]

build_book <- function(K, anch_w, N=20L){
  prevfill<-NULL; prevtk<-NULL; prevw<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]; if(nrow(m)<N) next
    setorder(m,-size); anch<-if(K>0) m$Ticker[1:K] else character(0)
    ma<-m[!Ticker %in% anch]; setorder(ma,-score_eff); nfill<-N-K; sel<-ma[1:nfill]
    a_t<-sel$score_eff; names(a_t)<-sel$Ticker
    fw<-linear_tilt_to_penalty_qd(a_t, lambda=1.5, w_prev=prevfill, phi=3.0, lb=0, ub=0.20)
    tk<-c(anch, names(fw)); w<-c(rep(anch_w,K), as.numeric(fw)*(1-K*anch_w))
    rr<-c(m[match(anch,Ticker),Ret_1m], sel$Ret_1m[match(names(fw),sel$Ticker)])
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk,w[match(allt,tk)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[i]<-sum(w*rr)-turn*COST; prevfill<-fw; prevtk<-tk; prevw<-w }
  out[is.finite(ret)]
}
metr <- function(bk, tag){ pr<-merge(bk, bench, by="Date"); if(nrow(pr)<50) return(NULL)
  prt<-data.table(date=pr$Date, ret_net=pr$ret, frequency="monthly"); brt<-data.table(date=pr$Date, benchmark_ret=pr$BM_Ret, benchmark_id="KOSPI200")
  bc<-build_benchmark_compare(prt, brt, tag, tag, annualization_factor=12); gv<-function(n){v<-bc[metric_name==n,active_value]; if(length(v)) as.numeric(v[1]) else NA_real_}
  act<-pr$ret-pr$BM_Ret; n<-nrow(pr)
  oos<-median(sapply(c(0.55,0.65,0.75),function(q){cut<-floor(n*q);(mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE)
  p2<-pr[Date>=as.Date("2017-01-01")]; a2<-p2$ret-p2$BM_Ret; m2<-mean(a2); dm<-a2-m2; nn<-length(a2)
  g0<-sum(dm^2)/nn; gs<-0; for(L in 1:3){wt<-1-L/4; gs<-gs+2*wt*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn}; p17<-m2/sqrt((g0+gs)/nn)
  rx<-xts(pr$ret, order.by=pr$Date); cagr<-as.numeric(Return.annualized(rx, scale=12)); mdd<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag, PORT_t=gv("Portfolio_Alpha_t_NW_lag3"), IR=gv("Information_Ratio"), oos_ret=oos, post2017_t=p17, cagr=cagr, mdd=mdd, calmar=if(mdd>0) cagr/mdd else NA_real_) }

grid<-CJ(K=c(1L,2L), w=c(0.12,0.14,0.16,0.18,0.20))
rows<-list()
for(j in seq_len(nrow(grid))){ K<-grid$K[j]; w<-grid$w[j]; r<-metr(build_book(K,w),sprintf("K%d_w%.2f",K,w)); if(!is.null(r)) rows[[length(rows)+1]]<-r }
res<-rbindlist(rows)
res[, pass_all := is.finite(PORT_t)&PORT_t>=2.95 & is.finite(oos_ret)&oos_ret>=0.7 & is.finite(calmar)&calmar>=0.64]
setorder(res, -pass_all, -calmar)
print(res[, .(tag, PORT_t=round(PORT_t,2), oos_ret=round(oos_ret,3), post2017_t=round(post2017_t,2), calmar=round(calmar,3), mdd=round(mdd,3), pass_all)])
np<-sum(res$pass_all,na.rm=TRUE)
PG("[GRID] configs passing ALL 3 HARD gates (PORT_t>=2.95 ∧ oos>=0.7 ∧ calmar>=0.64): %d", np)
if(np>0){ b<-res[pass_all==TRUE][1]; PG("[MILESTONE-CANDIDATE] %s: PORT_t=%.2f oos=%.3f calmar=%.3f post2017_t=%.2f", b$tag,b$PORT_t,b$oos_ret,b$calmar,b$post2017_t) }
fwrite(res, file.path(WD,"cycle6_anchor_grid_results.csv"))
