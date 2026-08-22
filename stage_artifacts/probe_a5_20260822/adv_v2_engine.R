## adv_v2_engine.R — 독립 재구현 엔진 (적대검증용). 읽기전용, 산출은 adv_* 접두만.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
OUTD<-"stage_artifacts/probe_a5_20260822"
IRf<-function(x){x<-x[is.finite(x)]; mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}

## ---- 데이터 (독립 재구성) ----
RD<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
RD[,Date:=as.Date(Date)]; setorder(RD,Date); RD<-RD[is.finite(Market)]
FAC<-setdiff(names(RD),c("Date","ym","as_of_date","source_version","Market"))
RD[,ym:=format(Date,"%Y-%m")]
MON<-RD[,c(lapply(.SD,function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
        by=ym, .SDcols=c("Market",FAC)]
setorder(MON,medate)
NM<-nrow(MON); NAX<-1L+length(FAC)
RET<-as.matrix(MON[,c("Market",FAC),with=FALSE]); RET[!is.finite(RET)]<-0   # NM x 22
MKT<-RET[,1]
YM<-MON$ym; MED<-MON$medate

sig_mat<-function(win=12L){
  S<-matrix(NA_real_,NM,length(FAC))
  cm<-apply(1+RET,2,cumprod)                       # 누적곱
  for(m in win:NM){ lo<-m-win+1L
    base<-if(lo==1L) rep(1,NAX) else cm[lo-1L,]
    gr<-cm[m,]/base                                 # 창 총수익 (1+R)
    S[m,]<-gr[-1]/gr[1]-1 }
  colnames(S)<-FAC; S }
S12<-sig_mat(12); S6<-sig_mat(6); S24<-sig_mat(24)

## 목표비중(22): 양수 active momentum 팩터에 비례, 없으면 Market 100%
tgt_w<-function(s,mode="cont"){ w<-numeric(NAX); pos<-which(is.finite(s)&s>0)
  if(!length(pos)){ w[1]<-1 } else if(mode=="cont"){ w[1+pos]<-s[pos]/sum(s[pos])
  } else { rk<-rank(s[pos]); w[1+pos]<-rk/sum(rk) }; w }

## 엔진: dec = 결정월 논리벡터(길이 NM). drift 또는 reset(매월 목표복귀)
engine<-function(dec, S=S12, bps=15, mode="cont", start_m=13L, rebal="drift", lambda=1){
  pr<-gr<-tov<-rep(NA_real_,NM); wprev<-rep(1/NAX,NAX); wcur<-NULL; wtar<-NULL
  for(m in start_m:NM){
    if(is.null(wcur) || dec[m]){ wtar<-tgt_w(S[m-1L,],mode)
      wcur<- if(lambda>=1) wtar else wprev+lambda*(wtar-wprev)
    } else if(rebal=="reset"){ wcur<-wtar } else wcur<-wprev
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt
    gr[m]<-sum(wcur*RET[m,]); pr[m]<-gr[m]-(bps/1e4)*dlt
    wd<-wcur*(1+RET[m,]); wprev<-wd/sum(wd) }
  list(pr=pr,gross=gr,tov=tov) }

dec_freq<-function(freq,phase=0,start_m=13L){ d<-rep(FALSE,NM)
  idx<-start_m:NM; d[idx[((idx-start_m-phase)%%freq)==0]]<-TRUE; d[start_m]<-TRUE; d }

MET<-function(r,start_m=13L){ k<-which(is.finite(r$pr)); p<-r$pr[k]; g<-r$gross[k]; mk<-MKT[k]
  na<-p-mk; ga<-g-mk; nav<-cumprod(1+p); n<-length(p)
  cg<-prod(1+p)^(12/n)-1; mdd<-min(nav/cummax(nav)-1)
  list(k=k,net=p,gross=g,mkt=mk,act=na,gact=ga,n=n,
    pt=nwt(na),IR=IRf(na),gpt=nwt(ga),gIR=IRf(ga),
    amean=mean(na)*12,asd=sd(na)*sqrt(12),gmean=mean(ga)*12,gsd=sd(ga)*sqrt(12),
    SR=IRf(p),CAGR=cg,MDD=mdd,calmar=cg/abs(mdd),TO=mean(r$tov[k])*12) }

cat("=== 데이터 확인 ===\n")
cat(sprintf("  NM=%d  적용창 = %s ~ %s  (n=%d)\n",NM,YM[13],YM[NM],NM-12))
cat("=== [V1] 엔진 패리티: R10 캐시 대조 ===\n")
r10<-readRDS(".cache/_dfa_c1_followup_r10.rds")
for(nm in c("C1_base_15","A5_quart_15","C1_base_5","A5_quart_5")){
  s<-r10[[nm]]; k<-is.finite(s$pr); a<-s$pr[k]-s$mon$Market[k]
  cat(sprintf("  [R10 %s] pt=%.5f n=%d TO=%.4f\n",nm,nwt(a),sum(k),mean(s$tov[k])*12)) }
for(cfg in list(c(1,15),c(3,15),c(1,5),c(3,5))){
  m<-MET(engine(dec_freq(cfg[1],0),bps=cfg[2]))
  cat(sprintf("  [ADV freq=%d bps=%d] pt=%.5f n=%d TO=%.4f\n",cfg[1],cfg[2],m$pt,m$n,m$TO)) }
## 시계열 비트 대조
sA<-r10[["A5_quart_15"]]; kA<-is.finite(sA$pr); mA<-engine(dec_freq(3,0),bps=15)
cat(sprintf("  시계열 max|diff| A5 = %.3e ; C1 = %.3e\n",
  max(abs(sA$pr[kA]-mA$pr[is.finite(mA$pr)])),
  {sC<-r10[["C1_base_15"]];kC<-is.finite(sC$pr);mC<-engine(dec_freq(1,0),bps=15)
   max(abs(sC$pr[kC]-mC$pr[is.finite(mC$pr)]))}))
saveRDS(list(NM=NM,NAX=NAX,RET=RET,MKT=MKT,S12=S12,S6=S6,S24=S24,YM=YM,MED=MED),
        file.path(OUTD,"adv_env.rds"))
