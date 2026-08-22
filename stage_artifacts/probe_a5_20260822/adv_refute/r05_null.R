suppressPackageStartupMessages({library(data.table);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
J<-readRDS("stage_artifacts/probe_a5_20260822/j_null_matrix.rds")
NULLM<-J$NULLM; GRID<-as.data.table(J$GRID); realf<-J$realf; NG<-nrow(GRID)
iA5<-which(GRID$win==12&GRID$mode=="cont"&GRID$freq==3&GRID$phase==0); obs<-realf[iA5]
cat("NG=",NG," B=",nrow(NULLM)," iA5=",iA5," obs=",round(obs,4),"\n")
cat("real family: max=",round(max(realf),4)," which=",which.max(realf)," rank of A5=",sum(realf>=obs),
    " pctile=",round(mean(realf<obs),4),"\n")
print(GRID[which.max(realf)])
cat("\n-- null at A5 coord: mean=",round(mean(NULLM[,iA5]),4)," sd=",round(sd(NULLM[,iA5]),4),
    " q95=",round(quantile(NULLM[,iA5],.95),4)," p(single)=",round(mean(NULLM[,iA5]>=obs),4),"\n")
cat("-- null mean across all 84 arms: ",round(mean(colMeans(NULLM)),4),
    " (min ",round(min(colMeans(NULLM)),3)," max ",round(max(colMeans(NULLM)),3),")\n")
mx<-apply(NULLM,1,max,na.rm=TRUE)
cat("-- FWER over FULL 84 family: p=",round(mean(mx>=obs),4)," crit_t.05=",round(quantile(mx,.95),4),"\n")
set.seed(77)
for(N in c(1,3,5,7,10,20,56,84)){ ps<-numeric(400)
  for(s in 1:400){ idx<-if(N==1)iA5 else c(iA5,sample(setdiff(1:NG,iA5),N-1))
    ps[s]<-mean(apply(NULLM[,idx,drop=FALSE],1,max,na.rm=TRUE)>=obs) }
  cat(sprintf("   N=%2d FWER_p=%.4f\n",N,mean(ps))) }

## ---- alternative null: H0 = zero mean active (the null the PORT_t gate actually tests) ----
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon
k<-is.finite(Z$a5$pr); A<-Z$a5$pr[k]-mon$Market[k]; n<-length(A)
PTf<-function(x){m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
set.seed(11); B<-4000; bl<-12
cat("\n== alt null A: stationary block bootstrap of A under H0 mean=0 (block=12) ==\n")
Ac<-A-mean(A); st<-numeric(B)
for(b in 1:B){ idx<-unlist(lapply(1:ceiling(n/bl),function(i) ((sample(n,1)+0:(bl-1)-1)%%n)+1))[1:n]
  st[b]<-PTf(Ac[idx]) }
cat("   null pt: mean=",round(mean(st),3)," sd=",round(sd(st),3)," q95=",round(quantile(st,.95),3),
    " -> single-arm p=",round(mean(st>=PTf(A)),4),"\n")
cat("   Bonferroni-equivalent crit for N=5 / 56 / 84: ",
    paste(round(sapply(c(5,56,84),function(N)quantile(st,(1-0.05/N))),3),collapse=" / "),"\n")
cat("   (max-stat with independence approx) FWER p N=5:",round(1-(1-mean(st>=PTf(A)))^5,4),
    " N=56:",round(1-(1-mean(st>=PTf(A)))^56,4),"\n")
