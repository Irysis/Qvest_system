# S1 — 패널 구축 (WT-R20260829_004 · 국면조건부 구성 de-risking)
# 기저 캐리어 = 2/20 cell4 와 동일: JT1993 J=6 skip1 · K200∪KQ150 시변 · top-25 EW · 2005-01~ · 15bps
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/ramp/factor_validation.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")

t0 <- Sys.time()
rl <- load_rawdata(use_cache = TRUE)
RAWDATA <- rl$RAWDATA; BM_DT <- rl$BM_DT; rm(rl); gc(verbose=FALSE)
if (!inherits(RAWDATA$Date,"Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date,"Date"))   BM_DT[, Date := as.Date(Date)]
cat(sprintf("[S1] BM_DT cols: %s\n", paste(names(BM_DT), collapse=",")))
RAWDATA <- RAWDATA[Date >= as.Date("2002-06-01")]
gc(verbose=FALSE)

## 신호: 기저 엔진 그대로
fe_env <- new.env(parent = globalenv()); fe_env$RAWDATA <- RAWDATA; fe_env$BM_DT <- BM_DT
source(file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"), local = fe_env)
FACTORS <- as.data.table(fe_env$FACTORS); rm(fe_env); gc(verbose=FALSE)
FACTORS <- FACTORS[Date >= as.Date("2005-01-01")]
cat(sprintf("[S1] FACTORS: %d rows · %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

## 유니버스 치환 (K200∪KQ150 PIT 시변)
mem <- unique(RAWDATA[Date %in% unique(FACTORS$Date) & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
FACTORS <- merge(FACTORS, mem, by = c("Date","Ticker"))
cat(sprintf("[S1] universe 치환 후: %d rows · %d months · median names %.0f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), median(FACTORS[, .N, by=Date]$N)))

ME <- sort(unique(FACTORS$Date))
ADV20 <- build_adv20_t1(RAWDATA[, .(Date, Ticker, Vol, Close)], at_dates = ME)
SIZE  <- RAWDATA[Date %in% ME & is.finite(Size), .(Date, Ticker, Size)]
RAWME <- RAWDATA[Date %in% ME]
BMM   <- BM_DT[Date %in% ME, .(Date, BM_Close)]

## 일간 패널 — 종목단 실현변동성(σ̂_i) + 슬리브 일간 NAV 용. Date/Ticker/Ret 만.
univ_tk <- unique(FACTORS$Ticker)
DAILY <- RAWDATA[Ticker %chin% univ_tk & is.finite(Ret) & Date >= as.Date("2003-06-01"),
                 .(Date, Ticker, Ret)]
setkey(DAILY, Ticker, Date)
cat(sprintf("[S1] DAILY: %d rows · %d tickers · %s~%s\n", nrow(DAILY), uniqueN(DAILY$Ticker),
            min(DAILY$Date), max(DAILY$Date)))

## 일간 벤치마크 수익 (dtype 정규화 — timestamp[ns] vs date32 조인 사고 방지)
BMD <- BM_DT[order(Date)]
if (!"BM_Ret" %in% names(BMD)) BMD[, BM_Ret := BM_Close/shift(BM_Close) - 1]
BMD <- BMD[is.finite(BM_Ret) & Date >= as.Date("2003-06-01"), .(Date = as.Date(Date), BM_Ret, BM_Close)]
cat(sprintf("[S1] BMD daily: %d rows · %s~%s\n", nrow(BMD), min(BMD$Date), max(BMD$Date)))

rm(RAWDATA); gc(verbose=FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
cat(sprintf("[S1] returns_dt %d · bench %d · liq %d · ruler=%s(%s)\n",
            nrow(fwd$returns_dt), nrow(fwd$bench_dt), nrow(fwd$liq_dt),
            fwd$liq_ruler, fwd$liq_ruler_source))

saveRDS(list(FACTORS=FACTORS, fwd=fwd, SIZE=SIZE, BMM=BMM, ME=ME, DAILY=DAILY, BMD=BMD),
        file.path(OUT, "panel.rds"))
cat(sprintf("[S1] done elapsed=%.1fs\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))
