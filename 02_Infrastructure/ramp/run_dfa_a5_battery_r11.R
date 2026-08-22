## run_dfa_a5_battery_r11.R — R11: A5(분기 리밸 × 연속가중 × broad-21) 게이트 배터리
## 게이트: ①구조 PIT ②shift 사다리(동월/정본/lag1) ③placebo 30-seed ④시대·서브윈도 분해 ⑤회전율 손익분기
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
set.seed(20260822)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m; S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
run<-function(bps=15,dec_lag=1,freq=3,perm=NULL,Suse=S){
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); wprev<-rep(1/NAx,NAx); wcur<-NULL
  Sx<-if(is.null(perm)) Suse else Suse[perm,,drop=FALSE]
  st<-13+max(dec_lag-1,0)
  for(m in st:NM){ d<-m-dec_lag; if(d<1) next
    if(is.null(wcur) || ((m-st)%%freq==0)){
      s<-Sx[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos])
      wcur<-w }
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt
    pr[m]<-sum(wcur*ri)-(bps/1e4)*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  list(pr=pr,tov=tov) }
M<-function(r){ k<-is.finite(r$pr); p<-r$pr[k]; mk<-mon$Market[k]; act<-p-mk
  nav<-cumprod(1+p); n<-length(p)
  list(pt=nwt(act),IR=IRf(act),SR=IRf(p),MDD=min(nav/cummax(nav)-1),
       CAGR=prod(1+p)^(12/n)-1,TO=mean(r$tov[k],na.rm=TRUE)*12,n=n,act=act,k=k) }
cat("== R11 A5 배터리 (분기리밸 × 연속가중 × broad-21) ==\n")
cat("\n[게이트②③ shift 사다리 — 15bps]\n")
for(dl in c(0,1,2)){ m<-M(run(15,dl)); cat(sprintf("  dec_lag=%d(%s): pt=%.3f IR=%.3f SR=%.3f\n",dl,
  c("동월(고의)","정본 m-1","lag1 m-2")[dl+1],m$pt,m$IR,m$SR)) }
cat("\n[게이트④ placebo 30-seed 월블록 셔플 — 15bps]\n")
base<-M(run(15,1)); ps<-replicate(30,{ M(run(15,1,3,perm=sample(NM)))$IR })
cat(sprintf("  real IR=%.3f | placebo mean=%.3f sd=%.3f | p(placebo>=real)=%.3f\n",
  base$IR,mean(ps,na.rm=TRUE),sd(ps,na.rm=TRUE),mean(ps>=base$IR,na.rm=TRUE)))
cat("\n[시대·서브윈도 분해 — 15bps]\n")
yy<-format(mon$medate[base$k],"%Y")
for(seg in list(c("2007","2011"),c("2012","2016"),c("2017","2021"),c("2022","2026"))){
  s<-yy>=seg[1]&yy<=seg[2]; if(sum(s)>=12) cat(sprintf("  %s-%s: n=%3d pt=%+.3f IR=%+.3f\n",seg[1],seg[2],sum(s),nwt(base$act[s]),IRf(base$act[s]))) }
cat("\n[손익분기 회전율 — §8-1]\n")
gross<-mean(base$act)*12+0.0015*base$TO
cat(sprintf("  gross_active=%.4f | TO=%.2f | drag15=%.4f | net15=%.4f | breakeven_TO=%.2f | headroom=%.2f\n",
  gross,base$TO,0.0015*base$TO,gross-0.0015*base$TO,gross/0.0015,gross/0.0015-base$TO))
cat("\n[비용 민감도]\n")
for(b in c(5,15,25,40)){ m<-M(run(b,1)); cat(sprintf("  %2dbps: pt=%.3f IR=%.3f SR=%.3f\n",b,m$pt,m$IR,m$SR)) }
cat("\n[분기 위상 민감도 — 시작월 오프셋 0/1/2 (사전등록 외 진단: 위상 의존성 검사)]\n")
for(off in 0:2){ pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); wprev<-rep(1/NAx,NAx); wcur<-NULL; st<-13+off
  for(m in st:NM){ d<-m-1
    if(is.null(wcur)||((m-st)%%3==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; pr[m]<-sum(wcur*ri)-0.0015*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  mm<-M(list(pr=pr,tov=tov)); cat(sprintf("  offset=%d: pt=%.3f IR=%.3f (n=%d)\n",off,mm$pt,mm$IR,mm$n)) }
cat("R11_DONE\n")
