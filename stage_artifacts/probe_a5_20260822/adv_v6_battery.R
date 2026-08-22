QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R")
library(data.table); set.seed(20260822)
oosret<-function(a,af=12){ n<-length(a); sp<-c(.55,.65,.75)
  r<-sapply(sp,function(fr){k<-floor(n*fr); if(k<6||(n-k)<6) return(NA_real_)
    ia<-a[1:k]; oa<-a[(k+1):n]; ii<-mean(ia)/sd(ia)*sqrt(af); oo<-mean(oa)/sd(oa)*sqrt(af)
    if(is.finite(ii)&&ii>0.05&&is.finite(oo)) oo/ii else NA_real_})
  list(med=median(r[is.finite(r)]),splits=r) }
C1<-engine(dec_freq(1,0),bps=15); A5<-engine(dec_freq(3,0),bps=15)
ensf<-function(bps=15,freq=3){ PR<-GR<-TO<-matrix(NA_real_,freq,NM)
  for(p in 0:(freq-1)){r<-engine(dec_freq(freq,p),bps=bps); PR[p+1,]<-r$pr; GR[p+1,]<-r$gross; TO[p+1,]<-r$tov}
  ok<-apply(PR,2,function(v)all(is.finite(v))); pr<-gr<-tov<-rep(NA_real_,NM)
  pr[ok]<-colMeans(PR[,ok,drop=F]); gr[ok]<-colMeans(GR[,ok,drop=F]); tov[ok]<-colMeans(TO[,ok,drop=F])
  list(pr=pr,gross=gr,tov=tov) }

cat("=== [V10] oos_retention v2 독립 재산출 (essence_score 미호출 = 레지스트리 무오염) ===\n")
for(nm in c("C1","A5_p0","A5_p1","A5_p2","A5E")){
  r<-switch(nm,C1=C1,A5_p0=A5,A5_p1=engine(dec_freq(3,1),bps=15),A5_p2=engine(dec_freq(3,2),bps=15),A5E=ensf(15))
  m<-MET(r); o<-oosret(m$act)
  cat(sprintf("  %-6s pt=%.4f oos_med=%.4f splits=[%s] calmar=%.4f MDD=%.4f\n",nm,m$pt,o$med,
    paste(sprintf("%.3f",o$splits),collapse=", "),m$calmar,m$MDD)) }

cat("\n=== [V11] 마지막 부분월(2026-08, 13영업일) 민감도 ===\n")
kk<-which(is.finite(C1$pr)&is.finite(A5$pr))
for(cut in list(list(l="전체(2026-08 포함)",drop=0),list(l="2026-08 제외",drop=1),
                list(l="2026 전체 제외",drop=sum(substr(YM[kk],1,4)=="2026")))){
  idx<-kk[seq_len(length(kk)-cut$drop)]
  a5<-A5$pr[idx]-MKT[idx]; c1<-C1$pr[idx]-MKT[idx]; d<-A5$pr[idx]-C1$pr[idx]
  cat(sprintf("  %-16s n=%3d | A5 pt=%.4f | C1 pt=%.4f | d_net=%+.4f%%/yr t=%+.3f\n",
    cut$l,length(idx),nwt(a5),nwt(c1),mean(d)*12*100,nwt(d))) }
## 위상별로도
cat("  [2026-08 제외 시 위상표]\n")
for(p in 0:2){ r<-engine(dec_freq(3,p),bps=15); k2<-which(is.finite(r$pr)); k2<-k2[-length(k2)]
  cat(sprintf("    phase%d pt=%.4f (전체 %.4f)\n",p,nwt(r$pr[k2]-MKT[k2]),MET(r)$pt)) }
e<-ensf(15); ke<-which(is.finite(e$pr)); ke2<-ke[-length(ke)]
cat(sprintf("    A5E    pt=%.4f (전체 %.4f)\n",nwt(e$pr[ke2]-MKT[ke2]),MET(e)$pt))

cat("\n=== [V12] 위상 = 달력분기 정렬 (경제적 내용 有無 검정) ===\n")
dm<-function(p){ d<-dec_freq(3,p); as.integer(substr(YM[which(d)],6,7)) }
for(p in 0:2) cat(sprintf("  phase%d 결정 적용월(캘린더) = %s\n",p,paste(sort(unique(dm(p))),collapse="/")))
## 월별 d_net
d<-(A5$pr-C1$pr)[kk]; cm<-as.integer(substr(YM[kk],6,7))
tb<-data.table(mo=cm,d=d)[,.(n=.N,mean_pct=mean(d)*100,t=ifelse(.N>=12,nwt(d),NA)),by=mo][order(mo)]
print(tb,digits=3)
cat(sprintf("  결정직후월(1/4/7/10) 평균차=%+.4f%%/월 vs 나머지 %+.4f%%/월\n",
  mean(d[cm %in% c(1,4,7,10)])*100, mean(d[!cm %in% c(1,4,7,10)])*100))

cat("\n=== [V13] 분기내 위치별 (§5-g) ===\n")
qk<-rep(c(1,2,3),length.out=length(kk))
dg<-(A5$gross-C1$gross)[kk]; dc<-((15/1e4)*(C1$tov-A5$tov))[kk]
for(q in 1:3) cat(sprintf("  q%d: net=%+.4f%% gross=%+.4f%% cost=%+.4f%% (n=%d)\n",q,
  mean(d[qk==q])*100,mean(dg[qk==q])*100,mean(dc[qk==q])*100,sum(qk==q)))

cat("\n=== [V14] 블록 부트스트랩 (block=12, B=3000) — §5-f ===\n")
n<-length(d); B<-3000; bl<-12; nb<-ceiling(n/bl); bs<-numeric(B)
for(i in 1:B){ st<-sample(1:(n-bl+1),nb,replace=TRUE)
  v<-unlist(lapply(st,function(s)d[s:(s+bl-1)]))[1:n]; bs[i]<-mean(v) }
cat(sprintf("  15bps: mean=%.6f/월 CI95=[%.6f, %.6f] P(mean>0)=%.4f\n",mean(bs),quantile(bs,.025),quantile(bs,.975),mean(bs>0)))
d0<-(engine(dec_freq(3,0),bps=0)$pr-engine(dec_freq(1,0),bps=0)$pr)[kk]
bs0<-numeric(B); for(i in 1:B){ st<-sample(1:(n-bl+1),nb,replace=TRUE)
  v<-unlist(lapply(st,function(s)d0[s:(s+bl-1)]))[1:n]; bs0[i]<-mean(v) }
cat(sprintf("  0bps : mean=%.6f/월 CI95=[%.6f, %.6f] P(mean>0)=%.4f\n",mean(bs0),quantile(bs0,.025),quantile(bs0,.975),mean(bs0>0)))

cat("\n=== [V15] 감쇠 회귀 R2 (freq 1..6 vs 1..6,12) ===\n")
RS<-data.table(freq=c(1,2,3,4,5,6,12))
RS[,lag:=(freq-1)/2]
RS[,gross:=sapply(freq,function(f) mean(sapply(0:(f-1),function(p) MET(engine(dec_freq(f,p),bps=0,rebal="reset"))$gmean)))]
print(RS,digits=6)
f1<-lm(gross~lag,RS[freq<=6]); f2<-lm(gross~lag,RS)
cat(sprintf("  freq<=6 : slope=%.6f R2=%.5f | freq<=6+12: slope=%.6f R2=%.5f\n",
  coef(f1)[2],summary(f1)$r.squared,coef(f2)[2],summary(f2)$r.squared))

cat("\n=== [V16] Market-100%% fallback 발화율 & 켜진 팩터 수 ===\n")
non<-sapply(12:(NM-1),function(dd) sum(is.finite(S12[dd,])&S12[dd,]>0))
cat(sprintf("  결정월 후보 %d개 | 평균 켜짐=%.2f/21 | fallback(0개) 발생=%d회 | 최소=%d 최대=%d\n",
  length(non),mean(non),sum(non==0),min(non),max(non)))
