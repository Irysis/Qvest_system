## run_dfa_bookmarginal_r16b.R — R16b: 정본 base 재측정 (도훈 정정: AE/noLayer4 가 최신)
## base = 05_Production/2-3.STR_1715_on_M4_R05_noLayer4_PG2 계약 산출물 (net_active_IR_arith 1.416 정확 재현 확인)
suppressPackageStartupMessages({library(data.table)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA); mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
d<-"05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
pr<-fread(file.path(d,"03_period_returns.csv")); bm<-fread(file.path(d,"05_benchmark_returns.csv"))
PG2<-data.table(ym=format(as.Date(pr$date),"%Y-%m"), pg2=pr$ret_net, bmr=bm$benchmark_ret[match(as.Date(pr$date),as.Date(bm$date))])
PG2<-PG2[is.finite(pg2)&is.finite(bmr)]
cat(sprintf("[base 검증] 전구간 net-active IR = %.4f (n=%d) — book_state 선언 1.416\n",IRf(PG2$pg2-PG2$bmr),nrow(PG2)))
R15<-readRDS(".cache/_dfa_pg2ov_r15.rds")
mk<-function(dt,col){ x<-copy(dt); x[,ym:=format(Date,"%Y-%m")]; x[,.(v=prod(1+get(col))-1),by=ym] }
A_base<-mk(R15$DAILY,"Strategy_Ret"); A_ov<-mk(as.data.table(R15$OV),"Ret_overlay")
M<-merge(PG2,A_base[,.(ym,a_base=v)],by="ym"); M<-merge(M,A_ov[,.(ym,a_ov=v)],by="ym"); setorder(M,ym)
base_ir<-IRf(M$pg2-M$bmr)
cat(sprintf("공통창 n=%d (%s~%s) | 동일창 PG2 IR=%.4f\n",nrow(M),M$ym[1],M$ym[nrow(M)],base_ir))
cat(sprintf("[sleeve] A5E IR=%.4f | A5E+오버레이 IR=%.4f | 상관 %.3f / %.3f\n",
  IRf(M$a_base-M$bmr),IRf(M$a_ov-M$bmr),
  cor(M$pg2-M$bmr,M$a_base-M$bmr),cor(M$pg2-M$bmr,M$a_ov-M$bmr)))
cat("\n=== book-marginal ΔIR (window-matched, w=0 control) ===\n")
cat(sprintf("%-6s %-13s %8s %9s %9s\n","w","sleeve","book_IR","dIR","book_SR"))
res<-list()
for(sl in c("a_base","a_ov")) for(w in c(0,0.05,0.10,0.15,0.20,0.30)){
  nb<-(1-w)*M$pg2+w*M[[sl]]; act<-nb-M$bmr; ir<-IRf(act)
  cat(sprintf("%-6.2f %-13s %8.4f %+9.4f %9.3f\n",w,ifelse(sl=="a_base","A5E","A5E+ov"),ir,ir-base_ir,mean(nb)/sd(nb)*sqrt(12)))
  res[[length(res)+1]]<-data.table(sleeve=sl,w=w,book_ir=ir,d_ir=ir-base_ir) }
R<-rbindlist(res); fwrite(R,"outputs/ramp/dfa_bookmarginal_r16b_20260822.csv")
b<-R[w>0&w<=0.20][which.max(d_ir)]
cat(sprintf("\n[판정] 사전등록 grid(<=0.20) 최대 dIR=%+.4f (%s w=%.2f) | 게이트 0.05 -> %s\n",
  b$d_ir,ifelse(b$sleeve=="a_base","A5E","A5E+ov"),b$w,ifelse(b$d_ir>=0.05,"PASS","FAIL")))
cat(sprintf("[진단] w=0.30 확장: A5E %+.4f | A5E+ov %+.4f (사전등록 밖 — 진단 전용)\n",
  R[sleeve=="a_base"&w==0.30]$d_ir, R[sleeve=="a_ov"&w==0.30]$d_ir))
cat("R16B_DONE\n")
