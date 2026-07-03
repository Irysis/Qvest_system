## run_ramp_shumulvey_stock25.R — RAMP_02 25종목 변환 (도훈 "25종목 제약 넣어서 진행").
## BL 21팩터 인덱스비중(월별, v4 regime) → 횡단면 종목스코어 Σ_f (w_f/Σw_f)·z_f(stock, FactorDB) →
##   top-25 EW long-only 15bps → canonical_screen_bt(계약 실측). idealized 인덱스배분 → 실배포 25종목.
## env: SMV_KEY (broad_m5_roll | broad_m8_roll). 출력: 실측 pt_capwt/calmar/oos (헌법 준수).
suppressPackageStartupMessages({library(data.table); library(arrow); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
KEY<-Sys.getenv("SMV_KEY","broad_m5_roll"); PER<-252
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
## 팩터 name→FactorDB id (broad 21, ramp_shumulvey_indices.R와 동일)
FACMAP<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
  LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
  Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
  Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
  ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

## --- v4 regime → BL 팩터비중 W 재구성 ---
G<-readRDS(sprintf(".cache/_smv4_regime_%s.rds",KEY)); view<-G$view; medates<-G$medates; meix<-G$meix; FACN<-G$FACN; N<-length(FACN)
R<-as.data.table(read_parquet(G$idxfile));R[,Date:=as.Date(Date)];setorder(R,Date);IDX<-c("Market",FACN)
for(c in IDX)R[[c]][!is.finite(R[[c]])]<-NA;R<-R[is.finite(Market)]
RmatAll<-as.matrix(R[,..IDX]);RmatAll[!is.finite(RmatAll)]<-0;a126<-1-exp(log(0.5)/126);Sacc<-matrix(0,N+1,N+1);Sig_list<-vector("list",length(medates));.mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc;if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5;w_ew<-rep(1/(N+1),N+1);Pf<-matrix(0,N,N+1);for(j in 1:N)Pf[j,1+j]<-1;Pf[,1]<- -1;VIEW0<-as.matrix(view[,..FACN])
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-5,N+1);A<-cbind(rep(1,N+1),diag(N+1));b0<-c(1,rep(0,N+1));r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);ww<-pmax(r$solution,0);if(sum(ww)<1e-9)return(w_ew);ww/sum(ww)}
build_W<-function(cc){Wt<-matrix(NA_real_,length(medates),N+1);for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-VIEW0[mi,];av<-which(is.finite(vv));if(length(av)<2){Wt[mi,]<-w_ew;next}
  Pa<-Pf[av,,drop=FALSE];va<-vv[av];pri<-delta*as.numeric(Sig%*%w_ew);M<-Pa%*%Sig%*%t(Pa);Om<-cc*diag(diag(M),length(av));muBL<-pri+as.numeric(Sig%*%t(Pa)%*%solve(M+Om,(va-as.numeric(Pa%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
# c는 TE3 캘리브
calib_c<-function(target){lo<-1e-3;hi<-50;for(b in 1:22){mid<-sqrt(lo*hi);W<-build_W(mid);tev<-c();for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig)||any(!is.finite(W[mi,])))next;tev<-c(tev,sqrt(as.numeric(t(W[mi,]-w_ew)%*%Sig%*%(W[mi,]-w_ew))))};mte<-mean(tev,na.rm=TRUE);if(!is.finite(mte)){hi<-mid;next};if(mte>target)lo<-mid else hi<-mid};sqrt(lo*hi)}
cc<-calib_c(0.03); W<-build_W(cc)
cat(sprintf("[%s] BL W 재구성 c=%.2f, N=%d팩터\n",KEY,cc,N))

## --- forward returns/bench/liq (캐시 재사용) ---
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_ym<-data.table(Date=sort(unique(fwd_ret$Date)));fwd_ym[,ym:=format(Date,"%Y-%m")]

## --- 월별 종목 스코어: Σ_f (w_f/Σw_f)·z_f(stock) ---
scores<-list()
for(mi in seq_along(medates)){ md<-medates[mi]; wf<-W[mi,2:(N+1)]; if(any(!is.finite(wf)))next
  sw<-sum(wf); wfn<-if(sw<1e-9)rep(1/N,N) else wf/sw   # 팩터비중 정규화(롱온리 항상 풀투자)
  ids<-unname(FACMAP[FACN]); f<-tryCatch(as.data.table(load_month_factors(md,factor_names=ids)),error=function(e)NULL); if(is.null(f)||nrow(f)==0)next
  fw<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")
  sc<-rep(0,nrow(fw)); for(k in seq_len(N)){col<-FACMAP[FACN[k]]; if(col%in%names(fw)){z<-fw[[col]];z[!is.finite(z)]<-0;sc<-sc+wfn[k]*z}}
  # fwd Date(같은 YM) 정렬
  fd<-fwd_ym[ym==format(md,"%Y-%m")]$Date; if(length(fd)==0)next
  scores[[as.character(md)]]<-data.table(Date=fd[1],Ticker=fw$Ticker,score=sc)
}
SC<-rbindlist(scores); cat(sprintf("scores: %d개월 × 평균 %.0f종목\n",uniqueN(SC$Date),nrow(SC)/uniqueN(SC$Date)))

## --- canonical_screen_bt: top-25 EW long-only 15bps ---
cs<-canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="smv25",strategy_id=paste0("RAMP02_25stock_",KEY))
pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1;cal<-cagr/abs(mdd)
cat(sprintf("\n=== RAMP_02 25종목 (broad 21팩터 BL→top25 EW 15bps, 헌법준수) [%s] ===\n",KEY))
cat(sprintf("  test %s~%s (%d개월)  PORT_t_capwt=%.2f  IR=%.2f  calmar=%.2f  oos=%.2f  absSR=%.2f  TO=%.1f\n",
  as.character(min(pr$date)),as.character(max(pr$date)),n, nwt(act),IRf(act),cal,oos_ret(act),IRf(pr$ret_net),cs$turnover_annual))
cat(sprintf("  GATES: pt>=2.95 %s | calmar>=0.64 %s | oos>=0.7 %s (밴드 %s)\n",
  ifelse(nwt(act)>=2.95,"P","F"),ifelse(cal>=0.64,"P","F"),ifelse(oos_ret(act)>=0.7,"P","F"),ifelse(oos_ret(act)>=0.5,"o","-")))
cat(sprintf("  [참조] 인덱스배분(idealized) %s pt 8.91/calmar 0.58/oos 0.72(MINY5) · RAMP_01(25종목) pt 2.73\n",KEY))
saveRDS(list(pr=pr,cs=cs),sprintf(".cache/_smv25_%s.rds",KEY)); cat("STOCK25_DONE\n")
