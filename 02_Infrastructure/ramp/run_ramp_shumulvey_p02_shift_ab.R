## run_ramp_shumulvey_p02_shift_ab.R — P0-2: 동월 적용(현행 bt) vs 익월 적용(보정) 타이밍 A/B.
## FQ-239 / prereg outputs/ramp/smv_v5_prereg_20260820.json / 계획 ~/.claude/plans/shu-yu-mulvey-rippling-nautilus.md
## 입력: P0-1이 재생성한 .cache/_smv_regime.rds(states/views) + .cache/_smv_result.rds(cvals) + 동결 지수 parquet.
## 타이밍 축만 고립: SJM 상태·뷰·c 캘리브 값 전부 재사용, 비중 재산출은 동일 코드 경로.
##   arm same = W[m] × ret[m]   (현행 bt() — 월말 결정 비중이 같은 달 수익 획득 = 동월 look-ahead)
##   arm corr = W[m-1] × ret[m] (보정 — 월말 결정 비중을 익월에 적용; 이후 전 계열의 기준선 M0 회계)
## 두 팔 공통 윈도(둘째 월부터)로 paired 비교. 인플레율 = overlay_lookahead_ab(current=same, strict=corr).
suppressPackageStartupMessages({library(data.table); library(arrow); library(quadprog)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/validation/overlay_pit_guard.R")

IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
SRf<-IRf
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

stopifnot(file.exists(".cache/_smv_regime.rds"), file.exists(".cache/_smv_result.rds"))
SM<-readRDS(".cache/_smv_regime.rds"); SR<-readRDS(".cache/_smv_result.rds")
view_ann<-SM$view_ann; medates<-SM$medates; meix<-SM$meix; cvals<-SR$cvals

## ---- 데이터 로드 (본체와 동일 블록) ----
R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date)
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth"); IDX<-c("Market",FACN)
for(c in IDX) R[[c]][!is.finite(R[[c]])]<-NA
R<-R[is.finite(Market)]
stopifnot(identical(as.integer(meix), as.integer(which(!duplicated(format(R$Date,"%Y-%m"),fromLast=TRUE)))))
RM<-copy(R); RM[,ym:=format(Date,"%Y-%m")]
mon<-RM[,lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),by=ym,.SDcols=IDX]
mon[,medate:=R$Date[meix]]; setorder(mon,medate)

## ---- Σ 스냅샷 재계산 (본체 :148-153 동일) ----
delta<-2.5; w_ew<-rep(1/7,7); PER<-252
RmatAll<-as.matrix(R[,..IDX]); RmatAll[!is.finite(RmatAll)]<-0
a126<-1-exp(log(0.5)/126); Sacc<-matrix(0,7,7); Sig_list<-vector("list",length(medates)); .mi<-1L
for(t in 1:nrow(RmatAll)){ x<-RmatAll[t,]; Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc
  if(.mi<=length(meix) && t==meix[.mi]){ if(t>=130)Sig_list[[.mi]]<-Sacc*PER; .mi<-.mi+1L } }
P<-matrix(0,6,7); for(j in 1:6)P[j,1+j]<-1; P[,1]<- -1
solveMVO<-function(muv,Sig){ D<-delta*Sig; D<-D+diag(1e-6,7); A<-cbind(rep(1,7),diag(7));b0<-c(1,rep(0,7))
  r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL); if(is.null(r))return(w_ew); pmax(r$solution,0)/sum(pmax(r$solution,0)) }
build_weights<-function(cc){ Wt<-matrix(NA_real_,length(medates),7)
  for(mi in seq_along(medates)){ Sig<-Sig_list[[mi]]; if(is.null(Sig))next
    vv<-as.numeric(view_ann[mi,..FACN]); if(any(!is.finite(vv)))next
    pri<-delta*as.numeric(Sig%*%w_ew)
    M<-P%*%Sig%*%t(P); Om<-cc*diag(diag(M))
    muBL<-pri + as.numeric(Sig%*%t(P)%*%solve(M+Om,(vv - as.numeric(P%*%pri))))
    Wt[mi,]<-solveMVO(muBL,Sig) }
  Wt }

## ---- 타이밍 2팔 백테 (공통 윈도, 5bps — 본체 bt()와 동일 비용/드리프트 회계) ----
bt_arm<-function(W, shift){ # shift=0 동월(현행) / 1 익월(보정)
  keep<-which(apply(W,1,function(r)all(is.finite(r)))); if(length(keep)<24)return(NULL)
  k0<-keep[1]; rng<-k0:length(medates)
  Wr<-W[rng,,drop=FALSE]
  for(i in 2:nrow(Wr))if(any(!is.finite(Wr[i,])))Wr[i,]<-Wr[i-1,]
  Wr[!is.finite(Wr)]<-1/7
  mr<-as.matrix(mon[rng,..IDX])
  ii<-2:nrow(mr)                       # 공통 윈도: 둘째 월부터 (corr 팔의 W[m-1] 존재 보장)
  pr<-numeric(length(ii)); to<-numeric(length(ii)); wprev<-rep(1/7,7)
  for(q in seq_along(ii)){ i<-ii[q]; wt<-if(shift==0)Wr[i,] else Wr[i-1,]; ri<-mr[i,]
    gross<-sum(wt*ri); dlt<-sum(abs(wt-wprev)); pr[q]<-gross-5e-4*dlt; to[q]<-dlt
    wd<-wt*(1+ri); wprev<-wd/sum(wd) }
  mkt<-mr[ii,1]
  ew<-numeric(length(ii)); we<-rep(1/7,7)
  for(q in seq_along(ii)){ i<-ii[q]; ri<-mr[i,]; ew[q]<-sum(we*ri); wd<-we*(1+ri); we<-wd/sum(wd); if(q%%3==0)we<-rep(1/7,7)}
  actM<-pr-mkt; actE<-pr-ew; n<-length(pr)
  nav<-cumprod(1+pr); mdd<-min(nav/cummax(nav)-1)
  list(IR_vsMkt=IRf(actM), IR_vsEW=IRf(actE), pt_capwt=nwt(actM), abs_SR=SRf(pr),
       abs_CAGR=prod(1+pr)^(12/n)-1, abs_MDD=mdd, TO_ann=mean(to)*12, n_mo=n,
       actM=actM, actE=actE, pr=pr, first=as.character(mon$medate[rng[ii[1]]]))
}

OUT<-list(); tags<-c()
cat(sprintf("%-9s %-5s %6s %9s %9s %9s %7s %8s %7s\n","model","arm","n_mo","IR_vsMkt","IR_vsEW","pt_capwt","absSR","absMDD","TO_yr"))
for(k in seq_along(cvals)){ tgt<-c(1,2,3,4)[k]; W<-build_weights(cvals[k])
  same<-bt_arm(W,0); corr<-bt_arm(W,1); if(is.null(same)||is.null(corr))next
  for(nm in c("same","corr")){ a<-get(nm)
    cat(sprintf("BL_TE%d%%  %-5s %6d %+9.2f %+9.2f %+9.2f %+7.2f %+8.3f %7.2f\n",
        tgt,nm,a$n_mo,a$IR_vsMkt,a$IR_vsEW,a$pt_capwt,a$abs_SR,a$abs_MDD,a$TO_ann)) }
  ab_pt <-overlay_lookahead_ab(same$pt_capwt, corr$pt_capwt, sprintf("TE%d%% pt_capwt",tgt))
  ab_ire<-overlay_lookahead_ab(same$IR_vsEW,  corr$IR_vsEW,  sprintf("TE%d%% IR_vsEW",tgt))
  difft<-tryCatch(nwt(same$actM - corr$actM), error=function(e)NA_real_)
  cat(sprintf("  paired NW-t(same-corr, actM) = %+0.2f | 시작월 %s\n", difft, corr$first))
  OUT[[length(OUT)+1]]<-data.table(te=tgt, arm=c("same","corr"),
    n_mo=c(same$n_mo,corr$n_mo), IR_vsMkt=c(same$IR_vsMkt,corr$IR_vsMkt),
    IR_vsEW=c(same$IR_vsEW,corr$IR_vsEW), pt_capwt=c(same$pt_capwt,corr$pt_capwt),
    abs_SR=c(same$abs_SR,corr$abs_SR), abs_MDD=c(same$abs_MDD,corr$abs_MDD),
    TO_ann=c(same$TO_ann,corr$TO_ann),
    infl_pt=rep(ab_pt$inflation,2), infl_ire=rep(ab_ire$inflation,2),
    paired_nwt_actM=rep(difft,2))
}
AB<-rbindlist(OUT)
fwrite(AB, "outputs/ramp/smv_p02_shift_ab_20260820.csv")
saveRDS(AB, ".cache/_smv_p02_shift_ab.rds")
cat("P02_DONE rows=",nrow(AB),"\n")
