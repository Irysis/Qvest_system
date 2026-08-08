## NP-156b — cap-tilt 증분 천장 1.307 이 momentum 고유인가 유니버스 구조 상수인가
## 착안: 증분 계열 = r_capprop - r_EW (같은 25종목). 이는 **선택된 종목의 사이즈 분산**이 정하지
##       그들을 고른 신호가 정하지 않는다. 무작위 25종목으로도 유사 t 면 구조 상수다.
## ★신호 없음·결정 없음 — 무작위 바스켓의 가중 방식 차이만 잰다(포트폴리오 구성 아님).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[156b] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
nw_t <- function(x, lag=3L){ x <- x[is.finite(x)]; n <- length(x); if (n<20) return(NA_real_)
  m <- mean(x); e <- x-m; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag){ gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/(lag+1))*gl }
  m/sqrt(s/n) }

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker"))
P <- P[Date>=as.Date("2012-12-01") & Date<=as.Date("2026-06-30")]   # R4 OOS 창 163m
say("R4 창 %d개월 · 유니버스 월평균 %.0f종목", uniqueN(P$Date), nrow(P)/uniqueN(P$Date))

draw <- function(seed, K=25L){
  set.seed(seed)
  S <- P[, .SD[sample(.N, min(K,.N))], by=Date]
  S[, .(diff = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m)), by=Date]$diff
}
ts <- sapply(1:60, function(s) nw_t(draw(s)))
say("--- 무작위 25종목 바스켓 60 draw: (시총가중 − 동일가중) 증분의 NW t ---")
say("  중앙값 %.3f · 평균 %.3f · sd %.3f", median(ts), mean(ts), sd(ts))
say("  분위 5%% %.3f · 25%% %.3f · 75%% %.3f · 95%% %.3f",
    quantile(ts,.05), quantile(ts,.25), quantile(ts,.75), quantile(ts,.95))
say("  ★R4 momentum 실측 1.307 의 백분위 = %.1f%%", mean(ts <= 1.307)*100)
say("  ★2.0 문턱 도달 draw = %d/60", sum(ts >= 2.0))
say("--- 대조: cap-tilt 는 무작위 선택에서도 같은 크기의 증분을 낳는가 ---")
say("  |t|>=1.0 draw = %d/60 · t>0 draw = %d/60", sum(abs(ts)>=1.0), sum(ts>0))
