## r3_inspect4.R — sign 방향(risk pole) + R1 LowRisk/Value family 차별(중복도) 해소
suppressPackageStartupMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

ds<-arrow::open_dataset("outputs/ramp/pure_factor_scores.parquet")
need<-c("D47_CVaR_5pct","D48_VaR_5pct","R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk",
        "D03_RealVol","D34_RealVol_21d","D45_Downside_Dev","V02_EP","V15_NetDebt_Adj_EP")
pf<-ds %>% filter(factor_id %in% need) %>%
  select(signal_date,security_id,factor_id,neutralized_z,z) %>% collect() %>% as.data.table()
pf[,signal_date:=as.Date(signal_date)]
cat("loaded",nrow(pf),"rows; z NA frac", round(mean(is.na(pf$neutralized_z)),3),"\n")
# use neutralized_z; fallback to z if all-NA
pf[,val:=fifelse(is.na(neutralized_z), z, neutralized_z)]

W<-dcast(pf, signal_date+security_id~factor_id, value.var="val")
# per-month cross-sectional correlation helper
xcor<-function(dt,a,b){
  s<-dt[!is.na(get(a))&!is.na(get(b)), .(c=if(.N>=20&&sd(get(a))>0&&sd(get(b))>0) cor(get(a),get(b),method="spearman") else NA_real_), by=signal_date]
  mean(s$c,na.rm=TRUE)
}
cat("\n=== risk-pole 확인: 각 tail 팩터 neutralized_z vs D03_RealVol (양수=high z가 high risk) ===\n")
for(f in c("D47_CVaR_5pct","D48_VaR_5pct","R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk","D45_Downside_Dev")){
  cat(sprintf("  cor(%s, D03_RealVol) = %+.3f\n", f, xcor(W,f,"D03_RealVol")))
}
cat("  cor(D34_RealVol_21d, D03_RealVol) =", sprintf("%+.3f",xcor(W,"D34_RealVol_21d","D03_RealVol")),"(vol 자기정합 sanity)\n")

# tail defense sleeve = mean of low-risk-oriented z. 먼저 risk-pole 부호로 정렬.
tailf<-c("D47_CVaR_5pct","D48_VaR_5pct","R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk")
poles<-sapply(tailf,function(f) sign(xcor(W,f,"D03_RealVol")))
cat("\nrisk poles (sign vs RealVol):",paste(tailf,poles,sep="="),"\n")
# defense sleeve: orient each toward LOW risk => multiply by -pole
for(f in tailf) W[, (paste0(f,"_def")):= get(f) * (-poles[f])]
defcols<-paste0(tailf,"_def")
W[, tail_def := rowMeans(.SD, na.rm=TRUE), .SDcols=defcols]
# z-score tail_def per month
W[, tail_def_z := { m<-mean(tail_def,na.rm=T); s<-sd(tail_def,na.rm=T); if(is.na(s)||s<1e-9) tail_def-m else (tail_def-m)/s }, by=signal_date]
cat("cor(tail_def_z, D03_RealVol) =",sprintf("%+.3f",xcor(W,"tail_def_z","D03_RealVol")),"(음수여야 defense=low risk)\n")

# R1 LowRisk / Value family group_z 비교 (차별·중복도)
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
lr<-g[family=="LowRisk",.(signal_date,security_id,LowRisk=group_z)]
vv<-g[family=="Value",.(signal_date,security_id,Value=group_z)]
W2<-merge(W[,.(signal_date,security_id,tail_def_z,V02_EP,V15_NetDebt_Adj_EP)],lr,by=c("signal_date","security_id"),all.x=TRUE)
W2<-merge(W2,vv,by=c("signal_date","security_id"),all.x=TRUE)
cat("\n=== 차별 검증 (candidate sleeve vs R1 family group_z) ===\n")
cat("  cor(tail_def_z, LowRisk group_z) =",sprintf("%+.3f",xcor(W2,"tail_def_z","LowRisk")),"(높으면 R1 LowRisk와 중복 우려)\n")
cat("  cor(V02_EP, Value group_z)       =",sprintf("%+.3f",xcor(W2,"V02_EP","Value")),"(높으면 R1 Value와 중복 우려)\n")
cat("  cor(V02_EP, V15_NetDebt_Adj_EP)  =",sprintf("%+.3f",xcor(W2,"V02_EP","V15_NetDebt_Adj_EP")),"\n")
cat("\nDONE_INSPECT4\n")
