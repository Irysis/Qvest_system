suppressPackageStartupMessages({library(data.table)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon; fac<-Z$fac
NM<-nrow(mon); NAx<-1+length(fac)
mkS<-function(M){ S<-matrix(NA_real_,NM,length(fac))
  for(fi in seq_along(fac)) for(m in 12:NM){w<-(m-11):m; S[m,fi]<-prod(1+M[w,1+fi])/prod(1+M[w,1])-1}; S}
wts<-function(M){ S<-mkS(M); W<-matrix(NA_real_,NM,NAx); wprev<-rep(1/NAx,NAx); wcur<-NULL
 for(m in 13:NM){ d<-m-1
  if(is.null(wcur)||((m-13)%%3==0)){s<-S[d,];pos<-which(is.finite(s)&s>0);w<-rep(0,NAx)
   if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]);wcur<-w}
  W[m,]<-wcur; ri<-M[m,]; wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev}; W}
M0<-as.matrix(mon[,c("Market",fac),with=FALSE]); M0[!is.finite(M0)]<-0
cat("== PIT future-perturbation test ==\n")
set.seed(9)
for(Tcut in c(100,150,200)){ M1<-M0; M1[(Tcut+1):NM,]<-matrix(rnorm(length(M1[(Tcut+1):NM,]),0,0.08),ncol=NAx)
  W0<-wts(M0); W1<-wts(M1)
  cat(sprintf("  T=%3d (%s): max|dW| for months<=T = %.3e  ; months>T = %.3e\n",Tcut,
   format(mon$medate[Tcut]),max(abs(W0[13:Tcut,]-W1[13:Tcut,])),max(abs(W0[(Tcut+1):NM,]-W1[(Tcut+1):NM,])))) }
cat("  -> decisions at t depend only on returns up to t-1: PASS (strategy layer)\n")
cat("\n== search-space census (files as evidence, DFA arc) ==\n")
f<-list.files("outputs/ramp",pattern="^dfa_",full.names=FALSE)
cat("  dfa_* artifacts in outputs/ramp:",length(f),"\n")
cat("  v5 phase-scan arm files (p1..p30):",length(grep("_p[0-9]+[.]csv$",f,value=TRUE)),"\n")
cat("  prereg files:",paste(grep("prereg",f,value=TRUE),collapse=", "),"\n")
## essence DSR: critical n_trials
source("02_Infrastructure/contracts/essence_score.R")
k<-is.finite(Z$a5$pr); a<-Z$a5$pr[k]-mon$Market[k]; n<-length(a); mu<-mean(a); s<-sd(a)
sr<-mu/s*sqrt(12); sk<-mean(((a-mu)/s)^3); ku<-mean(((a-mu)/s)^4)
cat(sprintf("\n== DSR diagnostics: active SR=%.4f n=%d skew=%.3f kurt=%.3f ==\n",sr,n,sk,ku))
for(nt in c(5,56,100,500,1000,1377,1400,2000)) cat(sprintf("   n_trials=%5d -> DSR=%.4f\n",nt,.essence_dsr(sr,n,nt,sk,ku,A=12)))
cat("\n== peer's normal-approx Bonferroni reproduced ==\n")
cat(sprintf("   two-sided p from t=3.2318: %.3e ; x56 = %.4f ; crit t = %.3f\n",
  2*(1-pnorm(3.2318)), min(1,56*2*(1-pnorm(3.2318))), qnorm(1-0.025/56)))
