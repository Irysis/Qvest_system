# R1 — 리스크 전용 압축 입력 생성 (RAWDATA 1회 로드 → Sector/Vol/Close/Size 스냅샷만 보존)
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/backtest_harness.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
SIG_DATE <- as.Date("2026-08-28")
t0 <- Sys.time()
rl <- load_rawdata(use_cache=TRUE); RD <- rl$RAWDATA; rm(rl); gc(verbose=FALSE)
if(!inherits(RD$Date,"Date")) RD[, Date := as.Date(Date)]
cat("[R1] RAWDATA cols:", paste(names(RD),collapse=","), "\n")
cat("[R1] rows:", nrow(RD), " max Date:", as.character(max(RD$Date)), "\n")
# PIT: sig_date 이후 전면 절단
RD <- RD[Date <= SIG_DATE]
ME <- readRDS(file.path(OUT,"panel.rds"))$ME
# (a) 섹터 맵 — 종목별 최신(<=sig_date) 섹터
sec_col <- intersect(c("Sector","SECTOR","sector"), names(RD))
SEC <- if(length(sec_col)) { setorder(RD, Ticker, Date); RD[, .SD[.N], by=Ticker, .SDcols=sec_col[1]] } else NULL
if(!is.null(SEC)) setnames(SEC, sec_col[1], "Sector")
# (b) 월말 섹터 패널(시변) — 월말 날짜만
SECM <- if(length(sec_col)) unique(RD[Date %in% ME, c("Date","Ticker",sec_col[1]), with=FALSE]) else NULL
if(!is.null(SECM)) setnames(SECM, sec_col[1], "Sector")
# (c) crowding 용 raw 슬림 (Date,Ticker,Close,Vol,Size) — 최근 400영업일만
dts <- sort(unique(RD$Date)); keep <- tail(dts, 400L)
RDS_slim <- RD[Date %in% keep, .(Date, Ticker, Close, Vol, Size)]
# (d) K200/KQ150 멤버십 (최신 월말)
memb <- unique(RD[Date %in% tail(ME,1), .(Ticker, K200, KQ150)])
# (e) ADV20 월말 패널은 panel.rds fwd$liq_dt 에 있음 → 재계산 불필요
saveRDS(list(SEC=SEC, SECM=SECM, RD_slim=RDS_slim, memb=memb, sig_date=SIG_DATE),
        file.path(OUT,"risk_inputs.rds"))
cat("[R1] SEC:", if(is.null(SEC)) 0 else nrow(SEC), " SECM:", if(is.null(SECM)) 0 else nrow(SECM),
    " RD_slim:", nrow(RDS_slim), " memb:", nrow(memb), "\n")
if(!is.null(SEC)) print(head(sort(table(SEC$Sector), decreasing=TRUE), 30))
cat(sprintf("[R1] done %.1fs\n", as.numeric(difftime(Sys.time(),t0,units="secs"))))
