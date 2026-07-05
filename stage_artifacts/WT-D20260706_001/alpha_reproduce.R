## ============================================================================
## WT-D20260706_001 Alpha Research — mega-cap 앵커 구성 screening-tier 재현 + 강화
## 역할: alpha (α̂ fill 신호 상속 + 구성 thesis screening 증거). weight opt/Σ/forge X.
## 재현 대상: cycle2(mega-cap 갭 진단) + cycle3(base vs anchor A/B) + cycle4(적대검증).
## 강화: (a) 앵커 selection/비중 명시적 t-1 PIT 라벨 (b) placebo random-fill 40->150 draw
##       (c) canonical top-N EW A/B는 canonical_screen_bt 계약 경유(base) + 앵커는 build_benchmark_compare 라우팅
## 측정 = build_benchmark_compare 실측(NW lag-3). metric_type=canonical_screen. proxy 손계산 금지.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/WT-D20260706_001")
DISC <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
dir.create(WD, showWarnings=FALSE, recursive=TRUE)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
COST <- 0.0015  # 15bps one-way (turnover*cost)

## ---- 상속 알파 패널: score_eff = STR_1715 earnings/quality selection (신규 사냥 X) ----
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(DISC,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
## PIT: alpha score 1개월 지연본 (lag1 검증용). shift by Ticker, first-obs fallback.
sp[, score_lag := shift(score_eff,1), by=Ticker]; sp[is.na(score_lag), score_lag := score_eff]
## PIT: size(시총) 1개월 지연본 (앵커 selection은 t-1 size로 — C10 정합, 미래참조 방지)
sp[, size_lag := shift(size,1), by=Ticker]; sp[is.na(size_lag), size_lag := size]
dts <- sort(unique(sp$Date))
PG("[PIT] panel months=%d range=%s..%s  (앵커=size_lag t-1, fill=score_eff/score_lag)",
   length(dts), as.character(min(dts)), as.character(max(dts)))

## ---- benchmark: cap-weighted KOSPI200 (pinned). β-scan align offset (외부 시계열 정렬 필수). ----
bm <- as.data.table(read_parquet(file.path(DISC,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
best_off<-0; best_cor<--2
for(off in -1:3){ e2<-copy(ew); e2[,key:=format(as.Date(paste0(ym,"-01")) %m+% months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key"); if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret); if(cc>best_cor){best_cor<-cc;best_off<-off}} }
ew[, key := format(as.Date(paste0(ym,"-01")) %m+% months(best_off),"%Y-%m")]
bench_capw <- merge(ew[,.(Date,key)], bmm[,.(key=ym,BM_Ret=bm_ret)], by="key")[,.(Date,BM_Ret)]
bench_ew   <- ew[, .(Date, BM_Ret=ew)]   ## EW-universe as benchmark (mega-cap 갭 대조군)
PG("[PIT] bench(capw KOSPI200) align offset=%+d cor=%.3f  (IKS200 아닌지 재확인: 아래 BM ann.)", best_off, best_cor)
PG("[CHK] capw BM annualized ret=%.3f%% (KOSPI200 total return 범위)", (prod(1+bench_capw$BM_Ret)^(12/nrow(bench_capw))-1)*100)

## ============================================================================
## Part A — mega-cap 갭 진단 재현 (cycle2): 동일 score_eff 알파, capw vs EW 벤치
## ============================================================================
returns_dt <- sp[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]
oos_ret <- function(pr){ pr<-pr[order(date)]; n<-nrow(pr); act<-pr$ret_net-pr$benchmark_ret
  median(sapply(c(0.55,0.65,0.75), function(q){cut<-floor(n*q); (mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE) }
p17t <- function(pr){ p2<-pr[date>=as.Date("2017-01-01")]; a<-p2$ret_net-p2$benchmark_ret; mu<-mean(a); dm<-a-mu; n<-length(a)
  g0<-sum(dm^2)/n; gs<-0; for(L in 1:3){w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; mu/sqrt((g0+gs)/n) }
sc_eff <- sp[is.finite(score_eff), .(Date,Ticker,score=score_eff)]
gapA <- list()
for(bnm in c("capw","ew")){ bench <- if(bnm=="capw") bench_capw else bench_ew
  r <- canonical_screen_bt(sc_eff, returns_dt, bench, top_n=20L); pr<-r$period_returns
  gapA[[bnm]] <- data.table(variant="V0_earnings(score_eff)", bench=bnm, metric_type="canonical_screen",
    PORT_t=r$portfolio_alpha_t_nw_lag3, net_sr=r$net_sr, oos_ret=oos_ret(pr), post2017_t=p17t(pr))
  PG("[A] score_eff vs %s bench: PORT_t=%.3f net_sr=%.3f oos_ret=%.3f post2017_t=%.3f",
     bnm, r$portfolio_alpha_t_nw_lag3, r$net_sr, oos_ret(pr), p17t(pr)) }
gapA <- rbindlist(gapA); fwrite(gapA, file.path(WD,"partA_megacap_gap.csv"))

## ============================================================================
## Part B — base vs anchor A/B 재현 (cycle3). 앵커 = size_lag(t-1) top-K @ anch_w + score_eff fill.
## ============================================================================
build_book <- function(K, anch_w, N=20L, fillmode="alpha", seed=1L){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size_lag)]
    if(nrow(m) < N+2) next
    setorder(m,-size_lag); anch<- if(K>0) m$Ticker[1:K] else character(0)   ## PIT: t-1 size
    ma<- if(K>0) m[!Ticker %in% anch] else m; nfill<-N-K
    ord <- switch(fillmode,
      alpha    = order(-ma$score_eff),
      lagalpha = order(-ma$score_lag),
      bottom   = order(ma$score_eff),
      random   = order((((seq_len(nrow(ma))*7919L + i*104729L + seed*1299709L) %% 100000L))))
    sel<-ma[ord][1:nfill]
    tk<-c(anch, sel$Ticker); w<-c(rep(anch_w,K), rep((1-K*anch_w)/nfill, nfill))
    rr<-c(if(K>0) m[match(anch,Ticker),Ret_1m] else numeric(0), sel$Ret_1m)
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk)
      wc<-ifelse(allt%in%tk, w[match(allt,tk)],0); wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk, prevw[match(allt,prevtk)],0); wp[is.na(wp)]<-0; turn<-sum(abs(wc-wp)) }
    out$ret[i] <- sum(w*rr) - turn*COST; prevw<-w; prevtk<-tk }
  out[is.finite(ret)]
}
## turnover proxy (annual, for cost-aware reporting)
turn_annual <- function(K, anch_w, N=20L, fillmode="alpha"){
  prevtk<-NULL; prevw<-NULL; ts<-c()
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size_lag)]; if(nrow(m)<N+2) next
    setorder(m,-size_lag); anch<- if(K>0) m$Ticker[1:K] else character(0)
    ma<- if(K>0) m[!Ticker %in% anch] else m; nfill<-N-K; setorder(ma,-score_eff); sel<-ma[1:nfill]
    tk<-c(anch, sel$Ticker); w<-c(rep(anch_w,K), rep((1-K*anch_w)/nfill, nfill))
    if(!is.null(prevtk)){ allt<-union(tk,prevtk); wc<-ifelse(allt%in%tk,w[match(allt,tk)],0);wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0);wp[is.na(wp)]<-0; ts<-c(ts,sum(abs(wc-wp))) }
    prevtk<-tk; prevw<-w }
  mean(ts)*12 }
bench <- bench_capw
metr <- function(bk, tag){ pr<-merge(bk, bench, by="Date"); setnames(pr,"ret","ret_net")
  prt<-data.table(date=pr$Date, ret_net=pr$ret_net, frequency="monthly")
  brt<-data.table(date=pr$Date, benchmark_ret=pr$BM_Ret, benchmark_id="KOSPI200")
  bc<-build_benchmark_compare(prt, brt, "wt706","wt706", annualization_factor=12)
  gv<-function(n){v<-bc[metric_name==n,active_value]; if(length(v)) as.numeric(v[1]) else NA_real_}
  act<-pr$ret_net-pr$BM_Ret; n<-nrow(pr)
  oos<-median(sapply(c(0.55,0.65,0.75),function(q){cut<-floor(n*q);(mean(act[(cut+1):n])/sd(act[(cut+1):n]))/(mean(act[1:cut])/sd(act[1:cut]))}),na.rm=TRUE)
  p2<-pr[Date>=as.Date("2017-01-01")]; a2<-p2$ret_net-p2$BM_Ret; m2<-mean(a2); dm<-a2-m2; nn<-length(a2)
  g0<-sum(dm^2)/nn; gs<-0; for(L in 1:3){w<-1-L/4; gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn}; p17<-m2/sqrt((g0+gs)/nn)
  data.table(tag=tag, metric_type="canonical_screen", PORT_t=gv("Portfolio_Alpha_t_NW_lag3"), IR=gv("Information_Ratio"),
    net_sr=mean(act)/sd(act)*sqrt(12), oos_ret=oos, post2017_t=p17) }
specs <- list(C0_base_noanchor=list(K=0,w=0), C1_anchor1=list(K=1,w=0.20),
  C2_anchor2=list(K=2,w=0.20), C3_anchor3=list(K=3,w=0.20))
rowsB<-list()
for(nm in names(specs)){ s<-specs[[nm]]; bk<-build_book(s$K, s$w, 20L); r<-metr(bk,nm)
  r[, turnover_annual := turn_annual(s$K, s$w)]; rowsB[[nm]]<-r
  PG("[B] %s: PORT_t=%.3f IR=%.3f net_sr=%.3f oos_ret=%.3f post2017_t=%.3f TO=%.2f",
     nm, r$PORT_t, r$IR, r$net_sr, r$oos_ret, r$post2017_t, r$turnover_annual) }
resB<-rbindlist(rowsB); fwrite(resB, file.path(WD,"partB_base_vs_anchor.csv"))

## ============================================================================
## Part C — 적대검증 (cycle4 확장): alpha-edge / lag1-PIT / placebo(random-fill 150 draw)
## ============================================================================
port_t <- function(bk){ pr<-merge(bk,bench,by="Date"); a<-pr$ret-pr$BM_Ret; mu<-mean(a);dm<-a-mu;n<-length(a)
  g0<-sum(dm^2)/n;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; mu/sqrt((g0+gs)/n) }
port_t_win <- function(bk, from){ pr<-merge(bk,bench,by="Date"); pr<-pr[Date>=as.Date(from)]; a<-pr$ret-pr$BM_Ret
  mu<-mean(a);dm<-a-mu;n<-length(a);g0<-sum(dm^2)/n;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n}; mu/sqrt((g0+gs)/n) }
t_alpha  <- port_t(build_book(2L,0.20,20L,"alpha"))
t_lag    <- port_t(build_book(2L,0.20,20L,"lagalpha"))
t_bottom <- port_t(build_book(2L,0.20,20L,"bottom"))
t_alpha17<- port_t_win(build_book(2L,0.20,20L,"alpha"), "2017-01-01")
t_bot17  <- port_t_win(build_book(2L,0.20,20L,"bottom"), "2017-01-01")
PG("[C] Q1 alpha-edge full: alpha=%.3f bottom=%.3f Δ=%.3f", t_alpha, t_bottom, t_alpha-t_bottom)
PG("[C] Q1 alpha-edge 2017+: alpha=%.3f bottom=%.3f Δ=%.3f", t_alpha17, t_bot17, t_alpha17-t_bot17)
PG("[C] Q3 lag1 PIT: alpha=%.3f lagalpha=%.3f (graceful degrade=진짜)", t_alpha, t_lag)
NDRAW <- 150L
nullt <- sapply(1:NDRAW, function(s) port_t(build_book(2L,0.20,20L,"random", seed=s)))
p_emp <- mean(nullt >= t_alpha)
PG("[C] Q2 placebo(random-fill %d): null mean=%.3f sd=%.3f alpha=%.3f p=%.4f (앵커고정, fill만 랜덤)", NDRAW, mean(nullt), sd(nullt), t_alpha, p_emp)
resC <- data.table(t_alpha_full=t_alpha, t_bottom_full=t_bottom, alpha_edge_full=t_alpha-t_bottom,
  t_alpha_2017=t_alpha17, t_bottom_2017=t_bot17, alpha_edge_2017=t_alpha17-t_bot17,
  t_lagalpha=t_lag, placebo_ndraw=NDRAW, placebo_null_mean=mean(nullt), placebo_null_sd=sd(nullt), placebo_p=p_emp)
fwrite(resC, file.path(WD,"partC_adversarial.csv"))

## ---- 앵커 identity 확인: top-2 size_lag가 실제 삼성전자/SK하이닉스인가 (최근 12개월) ----
recent <- tail(dts, 12)
anch_id <- rbindlist(lapply(recent, function(D){ m<-sp[Date==D & is.finite(size_lag)]; setorder(m,-size_lag)
  data.table(Date=D, rank1=m$Ticker[1], rank2=m$Ticker[2], rank3=m$Ticker[3]) }))
fwrite(anch_id, file.path(WD,"anchor_identity_recent.csv"))
PG("[ID] 최근 앵커 top-2 (samples): %s", paste(unique(paste(anch_id$rank1, anch_id$rank2)), collapse=" | "))

PG("[DONE] alpha reproduce complete. artifacts -> %s", WD)
