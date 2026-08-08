## M26 라운드 사전 프로브 — ★입력 실측 우선 (행수·관측단위·범위) + 커넥터 경유 타이밍
## 규약: 측정 첫 출력은 입력 실측 (2026-08-08 일간/월간 혼동 재발방지)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) { cat(sprintf(paste0("[probe] ",fmt,"\n"),...)); flush.console() }

## ---- (1) factor_db 입력 실측 --------------------------------------------
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
say("★factor_db 입력 실측: 월 파일 %d개 · %.2f GB · %s ~ %s",
    length(fp), sum(file.size(fp))/1e9, basename(fp[1]), basename(fp[length(fp)]))

F1 <- as.data.table(read_parquet(fp[length(fp)]))
say("최신월 %s: %d행 · 컬럼 %s", basename(fp[length(fp)]), nrow(F1), paste(names(F1), collapse=","))
say("  관측단위 = (Ticker × Factor_Name) long. 고유 Ticker %d · 고유 Factor %d · Date 고유값 %s",
    uniqueN(F1$Ticker), uniqueN(F1$Factor_Name),
    if ("Date" %in% names(F1)) paste(unique(as.character(F1$Date)), collapse="/") else "없음")

TARGET <- c("M26_Revenue_Mom","C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C14_Revenue_Surprise")
fc <- unique(F1$Factor_Name)
for (k in TARGET) say("  %-24s 최신월 존재: %-5s (행 %d)", k, k %in% fc, sum(F1$Factor_Name==k))

## ---- (2) RAWDATA 입력 실측 ----------------------------------------------
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
nd <- uniqueN(RAW$Date); ny <- uniqueN(format(RAW$Date,"%Y-%m"))
say("★RAWDATA 입력 실측: %d행 · 고유 Date %d · 고유 년월 %d ⇒ 관측단위 = %s",
    nrow(RAW), nd, ny, if (nd > ny*1.5) "★일간(daily)" else "월간(monthly)")
say("  범위 %s ~ %s", min(RAW$Date), max(RAW$Date))

## ---- (3) 커넥터 경유 타이밍 (C15) ----------------------------------------
source("02_Infrastructure/factor_db/factor_db_connector.R")
probe_ym <- c("2005-06-30","2015-06-30","2024-06-28")
for (d in probe_ym) {
  t0 <- Sys.time()
  z <- tryCatch(load_month_factors(d, factor_names=TARGET), error=function(e) e)
  el <- as.numeric(difftime(Sys.time(), t0, units="secs"))
  if (inherits(z,"error")) { say("  %s ERROR: %s", d, conditionMessage(z)); next }
  cnt <- z[, .N, by=Factor_Name]
  say("  %s  %.2fs  asof=%s  행 %d  { %s }", d, el,
      as.character(attr(z,"factor_db_asof_date")), nrow(z),
      paste(sprintf("%s:%d", cnt$Factor_Name, cnt$N), collapse=" "))
}
say("프로브 완료")
