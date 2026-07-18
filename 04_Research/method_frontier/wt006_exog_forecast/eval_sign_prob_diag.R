setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
library(arrow); library(data.table)
# use ensemble probs (recover from direct theta is lossy) -> reload per-seed prob via theta? we only saved theta.
# Diagnostic: sharpen the *direct theta* (which is ∝ p) with softmax on standardized log-theta = monotone in p.
th <- as.data.table(read_parquet("04_Research/method_frontier/wt006_exog_forecast/theta_R2_sign_prob.parquet"))
th[,date:=as.Date(date)]
sharp <- th[, {z<-(theta-mean(theta))/(sd(theta)+1e-12); w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]
m <- eval_theta(sharp, "sign_prob_sharp")
cat("\n==== sign_prob SHARPENED (exp(2z) on prob-ranking, diagnostic only) ====\n")
cat(sprintf("port_t=%.3f ew_uni_t=%.3f oos_ret=%.3f paired_vs_mom_t=%.3f lag1=%.3f turnover=%.2f\n",
    m$port_t, m$ew_uni_t, m$oos_ret, m$paired_vs_mom_t, m$lag1_port_t, m$turnover))
