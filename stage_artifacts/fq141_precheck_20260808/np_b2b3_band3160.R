## NP-b2b3 사전확인 — 31-60 버킷 음수(-0.0321 t -2.66)가 실재인가 버킷 경계 아티팩트인가
## 오늘 교훈 반영: ①문턱 단일값 취약 ②경계 아티팩트 의심 ③시대별 재현 확인
## 방법: 임의 버킷이 아니라 **슬라이딩 30-폭 창**을 rank 축에 굴려 프로파일을 본다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[b2b3] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker"))
setorder(P, Date, -Size); P[, rk := seq_len(.N), by=Date]
P[, uni_ew := mean(Ret_1m), by=Date]; P[, excess := Ret_1m - uni_ew]

band <- function(D, lo, hi){
  W <- D[rk>=lo & rk<=hi]
  if (!nrow(W)) return(NULL)
  data.table(lo=lo, hi=hi, excess_ann=mean(W$excess)*12,
             t=mean(W$excess)/sd(W$excess)*sqrt(nrow(W)))
}
say("--- 슬라이딩 30-폭 창 (전 구간 439개월) — 경계 아티팩트 점검 ---")
S <- rbindlist(lapply(seq(1, 121, by=5), function(s) band(P, s, s+29)))
print(S[, .(band=paste0(lo,"-",hi), excess_ann=round(excess_ann,4), t=round(t,2))])

say("--- 31-60 의 시대별 재현 ---")
eras <- list(c("1990-01-01","1999-12-31","1990s"), c("2000-01-01","2009-12-31","2000s"),
             c("2010-01-01","2016-12-31","2010-16"), c("2017-01-01","2026-07-31","2017+"))
for (e in eras) {
  D <- P[Date>=as.Date(e[1]) & Date<=as.Date(e[2])]
  b <- band(D,31,60); n1 <- band(D,11,30); n2 <- band(D,61,100)
  say("  %-8s 31-60 %+.4f(t %+.2f) | 이웃 11-30 %+.4f · 61-100 %+.4f",
      e[3], b$excess_ann, b$t, n1$excess_ann, n2$excess_ann)
}
say("--- 세부 분해: 31-40 / 41-50 / 51-60 (전 구간) ---")
for (r in list(c(31,40),c(41,50),c(51,60))) {
  b <- band(P, r[1], r[2]); say("  %d-%d  %+.4f (t %+.2f)", r[1], r[2], b$excess_ann, b$t)
}
