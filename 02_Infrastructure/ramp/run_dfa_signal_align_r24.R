## run_dfa_signal_align_r24.R — R24 진단: DFA 낙폭 시점 ↔ 국면 신호 정합도
## ★선택 오염 방지: 진단은 IS 구간(~2015-06)만. 선정 신호는 별도 사전등록 후 전 구간 측정.
## ★응답 규칙을 고정(노출 = 1 - 0.7*1{elevated})하고 신호만 바꿔 like-for-like 비교.
suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MDD<-function(r){n<-cumprod(1+r);min(n/cummax(n)-1)}; CAGR<-function(r,ppy=252)prod(1+r)^(ppy/length(r))-1
Z<-readRDS(".cache/_dfa_r23.rds"); D<-copy(Z$DAILY)[,.(Date,r=Strategy_Ret,mk=Market_Ret)]
setorder(D,Date)
SIG<-list()
v2<-as.data.table(read_parquet(".cache/regime_daily_v2.parquet")); v2[,Date:=as.Date(Date)]
for(k in c("MRS","n_axes_firing","VIX_z_smooth","FinStress_z_smooth","KRW_z_smooth","NFCI_z_smooth","Claims_z_smooth"))
  if(k %in% names(v2)) SIG[[k]]<-v2[,.(Date,s=get(k))]
pb<-as.data.table(read_parquet("06_Registry/regime_published/regime_signal_daily_published.parquet")); pb[,Date:=as.Date(Date)]
for(k in c("MSM_Crisis_Prob","FRED_MRS","Regime_Score","Regime_Score_smooth","KTRI_Score","Cash_Pct"))
  if(k %in% names(pb)) SIG[[k]]<-pb[,.(Date,s=get(k))]
## 인과 확장분위 (t 시점 문턱은 t-1 까지 데이터로만)
caus_flag<-function(s,q=0.80,burn=252L){ n<-length(s); f<-rep(FALSE,n); acc<-numeric(0)
  for(i in seq_len(n)){ if(i>burn && is.finite(s[i])){ th<-quantile(acc,q,na.rm=TRUE)
      if(is.finite(th)) f[i]<-s[i]>=th }
    if(is.finite(s[i])) acc<-c(acc,s[i]) }
  f }
IS_END<-as.Date("2015-06-30")
nav<-cumprod(1+D$r); ddv<-nav/cummax(nav)-1
D[,dd:=ddv]
isIdx<-which(D$Date<=IS_END)
cat(sprintf("=== R24 신호↔낙폭 정합도 진단 (IS-only: %s ~ %s, %d일) ===\n",
  format(min(D$Date)),format(IS_END),length(isIdx)))
cat(sprintf("IS 구간 DFA: CAGR %+.3f  MDD %.3f  calmar %.3f\n\n",
  CAGR(D$r[isIdx]),MDD(D$r[isIdx]),CAGR(D$r[isIdx])/abs(MDD(D$r[isIdx]))))
out<-list()
for(nm in names(SIG)){
  m<-merge(D,SIG[[nm]],by="Date",all.x=TRUE); setorder(m,Date)
  m[,s:=nafill(s,type="locf")]
  if(mean(is.finite(m$s))<0.5){ cat(sprintf("  %-20s 커버리지 부족(%.0f%%) — 제외\n",nm,100*mean(is.finite(m$s)))); next }
  m[,sl:=shift(s,1)]                                     # PIT: 전일 신호
  fl<-caus_flag(m$sl,0.80)
  i<-isIdx
  el<-fl[i]; rr<-m$r[i]; ddl<-m$dd[i]
  if(sum(el)<60){ cat(sprintf("  %-20s 발화 %d일 — 표본 부족, 제외\n",nm,sum(el))); next }
  mu_e<-mean(rr[el]); mu_n<-mean(rr[!el])
  ddcap<-sum(ddl[el] < -0.10)/max(1,sum(ddl < -0.10))     # 10%+ 낙폭 상태의 몇 %를 신호가 덮나
  ex<-ifelse(el,0.30,1.0)                                 # 응답 고정: CRISIS=0.30 (PG2 정본과 동일)
  ro<-ex*rr
  cal_o<-CAGR(ro)/abs(MDD(ro)); cal_b<-CAGR(rr)/abs(MDD(rr))
  out[[nm]]<-data.table(신호=nm, 발화율=mean(el), `평균수익_발화`=mu_e*252, `평균수익_비발화`=mu_n*252,
    `수익차(연율)`=(mu_e-mu_n)*252, `낙폭구간_포착률`=ddcap,
    `IS_calmar_base`=cal_b, `IS_calmar_오버레이`=cal_o, `calmar_개선`=cal_o/cal_b-1,
    `IS_MDD_base`=MDD(rr), `IS_MDD_오버레이`=MDD(ro))
}
T<-rbindlist(out); setorder(T,-`calmar_개선`)
cat("[IS 구간 like-for-like — 응답 규칙 고정(발화 시 노출 0.30), 신호만 교체]\n")
print(T[,.(신호,발화율=round(발화율,3),`수익차(연율)`=round(`수익차(연율)`,4),
  `낙폭포착`=round(`낙폭구간_포착률`,3), MDD_base=round(`IS_MDD_base`,3), MDD_ov=round(`IS_MDD_오버레이`,3),
  calmar_base=round(`IS_calmar_base`,3), calmar_ov=round(`IS_calmar_오버레이`,3), 개선=round(`calmar_개선`,3))])
fwrite(T,"outputs/ramp/dfa_signal_alignment_IS_20260822.csv")
cat(sprintf("\n[IS 최상] %s — calmar %.3f -> %.3f (%+.1f%%), MDD %.3f -> %.3f\n",
  T$신호[1],T$IS_calmar_base[1],T$`IS_calmar_오버레이`[1],100*T$calmar_개선[1],T$IS_MDD_base[1],T$`IS_MDD_오버레이`[1]))
cat("★이 선정은 IS-only 이며, 선정된 신호의 성과 판정은 별도 사전등록 후 전 구간에서 수행한다(OOS 미조회).\n")
cat("\nR24_DONE\n")
