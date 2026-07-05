# DART insider 신호 구성 + IC→PORT_t 하네스 (backfill 누적분 소비, 데이터 성장 시 재실행)
# 신호: net officer buying (임원 시장거래 signed notional, mechanical 이벤트 제외), 종목-월 집계
# PIT: 필링 접수일(rcept_dt) 기준 시그널 → forward 1M 실현수익. Cohen-Malloy-Pomorski 2012.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a
CKDIR <- ".cache/dart/insider_backfill"

# ── 1. 체크포인트 consolidate ──
files <- list.files(CKDIR, pattern="^\\d{6}\\.csv$", full.names=TRUE)
cat("[ic] 체크포인트 월:", length(files), "| 범위:",
    if(length(files)) paste(range(gsub("\\.csv$","",basename(files))), collapse="~") else "없음", "\n")
if (!length(files)) { cat("[ic] 데이터 없음 — backfill 대기\n"); quit(save="no") }
raw <- rbindlist(lapply(files, function(f) tryCatch(fread(f, colClasses=list(character="corp_code")), error=function(e) NULL)), fill=TRUE)
trades <- raw[!is.na(qty_change) & !is.na(reporter_class)]
cat("[ic] 총 거래행:", nrow(trades), "| 고유 corp:", length(unique(trades$corp_code)), "\n")

# ── 2. net officer buying 신호 (임원 + 시장거래 only, mechanical 제외) ──
MECH <- "임원퇴임|퇴임|주식분할|무상증자|합병|분할|상속|증여|주식배당|전환|행사|배정|해임|사임|신규상장"
MKT  <- "장내|장외|매수|매도|시장"
trades[, qc := as.numeric(qty_change)]; trades[, pr := as.numeric(price)]
off <- trades[grepl("임원", reporter_class) & grepl(MKT, report_reason %||% "") & !grepl(MECH, report_reason %||% "") &
              is.finite(qc)]
off[, notional := qc * ifelse(is.finite(pr) & pr>0, pr, 0)]  # signed KRW (price 없으면 shares만)
# 시그널 가용 월 = 필링 접수월(rcept_dt YYYYMMDD → ym). PIT: 접수 시점 공개.
off[, dt := as.character(rcept_dt %||% filing_date)]
off[, sig_ym := substr(gsub("[^0-9]","",dt),1,6)]
off <- off[nchar(sig_ym)==6]
# corp_code → ticker
uni <- fread(".cache/dart/universe_corpcodes.csv", colClasses="character")
off <- merge(off, uni[, .(corp_code, ticker)], by="corp_code", all.x=TRUE)
sig <- off[!is.na(ticker), .(net_notional=sum(notional,na.rm=TRUE), net_shares=sum(qc,na.rm=TRUE),
                             n_off=.N, n_buy=sum(qc>0), n_sell=sum(qc<0)), by=.(ticker, sig_ym)]
cat("[ic] 신호 종목-월:", nrow(sig), "| 순매수(net_notional>0):", sig[net_notional>0,.N],
    "| 순매도:", sig[net_notional<0,.N], "\n")

# ── 3. forward 1M 수익 (RAWDATA 월수익) ──
if (!file.exists(".cache/RAWDATA.parquet")) { cat("[ic] RAWDATA 없음\n"); quit(save="no") }
rd <- as.data.table(open_dataset(".cache/RAWDATA.parquet") |>
        (\(d) dplyr::select(d, Date, Ticker, Close))() |> (\(d) dplyr::collect(d))())
rd[, Date := as.Date(Date)]; rd[, ym := format(Date, "%Y%m")]
mclose <- rd[, .(mc = last(Close[is.finite(Close)])), by=.(Ticker, ym)][is.finite(mc)]
setorder(mclose, Ticker, ym)
mclose[, ret_fwd := shift(mc, -1)/mc - 1, by=Ticker]  # 다음달 수익 (forward)
# 신호 sig_ym 에 forward = 그 다음달 수익 (시그널 접수월 → 익월 실현)
setnames(sig, "ticker", "Ticker")
m <- merge(sig, mclose[, .(Ticker, sig_ym=ym, ret_fwd)], by=c("Ticker","sig_ym"))
m <- m[is.finite(ret_fwd) & is.finite(net_notional)]
cat("[ic] 매칭(신호∩수익):", nrow(m), "월수:", length(unique(m$sig_ym)), "\n")

# ── 4. rank-IC (월별 횡단면 Spearman) ──
ic_by_m <- m[, .(ic = if(.N>=5) cor(rank(net_notional), rank(ret_fwd)) else NA_real_, n=.N), by=sig_ym]
ic_by_m <- ic_by_m[is.finite(ic)]
if (nrow(ic_by_m)>=2) {
  icm <- mean(ic_by_m$ic); ics <- sd(ic_by_m$ic); icir <- icm/ics*sqrt(12)
  post17 <- ic_by_m[sig_ym >= "201701"]
  cat(sprintf("\n[ic] ===== net officer buying rank-IC =====\n"))
  cat(sprintf("[ic] 전기간: mean_IC=%.4f  ICIR=%.2f  n_months=%d  avg_names/m=%.1f\n",
              icm, icir, nrow(ic_by_m), mean(ic_by_m$n)))
  if (nrow(post17)>=2) cat(sprintf("[ic] 2017+  : mean_IC=%.4f  ICIR=%.2f  n_months=%d\n",
              mean(post17$ic), mean(post17$ic)/sd(post17$ic)*sqrt(12), nrow(post17)))
  cat("[ic] ★주의: 부분 데이터(backfill 진행중) — 전구간 완료 후 재실행이 verdict. 현재는 스모크/조기read.\n")
} else cat("[ic] IC 산출 월 부족(신호∩수익 커버리지 낮음 — 데이터 누적 대기)\n")
cat("[ic] DONE\n")
