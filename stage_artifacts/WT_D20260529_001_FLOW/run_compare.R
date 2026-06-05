# Stage 3 fix: method comparison reusing cached walk-forward results (opt_wf_results.rds)
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
LOCKBOX <- as.Date("2023-12-22")
res <- readRDS(file.path(OUT,"opt_wf_results.rds"))
methods <- names(res)

# BM monthly (need full rawdata BM_Ret)
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd <- rd[Date <= LOCKBOX & !is.na(BM_Ret), .(Date, BM_Ret)]
rd[, ym := format(Date,"%Y-%m")]
bm_m <- unique(rd[, .(Date, BM_Ret, ym)])[, .(bm = prod(1+BM_Ret)-1), by=ym]
setkey(bm_m, ym)

sleeve_stats <- function(dt){
  dt <- merge(dt, bm_m, by="ym", all.x=TRUE); dt <- dt[!is.na(bm)]
  dt[, active := ret_net - bm]; rn<-dt$ret_net; ac<-dt$active
  list(net_sr=mean(rn)/sd(rn)*sqrt(12), ir=mean(ac)/sd(ac)*sqrt(12), te=sd(ac)*sqrt(12),
       ann_ret=prod(1+rn)^(12/length(rn))-1, ann_vol=sd(rn)*sqrt(12),
       ann_to=sum(dt$turnover)/(length(rn)/12), n=length(rn))
}
comp <- rbindlist(lapply(methods, function(m){s<-sleeve_stats(res[[m]]);
  data.table(method=m, net_sr=round(s$net_sr,4), ir=round(s$ir,4), te=round(s$te,4),
             ann_ret=round(s$ann_ret,4), ann_vol=round(s$ann_vol,4),
             ann_to=round(s$ann_to,3), n=s$n)}))
setorder(comp, -ir)
cat("=== SLEEVE-LEVEL METHOD COMPARISON (net-of-cost 15bps, vs KOSPI200) ===\n"); print(comp)
fwrite(comp, file.path(OUT,"method_comparison.csv"))
comp[, to_pass := ann_to <= 6.0]
elig <- comp[to_pass==TRUE]; sel_method <- elig[which.max(ir), method]
cat(sprintf("\n[select] net_ir-max among TO<=6.0/yr: %s (net_sr=%.3f, ir=%.3f, ann_to=%.2f)\n",
    sel_method, comp[method==sel_method,net_sr], comp[method==sel_method,ir], comp[method==sel_method,ann_to]))
# EW baseline comparison (Cycle 2 mandate)
ew_ir <- comp[method=="EW", ir]; sel_ir <- comp[method==sel_method, ir]
cat(sprintf("[EW-baseline] EW net_ir=%.3f vs selected %s net_ir=%.3f -> sizing %s\n",
    ew_ir, sel_method, sel_ir, ifelse(sel_ir>ew_ir+0.02,"IMPROVES over EW","NO material improvement over EW (1/N)")))
saveRDS(list(comp=comp, sel_method=sel_method, res=res, bm_m=bm_m), file.path(OUT,"opt_stage2.rds"))
cat("\n[done compare]\n")
