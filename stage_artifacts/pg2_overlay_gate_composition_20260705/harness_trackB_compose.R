## ============================================================================
## Track B — Regime-conditional sleeve composition (holdings-level, NOVEL)
## 현행: score_eff = 0.65*core + 0.35*def (고정). Track B: 국면조건부 가변 배합.
##   risk-on(BULL/NORMAL) → core 틸트(공격), risk-off(CAUTION/CRISIS) → defense 틸트.
##   스칼라 노출이 아닌 횡단면 회전 → long-only turning-point 사망원인("현금가서 반등놓침") 회피.
## 차분설계: base-blend vs regime-blend를 동일 machinery로 재구성 → 재구성오차 상쇄.
## β-scan: base 재구성 return vs ret_orig 상관 최대 offset으로 Ret_1m 정렬(누출) 검증.
## 검증: 선택레벨 paired NW-t (regime − base) + lag1 stress. 양성이면 book 단계 escalate.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015; NSEL <- 20L; LAMBDA <- 1.5; PHI <- 3; UB <- 0.20
PG("[PG] start Track B  NSEL=%d lambda=%.1f phi=%d", NSEL, LAMBDA, PHI)

## ---------- load score panel ----------
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")))
sp[, Date := as.Date(Date)]; setorder(sp, Date, Ticker)
dts <- sort(unique(sp$Date)); PG("[PG] panel %d rows, %d months %s..%s", nrow(sp), length(dts), as.character(min(dts)), as.character(max(dts)))
## verify score_eff = 0.65 core + 0.35 def
chk <- sp[is.finite(score_eff) & is.finite(score_core_z) & is.finite(score_defense_z)]
d065 <- max(abs(chk$score_eff - (0.65*chk$score_core_z + 0.35*chk$score_defense_z)), na.rm=TRUE)
PG("[PG] score_eff==0.65core+0.35def max_abs_err=%.2e (%s)", d065, ifelse(d065<1e-6,"CONFIRMED","DIFF"))
## regime per month constant?
rc <- sp[, .(nr=uniqueN(regime_state)), by=Date]; PG("[PG] regime per-month unique max=%d (1=constant)", max(rc$nr))

## ---------- weighting machinery ----------
normalize_long_only <- function(w, ub=UB){
  w[w<0] <- 0; if(sum(w)==0) return(w); w <- w/sum(w)
  for(it in 1:50){ over <- w>ub; if(!any(over)) break
    excess <- sum(w[over]-ub); w[over] <- ub; free <- !over & w>0
    if(!any(free)) break; w[free] <- w[free] + excess*w[free]/sum(w[free]) }
  w[w>ub] <- ub; w/sum(w)
}
linear_tilt <- function(scores, lambda=LAMBDA){
  N <- length(scores); r <- rank(scores, ties.method="average")
  centered <- (r - (N+1)/2)/((N-1)/2)          ## in [-1,1]
  normalize_long_only(pmax(0, 1 + lambda*2*centered))
}

## build one portfolio path: score_fn(core,def,reg)->score, lam_fn(reg)->lambda, regime_col
build_path <- function(score_fn, lam_fn, regime_col="regime_state"){
  prevw <- NULL; prevtk <- NULL
  out <- data.table(Date=dts, ret=NA_real_, turn=NA_real_)
  for(k in seq_along(dts)){
    D <- dts[k]; m <- sp[Date==D & is.finite(score_core_z) & is.finite(score_defense_z) & is.finite(Ret_1m)]
    if(nrow(m)<NSEL){ out$ret[k] <- NA; next }
    reg <- m[[regime_col]][1]; lam <- lam_fn(reg)
    m[, sc := score_fn(score_core_z, score_defense_z, reg)]
    setorder(m, -sc); sel <- m[1:NSEL]
    w_tilt <- linear_tilt(sel$sc, lam)
    if(is.null(prevw)){ w <- w_tilt } else {
      wpa <- ifelse(sel$Ticker %in% prevtk, prevw[match(sel$Ticker, prevtk)], 0); wpa[is.na(wpa)] <- 0
      w <- normalize_long_only((PHI/(1+PHI))*wpa + (1/(1+PHI))*w_tilt)
    }
    if(is.null(prevw)) turn <- 1 else {
      allt <- union(sel$Ticker, prevtk)
      wc <- ifelse(allt %in% sel$Ticker, w[match(allt, sel$Ticker)], 0); wc[is.na(wc)] <- 0
      wp <- ifelse(allt %in% prevtk, prevw[match(allt, prevtk)], 0); wp[is.na(wp)] <- 0
      turn <- sum(abs(wc-wp)) }
    out$ret[k] <- sum(w*sel$Ret_1m) - turn*COST; out$turn[k] <- turn
    prevw <- w; prevtk <- sel$Ticker
  }
  out
}
nw_t_paired <- function(cand, base, lag=3){
  d <- cand-base; d<-d[is.finite(d)]; nn<-length(d); mu<-mean(d); dm<-d-mu; g0<-sum(dm^2)/nn; gs<-0
  for(L in 1:lag){ w<-1-L/(lag+1); gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn }
  c(mean_diff_ann=mu*12, t=mu/sqrt((g0+gs)/nn))
}
L15 <- function(reg) 1.5   ## constant lambda

## ---------- variant definitions ----------
## sleeve blend maps (w_core by regime); base = flat 0.65
mk_blend <- function(bull,normal,caut,cris) function(core,def,reg){
  wc <- switch(reg, BULL=bull, NORMAL=normal, CAUTION=caut, CRISIS=cris, 0.65); wc*core+(1-wc)*def }
f_base   <- function(core,def,reg) 0.65*core + 0.35*def
variants <- list(
  regime_blend  = list(sf=mk_blend(0.80,0.70,0.50,0.45), lf=L15),               # risk-on core / risk-off def
  reverse_blend = list(sf=mk_blend(0.45,0.55,0.80,0.85), lf=L15),               # opposite (sanity)
  strong_blend  = list(sf=mk_blend(0.95,0.80,0.35,0.25), lf=L15),               # extreme rotation
  tilt_regime   = list(sf=f_base, lf=function(reg) switch(reg,BULL=2.5,NORMAL=2.0,CAUTION=1.0,CRISIS=0.6,1.5)), # aggressive risk-on
  deconc_riskoff= list(sf=f_base, lf=function(reg) switch(reg,BULL=1.5,NORMAL=1.5,CAUTION=0.5,CRISIS=0.0,1.5))  # risk-off equal-weight
)

## ---------- build base + variants (normal + lag1) ----------
PG("[PG] building base...")
pb <- build_path(f_base, L15)
p2 <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p2[, ym := realized_ym]; setorder(p2, realized_ym)
base_ts <- pb[is.finite(ret)][, .(ym=format(Date,"%Y-%m"), ret_base=ret)]
for(off in -2:2){ bm <- copy(base_ts); bm[, key_ym := format(as.Date(paste0(ym,"-01")) %m+% months(off), "%Y-%m")]
  mrg <- merge(bm, p2[,.(key_ym=ym, ret_orig)], by="key_ym")
  if(nrow(mrg)>50) PG("[PG] beta-scan offset %+d: cor=%.3f n=%d", off, cor(mrg$ret_base, mrg$ret_orig), nrow(mrg)) }

## lag1 panel (regime shifted by 1 month per ticker)
sp[, regime_lag := shift(regime_state,1), by=Ticker]; sp[is.na(regime_lag), regime_lag := regime_state]

qm <- function(r, tag){ ii<-is.finite(r); x<-xts(r[ii], order.by=pb$Date[ii]); ta<-table.AnnualizedReturns(x, scale=12)
  data.table(tag=tag, SR=as.numeric(ta[3,1]), CAGR=as.numeric(ta[1,1]), MDD=as.numeric(maxDrawdown(x))) }
rows <- list(cbind(qm(pb$ret,"base_blend_0.65"), data.table(mean_turn=mean(pb$turn,na.rm=T), paired_t=NA_real_, lag1_t=NA_real_)))
for(nm in names(variants)){
  v <- variants[[nm]]
  pv  <- build_path(v$sf, v$lf, "regime_state")
  pvl <- build_path(v$sf, v$lf, "regime_lag")
  cc  <- merge(pb[,.(Date,rb=ret)], pv[,.(Date,rv=ret)], by="Date"); cc<-cc[is.finite(rb)&is.finite(rv)]
  ccl <- merge(pb[,.(Date,rb=ret)], pvl[,.(Date,rv=ret)],by="Date"); ccl<-ccl[is.finite(rb)&is.finite(rv)]
  pt  <- nw_t_paired(cc$rv, cc$rb); ptl <- nw_t_paired(ccl$rv, ccl$rb)
  rows[[length(rows)+1]] <- cbind(qm(pv$ret,nm), data.table(mean_turn=mean(pv$turn,na.rm=T), paired_t=pt["t"], lag1_t=ptl["t"]))
  PG("[PG] %s: SR=%.4f MDD=%.3f d_ann=%.4f paired_t=%.3f lag1_t=%.3f", nm, qm(pv$ret,nm)$SR, qm(pv$ret,nm)$MDD, pt["mean_diff_ann"], pt["t"], ptl["t"])
}
res <- rbindlist(rows, fill=TRUE)
print(res[, .(tag, SR=round(SR,4), MDD=round(MDD,4), mean_turn=round(mean_turn,3), paired_t=round(paired_t,3), lag1_t=round(lag1_t,3))])
fwrite(res, file.path(WD,"trackB_results.csv"))
PG("[PG] DONE Track B multi-variant. saved trackB_results.csv")
PG("[PG] 판정규칙: paired_t>~2 AND lag1 부호유지 시에만 book escalate. 아니면 composition null.")
