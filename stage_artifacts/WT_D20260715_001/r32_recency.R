## R32 supplement: full table + recency(2024+) active decomposition + OOS retention +
##   beta-vs-alpha attribution of the risk-axis improvement. READ frozen arm_series.
suppressPackageStartupMessages({library(arrow);library(data.table);library(sandwich);library(lmtest)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT<-file.path(QM,"stage_artifacts/WT_D20260715_001")
res<-readRDS(file.path(WT,"arm_series.rds"))
TAB<-as.data.table(read_parquet(file.path(WT,"comparison_table.parquet")))
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
IR_ann<-function(v){v<-v[is.finite(v)];if(length(v)<6)return(NA_real_);s<-sd(v);mean(v)/s*sqrt(12)}
oos3<-function(a,frac=c(0.55,0.65,0.75)){a<-a[is.finite(a)];n<-length(a);if(n<24)return(NA_real_)
  sr<-function(x){if(length(x)<6)return(NA_real_);s<-sd(x);if(!is.finite(s)||s<=0)return(NA_real_);mean(x)/s*sqrt(12)}
  r<-sapply(frac,function(f){k<-floor(n*f);is<-sr(a[1:k]);oo<-sr(a[(k+1):n]);if(is.na(is)||is<=0)return(NA_real_);oo/is})
  if(all(is.na(r)))NA_real_ else median(r,na.rm=TRUE)}

cat("===== FULL 3-ARM TABLE (overlay applied + pre) =====\n")
print(TAB[,lapply(.SD,function(x) if(is.numeric(x))round(x,4) else x)])

arms<-list(arm0=as.data.table(res$A0),arm1=as.data.table(res$A1),arm2=as.data.table(res$A2))
labs<-c(arm0="baseline",arm1="B2_value",arm2="Z6_value")
cat("\n===== ACTIVE RETURN by ERA (overlay applied, vs cap-w bench) =====\n")
rows<-list()
for(nm in names(arms)){m<-arms[[nm]][order(date)]
  full<-m$active_ovl; pre<-m[date<as.Date("2024-01-01")]$active_ovl; post<-m[date>=as.Date("2024-01-01")]$active_ovl
  rows[[nm]]<-data.table(arm=labs[nm],
    full_t=nw_t(full), full_IR=IR_ann(full), full_mean_bps=mean(full)*1e4,
    pre2024_t=nw_t(pre), pre2024_mean_bps=mean(pre)*1e4,
    post2024_t=nw_t(post), post2024_mean_bps=mean(post)*1e4, n_post=length(post),
    oos_ret_v2=oos3(full))}
ERA<-rbindlist(rows); print(ERA[,lapply(.SD,function(x) if(is.numeric(x))round(x,3) else x)])

cat("\n===== VALUE MARGINAL by ERA (arm - arm0, overlay active differential) =====\n")
mrg<-list()
for(nm in c("arm1","arm2")){
  m<-merge(arms[[nm]][,.(date,va=active_ovl)],arms$arm0[,.(date,ba=active_ovl)],by="date")[order(date)]
  d<-m$va-m$ba; pre<-m[date<as.Date("2024-01-01")];post<-m[date>=as.Date("2024-01-01")]
  mrg[[nm]]<-data.table(arm=labs[nm],
    full_paired_t=nw_t(d), full_dmean_bps=mean(d)*1e4,
    pre2024_paired_t=nw_t(pre$va-pre$ba), pre2024_dbps=mean(pre$va-pre$ba)*1e4,
    post2024_paired_t=nw_t(post$va-post$ba), post2024_dbps=mean(post$va-post$ba)*1e4,
    dIR_full=IR_ann(m$va)-IR_ann(m$ba))}
VM<-rbindlist(mrg); print(VM[,lapply(.SD,function(x) if(is.numeric(x))round(x,3) else x)])

cat("\n===== RISK-AXIS ATTRIBUTION: is Calmar/MDD gain from beta-reduction or alpha? =====\n")
## beta drop (pre-overlay) + downside capture
tb<-TAB[overlay=="applied"]
for(i in 1:nrow(tb)) cat(sprintf("  %s: beta=%.3f MDD=%.3f Calmar=%.3f CAGR=%.3f AnnVol=%.3f SR=%.3f\n",
  tb$arm[i],tb$beta[i],tb$MDD[i],tb$Calmar[i],tb$CAGR[i],tb$AnnVol[i],tb$SR_geo[i]))
## bear-month capture (benchmark<0): mean arm return in down-market months
bm<-arms$arm0[,.(date,benchmark_ret)]
for(nm in names(arms)){m<-merge(arms[[nm]][,.(date,ret_ovl)],bm,by="date")
  dn<-m[benchmark_ret< -0.03]; up<-m[benchmark_ret> 0.03]
  cat(sprintf("  %s: down-mkt(<-3%%) mean=%.4f (n=%d) | up-mkt(>3%%) mean=%.4f (n=%d) | down-capture vs bench=%.3f\n",
    labs[nm], mean(dn$ret_ovl), nrow(dn), mean(up$ret_ovl), nrow(up), mean(dn$ret_ovl)/mean(dn$benchmark_ret)))}

save_safe<-function(o,p,w){tmp<-paste0(p,".tmp_",Sys.getpid());w(o,tmp);if(file.exists(p))file.remove(p);file.rename(tmp,p)}
save_safe(ERA,file.path(WT,"era_active.parquet"),write_parquet)
save_safe(VM,file.path(WT,"value_marginal_era.parquet"),write_parquet)
cat("\nR32_RECENCY_DONE\n")
