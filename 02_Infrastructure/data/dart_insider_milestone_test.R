# DART insider 마일스톤 판정 도구 — 신호 → IC + top-25 long-only PORT_t 전이 (canonical_screen_bt 권위)
# backfill 누적분 소비. 데이터 성장 시 재실행 = verdict. sparse event-signal 구성.
# 신호: net officer buying (임원 open-market signed notional, 종목-월, trailing window 지속성).
# 구성: 양의 insider-buy 종목만 후보 → top-N(≤25) EW long-only. IC→PORT_t 전이 벽 직접 검증.
suppressPackageStartupMessages({ library(data.table); library(arrow) }); setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a
source("02_Infrastructure/contracts/canonical_screen_bt.R")
TRAIL <- as.integer(Sys.getenv("INSIDER_TRAIL_M","3"))   # 신호 trailing window(월)

# ── 1. 신호 구성 (net officer buying, open-market only) ──
files <- list.files(".cache/dart/insider_backfill", pattern="[0-9]{6}[.]csv$", full.names=TRUE)
cat(sprintf("[mt] 체크포인트 %d월 | 최신연도 %s | trail=%dM\n", length(files),
            if(length(files)) max(substr(gsub(".*/|\\.csv","",files),1,4)) else "?", TRAIL))
if (length(files) < 24) { cat("[mt] ★데이터 부족(<24월) — backfill 누적 대기. 현재는 도구 스모크.\n") }
raw <- rbindlist(lapply(files, function(f) tryCatch(fread(f, colClasses=list(character="corp_code")), error=function(e) NULL)), fill=TRUE)
t <- raw[!is.na(qty_change) & grepl("임원", as.character(reporter_class)) & grepl("장내|장외|시간외", as.character(report_reason))]
t[, qc := as.numeric(qty_change)]; t[, pr := as.numeric(price)]
t[, notional := qc * ifelse(is.finite(pr) & pr>0, pr, 0)]
t[, sig_ym := substr(gsub("[^0-9]","", as.character(rcept_dt %||% filing_date)),1,6)]
t <- t[nchar(sig_ym)==6]
uni <- fread(".cache/dart/universe_corpcodes.csv", colClasses="character")
t <- merge(t, uni[, .(stock_code, ticker)], by.x="corp_code", by.y="stock_code")[!is.na(ticker)]
mth <- t[, .(net=sum(notional,na.rm=TRUE)), by=.(ticker, sig_ym)]
# trailing TRAIL-월 합 (지속성)
allym <- sort(unique(mth$sig_ym))
setkey(mth, ticker, sig_ym)
mth[, ymi := match(sig_ym, allym)]
roll <- mth[, {
  x <- .SD[order(ymi)]
  data.table(sig_ym=allym, trail=sapply(seq_along(allym), function(k)
    sum(x$net[x$ymi > k-TRAIL & x$ymi <= k], na.rm=TRUE)))
}, by=ticker]
roll <- roll[trail != 0]

# ── 2. 월간 수익/벤치/유동성 패널 ──
rd <- as.data.table(open_dataset(".cache/RAWDATA.parquet") |>
        (\(d) dplyr::select(d, Date, Ticker, Close, Vol))() |> (\(d) dplyr::collect(d))())
rd[, Date := as.Date(Date)]; rd <- rd[Date <= as.Date("2026-06-30")]; rd[, ym := format(Date,"%Y%m")]
rd[, tv := Close * Vol]
mon <- rd[, .(mc=last(Close[is.finite(Close)]), adv=mean(tv[is.finite(tv)], na.rm=TRUE)), by=.(Ticker, ym)][is.finite(mc)]
setorder(mon, Ticker, ym); mon[, ret_fwd := shift(mc,-1)/mc - 1, by=Ticker]
mon[, mdate := as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet")); bm[, Date:=as.Date(Date)]; bm[, ym:=format(Date,"%Y%m")]
bmm <- bm[is.finite(BM_Ret), .(BM_Ret=prod(1+BM_Ret)-1), by=ym]
bmm[, mdate := as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))]

# ── 3. IC (전기간 + post-2017) ──
sig <- merge(roll[, .(Ticker=ticker, ym=sig_ym, score=trail)], mon[, .(Ticker, ym, ret_fwd)], by=c("Ticker","ym"))
sig <- sig[is.finite(ret_fwd) & is.finite(score)]
icm <- sig[, .(ic=if(.N>=5) cor(rank(score),rank(ret_fwd)) else NA_real_, n=.N), by=ym][is.finite(ic)]
ic_stat <- function(d) if(nrow(d)>=6) sprintf("IC=%.4f ICIR=%.2f n=%d", mean(d$ic), mean(d$ic)/sd(d$ic)*sqrt(12), nrow(d)) else sprintf("n=%d(부족)", nrow(d))
cat(sprintf("[mt] IC 전기간: %s | 2017+: %s\n", ic_stat(icm), ic_stat(icm[ym>="201701"])))

# ── 4. PORT_t (canonical_screen_bt, 양의 insider-buy 종목 top-25 long-only) ──
cand <- roll[trail > 0, .(Date=NA, Ticker=ticker, ym=sig_ym, score=trail)]  # 양의 순매수만 후보
scores_dt <- merge(cand[, .(Ticker, ym, score)], mon[, .(Ticker, ym, mdate)], by=c("Ticker","ym"))[, .(Date=mdate, Ticker, score)]
returns_dt <- mon[is.finite(ret_fwd), .(Date=mdate, Ticker, Ret_1m=ret_fwd)]
bench_dt <- bmm[, .(Date=mdate, BM_Ret)]
liq_dt <- mon[is.finite(adv), .(Date=mdate, Ticker, adv)]
cat(sprintf("[mt] PORT_t 후보: 종목-월 %d | 월수 %d | 평균 후보/월 %.1f\n",
            nrow(scores_dt), length(unique(scores_dt$Date)), nrow(scores_dt)/max(1,length(unique(scores_dt$Date)))))
res <- tryCatch(canonical_screen_bt(scores_dt, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8),
                error=function(e){ cat("[mt] canonical_screen_bt 에러:", conditionMessage(e), "\n"); NULL })
if (!is.null(res)) {
  pt <- res$portfolio_alpha_t_nw_lag3 %||% res$metrics$portfolio_alpha_t_nw_lag3 %||% NA
  ir <- res$information_ratio %||% res$metrics$information_ratio %||% NA
  cat(sprintf("\n[mt] ===== 마일스톤 판정 (net officer buying top-25 long-only) =====\n"))
  cat(sprintf("[mt] PORT_t(NW-3)=%.3f  IR=%.3f  n_months=%s  metric_type=canonical_screen\n",
              pt %||% NA, ir %||% NA, res$n_months %||% "?"))
  cat(sprintf("[mt] 게이트 PORT_t>=2.95: %s\n", if(is.finite(pt) && pt>=2.95) "PASS ★" else "미달(또는 데이터부족)"))
}
cat("[mt] ★verdict = backfill post-2017 도달 후. 현재는 도구 검증/조기read.\n[mt] DONE\n")
