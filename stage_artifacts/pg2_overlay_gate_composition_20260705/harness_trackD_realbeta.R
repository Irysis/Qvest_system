## ============================================================================
## Track D — REAL market-β tilt (overlay/composition frontier의 마지막 미검증 잔여)
## D1: weight-stage β 틸트 (risk-on 고β=반등포착 / risk-off 저β=방어), 진짜 252d β
## D2 진단: §6 핵심질문 — risk-off에서 저β 종목 틸트가 낙폭을 줄여 현금(R05)을 대체하나?
##   (현금은 자명히 낙폭↓; 저β-invested가 그에 근접 못하면 대체 불가 = §6 확증)
## 차분설계 vs base(0.65/0.35). paired NW-t + lag1. 저EV(§6 prior) 확인용 정직측정.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
COST <- 0.0015; NSEL <- 20L; LAMBDA <- 1.5; PHI <- 3; UB <- 0.20; KAP <- 0.6
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
bt <- as.data.table(read_parquet(file.path(WD,"panel_beta.parquet"))); bt[, Date := as.Date(Date)]
sp <- merge(sp, bt, by=c("Date","Ticker"), all.x=TRUE)
sp[, regime_lag := shift(regime_state,1), by=Ticker]; sp[is.na(regime_lag), regime_lag := regime_state]
dts <- sort(unique(sp$Date))
PG("[PG] Track D merged. beta coverage=%.3f", mean(is.finite(sp$beta)))

normalize_long_only <- function(w, ub=UB){ w[w<0]<-0; if(sum(w)==0) return(w); w<-w/sum(w)
  for(it in 1:50){ over<-w>ub; if(!any(over)) break; ex<-sum(w[over]-ub); w[over]<-ub; fr<-!over&w>0
    if(!any(fr)) break; w[fr]<-w[fr]+ex*w[fr]/sum(w[fr]) }; w[w>ub]<-ub; w/sum(w) }
linear_tilt <- function(s, lam=LAMBDA){ N<-length(s); r<-rank(s,ties.method="average")
  ce<-(r-(N+1)/2)/((N-1)/2); normalize_long_only(pmax(0,1+lam*2*ce)) }
nw_t_paired <- function(cand, base, lag=3){ d<-cand-base; d<-d[is.finite(d)]; nn<-length(d); mu<-mean(d)
  dm<-d-mu; g0<-sum(dm^2)/nn; gs<-0; for(L in 1:lag){ w<-1-L/(lag+1); gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn }
  c(mean_diff_ann=mu*12, t=mu/sqrt((g0+gs)/nn)) }
zc <- function(x){ mu<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); z<-(x-mu)/ifelse(s>0,s,1); z[!is.finite(z)]<-0; z }

## build path: tilt_fn(sel,reg)->per-name log-exposure; also return per-month regime + ret
build_path <- function(tilt_fn, regime_col="regime_state"){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_, turn=NA_real_, reg=NA_character_, bookbeta=NA_real_)
  for(k in seq_along(dts)){ D<-dts[k]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(beta)]
    if(nrow(m)<NSEL){ next }; reg<-m[[regime_col]][1]
    setorder(m,-score_eff); sel<-m[1:NSEL]
    w0<-linear_tilt(sel$score_eff); lg<-tilt_fn(sel,reg); w<-normalize_long_only(w0*exp(lg))
    if(!is.null(prevw)){ wpa<-ifelse(sel$Ticker%in%prevtk, prevw[match(sel$Ticker,prevtk)],0); wpa[is.na(wpa)]<-0
      w<-normalize_long_only((PHI/(1+PHI))*wpa+(1/(1+PHI))*w) }
    if(is.null(prevw)) turn<-1 else { allt<-union(sel$Ticker,prevtk)
      wc<-ifelse(allt%in%sel$Ticker,w[match(allt,sel$Ticker)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[k]<-sum(w*sel$Ret_1m)-turn*COST; out$turn[k]<-turn; out$reg[k]<-reg; out$bookbeta[k]<-sum(w*sel$beta)
    prevw<-w; prevtk<-sel$Ticker }
  out
}
tilt_base <- function(sel,reg) rep(0,nrow(sel))
## D1: risk-on high-beta / risk-off low-beta
tilt_D1 <- function(sel,reg){ if(reg%in%c("BULL","NORMAL")) KAP*zc(sel$beta) else if(reg%in%c("CAUTION","CRISIS")) -KAP*zc(sel$beta) else rep(0,nrow(sel)) }
## D1b: only risk-off low-beta (defensive-only, the cash-substitute composition)
tilt_D1b <- function(sel,reg){ if(reg%in%c("CAUTION","CRISIS")) -KAP*zc(sel$beta) else rep(0,nrow(sel)) }
## strong low-beta risk-off (kappa=1.5, aggressive de-beta)
tilt_D2 <- function(sel,reg){ if(reg%in%c("CAUTION","CRISIS")) -1.5*zc(sel$beta) else rep(0,nrow(sel)) }

pb <- build_path(tilt_base)
qm <- function(r,tag){ ii<-is.finite(r); x<-xts(r[ii],order.by=pb$Date[ii]); ta<-table.AnnualizedReturns(x,scale=12)
  data.table(tag=tag, SR=as.numeric(ta[3,1]), MDD=as.numeric(maxDrawdown(x)), bookbeta=mean(pb$bookbeta,na.rm=T)) }
vars <- list(D1_beta_rotate=tilt_D1, D1b_lowbeta_riskoff=tilt_D1b, D2_strong_lowbeta_riskoff=tilt_D2)
rows <- list(cbind(qm(pb$ret,"base"), data.table(paired_t=NA_real_, lag1_t=NA_real_)))
paths <- list(base=pb)
for(nm in names(vars)){ tf<-vars[[nm]]
  pv<-build_path(tf,"regime_state"); pvl<-build_path(tf,"regime_lag"); paths[[nm]]<-pv
  cc<-merge(pb[,.(Date,rb=ret)],pv[,.(Date,rv=ret)],by="Date"); cc<-cc[is.finite(rb)&is.finite(rv)]
  ccl<-merge(pb[,.(Date,rb=ret)],pvl[,.(Date,rv=ret)],by="Date"); ccl<-ccl[is.finite(rb)&is.finite(rv)]
  pt<-nw_t_paired(cc$rv,cc$rb); ptl<-nw_t_paired(ccl$rv,ccl$rb)
  mm<-qm(pv$ret,nm); mm$bookbeta<-mean(pv$bookbeta,na.rm=T)
  rows[[length(rows)+1]]<-cbind(mm, data.table(paired_t=pt["t"], lag1_t=ptl["t"]))
  PG("[PG] %s SR=%.4f MDD=%.3f bookbeta=%.3f paired_t=%.3f lag1_t=%.3f", nm, mm$SR, mm$MDD, mm$bookbeta, pt["t"], ptl["t"]) }
res<-rbindlist(rows,fill=TRUE)
print(res[, .(tag, SR=round(SR,4), MDD=round(MDD,4), bookbeta=round(bookbeta,3), paired_t=round(paired_t,3), lag1_t=round(lag1_t,3))])
fwrite(res, file.path(WD,"trackD_results.csv"))

## ---- D2 diagnostic: risk-off subperiod — does low-beta tilt reduce drawdown vs base? ----
ro <- pb$reg %in% c("CAUTION","CRISIS"); ro[is.na(ro)] <- FALSE
d1b <- paths[["D1b_lowbeta_riskoff"]]
cat("\n===== risk-off (CAUTION/CRISIS) 월 진단 =====\n")
PG("[PG] risk-off months n=%d  base mean=%.4f  lowbeta mean=%.4f  Δ=%.4f",
   sum(ro), mean(pb$ret[ro],na.rm=T), mean(d1b$ret[ro],na.rm=T), mean(d1b$ret[ro]-pb$ret[ro],na.rm=T))
PG("[PG] risk-off worst-10 avg: base=%.4f  lowbeta=%.4f (현금=0)",
   mean(sort(pb$ret[ro])[1:10]), mean(sort(d1b$ret[ro])[1:10]))
PG("[PG] → 저β 틸트가 risk-off 최악월에서 현금(0%%) 대비 여전히 큰 음수면 현금 대체 불가 = §6 확증")
PG("[PG] DONE Track D real-beta.")
