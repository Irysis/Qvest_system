suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
r <- readRDS("stage_artifacts/WT_D20260802_015/wt015_results.rds")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12L) return(NA_real_)
  fit<-lm(x~1); tryCatch(as.numeric(lmtest::coeftest(fit, vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3]), error=function(e) NA_real_)}
mode_dt <- data.table(date = as.Date(rownames(r$rot_tuned$W)), mode = r$rot_tuned$mode)
for (nm in c("rerun_tunedRot_vs_baseRot","value_tunedRot_vs_ewStatic")) {
  d <- as.data.table(r$paired[[nm]]$d_series)
  d <- merge(d, mode_dt, by="date")
  dc <- d[mode=="COND"]
  cat(sprintf("%s COND-only: n=%d t=%+.2f mean_d_ann=%+.2f%%\n", nm, nrow(dc), nw_t(dc$d), 100*mean(dc$d)*12))
}
# 국면 전환월(라벨이 전월과 다른 달)만 — 로테이션이 실제로 '움직인' 달
rs <- r$rot_tuned$r_sig; switch_m <- c(FALSE, rs[-1]!=rs[-length(rs)])
sw_dt <- data.table(date=as.Date(rownames(r$rot_tuned$W)), sw=switch_m)
d <- merge(as.data.table(r$paired$value_tunedRot_vs_ewStatic$d_series), sw_dt, by="date")
cat(sprintf("전환월(라벨 변경) rotation-vs-EW: n=%d t=%+.2f | 비전환월 n=%d t=%+.2f\n",
  nrow(d[sw==TRUE]), nw_t(d[sw==TRUE]$d), nrow(d[sw==FALSE]), nw_t(d[sw==FALSE]$d)))
