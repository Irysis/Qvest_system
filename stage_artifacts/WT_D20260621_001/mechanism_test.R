Sys.setenv(R_DATATABLE_NUM_THREADS="1"); suppressMessages(library(data.table)); setDTthreads(1L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A<-file.path(ROOT,"stage_artifacts/WT_D20260621_001")
p<-readRDS(file.path(OUT_A,"panel_fixed.rds"))
LOG<-function(...) cat(...,"\n")
# Direct mechanism test: is momentum's IC stronger in HIGH-H names than LOW-H names?
# Split each month into H-terciles, measure rank-IC(M01, fwd ret) within each.
d<-p[is.finite(H252)&is.finite(M01)&is.finite(Ret_1m)]
d[, H_tercile := cut(H252, breaks=quantile(H252,c(0,1/3,2/3,1),na.rm=TRUE),
                     labels=c("low_H","mid_H","high_H"), include.lowest=TRUE), by=Date]
ic_by<-d[, .(ic=if(.N>=8) cor(M01,Ret_1m,method="spearman") else NA_real_), by=.(Date,H_tercile)]
res<-ic_by[is.finite(ic), .(mean_ic=mean(ic), sd_ic=sd(ic), n=.N, t=mean(ic)/sd(ic)*sqrt(.N)), by=H_tercile]
cat("\n=== Momentum rank-IC conditional on Hurst tercile (THE mechanism test) ===\n")
print(res[order(H_tercile)])
cat("\nThesis predicts: high_H IC >> low_H IC (momentum reliable when persistent).\n")

# Momentum CRASH test: in anti-persistent (low-H) names, does momentum reverse harder in down markets?
# Daniel-Moskowitz: momentum crashes in rebounds. Check momentum's worst months conditional on prior-H.
# Simple proxy: avg fwd return of TOP-momentum quintile within low-H vs high-H.
d[, mom_q := cut(M01, breaks=quantile(M01,c(0,.8,1),na.rm=TRUE), labels=c("rest","top"), include.lowest=TRUE), by=Date]
crash<-d[mom_q=="top", .(mean_fwd=mean(Ret_1m), min_fwd=min(Ret_1m), q05=quantile(Ret_1m,.05)), by=H_tercile]
cat("\n=== Top-momentum-quintile forward return by H-tercile (crash check) ===\n")
print(crash[order(H_tercile)])
