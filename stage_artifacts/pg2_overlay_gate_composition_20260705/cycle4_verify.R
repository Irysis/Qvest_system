## 자가발전 사이클 4 — C2(mega-cap 앵커+알파) 적대검증
## Q1 벤치허깅 vs 진짜알파: 앵커-only(random/bottom fill) vs 앵커+alpha 분해
## Q2 placebo: score 셔플 50회 → PORT_t null 분포 → p-value
## Q3 lag1 PIT: 알파 score 1개월 지연 → graceful degrade면 진짜, 붕괴면 누출
## Q4 anchor-only(K=2, fill 무관) 자체 PORT_t = 허깅 baseline
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
sp[, score_lag := shift(score_eff,1), by=Ticker]; sp[is.na(score_lag), score_lag := score_eff]
dts <- sort(unique(sp$Date))
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date:=as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym:=format(Date,"%Y-%m")]; bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym:=format(Date,"%Y-%m")]
bo<-0;bc0<--2; for(off in -1:3){e2<-copy(ew);e2[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key");if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret);if(cc>bc0){bc0<-cc;bo<-off}}}
ew[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]
bench<-merge(ew[,.(Date,key)],bmm[,.(key=ym,BM_Ret=bm_ret)],by="key")[,.(Date,BM_Ret)]

## fillmode: alpha / lagalpha / bottom / random(seed)
build_book <- function(K=2L, anch_w=0.20, N=20L, fillmode="alpha", seed=1L){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]
    if(nrow(m) < N+2) next
    setorder(m,-size); anch<-m$Ticker[1:K]; ma<-m[!Ticker %in% anch]; nfill<-N-K
    ord <- switch(fillmode,
      alpha    = order(-ma$score_eff),
      lagalpha = order(-ma$score_lag),
      bottom   = order(ma$score_eff),
      random   = order((((seq_len(nrow(ma))*7919L + i*104729L + seed*1299709L) %% 100000L))))
    sel<-ma[ord][1:nfill]
    tk<-c(anch, sel$Ticker); w<-c(rep(anch_w,K), rep((1-K*anch_w)/nfill, nfill))
    rr<-c(m[match(anch,Ticker),Ret_1m], sel$Ret_1m)
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk,w[match(allt,tk)],0);wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0);wp[is.na(wp)]<-0;turn<-sum(abs(wc-wp)) }
    out$ret[i]<-sum(w*rr)-turn*COST; prevw<-w; prevtk<-tk }
  out[is.finite(ret)]
}
port_t <- function(bk){ pr<-merge(bk,bench,by="Date"); a<-pr$ret-pr$BM_Ret; mu<-mean(a);dm<-a-mu;n<-length(a)
  g0<-sum(dm^2)/n;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; mu/sqrt((g0+gs)/n) }
port_t_win <- function(bk, from){ pr<-merge(bk,bench,by="Date"); pr<-pr[Date>=as.Date(from)]; a<-pr$ret-pr$BM_Ret
  mu<-mean(a);dm<-a-mu;n<-length(a);g0<-sum(dm^2)/n;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; mu/sqrt((g0+gs)/n) }

t_alpha  <- port_t(build_book(fillmode="alpha"))
t_lag    <- port_t(build_book(fillmode="lagalpha"))
t_bottom <- port_t(build_book(fillmode="bottom"))
t_alpha17<- port_t_win(build_book(fillmode="alpha"), "2017-01-01")
t_bot17  <- port_t_win(build_book(fillmode="bottom"), "2017-01-01")
PG("[PG] Q1 decomp full: alpha=%.3f  bottom(anti-alpha)=%.3f  Δ(alpha edge)=%.3f", t_alpha, t_bottom, t_alpha-t_bottom)
PG("[PG] Q1 decomp 2017+: alpha=%.3f  bottom=%.3f  Δ=%.3f", t_alpha17, t_bot17, t_alpha17-t_bot17)
PG("[PG] Q3 lag1 PIT: alpha=%.3f  lagalpha=%.3f (graceful=진짜)", t_alpha, t_lag)

## Q2 placebo: random fill 40 seeds → null PORT_t dist
nullt <- sapply(1:40, function(s) port_t(build_book(fillmode="random", seed=s)))
p_emp <- mean(nullt >= t_alpha)
PG("[PG] Q2 placebo(random fill 40): null mean=%.3f sd=%.3f  alpha=%.3f  p=%.3f", mean(nullt), sd(nullt), t_alpha, p_emp)
res <- data.table(t_alpha_full=t_alpha, t_bottom_full=t_bottom, alpha_edge_full=t_alpha-t_bottom,
  t_alpha_2017=t_alpha17, t_bottom_2017=t_bot17, alpha_edge_2017=t_alpha17-t_bot17,
  t_lagalpha=t_lag, placebo_null_mean=mean(nullt), placebo_p=p_emp)
fwrite(res, file.path(WD,"cycle4_verify_results.csv"))
PG("[PG] DONE cycle4 verify")
