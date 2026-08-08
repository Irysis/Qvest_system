## NP-c2c3 — R4 mid_universe 실패가 tier-beta 탓인가 신호 탓인가
## R4: "MID 좁힐수록 cap-w 는 음(-1.106)이나 EW-uni 는 양(+1.526) = 순수 벤치-미스매치 지문,
##      tier-beta(MID-minus-mega, 2017+ mega 레짐서 음)가 지배 → 실현 불가"
## 여기서는 그 tier-beta 를 **직접 계량**한다: tier EW 수익 − cap-w 유니버스 벤치.
## 이 drag 가 크면 R4 실패의 상당분은 기계적이고, 작으면 신호 문제다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
say <- function(fmt,...) cat(sprintf(paste0("[c2c3] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
uni <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(uni, returns_dt, by=c("Date","Ticker"))
setorder(P, Date, -Size); P[, rk := seq_len(.N), by=Date]
P[, tier := fifelse(rk<=10,"MEGA", fifelse(rk<=30,"MID","OTHER"))]

BM <- P[, .(bm_capw = sum(Size/sum(Size)*Ret_1m)), by=Date]
TR <- P[, .(tier_ew = mean(Ret_1m)), by=.(Date,tier)]
X  <- merge(TR, BM, by="Date"); X[, drag := tier_ew - bm_capw]

rng <- function(lo,hi,lab){
  W <- X[Date>=as.Date(lo) & Date<=as.Date(hi)]
  say("--- %s (%s~%s, %d개월) ---", lab, lo, hi, uniqueN(W$Date))
  print(W[, .(drag_ann=round(mean(drag)*12,4), t=round(mean(drag)/sd(drag)*sqrt(.N),2)), by=tier][order(tier)])
}
rng("2012-12-01","2026-06-30","R4 OOS 창 163m")
rng("1990-01-01","2026-07-31","전 구간")
rng("2017-01-01","2026-07-31","2017+ mega 레짐")
rng("1990-01-01","2024-12-31","2025+ 제외")

say("--- 해석 보조: R4 baseline momentum port_t = 1.277, mid 변형 최선 1.044 / 최악 -1.106 ---")
say("    tier drag 가 연 -5%% 수준이면 top-25 포트의 net active 에 기계적으로 실린다.")
