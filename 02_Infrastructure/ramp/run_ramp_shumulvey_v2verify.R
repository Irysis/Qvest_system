## run_ramp_shumulvey_v2verify.R — 승자 셀 적대검증: placebo + 서브기간 안정성 + oos밴드 증거(헌법 §3).
## env: SMV_KEY (→ .cache/_smv2_regime_<KEY>.rds). 계약 build_benchmark_compare authoritative pt.
suppressPackageStartupMessages({library(data.table); library(arrow); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); source("02_Infrastructure/contracts/backtest_result_contract.R")
KEY<-Sys.getenv("SMV_KEY","ext_m5_cv"); CC<-as.numeric(Sys.getenv("SMV_CC","0")) # c for TE; 0=use TE3 calib
G<-readRDS(sprintf(".cache/_smv2_regime_%s.rds",KEY)); view_ann<-G$view_ann; medates<-G$medates; meix<-G$meix
R<-as.data.table(read_parquet(G$idxfile)); R[,Date:=as.Date(Date)]; setorder(R,Date); PER<-252
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth");IDX<-c("Market",FACN)
for(c in IDX)R[[c]][!is.finite(R[[c]])]<-NA;R<-R[is.finite(Market)]
RM<-copy(R);RM[,ym:=format(Date,"%Y-%m")];mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX];setorder(mon,ym);mon[,medate:=medates]
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
suppressMessages({library(sandwich);library(lmtest)})
RmatAll<-as.matrix(R[,..IDX]);RmatAll[!is.finite(RmatAll)]<-0;a126<-1-exp(log(0.5)/126);Sacc<-matrix(0,7,7);Sig_list<-vector("list",length(medates));.mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc;if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5;w_ew<-rep(1/7,7);P<-matrix(0,6,7);for(j in 1:6)P[j,1+j]<-1;P[,1]<- -1;VIEW0<-as.matrix(view_ann[,..FACN])
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-6,7);A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7));r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);pmax(r$solution,0)/sum(pmax(r$solution,0))}
build_W<-function(cc,V){Wt<-matrix(NA_real_,length(medates),7);for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-V[mi,];if(any(!is.finite(vv)))next
  pri<-delta*as.numeric(Sig%*%w_ew);M<-P%*%Sig%*%t(P);Om<-cc*diag(diag(M));muBL<-pri+as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv-as.numeric(P%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
calib_c<-function(target){lo<-1e-3;hi<-50;for(b in 1:26){mid<-sqrt(lo*hi);W<-build_W(mid,VIEW0);tev<-c();for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig)||any(!is.finite(W[mi,])))next;tev<-c(tev,sqrt(as.numeric(t(W[mi,]-w_ew)%*%Sig%*%(W[mi,]-w_ew))))};mte<-mean(tev,na.rm=TRUE);if(!is.finite(mte)){hi<-mid;next};if(mte>target)lo<-mid else hi<-mid};sqrt(lo*hi)}
port<-function(W){keep<-which(apply(W,1,function(r)all(is.finite(r))));if(length(keep)<24)return(NULL);k0<-keep[1];rng<-k0:length(medates)
  mr<-as.matrix(mon[rng,..IDX]);dts<-mon$medate[rng];Wr<-W[rng,,drop=FALSE];for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,];Wr[!is.finite(Wr)]<-1/7
  pr<-numeric(nrow(mr));wprev<-rep(1/7,7);for(i in 1:nrow(mr)){wt<-Wr[i,];ri<-mr[i,];pr[i]<-sum(wt*ri)-5e-4*sum(abs(wt-wprev));wd<-wt*(1+ri);wprev<-wd/sum(wd)}
  ew<-numeric(nrow(mr));we<-rep(1/7,7);for(i in 1:nrow(mr)){ri<-mr[i,];ew[i]<-sum(we*ri);wd<-we*(1+ri);we<-wd/sum(we*0+wd);if(i%%3==0)we<-rep(1/7,7)}
  data.table(date=dts,ret_net=pr,bm=mr[,1],ew=ew)}
ptc<-function(pp){prt<-data.table(date=pp$date,ret_net=pp$ret_net,frequency="monthly");bmt<-data.table(date=pp$date,benchmark_ret=pp$bm,benchmark_id="capw")
  build_benchmark_compare(prt,bmt,run_id="v",strategy_id="v",annualization_factor=12)[metric_name=="Portfolio_Alpha_t_NW_lag3",strategy_value]}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
cc<-if(CC>0)CC else calib_c(0.03)
W<-build_W(cc,VIEW0);pp<-port(W);act<-pp$ret_net-pp$bm;actE<-pp$ret_net-pp$ew;n<-length(act)
cat(sprintf("=== 적대검증 [%s] c=%.2f n_mo=%d test=%s~%s ===\n",KEY,cc,n,as.character(min(pp$date)),as.character(max(pp$date))))
ptr<-ptc(pp);cat(sprintf("[REAL] PORT_t=%.2f IR_vsMkt=%.2f IR_vsEW=%.2f oos=%.2f\n",ptr,IRf(act),IRf(actE),oos_ret(act)))
## (A) PLACEBO 30
pe<-c();pep<-c();for(seed in 1:30){set.seed(seed);Vp<-VIEW0[sample(nrow(VIEW0)),,drop=FALSE];Wp<-build_W(cc,Vp);ppp<-port(Wp);if(is.null(ppp))next;pe<-c(pe,IRf(ppp$ret_net-ppp$ew));pep<-c(pep,ptc(ppp))}
cat(sprintf("[PLACEBO] real IR_vsEW=%.2f vs shuffle mean=%.2f sd=%.2f | real PORT_t=%.2f vs shuffle mean=%.2f p95=%.2f | p(plac>=real)=%.3f → %s\n",
  IRf(actE),mean(pe),sd(pe),ptr,mean(pep),quantile(pep,.95),mean(pep>=ptr),ifelse(mean(pep>=ptr)<0.05,"타이밍 실재","spurious")))
## (B) 서브기간 안정성 — GFC 회복(첫 36m) 제거 + 3분할 PORT_t
pt_drop36<-nwt(act[37:n]); thirds<-split(act,cut(seq_len(n),3,labels=F))
cat(sprintf("[SUBPERIOD] 전체 PORT_t=%.2f | 첫36m제거 PORT_t=%.2f | 3분할 PORT_t: %s\n",ptr,pt_drop36,paste(sprintf("%.2f",sapply(thirds,nwt)),collapse=" / ")))
cat(sprintf("            3분할 mean월active(bps): %s | 마지막1/3 IR=%.2f\n",paste(sprintf("%.0f",sapply(thirds,function(x)mean(x)*1e4)),collapse=" / "),IRf(thirds[[3]])))
## (C) oos 밴드 증거 (oos∈[0.5,0.7) → 2/3 충족 시 조건부PASS): ① trailing PORT_t>0 ② placebo p<0.05 (③ book-marginal 별도)
oosv<-oos_ret(act);ev1<-IRf(thirds[[3]])>0 && nwt(thirds[[3]])>0; ev2<-mean(pep>=ptr)<0.05
cat(sprintf("[oos BAND] oos=%.2f %s | 증거① trailing(3rd)PORT_t>0:%s | 증거② placebo p<.05:%s | (③ book-marginal=별도) → %s\n",
  oosv, ifelse(oosv>=0.7,"≥0.7 무조건PASS",ifelse(oosv<0.5,"<0.5 무조건FAIL","[0.5,0.7) 밴드")),
  ifelse(ev1,"PASS","FAIL"),ifelse(ev2,"PASS","FAIL"),
  ifelse(oosv>=0.7,"GRADUATE", ifelse(oosv<0.5,"screen-tier", ifelse(sum(c(ev1,ev2))>=2,"조건부 GRADUATE(2/3, ③확인필요)","미달")))))
cat(sprintf("[PIT] CV튜닝은 첫 %dy(pre-test)만 사용, 테스트(%s~) 무참조. SJM last-state=데이터≤t.\n",G$miny,as.character(min(pp$date))))
cat("VVERIFY_DONE\n")
