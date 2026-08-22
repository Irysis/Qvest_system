## run_dfa_fm_exposure_r8.R — R8: FM + 위기-조건부 익스포저 층 (prereg dfa_v9 amendment_1, 가이드 8-1)
## crisis = mkt_jm Bear_Prob > expanding q95 (인과 월말 갱신, R3-C 정의). exposure = 0.70 crisis else 1.00.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
SER<-readRDS(".cache/_dfa_fm_dev_r7.rds")

## crisis 플래그 (월말, 인과 expanding q95 — 최소 60개월 이력)
jm<-as.data.table(read_parquet(".cache/regime_jump_daily.parquet", col_select=c("Date","Bear_Prob")))
jm[,Date:=as.Date(Date)]; jm<-jm[is.finite(Bear_Prob)]; setorder(jm,Date)
jm[,ym:=format(Date,"%Y-%m")]; jme<-jm[,.SD[Date==max(Date)],by=ym][,.(ym,bp=Bear_Prob)]
jme[,thr:=NA_real_]
for(i in seq_len(nrow(jme))){ h<-jm[Date<=jm[ym==jme$ym[i],max(Date)]]$Bear_Prob
  if(length(h)>=60*21) jme$thr[i]<-quantile(h,0.95,na.rm=TRUE) }
jme[,crisis:=is.finite(bp)&is.finite(thr)&bp>thr]

apply_exp<-function(ser,bps){ mon<-ser$mon; pr<-ser$pr
  ymv<-format(mon$medate,"%Y-%m")
  ## 결정 m-1 월말 crisis → m월 노출
  cr_dec<-jme[match(ymv,ym),crisis]; cr_use<-shift(cr_dec,1); cr_use[!is.finite(cr_use)]<-FALSE
  ex<-ifelse(cr_use,0.70,1.00)
  dex<-abs(diff(c(1,ex)))
  prx<-ex*pr-(bps/1e4)*dex
  list(pr=prx,ex=ex) }
mets<-function(mon,pr){ k<-is.finite(pr); p<-pr[k]; mk<-mon$Market[k]
  act<-p-mk; nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); n<-length(p)
  data.table(n_mo=n, pt_vsMkt=nwt(act), IR_vsMkt=IRf(act), SR=IRf(p),
    CAGR=prod(1+p)^(12/n)-1, MDD=mdd, calmar=(prod(1+p)^(12/n)-1)/abs(mdd)) }

OUT<-list()
## 익스포저-단독 기준선 (Market×EXP)
for(bps in c(5,15)){ mon<-SER[["v0_15"]]$mon
  prm<-mon$Market; ymv<-format(mon$medate,"%Y-%m")
  cr<-shift(jme[match(ymv,ym),crisis],1); cr[!is.finite(cr)]<-FALSE
  ex<-ifelse(cr,0.70,1.00); dex<-abs(diff(c(1,ex)))
  prx<-ex*prm-(bps/1e4)*dex
  keep<-which(is.finite(SER[[sprintf("v0_%d",bps)]]$pr))   # FM과 동일창
  m<-mets(mon[keep],prx[keep]); OUT[[length(OUT)+1]]<-cbind(data.table(arm="MKTxEXP",cost_bps=bps),m,data.table(crisis_months=sum(cr[keep]))) }
## FM 팔 × EXP
for(an in c("v0","F4","C1")) for(bps in c(5,15)){
  ser<-SER[[sprintf("%s_%d",an,bps)]]; e<-apply_exp(ser,bps)
  base<-mets(ser$mon,ser$pr); withx<-mets(ser$mon,e$pr)
  d<-cbind(data.table(arm=sprintf("%sxEXP",an),cost_bps=bps),withx)
  d[,`:=`(base_pt=base$pt_vsMkt, base_calmar=base$calmar, base_MDD=base$MDD,
          d_pt=withx$pt_vsMkt-base$pt_vsMkt, d_calmar=withx$calmar-base$calmar, d_MDD=withx$MDD-base$MDD,
          crisis_months=sum(e$ex<1 & is.finite(ser$pr)))]
  OUT[[length(OUT)+1]]<-d }
R8<-rbindlist(OUT,fill=TRUE)
cat("== R8 위기-조건부 익스포저 층 (crisis=mkt_jm>q95 인과, exp 0.70) ==\n")
print(R8,digits=3)
fwrite(R8,"outputs/ramp/dfa_fm_exposure_r8_20260822.csv")
cat("R8_DONE\n")
