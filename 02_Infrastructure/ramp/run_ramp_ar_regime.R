## run_ramp_ar_regime.R — 미배선 Absorption Ratio 엔진을 RAMP에 배선 (도훈 2026-06-19).
## AR(Kritzman 2010, 횡단면 상관 top-15 고유값 분산비 = 시장동조화/시스템취약) = 9축 MRS(US거시)와 직교한 국내축.
## 헌법 §3.5: hard switch 금지 → AR_z를 soft 3-state membership(risk_on/neutral/crisis, Σ=1, 연속)으로 변환,
##   M_regdd 군 IC를 soft-membership 가중 블렌드(μ_blend=Σ_s P(s)·IC_s). degenerate-CRISIS(3개월) 구조적 해소.
## 비교: baseline_hard(현 4-bin regime) vs AR_soft(배선). 실측 canonical_screen, PIT(AR 63d trailing + expanding z).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_ar.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_ar_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## ── 데이터 + sig_dates ──
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]   # hard 4-bin baseline
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(g$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
pg("data loaded\n")

## ── (배선 1) Absorption Ratio — col_select 안전 재구현 (Kritzman 2010, 63d/top15) ──
dr<-rawdata[!is.na(Ret),.(Date,Ticker,Ret)]; tds<-sort(unique(dr$Date))
ar_val<-rep(NA_real_,length(sig_dates))
for(i in seq_along(sig_dates)){ me<-sig_dates[i]; ei<-which(tds<=me); if(!length(ei))next; ei<-ei[length(ei)]
  if(ei<63)next; wd<-tds[(ei-62):ei]; wdat<-dr[Date %in% wd]
  sc<-wdat[,.N,by=Ticker]; vs<-sc[N>=floor(63*0.8),Ticker]; if(length(vs)<50)next
  rw<-dcast(wdat[Ticker %in% vs],Date~Ticker,value.var="Ret"); rm<-as.matrix(rw[,-1])
  cv<-apply(rm,2,var,na.rm=T); keep<-!is.na(cv)&cv>1e-10; if(sum(keep)<50)next; rm<-rm[,keep]; rm[is.na(rm)]<-0
  cm<-tryCatch(cor(rm,use="pairwise.complete.obs"),error=function(e)NULL); if(is.null(cm))next
  cm[is.na(cm)]<-0; diag(cm)<-1
  ev<-tryCatch(eigen(cm,symmetric=TRUE,only.values=TRUE)$values,error=function(e)NULL); if(is.null(ev))next
  lam<-pmax(0,ev); tot<-sum(lam); if(tot<1e-10)next; k<-min(15,length(lam))
  ar_val[i]<-sum(sort(lam,decreasing=TRUE)[1:k])/tot }
# expanding z (PIT)
ar_z<-rep(NA_real_,length(sig_dates))
for(i in seq_along(ar_val)){ p<-ar_val[1:i]; p<-p[is.finite(p)]; if(length(p)<12)next; s<-sd(p); if(!is.na(s)&&s>1e-8)ar_z[i]<-(ar_val[i]-mean(p))/s }
ARDT<-data.table(signal_date=sig_dates, ar=ar_val, ar_z=ar_z); ARDT[is.na(ar_z),ar_z:=0]
pg("AR computed: %d non-NA\n", sum(is.finite(ar_val)))
w("=== (배선) Absorption Ratio — 위기 포착 검증 ===")
for(cd in c("2008-10-31","2009-02-28","2020-03-31","2022-09-30","2026-03-31")){ r<-ARDT[signal_date<=as.Date(cd)][.N]
  w(sprintf("  %s: AR=%.3f ar_z=%+.2f", r$signal_date, r$ar, r$ar_z)) }
w(sprintf("  ar_z 범위 [%.2f, %.2f], 평균 %.2f", min(ARDT$ar_z,na.rm=T), max(ARDT$ar_z,na.rm=T), mean(ARDT$ar_z,na.rm=T)))

## ── (배선 2) AR_z → soft 3-state membership (Σ=1, no hard switch) ──
TAU<-1.0; anc<-c(risk_on=-1,neutral=0,crisis=1)
softmem<-function(z){ e<-exp(anc*z/TAU); e/sum(e) }
MEM<-ARDT[,{m<-softmem(ar_z); .(w_risk_on=m["risk_on"],w_neutral=m["neutral"],w_crisis=m["crisis"])},by=signal_date]
states<-c("risk_on","neutral","crisis")
w(sprintf("\nsoft membership 평균: risk_on=%.2f neutral=%.2f crisis=%.2f (연속, hard switch 없음)",
  mean(MEM$w_risk_on),mean(MEM$w_neutral),mean(MEM$w_crisis)))

## ── 군 월별 IC (forward) ──
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,MEM,by="signal_date"); setorder(gic,family,signal_date)

## ── score 빌더 ──
mk_score<-function(mode){ rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d)
    if(mode=="hard"){ rg<-gw[signal_date==dd,regime][1]
      hmap<-c(BULL="risk_on",NORMAL="neutral",CAUTION="neutral",CRISIS="crisis")  # 4-bin→3 근사(baseline 재현용은 아래 분리)
      wts<-sapply(grp,function(fm){p<-gic[family==fm&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0}) # uncond (baseline_uncond)
    } else if(mode=="hard4"){ rg<-gw[signal_date==dd,regime][1]
      wts<-sapply(grp,function(fm){ sub<-gic[family==fm&signal_date<dd]; sub<-sub[is.finite(ic)]
        # hard: 같은 4-bin regime 월만 (원 baseline 재현)
        rm<-gw[signal_date<dd & regime==rg,signal_date]; p<-sub[signal_date %in% rm,ic]; if(length(p)>=3)max(mean(p),0)else 0})
    } else { # AR_soft: μ_blend = Σ_s membership_s · IC_group,s (membership-가중 조건부 IC)
      mt<-MEM[signal_date==dd]
      wts<-sapply(grp,function(fm){ sub<-gic[family==fm&signal_date<dd]; sub<-sub[is.finite(ic)]; if(nrow(sub)<3)return(0)
        ics<-sapply(states,function(st){ ww<-sub[[paste0("w_",st)]]; if(sum(ww)<1e-6)return(NA); sum(sub$ic*ww)/sum(ww) })
        memnow<-c(mt$w_risk_on,mt$w_neutral,mt$w_crisis); v<-sum(memnow*ics,na.rm=TRUE); max(v,0) })
    }
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
    rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  s<-rbindlist(rows); s[,score:=zc(score),by=signal_date]; s}

gates<-function(sc,lab){
  cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
        fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],
        top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="ar",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL)
  pr<-as.data.table(cs$period_returns); setorder(pr,date); act<-pr$ret_net-pr$benchmark_ret
  n<-nrow(pr); .sp<-c(.55,.65,.75); rets<-sapply(.sp,function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
  data.table(model=lab, pt_capwt=nwt(act), oos_reten=median(rets,na.rm=T), calmar=cal, full_IR=IRf(act), TO=cs$turnover_annual)
}
pg("scoring hard4\n"); R1<-gates(mk_score("hard4"),"baseline_hard4(현 regime)")
pg("scoring AR_soft\n"); R2<-gates(mk_score("AR_soft"),"AR_soft(배선)")
R<-rbindlist(Filter(Negate(is.null),list(R1,R2)),fill=TRUE)
w("\n=== M_regdd: 현 hard-분류기 vs AR-배선 soft-membership (cap-w, book ref 게이트 2.95/0.7/0.64) ===")
w(sprintf("  %-26s %8s %9s %7s %7s %6s","model","pt_capwt","oos_reten","calmar","full_IR","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-26s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f",R$model[i],R$pt_capwt[i],R$oos_reten[i],R$calmar[i],R$full_IR[i],R$TO[i]))
saveRDS(list(R=R,ARDT=ARDT,MEM=MEM),".cache/_ramp_ar.rds")
write_parquet(ARDT,"outputs/ramp/absorption_ratio_signal.parquet")   # 배선 산출 (재사용)
w("\n[배선 완료] AR 신호 → outputs/ramp/absorption_ratio_signal.parquet + soft membership M_regdd")
close(con); cat("AR_DONE\n")
