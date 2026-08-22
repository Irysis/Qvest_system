suppressPackageStartupMessages({library(data.table);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon; fac<-Z$fac; S<-Z$S12
SER<-readRDS(".cache/_dfa_c1_followup_r10.rds"); NM<-nrow(mon)
nwt<-function(x){x<-x[is.finite(x)];m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
cat("== 1. prereg 5-arm active correlation (DSR independence assumption) ==\n")
arms<-c("C1_base_15","A2_rank_15","A3_win6_15","A4_win24_15","A5_quart_15")
A<-sapply(arms,function(a){p<-SER[[a]]$pr; p-mon$Market})
A<-A[complete.cases(A),]; C<-cor(A)
cat("   n common months:",nrow(A),"\n"); print(round(C,3))
ev<-eigen(C)$values
cat(sprintf("   off-diag corr range %.3f ~ %.3f | Kaiser(#eig>1)=%d | entropy-eff=%.2f (nominal 5)\n",
  min(C[upper.tri(C)]),max(C[upper.tri(C)]),sum(ev>1),exp(-sum((ev/sum(ev))*log(ev/sum(ev))))))
cat("\n== 2. yearly beta / alpha decomposition ==\n")
k<-is.finite(Z$a5$pr); P<-Z$a5$pr[k]; MK<-mon$Market[k]; D<-mon$medate[k]; yr<-format(D,"%Y")
YB<-rbindlist(lapply(sort(unique(yr)),function(y){s<-yr==y
  if(sum(s)<6)return(data.table(yr=y,n=sum(s),beta=NA_real_,act_ann=prod(1+P[s])^(12/sum(s))-prod(1+MK[s])^(12/sum(s)),
    mkt_ann=prod(1+MK[s])^(12/sum(s))-1,beta_excess=NA_real_))
  b<-coef(lm(P[s]~MK[s]))[2]
  data.table(yr=y,n=sum(s),beta=b,act_ann=prod(1+P[s])^(12/sum(s))-prod(1+MK[s])^(12/sum(s)),
    mkt_ann=prod(1+MK[s])^(12/sum(s))-1, beta_excess=(b-1)*(prod(1+MK[s])^(12/sum(s))-1))}))
print(YB[yr%in%c("2020","2023","2024","2025","2026")],digits=3)
cat(sprintf("   2026: beta_excess/act = %.3f\n",YB[yr=="2026",beta_excess/act_ann]))
cat("\n== 3. 'all-market fallback' branch firing count ==\n")
cnt<-0; for(m in 13:NM){s<-S[m-1,]; if(sum(is.finite(s)&s>0)==0)cnt<-cnt+1}
np<-sapply(13:NM,function(m)sum(is.finite(S[m-1,])&S[m-1,]>0))
cat("   months with zero positive-active factors:",cnt,"/",NM-12,"  n_positive: min",min(np),"median",median(np),"max",max(np),"\n")
cat("   -> A5 is effectively always ~100% invested in factor sleeves (defensive branch is dead code)\n")
cat("\n== 4. concentration: HHI of factor weights ==\n")
W<-matrix(NA_real_,NM,1+length(fac)); wprev<-rep(1/(1+length(fac)),1+length(fac)); wcur<-NULL
RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
for(m in 13:NM){d<-m-1
 if(is.null(wcur)||((m-13)%%3==0)){s<-S[d,];pos<-which(is.finite(s)&s>0);w<-rep(0,1+length(fac))
  if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]);wcur<-w}
 W[m,]<-wcur; ri<-RET[m,]; wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev}
h<-rowSums(W[13:NM,]^2); cat(sprintf("   HHI: median=%.3f (eff N=%.1f) p95=%.3f (eff N=%.1f) max=%.3f\n",
  median(h),1/median(h),quantile(h,.95),1/quantile(h,.95),max(h)))
cat("\n== 5. does 2026 also carry PORT_t? (peer says no) ==\n")
for(lab in list(c("full",""),c("ex2026","2026"),c("ex2025_26","2025|2026"))){
  ix<-if(lab[2]=="")seq_along(P) else grep(lab[2],yr,invert=TRUE)
  cat(sprintf("   %-10s n=%3d pt=%.3f mean_act_ann=%.4f\n",lab[1],length(ix),nwt(P[ix]-MK[ix]),mean(P[ix]-MK[ix])*12)) }
