QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R")
library(data.table); set.seed(777)
C1<-engine(dec_freq(1,0),bps=15)
cat("=== [V17] 위상 우열의 부분표본 안정성 (달력효과 vs 단일 draw) ===\n")
kk<-which(is.finite(C1$pr)); g<-cut(seq_along(kk),3,labels=c("T1","T2","T3"))
P<-list(); for(p in 0:2){ r<-engine(dec_freq(3,p),bps=15); r0<-engine(dec_freq(3,p),bps=0)
  for(lv in c("전체",levels(g))){ s<- if(lv=="전체") rep(TRUE,length(kk)) else g==lv
    idx<-kk[s]; P[[length(P)+1]]<-data.table(phase=p,seg=lv,n=sum(s),
      pt=nwt(r$pr[idx]-MKT[idx]), gross_act=mean(r0$gross[idx]-MKT[idx])*12*100,
      net_act=mean(r$pr[idx]-MKT[idx])*12*100) } }
PT<-rbindlist(P); print(dcast(PT,seg~phase,value.var="gross_act"),digits=4)
cat("  (위 = 구간별 gross active %/yr, 열=phase)\n")
print(dcast(PT,seg~phase,value.var="pt"),digits=4); cat("  (위 = 구간별 net pt)\n")

cat("\n=== [V18] 신호창 변형별 위상 순위 (phase0 우위가 창-불변인가) ===\n")
for(w in c("S6","S12","S24")){ SS<-get(w)
  v<-sapply(0:2,function(p) MET(engine(dec_freq(3,p),S=SS,bps=15))$pt)
  v0<-sapply(0:2,function(p) MET(engine(dec_freq(3,p),S=SS,bps=0))$gmean*100)
  cat(sprintf("  %s: pt=[%s] | gross_act%%=[%s] | argmax=phase%d\n",w,
    paste(sprintf("%.3f",v),collapse=", "),paste(sprintf("%.3f",v0),collapse=", "),which.max(v)-1)) }
cat("  rank-가중: ")
v<-sapply(0:2,function(p) MET(engine(dec_freq(3,p),bps=15,mode="rank"))$pt)
cat(sprintf("pt=[%s] argmax=phase%d\n",paste(sprintf("%.3f",v),collapse=", "),which.max(v)-1))

cat("\n=== [V19] 무작위 스케줄 null 재현 + 재해석 (B=400, p=1/3) ===\n")
B<-400; nl<-numeric(B); nT<-numeric(B)
for(i in 1:B){ sc<-runif(NM)<1/3; sc[13]<-TRUE; d<-rep(FALSE,NM); d[13:NM]<-sc[13:NM]
  m<-MET(engine(d,bps=15)); nl[i]<-m$pt; nT[i]<-m$TO }
cat(sprintf("  null pt15: mean=%.3f sd=%.3f q05=%.3f q50=%.3f q95=%.3f | TO mean=%.2f\n",
  mean(nl),sd(nl),quantile(nl,.05),median(nl),quantile(nl,.95),mean(nT)))
cat(sprintf("  A5(3.2318) 백분위=%.3f | C1(2.7748) 백분위=%.3f | A5E(2.7937) 백분위=%.3f\n",
  mean(nl<3.23180),mean(nl<2.77483),mean(nl<2.79383)))
cat(sprintf("  A5 - null평균 = %+.3f (=%.2f sd) | A5 - C1 = %+.3f (=%.2f sd)\n",
  3.23180-mean(nl),(3.23180-mean(nl))/sd(nl),3.23180-2.77483,(3.23180-2.77483)/sd(nl)))
## 결정적 3개월 주기 + 무작위 위상 null (실제 A5의 대조군으로 더 적절)
cat("  [결정적 freq3 위상 3개만의 분포] pt = 3.232 / 2.193 / 2.881 ; max-mean = %.3f\n")
pv<-c(3.23180,2.19269,2.88119); cat(sprintf("    mean=%.3f sd=%.3f max-mean=%+.3f\n",mean(pv),sd(pv),max(pv)-mean(pv)))

cat("\n=== [V20] §2 신호 지속성 / §3 HHI-드리프트 / §4 tenure 재현 ===\n")
dec<-12:(NM-1)
ON<-t(sapply(dec,function(d) as.integer(is.finite(S12[d,])&S12[d,]>0)))
cat(sprintf("  결정월=%d 평균켜짐=%.2f/21\n",nrow(ON),mean(rowSums(ON))))
sp<-c(); for(j in 1:ncol(ON)){ r<-rle(ON[,j]); sp<-c(sp,r$lengths[r$values==1]) }
cat(sprintf("  on-spell n=%d mean=%.3f median=%.1f q25=%.1f q75=%.1f max=%d P(<=3)=%.4f\n",
  length(sp),mean(sp),median(sp),quantile(sp,.25),quantile(sp,.75),max(sp),mean(sp<=3)))
cat(sprintf("  length==1 건수=%d | length>=13 건수=%d\n",sum(sp==1),sum(sp>=13)))
spo<-c(); for(j in 1:ncol(ON)){ r<-rle(ON[,j]); spo<-c(spo,r$lengths[r$values==0]) }
cat(sprintf("  off-spell mean=%.3f median=%.1f\n",mean(spo),median(spo)))
jac<-sapply(2:nrow(ON),function(i){a<-ON[i-1,];b<-ON[i,];sum(a&b)/sum(a|b)})
cat(sprintf("  Jaccard(t,t-1) 평균=%.4f | 멤버십 변화 평균=%.3f개/월\n",mean(jac),mean(rowSums(abs(diff(ON))))))
TG<-t(sapply(dec,function(d){s<-S12[d,];pos<-which(is.finite(s)&s>0);w<-numeric(NAX)
  if(!length(pos))w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]);w}))
l1<-function(h) mean(rowSums(abs(TG[(1+h):nrow(TG),]-TG[1:(nrow(TG)-h),])))
cat(sprintf("  목표비중 L1: lag1=%.4f lag3=%.4f 비율=%.4f (iid 기준 sqrt3=%.3f)\n",l1(1),l1(3),l1(3)/l1(1),sqrt(3)))
DW<-TG[-1,]-TG[-nrow(TG),]; x<-as.vector(DW[-nrow(DW),]); y<-as.vector(DW[-1,])
cat(sprintf("  corr(dW_t,dW_t+1)=%+.4f | 되돌림률=%.4f\n",cor(x,y),mean(sign(y[abs(x)>1e-12])!=sign(x[abs(x)>1e-12]))))
DS<-S12[dec[-1],]-S12[dec[-length(dec)],]; xs<-as.vector(DS[-nrow(DS),]); ys<-as.vector(DS[-1,])
cat(sprintf("  corr(dSignal_t,dSignal_t+1)=%+.4f\n",cor(xs,ys)))
## HHI
hhi<-function(r){ k<-which(is.finite(r$pr)); W<-r$W[k,]; list(h=mean(rowSums(W^2)),eN=mean(1/rowSums(W^2))) }
cA<-hhi(engine(dec_freq(3,0),bps=15)); cC<-hhi(engine(dec_freq(1,0),bps=15))
cQ<-hhi(engine(dec_freq(3,0),bps=15,rebal="reset"))
cat(sprintf("  HHI: C1=%.4f(eN %.2f) | A5drift=%.4f(eN %.2f) | QRreset=%.4f(eN %.2f)\n",
  cC$h,cC$eN,cA$h,cA$eN,cQ$h,cQ$eN))
mQ<-MET(engine(dec_freq(3,0),bps=15,rebal="reset"))
cat(sprintf("  QR(분기결정+매월리셋) pt=%.4f calmar=%.4f TO=%.3f | A5drift pt=%.4f TO=%.3f\n",
  mQ$pt,mQ$calmar,mQ$TO,MET(engine(dec_freq(3,0),bps=15))$pt,MET(engine(dec_freq(3,0),bps=15))$TO))
## 분기내 위치별 HHI
W<-engine(dec_freq(3,0),bps=15)$W; kq<-which(is.finite(engine(dec_freq(3,0),bps=15)$pr))
qq<-rep(1:3,length.out=length(kq))
for(q in 1:3) cat(sprintf("    q%d HHI=%.4f\n",q,mean(rowSums(W[kq[qq==q],]^2))))
