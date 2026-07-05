ec<-readRDS("_wt_eval_canonical.rds");ea<-readRDS("_wt_eval_allliq.rds")
cat("canon keys:",paste(names(ec),collapse="|"),"\n")
r<-ec[["ENSEMBLE"]]
if(!is.null(r)) cat(sprintf("CANON ENS port_t=%.2f IR=%.2f netSR=%.2f 2022+=%.2f pre18=%.2f post18=%.2f oos=%.2f calmar=%.2f MDD=%.1f turn=%.0f CAGR=%.1f\n",
  r$port_t,r$IR,r$net_sr,r$t_2022,r$t_pre18,r$t_post18,r$oos_ret,r$calmar,100*r$mdd,100*r$turnover,100*r$cagr))
r2<-ea[["ENSEMBLE"]]
if(!is.null(r2)) cat(sprintf("ALLLIQ ENS port_t=%.2f IR=%.2f netSR=%.2f 2022+=%.2f pre18=%.2f post18=%.2f oos=%.2f calmar=%.2f MDD=%.1f turn=%.0f CAGR=%.1f\n",
  r2$port_t,r2$IR,r2$net_sr,r2$t_2022,r2$t_pre18,r2$t_post18,r2$oos_ret,r2$calmar,100*r2$mdd,100*r2$turnover,100*r2$cagr))
