# =============================================================================
# driver_ls_v2.R — valmom value(BM)+momentum(12-1) z-combo LONG-SHORT gross 진단
#   목적: long-only valmom(Sharpe 0.825, Carhart4 t 1.63, OOS retention -0.06)의
#         OOS 붕괴가 (a) long-only 제약(1st eigenmode 시장노출) 인지 (b) 알파 자체
#         OOS 부재 인지 분리. LS는 시장중립 → 1st eigenmode 제거 → 직교 알파 순수 측정.
#   ★ KR 공매도 실편입 불가 — 순수 진단 (gross, turnover 비용 생략).
#   ★ v1 버그 fix: Return.portfolio를 매월 1-row(1 obs)로 호출 → periodicity 에러.
#     → leg wide matrix(날짜×종목) 만들어 Return.portfolio를 시계열에 단 한 번 호출
#       (매기간 EW rebalance). 손합성 없이 PerformanceAnalytics 표준함수 준수.
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

# ---- 1. Data + signal (fe_valmom: RAWDATA 전역 사용, 중복로드 없음) ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
source(file.path(INFRA, "alpha_search", "fe_valmom.R"))   # -> FACTORS(Date,Ticker,Score)
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

cat(sprintf("[LS-DONE] gross | LS Sharpe=%.3f | long=%.3f short=%.3f | Carhart4 a=%.2f%%/yr t=%.3f | OOS ret=%.3f (IS=%.3f n=%d / OOS=%.3f n=%d)\n",
            ls_sharpe, long_sharpe, short_sharpe, c4a, c4t, reten, sr_is, df[yr<=2015,.N], sr_oos, df[yr>=2016,.N]))
out <- list(
  experiment  = "valmom value(BM)+mom(12-1) z-combo LONG-SHORT gross diagnostic (KR short-sale infeasible; pure diagnostic)",
  metric_type = "backtested_gross_Return.portfolio",
  universe = "K200_KQ150", start_date = as.character(START_DATE), n_months = nrow(mm),
  ls_sharpe = round(ls_sharpe,4), long_leg_sharpe = round(long_sharpe,4), short_leg_sharpe = round(short_sharpe,4),
  carhart4_alpha_ann_pct = round(c4a,3), carhart4_alpha_t = round(c4t,4),
  oos_retention = round(reten,4), oos_sharpe_IS = round(sr_is,4), oos_sharpe_OOS = round(sr_oos,4),
  longonly_baseline = list(sharpe = 0.825, carhart4_t = 1.63, oos_retention = -0.06),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
write_json(out, file.path(OUT_DIR, "valmom_longshort_diagnostic.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[SAVED] valmom_longshort_diagnostic.json\n")
