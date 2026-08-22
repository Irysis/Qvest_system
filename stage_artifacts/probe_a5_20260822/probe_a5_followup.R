## probe_a5_followup.R — A5 기전 프로브 2차: 위상평균 사다리 · 무작위 스케줄 null · 변동성 분해 · 신호 whipsaw
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
OUTD<-"stage_artifacts/probe_a5_20260822"; set.seed(20260822)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
load_mon<-function(path){
  R<-as.data.table(read_parquet(path)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
  fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
  R[,ym:=format(Date,"%Y-%m")]
  mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
  setorder(mon,medate); list(mon=mon,fac=fac) }
BR<-load_mon("outputs/ramp/dfa_index_returns_broad_202608.parquet")
mon<-BR$mon; fac<-BR$fac; NM<-nrow(mon); NAx<-1+length(fac)
mk_sig<-function(mon,fac,win=12){ S<-matrix(NA_real_,nrow(mon),length(fac)); colnames(S)<-fac
  for(fi in seq_along(fac)){f<-fac[fi]; for(m in win:nrow(mon)){w<-(m-win+1):m
    S[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1}}; S }
S12<-mk_sig(mon,fac,12)

## sched: 결정월 집합을 직접 주입할 수 있는 엔진 (NULL이면 freq/phase 규칙)
run_arm3<-function(bps=15,freq=1,phase=0,start_m=13,sched=NULL,rebal_mode="drift"){
  pr<-rep(NA_real_,NM); gr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  wprev<-rep(1/NAx,NAx); wcur<-NULL; wtar<-NULL
  for(m in start_m:NM){ d<-m-1
    is_dec <- if(is.null(sched)) (is.null(wcur)||((m-start_m-phase)%%freq==0)) else (is.null(wcur)||(m %in% sched))
    if(is_dec){ s<-S12[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wtar<-w; wcur<-w
    } else if(rebal_mode=="reset") wcur<-wtar
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; gr[m]<-sum(wcur*ri); pr[m]<-gr[m]-(bps/1e4)*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  list(pr=pr,gross=gr,tov=tov) }
stat<-function(r,b){ k<-is.finite(r$pr); mk<-mon$Market[k]
  ga<-r$gross[k]-mk; na<-r$pr[k]-mk
  data.table(pt=nwt(na), IR=IRf(na), gross_pt=nwt(ga), gross_IR=IRf(ga),
    act_mean_ann=mean(na)*12, act_sd_ann=sd(na)*sqrt(12),
    gross_mean_ann=mean(ga)*12, gross_sd_ann=sd(ga)*sqrt(12), TO_ann=mean(r$tov[k])*12) }

## ===== (A) 위상평균 리밸 사다리 — 위상 로터리 제거 =====
cat("=========== (A) 위상-평균 리밸 주기 사다리 ===========\n")
LAD<-list()
for(f in c(1,2,3,4,5,6,12)){ rows<-list()
  for(p in 0:(f-1)){ r15<-run_arm3(15,f,p); r0<-run_arm3(0,f,p)
    s15<-stat(r15,15); s0<-stat(r0,0)
    rows[[length(rows)+1]]<-data.table(freq=f,phase=p,pt15=s15$pt,pt0=s0$pt,IR15=s15$IR,
      TO=s15$TO_ann,gross_mean=s0$gross_mean_ann,gross_sd=s0$gross_sd_ann,gross_IR=s0$gross_IR) }
  rr<-rbindlist(rows); LAD[[length(LAD)+1]]<-rr }
LADall<-rbindlist(LAD); fwrite(LADall,file.path(OUTD,"p6_phase_all.csv"))
AVG<-LADall[,.(n_phase=.N, pt15_mean=mean(pt15), pt15_min=min(pt15), pt15_max=max(pt15),
               pt0_mean=mean(pt0), IR15_mean=mean(IR15), TO_mean=mean(TO),
               gross_mean_ann=mean(gross_mean), gross_sd_ann=mean(gross_sd), gross_IR=mean(gross_IR)),by=freq]
print(AVG,digits=4); fwrite(AVG,file.path(OUTD,"p6_phase_avg_ladder.csv"))
b<-AVG[freq==1]
cat(sprintf("\n  기준 freq=1: pt15=%.3f pt0=%.3f gross_mean=%.4f%% gross_sd=%.4f%% TO=%.2f\n",
  b$pt15_mean,b$pt0_mean,b$gross_mean_ann*100,b$gross_sd_ann*100,b$TO_mean))
cat("  freq=3 위상평균 pt15 = ",sprintf("%.3f",AVG[freq==3]$pt15_mean)," (A5 실제 phase0 = 3.232)\n",sep="")

## ===== (B) 무작위 리밸 스케줄 null (평균 주기 3개월) =====
cat("\n=========== (B) 무작위 스케줄 null (p=1/3, B=400) ===========\n")
B<-400; nullpt15<-numeric(B); nullpt0<-numeric(B); nullTO<-numeric(B)
for(i in 1:B){ sc<-which(runif(NM)<1/3); r<-run_arm3(15,sched=sc); r0<-run_arm3(0,sched=sc)
  nullpt15[i]<-stat(r,15)$pt; nullpt0[i]<-stat(r0,0)$pt; nullTO[i]<-stat(r,15)$TO_ann }
a5_15<-3.23180114; a5_0<-3.47943483; c1_15<-2.77483103; c1_0<-3.18009279
cat(sprintf("  15bps null: mean=%.3f sd=%.3f q05=%.3f q50=%.3f q95=%.3f | TO mean=%.2f\n",
  mean(nullpt15),sd(nullpt15),quantile(nullpt15,.05),median(nullpt15),quantile(nullpt15,.95),mean(nullTO)))
cat(sprintf("   -> A5(3.232) 백분위 = %.3f | C1 월간(2.775) 백분위 = %.3f\n",mean(nullpt15<a5_15),mean(nullpt15<c1_15)))
cat(sprintf("  0bps null: mean=%.3f sd=%.3f q05=%.3f q95=%.3f\n",mean(nullpt0),sd(nullpt0),quantile(nullpt0,.05),quantile(nullpt0,.95)))
cat(sprintf("   -> A5(3.479) 백분위 = %.3f | C1(3.180) 백분위 = %.3f\n",mean(nullpt0<a5_0),mean(nullpt0<c1_0)))
fwrite(data.table(pt15=nullpt15,pt0=nullpt0,TO=nullTO),file.path(OUTD,"p6_random_sched_null.csv"))

## ===== (C) pt 격차의 평균 vs 변동성 분해 =====
cat("\n=========== (C) pt 격차 분해 (평균효과 vs 변동성효과) ===========\n")
c1<-stat(run_arm3(15,1,0),15); a5<-stat(run_arm3(15,3,0),15)
c10<-stat(run_arm3(0,1,0),0); a50<-stat(run_arm3(0,3,0),0)
ir_mean_eff<-(a5$act_mean_ann-c1$act_mean_ann)/c1$act_sd_ann
ir_vol_eff <-a5$act_mean_ann*(1/a5$act_sd_ann-1/c1$act_sd_ann)
cat(sprintf("  15bps: C1 mean=%.4f%% sd=%.4f%% IR=%.4f | A5 mean=%.4f%% sd=%.4f%% IR=%.4f\n",
  c1$act_mean_ann*100,c1$act_sd_ann*100,c1$IR,a5$act_mean_ann*100,a5$act_sd_ann*100,a5$IR))
cat(sprintf("   IR 격차 %.4f = 평균효과 %.4f (%.1f%%) + 변동성효과 %.4f (%.1f%%)\n",
  a5$IR-c1$IR,ir_mean_eff,100*ir_mean_eff/(a5$IR-c1$IR),ir_vol_eff,100*ir_vol_eff/(a5$IR-c1$IR)))
cat(sprintf("  0bps : C1 mean=%.4f%% sd=%.4f%% IR=%.4f | A5 mean=%.4f%% sd=%.4f%% IR=%.4f (평균 거의 동일, sd −%.2f%%)\n",
  c10$act_mean_ann*100,c10$act_sd_ann*100,c10$IR,a50$act_mean_ann*100,a50$act_sd_ann*100,a50$IR,
  100*(1-a50$act_sd_ann/c10$act_sd_ann)))
## 위상별 sd (변동성 이득이 위상 특수한가)
cat("  위상별 0bps active sd(연율%) / IR:\n")
for(p in 0:2){ s<-stat(run_arm3(0,3,p),0); cat(sprintf("    phase%d: sd=%.4f  mean=%.4f  IR=%.4f\n",p,s$act_sd_ann*100,s$act_mean_ann*100,s$IR)) }

## ===== (D) 월별 승패 분해 (gross vs cost) =====
cat("\n=========== (D) 월별 승패 분해 ===========\n")
rc<-run_arm3(15,1,0); ra<-run_arm3(15,3,0); k<-is.finite(rc$pr)&is.finite(ra$pr)
dg<-(ra$gross-rc$gross)[k]; dcst<-((15/1e4)*(rc$tov-ra$tov))[k]; dn<-(ra$pr-rc$pr)[k]
qk<-rep(c(1,2,3),length.out=sum(k))
cat(sprintf("  net 승률=%.3f | gross 승률=%.3f | cost 우위 월 비율=%.3f\n",mean(dn>0),mean(dg>0),mean(dcst>0)))
cat(sprintf("  |gross 차| 평균=%.4f%%/월  vs |cost 차| 평균=%.4f%%/월 (%.1f배)\n",
  mean(abs(dg))*100,mean(abs(dcst))*100,mean(abs(dg))/mean(abs(dcst))))
cat("  분기내 위치별 평균 net 차(%/월) 및 cost 차:\n")
for(q in 1:3) cat(sprintf("    q%d: net=%+.4f gross=%+.4f cost=%+.4f (n=%d)\n",q,
  mean(dn[qk==q])*100,mean(dg[qk==q])*100,mean(dcst[qk==q])*100,sum(qk==q)))
top<-order(abs(dn),decreasing=TRUE)[1:10]
cat(sprintf("  상위 10개월이 net 평균차에 기여하는 비중 = %.3f\n",sum(dn[top])/sum(dn)))
cat(sprintf("  상위 10개월 제거 후 평균차 = %.4f%%/yr (원 %.4f%%/yr), NW-t=%.3f\n",
  mean(dn[-top])*12*100,mean(dn)*12*100,nwt(dn[-top])))

## ===== (E) 신호 whipsaw — 월간 재결정이 되돌려지는 거래인가 =====
cat("\n=========== (E) 목표비중 증분의 자기상관 (whipsaw 검정) ===========\n")
dec<-12:(NM-1)
tgt<-function(d){ s<-S12[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
  if(!length(pos))w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); w }
TG<-t(sapply(dec,tgt)); DW<-TG[-1,]-TG[-nrow(TG),]
x<-as.vector(DW[-nrow(DW),]); y<-as.vector(DW[-1,])
cat(sprintf("  corr(dW_t, dW_t+1) = %+.4f  (음수=whipsaw/역전, 0=랜덤워크, 양수=추세)\n",cor(x,y)))
cat(sprintf("  거래 되돌림률 P(sign(dW_t+1) != sign(dW_t) | |dW_t|>0) = %.3f\n",
  mean(sign(y[abs(x)>1e-12])!=sign(x[abs(x)>1e-12]))))
## 실제 실현: 월간 재결정이 만든 '증분 거래'가 다음달 얼마나 되돌려지나 (weight 가중)
rev_frac<-sum(pmax(0,-y*sign(x))*abs(x)>0)  # placeholder guard
cat(sprintf("  |dW| L1 평균 = %.4f (월) — 이 중 다음달 역방향 비중 = %.3f\n",
  mean(rowSums(abs(DW))), sum(abs(y)[sign(y)!=sign(x)&abs(x)>1e-12])/sum(abs(y)[abs(x)>1e-12])))
## 12M active 신호 자체의 증분 자기상관
DS<-S12[dec[-1],]-S12[dec[-length(dec)],]
xs<-as.vector(DS[-nrow(DS),]); ys<-as.vector(DS[-1,])
cat(sprintf("  corr(dSignal_t, dSignal_t+1) = %+.4f\n",cor(xs,ys,use="complete.obs")))

## ===== (F) 신규진입 팩터의 비중 몫 =====
cat("\n=========== (F) 신규진입 팩터가 차지하는 비중 몫 ===========\n")
ON<-(is.finite(S12)&S12>0)[dec,,drop=FALSE]; nd<-nrow(ON)
TEN<-matrix(0L,nd,ncol(ON)); for(j in seq_len(ncol(ON))){t<-0L;for(i in 1:nd){t<-if(ON[i,j])t+1L else 0L;TEN[i,j]<-t}}
wsum_new<-0;wsum_old<-0;cnt_new<-0;cnt_old<-0
for(i in 1:nd){ s<-S12[dec[i],]; pos<-which(is.finite(s)&s>0); if(!length(pos))next
  w<-s[pos]/sum(s[pos]); tn<-TEN[i,pos]
  wsum_new<-wsum_new+sum(w[tn<=3]); wsum_old<-wsum_old+sum(w[tn>=4])
  cnt_new<-cnt_new+sum(tn<=3); cnt_old<-cnt_old+sum(tn>=4) }
cat(sprintf("  신규(tenure<=3): 종목수 몫 %.3f · 비중 몫 %.3f\n",cnt_new/(cnt_new+cnt_old),wsum_new/(wsum_new+wsum_old)))
cat(sprintf("  유지(tenure>=4): 종목수 몫 %.3f · 비중 몫 %.3f\n",cnt_old/(cnt_new+cnt_old),wsum_old/(wsum_new+wsum_old)))
cat("\nPROBE_A5_FOLLOWUP_DONE\n")
