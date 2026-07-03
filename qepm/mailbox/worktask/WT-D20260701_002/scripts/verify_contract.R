## 검증 Step2 — 계약 official 측정(PerformanceAnalytics) + oos_retention + holdout 사전등록.
suppressPackageStartupMessages({library(data.table); library(PerformanceAnalytics); library(xts)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/contracts/holdout_falsification.R"))
d <- fread(file.path(ROOT,".cache/discovery/verify_overlay_series.csv")); d[, date := as.Date(date)]; setorder(d, date)
xr <- function(col) xts(d[[col]], order.by=d$date)
cat("=== 계약 official 지표 (PerformanceAnalytics 표준함수, metric_type=backtested) ===\n")
cat(sprintf("  %-14s %6s %6s %6s %7s %7s %7s\n","strat","SR","CAGR","Vol","MDD","Calmar","Sortino"))
official <- function(col){
  x <- xr(col); a <- table.AnnualizedReturns(x, scale=12, Rf=0)
  cat(sprintf("  %-14s %6.3f %6.3f %6.3f %7.3f %7.3f %7.3f\n", col,
      as.numeric(a[3,1]), as.numeric(a[1,1]), as.numeric(a[2,1]),
      -as.numeric(maxDrawdown(x)), as.numeric(CalmarRatio(x)), as.numeric(SortinoRatio(x,MAR=0)))) }
invisible(lapply(c("ret_book","ret_faith","ret_combine","ret_tsmom","ret_placebo"), official))

IRf <- function(x){x<-x[is.finite(x)]; if(length(x)<6||sd(x)==0) return(NA_real_); mean(x)/sd(x)*sqrt(12)}
oosr <- function(v){n<-length(v); median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr); if(k<12||(n-k)<6) return(NA_real_); is<-IRf(v[1:k]); oo<-IRf(v[(k+1):n]); if(!is.na(is)&&is>0) oo/is else NA_real_}),na.rm=TRUE)}
cat("\n=== oos_retention (anchored 3-split median; HARD ≥0.7 / band[0.5,0.7)) ===\n")
for(col in c("ret_faith","ret_combine","ret_tsmom")){
  cat(sprintf("  %-12s 전략SR oos_ret=%.2f | (전략−book)diff oos_ret=%.2f\n", col, oosr(d[[col]]), oosr(d[[col]]-d$ret_book))) }
cat("  (전략SR retention = 전략 자체 OOS안정 / diff retention = *개선분* OOS안정 — 후자가 핵심)\n")

cat("\n=== holdout 사전등록 (block bootstrap 예측구간, 봉인) ===\n")
for(col in c("ret_faith","ret_combine")){
  iv <- build_holdout_interval(d[[col]], holdout_months=21L, strategy_id=paste0("paper4_",col))
  cat(sprintf("  %-12s Sharpe 예측구간 [q05=%.2f, q95=%.2f] n=%d sr_input=%.2f\n", col, iv$q05, iv$q95, iv$n_input_months, iv$sr_input))
  save_holdout_interval(iv, file.path(ROOT,".cache/discovery",paste0("holdout_paper4_",col,".json")), overwrite=TRUE)
}
cat("\n판정: official SR 개선 확인 + diff oos_retention≥0.7 + placebo통과 → 검증생존. diff<0.7 or 충실≈tsmom → 약화/generic.\n")
cat("=== done ===\n")
