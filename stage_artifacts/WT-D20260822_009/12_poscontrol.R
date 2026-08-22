## 양성 대조 = 동일 창(268m)·동일 하네스에서 기측정 양성(MAX5 상위10% 배제)의 검출 여부
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite);library(sandwich);library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT-D20260822_009")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<6L)return(NA_real_);fit<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(fit,vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
say <- function(f,...) cat(sprintf(paste0("[pc] ",f,"\n"),...))
O <- readRDS(file.path(OUT,"10_measure_objects.rds")); SMx<-O$SMx; rb<-O$rb
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret)[,Date:=as.Date(Date)]; bench<-as.data.table(SI$bench)[,Date:=as.Date(Date)]
PANx <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_010/ot_panel.parquet"))[,Date:=as.Date(Date)]
MAX5 <- PANx[is.finite(max5),.(Date,Ticker,max5)]
MM <- merge(SMx[,.(Date,Ticker,sc,Size,adv)], MAX5, by=c("Date","Ticker"), all.x=TRUE)
MM[, thr5 := {v<-max5[is.finite(max5)]; if(length(v)>=30L) quantile(v,0.90,type=7,names=FALSE) else Inf}, by=Date]
MM[, ex5 := is.finite(max5) & max5>=thr5]
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
top25 <- function(Sx){dd<-sort(unique(Sx$Date));W<-vector("list",length(dd))
  for(i in seq_along(dd)){sub<-Sx[Date==dd[i]];if(nrow(sub)<25)next;setorder(sub,-sc);hd<-head(sub,25)
    W[[i]]<-data.table(Date=dd[i],Ticker=hd$Ticker,w=cap_norm(hd$Size))};rbindlist(W)}
r5 <- weighted_screen_bt(top25(MM[ex5==FALSE,.(Date,Ticker,sc,Size,adv)]), fwd_ret, bench,
      cost_bps_oneway=15, run_id="WT009_pc_max5", strategy_id="WT009_poscontrol_max5")
pb <- as.data.table(rb$period_returns)[,.(date, ab=ret_net-benchmark_ret)]
p5 <- as.data.table(r5$period_returns)[,.(date, a5=ret_net-benchmark_ret)]
PD5 <- merge(pb,p5,by="date")[, d:=a5-ab]
J <- list(design="동일 base·동일 하네스·동일 268월 창에서 기측정 양성(WT-014 MAX5 상위10% 배제) 재측정 = 검사기 전도성(conductivity) 확인",
  delta_ir=r5$information_ratio-rb$information_ratio, paired_nw_t=nw_t(PD5$d),
  mean_d_active=mean(PD5$d), annual_pp=1200*mean(PD5$d), n=nrow(PD5),
  port_t_pc=r5$portfolio_alpha_t_nw_lag3, port_t_base=rb$portfolio_alpha_t_nw_lag3,
  prior_art_reference=list(delta_ir=0.1692, paired_t=1.565, n_months=256,
    note="WT-014 원 측정은 256 공통월(max5 가용창). 본 재측정은 268월 — 창이 달라 수치는 근사 일치 여부만 본다."))
J$detected <- isTRUE(J$delta_ir >= 0.05)
say("양성 대조 MAX5: ΔIR=%+.4f paired NW t=%+.3f mean=%+.5f (연 %+.2f%%p) PORT_t %.3f→%.3f | 검출=%s",
    J$delta_ir, J$paired_nw_t, J$mean_d_active, J$annual_pp, J$port_t_base, J$port_t_pc, J$detected)
write_json(J, file.path(OUT,"12_poscontrol.json"), auto_unbox=TRUE, pretty=TRUE, digits=NA, na="null")
