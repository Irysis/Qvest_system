QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R")
library(data.table); set.seed(4242)
C1<-function(b) engine(dec_freq(1,0),bps=b); A5<-function(b) engine(dec_freq(3,0),bps=b)

cat("=== [V4] 비용 분해 (§1 검증) ===\n")
for(b in c(0,5,15)){
  c1<-MET(C1(b)); a5<-MET(A5(b))
  k<-is.finite(C1(b)$pr)&is.finite(A5(b)$pr)
  dn<-(A5(b)$pr-C1(b)$pr)[k]; dg<-(A5(b)$gross-C1(b)$gross)[k]
  dc<-((b/1e4)*(C1(b)$tov-A5(b)$tov))[k]
  cat(sprintf("  %2dbps | C1 gross=%.4f%% net=%.4f%% TO=%.3f gpt=%.3f npt=%.3f | A5 gross=%.4f%% net=%.4f%% TO=%.3f gpt=%.3f npt=%.3f\n",
    b,c1$gmean*100,c1$amean*100,c1$TO,c1$gpt,c1$pt,a5$gmean*100,a5$amean*100,a5$TO,a5$gpt,a5$pt))
  cat(sprintf("        d_gross=%+.4f%%/yr  d_cost=%+.4f%%/yr  d_net=%+.4f%%/yr | paired t(net)=%+.4f t(gross)=%+.4f | 비용몫=%.1f%%\n",
    mean(dg)*12*100,mean(dc)*12*100,mean(dn)*12*100,nwt(dn),nwt(dg),100*mean(dc)/mean(dn))) }

cat("\n=== [V5] IR 격차 평균효과 vs 변동성효과 (§1-b) ===\n")
c1<-MET(C1(15)); a5<-MET(A5(15))
me<-(a5$amean-c1$amean)/c1$asd; ve<-a5$amean*(1/a5$asd-1/c1$asd)
cat(sprintf("  IR C1=%.4f A5=%.4f 격차=%.4f = 평균효과 %.4f(%.1f%%) + 변동성효과 %.4f(%.1f%%)\n",
  c1$IR,a5$IR,a5$IR-c1$IR,me,100*me/(a5$IR-c1$IR),ve,100*ve/(a5$IR-c1$IR)))
c10<-MET(C1(0)); a50<-MET(A5(0))
cat(sprintf("  0bps active sd: C1=%.4f%% A5=%.4f%% (%+.2f%%)\n",c10$asd*100,a50$asd*100,100*(a50$asd/c10$asd-1)))

cat("\n=== [V6] 부분표본 3분할 (§5-d) ===\n")
k<-which(is.finite(C1(15)$pr)&is.finite(A5(15)$pr)); dn<-(A5(15)$pr-C1(15)$pr)[k]
n<-length(dn); g<-cut(seq_len(n),3,labels=c("T1","T2","T3"))
for(lv in levels(g)){ s<-g==lv
  cat(sprintf("  %s [%s ~ %s] n=%d d_net=%+.4f%%/yr NW-t=%+.4f 승률=%.3f\n",lv,YM[k][which(s)[1]],
    YM[k][tail(which(s),1)],sum(s),mean(dn[s])*12*100,nwt(dn[s]),mean(dn[s]>0))) }

cat("\n=== [V7] 상위 10개월 제거 (§5-e) ===\n")
cat(sprintf("  전체 net 승률=%.4f  평균차=%+.5f%%/yr\n",mean(dn>0),mean(dn)*12*100))
top<-order(abs(dn),decreasing=TRUE)[1:10]
cat(sprintf("  |차| 상위10 기여몫=%.4f | 제거후 평균차=%+.5f%%/yr NW-t=%+.4f\n",
  sum(dn[top])/sum(dn),mean(dn[-top])*12*100,nwt(dn[-top])))
top2<-order(dn,decreasing=TRUE)[1:10]
cat(sprintf("  (부호기준 상위10 제거) 평균차=%+.5f%%/yr NW-t=%+.4f\n",mean(dn[-top2])*12*100,nwt(dn[-top2])))
cat(sprintf("  하위10(최악) 제거 시 평균차=%+.5f%%/yr\n",mean(dn[-order(dn)[1:10]])*12*100))

cat("\n=== [V8] 감쇠율/손익분기 (§6) ===\n")
## reset 계열: 분기 결정 + 매월 목표복귀 (드리프트 제거) — 평균 지연 = (freq-1)/2
res<-list()
for(f in 1:6){ pv<-numeric(f)
  for(p in 0:(f-1)) pv[p+1]<-MET(engine(dec_freq(f,p),bps=0,rebal="reset"))$gmean
  res[[length(res)+1]]<-data.table(freq=f,lag=(f-1)/2,gross=mean(pv)) }
RS<-rbindlist(res); fit<-lm(gross~lag,RS)
cat("  [reset 계열, 0bps, 위상평균 gross active]\n"); print(RS,digits=5)
cat(sprintf("  기울기=%.6f/yr per lag-month  R2=%.5f\n",coef(fit)[2],summary(fit)$r.squared))
dr<-list(); for(f in 1:6){ pv<-numeric(f); tv<-numeric(f)
  for(p in 0:(f-1)){ m<-MET(engine(dec_freq(f,p),bps=0)); pv[p+1]<-m$gmean; tv[p+1]<-m$TO }
  dr[[length(dr)+1]]<-data.table(freq=f,gross=mean(pv),TO=mean(tv)) }
DR<-rbindlist(dr); print(DR,digits=5)
d13<-DR[freq==1]$gross-DR[freq==3]$gross; dTO<-DR[freq==1]$TO-DR[freq==3]$TO
cat(sprintf("  drift 계열 freq1->3: d_gross=%.6f (=%.4f%%/yr)  d_TO=%.4f  손익분기 bps=%.2f\n",
  d13,d13*100,dTO,d13/dTO*1e4))

cat("\n=== [V9] 부분이동 lambda (§7-②) ===\n")
for(l in c(1,0.8,0.6,0.5,0.4)){ m<-MET(engine(dec_freq(1,0),bps=15,lambda=l)); m0<-MET(engine(dec_freq(1,0),bps=0,lambda=l))
  cat(sprintf("  lambda=%.1f: pt=%.4f IR=%.4f TO=%.3f gross=%.4f%% gsd=%.4f%% MDD=%.4f calmar=%.4f\n",
    l,m$pt,m$IR,m$TO,m0$gmean*100,m0$gsd*100,m$MDD,m$calmar)) }
