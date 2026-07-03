## run_ramp_shumulvey_contract.R — Shu-Mulvey KR 결과를 §2 계약(build_benchmark_compare) 경유 authoritative 재측정.
## period_returns_tbl(date,ret_net,frequency) + benchmark(cap-w market) → Portfolio_Alpha_t_NW_lag3 권위 pt.
suppressPackageStartupMessages({library(data.table); library(arrow); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")  # build_benchmark_compare + deps(xts/PerfAnalytics)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
G<-readRDS(".cache/_smv_regime.rds"); view_ann<-G$view_ann; medates<-G$medates; meix<-G$meix
R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns.parquet")); R[,Date:=as.Date(Date)]; setorder(R,Date)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth"); IDX<-c("Market",FACN); PER<-252
for(c in IDX){R[[c]][!is.finite(R[[c]])]<-NA}; R<-R[is.finite(Market)]
RM<-copy(R); RM[,ym:=format(Date,"%Y-%m")]
mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX]; setorder(mon,ym)
mon[,medate:=medates]
RmatAll<-as.matrix(R[,..IDX]); RmatAll[!is.finite(RmatAll)]<-0
a126<-1-exp(log(0.5)/126); Sacc<-matrix(0,7,7); Sig_list<-vector("list",length(medates)); .mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc
  if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5; w_ew<-rep(1/7,7); P<-matrix(0,6,7);for(j in 1:6)P[j,1+j]<-1;P[,1]<- -1
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-6,7);A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7))
  r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);pmax(r$solution,0)/sum(pmax(r$solution,0))}
build_W<-function(cc){Wt<-matrix(NA_real_,length(medates),7)
  for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-as.numeric(view_ann[mi,..FACN]);if(any(!is.finite(vv)))next
    pri<-delta*as.numeric(Sig%*%w_ew);M<-P%*%Sig%*%t(P);Om<-cc*diag(diag(M))
    muBL<-pri+as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv-as.numeric(P%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
# 월간 net 포트수익 + 날짜
port<-function(cc){W<-build_W(cc);keep<-which(apply(W,1,function(r)all(is.finite(r))));k0<-keep[1];rng<-k0:length(medates)
  mr<-as.matrix(mon[rng,..IDX]);dts<-mon$medate[rng];Wr<-W[rng,,drop=FALSE]
  for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,];Wr[!is.finite(Wr)]<-1/7
  pr<-numeric(nrow(mr));wprev<-rep(1/7,7);for(i in 1:nrow(mr)){wt<-Wr[i,];ri<-mr[i,];pr[i]<-sum(wt*ri)-5e-4*sum(abs(wt-wprev));wd<-wt*(1+ri);wprev<-wd/sum(wd)}
  data.table(date=dts,ret_net=pr,bm=mr[,1])}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}

cat("=== Shu-Mulvey KR — §2 계약(build_benchmark_compare) authoritative 재측정 ===\n")
cat(sprintf("  %-6s %10s %8s %8s %8s %8s\n","TE","PORT_t_NW3","IR","calmar","oos_ret","absSR"))
for(te in c("TE3","TE4")){ cc<-if(te=="TE3")20.571 else 13.266
  pp<-port(cc)
  prt<-data.table(date=pp$date,ret_net=pp$ret_net,frequency="monthly")
  bmt<-data.table(date=pp$date,benchmark_ret=pp$bm,benchmark_id="capw_K200KQ150")
  bc<-build_benchmark_compare(prt,bmt,run_id="smv",strategy_id=paste0("SHUMULVEY_",te),annualization_factor=12)
  pt<-bc[metric_name=="Portfolio_Alpha_t_NW_lag3",strategy_value]
  ir<-bc[metric_name=="Information_Ratio",active_value]
  act<-pp$ret_net-pp$bm; nav<-cumprod(1+pp$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pp$ret_net)^(12/length(pp$ret_net))-1
  cal<-cagr/abs(mdd); oos<-oos_ret(act); sr<-mean(pp$ret_net)/sd(pp$ret_net)*sqrt(12)
  cat(sprintf("  %-6s %10.2f %8.2f %8.2f %8.2f %8.2f   [gates pt>=2.95 %s|calmar>=0.64 %s|oos>=0.7 %s]\n",
    te,pt,ir,cal,oos,sr, ifelse(pt>=2.95,"P","F"),ifelse(cal>=0.64,"P","F"),ifelse(!is.na(oos)&&oos>=0.7,"P","F")))
}
cat("CONTRACT_DONE\n")
