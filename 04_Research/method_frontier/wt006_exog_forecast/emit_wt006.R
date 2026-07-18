# WT-D20260718_006 — AX-001v2 crisis conditional + mandated charts + alpha_scores emission.
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(jsonlite)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
W5  <- "04_Research/method_frontier/wt005_factor_timing"
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
SA  <- "stage_artifacts/WT_D20260718_006"
fams <- c("value","quality","momentum","low_vol","size","dividend")

FAM  <- as.data.table(read_parquet(file.path(W5,"family_z_panel.parquet"))); FAM[,Date:=as.Date(Date)]
FEAT <- as.data.table(read_parquet(file.path(W5,"family_feature_panel.parquet"))); FEAT[,date:=as.Date(date)]
Rg <- as.data.table(read_parquet(file.path(W5,"grid_returns.parquet"))); Rg[,Date:=as.Date(Date)]
BMg<- as.data.table(read_parquet(file.path(W5,"grid_bench.parquet"))); BMg[,Date:=as.Date(Date)]
LQg<- as.data.table(read_parquet(file.path(W5,"grid_liq.parquet"))); LQg[,Date:=as.Date(Date)]
size_dt <- FAM[, .(Date,Ticker,size=Size)]
canon <- function(score_dt, dates){ S<-score_dt[!is.na(score),.(Date,Ticker,score)]; S<-S[Date %in% Rg$Date & Date %in% dates]
  canonical_screen_bt(S,Rg,BMg,top_n=25L,cost_bps_oneway=15,liq_dt=LQg,liq_min=2e8,run_id="wt006",strategy_id="wt006",periods_per_year=12L,diag_dual_basis=TRUE,size_dt=size_dt) }
score_from_theta <- function(th){ W<-dcast(th,date~family,value.var="theta"); setnames(W,fams,paste0("th_",fams))
  M<-merge(FAM,W,by.x="Date",by.y="date"); sc<-numeric(nrow(M)); for(fk in fams){z<-M[[fk]];w<-M[[paste0("th_",fk)]];z[is.na(z)]<-0;w[is.na(w)]<-0;sc<-sc+w*z}; M[,score:=sc]; M[,.(Date,Ticker,score)] }
oos_dates <- sort(unique(as.Date(read_parquet(file.path(W5,"theta_transformer_ensemble.parquet"))$date)))

FAM[, score_ew := rowMeans(.SD, na.rm=TRUE), .SDcols=fams]
mom_theta <- FEAT[is.finite(tr_12m),{z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9);w<-exp(2*z);.(family=family,theta=w/sum(w))},by=date]
th_gbm <- as.data.table(read_parquet(file.path(OUT,"theta_GBM_ensemble.parquet")));th_gbm[,date:=as.Date(date)]
th_en  <- as.data.table(read_parquet(file.path(OUT,"theta_EN_combined.parquet")));th_en[,date:=as.Date(date)]

res_static<-canon(FAM[,.(Date,Ticker,score=score_ew)],oos_dates)
res_mom   <-canon(score_from_theta(mom_theta),oos_dates)
res_gbm   <-canon(score_from_theta(th_gbm),oos_dates)
res_en    <-canon(score_from_theta(th_en),oos_dates)
act <- function(res){pr<-res$period_returns; data.table(date=as.Date(pr$date), active=pr$ret_net-pr$benchmark_ret)}

# ---- AX-001 v2 crisis conditional (best forecasting GBM vs momentum) ----
reg <- as.data.table(read_parquet("04_Research/decision_framework/smart_beta_regime/outputs/regime_labels_monthly.parquet"))
reg[, ym := as.character(ym)]
crisis_states <- unique(reg$regime_state)[grepl("crisis|bear|stress|risk_off|3|4", unique(reg$regime_state), ignore.case=TRUE)]
am<-act(res_mom); ag<-act(res_gbm); ab<-act(res_static)
am[,ym:=format(date,"%Y-%m")]; ag[,ym:=format(date,"%Y-%m")]
am<-merge(am,reg[,.(ym,regime_state)],by="ym",all.x=TRUE); ag<-merge(ag,reg[,.(ym,regime_state)],by="ym",all.x=TRUE)
is_cri <- function(s) s %in% crisis_states
ax001 <- list(crisis_states=crisis_states,
  n_crisis=sum(is_cri(am$regime_state),na.rm=TRUE),
  mom_crisis_active=round(mean(am[is_cri(regime_state)]$active,na.rm=TRUE),4),
  gbm_crisis_active=round(mean(ag[is_cri(regime_state)]$active,na.rm=TRUE),4),
  mom_normal_active=round(mean(am[!is_cri(regime_state)]$active,na.rm=TRUE),4),
  gbm_normal_active=round(mean(ag[!is_cri(regime_state)]$active,na.rm=TRUE),4))
write_json(ax001, file.path(OUT,"ax001_v2.json"), pretty=TRUE, auto_unbox=TRUE)
cat("AX-001 v2:\n"); print(ax001)

# ================= CHART 1: per-logic/config OOS survival bars =================
TAB <- fread(file.path(OUT,"wt006_eval_summary.csv"))
bar <- TAB[grepl("^EN_|^GBM_ensemble|factor_momentum|valuation|static", strategy)]
bar[, lab := gsub(" \\(.*\\)","",strategy)]
bar[, lab := gsub("EN_","",lab)]
setorder(bar, paired_vs_mom_t)
png(file.path(SA,"wt006_chart1_perlogic_oos_survival.png"), width=1150, height=720, res=130)
par(mar=c(5,11,4,2))
cols <- ifelse(bar$strategy=="factor_momentum (WT005 baseline)","#1f77b4", ifelse(bar$paired_vs_mom_t>=0,"#2ca02c","#d62728"))
bp<-barplot(bar$paired_vs_mom_t, horiz=TRUE, names.arg=bar$lab, las=1, col=cols, border=NA,
    xlab="paired NW-t (config active − factor-momentum active)", xlim=c(-2.8,0.6),
    main="WT-006: does any economic-logic combo beat factor-momentum OOS?\n(green>0 would beat baseline; all red = none survives)")
abline(v=0,lty=1,col="grey30"); abline(v=1.7,lty=2,col="darkgreen")
posv <- ifelse(is.finite(bar$paired_vs_mom_t) & bar$paired_vs_mom_t>=0, 4L, 2L)
for(j in seq_len(nrow(bar))){
  text(bar$paired_vs_mom_t[j], bp[j], sprintf("%.2f (oos %.2f)",bar$paired_vs_mom_t[j], bar$oos_ret[j]),
       pos=posv[j], cex=0.62, xpd=NA)
}
dev.off()

# ================= CHART 2: forecasting vs momentum vs static — cumulative active =================
merge_act <- Reduce(function(a,b)merge(a,b,by="date"), list(
  setnames(act(res_static),"active","static"),
  setnames(act(res_mom),"active","momentum"),
  setnames(act(res_gbm),"active","GBM_forecast"),
  setnames(act(res_en),"active","EN_forecast")))
setorder(merge_act,date)
cum <- copy(merge_act); for(c in c("static","momentum","GBM_forecast","EN_forecast")) cum[[c]]<-cumsum(cum[[c]])
png(file.path(SA,"wt006_chart2_equity_forecast_vs_momentum.png"), width=1150, height=680, res=130)
par(mar=c(4,4.5,4,2))
matplot(cum$date, cum[,.(momentum,GBM_forecast,EN_forecast,static)], type="l", lty=1, lwd=c(2.4,2,2,1.5),
  col=c("#1f77b4","#d62728","#ff7f0e","grey55"), xlab="", ylab="cumulative active return (sum)", xaxt="n",
  main="WT-006: exogenous-forecasting vs factor-momentum baseline (OOS 2012-12..2026-06)")
axis(1, at=pretty(cum$date), labels=format(pretty(cum$date),"%Y"))
legend("topleft", c("factor_momentum (baseline)","GBM multi-logic forecast","EN combined forecast","static EW"),
  col=c("#1f77b4","#d62728","#ff7f0e","grey55"), lty=1, lwd=2, bty="n", cex=0.8)
abline(h=0,col="grey80")
dev.off()
cat("charts written to", SA, "\n")

# ---- alpha_scores.parquet: last OOS month per-stock scores (documentary; GBM ensemble) ----
last_dt <- max(oos_dates)
sc_gbm <- score_from_theta(th_gbm)[Date==last_dt]
sc_mom <- score_from_theta(mom_theta)[Date==last_dt]; setnames(sc_mom,"score","score_momentum")
sc_st  <- FAM[Date==last_dt,.(Date,Ticker,score_static=score_ew)]
AS <- merge(sc_gbm[,.(Date,Ticker,score_gbm_forecast=score)], sc_mom[,.(Date,Ticker,score_momentum)], by=c("Date","Ticker"),all=TRUE)
AS <- merge(AS, sc_st, by=c("Date","Ticker"), all=TRUE)
write_parquet(AS, file.path(SA,"alpha_scores.parquet"))
cat("alpha_scores last month", as.character(last_dt), " rows", nrow(AS), "\n")
