## run_ramp_shumulvey_verify.R — Shu-Mulvey KR 결과 적대 검증 (graduation 주장 전 의무).
## (A) oos_retention (세번째 HARD 게이트, 2017+ decay로 RAMP 전부 죽던 것) — anchored 3-split median.
## (B) PLACEBO: regime view를 시간 셔플(타이밍 파괴) → IR 붕괴하면 타이밍 실재, 살아있으면 정적틸트 아티팩트.
## (C) 분해: active_vs_market = 정적틸트(EW vs Market) + 타이밍(BL vs EW).
## (D) PIT 재점검: SJM은 smoother 마지막상태(데이터≤t만, 미래無) — online filter 아닌 점 명시.
suppressPackageStartupMessages({library(data.table); library(arrow); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_smv_verify.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
SRf<-IRf; nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

G<-readRDS(".cache/_smv_regime.rds"); view_ann<-G$view_ann; medates<-G$medates; meix<-G$meix
R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns.parquet")); R[,Date:=as.Date(Date)]; setorder(R,Date)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth"); IDX<-c("Market",FACN); PER<-252
for(c in IDX){R[[c]][!is.finite(R[[c]])]<-NA}; R<-R[is.finite(Market)]
RM<-copy(R); RM[,ym:=format(Date,"%Y-%m")]
mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX]; setorder(mon,ym)

## EWMA cov 스냅샷
RmatAll<-as.matrix(R[,..IDX]); RmatAll[!is.finite(RmatAll)]<-0
a126<-1-exp(log(0.5)/126); Sacc<-matrix(0,7,7); Sig_list<-vector("list",length(medates)); .mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc
  if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5; w_ew<-rep(1/7,7); P<-matrix(0,6,7);for(j in 1:6)P[j,1+j]<-1;P[,1]<- -1
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-6,7);A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7))
  r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);pmax(r$solution,0)/sum(pmax(r$solution,0))}
build_W<-function(cc,VIEW){Wt<-matrix(NA_real_,length(medates),7)
  for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-VIEW[mi,];if(any(!is.finite(vv)))next
    pri<-delta*as.numeric(Sig%*%w_ew);M<-P%*%Sig%*%t(P);Om<-cc*diag(diag(M))
    muBL<-pri+as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv-as.numeric(P%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
VIEW0<-as.matrix(view_ann[,..FACN])
# 포트 월수익 (5bps delta) + EW(분기)
port_ret<-function(W){keep<-which(apply(W,1,function(r)all(is.finite(r))));k0<-keep[1];rng<-k0:length(medates)
  mr<-as.matrix(mon[rng,..IDX]);Wr<-W[rng,,drop=FALSE];for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,];Wr[!is.finite(Wr)]<-1/7
  pr<-numeric(nrow(mr));wprev<-rep(1/7,7);for(i in 1:nrow(mr)){wt<-Wr[i,];ri<-mr[i,];pr[i]<-sum(wt*ri)-5e-4*sum(abs(wt-wprev));wd<-wt*(1+ri);wprev<-wd/sum(wd)}
  ew<-numeric(nrow(mr));we<-rep(1/7,7);for(i in 1:nrow(mr)){ri<-mr[i,];ew[i]<-sum(we*ri);wd<-we*(1+ri);we<-wd/sum(wd);if(i%%3==0)we<-rep(1/7,7)}
  list(pr=pr,mkt=mr[,1],ew=ew,rng=rng)}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}

cvals<-c(TE3=20.571,TE4=13.266)
w("=== Shu-Mulvey KR — 적대 검증 (graduation 주장 전) ===\n")
for(nm in names(cvals)){ cc<-cvals[nm]
  W<-build_W(cc,VIEW0); pp<-port_ret(W); act<-pp$pr-pp$mkt; actE<-pp$pr-pp$ew
  oos<-oos_ret(act); pt<-nwt(act); ir<-IRf(act); irE<-IRf(actE)
  nav<-cumprod(1+pp$pr);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pp$pr)^(12/length(pp$pr))-1;cal<-cagr/abs(mdd)
  w(sprintf("[%s c=%.2f]  pt_capwt=%.2f  IR_vsMkt=%.2f  IR_vsEW=%.2f  calmar=%.2f  oos_retention=%.2f  (n=%d)",
    nm,cc,pt,ir,irE,cal,oos,length(act)))
  ## HARD 게이트 판정
  w(sprintf("   GATES: pt>=2.95 %s | calmar>=0.64 %s | oos>=0.7 %s  → %s",
    ifelse(pt>=2.95,"PASS","FAIL"),ifelse(cal>=0.64,"PASS","FAIL"),ifelse(!is.na(oos)&&oos>=0.7,"PASS",sprintf("FAIL(%.2f)",oos)),
    ifelse(pt>=2.95&&cal>=0.64&&!is.na(oos)&&oos>=0.7,"★ALL-PASS","미달")))
}

## (B) PLACEBO — view 시간 셔플 (타이밍 파괴), 30 seeds
w("\n=== PLACEBO: regime view 시간순서 셔플 (타이밍 파괴) → IR_vsEW 붕괴해야 타이밍 실재 ===")
for(nm in names(cvals)){ cc<-cvals[nm]
  W<-build_W(cc,VIEW0);pp<-port_ret(W);realIRE<-IRf(pp$pr-pp$ew); realPT<-nwt(pp$pr-pp$mkt)
  pe<-c()
  for(seed in 1:30){set.seed(seed);prm<-sample(nrow(VIEW0));Vp<-VIEW0[prm,,drop=FALSE]
    Wp<-build_W(cc,Vp);ppp<-port_ret(Wp);pe<-c(pe,IRf(ppp$pr-ppp$ew))}
  pe<-pe[is.finite(pe)];pval<-mean(pe>=realIRE)
  w(sprintf("[%s] real IR_vsEW=%.2f | placebo IR_vsEW mean=%.2f sd=%.2f p95=%.2f | p(placebo>=real)=%.3f → %s",
    nm,realIRE,mean(pe),sd(pe),quantile(pe,.95),pval, ifelse(pval<0.05,"타이밍 실재(유의)","spurious 의심")))
}

## (C) 분해: 정적틸트(EW vs Market) vs 타이밍(BL vs EW)
W<-build_W(cvals["TE3"],VIEW0);pp<-port_ret(W)
w("\n=== 분해 (active vs cap-w Market) ===")
w(sprintf("  정적 7팩터 EW틸트   : IR_vsMkt=%.2f  pt=%.2f  (regime 無)",IRf(pp$ew-pp$mkt),nwt(pp$ew-pp$mkt)))
w(sprintf("  +regime 타이밍(BL)  : IR_vsMkt=%.2f  pt=%.2f  (TE3)",IRf(pp$pr-pp$mkt),nwt(pp$pr-pp$mkt)))
w(sprintf("  순수 타이밍 기여     : IR_vsEW=%.2f  pt(BL-EW)=%.2f",IRf(pp$pr-pp$ew),nwt(pp$pr-pp$ew)))

## (D) PIT 노트
w("\n[PIT] SJM=offline smoother 마지막상태(window≤t, 미래데이터 無 → C1/C5 valid). 단 논문은 online filter(shift ~2x).")
w("[PIT] load_month_factors C13/14/15(IC expanding-sign), 인덱스 월말t 선택→t+1 보유(1기지연), VW=Size_lag(t-1).")
close(con);cat("VERIFY_DONE\n")
