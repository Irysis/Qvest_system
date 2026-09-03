# B1-5 실측 보유종목의 시장 귀속 분해 (K200=KOSPI대형 / KQ150=KOSDAQ / 그외)
# 설계 없음 — 이미 측정된 결과의 분해만.
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R")
res <- load_rawdata(TRUE); RAWDATA <- res$RAWDATA; rm(res); gc()
H <- fread("04_Research/strategies/RF_B1_5_MomIlliq/stage/20260829_230711_27764/04_holdings.csv")
H[, date := as.Date(date)]
FL <- RAWDATA[, .(Date,Ticker,K200,KQ150)]
setkey(FL, Date, Ticker)
# 보유일이 시그널일이 아니라 실행일이므로, 각 보유일 이전 최근 영업일 플래그 roll join
setkey(H, date, ticker)
J <- FL[H, on=.(Date=date, Ticker=ticker), roll=Inf]
J[, k2 := !is.na(K200) & K200==TRUE][, kq := !is.na(KQ150) & KQ150==TRUE]
cat("\n== B1-5 보유 슬롯 귀속 (전기간) ==\n")
print(J[, .(slots=.N, K200=sum(k2), KQ150=sum(kq), neither=sum(!k2&!kq),
            KQ150_share=round(mean(kq),3))])
cat("\n== 연도별 보유 슬롯 중 KQ150(코스닥) 비중 ==\n")
print(J[, .(slots=.N, K200=sum(k2), KQ150=sum(kq), neither=sum(!k2&!kq),
            KQ150_share=round(mean(kq),3)), by=.(yr=year(Date))][order(yr)])
cat("\n== 리밸런싱일 수:", uniqueN(J$Date), " 고유 종목:", uniqueN(J$Ticker), "\n")

# ---- Size 컬럼 가용성 (대안 축 권고의 근거 — 설계 아님, 사실 확인) ----
cat("\n== Size / Float 컬럼 결측률 (연도별, 월말) ==\n")
RAWDATA[, .ym := format(Date,"%Y-%m")]
me <- sort(RAWDATA[, .(Date=max(Date)), by=.ym]$Date); RAWDATA[, .ym := NULL]
me <- me[me >= as.Date("2005-01-01")]
S <- RAWDATA[Date %in% me, .(n=.N, size_na=round(mean(is.na(Size)),3),
                             float_na=round(mean(is.na(Float)),3)), by=.(yr=year(Date))]
print(S[order(yr)])
