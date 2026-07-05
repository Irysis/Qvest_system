## 사이클 7 — 앵커 + m4×R05 오버레이 (마일스톤 결정 측정)
## selection 레이어서 앵커는 oos 벽 뚫으나(oos 0.89) calmar 실패(0.58, 집중 MDD 38%).
## 오버레이는 낙폭 레버(프로덕션 calmar 1.94). → 프로덕션 오버레이 exposure e[t]=ret_L5/ret_orig 추출,
## anchored book에 적용해 calmar 회복+oos/PORT_t 유지 여부 측정. self-consistency + 정렬검증 포함.
## ★근사 경고: e[t]는 프로덕션 book beta 기반(앵커가 beta 변경) → 1차근사. exact는 앵커 beta로 오버레이 재유도 필요.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
PD   <- file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))
COST <- 0.0015

## ── production overlay period returns ──
bt <- readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds"))
pr <- as.data.table(bt$period_returns)
## realized_ym key
pr[, ym := as.character(realized_ym)]
## identify admitted overlay variant by calmar (target ~1.94)
vcol <- paste0("ret_L5_V", 1:5)
vstats <- rbindlist(lapply(vcol, function(v){ r<-pr[[v]]; r<-r[is.finite(r)]; rx<-xts(r, order.by=seq(as.Date("2005-01-01"), by="month", length.out=length(r)))
  data.table(V=v, sr=mean(r)/sd(r)*sqrt(12), calmar=as.numeric(Return.annualized(rx,scale=12))/as.numeric(maxDrawdown(rx))) }))
print(vstats)
admV <- vstats[which.max(calmar), V]
PG("[overlay] admitted variant (max calmar) = %s", admV)
## exposure e[t] = ret_L5_adm / ret_orig  (regime-cash: cash=0). clip [0, 1.2]. undefined(ret_orig~0) -> carry.
pr[, e := get(admV) / ret_orig]
pr[!is.finite(e) | abs(ret_orig) < 0.003, e := NA_real_]
pr[, e := nafill(nafill(e, "locf"), "nocb")]
pr[e < 0, e := 0]; pr[e > 1.2, e := 1.2]
## self-consistency: applying e to ret_orig recovers ret_L5_adm?
pr[, ret_L5_recon := e * ret_orig]
sc <- pr[is.finite(get(admV)) & is.finite(ret_L5_recon), cor(get(admV), ret_L5_recon)]
PG("[self-check] cor(ret_L5_adm, e*ret_orig) = %.4f (>0.98 = e derivation valid)", sc)
PG("[overlay] exposure e: mean=%.3f min=%.3f frac_cash(<0.5)=%.3f", mean(pr$e), min(pr$e), mean(pr$e<0.5))

## ── my anchored books (raw, pre-overlay) ──
sp <- as.data.table(read_parquet(file.path(PD,"02_holdings_universe/alpha_scores_r05_panel.parquet"))); sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE); dts <- sort(unique(sp$Date))
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2; for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]

build_raw <- function(K, anch_w, N=20L){
  prevfill<-NULL; prevtk<-NULL; prevw<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]; if(nrow(m)<N) next
    setorder(m,-size); anch<-if(K>0) m$Ticker[1:K] else character(0)
    ma<-m[!Ticker %in% anch]; setorder(ma,-score_eff); nfill<-N-K; sel<-ma[1:nfill]
    a_t<-sel$score_eff; names(a_t)<-sel$Ticker
    fw<-linear_tilt_to_penalty_qd(a_t, lambda=1.5, w_prev=prevfill, phi=3.0, lb=0, ub=0.20)
    tk<-c(anch, names(fw)); w<-c(rep(anch_w,K), as.numeric(fw)*(1-K*anch_w))
    rr<-c(m[match(anch,Ticker),Ret_1m], sel$Ret_1m[match(names(fw),sel$Ticker)])
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk,w[match(allt,tk)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[i]<-sum(w*rr)-turn*COST; prevfill<-fw; prevtk<-tk; prevw<-w }
  out[is.finite(ret)]
}
## align my raw book ym to production e ym (offset by matching C0_raw vs ret_orig)
C0raw <- build_raw(0,0.0); C0raw[, ym := format(Date,"%Y-%m")]
al_off<-0; al_cor<--2; for(off in 0:2){ tmp<-copy(C0raw); tmp[, key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(tmp, pr[,.(key=ym, ret_orig)], by="key"); if(nrow(mm)>50){cc<-cor(mm$ret, mm$ret_orig); if(cc>al_cor){al_cor<-cc; al_off<-off}} }
PG("[align] C0_raw vs production ret_orig: best offset=%d cor=%.4f", al_off, al_cor)

apply_overlay <- function(bk){ bk<-copy(bk); bk[, ym := format(Date,"%Y-%m")]
  bk[, key := format(as.Date(paste0(ym,"-01")) %m+% months(al_off),"%Y-%m")]
  bk<-merge(bk, pr[,.(key=ym, e)], by="key", all.x=TRUE); bk[is.na(e), e:=1]
  bk[, ret := ret * e]; bk[, .(Date, ret)] }

metr <- function(bk, tag){ pr2<-merge(bk, bench, by="Date"); if(nrow(pr2)<50) return(NULL)
  prt<-data.table(date=pr2$Date, ret_net=pr2$ret, frequency="monthly"); brt<-data.table(date=pr2$Date, benchmark_ret=pr2$BM_Ret, benchmark_id="KOSPI200")
  bc<-build_benchmark_compare(prt, brt, tag, tag, annualization_factor=12); gv<-function(n){v<-bc[metric_name==n,active_value]; if(length(v)) as.numeric(v[1]) else NA_real_}
  act<-pr2$ret-pr2$BM_Ret; n<-nrow(pr2)
  oos<-median(sapply(c(0.55,0.65,0.75),function(q){cut<-floor(n*q);(mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE)
  p2<-pr2[Date>=as.Date("2017-01-01")]; a2<-p2$ret-p2$BM_Ret; m2<-mean(a2); dm<-a2-m2; nn<-length(a2)
  g0<-sum(dm^2)/nn; gs<-0; for(L in 1:3){wt<-1-L/4; gs<-gs+2*wt*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn}; p17<-m2/sqrt((g0+gs)/nn)
  rx<-xts(pr2$ret, order.by=pr2$Date); cagr<-as.numeric(Return.annualized(rx, scale=12)); mdd<-as.numeric(maxDrawdown(rx))
  data.table(tag=tag, PORT_t=gv("Portfolio_Alpha_t_NW_lag3"), IR=gv("Information_Ratio"), oos_ret=oos, post2017_t=p17, cagr=cagr, mdd=mdd, calmar=if(mdd>0) cagr/mdd else NA_real_) }

res<-rbindlist(list(
  metr(C0raw, "C0_raw_noOverlay"),
  metr(apply_overlay(C0raw), "C0_overlay(=production)"),
  metr(build_raw(2,0.20), "C2_raw_noOverlay"),
  metr(apply_overlay(build_raw(2,0.20)), "C2_anchor+overlay"),
  metr(apply_overlay(build_raw(2,0.16)), "C2_w0.16+overlay"),
  metr(apply_overlay(build_raw(1,0.20)), "C1_anchor+overlay")
), fill=TRUE)
res[, pass_all := is.finite(PORT_t)&PORT_t>=2.95 & is.finite(oos_ret)&oos_ret>=0.7 & is.finite(calmar)&calmar>=0.64]
print(res[, .(tag, PORT_t=round(PORT_t,2), IR=round(IR,3), oos_ret=round(oos_ret,3), post2017_t=round(post2017_t,2), calmar=round(calmar,3), mdd=round(mdd,3), pass_all)])
c2o<-res[tag=="C2_anchor+overlay"]; c0o<-res[tag=="C0_overlay(=production)"]
PG("[BOOK-MARGINAL] C2+overlay IR=%.3f vs C0+overlay(=production) IR=%.3f  ΔIR=%.3f", c2o$IR, c0o$IR, c2o$IR-c0o$IR)
PG("[MILESTONE] C2_anchor+overlay pass_all(PORT>=2.95 ∧ oos>=0.7 ∧ calmar>=0.64) = %s", c2o$pass_all)
fwrite(res, file.path(WD,"cycle7_anchor_overlay_results.csv"))
