#!/usr/bin/env Rscript
# =============================================================================
# run_tsmom_timing.R — time-series/path 단일명 타이밍 probe (관계형 후 마지막 미탐색 long-only 클래스)
# -----------------------------------------------------------------------------
# 배경: 직교 입력 경로 중 횡단면(factor-score)·관계형(lead-lag/spillover) 전부 종료.
#   유일 미탐색 long-only 클래스 = *시계열/path-dependent 단일명 타이밍* — 선택/노출을
#   횡단면 랭킹이 아니라 **각 종목 자기 path 상태**로 결정. 메모리 사전판정 = ≈overlay
#   (MDD↓·alpha X). 본 probe = cheap 공식 검증.
#
# 신호 (Faber 2007 절대모멘텀 / Moskowitz-Ooi-Pedersen 2012 TSMOM, 순수 시계열·per-name):
#   trend_on_i(t) = Close_i[t] > MA200_i[t]   (자기 200d 이동평균 상회 = 추세 ON)
#   보유: universe(K200∪KQ150)∩LiqPass∩trend_on 중 EW, **목표 N=25 고정 denominator**.
#     → trend-on 종목 < 25면 그만큼 CASH 보유(=단일명 레벨 디리스크 타이밍, overlay 거동).
#     → > 25면 자기 12-1 추세강도 상위 25.
#   이것이 횡단면 알파와 다른 점: 포트가 추세 빈약 국면에 *현금으로 빠짐*(timing).
#
# ★ 측정: 자체합성 금지 — Return.portfolio(CASH asset 포함, 합=1) → apply.monthly →
#   build_bt_result(frequency=monthly) → audit → essence_score(PORT_t NW lag3·OOS·DSR).
# ★ 직교성: 월간 active(port−bm) vs STR_str1715v2 active 상관(천장 코어 대비).
# ★ 반증기준(선행고정): PORT_t≥2.95 · OOS_retention≥0.7 · return_cor<0.5. 하나라도 깨지면 F.
# ===== PIT: MA200·12-1·trend 전부 t까지 데이터(shift). 월말 신호 → 다음달 보유. =====
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(zoo); library(PerformanceAnalytics); library(jsonlite)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
INFRA <- file.path(PROJ, "02_Infrastructure"); CD <- file.path(INFRA, "contracts")
source(file.path(INFRA, "config.R")); source(file.path(INFRA, "backtest_harness.R"))
source(file.path(CD, "backtest_result_contract.R")); source(file.path(CD, "audit_bt_result.R")); source(file.path(CD, "essence_score.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0L||(length(a)==1L&&is.na(a))) b else a
TARGET_N <- 25L; COST_BPS <- 15
MA_WIN  <- as.integer(Sys.getenv("TSMOM_MA_WIN", "200"))     # trend MA window (짧을수록 하락구간 현금화↑)
REQ_MOM <- Sys.getenv("TSMOM_REQ_MOM_POS", "0") == "1"        # 추가 필터: 자기 12-1 모멘텀>0 동시 요구
CFG_TAG <- sprintf("ma%d%s", MA_WIN, if(REQ_MOM) "_mompos" else "")

# ---- 1. Data ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(verbose=FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
LIQ <- 2e8
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align="right"), by=Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ]
# per-name path features (PIT: shift 1 → t-1 기준 trailing)
RAWDATA[, MA200 := frollmean(shift(Close,1L), MA_WIN), by=Ticker]            # 200d MA (t까지)
RAWDATA[, trend_on := is.finite(MA200) & shift(Close,1L) > MA200, by=Ticker] # 절대모멘텀 ON (어제 종가>MA)
RAWDATA[, mom121 := shift(Close,21L)/shift(Close,252L) - 1, by=Ticker]       # 12-1 자기추세 강도
all_dates <- sort(unique(RAWDATA$Date))
RAWDATA[, .ym := format(Date,"%Y-%m")]
me <- RAWDATA[, .(Date=max(Date)), by=.ym]$Date
me <- me[me >= as.Date("2005-01-01")]                                        # 표준 시작

# ---- 2. 월별 timing weights (CASH 허용) ----
held_list <- vector("list", length(me)); cash_frac <- numeric(length(me))
for (i in seq_along(me)) {
  d <- me[i]
  cand <- RAWDATA[Date==d & LiqPass==TRUE & trend_on==TRUE & (K200==TRUE|KQ150==TRUE) & is.finite(mom121) &
                  (!REQ_MOM | mom121 > 0),
                  .(Ticker, mom121)]
  exec <- get_execution_date(d, all_dates); if (is.na(exec)) next
  nca <- nrow(cand)
  if (nca == 0L) { cash_frac[i] <- 1; held_list[[i]] <- data.table(exec=exec, Ticker=character(0), w=numeric(0)); next }
  setorder(cand, -mom121)
  picks <- head(cand$Ticker, TARGET_N)
  w_each <- 1/TARGET_N                          # 고정 denominator → trend-on<25면 cash
  held_list[[i]] <- data.table(exec=exec, Ticker=picks, w=w_each)
  cash_frac[i] <- 1 - length(picks)*w_each
}
held <- rbindlist(held_list, use.names=TRUE)
used_me <- which(sapply(held_list, function(x) !is.null(x)))
avg_cash <- round(mean(cash_frac[used_me]), 3)
cat(sprintf("[tsmom] rebal months=%d | avg cash frac=%.3f (timing intensity)\n", length(used_me), avg_cash))

# ---- 3. daily net returns (Return.portfolio + CASH asset) ----
tickers <- sort(unique(held$Ticker))
RR <- RAWDATA[Ticker %in% tickers & Date >= min(held$exec) & is.finite(Ret), .(Date, Ticker, Ret)]
Rw <- dcast(RR, Date ~ Ticker, value.var="Ret"); setorder(Rw, Date)
rdates <- Rw$Date; Rmat <- as.matrix(Rw[, -1, with=FALSE]); Rmat[!is.finite(Rmat)] <- 0
Rmat <- cbind(Rmat, CASH=0)                                  # 현금 자산 (ret 0)
R_xts <- xts(Rmat, order.by=rdates)
# weights per rebalance(exec date) — 보유 + CASH(나머지)
Wlist <- list()
for (i in used_me) {
  hd <- held_list[[i]]; ex <- hd$exec[1] %||% held_list[[i]]$exec
  ex <- unique(held_list[[i]]$exec); ex <- ex[is.finite(ex)][1]
  if (is.na(ex)) next
  wv <- setNames(rep(0, ncol(R_xts)), colnames(R_xts))
  if (nrow(hd) > 0L) wv[hd$Ticker] <- hd$w
  wv["CASH"] <- max(0, 1 - sum(wv[setdiff(names(wv),"CASH")]))
  Wlist[[as.character(ex)]] <- data.table(Date=ex, t(wv))
}
Wdt <- rbindlist(Wlist, use.names=TRUE); setorder(Wdt, Date)
W_xts <- xts(as.matrix(Wdt[, -1, with=FALSE]), order.by=Wdt$Date)
W_xts <- W_xts[, colnames(R_xts)]                            # 컬럼 정합
rp <- Return.portfolio(R=R_xts, weights=W_xts, rebalance_on=NA, verbose=TRUE)
port_gross <- rp$returns
# turnover 비용 (BOP vs 직전 EOP, run_wf_ensemble 패턴)
bop <- as.matrix(rp$BOP.Weight); eop <- as.matrix(rp$EOP.Weight); idx <- as.Date(index(rp$BOP.Weight))
to_v <- numeric(nrow(bop)); prev <- rep(0, ncol(bop))
for (j in seq_len(nrow(bop))) { tg <- bop[j,]; tg[!is.finite(tg)] <- 0
  d <- sum(abs(tg - prev), na.rm=TRUE); if (d>1e-8) to_v[j] <- d; pe <- eop[j,]; pe[!is.finite(pe)] <- 0; prev <- pe }
pdt <- data.table(Date=as.Date(index(port_gross)), r_gross=as.numeric(port_gross), to=to_v)
pdt[, r_net := r_gross - to*(COST_BPS/1e4)]; setorder(pdt, Date)
ann_to <- round(sum(pdt$to)/(nrow(pdt)/252), 2)

# ---- 4. benchmark (KOSPI200 daily) ----
bm <- unique(RAWDATA[Date %in% pdt$Date & is.finite(BM_Ret), .(Date, BM_Ret)]); setorder(bm, Date)
pdt <- merge(pdt, bm, by="Date", all.x=TRUE); pdt[!is.finite(BM_Ret), BM_Ret := 0]

# ---- 5. 계약 측정 (월간 NAV) ----
ED <- xts(pdt$r_net, order.by=pdt$Date); BMx <- xts(pdt$BM_Ret, order.by=pdt$Date)
mret <- apply.monthly(ED, Return.cumulative); mdates <- as.Date(index(mret))
nav <- as.numeric(cumprod(1 + as.numeric(mret)))
sim_result <- list(DAILY_NAV_DT=data.table(Date=mdates, NAV=nav),
  strategy_xts=ED, bm_xts=BMx, HOLDINGS_LOG=list(), PORTFOLIO_LOG=data.table(Exec_Date=as.Date(Wdt$Date)))
spec <- list(strategy_name="TSMOM_timing_longonly", signal="per-name absolute momentum (Close>MA200) timing, cash when few trend",
  weighting="EW target_n=25 fixed denominator (cash residual)", rebalance="monthly",
  lookahead_prevention="MA200/12-1/trend t-1 shift; 월말신호→다음달 보유; Return.portfolio")
bt <- build_bt_result(sim_result, spec, run_id="TSMOM_TIMING", strategy_id="TSMOM_TIMING", strategy_version="v1",
  benchmark_id="KOSPI200", benchmark_name="KOSPI 200", transaction_cost_bps=COST_BPS, slippage_bps=0,
  risk_free_rate=0, frequency="monthly", annualization_factor=12, universe_id="K200_KQ150",
  code_version="run_tsmom_timing_v1", created_by_agent="factor-rotation")
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative=2L)   # 단일 config probe (n_trials≈1~2)

# ---- 6. OOS retention + 직교성(STR_1715 v2 active) ----
PRm <- as.data.table(bt$period_returns)[, .(date, ret_net)]
BRm <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
MM <- merge(PRm, BRm, by="date"); setorder(MM, date)
n <- nrow(MM); k <- floor(n*0.65); shp <- function(x){x<-x[is.finite(x)];if(length(x)<2||sd(x)==0)return(NA);mean(x)/sd(x)*sqrt(12)}
act <- MM$ret_net - MM$benchmark_ret
is_sr <- shp(act[1:k]); oos_sr <- shp(act[(k+1):n])
oos_ret <- es$essence$oos_retention %||% (if(is.finite(is_sr)&&abs(is_sr)>=0.1) oos_sr/is_sr else NA_real_)
# 직교성: STR_str1715v2 월간 active
ref_cor <- NA_real_
refp <- file.path(PROJ,"04_Research/strategies/STR_str1715v2/sim_result.rds")
if (file.exists(refp)) {
  rs <- readRDS(refp); rd <- as.data.table(rs$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  rbm <- if(!is.null(rs$bm_xts)) data.table(Date=as.Date(index(rs$bm_xts)), b=as.numeric(rs$bm_xts[,1])) else NULL
  if(!is.null(rbm)){ rj <- merge(rd, rbm, by="Date"); rj[, ra := r - b]
    rjm <- apply.monthly(xts(rj$ra, order.by=rj$Date), Return.cumulative)
    refm <- data.table(ym=format(as.Date(index(rjm)),"%Y-%m"), ref_act=as.numeric(rjm))
    mym <- data.table(ym=format(MM$date,"%Y-%m"), my_act=act)
    cj <- merge(mym, refm, by="ym")
    if(nrow(cj)>=24) ref_cor <- suppressWarnings(cor(cj$my_act, cj$ref_act)) }
}

# ---- 7. 평결 (반증기준 선행고정) ----
PORT_t <- es$essence$portfolio_alpha_t_nw_lag3 %||% NA
g_port <- is.finite(PORT_t) && PORT_t >= 2.95
g_oos  <- is.finite(oos_ret) && oos_ret >= 0.7
g_orth <- is.finite(ref_cor) && ref_cor < 0.5
verdict <- if (g_port && g_oos && g_orth) "★ BREAKTHROUGH — 3기준 동시충족(직교+알파+OOS). 재검증 필수" else
           "F — time-series/path 타이밍도 long-only 알파 아님(반증기준 미충족)"
overlay_behavior <- sprintf("MDD %.1f%% vs BM, avg_cash %.3f → %s",
  (es$essence$mdd%||%NA)*100, avg_cash,
  if(is.finite(es$essence$mdd) && (es$essence$mdd < 0.30) && !g_port) "overlay 거동(MDD↓·alpha X) 확인" else "—")

out <- list(schema_version="v1.0", generated=as.character(Sys.Date()),
  probe="time-series/path single-name timing (Faber abs-mom / TSMOM)", grade=es$grade, metric_type=es$metric_type,
  essence=es$essence, port_t=PORT_t, oos_retention=if(is.finite(oos_ret))round(oos_ret,3) else NA,
  oos_is_active_sharpe=round(is_sr,3), oos_oos_active_sharpe=round(oos_sr,3),
  return_cor_vs_str1715v2=if(is.finite(ref_cor))round(ref_cor,3) else NA,
  avg_cash_frac=avg_cash, ann_turnover=ann_to, n_months=n,
  gates=list(port_t_ge_2p95=g_port, oos_ret_ge_0p7=g_oos, ortho_lt_0p5=g_orth),
  verdict=verdict, overlay_behavior=overlay_behavior,
  date_range=c(as.character(min(MM$date)), as.character(max(MM$date))))
dir.create(file.path(PROJ,"04_Research/factor_rotation/output"), showWarnings=FALSE, recursive=TRUE)
write_json(out, file.path(PROJ, sprintf("04_Research/factor_rotation/output/tsmom_timing_probe_%s.json", CFG_TAG)),
  auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)

cat("\n==== TSMOM 단일명 타이밍 probe (time-series/path 클래스) ====\n")
cat(sprintf("grade=%s netSR=%.3f PORT_t=%.3f DSR=%s OOS_ret=%s Calmar=%.2f MDD=%.1f%% CAGR=%.1f%%\n",
  es$grade, es$essence$net_sharpe%||%NA, PORT_t, as.character(round(es$essence$dsr,3)),
  if(is.finite(oos_ret))sprintf("%.3f",oos_ret) else "NA", es$essence$calmar%||%NA,
  (es$essence$mdd%||%NA)*100, (es$essence$cagr%||%NA)*100))
cat(sprintf("return_cor vs STR_1715v2=%s | avg_cash=%.3f | ann_TO=%.2f\n",
  if(is.finite(ref_cor))sprintf("%.3f",ref_cor) else "NA", avg_cash, ann_to))
cat(sprintf("gates: PORT_t≥2.95=%s OOS≥0.7=%s ortho<0.5=%s\n", g_port, g_oos, g_orth))
cat(sprintf("★ %s\n  %s\n", verdict, overlay_behavior))
