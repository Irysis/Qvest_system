## p1_build_panel.R — WT-R20260829_001 Phase 1: PIT-safe 패널 빌드
## 논문: Chan-Jegadeesh-Lakonishok (1996) Momentum Strategies, JF 51(5) / NBER w5375
## PIT: 신호 = 월말 거래일(t) 시점 factor DB(load_month_factors 경유, C15) ·
##      수익 = t+1 월 forward (build_monthly_forward_returns) · 유동성 = adv20_t1 (C10)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")      # build_monthly_forward_returns / build_adv20_t1
source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT <- "stage_artifacts/WT_R20260829_001"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
FIDS <- c("M02_Mom_6_1","C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m","C04_ESBR")

## ── 1. rawdata (일간) → adv20_t1 자 + 월말 slim ──────────────────────────────
.need <- c("Date","Ticker","Close","Vol","Ret","K200","KQ150","Size","BM_Ret")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need)))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2004-01-01")]
ud <- sort(unique(RAW$Date))
ME  <- as.Date(tapply(as.character(ud), format(ud,"%Y-%m"), max))
ME  <- sort(ME[ME >= as.Date("2005-01-01")])
cat(sprintf("[p1] month-ends %d : %s ~ %s\n", length(ME), min(ME), max(ME)))

ADV20 <- build_adv20_t1(RAW[, .(Date,Ticker,Vol,Close)], at_dates = ME)   # C10: 당일 제외 20일 평균
RAWME <- RAW[Date %in% ME]; rm(RAW); invisible(gc())

fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
RET_DT   <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,   .(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,     .(Date=as.Date(Date), Ticker, adv)]
LIQ_RULER <- attr(fwd$liq_dt, "liq_ruler", exact=TRUE)
cat(sprintf("[p1] liq_ruler=%s | returns %d행 %d월 | bench %d월\n",
    as.character(LIQ_RULER), nrow(RET_DT), uniqueN(RET_DT$Date), nrow(BENCH_DT)))

UNIV <- RAWME[(!is.na(K200) & K200==1) | (!is.na(KQ150) & KQ150==1), .(Date, Ticker, K200=as.integer(!is.na(K200)&K200==1))]
SIZE_DT <- RAWME[is.finite(Size) & Size>0, .(Date, Ticker, Size)]
rm(RAWME); invisible(gc())

## ── 2. factor 패널 (C15: load_month_factors 경유만) ──────────────────────────
pit_rows <- list()
FL <- rbindlist(lapply(ME, function(d){
  x <- tryCatch(load_month_factors(d, coverage_min = 0, factor_names = FIDS),
                error=function(e){cat("[p1][ERR]",as.character(d),conditionMessage(e),"\n"); NULL})
  if (is.null(x) || nrow(x)==0) return(NULL)
  asof <- attr(x, "factor_db_asof_date")
  pit_rows[[as.character(d)]] <<- data.table(Date=d, asof=asof,
      asof_le_sig = isTRUE(!is.na(asof) && asof <= d),
      file = attr(x,"factor_db_file"))
  as.data.table(x)[, .(Date=d, Ticker, Factor_Name, z=Z_Score_Aligned)]
}), fill=TRUE)
PIT_ASOF <- rbindlist(pit_rows)
cat(sprintf("[p1] factor long %d행 | asof<=sig 전월 통과: %s (위반 %d월)\n",
    nrow(FL), all(PIT_ASOF$asof_le_sig), sum(!PIT_ASOF$asof_le_sig)))

FW <- dcast(FL, Date + Ticker ~ Factor_Name, value.var="z")
FW <- merge(FW, UNIV, by=c("Date","Ticker"))     # K200 ∪ KQ150 (C6: 시점별 실제 멤버십)
FW <- merge(FW, LIQ_DT, by=c("Date","Ticker"), all.x=TRUE)
FW <- merge(FW, SIZE_DT, by=c("Date","Ticker"), all.x=TRUE)

write_parquet(FW,       file.path(OUT,"panel_factors.parquet"))
write_parquet(RET_DT,   file.path(OUT,"panel_returns.parquet"))
write_parquet(BENCH_DT, file.path(OUT,"panel_bench.parquet"))
write_parquet(LIQ_DT,   file.path(OUT,"panel_liq.parquet"))
write_parquet(PIT_ASOF, file.path(OUT,"pit_asof.parquet"))
cat(sprintf("[p1] DONE — FW %d행 %d월 %d종목\n", nrow(FW), uniqueN(FW$Date), uniqueN(FW$Ticker)))
