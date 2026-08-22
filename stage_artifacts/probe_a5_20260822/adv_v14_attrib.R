QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R"); library(data.table)
C1<-engine(dec_freq(1,0),bps=15); A5<-engine(dec_freq(3,0),bps=15)
kk<-which(is.finite(C1$pr)); dn<-(A5$pr-C1$pr)[kk]
top<-order(abs(dn),decreasing=TRUE)[1:10]
cat("=== [V21] '§5(e) 상위10개월이 phase0 gross 프리미엄의 근거' 인과주장 검정 ===\n")
G<-sapply(0:2,function(p) (engine(dec_freq(3,p),bps=0)$gross)[kk]-MKT[kk])
prem<-G[,1]-rowMeans(G)                                   # phase0 gross active − 위상평균
cat(sprintf("  phase0 gross 프리미엄 = %+.4f%%/yr (전체)\n",mean(prem)*12*100))
cat(sprintf("  A5-C1 |차| 상위10개월 제거 후 프리미엄 = %+.4f%%/yr (기여몫 %.3f)\n",
  mean(prem[-top])*12*100, (sum(prem)-sum(prem[-top]))/sum(prem)))
pt10<-order(abs(prem),decreasing=TRUE)[1:10]
cat(sprintf("  프리미엄 자체의 상위10개월 제거 후 = %+.4f%%/yr (기여몫 %.3f) — 겹치는 달 %d/10\n",
  mean(prem[-pt10])*12*100,(sum(prem)-sum(prem[-pt10]))/sum(prem), length(intersect(top,pt10))))
cat(sprintf("  corr(|A5-C1 차|, |프리미엄|) = %+.4f\n",cor(abs(dn),abs(prem))))
cat("\n=== [V22] 최종 요약표 (모든 판정 축) ===\n")
ens<-function(bps=15){PR<-matrix(NA_real_,3,NM);for(p in 0:2)PR[p+1,]<-engine(dec_freq(3,p),bps=bps)$pr
  ok<-apply(PR,2,function(v)all(is.finite(v)));pr<-rep(NA_real_,NM);pr[ok]<-colMeans(PR[,ok,drop=F]);list(pr=pr,gross=pr,tov=rep(0,NM),W=matrix(0,NM,NAX))}
oosret<-function(a,af=12){n<-length(a);sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr)
  ia<-a[1:k];oa<-a[(k+1):n];ii<-mean(ia)/sd(ia)*sqrt(af);oo<-mean(oa)/sd(oa)*sqrt(af)
  if(ii>0.05) oo/ii else NA})}
for(nm in c("C1","A5_p0","A5_p1","A5_p2","A5E")){
  r<-switch(nm,C1=C1,A5_p0=A5,A5_p1=engine(dec_freq(3,1),bps=15),A5_p2=engine(dec_freq(3,2),bps=15),A5E=ens(15))
  m<-MET(r); o<-oosret(m$act)
  cat(sprintf("  %-6s pt=%.3f[%s] oos=%.3f[%s] calmar=%.3f[F] -> HARD %s\n",nm,m$pt,
    ifelse(m$pt>=2.95,"P","F"),median(o[is.finite(o)]),
    ifelse(median(o[is.finite(o)])>=0.7,"P",ifelse(median(o[is.finite(o)])>=0.5,"b","F")),m$calmar,
    paste0(ifelse(m$pt>=2.95,"P","F"),ifelse(median(o[is.finite(o)])>=0.7,"P","F"),"F"))) }
