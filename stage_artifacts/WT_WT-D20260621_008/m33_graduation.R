suppressMessages({library(data.table)})
setDTthreads(1L)
B <- readRDS("/tmp/m33_base.rds")
res <- B$res_base
pr <- res$period_returns   # date, ret_net, benchmark_ret
setorder(pr, date)
active <- pr$ret_net - pr$benchmark_ret
n <- nrow(pr)

# net SR (annualized, monthly)
ann_sr <- function(x) mean(x)/sd(x)*sqrt(12)
full_sr <- ann_sr(active)

# OOS retention v2: anchored 3-split {55/65/75} median of (OOS_SR / IS_SR)
splits <- c(0.55,0.65,0.75)
rets <- c()
for(s in splits){
  k <- floor(n*s)
  is_sr <- ann_sr(active[1:k]); oos_sr <- ann_sr(active[(k+1):n])
  rets <- c(rets, oos_sr/is_sr)
}
oos_ret <- median(rets)

# calmar: net portfolio CAGR / MDD (use net portfolio returns, not active)
netp <- pr$ret_net
cum <- cumprod(1+netp)
cagr <- cum[length(cum)]^(12/n)-1
peak <- cummax(cum); dd <- cum/peak-1; mdd <- abs(min(dd))
calmar <- cagr/mdd

# subperiod stability (3 eras): sign-consistency of active SR
era <- cut(pr$date, breaks=as.Date(c("2005-01-01","2012-01-01","2019-01-01","2027-01-01")),
           labels=c("e1","e2","e3"))
sub <- data.table(active, era)[, .(sr=ann_sr(active)), by=era]
n_pos <- sum(sub$sr>0)
subperiod_stab <- n_pos/3

cat("=== BASE GRADUATION TABLE (metric_type=canonical_screen) ===\n")
cat("PORT_t (NW lag3):", round(res$portfolio_alpha_t_nw_lag3,3)," [HARD>=2.95]\n")
cat("net active SR (full):", round(full_sr,3),"\n")
cat("OOS retention v2 (3-split median):", round(oos_ret,3)," [HARD>=0.7]  splits:",paste(round(rets,2),collapse=","),"\n")
cat("calmar (net port):", round(calmar,3)," [HARD>=0.64]  (CAGR",round(cagr,3),"MDD",round(mdd,3),")\n")
cat("subperiod stability:", round(subperiod_stab,2)," era SRs:",paste(round(sub$sr,2),collapse=","),"\n")
cat("turnover_annual:", round(res$turnover_annual,2),"\n")
cat("\nHARD gates: PORT_t", ifelse(res$portfolio_alpha_t_nw_lag3>=2.95,"PASS","FAIL"),
    "| oos_ret", ifelse(oos_ret>=0.7,"PASS","FAIL"),
    "| calmar", ifelse(calmar>=0.64,"PASS","FAIL"),"\n")
saveRDS(list(oos_ret=oos_ret,calmar=calmar,cagr=cagr,mdd=mdd,full_sr=full_sr,
             subperiod_stab=subperiod_stab,sub=sub), "/tmp/m33_grad.rds")
