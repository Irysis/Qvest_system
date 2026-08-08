## NP-c8 — 2026-06/07 반전의 종목 귀속: 삼성/하이닉스 되돌림인가 승자 교체인가
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
say <- function(fmt,...) cat(sprintf(paste0("[np-c8] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
uni <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(uni, returns_dt, by=c("Date","Ticker"))
P[, `:=`(w_cap=Size/sum(Size), w_ew=1/.N), by=Date]
P[, contrib := (w_cap-w_ew)*Ret_1m]

show <- function(lo,hi,lab){
  W <- P[Date>=as.Date(lo) & Date<=as.Date(hi)]
  A <- W[, .(total=sum(contrib), avg_wcap=mean(w_cap)), by=Ticker][order(total)]
  tot <- sum(A$total)
  say("--- %s (%s~%s) d_sum=%+.5f · 월평균 d=%+.5f ---", lab, lo, hi, tot, tot/uniqueN(W$Date))
  say("   [음수 기여 상위 6 = 반전 주도]")
  print(head(A[, .(Ticker, total=round(total,5), avg_wcap=round(avg_wcap,4))],6))
  say("   [양수 기여 상위 4]")
  print(head(A[order(-total), .(Ticker, total=round(total,5), avg_wcap=round(avg_wcap,4))],4))
  A
}
A_rev  <- show("2026-06-01","2026-07-31","반전 2개월")
A_peak <- show("2026-01-01","2026-05-31","정점 구간 2026 1~5월")

say("--- 되돌림 검정: 정점 구간 상위-2 가 반전 구간에서 어디에 있나 ---")
top2 <- head(A_peak[order(-total)]$Ticker,2)
for (t in top2) {
  r <- A_rev[Ticker==t]
  rk <- which(A_rev[order(total)]$Ticker==t)
  say("   %s : 정점기여 %+.5f -> 반전기여 %+.5f (반전구간 음수기여 순위 %d/%d)",
      t, A_peak[Ticker==t]$total, r$total, rk, nrow(A_rev))
}
say("   반전 주도 상위-2 = %s", paste(head(A_rev[order(total)]$Ticker,2), collapse=", "))
say("   정점 주도 상위-2 = %s", paste(top2, collapse=", "))
say("   교집합 = %s", paste(intersect(head(A_rev[order(total)]$Ticker,2), top2), collapse=", "))
