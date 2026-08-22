## run_dfa_breadth_r19.R — R19: breadth-scaled Market weight (prereg dfa_v16_20260822)
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
IDXF<-Sys.getenv("SMV_IDX_R19","outputs/ramp/dfa_index_returns_broad_202608.parquet")
R<-as.data.table(read_parquet(IDXF)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
R[,ym:=format(Date,"%Y-%m")]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",fac)]
mon<-mon[ym<="2026-07"]                      # 진행월 제외 (prereg pit_gates)
NM<-nrow(mon); NF<-length(fac); NAx<-1+NF
S<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM) S[m,fi]<-prod(1+mon[[fac[fi]]][(m-11):m])/prod(1+mon$Market[(m-11):m])-1
RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0

run_ens<-function(arm,bps=15,dec_lag=1,freq=3,ncoh=3,start0=13){
  pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM); mw_c<-matrix(NA_real_,ncoh,NM)
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-dec_lag; if(d<1) next
      if(is.null(wcur)||((m-st)%%freq==0)){
        s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
        if(length(pos)==0){ w[1]<-1
        } else if(arm=="E0"){ w[1+pos]<-s[pos]/sum(s[pos])
        } else {                                    # E1: breadth-scaled market
          br<-length(pos)/NF; w[1]<-1-br; w[1+pos]<-br*s[pos]/sum(s[pos]) }
        wcur<-w }
      mw_c[cc+1,m]<-wcur[1]
      ri<-RET[m,]; dlt<-sum(abs(wcur-wprev)); to_c[cc+1,m]<-dlt
      pr_c[cc+1,m]<-sum(wcur*ri)-(bps/1e4)*dlt
      wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); mwt<-rep(NA_real_,NM)
  for(m in (start0+ncoh-1):NM) if(all(is.finite(pr_c[,m]))){ pr[m]<-mean(pr_c[,m]); tov[m]<-mean(to_c[,m]); mwt[m]<-mean(mw_c[,m]) }
  list(pr=pr,tov=tov,mw=mwt) }

E<-list(full=rep(TRUE,NM), clean=mon$ym>="2015-07")
rep1<-function(r,lab,win){ s<-E[[win]]&is.finite(r$pr); p<-r$pr[s]; a<-p-mon$Market[s]
  nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); cagr<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-12s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | calmar=%.3f MDD=%.3f TO=%.2f | 평균Market비중=%.3f\n",
    lab,win,length(p),nwt(a),IRf(a),cagr/abs(mdd),mdd,mean(r$tov[s],na.rm=TRUE)*12,mean(r$mw[s],na.rm=TRUE)))
  invisible(a) }
cat("=== R19 breadth-scaled Market weight (prereg dfa_v16) ===\n")
cat("[헤드라인 사전지정 셀: E1, 15bps, dec_lag=1]\n")
A<-list(); for(arm in c("E0","E1")){ r<-run_ens(arm); A[[arm]]<-r
  for(w in c("full","clean")) rep1(r,ifelse(arm=="E0","E0_control","E1_breadth"),w) }
cat("\n[대응표본 E1 - E0]\n")
for(w in c("full","clean")){ s<-E[[w]]&is.finite(A$E0$pr)&is.finite(A$E1$pr)
  d<-(A$E1$pr-A$E0$pr)[s]; cat(sprintf("  %-5s n=%3d mean=%+.4f%%/월 NW-t=%+.3f\n",w,sum(s),100*mean(d),nwt(d))) }
cat("\n[전 셀 전수 보고: arm x cost x dec_lag — full 창 IR]\n")
cat(sprintf("  %-4s %-6s %s\n","arm","cost","dec_lag=0    1        2        3"))
for(arm in c("E0","E1")) for(bp in c(5,15,25)){
  v<-sapply(0:3,function(dl){r<-run_ens(arm,bps=bp,dec_lag=dl); IRf((r$pr-mon$Market)[is.finite(r$pr)])})
  cat(sprintf("  %-4s %-6s %s\n",arm,paste0(bp,"bps"),paste(sprintf("%+8.3f",v),collapse=" "))) }
saveRDS(list(A=A,mon=mon),".cache/_dfa_r19.rds")
cat("\nR19_DONE\n")
