## NP-b2b 사전확인 — cap-rank 버킷별 forward 수익 프로파일에 'mid 혹'이 있는가
## R4 변형은 전부 EW<->cap-w 단조 혼합. mid 에 혹이 있는 비단조 틸트는 미검.
## 혹이 없으면 mid-틸트 설계는 근거가 없다(착수 전 기각). 포트폴리오 미구성 — 버킷 평균만.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[b2b] ",fmt,"\n"),...))
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
P[, bucket := cut(rk, breaks=c(0,10,30,60,100,150,200,300,Inf),
                  labels=c("1-10","11-30","31-60","61-100","101-150","151-200","201-300","300+"))]
P[, uni_ew := mean(Ret_1m), by=Date]
P[, excess := Ret_1m - uni_ew]      # 유니버스 EW 대비 = 버킷의 상대 수익

prof <- function(lo,hi,lab){
  W <- P[Date>=as.Date(lo) & Date<=as.Date(hi)]
  A <- W[, .(n_avg=round(.N/uniqueN(W$Date),1),
             excess_ann=round(mean(excess)*12,4),
             t=round(mean(excess)/sd(excess)*sqrt(.N),2)), by=bucket][order(bucket)]
  say("--- %s (%s~%s, %d개월) — 유니버스 EW 대비 ---", lab, lo, hi, uniqueN(W$Date))
  print(A)
}
prof("1990-01-01","2026-07-31","전 구간")
prof("2012-12-01","2026-06-30","R4 OOS 창")
prof("2017-01-01","2026-07-31","2017+ mega 레짐")
prof("1990-01-01","2024-12-31","2025+ 제외")
