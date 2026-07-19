## ============================================================================
## WT-014 — 실 STR_1715 book SELECTION 고정, WEIGHTING A/B (LinearTilt vs ERC vs inv-vol vs EW)
##   → book-marginal 위험조정(calmar/IR/MDD) 개선 여부 실측. (도훈 배포 결정재료, book 변경 아님)
##
## 실 book = STR_1715_on_M4gAE_R05_noLayer4_PG2:
##   selection = alpha_scores(WT_D20260425_010) score_eff top-N + liq 2e8 (t-1)
##   weighting = LinearTilt(.tilt lam=1.5)  [교체 대상]
##   overlay   = m4 × β_R05  [고정, 전 weighting 동일 적용 — layer5 faith 패널서 소싱]
##   book ret  = β_R05 × m4 × ret_orig − |Δβ_R05|×15bps  (recompute_bt_noLayer4_clean.R 정의)
##   book IR   = 1.4160 (SANITY 대조), PORT_t 6.214, calmar 1.941, MDD 0.233 (269m)
##
## PIT: cov/vol = trailing DAILY (rawdata Ret, Date < anchor = 홀딩월 시작 전, C5). lag1 스트레스 + placebo.
## metric_type = weighted (계약 build_benchmark_compare 경유 PORT_t/IR — self-synth 금지).
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics); library(sandwich); library(lmtest)
})
setDTthreads(1); options(scipen=999)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/portfolio/hrp_core.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
OUT <- file.path(ROOT,"04_Research/method_frontier/wt014_realbook_weighting"); dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
LOG <- file(file.path(OUT,"run.log.txt"), open="wt"); sink(LOG, split=TRUE)
set.seed(20260719)
t0 <- Sys.time()
UB <- 0.20; LIQ <- 2e8; LAMBDA <- 1.5; COST <- 0.0015; COV_WIN_D <- 252L
cat("=== WT-014 realbook weighting A/B ===\n")

## ---------- weight functions ----------
.norm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt <- function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}
cap_renorm <- function(w, cap=UB, iter=100){ w[!is.finite(w)]<-0; w[w<0]<-0; s<-sum(w); if(s<=0) return(w); w<-w/s
  for(i in seq_len(iter)){ over<-w>cap+1e-12; if(!any(over)) break; excess<-sum(w[over]-cap); w[over]<-cap
    under<-(!over)&(w>0); if(!any(under)) break; w[under]<-w[under]+excess*w[under]/sum(w[under]) }
  s<-sum(w); if(s>0) w/s else w }
w_erc <- function(S, ub=UB, iter=2000, tol=1e-9){ p<-ncol(S); dg<-diag(S); dg[dg<=0]<-min(dg[dg>0],na.rm=TRUE)
  w<-1/sqrt(dg); w<-w/sum(w)
  for(k in seq_len(iter)){ mrc<-as.numeric(S%*%w); rc<-w*mrc; tgt<-mean(rc)
    wn<-w*(tgt/pmax(rc,1e-16))^0.5; wn<-wn/sum(wn); if(max(abs(wn-w))<tol){w<-wn;break}; w<-wn }
  setNames(cap_renorm(w,ub), colnames(S)) }
w_invvol <- function(sig, ub=UB){ v<-1/pmax(sig,1e-12); setNames(cap_renorm(v/sum(v),ub), names(sig)) }
w_ew <- function(nm) setNames(rep(1/length(nm),length(nm)), nm)

## ---------- load ----------
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"),
                    col_select=c("Date","Ticker","score_eff","Ret_1m")))
ap[, Date:=as.Date(Date)]; ap <- ap[!is.na(score_eff)]
ap[, sig_ym := year(Date)*100L + month(Date)]
setkey(ap, Date)
cat(sprintf("[ap] rows=%d dates=%d %s~%s\n", nrow(ap), uniqueN(ap$Date), as.character(min(ap$Date)), as.character(max(ap$Date))))

raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),
                     col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]
rawTV <- raw[, .(Date,Ticker,TV)]; setkey(rawTV, Date)
setkey(raw, Ticker, Date)

L5 <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
L5[, anchor_date:=as.Date(anchor_date)]
L5[, ret_ym_int := as.integer(gsub("-","",return_ym))]
L5[, real_ym_int := as.integer(gsub("-","",realized_ym))]
setorder(L5, real_ym_int)
L5[, dR05 := abs(beta_R05 - shift(beta_R05,1,fill=1.0))]
cat(sprintf("[L5] rows=%d return_ym %d~%d realized_ym %d~%d\n", nrow(L5), min(L5$ret_ym_int),max(L5$ret_ym_int),min(L5$real_ym_int),max(L5$real_ym_int)))

BM <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
BM[, Date:=as.Date(Date)]; BM <- BM[is.finite(BM_Ret)]; setorder(BM,Date)
BMx <- xts(BM$BM_Ret, order.by=BM$Date)
a <- L5$anchor_date; bmw <- rep(NA_real_, nrow(L5))
for(i in 2:nrow(L5)){ seg <- BMx[index(BMx)>a[i-1] & index(BMx)<=a[i]]; if(nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
bmw[1] <- 0; L5[, bmw := bmw]
L5key <- L5[, .(ret_ym_int, anchor_date, beta_R05, m4, dR05, bmw, real_ym_int, ret_orig)]

## ---------- precompute LIQ_SET (once) ----------
sig_dates <- sort(unique(ap$Date))
cat(sprintf("[liq] precomputing eligibility for %d signal dates...\n", length(sig_dates)))
LIQ_SET <- list()
for(s in sig_dates){
  wtv <- rawTV[Date>=s-30L & Date<s, .(ATV=mean(TV,na.rm=TRUE)), by=Ticker]
  LIQ_SET[[as.character(year(s)*100L+month(s))]] <- wtv[ATV>=LIQ, Ticker]
}
cat(sprintf("[liq] done (%.1f min)\n", as.numeric(difftime(Sys.time(),t0,units="mins"))))

## ---------- month arithmetic ----------
ym_add <- function(sy, k){ y<-sy%/%100L; m<-sy%%100L; tot<-(y*12L+(m-1L))+k; (tot%/%12L)*100L + (tot%%12L)+1L }

## ---------- precompute PICKS per (N, L5-join offset) ----------
## Ret_1m@(ap month M) is realized in month M+1 (raw close-to-close, 진단 diag_ret1m). The book ret_orig/overlay/
## benchmark live in L5 rows; the matching L5 row (same holding period as recon return) is found by offset scan
## (parity corr max). We JOIN L5 at real_ym == sy+OFF and use that row's β_R05/m4/bmw/anchor — within an L5 row
## ret_orig·bmw·β_R05·m4 are the SAME holding period (book construction), so a corr-max match aligns everything.
make_picks <- function(N, OFF=0L){
  P <- list()
  for(s in sig_dates){
    sy <- year(s)*100L+month(s)
    l5r <- L5key[real_ym_int==ym_add(sy,OFF)]; if(nrow(l5r)==0) next
    elig <- LIQ_SET[[as.character(sy)]]
    pnl <- ap[Date==s][Ticker %in% elig & !is.na(Ret_1m)]
    if(nrow(pnl) < N) next
    setorder(pnl,-score_eff); pk <- pnl[seq_len(N)]
    ## cov cutoff = SIGNAL-derived (offset-independent, PIT-clean): Ret_1m@sy realized in month sy+1 → weights
    ## formed at start of holding month sy+1 using daily data < that date (through end of sy). cut_lag1 = 1mo staler.
    d_hold  <- as.Date(sprintf("%04d-%02d-01", ym_add(sy,1)%/%100L, ym_add(sy,1)%%100L))
    d_lag1  <- as.Date(sprintf("%04d-%02d-01", sy%/%100L, sy%%100L))
    P[[as.character(sy)]] <- list(sy=sy, real_ym=l5r$real_ym_int[1], anchor=l5r$anchor_date[1],
        cut_cov=d_hold, cut_cov_lag1=d_lag1,
        beta_R05=l5r$beta_R05[1], m4=l5r$m4[1], dR05=l5r$dR05[1], bmw=l5r$bmw[1], ret_orig=l5r$ret_orig[1],
        tk=pk$Ticker, score=setNames(pk$score_eff,pk$Ticker), ret=setNames(pk$Ret_1m,pk$Ticker))
  }
  P }

## ---------- cov cache for a picks set (per month, over its tickers, cutoff Date<anchor) ----------
cov_of <- function(tickers, cut){
  sub <- raw[.(tickers)][Date<cut & Date>=cut-460L, .(Date,Ticker,Ret)]
  W <- dcast(sub, Date~Ticker, value.var="Ret"); M <- as.matrix(W[,-1,drop=FALSE])
  keep <- colSums(!is.na(M)) >= 120L; M <- M[, keep, drop=FALSE]
  M <- tail(M[complete.cases(M),,drop=FALSE], COV_WIN_D)
  if(ncol(M)<5L || nrow(M)<60L) return(NULL)
  list(S=.get_cor_cov(M,"lw_nls")$cov, tk=colnames(M)) }

## ---------- build bare monthly series for a weighting method from precomputed PICKS ----------
build_series <- function(PICKS, method, COVC=NULL){
  rows <- list(); prevw <- NULL
  for(nm in names(PICKS)){
    P <- PICKS[[nm]]; tk <- P$tk; sc <- P$score; rr <- P$ret
    if(method=="EW"){ w <- w_ew(tk)
    } else if(method=="LinearTilt"){ w <- setNames(.tilt(sc), tk)
    } else if(method %in% c("ERC","invvol")){
      cv <- COVC[[nm]]; if(is.null(cv)) next
      if(method=="ERC") w <- w_erc(cv$S) else w <- w_invvol(setNames(sqrt(diag(cv$S)), cv$tk))
      rr <- rr[cv$tk]
    } else if(method=="placebo"){ g <- rgamma(length(tk),1); w <- setNames(cap_renorm(g/sum(g),UB),tk) }
    w <- w[!is.na(w) & w>0]; if(!length(w)) next; rr <- rr[names(w)]; if(anyNA(rr)) rr[is.na(rr)]<-0
    if(is.null(prevw)) trad <- sum(abs(w)) else { un<-union(names(w),names(prevw))
      a1<-setNames(rep(0,length(un)),un); b1<-a1; a1[names(w)]<-w; b1[names(prevw)]<-prevw; trad<-sum(abs(a1-b1)) }
    net <- sum(w*rr) - trad*COST
    rows[[length(rows)+1L]] <- data.table(sig_ym=P$sy, real_ym=P$real_ym, anchor=P$anchor,
        beta_R05=P$beta_R05, m4=P$m4, dR05=P$dR05, bmw=P$bmw, ret_orig=P$ret_orig, ret_net_bare=net, n=length(w))
    prevw <- w
  }
  rbindlist(rows) }

## ---------- metrics via contract (bare & book) ----------
RID<-"WT014"; SID<-"WT014"
metric_block <- function(dt, overlay){
  d <- copy(dt); setorder(d, real_ym)
  d[, ret := if(overlay) beta_R05*m4*ret_net_bare - dR05*COST else ret_net_bare]
  pr <- data.table(run_id=RID, strategy_id=SID, date=d$anchor, frequency="monthly",
        ret_gross=d$ret, ret_net=d$ret, risk_free_ret=0, excess_ret_net=d$ret,
        turnover=NA_real_, cost_ret=0, cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
  br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=d$anchor,
        benchmark_ret=d$bmw, benchmark_nav=cumprod(1+ifelse(is.na(d$bmw),0,d$bmw)),
        risk_free_ret=0, benchmark_excess_ret=d$bmw, frequency="monthly")
  bc <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
  gv <- function(nm){ v<-bc[metric_name==nm]$active_value; if(length(v)) as.numeric(v[1]) else NA_real_ }
  gvs<- function(nm){ v<-bc[metric_name==nm]$strategy_value; if(length(v)) as.numeric(v[1]) else NA_real_ }
  x <- xts(d$ret, order.by=d$anchor); cagr <- as.numeric(Return.annualized(x,scale=12,geometric=TRUE))
  mdd <- as.numeric(maxDrawdown(x)); active <- d$ret - d$bmw
  list(n=nrow(d), IR=gv("Information_Ratio"), PORT_t=gvs("Portfolio_Alpha_t_NW_lag3"), alpha_ann=gvs("Alpha_Annualized"),
       cagr=cagr, mdd=mdd, calmar=cagr/mdd, net_sr=as.numeric(mean(d$ret)/sd(d$ret)*sqrt(12)),
       active_sr=as.numeric(mean(active)/sd(active)*sqrt(12)), series=d[,.(real_ym,anchor,ret,bmw,active=ret-bmw)]) }

## ============================================================================
## STAGE 1 — SANITY: LinearTilt parity vs L5 ret_orig + book IR 1.416
## ============================================================================
cat("\n--- STAGE 1: alignment / SANITY (LinearTilt) ---\n")
## (0) ground-truth reference: book's OWN ret_orig through the SAME harness/benchmark → must reproduce book 1.416
actual_dt <- L5[real_ym_int>=200402, .(real_ym=real_ym_int, anchor=anchor_date, beta_R05, m4, dR05, bmw, ret_orig, ret_net_bare=ret_orig)]
act_bare <- metric_block(actual_dt, FALSE); act_book <- metric_block(actual_dt, TRUE)
cat(sprintf("[HARNESS-SANITY] ACTUAL book (from L5 ret_orig directly): BOOK IR=%.4f (book 1.4160) PORT_t=%.3f (6.214) calmar=%.3f (1.941) MDD=%.4f (0.2329) n=%d\n",
    act_book$IR, act_book$PORT_t, act_book$calmar, act_book$mdd, act_book$n))
cat(sprintf("                 ACTUAL bare (ret_orig, no overlay):     BARE IR=%.4f PORT_t=%.3f calmar=%.3f MDD=%.4f\n",
    act_bare$IR, act_bare$PORT_t, act_bare$calmar, act_bare$mdd))
## (1) reconstruction: scan N x L5-join offset, maximize LinearTilt parity vs ret_orig(joined row = same holding period)
best <- NULL
for(N in c(20L,25L)) for(OFF in 0:3){
  PK <- make_picks(N, OFF); if(length(PK)<50L) next
  lt <- build_series(PK,"LinearTilt"); setorder(lt, real_ym)
  cc <- cor(lt$ret_net_bare, lt$ret_orig, use="complete.obs")
  cat(sprintf("  N=%d OFF=%d  corr(recon LT, ret_orig[joined])=%.4f  n=%d\n", N, OFF, cc, nrow(lt)))
  if(is.null(best) || (is.finite(cc)&&cc>best$cc)) best <- list(N=N, OFF=OFF, cc=cc, lt=lt, PK=PK)
}
N_BOOK <- best$N; OFF_BOOK <- best$OFF; PICKS <- best$PK
cat(sprintf("[SANITY] chosen N_BOOK=%d L5_OFF=%d (best LinearTilt parity corr=%.4f)\n", N_BOOK, OFF_BOOK, best$cc))
lt_book <- metric_block(best$lt, TRUE); lt_bare <- metric_block(best$lt, FALSE)
cat(sprintf("[SANITY] recon LinearTilt BARE: IR=%.4f PORT_t=%.3f calmar=%.3f MDD=%.4f (actual bare %.4f/%.3f/%.3f/%.4f)\n",
    lt_bare$IR, lt_bare$PORT_t, lt_bare$calmar, lt_bare$mdd, act_bare$IR, act_bare$PORT_t, act_bare$calmar, act_bare$mdd))
cat(sprintf("[SANITY] recon LinearTilt BOOK: IR=%.4f (book 1.4160 / actual %.4f) PORT_t=%.3f (6.214/%.3f) calmar=%.3f (1.941/%.3f) MDD=%.4f (0.2329/%.4f) n=%d\n",
    lt_book$IR, act_book$IR, lt_book$PORT_t, act_book$PORT_t, lt_book$calmar, act_book$calmar, lt_book$mdd, act_book$mdd, lt_book$n))

## precompute cov cache once for chosen picks (ERC/invvol share it). SIGNAL-derived cutoff (PIT-clean, no look-ahead).
cat("[cov] building daily-cov cache (clean cutoff = holding-month start) + lag1 (staler)...\n")
COVC <- list(); COVC_lag1 <- list()
for(nm in names(PICKS)){ P<-PICKS[[nm]]
  COVC[[nm]]      <- tryCatch(cov_of(P$tk, P$cut_cov),      error=function(e) NULL)
  COVC_lag1[[nm]] <- tryCatch(cov_of(P$tk, P$cut_cov_lag1), error=function(e) NULL) }
cat(sprintf("[cov] months with cov=%d / %d (%.1f min)\n", sum(!sapply(COVC,is.null)), length(COVC), as.numeric(difftime(Sys.time(),t0,units="mins"))))

## ============================================================================
## STAGE 2 — A/B 4 weightings @ N_BOOK
## ============================================================================
cat("\n--- STAGE 2: weighting A/B @ N=", N_BOOK, " ---\n", sep="")
methods <- c("LinearTilt","ERC","invvol","EW")
bare_series <- list(); AB <- list()
for(mth in methods){
  bs <- if(mth=="LinearTilt") best$lt else build_series(PICKS, mth, COVC)
  bare_series[[mth]] <- bs
  mb <- metric_block(bs, FALSE); bk <- metric_block(bs, TRUE)
  AB[[mth]] <- list(method=mth, n_bare=mb$n, n_book=bk$n,
    bare=list(IR=mb$IR,PORT_t=mb$PORT_t,calmar=mb$calmar,mdd=mb$mdd,cagr=mb$cagr,net_sr=mb$net_sr),
    book=list(IR=bk$IR,PORT_t=bk$PORT_t,calmar=bk$calmar,mdd=bk$mdd,cagr=bk$cagr,net_sr=bk$net_sr,alpha_ann=bk$alpha_ann))
  cat(sprintf("  %-11s | BARE calmar=%.3f PORT_t=%.3f MDD=%.3f IR=%.3f | BOOK calmar=%.3f PORT_t=%.3f MDD=%.4f IR=%.4f (n=%d)\n",
      mth, mb$calmar, mb$PORT_t, mb$mdd, mb$IR, bk$calmar, bk$PORT_t, bk$mdd, bk$IR, bk$n))
}

## common-month re-measure (fair ΔIR)
common_real <- Reduce(intersect, lapply(methods, function(m) bare_series[[m]]$real_ym))
cat(sprintf("\n[common months] %d\n", length(common_real)))
book_common <- list()
for(mth in methods){ bk <- metric_block(bare_series[[mth]][real_ym %in% common_real], TRUE)
  book_common[[mth]] <- list(IR=bk$IR,PORT_t=bk$PORT_t,calmar=bk$calmar,mdd=bk$mdd,cagr=bk$cagr,net_sr=bk$net_sr) }
IR_LT <- book_common[["LinearTilt"]]$IR; CAL_LT <- book_common[["LinearTilt"]]$calmar
cat("[book-marginal on common months, vs LinearTilt book]\n")
for(mth in methods){ bc<-book_common[[mth]]
  cat(sprintf("  %-11s | BOOK calmar=%.4f PORT_t=%.3f MDD=%.4f IR=%.4f  dIR=%+.4f dcalmar=%+.4f\n",
      mth, bc$calmar, bc$PORT_t, bc$mdd, bc$IR, bc$IR-IR_LT, bc$calmar-CAL_LT)) }

## ---------- PIT lag1 stress: recompute weights from 1-month-STALER cov (proper weight-staleness test) ----------
## clean improvement should persist under staler cov; collapse => fragile/look-ahead-sensitive (cov freshness artifact).
cat("\n--- PIT lag1 stress (ERC/invvol weights from cov 1mo staler) ---\n")
lag1 <- list()
for(mth in c("ERC","invvol")){
  bs <- build_series(PICKS, mth, COVC_lag1); bs <- bs[real_ym %in% common_real]; bk <- metric_block(bs, TRUE)
  lag1[[mth]] <- list(calmar=bk$calmar, IR=bk$IR, dcalmar_vs_clean=bk$calmar-book_common[[mth]]$calmar)
  cat(sprintf("  %-11s staler-cov BOOK calmar=%.4f IR=%.4f (clean-cov calmar %.4f, LinearTilt %.4f)\n",
      mth, bk$calmar, bk$IR, book_common[[mth]]$calmar, CAL_LT)) }

## ---------- placebo random weights ----------
cat("\n--- placebo: random capped weights book (100 draws, common months) ---\n")
NPERM <- 100L; pl_cal <- numeric(NPERM); pl_ir <- numeric(NPERM)
for(p in seq_len(NPERM)){ bs <- build_series(PICKS,"placebo"); bs <- bs[real_ym %in% common_real]
  bk <- metric_block(bs, TRUE); pl_cal[p]<-bk$calmar; pl_ir[p]<-bk$IR }
plac <- list(calmar=list(p50=median(pl_cal), p95=quantile(pl_cal,.95,names=FALSE),
    erc_rank=mean(pl_cal<book_common[["ERC"]]$calmar), invvol_rank=mean(pl_cal<book_common[["invvol"]]$calmar),
    lineartilt_rank=mean(pl_cal<CAL_LT)),
  ir=list(p50=median(pl_ir), p95=quantile(pl_ir,.95,names=FALSE), lineartilt_rank=mean(pl_ir<IR_LT)))
cat(sprintf("  placebo calmar p50=%.4f p95=%.4f | ERC rank=%.2f invvol rank=%.2f LinearTilt rank=%.2f\n",
    plac$calmar$p50, plac$calmar$p95, plac$calmar$erc_rank, plac$calmar$invvol_rank, plac$calmar$lineartilt_rank))
cat(sprintf("  placebo IR p50=%.4f p95=%.4f | LinearTilt rank=%.2f\n", plac$ir$p50, plac$ir$p95, plac$ir$lineartilt_rank))

## ---------- verdict ----------
erc<-book_common[["ERC"]]; iv<-book_common[["invvol"]]
dIR_erc<-erc$IR-IR_LT; dIR_iv<-iv$IR-IR_LT; dcal_erc<-erc$calmar-CAL_LT; dcal_iv<-iv$calmar-CAL_LT
improves <- (dIR_erc>=0.05 && dcal_erc>0) || (dIR_iv>=0.05 && dcal_iv>0)
verdict <- if(improves) "IMPROVES_BOOK" else "NO_IMPROVEMENT_DEGRADES"

summary <- list(wt="WT-014_realbook_weighting", date=format(Sys.Date()), metric_type="weighted",
  question="실 STR_1715 book SELECTION 고정, WEIGHTING LinearTilt->ERC/inv-vol/EW 시 book 위험조정(calmar/IR/MDD) 개선 + book-marginal dIR",
  book_ref=list(strategy="STR_1715_on_M4gAE_R05_noLayer4_PG2", IR=1.4160, PORT_t=6.214, calmar=1.941, mdd=0.2329, n=269),
  N_BOOK=N_BOOK, L5_join_offset=OFF_BOOK, sanity_lineartilt_parity_corr=round(best$cc,4),
  harness_sanity_actual_book=list(IR=round(act_book$IR,4),PORT_t=round(act_book$PORT_t,3),calmar=round(act_book$calmar,3),mdd=round(act_book$mdd,4),n=act_book$n,
      note="L5 ret_orig 직접 → 계약 harness. book 1.4160/6.214/1.941/0.2329 재현 = harness+benchmark 검증"),
  actual_bare=list(IR=round(act_bare$IR,4),PORT_t=round(act_bare$PORT_t,3),calmar=round(act_bare$calmar,3),mdd=round(act_bare$mdd,4)),
  sanity_recon_bare=list(IR=round(lt_bare$IR,4),PORT_t=round(lt_bare$PORT_t,3),calmar=round(lt_bare$calmar,3),mdd=round(lt_bare$mdd,4)),
  sanity_recon_book=list(IR=round(lt_book$IR,4),PORT_t=round(lt_book$PORT_t,3),calmar=round(lt_book$calmar,3),mdd=round(lt_book$mdd,4),n=lt_book$n),
  n_common_months=length(common_real),
  weightings=lapply(AB, function(x) list(method=x$method, n_book=x$n_book,
      bare=lapply(x$bare,function(v) round(v,4)), book=lapply(x$book,function(v) round(v,4)))),
  book_marginal_common=lapply(methods, function(m){ bc<-book_common[[m]]
      list(method=m, IR=round(bc$IR,4), PORT_t=round(bc$PORT_t,3), calmar=round(bc$calmar,4), mdd=round(bc$mdd,4),
           net_sr=round(bc$net_sr,4), dIR_vs_lineartilt=round(bc$IR-IR_LT,4), dcalmar_vs_lineartilt=round(bc$calmar-CAL_LT,4)) }),
  pit=list(cov="trailing daily rawdata Ret, Date<anchor (C5), <=252d lw_nls",
      lag1_stress=lapply(lag1,function(v) list(calmar=round(v$calmar,4),IR=round(v$IR,4))), placebo=plac,
      self_synthesis="build_benchmark_compare 계약 경유(PerformanceAnalytics)"),
  verdict=verdict, improves_book=improves,
  dIR_erc=round(dIR_erc,4), dIR_invvol=round(dIR_iv,4), dcalmar_erc=round(dcal_erc,4), dcalmar_invvol=round(dcal_iv,4))
saveRDS(list(AB=AB, book_common=book_common, lag1=lag1, placebo=plac, sanity=lt_book, summary=summary),
        file.path(OUT,"wt014_realbook_weighting.rds"))
write_json(summary, file.path(OUT,"wt014_summary.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat(sprintf("\n[VERDICT] %s | dIR_erc=%+.4f dIR_invvol=%+.4f dcalmar_erc=%+.4f dcalmar_invvol=%+.4f (%.1f min)\n",
    verdict, dIR_erc, dIR_iv, dcal_erc, dcal_iv, as.numeric(difftime(Sys.time(),t0,units="mins"))))
cat("[done] saved wt014_summary.json + rds\n")
sink(); close(LOG)
