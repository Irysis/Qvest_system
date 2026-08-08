## NP-157c2c — cap-tier 별 전이 벽: 소형/중형에서는 방향이 반대인가
## 발단: 상위-2(또는 5) 제거 시 2025+ d 가 음수(-0.0146) → 메가캡 밖에서는 EW 가 cap-w 를 이기는가.
## 방법: 각 월 Size 순위로 tier 배정(MEGA 상위10 · MID 11~30 · OTHER 나머지) 후 **tier 내부**에서
##       d_tier = Σ(tier내 시총가중 × r) − mean(tier내 r) 산출. tier 내부 벤치 대비이므로 tier-beta 제거.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
say <- function(fmt,...) cat(sprintf(paste0("[c2c] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
uni <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0, .(Date,Ticker,Size)]
P <- merge(uni, returns_dt, by=c("Date","Ticker"))
setorder(P, Date, -Size)
P[, rk := seq_len(.N), by=Date]
P[, tier := fifelse(rk<=10,"MEGA", fifelse(rk<=30,"MID","OTHER"))]

## tier 내부 d
TD <- P[, .(d_tier = sum(Size/sum(Size)*Ret_1m) - mean(Ret_1m), n=.N), by=.(Date,tier)]
TD[, year := as.integer(format(Date,"%Y"))]

say("--- tier 내부 d_ann (전 구간 %d개월) ---", uniqueN(TD$Date))
print(TD[, .(n_months=.N, d_ann=round(mean(d_tier)*12,4), med_n=median(n)), by=tier][order(tier)])

say("--- tier 내부 d_ann · 2025+ 제외 vs 2025+ ---")
print(TD[, .(excl2025 = round(mean(d_tier[year<2025])*12,4),
             only2025 = round(mean(d_tier[year>=2025])*12,4)), by=tier][order(tier)])

say("--- 대조: 전체 유니버스 d (tier 무시) ---")
D <- fread(file.path(OUT,"np157c2a1_d_extended.csv")); D[, Date:=as.Date(Date)]
D[, year := as.integer(format(Date,"%Y"))]
say("   전 구간 %+.4f · 2025+ 제외 %+.4f · 2025+ %+.4f",
    mean(D$d)*12, mean(D[year<2025]$d)*12, mean(D[year>=2025]$d)*12)

say("--- tier 내부 d 의 5년 블록 (OTHER 중심) ---")
TD[, era5 := paste0(floor(year/5)*5,"s")]
print(dcast(TD[, .(d_ann=round(mean(d_tier)*12,4)), by=.(era5,tier)], era5 ~ tier, value.var="d_ann"))
fwrite(TD, file.path(OUT,"np157c2c_tier_d.csv"))
say("저장: np157c2c_tier_d.csv")
