## r8_probe.R — R8 착수 전 de-risk: R7 캐시 PR 구조·parity + noLayer4 bt_result 구조 확인
suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
IRf <- function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt <- function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
oos_ret <- function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}

cat("=== R7 cache load ===\n")
r7 <- readRDS(".cache/_ramp_r7_20260712.rds")
cat("names(r7):", paste(names(r7),collapse=", "), "\n")
cat("names(PR):", paste(names(r7$PR),collapse=", "), "\n")
pr <- r7$PR[["capwrepro_W36_K20"]]
cat("PR[[capwrepro_W36_K20]] cols:", paste(names(pr),collapse=", "), " nrow=", nrow(pr), "\n")
cat("date range:", as.character(min(pr$date)), "~", as.character(max(pr$date)), "\n")
cat(sprintf("EW active (act): PORT_t(nwt)=%.4f IR=%.4f oos=%.4f\n", nwt(pr$act), IRf(pr$act), oos_ret(pr$act)))
cat(sprintf("cap-w active (act_bm): PORT_t=%.4f IR=%.4f oos=%.4f\n", nwt(pr$act_bm), IRf(pr$act_bm), oos_ret(pr$act_bm)))
cat("stored E2 (res$e2$cap_w): capwt=", r7$res$e2$cap_w$port_t_capwt, " EWuni=", r7$res$e2$cap_w$port_t_EWuni,
    " ew_oos=", r7$res$e2$cap_w$ew_oos_retention, " cap-w oos=", r7$res$e2$cap_w$oos_retention, "\n")
# thirds trailing
n <- nrow(pr); thirds <- split(pr$act, cut(seq_len(n),3,labels=FALSE))
cat(sprintf("EW thirds nwt: %s | last-third IRf=%.3f nwt=%.3f\n",
    paste(sprintf("%.2f",sapply(thirds,nwt)),collapse=" / "), IRf(thirds[[3]]), nwt(thirds[[3]])))

cat("\n=== noLayer4 bt_result ===\n")
bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
cat("bt names:", paste(names(bt),collapse=", "), "\n")
pr_b <- as.data.table(bt$period_returns); cat("period_returns cols:", paste(names(pr_b),collapse=", "), " nrow=", nrow(pr_b), "\n")
print(head(pr_b,3))
if(!is.null(bt$benchmark_returns)){ bb<-as.data.table(bt$benchmark_returns); cat("benchmark_returns cols:", paste(names(bb),collapse=", "), " nrow=", nrow(bb), "\n"); print(head(bb,3)) }

cat("\n=== caches exist ===\n")
for(f in c(".cache/_ramp_r6_sel_20260711.rds",".cache/_ramp_r6_20260711.rds","outputs/ramp/r6_factor_deployzone_active.parquet",
           "outputs/ramp/pure_factor_scores.parquet","outputs/ramp/factor_group_scores.parquet",".cache/rawdata.parquet"))
  cat(sprintf("  %s : %s\n", f, file.exists(f)))
cat("PROBE_DONE\n")
