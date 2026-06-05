# Resume: load saved KR_top342 panel, run diagnostics + v2 comparison
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/universe_expanded_v2.R")
LOCKBOX <- as.Date("2023-12-22")
OUTDIR  <- "stage_artifacts/WT_D20260529_001_QMJ"

AXES <- list(
  Profitability = c("Q01_GPA","Q02_ROE","Q03_ROA","Q35_CashBased_OpProf","Q10_Gross_Margin","Q11_Net_Margin"),
  Safety        = c("Q13_Fin_Leverage","Q25_Ohlson_O","Q07_Earnings_Stability","AC18_Accrual_Quality","AC10_Pct_Accruals"),
  Growth        = c("GR04_GPA_Growth","GR01_Revenue_Growth","GR02_Earnings_Growth","GR07_Composite_Growth"))
ALL_F <- unlist(AXES, use.names=FALSE)

panel <- readRDS(file.path(OUTDIR,"qmj_panel.rds"))
cat("[load] panel rows:", nrow(panel), " dates:", uniqueN(panel$Date), " with-ret:", sum(!is.na(panel$Ret_1m)),"\n")
# panel already has Ret_1m merged + NA dropped from build step (with returns: 59995)
panel <- panel[!is.na(Ret_1m)]

nw_t <- function(x, lag=3){ x<-x[!is.na(x)]; n<-length(x); mu<-mean(x); e<-x-mu
  g0<-sum(e^2)/n; s<-g0; for(l in 1:lag){w<-1-l/(lag+1); g<-sum(e[(l+1):n]*e[1:(n-l)])/n; s<-s+2*w*g}; mu/sqrt(s/n)}

ic_dt <- panel[, .(ic=if(.N>=10) cor(qmj_z,Ret_1m,method="spearman",use="complete.obs") else NA_real_, n=.N), by=Date][!is.na(ic)]
rank_ic<-mean(ic_dt$ic); icir<-rank_ic/sd(ic_dt$ic); nm<-nrow(ic_dt); harvey_t<-nw_t(ic_dt$ic,3)

sp<-function(d0,d1){x<-ic_dt[Date>=d0&Date<=d1]$ic; if(length(x)<6) NA else mean(x)}
sp1<-sp(as.Date("2008-01-01"),as.Date("2014-12-31")); sp2<-sp(as.Date("2015-01-01"),as.Date("2019-12-31")); sp3<-sp(as.Date("2020-01-01"),LOCKBOX)
sp_vals<-c(sp1,sp2,sp3)
subperiod_stability<-mean(sign(sp_vals)==sign(rank_ic) & abs(sp_vals)>=0.5*abs(rank_ic), na.rm=TRUE)

mono_dt<-panel[, {q<-cut(frank(qmj_z,ties.method="first"),5,labels=FALSE); .(q=q,r=Ret_1m)}, by=Date]
quint<-mono_dt[, .(mr=mean(r,na.rm=TRUE)), by=q][order(q)]
monotonicity<-cor(quint$q,quint$mr,method="spearman")

topq<-panel[, {thr<-quantile(qmj_z,0.8,na.rm=TRUE); .(Ticker=Ticker[qmj_z>=thr])}, by=Date]
dts<-sort(unique(topq$Date))
to_vec<-sapply(2:length(dts), function(i){a<-topq[Date==dts[i-1]]$Ticker; b<-topq[Date==dts[i]]$Ticker
  if(!length(a)||!length(b)) return(NA_real_); length(setdiff(b,a))/length(b)})
turnover_proxy_monthly<-mean(to_vec,na.rm=TRUE); turnover_annual<-turnover_proxy_monthly*12

port<-panel[, {thr<-quantile(qmj_z,0.8,na.rm=TRUE); sel<-qmj_z>=thr
  .(active=mean(Ret_1m[sel],na.rm=TRUE)-mean(Ret_1m,na.rm=TRUE), uni_ret=mean(Ret_1m,na.rm=TRUE), nsel=sum(sel))}, by=Date][!is.na(active)]
cost_monthly<-turnover_proxy_monthly*0.0015
port[, active_net := active-cost_monthly]
port_alpha_t_gross<-nw_t(port$active,3); port_alpha_t_net<-nw_t(port$active_net,3)
mean_active_net<-mean(port$active_net)
sr_net<-mean(port$active_net)/sd(port$active_net)*sqrt(12); sr_gross<-mean(port$active)/sd(port$active)*sqrt(12)

# DSR
N_trials<-4; T_n<-nrow(port); sr_obs<-mean(port$active_net)/sd(port$active_net)
sk<-(function(x){m<-mean(x);s<-sd(x);mean((x-m)^3)/s^3})(port$active_net)
ku<-(function(x){m<-mean(x);s<-sd(x);mean((x-m)^4)/s^4})(port$active_net)
emc<-0.5772156649; sr_var<-1/sqrt(T_n); z<-qnorm(1-1/N_trials); z2<-qnorm(1-1/(N_trials*exp(1)))
sr0<-sr_var*((1-emc)*z+emc*z2)
dsr_den<-sqrt((1-sk*sr_obs+(ku-1)/4*sr_obs^2)/(T_n-1))
dsr<-pnorm((sr_obs-sr0)/dsr_den)

# AX-001 v2
mret<-merge(ic_dt, port[,.(Date,uni_ret)], by="Date")
thr_bad<-quantile(mret$uni_ret,0.15,na.rm=TRUE)
ic_bad<-mean(mret[uni_ret<=thr_bad]$ic,na.rm=TRUE); ic_norm<-mean(mret[uni_ret>thr_bad]$ic,na.rm=TRUE)
ax001_ratio<-ic_bad/ic_norm
crisis_active_net<-mean(port[uni_ret<=thr_bad]$active_net,na.rm=TRUE)

# Orthogonality
str1715<-as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
str1715[, Date:=as.Date(Date)]
m15<-merge(panel[,.(Date,Ticker,qmj_z)], str1715[,.(Date,Ticker,s15=score_eff)], by=c("Date","Ticker"))[!is.na(qmj_z)&!is.na(s15)]
cor_vs_1715<-mean(m15[, .(c=if(.N>=10) cor(qmj_z,s15,method="spearman") else NA_real_), by=Date]$c, na.rm=TRUE)
dml<-as.data.table(read_parquet("stage_artifacts/WT_D20260528_003_overnight_D_ML/alpha_scores.parquet")); dml[, Date:=as.Date(Date)]
mD<-merge(panel[,.(Date,Ticker,qmj_z)], dml[,.(Date,Ticker,dz=alpha_z)], by=c("Date","Ticker"))[!is.na(qmj_z)&!is.na(dz)]
cor_vs_D<-mean(mD[, .(c=if(.N>=10) cor(qmj_z,dz,method="spearman") else NA_real_), by=Date]$c, na.rm=TRUE)

# axis-level IC (factor zoo validation — show each axis carries signal)
axis_ic<-function(col) mean(panel[, .(ic=if(.N>=10) cor(get(col),Ret_1m,method="spearman",use="complete.obs") else NA_real_), by=Date]$ic, na.rm=TRUE)
ic_prof<-axis_ic("prof_z"); ic_safe<-axis_ic("safe_z"); ic_grow<-axis_ic("grow_z")

# ---- v2 FREEFLOAT comparison ----
compute_qmj<-function(sig_date, universe_label){
  u<-tryCatch(build_universe_v2(sig_date,label=universe_label),error=function(e)NULL); if(is.null(u)||!nrow(u)) return(NULL)
  uni<-u$Ticker
  f<-tryCatch(load_month_factors(sig_date),error=function(e)NULL); if(is.null(f)||!nrow(f)) return(NULL)
  f<-f[Ticker %in% uni & Factor_Name %in% ALL_F]; if(!nrow(f)) return(NULL)
  w<-dcast(f, Ticker~Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x)mean(x,na.rm=TRUE))
  axs<-function(cols){cols<-intersect(cols,names(w)); if(length(cols)<2) return(rep(NA_real_,nrow(w)))
    m<-as.matrix(w[,..cols]); s<-rowMeans(m,na.rm=TRUE); s[rowSums(!is.na(m))<2]<-NA_real_; s}
  w[, prof:=axs(AXES$Profitability)][, safe:=axs(AXES$Safety)][, grow:=axs(AXES$Growth)]
  zstd<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) return(x*0);(x-m)/s}
  w[, `:=`(prof_z=zstd(prof),safe_z=zstd(safe),grow_z=zstd(grow))]
  w<-w[!is.na(prof_z)&!is.na(safe_z)&!is.na(grow_z)]; if(!nrow(w)) return(NULL)
  w[, qmj:=(prof_z+safe_z+grow_z)/3]; w[, qmj_z:=zstd(qmj)]
  data.table(Date=sig_date, Ticker=w$Ticker, qmj_z=w$qmj_z)
}
retmap<-str1715[, .(Date,Ticker,Ret_1m)]; setkey(retmap,Date,Ticker)
grid<-sort(unique(panel$Date))
cat("[v2] building FREEFLOAT...\n")
pv<-rbindlist(lapply(seq_along(grid), function(i){d<-grid[i]; if(i%%48==0) cat(" v2",as.character(d),"\n"); tryCatch(compute_qmj(d,"KR_TOP500_FREEFLOAT"),error=function(e)NULL)}),fill=TRUE)
pv<-merge(pv,retmap,by=c("Date","Ticker"),all.x=TRUE)[!is.na(Ret_1m)]
ic2<-pv[, .(ic=if(.N>=10) cor(qmj_z,Ret_1m,method="spearman",use="complete.obs") else NA_real_), by=Date][!is.na(ic)]
rank_ic_v2<-mean(ic2$ic); icir_v2<-rank_ic_v2/sd(ic2$ic); harvey_t_v2<-nw_t(ic2$ic,3)

# ---- OUTPUT ----
diag<-list(n_months=nm, rank_ic=round(rank_ic,4), icir=round(icir,4),
  harvey_t_rank_ic=round(harvey_t,4), harvey_t_method="Newey-West lag=3 on monthly rank-IC series",
  portfolio_alpha_t_gross=round(port_alpha_t_gross,4), portfolio_alpha_t_net=round(port_alpha_t_net,4),
  portfolio_alpha_t_note="DISTINCT from rank-IC t. NW lag=3 on top-quintile EW net active monthly series.",
  monotonicity=round(monotonicity,4), subperiod_stability=round(subperiod_stability,4),
  subperiod_ic=list(p2008_14=round(sp1,4),p2015_19=round(sp2,4),p2020_lockbox=round(sp3,4)),
  axis_ic=list(profitability=round(ic_prof,4),safety=round(ic_safe,4),growth=round(ic_grow,4)),
  turnover_proxy_monthly=round(turnover_proxy_monthly,4), turnover_annual=round(turnover_annual,4),
  sr_net_of_cost_annual=round(sr_net,4), sr_gross_annual=round(sr_gross,4),
  mean_active_net_monthly=round(mean_active_net,5), dsr=round(dsr,4), dsr_N_trials=N_trials,
  ax001_v2=list(ic_bad=round(ic_bad,4),ic_normal=round(ic_norm,4),bad_normal_ratio=round(ax001_ratio,4),crisis_active_net_monthly=round(crisis_active_net,5)),
  quintile_returns=setNames(round(quint$mr,5),paste0("Q",quint$q)))
ortho<-list(cor_vs_STR_1715_score_eff=round(cor_vs_1715,4), cor_vs_D_ML_alpha_z=round(cor_vs_D,4),
  n_overlap_1715=nrow(m15), n_overlap_D=nrow(mD), threshold=0.30,
  pass_1715=abs(cor_vs_1715)<0.30, pass_D=abs(cor_vs_D)<0.30)
univ_cmp<-list(KR_top342=list(rank_ic=round(rank_ic,4),icir=round(icir,4),harvey_t=round(harvey_t,4),n=nm),
  KR_TOP500_FREEFLOAT=list(rank_ic=round(rank_ic_v2,4),icir=round(icir_v2,4),harvey_t=round(harvey_t_v2,4),n=nrow(ic2)))
validation<-list(task_id="WT-D20260529_001",track="QMJ",as_of_date="2026-05-29",lockbox=as.character(LOCKBOX),
  universe_default="KR_top342",cost_model="v2.3_kr_retail_15bps",diagnostics=diag,orthogonality=ortho,
  universe_comparison=univ_cmp,
  ax004_exclusion=list(structure="multi-axis quality composite",axes=names(AXES),n_factors=length(ALL_F),
    profitability=AXES$Profitability,safety=AXES$Safety,growth=AXES$Growth,single_signal_avoided=TRUE,
    note="AFP 2019 QMJ 3-axis. require >=2 proxies/axis AND all 3 axes present per name. NOT single GP/profitability."))
write_json(validation, file.path(OUTDIR,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

alpha_scores<-panel[, .(Date,Ticker,alpha_z=qmj_z,prof_z,safe_z,grow_z,
  confidence=pmin(1,pmax(0,0.5+0.5*scale(qmj_z)[,1]/3)))]
write_parquet(alpha_scores, file.path(OUTDIR,"alpha_scores.parquet"))

cat("\n================ SUMMARY ================\n")
cat(sprintf("rank_IC=%.4f ICIR=%.4f harvey_t(IC)=%.2f port_alpha_t_net=%.2f (gross %.2f)\n",rank_ic,icir,harvey_t,port_alpha_t_net,port_alpha_t_gross))
cat(sprintf("SR_net=%.3f SR_gross=%.3f DSR=%.3f mono=%.3f subperiod=%.2f n=%d\n",sr_net,sr_gross,dsr,monotonicity,subperiod_stability,nm))
cat(sprintf("subperiod IC: 08-14=%.4f 15-19=%.4f 20-LB=%.4f\n",sp1,sp2,sp3))
cat(sprintf("axis IC: prof=%.4f safe=%.4f grow=%.4f\n",ic_prof,ic_safe,ic_grow))
cat(sprintf("TO_ann=%.2f AX001_v2 ratio=%.3f (bad=%.4f norm=%.4f) crisis_net=%.5f\n",turnover_annual,ax001_ratio,ic_bad,ic_norm,crisis_active_net))
cat(sprintf("cor_vs_1715=%.4f (n=%d) cor_vs_D=%.4f (n=%d) thr=0.30\n",cor_vs_1715,nrow(m15),cor_vs_D,nrow(mD)))
cat(sprintf("v2 FREEFLOAT: rank_IC=%.4f ICIR=%.4f harvey_t=%.2f n=%d\n",rank_ic_v2,icir_v2,harvey_t_v2,nrow(ic2)))
cat("=========================================\n")
