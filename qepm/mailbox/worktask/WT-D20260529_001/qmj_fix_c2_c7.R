# C2 fix: emit PIT-clean alpha_scores (membership = universe ∩ factor-coverage, NOT forward-return)
# C7 fix: reproducible month-normalized cor_vs_D folded into validation
# C4 (RF-A6) partial: report best-single proxy ICIR vs composite; expand DSR N_trials
# C5 partial: top-quintile liquidity sanity via universe AvgTrdVal_20d
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
ROOT<-"/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/universe_expanded_v2.R")
LOCKBOX<-as.Date("2023-12-22"); OUTDIR<-"stage_artifacts/WT_D20260529_001_QMJ"

AXES<-list(
  Profitability=c("Q01_GPA","Q02_ROE","Q03_ROA","Q35_CashBased_OpProf","Q10_Gross_Margin","Q11_Net_Margin"),
  Safety=c("Q13_Fin_Leverage","Q25_Ohlson_O","Q07_Earnings_Stability","AC18_Accrual_Quality","AC10_Pct_Accruals"),
  Growth=c("GR04_GPA_Growth","GR01_Revenue_Growth","GR02_Earnings_Growth","GR07_Composite_Growth"))
ALL_F<-unlist(AXES,use.names=FALSE)

str1715<-as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
str1715[, Date:=as.Date(Date)]
grid<-sort(unique(str1715$Date)); grid<-grid[grid>=as.Date("2008-01-01") & grid<=LOCKBOX]

# build score panel + per-proxy z (for RF-A2 best-single) + liquidity flag (RF-A5) — NO return merge
build_scores<-function(sig_date){
  u<-tryCatch(build_universe_v2(sig_date,label="KR_top342"),error=function(e)NULL); if(is.null(u)||!nrow(u)) return(NULL)
  liq<-u[,.(Ticker, AvgTrdVal_20d)]
  f<-tryCatch(load_month_factors(sig_date),error=function(e)NULL); if(is.null(f)||!nrow(f)) return(NULL)
  f<-f[Ticker %in% u$Ticker & Factor_Name %in% ALL_F]; if(!nrow(f)) return(NULL)
  w<-dcast(f, Ticker~Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x)mean(x,na.rm=TRUE))
  axs<-function(cols){cols<-intersect(cols,names(w)); if(length(cols)<2) return(rep(NA_real_,nrow(w)))
    m<-as.matrix(w[,..cols]); s<-rowMeans(m,na.rm=TRUE); s[rowSums(!is.na(m))<2]<-NA_real_; s}
  z<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) return(x*0);(x-m)/s}
  w[, prof:=axs(AXES$Profitability)][, safe:=axs(AXES$Safety)][, grow:=axs(AXES$Growth)]
  w[, `:=`(prof_z=z(prof),safe_z=z(safe),grow_z=z(grow))]
  w<-w[!is.na(prof_z)&!is.na(safe_z)&!is.na(grow_z)]; if(!nrow(w)) return(NULL)
  w[, qmj:=(prof_z+safe_z+grow_z)/3][, qmj_z:=z(qmj)]
  # keep per-proxy aligned-z for best-single test
  pres<-intersect(ALL_F,names(w))
  out<-w[, c("Ticker","qmj_z","prof_z","safe_z","grow_z",pres),with=FALSE]
  out<-merge(out, liq, by="Ticker", all.x=TRUE)
  out[, Date:=sig_date]
  out
}
cat("[C2] building PIT-clean score panel (no return conditioning)...\n")
scp<-rbindlist(lapply(seq_along(grid),function(i){d<-grid[i]; if(i%%48==0) cat(" ",as.character(d),"\n"); tryCatch(build_scores(d),error=function(e)NULL)}),fill=TRUE)
cat("[C2] PIT-clean panel rows:",nrow(scp)," dates:",uniqueN(scp$Date)," (vs label-filtered 59995)\n")

# PIT-clean alpha_scores handoff (membership NOT return-conditioned)
alpha_scores<-scp[, .(Date,Ticker,alpha_z=qmj_z,prof_z,safe_z,grow_z,
  confidence=pmin(1,pmax(0,0.5+0.5*scale(qmj_z)[,1]/3)))]
write_parquet(alpha_scores, file.path(OUTDIR,"alpha_scores.parquet"))
cat("[C2] alpha_scores.parquet re-emitted PIT-clean. rows:",nrow(alpha_scores),"\n")

# C4 RF-A2: best-single proxy ICIR vs composite (use label panel for IC — diagnostics only, separate from handoff)
retmap<-str1715[,.(Date,Ticker,Ret_1m)]
dlab<-merge(scp, retmap, by=c("Date","Ticker"))[!is.na(Ret_1m)]
pres<-intersect(ALL_F,names(scp))
single_icir<-sapply(pres, function(fc){
  ic<-dlab[, .(ic=if(.N>=10) cor(get(fc),Ret_1m,method="spearman",use="complete.obs") else NA_real_), by=Date][!is.na(ic)]
  if(nrow(ic)<12) return(NA_real_); mean(ic$ic)/sd(ic$ic)})
single_icir<-sort(single_icir,decreasing=TRUE)
comp_ic<-dlab[, .(ic=if(.N>=10) cor(qmj_z,Ret_1m,method="spearman",use="complete.obs") else NA_real_), by=Date][!is.na(ic)]
comp_icir<-mean(comp_ic$ic)/sd(comp_ic$ic)
best_single_icir<-max(single_icir,na.rm=TRUE)
rf_a2_improve<-(comp_icir-best_single_icir)/abs(best_single_icir)
cat(sprintf("[C4 RF-A2] composite ICIR=%.4f best-single ICIR=%.4f (%s) improve=%.1f%%\n",
  comp_icir,best_single_icir,names(single_icir)[1],100*rf_a2_improve))

# C5 RF-A5: top-quintile liquidity vs 2e8 floor
topliq<-dlab[, {thr<-quantile(qmj_z,0.8,na.rm=TRUE); sel<-qmj_z>=thr
  .(below_2e8=mean(AvgTrdVal_20d[sel]<2e8,na.rm=TRUE), n=sum(sel))}, by=Date]
illiq_frac<-mean(topliq$below_2e8,na.rm=TRUE)
cat(sprintf("[C5 RF-A5] top-quintile fraction below 2e8 KRW = %.1f%% (RF-A5 flags if >50%%)\n",100*illiq_frac))

# C5 RF-A4: sector-neutral IC — universe.parquet sector is NA; use Factor DB built-in only -> document unavailable
# (sector mapping absent in PIT universe; neutralization at axis level not applied. Report transparently.)

# C7: reproducible cor_vs_D month-normalized
dml<-as.data.table(read_parquet("stage_artifacts/WT_D20260528_003_overnight_D_ML/alpha_scores.parquet"))
dml[, Date:=as.Date(Date)]; dml[, Dms:=as.Date(format(Date,"%Y-%m-01"))]
sp<-copy(scp); sp[, Dms:=as.Date(format(Date,"%Y-%m-01"))]
mD<-merge(sp[,.(Dms,Ticker,qmj_z)], dml[,.(Dms,Ticker,dz=alpha_z)], by=c("Dms","Ticker"))[!is.na(qmj_z)&!is.na(dz)]
corD<-mean(mD[, .(c=if(.N>=10) cor(qmj_z,dz,method="spearman") else NA_real_), by=Dms]$c, na.rm=TRUE)
cat(sprintf("[C7] cor_vs_D (reproducible, month-normalized) = %.4f n=%d months=%d\n",corD,nrow(mD),uniqueN(mD$Dms)))

# expanded DSR N_trials (C4 RF-A6): proxies(15)+axes(3)+composite(1)+universe(2)+inclusion(1) ~ 22 effective
N_trials_exp<-22
port<-dlab[, {thr<-quantile(qmj_z,0.8,na.rm=TRUE); sel<-qmj_z>=thr
  .(active=mean(Ret_1m[sel],na.rm=TRUE)-mean(Ret_1m,na.rm=TRUE))}, by=Date][!is.na(active)]
# turnover from PIT-clean panel
topq<-dlab[, {thr<-quantile(qmj_z,0.8,na.rm=TRUE); .(Ticker=Ticker[qmj_z>=thr])}, by=Date]
dts<-sort(unique(topq$Date))
to_m<-mean(sapply(2:length(dts),function(i){a<-topq[Date==dts[i-1]]$Ticker;b<-topq[Date==dts[i]]$Ticker
  if(!length(a)||!length(b)) NA_real_ else length(setdiff(b,a))/length(b)}),na.rm=TRUE)
port[, active_net:=active-to_m*0.0015]
T_n<-nrow(port); sr_obs<-mean(port$active_net)/sd(port$active_net)
sk<-(function(x){m<-mean(x);s<-sd(x);mean((x-m)^3)/s^3})(port$active_net)
ku<-(function(x){m<-mean(x);s<-sd(x);mean((x-m)^4)/s^4})(port$active_net)
emc<-0.5772156649; sr_var<-1/sqrt(T_n); zz<-qnorm(1-1/N_trials_exp); z2<-qnorm(1-1/(N_trials_exp*exp(1)))
sr0<-sr_var*((1-emc)*zz+emc*z2)
dsr_exp<-pnorm((sr_obs-sr0)/sqrt((1-sk*sr_obs+(ku-1)/4*sr_obs^2)/(T_n-1)))
cat(sprintf("[C4 RF-A6] DSR with N_trials=%d (expanded) = %.4f (was 0.358 at N=4)\n",N_trials_exp,dsr_exp))

# patch validation json
v<-fromJSON(file.path(OUTDIR,"alpha_validation.json"),simplifyVector=FALSE)
v$codex_round1_remediation<-list(
  C2_pit_clean_alpha_scores=list(fixed=TRUE, pit_clean_rows=nrow(alpha_scores),
    note="alpha_scores.parquet re-emitted with membership = universe ∩ factor-coverage. NO forward-return (!is.na(Ret_1m)) conditioning. IC/portfolio diagnostics use a SEPARATE label-merged frame, never the handoff."),
  C4_rf_a2_best_single=list(composite_icir=round(comp_icir,4), best_single_icir=round(best_single_icir,4),
    best_single_proxy=names(single_icir)[1], improve_pct=round(100*rf_a2_improve,1),
    rf_a2_cleared=(rf_a2_improve>0.05)),
  C4_rf_a6_dsr_expanded=list(N_trials=N_trials_exp, dsr=round(dsr_exp,4), still_fail=(dsr_exp<0.5)),
  C5_rf_a5_liquidity=list(top_quintile_below_2e8_frac=round(illiq_frac,4), rf_a5_cleared=(illiq_frac<0.5)),
  C5_rf_a4_sector_neutral=list(status="UNAVAILABLE",
    note="PIT universe.parquet Sector column is NA across panel (verified). Sector-neutral IC not computable from available KR PIT data without external sector map. Reported transparently per answer-principles (no fabrication)."),
  C7_cor_vs_D_reproducible=list(value=round(corD,4), n=nrow(mD), months=uniqueN(mD$Dms),
    method="D month-end -> month-start normalization, per-date spearman avg. Folded into this script (reproducible)."))
v$orthogonality$cor_vs_D_ML_alpha_z<-round(corD,4)
v$orthogonality$pass_D<-(abs(corD)<0.30)
write_json(v, file.path(OUTDIR,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("[done] validation patched.\n")
EOF
