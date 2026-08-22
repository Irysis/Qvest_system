## run_dfa_bookmarginal_r20.R — R20 채택팔 F1(k=5) 의 book-marginal ΔIR
## base = 05_Production/2-3.STR_1715_on_M4_R05_noLayer4_PG2 (도훈 정정: AE/noLayer4 = 최신 book)
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
d<-"05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
pr<-fread(file.path(d,"03_period_returns.csv")); bm<-fread(file.path(d,"05_benchmark_returns.csv"))
PG2<-data.table(ym=format(as.Date(pr$date),"%Y-%m"), pg2=pr$ret_net,
                bmr=bm$benchmark_ret[match(as.Date(pr$date),as.Date(bm$date))])
PG2<-PG2[is.finite(pg2)&is.finite(bmr)]
cat(sprintf("[base] PG2 전구간 net-active IR=%.4f (n=%d, %s~%s) — book_state 선언 1.416\n",
  IRf(PG2$pg2-PG2$bmr),nrow(PG2),PG2$ym[1],PG2$ym[nrow(PG2)]))
Z<-readRDS(".cache/_dfa_r20.rds"); mon<-Z$mon
SL<-data.table(ym=mon$ym, F0=Z$res$F0_control$pr, F1=Z$res$F1_topquintile_k5$pr)
M<-merge(PG2,SL,by="ym"); M<-M[is.finite(F1)&is.finite(F0)]; setorder(M,ym)
base_ir<-IRf(M$pg2-M$bmr)
cat(sprintf("[공통창] n=%d (%s~%s) | 동일창 PG2 IR=%.4f\n",nrow(M),M$ym[1],M$ym[nrow(M)],base_ir))
for(sl in c("F0","F1")) cat(sprintf("[sleeve] %s: IR(vs book벤치)=%+.4f | PG2 active 와 상관=%+.3f\n",
  sl,IRf(M[[sl]]-M$bmr),cor(M$pg2-M$bmr,M[[sl]]-M$bmr)))
cat("\n=== book-marginal ΔIR (사전등록 grid w<=0.20, w=0 통제) ===\n")
cat(sprintf("%-6s %-6s %9s %10s %10s\n","w","sleeve","book_IR","dIR","book_SR"))
res<-list()
for(sl in c("F0","F1")) for(w in c(0,0.05,0.10,0.15,0.20,0.30)){
  nb<-(1-w)*M$pg2+w*M[[sl]]; ir<-IRf(nb-M$bmr)
  cat(sprintf("%-6.2f %-6s %9.4f %+10.4f %10.3f\n",w,sl,ir,ir-base_ir,mean(nb)/sd(nb)*sqrt(12)))
  res[[length(res)+1]]<-data.table(sleeve=sl,w=w,book_ir=ir,d_ir=ir-base_ir) }
R<-rbindlist(res); fwrite(R,"outputs/ramp/dfa_bookmarginal_r20_20260822.csv")
b<-R[sleeve=="F1"&w>0&w<=0.20][which.max(d_ir)]
cat(sprintf("\n[판정] F1 사전등록 grid 최대 ΔIR=%+.4f (w=%.2f) | 게이트 0.05 -> %s\n",
  b$d_ir,b$w,ifelse(b$d_ir>=0.05,"PASS","FAIL")))
cat(sprintf("[대조] F0 최대 ΔIR=%+.4f | R16b A5E 기록 -0.0275\n", R[sleeve=="F0"&w>0&w<=0.20][which.max(d_ir)]$d_ir))
cat("R20_BOOKMARGINAL_DONE\n")
