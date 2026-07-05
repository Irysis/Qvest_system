## ============================================================================
## 자가발전 사이클 5 — 마일스톤 판정: 배포 앵커북 (앵커 base × 실제 m4×R05 오버레이)
## incumbent no_faith(=ret_orig × m4_weight_lag × beta_R05_V5) 대비 book-marginal.
## graduation HARD 3: PORT_t≥2.95 · oos_retention≥0.7 · calmar≥0.64 (배포북 기준).
## 앵커 base = C2(top-2 mega-cap 앵커@0.20 + score_eff 알파 18종). 동일 오버레이 양측 적용.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015

## ---- overlay panel (actual m4 × R05_V5 scalar + base ret_orig + regime) ----
ov <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))
ov <- ov[, .(return_ym, regime, ret_orig, m4=m4_weight_lag, r05=beta_R05_V5, ret_L5_V5)]
ov[, ovl := m4 * r05]
## verify: ret_orig*ovl ~ ret_L5_V5 (=no_faith incumbent monthly)
chk <- ov[is.finite(ret_orig)&is.finite(ret_L5_V5)]; cc <- cor(chk$ret_orig*chk$ovl, chk$ret_L5_V5)
PG("[PG] overlay scalar check cor(ret_orig*m4*r05, ret_L5_V5)=%.4f (1.0=정확)", cc)

## ---- my panels ----
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
dts <- sort(unique(sp$Date))

## build book: K mega-cap anchors @ anch_w + N-K score_eff alpha (EW fill)
build_book <- function(K=2L, anch_w=0.20, N=20L){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]; if(nrow(m)<N+2) next
    setorder(m,-size); anch<- if(K>0) m$Ticker[1:K] else character(0)
    ma<- if(K>0) m[!Ticker %in% anch] else m; setorder(ma,-score_eff); nfill<-N-K; sel<-ma[1:nfill]
    tk<-c(anch, sel$Ticker); w<-c(rep(anch_w,K), rep((1-K*anch_w)/nfill, nfill))
    rr<-c(if(K>0) m[match(anch,Ticker),Ret_1m] else numeric(0), sel$Ret_1m)
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk,w[match(allt,tk)],0);wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0);wp[is.na(wp)]<-0;turn<-sum(abs(wc-wp)) }
    out$ret[i]<-sum(w*rr)-turn*COST; prevw<-w; prevtk<-tk }
  out[is.finite(ret)]
}
base_recon <- build_book(K=0L); anchored <- build_book(K=2L)

## ---- align my Date -> overlay return_ym via ret_orig correlation ----
ov[, ym_key := return_ym]
align_join <- function(bk){ b<-copy(bk); b[, ym := format(Date,"%Y-%m")]
  best_off<-0; best_cor<--2
  for(off in -2:2){ b2<-copy(b); b2[, key := format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
    mm<-merge(b2, ov[,.(key=ym_key, ret_orig)], by="key"); if(nrow(mm)>100){ cc<-cor(mm$ret, mm$ret_orig); if(cc>best_cor){best_cor<-cc;best_off<-off} } }
  b[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
  list(off=best_off, cor=best_cor, dt=merge(b, ov[,.(key=ym_key, ovl, regime, ret_orig, ret_L5_V5)], by="key")) }
aj <- align_join(base_recon); PG("[PG] base align offset=%+d cor=%.3f", aj$off, aj$cor)
OFF <- aj$off
mapov <- function(bk){ b<-copy(bk); b[,ym:=format(Date,"%Y-%m")]; b[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(OFF),"%Y-%m")]
  merge(b, ov[,.(key=ym_key, ovl, regime, ret_orig, ret_L5_V5)], by="key") }
B <- mapov(base_recon); A <- mapov(anchored)
B[, ret_ov := ret * ovl]; A[, ret_ov := ret * ovl]      ## apply actual m4×R05 overlay
setorder(B, key); setorder(A, key)

## benchmark (cap-weighted) aligned to return_ym
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym:=format(Date,"%Y-%m")]; bmm<-bm[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]
addbm <- function(X){ merge(X, bmm[,.(key=ym, BM_Ret=bm_ret)], by="key") }
B<-addbm(B); A<-addbm(A)

gates <- function(X, tag){ X<-X[order(key)]; r<-X$ret_ov; d<-as.Date(paste0(X$key,"-01"))
  x<-xts(r, order.by=d); ta<-table.AnnualizedReturns(x, scale=12); sr<-as.numeric(ta[3,1])
  mdd<-as.numeric(maxDrawdown(x)); cagr<-as.numeric(Return.annualized(x,scale=12)); calmar<-cagr/mdd
  act<-r - X$BM_Ret; n<-length(act); mu<-mean(act); dm<-act-mu; g0<-sum(dm^2)/n; gs<-0
  for(L in 1:3){w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; pt<-mu/sqrt((g0+gs)/n)
  ir<-mu/sd(act)*sqrt(12)
  oos<-median(sapply(c(0.55,0.65,0.75),function(q){cut<-floor(n*q);(mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE)
  data.table(tag=tag, n=n, SR=sr, CAGR=cagr, MDD=mdd, Calmar=calmar, PORT_t=pt, IR=ir, oos_ret=oos) }
gB<-gates(B,"base_recon+overlay(≈incumbent)"); gA<-gates(A,"anchored+overlay(candidate)")

## book-marginal: paired NW-t of active diff (anchored - base), same overlay
mrg<-merge(A[,.(key, aA=ret_ov-BM_Ret)], B[,.(key, aB=ret_ov-BM_Ret)], by="key")
dd<-mrg$aA-mrg$aB; n<-length(dd); mu<-mean(dd); dm<-dd-mu; g0<-sum(dm^2)/n; gs<-0
for(L in 1:3){w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; bm_t<-mu/sqrt((g0+gs)/n)
res<-rbindlist(list(gB,gA))
res[, `:=`(SR=round(SR,3),CAGR=round(CAGR,3),MDD=round(MDD,3),Calmar=round(Calmar,3),PORT_t=round(PORT_t,3),IR=round(IR,3),oos_ret=round(oos_ret,3))]
print(res)
dIR <- gA$IR - gB$IR
PG("[PG] ===== 마일스톤 판정 =====")
PG("[PG] book-marginal: anchored vs base paired NW-t=%.3f  ΔIR=%.4f (≥0.05 게이트)", bm_t, dIR)
PG("[PG] candidate HARD3: PORT_t=%.3f(≥2.95) oos_ret=%.3f(≥0.7) Calmar=%.3f(≥0.64)", gA$PORT_t, gA$oos_ret, gA$Calmar)
MILE <- is.finite(gA$PORT_t)&gA$PORT_t>=2.95 & is.finite(gA$oos_ret)&gA$oos_ret>=0.7 & is.finite(gA$Calmar)&gA$Calmar>=0.64 & dIR>=0.05 & bm_t>1.5
PG("[PG] MILESTONE=%s (HARD3 배포북 통과 AND book-marginal ΔIR≥0.05 AND paired_t>1.5)", MILE)
fwrite(res, file.path(WD,"cycle5_milestone_results.csv"))
fwrite(data.table(book_marginal_paired_t=bm_t, dIR=dIR, milestone=MILE, align_off=OFF, align_cor=aj$cor, overlay_check_cor=cc), file.path(WD,"cycle5_milestone_verdict.csv"))
PG("[PG] DONE cycle5 milestone")
