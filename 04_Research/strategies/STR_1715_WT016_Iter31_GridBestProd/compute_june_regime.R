## 6월 regime_state 산출 — 01_extend_regime_panel.R 로직 그대로, SIGNAL_CUTOFF=2026-05-29
## 출력: sig_date 2026-06-01 regime_state (β_R05 입력). PIT: ≤05-29 데이터만.
suppressPackageStartupMessages({library(data.table); library(arrow); library(lubridate)})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
PR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(PR, "02_Infrastructure/config.R"))
source(file.path(PR, "02_Infrastructure/backtest_harness.R"))

SIGNAL_CUTOFF <- as.Date("2026-05-29")   # 5월 마지막 영업일 → sig_date 2026-06-01
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)
# benchmark.parquet Date가 POSIXct(09:00:00)면 me-90이 90초로 계산됨 → Date 정규화 필수
BM_DT[, Date := as.Date(Date)]; RAWDATA[, Date := as.Date(Date)]
setkey(RAWDATA, Date, Ticker)
cat(sprintf("RAWDATA max=%s | BM_DT max=%s\n", max(RAWDATA$Date), max(BM_DT$Date)))
bm_ret_col <- if ("BM_Ret" %in% names(BM_DT)) "BM_Ret" else "Ret"

breadth_daily <- RAWDATA[!is.na(Ret), .(breadth_pos_pct = mean(Ret > 0, na.rm=TRUE), n_active=.N), by=Date]
setkey(breadth_daily, Date)

me_dates <- BM_DT[Date <= SIGNAL_CUTOFF, .(month_end=max(Date)), by=.(YM=format(Date,"%Y-%m"))]$month_end
me_dates <- sort(unique(me_dates))

build_regime_features <- function(me) {
  win_60 <- BM_DT[Date <= me & Date > me - 90]; if (nrow(win_60) < 30L) return(NULL)
  rv60 <- sd(win_60[[bm_ret_col]], na.rm=TRUE) * sqrt(252)
  me_close_row <- BM_DT[Date == me]; me_close <- if (nrow(me_close_row)>=1L) me_close_row[["BM_Close"]][1L] else NA_real_
  me_ym <- format(me, "%Y-%m"); prev_me <- BM_DT[format(Date,"%Y-%m") != me_ym & Date < me, max(Date)]
  prev_close_row <- BM_DT[Date == prev_me]; prev_close <- if (nrow(prev_close_row)>=1L) prev_close_row[["BM_Close"]][1L] else NA_real_
  ret_1m <- if (!is.na(me_close)&&!is.na(prev_close)&&prev_close>0) me_close/prev_close-1 else NA_real_
  win_252 <- BM_DT[Date <= me & Date > me - 380]
  dd_12m <- if (nrow(win_252) < 20L) NA_real_ else { px<-cumprod(1+win_252[[bm_ret_col]]); min(px/cummax(px)-1, na.rm=TRUE) }
  br_60 <- breadth_daily[Date <= me & Date > me - 90, mean(breadth_pos_pct, na.rm=TRUE)]
  data.table(month_end=me, rv60=rv60, ret_1m=ret_1m, dd_12m=dd_12m, breadth60=br_60)
}
regime_feat <- rbindlist(lapply(me_dates, build_regime_features), fill=TRUE)
regime_feat <- regime_feat[!is.na(rv60) & !is.na(dd_12m)]; setorder(regime_feat, month_end)

expanding_percentile <- function(x) {
  n<-length(x); out<-rep(NA_real_,n)
  for (i in seq_len(n)) { if(i==1L){out[i]<-0.5;next}; past<-x[seq_len(i-1L)]; past<-past[is.finite(past)]
    out[i] <- if (length(past)<6L) 0.5 else mean(past <= x[i], na.rm=TRUE) }
  out
}
regime_feat[, pct_rv60 := expanding_percentile(rv60)]
regime_feat[, pct_neg_ret := expanding_percentile(-ret_1m)]
regime_feat[, pct_neg_dd := expanding_percentile(-dd_12m)]
regime_feat[, pct_neg_brth := expanding_percentile(-breadth60)]
regime_feat[, regime_score := 0.35*pct_rv60 + 0.25*pct_neg_ret + 0.25*pct_neg_dd + 0.15*pct_neg_brth]

cls_thr_q <- function(scores, qs=c(0.30,0.65,0.85)) {
  n<-length(scores); out<-character(n)
  for (i in seq_len(n)) { if(i<12L){out[i]<-"NORMAL";next}; past<-scores[seq_len(i-1L)]; past<-past[is.finite(past)]
    if(length(past)<12L){out[i]<-"NORMAL";next}; th<-quantile(past,probs=qs,na.rm=TRUE); s<-scores[i]
    out[i] <- if(s<=th[1])"BULL" else if(s<=th[2])"NORMAL" else if(s<=th[3])"CAUTION" else "CRISIS" }
  out
}
regime_feat[, regime_state := cls_thr_q(regime_score)]
# [fix] month_end가 달력 말일이 아닐 때(05-29 등) +1일은 같은 달에 머물러 sig_date 충돌·누락.
# month_end의 월 1일 + 1개월 = 다음달 1일 (robust). 05-29 → 2026-06-01.
regime_feat[, sig_date := as.Date(paste0(format(month_end,"%Y-%m"),"-01")) %m+% months(1)]
setorder(regime_feat, sig_date, -month_end); regime_feat <- regime_feat[, .SD[1L], by=sig_date]

cat("\n=== 최근 6개월 regime_state (sanity: 03=CRISIS,04=NORMAL,05=CAUTION 예상) ===\n")
print(regime_feat[sig_date >= as.Date("2026-01-01"),
   .(sig_date, regime_state, regime_score=round(regime_score,3),
     rv60=round(rv60,3), ret_1m=round(ret_1m,4), dd_12m=round(dd_12m,4))])
june <- regime_feat[sig_date == as.Date("2026-06-01")]
cat(sprintf("\n>>> 6월(sig_date 2026-06-01) regime_state = %s | score=%.3f <<<\n",
            if(nrow(june)) june$regime_state else "NA", if(nrow(june)) june$regime_score else NA))
