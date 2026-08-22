suppressPackageStartupMessages({library(data.table); library(arrow)})
suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)]; mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
E<-readRDS("stage_artifacts/probe_a5_20260822/adv_env.rds")
NM<-E$NM; NAX<-E$NAX; RET<-E$RET; MKT<-E$MKT; S12<-E$S12; S6<-E$S6; S24<-E$S24; YM<-E$YM; MED<-E$MED
tgt_w<-function(s,mode="cont"){ w<-numeric(NAX); pos<-which(is.finite(s)&s>0)
  if(!length(pos)){ w[1]<-1 } else if(mode=="cont"){ w[1+pos]<-s[pos]/sum(s[pos])
  } else { rk<-rank(s[pos]); w[1+pos]<-rk/sum(rk) }; w }
engine<-function(dec, S=S12, bps=15, mode="cont", start_m=13L, rebal="drift", lambda=1){
  pr<-gr<-tov<-rep(NA_real_,NM); wprev<-rep(1/NAX,NAX); wcur<-NULL; wtar<-NULL
  WK<-matrix(NA_real_,NM,NAX)
  for(m in start_m:NM){
    if(is.null(wcur) || dec[m]){ wtar<-tgt_w(S[m-1L,],mode)
      wcur<- if(lambda>=1) wtar else wprev+lambda*(wtar-wprev)
    } else if(rebal=="reset"){ wcur<-wtar } else wcur<-wprev
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; WK[m,]<-wcur
    gr[m]<-sum(wcur*RET[m,]); pr[m]<-gr[m]-(bps/1e4)*dlt
    wd<-wcur*(1+RET[m,]); wprev<-wd/sum(wd) }
  list(pr=pr,gross=gr,tov=tov,W=WK) }
dec_freq<-function(freq,phase=0,start_m=13L){ d<-rep(FALSE,NM)
  idx<-start_m:NM; d[idx[((idx-start_m-phase)%%freq)==0]]<-TRUE; d[start_m]<-TRUE; d }
MET<-function(r){ k<-which(is.finite(r$pr)); p<-r$pr[k]; g<-r$gross[k]; mk<-MKT[k]
  na<-p-mk; ga<-g-mk; nav<-cumprod(1+p); n<-length(p)
  cg<-prod(1+p)^(12/n)-1; mdd<-min(nav/cummax(nav)-1)
  list(k=k,net=p,gross=g,mkt=mk,act=na,gact=ga,n=n,
    pt=nwt(na),IR=IRf(na),gpt=nwt(ga),gIR=IRf(ga),
    amean=mean(na)*12,asd=sd(na)*sqrt(12),gmean=mean(ga)*12,gsd=sd(ga)*sqrt(12),
    SR=IRf(p),CAGR=cg,MDD=mdd,calmar=cg/abs(mdd),TO=mean(r$tov[k])*12) }
