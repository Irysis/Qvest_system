## ============================================================================
## Track C — Weight-stage regime-conditional per-name tilt (composition, final lever)
## 선택(top-20 by base score) 유지, 가중을 국면조건부 per-name factor로 재틸트:
##   risk-off(CAUTION/CRISIS) → 저-tail-risk(−R05_Tail_Risk_Z) 과중 (방어)
##   risk-on(BULL/NORMAL)     → 모멘텀(score_core_z) 과중 (반등 포착)
##   w_final ∝ w_tilt × exp(kappa(reg) × factor_z) → renorm[0,0.20],Σ=1
## 로드맵 P3 "홀딩스-레벨 고β/저vol 틸트" tractable 구현. 차분설계 vs base.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
COST <- 0.0015; NSEL <- 20L; LAMBDA <- 1.5; PHI <- 3; UB <- 0.20
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]; setorder(sp, Date, Ticker)
sp[, regime_lag := shift(regime_state,1), by=Ticker]; sp[is.na(regime_lag), regime_lag := regime_state]
dts <- sort(unique(sp$Date))
PG("[PG] Track C panel %d rows, cols: %s", nrow(sp), paste(names(sp), collapse=","))

normalize_long_only <- function(w, ub=UB){ w[w<0]<-0; if(sum(w)==0) return(w); w<-w/sum(w)
  for(it in 1:50){ over<-w>ub; if(!any(over)) break; ex<-sum(w[over]-ub); w[over]<-ub; fr<-!over&w>0
    if(!any(fr)) break; w[fr]<-w[fr]+ex*w[fr]/sum(w[fr]) }; w[w>ub]<-ub; w/sum(w) }
linear_tilt <- function(s, lam=LAMBDA){ N<-length(s); r<-rank(s,ties.method="average")
  ce<-(r-(N+1)/2)/((N-1)/2); normalize_long_only(pmax(0,1+lam*2*ce)) }
nw_t_paired <- function(cand, base, lag=3){ d<-cand-base; d<-d[is.finite(d)]; nn<-length(d); mu<-mean(d)
  dm<-d-mu; g0<-sum(dm^2)/nn; gs<-0; for(L in 1:lag){ w<-1-L/(lag+1); gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn }
  c(mean_diff_ann=mu*12, t=mu/sqrt((g0+gs)/nn)) }

## tilt_fn(sel_dt, reg) returns per-name multiplicative log-exposure (0 = base)
build_path <- function(tilt_fn, regime_col="regime_state"){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_, turn=NA_real_)
  for(k in seq_along(dts)){ D<-dts[k]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(score_core_z) & is.finite(R05_Tail_Risk_Z)]
    if(nrow(m)<NSEL){ next }; reg<-m[[regime_col]][1]
    setorder(m,-score_eff); sel<-m[1:NSEL]
    w0 <- linear_tilt(sel$score_eff)
    lg <- tilt_fn(sel, reg); w_t <- normalize_long_only(w0*exp(lg))
    if(is.null(prevw)){ w<-w_t } else { wpa<-ifelse(sel$Ticker %in% prevtk, prevw[match(sel$Ticker,prevtk)],0); wpa[is.na(wpa)]<-0
      w<-normalize_long_only((PHI/(1+PHI))*wpa+(1/(1+PHI))*w_t) }
    if(is.null(prevw)) turn<-1 else { allt<-union(sel$Ticker,prevtk)
      wc<-ifelse(allt%in%sel$Ticker,w[match(allt,sel$Ticker)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[k]<-sum(w*sel$Ret_1m)-turn*COST; out$turn[k]<-turn; prevw<-w; prevtk<-sel$Ticker }
  out
}
zc <- function(x){ x <- x - mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE); if(s>0) x/s else x*0 }
KAP <- 0.6
tilt_base <- function(sel,reg) rep(0, nrow(sel))
tilt_C1 <- function(sel,reg){ if(reg %in% c("CAUTION","CRISIS")) -KAP*zc(sel$R05_Tail_Risk_Z) else rep(0,nrow(sel)) } # low tail-risk OW risk-off
tilt_C2 <- function(sel,reg){ if(reg %in% c("BULL","NORMAL"))    KAP*zc(sel$score_core_z)    else rep(0,nrow(sel)) } # momentum OW risk-on
tilt_C3 <- function(sel,reg){ if(reg %in% c("CAUTION","CRISIS")) -KAP*zc(sel$R05_Tail_Risk_Z) else KAP*zc(sel$score_core_z) }

pb <- build_path(tilt_base)
qm <- function(r,tag){ ii<-is.finite(r); x<-xts(r[ii],order.by=pb$Date[ii]); ta<-table.AnnualizedReturns(x,scale=12)
  data.table(tag=tag, SR=as.numeric(ta[3,1]), MDD=as.numeric(maxDrawdown(x))) }
vars <- list(C1_lowtail_riskoff=tilt_C1, C2_mom_riskon=tilt_C2, C3_both=tilt_C3)
rows <- list(cbind(qm(pb$ret,"base"), data.table(mean_turn=mean(pb$turn,na.rm=T), paired_t=NA_real_, lag1_t=NA_real_)))
for(nm in names(vars)){ tf<-vars[[nm]]
  pv<-build_path(tf,"regime_state"); pvl<-build_path(tf,"regime_lag")
  cc<-merge(pb[,.(Date,rb=ret)],pv[,.(Date,rv=ret)],by="Date"); cc<-cc[is.finite(rb)&is.finite(rv)]
  ccl<-merge(pb[,.(Date,rb=ret)],pvl[,.(Date,rv=ret)],by="Date"); ccl<-ccl[is.finite(rb)&is.finite(rv)]
  pt<-nw_t_paired(cc$rv,cc$rb); ptl<-nw_t_paired(ccl$rv,ccl$rb)
  rows[[length(rows)+1]]<-cbind(qm(pv$ret,nm), data.table(mean_turn=mean(pv$turn,na.rm=T), paired_t=pt["t"], lag1_t=ptl["t"]))
  PG("[PG] %s SR=%.4f MDD=%.3f d_ann=%.4f paired_t=%.3f lag1_t=%.3f", nm, qm(pv$ret,nm)$SR, qm(pv$ret,nm)$MDD, pt["mean_diff_ann"], pt["t"], ptl["t"]) }
res<-rbindlist(rows,fill=TRUE)
print(res[, .(tag, SR=round(SR,4), MDD=round(MDD,4), mean_turn=round(mean_turn,3), paired_t=round(paired_t,3), lag1_t=round(lag1_t,3))])
fwrite(res, file.path(WD,"trackC_results.csv"))
PG("[PG] DONE Track C weight-tilt. saved trackC_results.csv")
