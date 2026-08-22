## run_dfa_risknorm_r22.R — R22: 역변동성 정규화 가중 (prereg dfa_v18_20260822)
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",fac)]
mon<-mon[ym<="2026-07"]; NM<-nrow(mon); NF<-length(fac); NAx<-1+NF
ACT<-sapply(fac,function(k)mon[[k]]-mon$Market)
S<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM) S[m,fi]<-prod(1+mon[[fac[fi]]][(m-11):m])/prod(1+mon$Market[(m-11):m])-1
RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
## 인과 trailing 36M active sd (결정시점 d 까지만) + 상관 가중(D3 판본, 진단셀용)
SD<-matrix(NA_real_,NM,NF); CW<-matrix(1,NM,NF)
for(m in 36:NM){ w<-(m-35):m; A<-ACT[w,,drop=FALSE]
  SD[m,]<-apply(A,2,function(x)sd(x[is.finite(x)]))
  ok<-which(apply(A,2,function(x)sum(is.finite(x))>=24))
  if(length(ok)>=3){ C<-suppressWarnings(cor(A[,ok,drop=FALSE],use="pairwise.complete.obs")); diag(C)<-NA
    mc<-colMeans(abs(C),na.rm=TRUE); CW[m,ok]<-1/(1+ifelse(is.finite(mc),mc,0)) } }
run<-function(arm,K=5,bps=15,dec_lag=1,freq=3,ncoh=3,start0=37){
  pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM)
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-dec_lag; if(d<1) next
      if(is.null(wcur)||((m-st)%%freq==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0)
        if(!is.na(K)&&length(pos)>K) pos<-pos[order(s[pos],decreasing=TRUE)][1:K]
        w<-rep(0,NAx)
        if(length(pos)==0) w[1]<-1 else { v<-s[pos]
          if(arm %in% c("G1","G2")){ sg<-SD[d,pos]; sg[!is.finite(sg)|sg<=0]<-median(sg[is.finite(sg)&sg>0]); v<-v/sg }
          if(arm=="G2") v<-v*CW[d,pos]
          w[1+pos]<-v/sum(v) }
        wcur<-w }
      ri<-RET[m,]; dlt<-sum(abs(wcur-wprev)); to_c[cc+1,m]<-dlt
      pr_c[cc+1,m]<-sum(wcur*ri)-(bps/1e4)*dlt
      wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  for(m in (start0+ncoh-1):NM) if(all(is.finite(pr_c[,m]))){ pr[m]<-mean(pr_c[,m]); tov[m]<-mean(to_c[,m]) }
  list(pr=pr,tov=tov) }
E<-list(full=rep(TRUE,NM), clean=mon$ym>="2015-07")
rep1<-function(r,lab,win){ s<-E[[win]]&is.finite(r$pr); p<-r$pr[s]; a<-p-mon$Market[s]
  nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); cagr<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-16s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | calmar=%.3f MDD=%.3f TO=%.2f\n",
    lab,win,length(p),nwt(a),IRf(a),cagr/abs(mdd),mdd,mean(r$tov[s],na.rm=TRUE)*12)) }
cat("=== R22 역변동성 정규화 (prereg dfa_v18) ===\n[헤드라인: G1, 15bps, dec_lag=1. ★start0=37 (36M sigma warm-up) — G0 도 동일 창]\n")
A<-list(); for(a in c("G0","G1","G2")){ A[[a]]<-run(a); for(w in c("full","clean")) rep1(A[[a]],
  c(G0="G0_control",G1="G1_risknorm",G2="G2_diag_corr+risk")[a],w) }
cat("\n[대응표본]\n")
for(p in list(c("G1","G0"),c("G2","G0"))) for(w in c("full","clean")){
  s<-E[[w]]&is.finite(A[[p[1]]]$pr)&is.finite(A[[p[2]]]$pr); d<-(A[[p[1]]]$pr-A[[p[2]]]$pr)[s]
  cat(sprintf("  %s - %s [%-5s] n=%3d mean=%+.4f%%/월 NW-t=%+.3f\n",p[1],p[2],w,sum(s),100*mean(d),nwt(d))) }
cat("\n[전 셀 전수 — full 창 IR]\n")
cat(sprintf("  %-4s %-6s %s\n","arm","cost","lag0     lag1     lag2     lag3"))
for(a in c("G0","G1","G2")) for(bp in c(5,15,25)){
  v<-sapply(0:3,function(dl){r<-run(a,bps=bp,dec_lag=dl); IRf((r$pr-mon$Market)[is.finite(r$pr)])})
  cat(sprintf("  %-4s %-6s %s\n",a,paste0(bp,"bps"),paste(sprintf("%+8.3f",v),collapse=" "))) }
saveRDS(list(A=A,mon=mon),".cache/_dfa_r22.rds")
cat("\nR22_DONE\n")
