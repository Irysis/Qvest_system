## run_meta_diagnostic.R — 결함3 수리: 메타특성이 *다음달 팩터 IC*를 예측하나 (포트백테 前 진단층)
## 각 팩터-월의 forward IC(다음달 rank-IC)를 메타특성들에 패널회귀 → 부호·강도·유의성(팩터클러스터 SE).
## 부호가 정해지면 배선 방향/강도의 근거가 됨. (지금까지 임의계수·미검증부호였음.)
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_meta_diag.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam_of<-function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V")"Value" else if(p1=="M")"Momentum" else if(p1=="Q"||p=="GR")"Quality" else if(p1=="D")"LowRisk"
  else if(p1=="L")"Liquidity" else if(p1=="A")"Accrual" else if(p1=="C")"Consensus" else if(p1=="I"||p=="XF")"Flow"
  else if(p=="CR"||p=="SE")"Crowding" else if(p1=="R")"Risk" else if(p1=="G")"Growth" else "Other" }
w("======== 메타특성 → forward 팩터-IC 예측력 진단 ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)   # Date,factor_id,ic (당월 realized rank-IC)
FIC[,fam:=sapply(factor_id,fam_of)]
## ── forward IC = 다음달 realized IC (예측 대상) ──
FIC[, fwd_ic := shift(ic,-1L), by=factor_id]
## ── 메타특성 (전부 PIT: 당월까지 정보로 산출, 다음달 IC 예측) ──
FIC[, m_icmean := shift(frollmean(ic,12L,na.rm=TRUE),1L), by=factor_id]                          # base weight
FIC[, m_ic6    := shift(frollmean(ic,6L ,na.rm=TRUE),1L), by=factor_id]
FIC[, m_ic24   := shift(frollmean(ic,24L,na.rm=TRUE),1L), by=factor_id]
FIC[, m_slope  := m_ic6 - m_ic24]                                                                # 기울기
FIC[, m_icvol  := shift(frollapply(ic,12L,sd,fill=NA),1L), by=factor_id]                         # IC 변동성
FIC[, m_ichit  := shift(frollmean(as.numeric(ic>0),12L,na.rm=TRUE),1L), by=factor_id]            # 적중률
FIC[, m_persist:= as.numeric(m_ic6>0 & m_ic24>0)]
FIC[, m_fammean:= mean(m_icmean,na.rm=TRUE), by=.(Date,fam)]                                      # family 평균IC
## crowding / skew (팩터 롱레그) — 부호검증 목적
crf<-unique(sc$factor_id); crf<-crf[grepl("^CR|^SE",crf)]
stk_cr<-sc[factor_id %in% crf, .(cr_z=mean(nz,na.rm=T)), by=.(date,tic)]
m<-merge(sc[,.(date,tic,factor_id,nz)], ret_dt, by=c("date","tic")); m[, rk:=frank(-nz,ties.method="first")/.N, by=.(date,factor_id)]
top<-m[rk<=0.2]; fr<-top[,.(fret=mean(Ret,na.rm=T)),by=.(date,factor_id)]
tc<-merge(top[,.(date,factor_id,tic)], stk_cr, by=c("date","tic")); fcr<-tc[,.(crowd=mean(cr_z,na.rm=T)),by=.(date,factor_id)]
setorder(fr,factor_id,date); fr[,skew:=shift(frollapply(fret,24L,function(z){z<-z[is.finite(z)];if(length(z)<12)return(NA);mean(((z-mean(z))/sd(z))^3)},fill=NA),1L),by=factor_id]
FIC<-merge(FIC, fcr[,.(date=date,factor_id,crowd)], by.x=c("Date","factor_id"), by.y=c("date","factor_id"), all.x=TRUE)
FIC<-merge(FIC, fr[,.(date,factor_id,skew)], by.x=c("Date","factor_id"), by.y=c("date","factor_id"), all.x=TRUE)
FIC[, m_crowd:=shift(frollmean(crowd,3L,na.rm=TRUE),1L), by=factor_id]
FIC[, m_skew:=skew]
## 횡단(월별) z of 각 메타 → forward_ic 예측 (부호·강도 비교가능)
metas<-c("m_icmean","m_slope","m_icvol","m_ichit","m_persist","m_fammean","m_crowd","m_skew")
for(mm in metas) FIC[, (paste0("z_",mm)):=zc(get(mm)), by=Date]
DT<-FIC[is.finite(fwd_ic)]
## ── 단변량: 각 메타의 forward-IC 예측 (팩터·월 클러스터-robust t via NW on monthly mean) ──
w("\n=== 단변량: z_meta → forward 팩터-IC (월별 횡단 slope의 시계열 평균 + NW-t) ===")
w("  (부호+ = 그 메타 높을수록 다음달 IC 높음 → up-weight 정당. |t|>2 = 유의)")
uni<-data.table()
for(mm in metas){ zc2<-paste0("z_",mm)
  bt<-DT[is.finite(get(zc2)), .(b=coef(lm(fwd_ic~get(zc2)))[2]), by=Date]  # 월별 횡단 회귀 slope
  bt<-bt[is.finite(b)]; f<-lm(b~1,bt); tt<-as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])
  uni<-rbind(uni,data.table(meta=mm, mean_slope=round(mean(bt$b),5), t=round(tt,2), pred=ifelse(abs(tt)>2,ifelse(tt>0,"↑유의","↓유의"),"·무의")))
  w(sprintf("  %-10s mean_slope=%+.5f  t=%+.2f  %s", mm, mean(bt$b), tt, uni[.N,pred])) }
uni[,abst:=abs(t)]; setorder(uni,-abst); fwrite(uni,file.path(OUT,"meta_diag_uni.csv"))
## ── 다변량 (모든 메타 동시, 월별 → NW-t) ──
w("\n=== 다변량 (base m_icmean 통제하 각 메타의 *증분* 예측력) ===")
zs<-paste0("z_",metas); form<-as.formula(paste("fwd_ic ~", paste(zs,collapse="+")))
DTm<-DT[complete.cases(DT[,..zs])]
bt<-DTm[, { c<-tryCatch(coef(lm(form,.SD)),error=function(e) rep(NA,length(zs)+1)); as.list(c) }, by=Date]
setnames(bt, c("Date","intercept",zs))
for(zz in zs){ b<-bt[[zz]]; b<-b[is.finite(b)]; if(length(b)<12) next; f<-lm(b~1,data.table(b=b)); tt<-as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])
  w(sprintf("  %-10s 증분 slope=%+.5f  t=%+.2f  %s", sub("z_","",zz), mean(b), tt, ifelse(abs(tt)>2,"유의","·"))) }
w("\n  → base(m_icmean) 대비 *증분* 유의한 메타만 배선가치. crowd/skew 부호도 여기서 확정.")
cat("METADIAG| ", paste(sprintf("%s:t%.1f",uni$meta,uni$t),collapse=" "),"\n")
close(con); cat("META_DIAG_DONE\n")
