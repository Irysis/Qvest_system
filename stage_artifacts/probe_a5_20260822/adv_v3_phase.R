QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R")
library(data.table)
cat("=== [V2] 위상 표: (a) 공통시작(colleague 방식) vs (b) 시작이동(R11 방식) ===\n")
out<-list()
for(p in 0:2){
  a15<-MET(engine(dec_freq(3,p),bps=15)); a0<-MET(engine(dec_freq(3,p),bps=0))
  out[[length(out)+1]]<-data.table(방식="공통시작(m=13)",phase=p,n=a15$n,pt15=a15$pt,pt0=a0$pt,
    IR15=a15$IR,TO=a15$TO,gmean=a0$gmean,gsd=a0$gsd) }
## R11 방식: start_m = 13+off  (표본 이동)
for(p in 0:2){ sm<-13L+p; d<-dec_freq(3,0,start_m=sm)
  a15<-MET(engine(d,bps=15,start_m=sm)); a0<-MET(engine(d,bps=0,start_m=sm))
  out[[length(out)+1]]<-data.table(방식="시작이동(R11)",phase=p,n=a15$n,pt15=a15$pt,pt0=a0$pt,
    IR15=a15$IR,TO=a15$TO,gmean=a0$gmean,gsd=a0$gsd) }
O<-rbindlist(out); print(O,digits=4)
cat(sprintf("\n  공통시작 위상평균 pt15 = %.4f | 시작이동 위상평균 pt15 = %.4f\n",
  mean(O[방식=="공통시작(m=13)"]$pt15), mean(O[방식=="시작이동(R11)"]$pt15)))
c1<-MET(engine(dec_freq(1,0),bps=15)); c10<-MET(engine(dec_freq(1,0),bps=0))
cat(sprintf("  C1 월간 pt15=%.4f pt0=%.4f\n",c1$pt,c10$pt))

cat("\n=== [V3] A5E 3-코호트 중첩 앙상블 (실행가능한 위상중립판) ===\n")
## 각 코호트: 공통시작 m=13, 위상 p. 자본 1/3씩. 전체 수익 = 코호트 수익 평균.
ens<-function(bps=15,freq=3,S=S12,lambda=1){
  PR<-GR<-TO<-matrix(NA_real_,freq,NM)
  for(p in 0:(freq-1)){ r<-engine(dec_freq(freq,p),S=S,bps=bps,lambda=lambda)
    PR[p+1,]<-r$pr; GR[p+1,]<-r$gross; TO[p+1,]<-r$tov }
  ok<-apply(PR,2,function(v) all(is.finite(v)))
  pr<-gr<-tov<-rep(NA_real_,NM)
  pr[ok]<-colMeans(PR[,ok,drop=FALSE]); gr[ok]<-colMeans(GR[,ok,drop=FALSE]); tov[ok]<-colMeans(TO[,ok,drop=FALSE])
  list(pr=pr,gross=gr,tov=tov) }
for(bps in c(0,5,15,25,40)){ m<-MET(ens(bps))
  cat(sprintf("  A5E %2dbps: pt=%.4f IR=%.4f SR=%.3f MDD=%.4f calmar=%.4f TO=%.3f n=%d\n",
    bps,m$pt,m$IR,m$SR,m$MDD,m$calmar,m$TO,m$n)) }
cat("  (대조) C1 월간 15bps: pt=%s\n")
cat(sprintf("  C1 15bps: pt=%.4f IR=%.4f SR=%.3f MDD=%.4f calmar=%.4f TO=%.3f\n",
  c1$pt,c1$IR,c1$SR,c1$MDD,c1$calmar,c1$TO))
a5<-MET(engine(dec_freq(3,0),bps=15))
cat(sprintf("  A5(phase0) 15bps: pt=%.4f IR=%.4f SR=%.3f MDD=%.4f calmar=%.4f TO=%.3f\n",
  a5$pt,a5$IR,a5$SR,a5$MDD,a5$calmar,a5$TO))
e15<-MET(ens(15))
cat(sprintf("\n  ** 앙상블 pt(%.4f) vs 위상별 pt 단순평균(%.4f) 차 = %+.4f **\n",
  e15$pt, mean(O[방식=="공통시작(m=13)"]$pt15), e15$pt-mean(O[방식=="공통시작(m=13)"]$pt15)))
## paired vs C1
kk<-is.finite(ens(15)$pr)&is.finite(engine(dec_freq(1,0),bps=15)$pr)
d<-(ens(15)$pr-engine(dec_freq(1,0),bps=15)$pr)[kk]
cat(sprintf("  A5E - C1 paired: mean=%+.4f%%/yr NW-t=%+.4f\n",mean(d)*12*100,nwt(d)))
d0<-(ens(0)$pr-engine(dec_freq(1,0),bps=0)$pr)[kk]
cat(sprintf("  A5E - C1 paired (0bps): mean=%+.4f%%/yr NW-t=%+.4f\n",mean(d0)*12*100,nwt(d0)))
saveRDS(list(ens=ens),"stage_artifacts/probe_a5_20260822/adv_ens_fn.rds")
fwrite(O,"stage_artifacts/probe_a5_20260822/adv_phase_table.csv")
