## run_ramp_round1.R — RAMP 자율 Round 1: 고레버리지 가설 (군선택/컨비션/IC가중) + OOS 검증
## 기준 best=M_regime_datadriven net_sr +0.110. 유의(port_t)까지 탐색. 다중검정 방어=OOS holdout.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R")); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/ramp/ramp_loop.R")
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
log<-file(".cache/_ramp_round1.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),log)
led<-ramp_observe(verbose=FALSE); w(sprintf("[Observe] L-code %d (failure %d 회피)", nrow(led$all%||%data.frame()), nrow(led$fails)))

g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g, signal_date+security_id ~ family, value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet")); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(gw$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
# OOS split (마지막 24m = holdout)
oos_cut<-sig_dates[length(sig_dates)-23]
cm<-tryCatch(readRDS(".cache/_consolidation.rds")$metrics,error=function(e)NULL)

score_wts<-function(dt,wts,cols){X<-as.matrix(dt[,..cols]);X[is.na(X)]<-0;ww<-wts[cols];ww[is.na(ww)]<-0;ww<-ww/sum(ww)
  d2<-dt[,.(signal_date,security_id)];d2[,score:=as.numeric(X%*%ww)];d2[,score:=zc(score),by=signal_date];d2}
# 데이터구동 regime 가중 (PIT trailing regime-IC) — Round0 best
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,unique(gw[,.(signal_date,regime)]),by="signal_date"); setorder(gic,family,signal_date)
regdd_score<-function(cols){ rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);rg<-gw[signal_date==dd,regime][1]
    wts<-sapply(cols,function(fm){p<-gic[family==fm&regime==rg&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(cols)),cols); rows[[d]]<-score_wts(gw[signal_date==dd],wts,cols)}
  rbindlist(rows)}
runbt<-function(d,lab){v<-validate_factor(d[,.(signal_date,security_id,factor_id=lab,neutralized_z=score)],fwd,top_n=25L,cost_bps=15)
  # OOS net_sr
  vo<-tryCatch(validate_factor(d[signal_date>=oos_cut,.(signal_date,security_id,factor_id=lab,neutralized_z=score)],fwd,top_n=25L,cost_bps=15),error=function(e)list())
  data.table(model=lab,net_sr=v$net_sr%||%NA,port_t=v$portfolio_alpha_t_nw%||%NA,to=v$turnover_annual%||%NA,oos_sr=vo$net_sr%||%NA)}

res<-list()
## H1 군선택: drag 군(Accruals/Credit/LowRisk/Composite) 제거 → regime_dd
keep<-setdiff(grp,c("Accruals","Credit","LowRisk","Composite"))
res$SEL<-runbt(regdd_score(keep),"H1_regdd_select7")
## H2 IC가중: 군별 rank_ic_ir 비례 (전체군)
if(!is.null(cm)){ icw<-setNames(pmax(cm$rank_ic_ir,0),cm$group); icw<-icw[grp]; icw[is.na(icw)]<-0
  res$ICW<-runbt(score_wts(gw,icw,grp),"H2_icweight") }
## H3 컨비션: regime_dd 스코어를 부호유지 제곱 틸트 (top 강조)
cv<-regdd_score(grp); cv[,score:=sign(score)*score^2]; cv[,score:=zc(score),by=signal_date]
res$CONV<-runbt(cv,"H3_regdd_conviction")
## H4 선택+컨비션
cs<-regdd_score(keep); cs[,score:=sign(score)*score^2]; cs[,score:=zc(score),by=signal_date]
res$SELC<-runbt(cs,"H4_select_conviction")

R<-rbindlist(res,fill=TRUE)[order(-net_sr)]
w("\n=== Round 1 (top-25 long-only net, OOS=마지막24m) ===")
w(sprintf("  %-22s %8s %8s %8s %8s","model","net_sr","port_t","TO","oos_sr"))
for(i in seq_len(nrow(R)))w(sprintf("  %-22s %+8.3f %+8.2f %8.1f %+8.3f",R$model[i],R$net_sr[i],R$port_t[i],R$to[i],R$oos_sr[i]))
b<-R[1]; prev<-0.110
w(sprintf("\n[Best] %s net_sr=%+.3f port_t=%+.2f oos=%+.3f | 직전best +0.110 대비 %s",b$model,b$net_sr,b$port_t,b$oos_sr,ifelse(b$net_sr>prev,"개선✓","미달")))
sig<-!is.na(b$port_t)&&b$port_t>1.96&&!is.na(b$oos_sr)&&b$oos_sr>0
w(sprintf("[유의 판정] port_t>1.96 ∧ OOS_sr>0 = %s", ifelse(sig,"★유의 달성","미달 — 계속")))
ramp_document(strategy_id=sprintf("RAMP_ROUND1_%s",format(Sys.Date(),"%Y%m%d")),grade=ifelse(b$net_sr>0,"B","C"),
  lesson_text=sprintf("Round1 고레버리지: best=%s net_sr=%+.3f port_t=%+.2f oos=%+.3f (직전 +0.110). 군선택(drag4 제거)/컨비션/IC가중 시험. %s",b$model,b$net_sr,b$port_t,b$oos_sr,ifelse(sig,"유의달성","미유의 계속")),
  metrics=list(best=b$model,net_sr=b$net_sr,port_t=b$port_t,oos_sr=b$oos_sr),core_reference="RAMP autonomous Round1")
saveRDS(R,".cache/_ramp_round1.rds"); close(log); cat("ROUND1_DONE\n")
