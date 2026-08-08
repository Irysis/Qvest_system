## NP-c-① 위험모델 면 — '담을 수 없는 tier' 가 유발하는 구조적 추적오차(TE) 하한
## 벤치(cap-w)는 MEGA 를 큰 비중으로 담는데 top-25 EW long-only 는 그 비중을 담을 수 없다.
## 그 미보유분만으로 생기는 TE 하한을 계산하면, 현행 TE 예산이 달성 불가 목표인지 판정된다.
## ★완전 재현: TE_floor = sd( Σ_{i∈MEGA}(w_bench,i − w_port,i)·r_i ) 의 하한을
##   포트가 MEGA 를 '최대한' 담는 경우(제약 [0,0.20]·25종)로 잡는다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[te] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker,Size)]
P <- merge(U, ret, by=c("Date","Ticker")); setorder(P, Date, -Size)
P[, `:=`(rk=seq_len(.N), w_bench=Size/sum(Size)), by=Date]

## 시나리오: 포트가 MEGA 를 담는 정도 (제약 [0,0.20]·25종 → MEGA 최대 담기 = 상위 몇 종을 0.20 씩)
scen <- function(n_mega, cap=0.20, lab){
  X <- P[, {
    m <- .SD[rk <= n_mega]
    w_p <- pmin(cap, m$w_bench)            # 포트가 담는 MEGA 비중(캡 적용, 벤치 이하)
    gap <- m$w_bench - w_p                 # 미보유분
    .(miss = sum(gap * m$Ret_1m), gap_w = sum(gap))
  }, by=Date, .SDcols=c("rk","w_bench","Ret_1m")]
  te <- sd(X$miss)*sqrt(12)
  say("%-30s 평균 미보유비중 %5.1f%%  TE 하한 %5.2f%%/yr", lab, mean(X$gap_w)*100, te*100)
  invisible(te)
}
say("--- 전 구간(439m) MEGA 미보유가 만드는 TE 하한 ---")
scen(10, 0.20, "MEGA 10종 · cap 0.20 담기")
scen(10, 0.00, "MEGA 전혀 안 담기")
scen(2,  0.20, "상위 2종만 cap 0.20 담기")
scen(2,  0.00, "상위 2종 안 담기")

say("--- 2025+ 구간(메가캡 집중기) ---")
P25 <- P[Date >= as.Date("2025-01-01")]; P <- P25
scen(10, 0.20, "MEGA 10종 · cap 0.20 담기")
scen(10, 0.00, "MEGA 전혀 안 담기")
scen(2,  0.20, "상위 2종만 cap 0.20 담기")
