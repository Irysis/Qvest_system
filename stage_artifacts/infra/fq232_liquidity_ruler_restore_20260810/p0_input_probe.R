## FQ-232 P0 — 입력 실측 (측정 첫 출력 = 입력 실측 규약)
##  목적: (1) rawdata 관측단위·범위 (2) M26 alpha_scores 패널 (3) DEGRADED 발생 조건 재현
##  ★자본 주장 없음. 측정 신뢰 라운드.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq232_liquidity_ruler_restore_20260810")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }

t0 <- Sys.time()
RAWPATH <- ".cache/RAWDATA.parquet"
fi <- file.info(RAWPATH)
say("vintage pin: %s | %.0f bytes | mtime %s", RAWPATH, fi$size, format(fi$mtime))

RAW <- as.data.table(read_parquet(RAWPATH,
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
say("★입력 실측 RAW: %d행 · %d 고유거래일 · %d 종목 · %s ~ %s",
    nrow(RAW), uniqueN(RAW$Date), uniqueN(RAW$Ticker), min(RAW$Date), max(RAW$Date))
udates <- sort(unique(RAW$Date))
dpm <- as.integer(table(format(udates, "%Y-%m")))
say("캘린더월당 고유거래일: 중앙 %.0f · min %d · max %d (관측단위 = 일간)",
    median(dpm), min(dpm), max(dpm))
say("Vol*Close 중앙 %.3g KRW (문턱 2e8)", median(RAW$Vol * RAW$Close, na.rm = TRUE))

ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
say("월말 거래일 %d개 (%s ~ %s)", length(ME), min(ME), max(ME))
RAWME <- RAW[Date %in% ME]
dpm_slim <- as.integer(table(format(sort(unique(RAWME$Date)), "%Y-%m")))
say("★slim 패널 실측: %d행 · 캘린더월당 고유거래일 중앙 %.0f  → .daily_ok = %s",
    nrow(RAWME), median(dpm_slim), (median(dpm_slim) >= 15))

## M26 점수 패널
AP <- file.path(ROOT, "stage_artifacts/WT_D20260808_002/alpha_scores.parquet")
say("alpha_scores 존재 = %s", file.exists(AP))
if (file.exists(AP)) {
  A <- as.data.table(read_parquet(AP))
  say("★입력 실측 alpha_scores: %d행 · %d개월 · 컬럼 [%s]",
      nrow(A), uniqueN(A$Date), paste(names(A), collapse = ", "))
  say("  signal_ym %s ~ %s", min(A$signal_ym), max(A$signal_ym))
}

## DEGRADED 발생 재현 (라벨만 — 비용 큰 루프는 P2 에서)
source("02_Infrastructure/ramp/factor_validation.R")
say("build_adv20_t1 존재 = %s", exists("build_adv20_t1", mode = "function"))
fml <- names(formals(build_monthly_forward_returns))
say("현행 시그니처: build_monthly_forward_returns(%s)", paste(fml, collapse = ", "))

## 저장: 이후 단계가 재로딩 없이 쓰도록 slim + ME 캐시 (동일 vintage 고정)
saveRDS(list(vintage = list(path = RAWPATH, bytes = fi$size, mtime = format(fi$mtime)),
             ME = ME,
             raw_rows = nrow(RAW), raw_dates = uniqueN(RAW$Date),
             dpm_med = median(dpm), dpm_slim_med = median(dpm_slim)),
        file.path(OUT, "p0_probe.rds"))

## 20일-자 사전계산 (일간 → 월말 시점값). 이 산출이 P2 A/B 의 '복원' 입력.
t1 <- Sys.time()
ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
say("build_adv20_t1: %d행 · 소요 %.1fs", nrow(ADV20), as.numeric(difftime(Sys.time(), t1, units = "secs")))
say("  adv20 NA %d건 (%.4f%%) · 중앙 %.3g",
    sum(is.na(ADV20$adv)), 100 * mean(is.na(ADV20$adv)), median(ADV20$adv, na.rm = TRUE))
arrow::write_parquet(ADV20, file.path(OUT, "adv20_t1_monthend.parquet"))
say("저장 → adv20_t1_monthend.parquet")

## 1일치 자(구판/DEGRADED 등가) 도 저장 — A/B 대조군
ADV1 <- RAWME[, .(Date, Ticker, adv = Vol * Close)]
arrow::write_parquet(ADV1, file.path(OUT, "adv1_sameday_monthend.parquet"))
say("저장 → adv1_sameday_monthend.parquet (%d행)", nrow(ADV1))

say("총 소요 %.1fs", as.numeric(difftime(Sys.time(), t0, units = "secs")))
