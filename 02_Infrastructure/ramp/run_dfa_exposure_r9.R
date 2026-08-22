## run_dfa_exposure_r9.R — R9: 익스포저 트리거 재설계 (prereg dfa_v10, 가이드 8-1)
## 트리거 3안: E1 월내최대(이진) · E2 월말 연속백분위 · E3 월내평균 연속. crisis신호 = mkt_jm Bear_Prob(인과).
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
SER<-readRDS(".cache/_dfa_fm_dev_r7.rds")

## 일별 Bear_Prob → 월별 통계 (월말/월내최대/월내평균) + 인과 expanding q95·백분위
jm<-as.data.table(read_parquet(".cache/regime_jump_daily.parquet", col_select=c("Date","Bear_Prob")))
jm[,Date:=as.Date(Date)]; jm<-jm[is.finite(Bear_Prob)]; setorder(jm,Date); jm[,ym:=format(Date,"%Y-%m")]
mstat<-jm[,.(bp_end=Bear_Prob[.N], bp_max=max(Bear_Prob), bp_mean=mean(Bear_Prob), n=.N),by=ym]
setorder(mstat,ym)
## 인과 expanding: 각 월 d 까지의 전체 일별 bp 로 q95·백분위 산출 (누적)
cum_bp<-numeric(0); mstat[,`:=`(q95=NA_real_,rank_end=NA_real_,rank_mean=NA_real_,crisis_max=NA)]
for(i in seq_len(nrow(mstat))){ ym_i<-mstat$ym[i]
  cum_bp<-jm[ym<=ym_i,Bear_Prob]
  if(length(cum_bp)>=60*21){
    q<-quantile(cum_bp,0.95,na.rm=TRUE); mstat$q95[i]<-q
    mstat$crisis_max[i]<-mstat$bp_max[i]>q
    mstat$rank_end[i]<-mean(cum_bp<=mstat$bp_end[i])
    mstat$rank_mean[i]<-mean(cum_bp<=mstat$bp_mean[i]) } }

## 익스포저 벡터 생성 (결정월 d=m-1 → 적용 m). 워밍업 이전/결측 = exposure 1.0
mk_exp<-function(mon, kind){
  ymv<-format(mon$medate,"%Y-%m"); idx<-match(ymv,mstat$ym)
  dec<-switch(kind,
    E1=ifelse(is.finite(mstat$crisis_max[idx]) & mstat$crisis_max[idx], 0.70, 1.00),
    E2=1-0.30*ifelse(is.finite(mstat$rank_end[idx]), mstat$rank_end[idx], 0),
    E3=1-0.30*ifelse(is.finite(mstat$rank_mean[idx]), mstat$rank_mean[idx], 0))
  ex<-shift(dec,1); ex[!is.finite(ex)]<-1.00; ex }

mets<-function(mon,pr){ k<-is.finite(pr); p<-pr[k]; mk<-mon$Market[k]
  act<-p-mk; nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); n<-length(p)
  data.table(n_mo=n, pt_vsMkt=nwt(act), IR_vsMkt=IRf(act), SR=IRf(p),
    CAGR=prod(1+p)^(12/n)-1, MDD=mdd, calmar=(prod(1+p)^(12/n)-1)/abs(mdd)) }
apply_exp<-function(ser,bps,kind){ ex<-mk_exp(ser$mon,kind); dex<-abs(diff(c(1,ex)))
  list(pr=ex*ser$pr-(bps/1e4)*dex, ex=ex) }

OUT<-list()
## 익스포저-단독 기준선 (Market x EXP) — 8-1 순서 요건
for(kind in c("E1","E2","E3")) for(bps in c(5,15)){
  ref<-SER[["C1_15"]]; ex<-mk_exp(ref$mon,kind); dex<-abs(diff(c(1,ex)))
  prm<-ex*ref$mon$Market-(bps/1e4)*dex
  keep<-which(is.finite(SER[[sprintf("C1_%d",bps)]]$pr))
  m<-mets(ref$mon[keep],prm[keep])
  OUT[[length(OUT)+1]]<-cbind(data.table(arm=sprintf("MKTx%s",kind),cost_bps=bps),m,
    data.table(base_pt=NA_real_,d_pt=NA_real_,d_calmar=NA_real_,d_MDD=NA_real_,avg_exp=round(mean(ex[keep]),3),min_exp=round(min(ex[keep]),3))) }
## FM base x EXP
for(an in c("v0","C1")) for(kind in c("E1","E2","E3")) for(bps in c(5,15)){
  ser<-SER[[sprintf("%s_%d",an,bps)]]; e<-apply_exp(ser,bps,kind)
  base<-mets(ser$mon,ser$pr); withx<-mets(ser$mon,e$pr)
  d<-cbind(data.table(arm=sprintf("%sx%s",an,kind),cost_bps=bps),withx)
  d[,`:=`(base_pt=base$pt_vsMkt, d_pt=withx$pt_vsMkt-base$pt_vsMkt,
          d_calmar=withx$calmar-base$calmar, d_MDD=withx$MDD-base$MDD,
          avg_exp=round(mean(e$ex[is.finite(ser$pr)]),3), min_exp=round(min(e$ex[is.finite(ser$pr)]),3))]
  OUT[[length(OUT)+1]]<-d }
R9<-rbindlist(OUT,fill=TRUE)
## 기준선 무익스포저 (대조)
base_rows<-rbindlist(lapply(c("v0","C1"),function(an){ s<-SER[[sprintf("%s_15",an)]]; cbind(data.table(arm=sprintf("%s_noEXP",an),cost_bps=15),mets(s$mon,s$pr)) }),fill=TRUE)
cat("== R9 익스포저 트리거 재설계 (crisis=mkt_jm 인과) ==\n")
cat("-- 무익스포저 기준선(15bps) --\n"); print(base_rows[,.(arm,pt_vsMkt,calmar,MDD)],digits=3)
cat("\n-- FM base x EXP (d_ = base 대비 변화) --\n")
print(R9[grepl("^v0x|^C1x",arm),.(arm,cost_bps,pt_vsMkt,calmar,MDD,d_pt,d_calmar,d_MDD,avg_exp,min_exp)][order(arm,cost_bps)],digits=3)
cat("\n-- 익스포저-단독 기준선 (Market x EXP) --\n")
print(R9[grepl("^MKTx",arm),.(arm,cost_bps,pt_vsMkt,SR,MDD,calmar,avg_exp,min_exp)][order(arm,cost_bps)],digits=3)
fwrite(R9,"outputs/ramp/dfa_exposure_r9_20260822.csv")
cat("\n[트리거 발화 통계] E1 crisis월수:",sum(mstat$crisis_max,na.rm=TRUE),
    "| rank_end 유효월:",sum(is.finite(mstat$rank_end)),"| rank_end 중앙:",round(median(mstat$rank_end,na.rm=TRUE),3),"\n")
cat("R9_DONE\n")
