## ============================================================================
## 공격형 bull-conviction 오버레이 — strict PIT + overlay_pit_guard 내장
## 가설: bull 확신 높은 달엔 alpha가 더 잘 먹힘 → top-score 종목 비중↑(λ 상향).
##   defensive와 달리 수익을 *더할* 수 있어 ΔIR 통과 여지.
## 신호(bull_conf) = 1 − Bear_Prob 확장백분위, ★holdings_signal_cutoff(홀딩월 시작 전) 로드.
## 검증: assert_overlay_pit(가드) + 조건부 IC + lag1 + strict-A/B(anchor-like 대비 인플레).
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
source(file.path(ROOT,"02_Infrastructure/validation/overlay_pit_guard.R"))   # ★PIT 가드
NSEL<-20L; LAM_BASE<-1.5; PHI<-3; UB<-0.20

sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]; dts <- sort(unique(sp$Date))

## ---- bull 신호: 1 − Bear_Prob, ★strict PIT (holdings_signal_cutoff = 홀딩월 시작 전) ----
urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache/regime_jump_daily.parquet")))
urs[,Date:=as.Date(Date)];setorder(urs,Date);urs<-urs[is.finite(Bear_Prob_lag)]
cutoff_strict <- as.Date(sapply(dts, function(d) as.character(holdings_signal_cutoff(d))))   # first-day(month(D)+1)
holding_start <- cutoff_strict
assert_overlay_pit(cutoff_strict, holding_start, "bull_conviction")   # ★HARD: 컷오프≤홀딩월시작
raw_bull <- rep(NA_real_, length(dts))
for(i in seq_along(dts)){ pv<-urs[Date < cutoff_strict[i]]; if(nrow(pv)>0) raw_bull[i]<- -tail(pv$Bear_Prob_lag,1) }  # −bear = bull-ness
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
bull_conf <- epct(raw_bull)   # [0,1], 1=강한 bull 확신
bull_dt <- data.table(Date=dts, bull_conf=bull_conf)
PG("[PG] bull_conf 평균=%.3f  가드 assert PASS (컷오프=홀딩월 시작 전)", mean(bull_conf))

## ---- 조건부 IC: bull tercile별 rank-IC (가설 근거 확인) ----
sp2 <- merge(sp, bull_dt, by="Date")
ic_by <- sp2[is.finite(score_eff)&is.finite(Ret_1m), .(ic=cor(score_eff,Ret_1m,method="spearman"),.N), by=.(Date,bull_conf)]
ic_by[, terc := cut(bull_conf, quantile(bull_conf,c(0,.33,.67,1),na.rm=T), labels=c("low_bull","mid","high_bull"), include.lowest=T)]
PG("[PG] 조건부 rank-IC: %s", paste(ic_by[,.(ic=round(mean(ic,na.rm=T),4)),by=terc][order(terc)][, sprintf("%s=%.4f",terc,ic)], collapse=" | "))

## ---- weight builders ----
norm_lo<-function(w,ub=UB){w[w<0]<-0;if(sum(w)==0)return(w);w<-w/sum(w);for(it in 1:50){o<-w>ub;if(!any(o))break;ex<-sum(w[o]-ub);w[o]<-ub;fr<-!o&w>0;if(!any(fr))break;w[fr]<-w[fr]+ex*w[fr]/sum(w[fr])};w[w>ub]<-ub;w/sum(w)}
ltilt<-function(s,lam){N<-length(s);r<-rank(s,ties.method="average");ce<-(r-(N+1)/2)/((N-1)/2);norm_lo(pmax(0,1+lam*2*ce))}

## bench (cap-w KOSPI200, 홀딩월=month(D)+1 정렬)
bm<-as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet")));bm[,Date:=as.Date(Date)]
bm<-bm[is.finite(BM_Ret)];bm[,ym:=format(Date,"%Y-%m")];bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
bench_of<-function(d){ hm<-format(holdings_signal_cutoff(d),"%Y-%m"); v<-bmm[ym==hm,bm_ret]; if(length(v))v[1] else NA_real_ }
benchv<-sapply(dts, bench_of)

## build path with lambda(t) = LAM_BASE*(1+kappa*(bull_conf-0.5)*2) ; kappa=0 → base
build<-function(kappa, lam_fn=NULL, conf=bull_conf){
  prevw<-NULL;prevtk<-NULL;out<-data.table(Date=dts,ret=NA_real_)
  for(k in seq_along(dts)){D<-dts[k]
    m<-sp[Date==D & is.finite(score_eff)&is.finite(Ret_1m)]; if(nrow(m)<NSEL)next
    setorder(m,-score_eff); sel<-m[1:NSEL]
    lam <- if(!is.null(lam_fn)) lam_fn(conf[k]) else LAM_BASE*(1+kappa*(conf[k]-0.5)*2)
    lam <- max(0.2, lam)
    w<-ltilt(sel$score_eff, lam)
    if(!is.null(prevw)){wpa<-ifelse(sel$Ticker%in%prevtk,prevw[match(sel$Ticker,prevtk)],0);wpa[is.na(wpa)]<-0
      w<-norm_lo((PHI/(1+PHI))*wpa+(1/(1+PHI))*w)}
    if(is.null(prevw))turn<-1 else{allt<-union(sel$Ticker,prevtk);wc<-ifelse(allt%in%sel$Ticker,w[match(allt,sel$Ticker)],0);wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0);wp[is.na(wp)]<-0;turn<-sum(abs(wc-wp))}
    out$ret[k]<-sum(w*sel$Ret_1m)-turn*COST;prevw<-w;prevtk<-sel$Ticker}
  out
}
met<-function(bk,tag){pr<-merge(bk[is.finite(ret)],data.table(Date=dts,bm=benchv),by="Date");pr<-pr[is.finite(bm)]
  x<-xts(pr$ret,order.by=pr$Date);act<-pr$ret-pr$bm;mu<-mean(act);dm<-act-mu;nn<-length(act);g0<-sum(dm^2)/nn;gs<-0
  for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};pt<-mu/sqrt((g0+gs)/nn)
  data.table(tag=tag,SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),MDD=as.numeric(maxDrawdown(x)),
    PORT_t=pt,IR=mu/sd(act)*sqrt(12),ret=list(pr$ret))}
base<-build(0)
rows<-list(met(base,"base_lam1.5"))
for(kap in c(0.5,1.0,2.0)){ b<-build(kap); rows[[length(rows)+1]]<-met(b,sprintf("bull_kappa%.1f",kap)) }
## 이진판: high-bull tercile λ=2.5, else 1.0
b_bin<-build(0, lam_fn=function(c) if(c>=quantile(bull_conf,.67,na.rm=T)) 2.5 else 1.0)
rows[[length(rows)+1]]<-met(b_bin,"bull_binary_hi2.5")
res<-rbindlist(lapply(rows,function(r)r[,.(tag,SR,MDD,PORT_t,IR)]))
b0<-res[tag=="base_lam1.5"]; res[, dPORT_t := PORT_t-b0$PORT_t]; res[, dSR := SR-b0$SR]
print(res[,.(tag,SR=round(SR,3),MDD=round(MDD,3),PORT_t=round(PORT_t,3),IR=round(IR,3),dSR=round(dSR,3),dPORT_t=round(dPORT_t,3))])

## ---- ★strict-PIT A/B: strict(홀딩월시작 전) vs anchor-like(1개월 뒤) 인플레 확인 ----
cutoff_loose <- as.Date(sapply(dts, function(d) as.character(holdings_signal_cutoff(d) %m+% months(1))))  # 1개월 뒤=look-ahead
raw_loose<-rep(NA_real_,length(dts));for(i in seq_along(dts)){pv<-urs[Date<cutoff_loose[i]];if(nrow(pv)>0)raw_loose[i]<- -tail(pv$Bear_Prob_lag,1)}
conf_loose<-epct(raw_loose)
b_strict<-met(build(1.0,conf=bull_conf),"strict"); b_loose<-met(build(1.0,conf=conf_loose),"loose")
ab<-overlay_lookahead_ab(b_loose$PORT_t, b_strict$PORT_t, "PORT_t(kappa1.0)")
PG("[PG] %s", ab$message)
## lag1: bull_conf 1개월 지연
conf_lag<-c(0.5, bull_conf[-length(bull_conf)]); b_lag<-met(build(1.0,conf=conf_lag),"lag1")
PG("[PG] lag1 스트레스: strict PORT_t=%.3f → lag1 PORT_t=%.3f (base %.3f)", b_strict$PORT_t, b_lag$PORT_t, b0$PORT_t)
fwrite(res, file.path(WD,"bull_conviction_results.csv"))
PG("[PG] DONE bull_conviction")
