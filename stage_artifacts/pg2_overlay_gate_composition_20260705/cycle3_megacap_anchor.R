## 자가발전 사이클 3 — mega-cap 앵커 구성 (사이클2 진단의 직접 레버)
## 진단: post-2017 벽 = cap-weighted 벤치를 mega-cap이 지배 → 분산북이 못 따라감.
## 레버: 벤치 지배 top-K cap 종목을 20% cap에 앵커 + 나머지를 알파로 채워 갭 축소.
##   (현 북은 earnings로 선택해 삼성/하이닉스 저비중 = 갭의 원천)
## 측정: build_benchmark_compare 권위 PORT_t + oos + post-2017. vs cap-weighted.
## 발견: PORT_t≥2.95 AND oos_ret≥0.7. 특히 post-2017 개선이 핵심.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015

sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(WD,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
dts <- sort(unique(sp$Date))

## cap-weighted benchmark aligned
bm <- as.data.table(read_parquet(file.path(WD,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2; for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]

## build book: anchor top-K cap names at anch_w each, fill rest EW with alpha top-(20-K)
## regime_anchor: only anchor when trailing mega-cap momentum > 0 (top-cap leading)
build_book <- function(K, anch_w, N=20L, regime=FALSE){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  ## trailing mega-cap leadership: 12m return of top-3 cap vs EW (per month)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size)]
    if(nrow(m)<N) next
    setorder(m,-size); anch<-if(K>0) m$Ticker[1:K] else character(0)
    do_anchor <- TRUE
    if(regime && K>0){ ## anchor only if top-K cap 12m mom > universe median mom
      tm <- mean(m$mom[1:K], na.rm=TRUE); do_anchor <- is.finite(tm) && tm > median(m$mom, na.rm=TRUE) }
    ma <- m[!Ticker %in% (if(do_anchor) anch else character(0))]
    setorder(ma,-score_eff); nfill <- N - (if(do_anchor) K else 0L); sel<-ma[1:nfill]
    if(do_anchor && K>0){ w_anchor <- rep(anch_w, K); rem <- 1 - sum(w_anchor)
      tk <- c(anch, sel$Ticker); w <- c(w_anchor, rep(rem/nfill, nfill))
      rr <- c(m[match(anch,Ticker), Ret_1m], sel$Ret_1m)
    } else { tk <- sel$Ticker; w <- rep(1/nfill, nfill); rr <- sel$Ret_1m }
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk, w[match(allt,tk)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk, prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[i] <- sum(w*rr) - turn*COST; prevw<-w; prevtk<-tk }
  out[is.finite(ret)]
}
metr <- function(bk, tag){ pr<-merge(bk, bench, by.x="Date", by.y="Date"); setnames(pr,"ret","ret_net")
  prt<-data.table(date=pr$Date, ret_net=pr$ret_net, frequency="monthly")
  brt<-data.table(date=pr$Date, benchmark_ret=pr$BM_Ret, benchmark_id="KOSPI200")
  bc<-build_benchmark_compare(prt, brt, "c3","c3", annualization_factor=12)
  gv<-function(n){v<-bc[metric_name==n,active_value]; if(length(v)) as.numeric(v[1]) else NA_real_}
  act<-pr$ret_net-pr$BM_Ret; n<-nrow(pr)
  oos<-median(sapply(c(0.55,0.65,0.75),function(q){cut<-floor(n*q);(mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE)
  p2<-pr[Date>=as.Date("2017-01-01")]; a2<-p2$ret_net-p2$BM_Ret; m2<-mean(a2); dm<-a2-m2; nn<-length(a2)
  g0<-sum(dm^2)/nn; gs<-0; for(L in 1:3){w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn}; p17<-m2/sqrt((g0+gs)/nn)
  data.table(tag=tag, PORT_t=gv("Portfolio_Alpha_t_NW_lag3"), IR=gv("Information_Ratio"),
    net_sr=mean(act)/sd(act)*sqrt(12), oos_ret=oos, post2017_t=p17) }

specs <- list(
  C0_no_anchor      = list(K=0, w=0),
  C1_anchor1_0.20   = list(K=1, w=0.20),
  C2_anchor2_0.20   = list(K=2, w=0.20),
  C3_anchor3_0.20   = list(K=3, w=0.20),
  C4_anchor2_regime = list(K=2, w=0.20, regime=TRUE)
)
rows<-list()
for(nm in names(specs)){ s<-specs[[nm]]; bk<-build_book(s$K, s$w, 20L, isTRUE(s$regime)); r<-metr(bk,nm); rows[[nm]]<-r
  PG("[PG] %s: PORT_t=%.3f IR=%.3f net_sr=%.3f oos_ret=%.3f post2017_t=%.3f", nm, r$PORT_t, r$IR, r$net_sr, r$oos_ret, r$post2017_t) }
res<-rbindlist(rows); res[, DISCOVERY := is.finite(PORT_t)&PORT_t>=2.95&is.finite(oos_ret)&oos_ret>=0.7]
print(res[, .(tag, PORT_t=round(PORT_t,3), IR=round(IR,3), net_sr=round(net_sr,3), oos_ret=round(oos_ret,3), post2017_t=round(post2017_t,3), DISCOVERY)])
fwrite(res, file.path(WD,"cycle3_anchor_results.csv"))
PG("[PG] DONE cycle3. discoveries=%d", sum(res$DISCOVERY,na.rm=TRUE))
