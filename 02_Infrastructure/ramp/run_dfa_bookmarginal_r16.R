## run_dfa_bookmarginal_r16.R — R16: A5E(±PG2오버레이) book-marginal ΔIR (FQ-239)
## base = 05_Production PG2 정본(ret_L5_V5, MDD -0.2329로 book_state 기록과 일치 식별)
## ★기록: book_state 선언 incumbent_book_ir=1.416 은 현행 production 산출에서 재현 불가(실측 0.75~1.01)
##   → base 는 재현 가능한 실측값으로 두고, ΔIR 은 동일창 w=0 control 대비 증분으로 판정(규약 window-matched)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA); mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## PG2 정본
b<-readRDS("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds")
pr<-as.data.table(b$period_returns)
bm<-as.data.table(read_parquet(".cache/benchmark.parquet")); bm[,Date:=as.Date(Date)]; bm[,ym:=format(Date,"%Y-%m")]
BM<-bm[is.finite(BM_Ret),.(bmr=prod(1+BM_Ret)-1),by=ym]
PG2<-merge(pr[,.(ym=realized_ym, pg2=ret_L5_V5)],BM,by="ym"); setorder(PG2,ym)

## A5E (오버레이 전/후) 월별
R15<-readRDS(".cache/_dfa_pg2ov_r15.rds")
mk<-function(dt,col){ x<-copy(dt); x[,ym:=format(Date,"%Y-%m")]; x[,.(v=prod(1+get(col))-1),by=ym] }
A_base<-mk(R15$DAILY,"Strategy_Ret"); A_ov<-mk(as.data.table(R15$OV),"Ret_overlay")

M<-merge(PG2, A_base[,.(ym,a_base=v)], by="ym")
M<-merge(M, A_ov[,.(ym,a_ov=v)], by="ym"); setorder(M,ym)
cat("공통창: n=",nrow(M)," ",M$ym[1],"~",M$ym[nrow(M)],"\n",sep="")
cat(sprintf("[base 실측] PG2 net-active IR(동일창) = %.4f  ★book_state 선언 1.416 재현 불가\n",
  IRf(M$pg2-M$bmr)))
cat(sprintf("[sleeve 단독] A5E IR=%.4f | A5E+오버레이 IR=%.4f\n",IRf(M$a_base-M$bmr),IRf(M$a_ov-M$bmr)))
cat(sprintf("[상관] PG2 active vs A5E active = %.3f | vs A5E+ov = %.3f\n",
  cor(M$pg2-M$bmr,M$a_base-M$bmr), cor(M$pg2-M$bmr,M$a_ov-M$bmr)))

cat("\n=== book-marginal ΔIR (w = A5E 비중, window-matched) ===\n")
cat(sprintf("%-6s %-14s %8s %8s %9s %8s\n","w","sleeve","book_IR","ΔIR","paired_t","book_SR"))
base_ir<-IRf(M$pg2-M$bmr)
res<-list()
for(sl in c("a_base","a_ov")) for(w in c(0,0.05,0.10,0.15,0.20)){
  nb<-(1-w)*M$pg2 + w*M[[sl]]
  act<-nb-M$bmr; ir<-IRf(act); dl<-ir-base_ir
  pt<-if(w>0) nwt(act-(M$pg2-M$bmr)) else NA
  cat(sprintf("%-6.2f %-14s %8.4f %+8.4f %9s %8.3f\n",w,
    ifelse(sl=="a_base","A5E","A5E+PG2ov"),ir,dl,ifelse(is.na(pt),"-",sprintf("%+.2f",pt)),
    mean(nb)/sd(nb)*sqrt(12)))
  res[[length(res)+1]]<-data.table(sleeve=sl,w=w,book_ir=ir,d_ir=dl,paired_t=pt)
}
R<-rbindlist(res); fwrite(R,"outputs/ramp/dfa_bookmarginal_r16_20260822.csv")
best<-R[w>0][which.max(d_ir)]
cat(sprintf("\n[판정] 최대 ΔIR = %+.4f (%s, w=%.2f) | 게이트 0.05 -> %s\n",
  best$d_ir, ifelse(best$sleeve=="a_base","A5E","A5E+PG2ov"), best$w,
  ifelse(best$d_ir>=0.05,"PASS","FAIL")))
cat("R16_DONE\n")
