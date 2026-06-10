# =============================================================================
# driver_ls_generic.R — single-factor LONG-SHORT gross 진단 (fe 경로 인자화 일반화)
#   목적: long-only로 기각된 단일 팩터가 "베타에 가린 진짜 알파"인지 long-short로
#         재평가. LS = 시장중립 → 1st eigenmode(시장노출) 제거 → 직교 알파 순수 측정.
#         valmom 선례: long-only Carhart4 t1.63·OOS-0.06 → LS t3.13·OOS0.60·Sharpe1.00.
#   ★ KR 공매도 실편입 불가 — 순수 진단 (gross, turnover 비용 생략).
#
#   ★ driver_ls_v2.R 일반화: fe_valmom.R 하드코딩만 환경변수 FE_PATH/STRAT_NAME로 분리.
#     나머지(Return.portfolio 시계열 long-short·Carhart4 t·OOS retention·JSON 저장) 동일.
#   호출: FE_PATH=<fe.R 절대|상대경로>, STRAT_NAME=<태그> 환경변수 전달 후
#         Rscript -e "source('.../driver_ls_generic.R')"  (-f 금지, driver BOM 없이)
#   출력: stage_artifacts/alpha_search/{STRAT_NAME}_longshort_diagnostic.json
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
}))
PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))
source(file.path(INFRA, "factor_portfolios.R"))
OUT_DIR     <- file.path(PROJ, "stage_artifacts", "alpha_search")
START_DATE  <- as.Date("2005-01-01")
DECILE_FRAC <- 0.10

# ---- 인자: fe 경로 + 전략 태그 (driver_ls_v2 의 유일한 변경점) ----
FE_PATH    <- Sys.getenv("FE_PATH", "")
STRAT_NAME <- Sys.getenv("STRAT_NAME", "")
if (!nzchar(FE_PATH) || !nzchar(STRAT_NAME))
  stop("FE_PATH 와 STRAT_NAME 환경변수 필수 (예: FE_PATH=02_Infrastructure/alpha_search/fe_qualitygp.R STRAT_NAME=qualitygp)")
if (!file.exists(FE_PATH)) {  # 상대경로면 PROJ 기준 재시도
  cand <- file.path(PROJ, FE_PATH)
  if (file.exists(cand)) FE_PATH <- cand else stop("FE_PATH 파일 없음: ", FE_PATH)
}
cat(sprintf("[LS-GEN] fe=%s | strat=%s\n", FE_PATH, STRAT_NAME))

# ---- 1. Data + signal (fe: RAWDATA 전역 사용, 중복로드 없음) ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
# 유동성 파생컬럼 (factor_engine_template 전제: TradingValue/AvgTV20/LiqPass) — run_alpha_search L80-83 표준 재현
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
source(FE_PATH)   # -> FACTORS(Date,Ticker,Score)   ★ 인자화된 유일한 변경점
stopifnot(exists("FACTORS"), is.data.table(FACTORS))
FACTORS <- FACTORS[Date >= START_DATE]

# ---- 2. 월말 패널 + 종목 forward 1M 보유수익 (d 편입결정 -> nd 실현; lookahead 없음) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
me_panel <- RAWDATA[Date %in% me_dates, .(Date, Ticker, Close)]
RAWDATA[, .ym := NULL]; rm(RAWDATA); gc(FALSE)
setorder(me_panel, Ticker, Date)
me_panel[, ret_fwd  := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]   # forward 1M (C2 안전)
me_panel[, ret_date := shift(Date,  1L, type = "lead"), by = Ticker]               # 실현일 nd
setkey(me_panel, Ticker, Date)

sig_dates <- sort(unique(FACTORS$Date)); sig_dates <- sig_dates[sig_dates %in% me_dates]

# ---- 3. leg long table -> wide -> Return.portfolio (시계열 단일 호출, 표준함수) ----
build_leg <- function(side) {
  L <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    fd <- FACTORS[Date == d]; if (nrow(fd) < 10L) next
    n_dec <- max(2L, as.integer(ceiling(nrow(fd) * DECILE_FRAC)))
    setorder(fd, -Score)
    sel <- if (side == "long") head(fd, n_dec) else tail(fd, n_dec)
    mp  <- me_panel[.(sel$Ticker, d), .(Ticker, ret_fwd, ret_date), nomatch = 0L]
    mp  <- mp[is.finite(ret_fwd) & !is.na(ret_date)]
    if (nrow(mp) < 2L) next
    mp[, w := 1 / .N]   # equal-weight
    L[[i]] <- mp[, .(Date = ret_date, Ticker, ret = ret_fwd, w)]
  }
  rbindlist(Filter(Negate(is.null), L))
}
leg_series <- function(side) {
  lg <- build_leg(side)
  Rw <- dcast(lg, Date ~ Ticker, value.var = "ret", fill = 0)
  Ww <- dcast(lg, Date ~ Ticker, value.var = "w",   fill = 0)
  dts <- Rw$Date
  Rx <- xts(as.matrix(Rw[, -1, with = FALSE]), order.by = dts)
  Wx <- xts(as.matrix(Ww[, -1, with = FALSE]), order.by = dts)
  Return.portfolio(R = Rx, weights = Wx)   # 매기간 EW rebalance, gross 포트 시계열
}
long_x  <- leg_series("long")
short_x <- leg_series("short")
mm <- na.omit(merge(long_x, short_x)); colnames(mm) <- c("long", "short")
ls_x <- mm[, "long"] - mm[, "short"]   # 시장중립 LS (시계열 element-wise 차감)

# ---- 4. 측정 (1) Sharpe (2) Carhart4 alpha t (3) OOS retention ----
sh <- function(x){ t<-tryCatch(table.AnnualizedReturns(x,scale=12,Rf=0),error=function(e)NULL); if(is.null(t)) NA_real_ else as.numeric(t[3,1]) }
ls_sharpe <- sh(ls_x); long_sharpe <- sh(mm[,"long"]); short_sharpe <- sh(mm[,"short"])
mf <- tryCatch(run_multifactor_regression(ls_x, bm_xts = NULL, factor_dt = load_kr_factor_returns()),
               error = function(e){ cat("[LS] mf fail:", conditionMessage(e), "\n"); NULL })
c4t <- if (!is.null(mf) && !is.null(mf$Carhart4)) mf$Carhart4$alpha_tstat   else NA_real_
c4a <- if (!is.null(mf) && !is.null(mf$Carhart4)) mf$Carhart4$alpha*12*100  else NA_real_

df <- data.table(Date = index(ls_x), r = as.numeric(ls_x)); df[, yr := year(Date)]
srof <- function(v){ v<-v[is.finite(v)]; s<-sd(v); if(!is.finite(s)||s<=0) NA_real_ else mean(v)/s*sqrt(12) }
sr_is <- srof(df[yr <= 2015, r]); sr_oos <- srof(df[yr >= 2016, r])
reten <- if (is.finite(sr_is) && abs(sr_is) > 1e-9) sr_oos / sr_is else NA_real_

cat(sprintf("[LS-DONE] %s gross | LS Sharpe=%.3f | long=%.3f short=%.3f | Carhart4 a=%.2f%%/yr t=%.3f | OOS ret=%.3f (IS=%.3f n=%d / OOS=%.3f n=%d)\n",
            STRAT_NAME, ls_sharpe, long_sharpe, short_sharpe, c4a, c4t, reten, sr_is, df[yr<=2015,.N], sr_oos, df[yr>=2016,.N]))
out <- list(
  experiment  = sprintf("%s single-factor LONG-SHORT gross diagnostic (KR short-sale infeasible; pure diagnostic)", STRAT_NAME),
  strategy    = STRAT_NAME, fe_path = FE_PATH,
  metric_type = "backtested_gross_Return.portfolio",
  universe = "K200_KQ150", start_date = as.character(START_DATE), n_months = nrow(mm),
  ls_sharpe = round(ls_sharpe,4), long_leg_sharpe = round(long_sharpe,4), short_leg_sharpe = round(short_sharpe,4),
  carhart4_alpha_ann_pct = round(c4a,3), carhart4_alpha_t = round(c4t,4),
  oos_retention = round(reten,4), oos_sharpe_IS = round(sr_is,4), oos_sharpe_OOS = round(sr_oos,4),
  valmom_reference = list(ls_sharpe = 1.00, carhart4_t = 3.13, oos_retention = 0.60,
                          note = "valmom long-only(Sharpe0.825,t1.63,OOS-0.06) -> LS 살아남 선례"),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(out, file.path(OUT_DIR, sprintf("%s_longshort_diagnostic.json", STRAT_NAME)),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("[SAVED] %s_longshort_diagnostic.json\n", STRAT_NAME))
