#==============================================================================
# Codex Critic supplements: best-single-factor ICIR (RF-A2), sector-neutral IC
# drop (RF-A4), correlation vs STR_1715 active (L-219), DSR multiplicity (RF-A6).
#==============================================================================
suppressPackageStartupMessages({library(data.table);library(arrow);library(dplyr);library(jsonlite)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")
FACTORS <- c("Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability")
AF <- "stage_artifacts/WT_D20260614_003"

# ---- rebuild panel WITH per-factor z + sector ----
ds <- open_dataset(".cache/rawdata.parquet")
raw <- as.data.table(ds %>% select(Date,Ticker,K200,KQ150,Sector,Close,Vol,BM_Ret) %>%
  filter(Date >= as.Date("2004-06-01")) %>% collect())
setorder(raw,Ticker,Date); raw[,Date:=as.Date(Date)]
raw[,tv:=Vol*Close]; raw[,adv20:=frollmean(tv,20,align="right"),by=Ticker]; raw[,ym:=format(Date,"%Y%m")]
me_dates <- raw[,.(me_date=max(Date)),by=ym]
me <- merge(raw,me_dates,by="ym"); me <- me[Date==me_date]; me[,ym_int:=as.integer(ym)]
setorder(me,Ticker,ym_int)
me[,fwd_close:=shift(Close,type="lead"),by=Ticker]; me[,fwd_ym_int:=shift(ym_int,type="lead"),by=Ticker]
me[,Ret_1m:=fwd_close/Close-1]
me[,gap_ok:={y1<-ym_int%/%100;m1<-ym_int%%100;y2<-fwd_ym_int%/%100;m2<-fwd_ym_int%%100;(y2*12+m2)-(y1*12+m1)==1}]
me[gap_ok==FALSE|is.na(gap_ok),Ret_1m:=NA_real_]
sig_dates <- sort(unique(me_dates$me_date)); sig_dates <- sig_dates[sig_dates>=as.Date("2005-01-01")]

rows <- rbindlist(lapply(sig_dates,function(sd){
  ym_tag<-format(sd,"%Y%m"); snap<-me[ym==ym_tag]; if(nrow(snap)==0) return(NULL)
  snap[,in_univ:=(K200==1|KQ150==1)]; snap[is.na(in_univ),in_univ:=FALSE]
  snap[,liq_ok:=!is.na(adv20)&adv20>=2e8]; univ<-snap[in_univ&liq_ok]; if(nrow(univ)<30) return(NULL)
  ff<-tryCatch(load_month_factors(sd,coverage_min=0.05,factor_names=FACTORS),error=function(e)NULL)
  if(is.null(ff)||nrow(ff)==0) return(NULL); ff<-ff[Ticker%in%univ$Ticker]
  w<-dcast(ff,Ticker~Factor_Name,value.var="Z_Score_Aligned",fun.aggregate=function(x)x[1])
  have<-intersect(FACTORS,names(w)); if(length(have)<2) return(NULL)
  for(f in have){z<-w[[f]];mu<-mean(z,na.rm=T);sg<-sd(z,na.rm=T);w[[f]]<-if(is.finite(sg)&&sg>0)(z-mu)/sg else NA_real_}
  m<-merge(w,univ[,.(Ticker,Sector,Ret_1m)],by="Ticker",all.x=TRUE); m[,Date:=sd]; m
}),fill=TRUE)

# ---- (1) Best single-factor ICIR vs composite (RF-A2) ----
icir_one <- function(fac){
  d<-rows[!is.na(get(fac))&!is.na(Ret_1m)]
  ic<-d[,.(ic=suppressWarnings(cor(get(fac),Ret_1m,method="spearman",use="complete.obs")),n=.N),by=Date][n>=10&is.finite(ic)]
  c(rank_ic=mean(ic$ic),icir=mean(ic$ic)/sd(ic$ic))
}
single<-sapply(FACTORS,icir_one)
rows[,comp:=rowMeans(.SD,na.rm=T),.SDcols=FACTORS]
ic_c<-rows[!is.na(comp)&!is.na(Ret_1m),.(ic=suppressWarnings(cor(comp,Ret_1m,method="spearman",use="complete.obs")),n=.N),by=Date][n>=10&is.finite(ic)]
comp_icir<-mean(ic_c$ic)/sd(ic_c$ic); comp_ic<-mean(ic_c$ic)
best_single_icir<-max(single["icir",])
cat("=== RF-A2: single vs composite ICIR ===\n")
print(round(single,4)); cat(sprintf("composite: rank_ic=%.4f icir=%.4f | best_single_icir=%.4f | improve=%.1f%%\n",
  comp_ic,comp_icir,best_single_icir,(comp_icir/best_single_icir-1)*100))

# ---- (2) Sector-neutral IC drop (RF-A4) ----
rows[,comp_sn:={x<-comp; if(sum(!is.na(x))>2){ x-ave(x,Sector,FUN=function(z)mean(z,na.rm=T)) } else x},by=Date]
ic_sn<-rows[!is.na(comp_sn)&!is.na(Ret_1m),.(ic=suppressWarnings(cor(comp_sn,Ret_1m,method="spearman",use="complete.obs")),n=.N),by=Date][n>=10&is.finite(ic)]
sn_ic<-mean(ic_sn$ic); sn_icir<-mean(ic_sn$ic)/sd(ic_sn$ic)
cat(sprintf("\n=== RF-A4: sector-neutral IC ===\nraw_ic=%.4f sector_neutral_ic=%.4f retention=%.1f%% (sn_icir=%.3f)\n",
  comp_ic,sn_ic,sn_ic/comp_ic*100,sn_icir))

# ---- (3) Correlation vs STR_1715 active (L-219) ----
sm<-as.data.table(read_parquet(file.path(AF,"sleeve_monthly.parquet")))[order(Date)]
sm[,ym:=format(Date,"%Y%m")]
s17<-as.data.table(read_parquet("stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet"))
s17[,ym:=format(date,"%Y%m")]
mrg<-merge(sm[,.(ym,ret_net,active_net)],s17[,.(ym,str_ret=ret_net)],by="ym")
# benchmark monthly for STR active — use sm BM
mrg<-merge(mrg,sm[,.(ym,BM_Ret)],by="ym")
mrg[,str_active:=str_ret-BM_Ret]
cor_total<-cor(mrg$ret_net,mrg$str_ret)
cor_active<-cor(mrg$active_net,mrg$str_active)
cat(sprintf("\n=== L-219: correlation vs STR_1715 ===\nn=%d cor_total=%.3f cor_active=%.3f\n",nrow(mrg),cor_total,cor_active))

# ---- (4) DSR with realistic multiplicity (RF-A6) ----
# Decontam path: cluster23 was selected from 409 batch candidates → effective n_trials.
# Report DSR under n_trials in {1, 23 (cluster), 409 (batch)}.
d<-readRDS(file.path(AF,"diag.rds"))
sr_m<-d$net_sr/sqrt(12); T_obs<-d$T_obs
act<-sm$active_net; sk<-mean((act-mean(act))^3)/sd(act)^3; ku<-mean((act-mean(act))^4)/sd(act)^4
dsr_for<-function(N){
  # expected max SR under N trials (Bailey-LdP): SR0 = sqrt(Var_IS_SR)*((1-g)*Z_inv(1-1/N)+g*Z_inv(1-1/(N*e)))
  g<-0.5772156649; e<-exp(1); varSR<-(1-sk*sr_m+(ku-1)/4*sr_m^2)/(T_obs-1)
  sr0<-sqrt(varSR)*((1-g)*qnorm(1-1/N)+g*qnorm(1-1/(N*e)))
  if(N==1) sr0<-0
  num<-(sr_m-sr0)*sqrt(T_obs-1); den<-sqrt(1-sk*sr_m+(ku-1)/4*sr_m^2)
  pnorm(num/den)
}
dsr_tbl<-sapply(c(1,23,409),dsr_for)
cat(sprintf("\n=== RF-A6: DSR multiplicity ===\nn_trials=1: DSR=%.3f | n=23(cluster): DSR=%.3f | n=409(batch): DSR=%.3f\n",
  dsr_tbl[1],dsr_tbl[2],dsr_tbl[3]))

out<-list(
  rf_a2_single_vs_composite=list(single=as.list(as.data.frame(round(single,4))),
    composite_rank_ic=round(comp_ic,4),composite_icir=round(comp_icir,4),
    best_single_icir=round(best_single_icir,4),
    composite_improve_pct=round((comp_icir/best_single_icir-1)*100,1),
    verdict=if(comp_icir>best_single_icir*1.05)"composite >5% better than best single (RF-A2 PASS)" else "composite improvement <5% (RF-A2 FLAG)"),
  rf_a4_sector_neutral=list(raw_ic=round(comp_ic,4),sector_neutral_ic=round(sn_ic,4),
    retention_pct=round(sn_ic/comp_ic*100,1),sn_icir=round(sn_icir,3),
    verdict=if(sn_ic>=0.5*comp_ic)"sector-neutral IC retains >=50% (RF-A4 PASS)" else "sector-neutral IC retention <50% (RF-A4 FAIL)"),
  l219_str1715_corr=list(n=nrow(mrg),cor_total=round(cor_total,3),cor_active=round(cor_active,3),
    threshold_active=0.30,baseline_409_corr_core=0.87,
    verdict=if(cor_active<0.30)"active correlation vs STR_1715 <0.30 (diversifier confirmed)" else sprintf("active cor %.2f — NOT a low-cor diversifier on active basis",cor_active)),
  rf_a6_dsr_multiplicity=list(dsr_n1=round(dsr_tbl[1],3),dsr_n23_cluster=round(dsr_tbl[2],3),
    dsr_n409_batch=round(dsr_tbl[3],3),
    verdict=if(dsr_tbl[2]>=0.5)"DSR survives cluster-level multiplicity (n=23)" else "DSR fails under cluster multiplicity")
)
write_json(out,file.path(AF,"codex_supplements.json"),pretty=TRUE,auto_unbox=TRUE,digits=6)
cat("\nsaved codex_supplements.json\n")
