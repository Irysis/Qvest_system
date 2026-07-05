## Self-Adversarial probe: anchored 개선이 (a)진짜 구성효과 vs (b)mega-cap beta 국면 harvest 판별
## C-1: anchored vs base 국면별 active-diff 분해 (paired NW-t 음수의 원인)
## C-2: 앵커를 삼성/하이닉스가 아닌 "임의 top-2 아무 종목"(3~4번째 cap)으로 대체 → 개선 유지되면 구성효과, 사라지면 특정종목 의존
## C-3: 앵커 없이 base에 삼성/하이닉스만 강제편입(20%cap) but fill=base top18 그대로 = anchored와 동일. 대신 앵커 비중을 벤치 실share(동적)로 = cap-proportional 앵커 → PORT_t
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/WT-D20260706_001")
DISC <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
COST <- 0.0015
sp <- as.data.table(read_parquet(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")))
sp[, Date := as.Date(Date)]
pm <- as.data.table(read_parquet(file.path(DISC,"panel_size_mom.parquet"))); pm[, Date := as.Date(Date)]
sp <- merge(sp, pm, by=c("Date","Ticker"), all.x=TRUE)
sp[, size_lag := shift(size,1), by=Ticker]; sp[is.na(size_lag), size_lag := size]
dts <- sort(unique(sp$Date))
bm <- as.data.table(read_parquet(file.path(DISC,"pinned_cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Date,"%Y-%m")]; bmm <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]
ew <- sp[is.finite(Ret_1m), .(ew=mean(Ret_1m)), by=Date]; ew[, ym := format(Date,"%Y-%m")]
bo<-0;bcv<--2; for(off in -1:3){e2<-copy(ew);e2[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(off),"%Y-%m")]
  mm<-merge(e2,bmm[,.(key=ym,bm_ret)],by="key");if(nrow(mm)>50){cc<-cor(mm$ew,mm$bm_ret);if(cc>bcv){bcv<-cc;bo<-off}}}
ew[,key:=format(as.Date(paste0(ym,"-01"))%m+%months(bo),"%Y-%m")]
bench<-merge(ew[,.(Date,key)],bmm[,.(key=ym,BM_Ret=bm_ret)],by="key")[,.(Date,BM_Ret)]
ptw <- function(a){ mu<-mean(a);dm<-a-mu;n<-length(a);g0<-sum(dm^2)/n;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):n]*dm[1:(n-L)])/n};mu/sqrt((g0+gs)/n) }

## anchor_rank: which cap-rank names to anchor (1:2 = 삼성/하이닉스; 3:4 = placebo 임의 top; NULL = base)
build_book <- function(anchor_ranks=1:2, anch_w=0.20, N=20L, capprop=FALSE){
  prevw<-NULL; prevtk<-NULL; out<-data.table(Date=dts, ret=NA_real_)
  for(i in seq_along(dts)){ D<-dts[i]
    m<-sp[Date==D & is.finite(score_eff) & is.finite(Ret_1m) & is.finite(size_lag)]; if(nrow(m)<N+5) next
    setorder(m,-size_lag)
    K <- length(anchor_ranks); anch <- if(K>0) m$Ticker[anchor_ranks] else character(0)
    ma <- if(K>0) m[!Ticker %in% anch] else m; nfill<-N-K; setorder(ma,-score_eff); sel<-ma[1:nfill]
    if(K>0){
      if(capprop){ aw <- m$size_lag[anchor_ranks]/sum(m$size_lag[anchor_ranks]) * (K*anch_w) } else aw <- rep(anch_w,K)
      tk<-c(anch,sel$Ticker); w<-c(aw, rep((1-sum(aw))/nfill, nfill))
      rr<-c(m[match(anch,Ticker),Ret_1m], sel$Ret_1m)
    } else { tk<-sel$Ticker; w<-rep(1/nfill,nfill); rr<-sel$Ret_1m }
    if(is.null(prevw)) turn<-1 else { allt<-union(tk,prevtk);wc<-ifelse(allt%in%tk,w[match(allt,tk)],0);wc[is.na(wc)]<-0
      wp<-ifelse(allt%in%prevtk,prevw[match(allt,prevtk)],0);wp[is.na(wp)]<-0;turn<-sum(abs(wc-wp)) }
    out$ret[i]<-sum(w*rr)-turn*COST; prevw<-w; prevtk<-tk }
  out[is.finite(ret)]
}
pt_of <- function(bk){ pr<-merge(bk,bench,by="Date"); ptw(pr$ret-pr$BM_Ret) }

anchored <- build_book(1:2, 0.20)
base     <- build_book(integer(0))
placebo_cap34 <- build_book(3:4, 0.20)     ## C-2: 3~4번째 cap 앵커 (삼성/하이닉스 아님)
capprop_anch  <- build_book(1:2, 0.20, capprop=TRUE)  ## C-3: cap-proportional 앵커

PG("[CH-C2] 임의 top(3~4위 cap) 앵커 PORT_t=%.3f vs 삼성/하이닉스 앵커 %.3f vs base %.3f",
   pt_of(placebo_cap34), pt_of(anchored), pt_of(base))
PG("[CH-C3] cap-proportional 앵커 PORT_t=%.3f (20%%flat=%.3f)", pt_of(capprop_anch), pt_of(anchored))

## C-1: paired active-diff 국면 분해 — 어느 시기가 음수 paired-t 만드는가
prA<-merge(anchored,bench,by="Date"); prB<-merge(base,bench,by="Date")
mrg<-merge(prA[,.(Date,aA=ret-BM_Ret)], prB[,.(Date,aB=ret-BM_Ret)], by="Date"); mrg[,dd:=aA-aB]
for(seg in list(c("2004-01-01","2016-12-31"), c("2017-01-01","2020-12-31"), c("2021-01-01","2026-12-31"))){
  s<-mrg[Date>=as.Date(seg[1]) & Date<=as.Date(seg[2])]
  PG("[CH-C1] %s..%s: paired diff mean=%+.4f NW-t=%+.3f (n=%d) anchoredActive=%.4f baseActive=%.4f",
     substr(seg[1],1,7), substr(seg[2],1,7), mean(s$dd), ptw(s$dd), nrow(s), mean(s$aA), mean(s$aB)) }

## C-1b: anchored SR가 base보다 높은데 paired-t 음수인 이유 = anchored가 변동성도 줄이나?
PG("[CH-C1b] anchored active sd=%.4f base active sd=%.4f (앵커가 tracking-vol 축소 => SR 상승, 초과수익 자체는 base가 클 수도)",
   sd(mrg$aA), sd(mrg$aB))
PG("[CH-C1b] anchored mean active=%.4f base mean active=%.4f", mean(mrg$aA), mean(mrg$aB))

res<-data.table(anchored_pt=pt_of(anchored), base_pt=pt_of(base),
  placebo_cap34_pt=pt_of(placebo_cap34), capprop_pt=pt_of(capprop_anch),
  anchored_active_mean=mean(mrg$aA), base_active_mean=mean(mrg$aB),
  anchored_active_sd=sd(mrg$aA), base_active_sd=sd(mrg$aB))
fwrite(res, file.path(WD,"partE_challenge_probe.csv"))
PG("[DONE] challenge probe")
