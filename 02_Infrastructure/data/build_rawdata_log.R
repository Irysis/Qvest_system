#==============================================================================
# build_rawdata_log.R — RAWDATA 로그 변환 캐시 (.cache/rawdata_log.parquet)
#
# 2026-11-16 도훈 "(가) 로그 캐시 파일 하나 더 만드는 방향으로 가서 추후에 다른 전략에도 이 데이터 쓸 수 있게 하자".
# 원천 = .cache/RAWDATA.parquet(퀀티 단독 · 상장 전 행 삭제 뒤) · 밤 갱신 [1y2] 가 RAWDATA 확정 뒤 다시 만든다.
#
# 열(전부 그날 값 또는 같은 수정 기준의 비율 — 미래 기업행위 수정 계수가 상쇄되는 것만):
#   LogRet     = log1p(Ret)                      일 로그 수익률(Ret = 단순 수익률 소수)
#   LogBMRet   = log1p(BM_Ret)                   벤치 일 로그 수익률
#   LogSize    = log(Size)                       로그 시가총액(원 · Size ≤ 0 → NA)
#   LogFloatCap= log(Size × Float / 100)         로그 유동 시가총액(Float = 유동비율 % · 없으면 NA)
#   LogAmount  = log1p(Close × Vol)              로그 거래대금(수정 종가 × 수정 거래량 = 실제 대금 — 수정 계수 상쇄)
#   LogHL      = log(High / Low)                 장중 범위
#   LogCO      = log(Close / Open)               시가 대비 종가
#   LogGap     = log(Open / 전 거래일 Close)       갭(같은 종목 직전 행 · 첫 행 NA)
# ★넣지 않는 것: 로그 거래량 log(Vol) — 수정 거래량 수준도 나중 분할 비율이 과거에 곱해져 있다(GP 설계 점검 11-16 적발 · 거래 활동은 LogAmount)
#   · 로그 주가 수준 log(Open/High/Low/Close) — 수정주가 수준에는 그 뒤 분할 · 증자의 수정 계수가 거꾸로 들어 있다
#   (측정 축 동전주 바닥과 같은 PIT 경계 · pit.md). 수준이 필요하면 원 RAWDATA 를 쓰고 경계를 기록한다.
# 위생 열(AdminStock · TradingHalt · UnfaithfulDisc · K200 · KQ150)은 싣지 않는다 — 소비자가 RAWDATA 와 Date · Ticker 로 붙인다.
# 사용: Rscript build_rawdata_log.R [--root <QM_ROOT>] [--out <경로>]
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
args <- commandArgs(trailingOnly = TRUE)
arg <- function(k, d) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1L] }
ROOT <- gsub("\\\\", "/", arg("--root", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
SRC <- file.path(ROOT, ".cache", "RAWDATA.parquet")
OUT <- arg("--out", file.path(ROOT, ".cache", "rawdata_log.parquet"))
t0 <- proc.time()
if (!file.exists(SRC)) stop("[rawdata-log] RAWDATA 없음: ", SRC)

R <- as.data.table(read_parquet(SRC, col_select = c("Date", "Ticker", "Open", "High", "Low", "Close", "Vol", "Size", "Float", "Ret", "BM_Ret")))
R[, Date := as.Date(Date)]
setorder(R, Ticker, Date)
pos <- function(x) fifelse(is.finite(x) & x > 0, x, NA_real_)
L <- R[, .(Date, Ticker,
           LogRet = fifelse(is.finite(Ret) & Ret > -1, log1p(Ret), NA_real_),
           LogBMRet = fifelse(is.finite(BM_Ret) & BM_Ret > -1, log1p(BM_Ret), NA_real_),
           LogSize = log(pos(Size)),
           LogFloatCap = log(pos(Size * Float / 100)),
           LogAmount = fifelse(is.finite(Vol) & Vol >= 0 & is.finite(Close) & Close > 0, log1p(Close * Vol), NA_real_),
           LogHL = log(pos(High) / pos(Low)),
           LogCO = log(pos(Close) / pos(Open)),
           LogGap = log(pos(Open) / shift(pos(Close)))), by = NULL]
L[R[, .I[1L], by = Ticker]$V1, LogGap := NA_real_]   # 종목 첫 행 = 직전 종가 없음
rm(R); invisible(gc())
num <- setdiff(names(L), c("Date", "Ticker"))
for (k in num) set(L, which(!is.finite(L[[k]])), k, NA_real_)
setkey(L, Date, Ticker)

# 검사: 행 수 = RAWDATA · 키 중복 0 · 수익률 열 비결측률
if (anyDuplicated(L, by = c("Date", "Ticker"))) stop("[rawdata-log] (Date, Ticker) 중복")
tmp <- paste0(OUT, ".tmp")
write_parquet(L, tmp)
if (file.exists(OUT)) unlink(OUT)
if (!file.rename(tmp, OUT)) stop("[rawdata-log] 교체 실패: ", OUT)
cat(sprintf("RAWDATA_LOG rows=%s tickers=%d dates=%s~%s · LogRet NA %.2f%% · LogGap NA %.2f%% · %.0fs\n",
            format(nrow(L), big.mark = ","), uniqueN(L$Ticker), min(L$Date), max(L$Date),
            100 * mean(is.na(L$LogRet)), 100 * mean(is.na(L$LogGap)), (proc.time() - t0)["elapsed"]))
