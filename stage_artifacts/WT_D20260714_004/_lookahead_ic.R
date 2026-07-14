## R28 look-ahead corroboration — stored score IC vs contemporaneous(month it's screened) vs +1 forward.
## stored score label M is built from factor_db_M (month-M-END, parity 0.913). deltair maps label M -> month-M return.
## If IC(stored, month-M return) is strong => month-M-END factor data explains month-M return = look-ahead.
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
bkp<-file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk<-as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]; bk<-bk[is.finite(score_eff)]
bk[,labym:=format(Date,"%Y-%m")]
## monthly returns from RAWDATA (month-end close -> next month-end close)
RAW<-as.data.table(read_parquet(file.path(QM,".cache/RAWDATA.parquet"),col_select=c("Ticker","Date","Close")))
RAW[,Date:=as.Date(Date)]; RAW[,ym:=format(Date,"%Y-%m")]
me<-RAW[,.(md=max(Date)),by=ym]; RAWm<-merge(RAW,me,by.x=c("ym","Date"),by.y=c("ym","md"))[,.(ym,Ticker,Close)]
setorder(RAWm,Ticker,ym)
RAWm[,ret_next:=shift(Close,1,type="lead")/Close-1,by=Ticker]  # return over the month AFTER ym's month
## For label M (first of month M): factor data = month-M-end.
##  - "contemporaneous" return = return DURING month M = from (M-1)-end close to M-end close = ret_next of ym=(M-1)
##  - "forward+1" return = return during month M+1 = ret_next of ym=M
## Build per label M:
ym_shift<-function(ym,k){mi<-as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7))+k; sprintf("%04d-%02d",(mi-1L)%/%12L,(mi-1L)%%12L+1L)}
bk[,ym_contemp:=ym_shift(labym,-1)]   # return during month M
bk[,ym_fwd1:=labym]                    # return during month M+1
## contemporaneous IC: score(label M) vs ret_next[ym=M-1] (= month-M return)
ic_join<-function(retym_col,lab){
  m<-merge(bk[,.(Ticker,score_eff,rym=get(retym_col))], RAWm[,.(Ticker,ym,ret_next)],
           by.x=c("Ticker","rym"), by.y=c("Ticker","ym"))
  m<-m[is.finite(ret_next)]
  per<-m[,{if(.N>=20&&sd(score_eff)>0&&sd(ret_next)>0) .(ic=cor(score_eff,ret_next,method="spearman")) else .(ic=NA_real_)},by=rym]
  ics<-per$ic[is.finite(per$ic)]
  fit<-lm(ics~1); se<-sqrt(NeweyWest(fit,lag=3,prewhite=FALSE)[1,1])
  cat(sprintf("%-16s mean rank-IC=%.4f  n_months=%d  IC_t(NW3)=%.2f\n",lab,mean(ics),length(ics),coef(fit)[1]/se))
}
cat("=== stored score_eff rank-IC: contemporaneous (month-M, same as factor vintage) vs forward+1 (month-M+1) ===\n")
ic_join("ym_contemp","contemporaneous(M)")
ic_join("ym_fwd1","forward+1(M+1)")
cat("LOOKAHEAD_IC_DONE\n")
