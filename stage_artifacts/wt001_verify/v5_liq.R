suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
say <- function(...) cat(sprintf(...), "\n")
sch <- open_dataset(".cache/RAWDATA.parquet", format="parquet")
say("[COLS] %s", paste(names(sch), collapse=", "))
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close","Vol")))[, Date:=as.Date(Date)]
say("[SHAPE] RAWDATA nrow=%d DAILY n_day=%d", nrow(R), uniqueN(R$Date))
s <- R[Ticker=="A005930" & Date>=as.Date("2024-01-01") & Date<=as.Date("2024-01-31")][order(Date)]
say("[SAMPLE A005930 2024-01] Vol 일별: %s", paste(format(head(s$Vol,10), big.mark=","), collapse=" | "))
say("  -> 일별 변동계수 %.3f (0 에 가까우면 이미 이동평균)", sd(s$Vol)/mean(s$Vol))
# 월말 1일 거래대금 vs 20일 평균 거래대금 비교: eligible 판정 차이
setkey(R, Ticker, Date)
R[, adv20 := frollmean(Vol*Close, 20L, align="right"), by=Ticker]
R[, ym := format(Date,"%Y-%m")]
ME <- R[, .(Date=max(Date)), by=ym]$Date
M <- R[Date %in% ME & is.finite(Close) & is.finite(Vol)]
M[, adv1 := Vol*Close]
M2 <- M[is.finite(adv20)]
say("[LIQ] 월말행 n=%d : adv1>=2e8 %.4f · adv20>=2e8 %.4f · 판정 불일치 %.4f",
    nrow(M2), mean(M2$adv1>=2e8), mean(M2$adv20>=2e8), mean((M2$adv1>=2e8)!=(M2$adv20>=2e8)))
say("[LIQ] median adv1=%.3e median adv20=%.3e  cor(rank)=%.3f", median(M2$adv1), median(M2$adv20),
    cor(frank(M2$adv1), frank(M2$adv20)))
