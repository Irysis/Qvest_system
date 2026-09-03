# O1 — optimizer 입력 로드 + 파이프라인 parity 검증 (alpha 좌표 재현)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/contracts/weighted_screen_bt.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")

AS  <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
SIG <- as.data.table(read_parquet(file.path(OUT,"regime_signal_timeseries.parquet")))
P   <- readRDS(file.path(OUT,"panel.rds"))
R   <- as.data.table(P$fwd$returns_dt)[!is.na(Ret_1m)]
BENCH <- as.data.table(P$fwd$bench_dt)
LIQ <- as.data.table(P$fwd$liq_dt)
cat("[O1] AS", nrow(AS), "dates", uniqueN(AS$Date), "| SIG", nrow(SIG),
    "| R", nrow(R), "| BENCH", nrow(BENCH), "| LIQ", nrow(LIQ), names(LIQ), "\n")
cat("[O1] liq_ruler:", P$fwd$liq_ruler, "/", P$fwd$liq_ruler_source, "\n")

sel_top <- function(D, scorecol, n=25L){ x <- copy(D); setorderv(x, c("Date", scorecol), c(1,-1))
  x[, .(Ticker=Ticker[seq_len(min(n,.N))]), by=Date] }
ew <- function(H) H[, .(Ticker, w=1/.N), by=Date]

H_on  <- sel_top(AS,"score");               H_off <- sel_top(AS,"score_base_momentum")
m_on  <- weighted_screen_bt(ew(H_on),  R, BENCH, 15, "o1_parity_on",  "o1_parity_on")
m_off <- weighted_screen_bt(ew(H_off), R, BENCH, 15, "o1_parity_off", "o1_parity_off")

met <- function(m, lab){ pr <- as.data.table(m$period_returns); r <- pr$ret_net; n <- length(r)
  nav <- cumprod(1+r); mdd <- min(nav/cummax(nav)-1); cg <- prod(1+r)^(12/n)-1
  fit <- lm(r ~ pr$benchmark_ret); ct <- coeftest(fit, vcov=NeweyWest(fit,lag=3,prewhite=FALSE))
  cat(sprintf("%-14s n=%3d PORT_t=%+.4f SR=%+.4f CAGR=%+.4f MDD=%+.4f Calmar=%+.4f b=%.4f a=%+.4f%%/yr t(a)=%+.3f TO=%.4f\n",
    lab,n,m$portfolio_alpha_t_nw_lag3, mean(r)/sd(r)*sqrt(12), cg, mdd, cg/abs(mdd),
    ct[2,1], 100*12*ct[1,1], ct[1,3], m$turnover_annual)) }
met(m_on,"EW_overlayON"); met(m_off,"EW_overlayOFF")
cat("[alpha 보고값] cand SR 0.50506 CAGR 0.114218 MDD -0.635344 Calmar 0.179773 PORT_t 0.915291 a 3.6076 TO 9.3803\n")
cat("[alpha 보고값] A0   a 5.1365 · Calmar/SR 은 s4_candidate.json 참조\n")

## 유동성 제약 실측 — 선택분 ADV20 < 2e8 건수
chk <- merge(rbind(H_on[,.(Date,Ticker,arm="on")],H_off[,.(Date,Ticker,arm="off")]),
             LIQ[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("[O1][LIQ] 선택슬롯 %d · adv NA %d · adv<2e8 %d (%.4f%%) · min adv %.3e\n",
  nrow(chk), sum(is.na(chk$adv)), sum(chk$adv<2e8,na.rm=TRUE),
  100*mean(chk$adv<2e8,na.rm=TRUE), min(chk$adv,na.rm=TRUE)))
saveRDS(list(AS=AS,SIG=SIG,R=R,BENCH=BENCH,LIQ=LIQ,H_on=H_on,H_off=H_off,
             m_on=m_on,m_off=m_off), file.path(OUT,"o1_objects.rds"))
