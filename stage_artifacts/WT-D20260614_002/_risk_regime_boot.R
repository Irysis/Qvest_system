# RF-R8 fix: bootstrap CI for per-regime mean-pair-corr (CRISIS n=46, CAUTION n=44 < thresholds)
# + pooled-fallback note. PIT-safe expanding regime labels (from _risk_regime_pit.R).
suppressMessages({ library(data.table); library(arrow) })
source("02_Infrastructure/config.R")
OUT<-"stage_artifacts/WT-D20260614_002"
panel<-as.data.table(read_parquet(file.path(OUT,"_factor_return_panel.parquet"))); setorder(panel,ym)
STYLE<-c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
         "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
bm<-as.data.table(read_parquet(".cache/benchmark.parquet"))[,.(Date=as.Date(Date),BM_Ret)]; bm[,ym:=format(Date,"%Y%m")]
bmm<-bm[,.(bm_ret=prod(1+BM_Ret,na.rm=TRUE)-1),by=ym]
P<-merge(panel,bmm,by="ym"); setorder(P,ym)
n<-nrow(P); reg<-rep(NA_character_,n); MINW<-36L
for(t in seq_len(n)){ if(t<=MINW){reg[t]<-"WARMUP";next}
  q<-quantile(P$bm_ret[1:(t-1)],c(0.20,0.40,0.80),na.rm=TRUE); x<-P$bm_ret[t]
  reg[t]<-if(x<=q[1])"CRISIS" else if(x<=q[2])"CAUTION" else if(x>=q[3])"BULL" else "NORMAL" }
P[,regime:=reg]; Pv<-P[regime!="WARMUP"]

meanpair<-function(M){M<-M[,colSums(is.finite(M))>5,drop=FALSE]
  C<-suppressWarnings(cor(M,use="pairwise.complete.obs")); mean(C[upper.tri(C)],na.rm=TRUE)}
set.seed(42); B<-2000L
boot_ci<-function(sub){ if(nrow(sub)<6) return(c(NA,NA,NA))
  M<-as.matrix(sub[,..STYLE]); est<-meanpair(M)
  bs<-replicate(B,{ idx<-sample(nrow(sub),replace=TRUE); meanpair(as.matrix(sub[idx,..STYLE])) })
  c(est, quantile(bs,0.05,na.rm=TRUE), quantile(bs,0.95,na.rm=TRUE)) }
res<-rbindlist(lapply(c("CRISIS","CAUTION","NORMAL","BULL"), function(rg){
  sub<-Pv[regime==rg]; ci<-boot_ci(sub)
  data.table(regime=rg, n_months=nrow(sub),
    mean_pair_corr=round(ci[1],4), boot_ci05=round(ci[2],4), boot_ci95=round(ci[3],4),
    bootstrap_required=nrow(sub)<50, small_sample=nrow(sub)<30)
}))
# pooled fallback: if CRISIS/CAUTION CI very wide, optimizer should pool CRISIS+CAUTION (stress pool)
stress_pool<-Pv[regime %in% c("CRISIS","CAUTION")]; sp_ci<-boot_ci(stress_pool)
pooled<-data.table(regime="STRESS_POOL(CRISIS+CAUTION)", n_months=nrow(stress_pool),
  mean_pair_corr=round(sp_ci[1],4), boot_ci05=round(sp_ci[2],4), boot_ci95=round(sp_ci[3],4),
  bootstrap_required=FALSE, small_sample=FALSE)
res<-rbind(res,pooled)
saveRDS(res, file.path(OUT,"_risk_regime_boot.rds"))
print(res)
cat("[regime-boot] CRISIS n=46<50 -> bootstrap CI provided; STRESS_POOL fallback (n=90) for optimizer if CI too wide.\n")
