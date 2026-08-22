## run_dfa_strength_r17.R — R17 D3(상관반영 가중) + 이중 벤치 평가 (prereg dfa_v15)
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IDXF<-Sys.getenv("SMV_IDX_R17","outputs/ramp/dfa_index_returns_broad_202608.parquet")
TAG<-Sys.getenv("SMV_TAG_R17","q67")
R<-as.data.table(read_parquet(IDXF)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NF<-length(fac); NAx<-1+NF
ACT<-matrix(NA_real_,NM,NF); for(fi in 1:NF) ACT[,fi]<-mon[[fac[fi]]]-mon$Market
S<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM){ w<-(m-11):m; S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
## D3: 상관 반영 가중 계수 (결정시점까지 trailing 36M active 상관, 인과)
CW<-matrix(1,NM,NF)
for(m in 36:NM){ w<-(m-35):m; A<-ACT[w,,drop=FALSE]
  ok<-which(apply(A,2,function(x)sum(is.finite(x))>=24))
  if(length(ok)<3) next
  C<-suppressWarnings(cor(A[,ok,drop=FALSE],use="pairwise.complete.obs"))
  diag(C)<-NA; mc<-colMeans(abs(C),na.rm=TRUE)
  CW[m,ok]<-1/(1+ifelse(is.finite(mc),mc,0)) }
run_ens<-function(Suse,bps=15,mode="cont",cw=NULL,dec_lag=1,freq=3,ncoh=3,start0=13){
  pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM)
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-dec_lag; if(d<1) next
      if(is.null(wcur)||((m-st)%%freq==0)){
        s<-Suse[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
        if(length(pos)==0) w[1]<-1 else {
          v<-s[pos]; if(!is.null(cw)) v<-v*cw[d,pos]
          w[1+pos]<-v/sum(v) }
        wcur<-w }
      ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
      dlt<-sum(abs(wcur-wprev)); to_c[cc+1,m]<-dlt
      pr_c[cc+1,m]<-sum(wcur*ri)-(bps/1e4)*dlt
      wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  for(m in (start0+ncoh-1):NM) if(all(is.finite(pr_c[,m]))){ pr[m]<-mean(pr_c[,m]); tov[m]<-mean(to_c[,m]) }
  list(pr=pr,tov=tov) }
## KOSPI200 벤치 (자본 게이트 정본)
d<-"05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
bmK<-fread(file.path(d,"05_benchmark_returns.csv"))
K<-data.table(ym=format(as.Date(bmK$date),"%Y-%m"), k200=bmK$benchmark_ret)
rep_arm<-function(r,lab,win="full"){
  k<-which(is.finite(r$pr)); ymv<-mon$ym[k]
  if(win=="ex2026") { sel<-substr(ymv,1,4)<"2026"; k<-k[sel]; ymv<-ymv[sel] }
  if(win=="clean")  { sel<-ymv>="2015-07"; k<-k[sel]; ymv<-ymv[sel] }   # universe exit recording starts 2015-12
  p<-r$pr[k]; par<-mon$Market[k]; kk<-K$k200[match(ymv,K$ym)]
  nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); n<-length(p)
  cagr<-prod(1+p)^(12/n)-1
  cat(sprintf("%-16s [%-6s] n=%3d | parent: pt=%+.3f IR=%+.3f | K200: IR=%+.3f | calmar=%.3f MDD=%.3f TO=%.2f\n",
    lab,win,n,nwt(p-par),IRf(p-par), if(all(is.na(kk))) NA else IRf(p-kk), cagr/abs(mdd),mdd,mean(r$tov[k],na.rm=TRUE)*12))
  invisible(list(pr=p,par=par,k200=kk,d=mon$medate[k])) }
cat("=== R17 [",TAG,"] 이중 벤치 평가 ===\n",sep="")
r0<-run_ens(S); r3<-run_ens(S,cw=CW)
for(w in c("full","clean")){ rep_arm(r0,"D0_base",w); rep_arm(r3,"D3_corrweight",w) }
k<-is.finite(r0$pr)&is.finite(r3$pr)
cat(sprintf("\n[paired] D3 - D0 : NW-t = %+.3f\n", nwt((r3$pr-r0$pr)[k])))
saveRDS(list(r0=r0,r3=r3,mon=mon,K=K,tag=TAG),sprintf(".cache/_dfa_r17_%s.rds",TAG))
cat("R17_DONE\n")
