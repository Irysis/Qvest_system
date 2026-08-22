suppressPackageStartupMessages({library(data.table);library(xts);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R"); source("02_Infrastructure/contracts/essence_score.R")
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
kk<-is.finite(Z$a5$pr); P<-Z$a5$pr[kk]; MK<-mon$Market[kk]; D<-mon$medate[kk]; A<-P-MK; n<-length(A)
cat("eval window:",format(min(D)),"~",format(max(D))," n=",n,"\n")

## --- oos retention as contract defines it, own implementation (verified vs contract above) ---
ret_at<-function(a,fr){ nn<-length(a); k<-floor(nn*fr); if(k<6||(nn-k)<6)return(NA_real_)
  ia<-a[1:k]; oa<-a[(k+1):nn]; ii<-mean(ia)/sd(ia)*sqrt(12); oo<-mean(oa)/sd(oa)*sqrt(12)
  if(is.finite(ii)&&ii>0.05&&is.finite(oo)) oo/ii else NA_real_ }
cat("\n[A] contract splits {55/65/75}:",paste(round(sapply(c(.55,.65,.75),ret_at,a=A),4),collapse=" / "),
    " median=",round(median(sapply(c(.55,.65,.75),ret_at,a=A)),4),"\n")
g<-seq(0.40,0.90,0.01); rg<-sapply(g,ret_at,a=A)
cat("[B] full grid 0.40-0.90 (51 pts): frac>=0.7 =",round(mean(rg>=0.7,na.rm=TRUE),4),
    " median=",round(median(rg,na.rm=TRUE),4)," range=",round(min(rg,na.rm=TRUE),3),"-",round(max(rg,na.rm=TRUE),3),"\n")
alt<-list(c(.5,.6,.7,.8),c(.6,.7,.8),c(.5,.6,.7),c(.45,.6,.75),c(.55,.7,.85),c(.6,.65,.7),c(.5,.65,.8))
for(s in alt) cat(sprintf("   anchors {%s} median=%.4f %s\n",paste(round(s*100),collapse="/"),
   median(sapply(s,ret_at,a=A),na.rm=TRUE), ifelse(median(sapply(s,ret_at,a=A),na.rm=TRUE)>=0.7,"PASS","FAIL")))
cat("[C] k local sensitivity (k=floor(n*.65)=",floor(n*.65),"):\n   ")
for(k in (floor(n*.65)-3):(floor(n*.65)+3)){ ia<-A[1:k];oa<-A[(k+1):n]
  cat(sprintf("k=%d:%.4f ",k,(mean(oa)/sd(oa))/(mean(ia)/sd(ia)))) }; cat("\n")

## --- 2026 dependence ---
yr<-format(D,"%Y")
cat("\n[D] yearly active contribution\n")
YT<-data.table(yr=yr,a=A,p=P,mk=MK)[,.(nmo=.N,sum_act=sum(a),ann_act=prod(1+p)^(12/.N)-prod(1+mk)^(12/.N),
     mkt_ann=prod(1+mk)^(12/.N)-1),by=yr]
print(YT[order(-abs(sum_act))][1:8],digits=3)
cat("  total sum(active) =",round(sum(A),4)," 2026 share =",round(sum(A[yr=="2026"])/sum(A),4),"\n")

drop<-function(idx,lab){ a<-A[-idx]; p<-P[-idx]; m<-MK[-idx]
  cat(sprintf("  %-26s n=%3d pt=%6.3f oos=%6.3f (%s) IR=%.3f\n",lab,length(a),nwt(a),
    median(sapply(c(.55,.65,.75),ret_at,a=a),na.rm=TRUE),
    paste(round(sapply(c(.55,.65,.75),ret_at,a=a),3),collapse="/"),IRf(a))) }
cat("\n[E] deletions (pt uses NW on remaining series)\n")
drop(integer(0),"none (base)")
drop(which(yr=="2026"),"drop 2026 (8mo)")
drop(which(yr%in%c("2025","2026")),"drop 2025-26")
drop(which(D==D[yr=="2026"][5]),"drop 2026-05 only")
drop(tail(seq_len(n),4),"drop last 4 mo")
drop(tail(seq_len(n),1),"drop last 1 mo")
drop(which(A==max(A)),"drop best month")
drop(which(A==min(A)),"drop worst month")
cat("\n[F] leading truncations j=1..12 (phase fixed, drop first j months)\n")
for(j in c(1,2,3,4,6,8,12)){ a<-A[-(1:j)]
  cat(sprintf("  j=%2d n=%3d pt=%6.3f oos=%6.3f\n",j,length(a),nwt(a),median(sapply(c(.55,.65,.75),ret_at,a=a),na.rm=TRUE))) }
cat("\n[G] subperiods\n")
for(cut in c("2013","2015","2017","2019","2021")){ s<-yr>=cut
  cat(sprintf("  %s- n=%3d pt=%6.3f IR=%.3f  | pre: n=%3d pt=%6.3f IR=%.3f\n",cut,sum(s),nwt(A[s]),IRf(A[s]),
      sum(!s),nwt(A[!s]),IRf(A[!s]))) }
cat("\n[H] beta / CAPM alpha\n")
for(lab in c("full","ex2026")){ ix<-if(lab=="full")seq_len(n) else which(yr!="2026")
  m<-lm(P[ix]~MK[ix]); ct<-coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))
  cat(sprintf("  %-7s beta=%.4f alpha_ann=%.4f alpha_t=%.3f  rawPT=%.3f\n",lab,coef(m)[2],coef(m)[1]*12,ct[1,3],nwt(A[ix]))) }
cat("\nR04_DONE\n")
