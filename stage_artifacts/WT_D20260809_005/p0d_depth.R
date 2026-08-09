## P0d — 기전 확정: .cons_history() 이력 깊이 실측 (추론 아닌 측정)
## 빌더가 CONSENSUS 를 만드는 경로를 그대로 재현해 sue/esbr 원천의 (Ticker × Date) 깊이를 잰다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[p0d] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/config.R")

## 빌더 425~434행 재현: consensus parquet 들을 이름별로 읽는다
b <- readLines("02_Infrastructure/factor_db/factor_db_builder.R", warn=FALSE)
cat(paste0(sprintf("%5d| ", 418:436), b[418:436]), sep="\n")

cfs <- sort(Sys.glob(file.path(CACHE_DIR, "consensus", "*.parquet")))
if (!length(cfs)) cfs <- sort(Sys.glob(".cache/consensus/*.parquet"))
say("consensus 원천 파일 %d개: %s", length(cfs), paste(basename(cfs), collapse=", "))

for (cf in cfs) {
  nm <- tools::file_path_sans_ext(basename(cf))
  dt <- as.data.table(read_parquet(cf))
  if (!all(c("Date","Ticker") %in% names(dt))) { say("  %-14s 컬럼 %s (Date/Ticker 부재)", nm, paste(names(dt),collapse=",")); next }
  dt[, Date := as.Date(Date)]
  nd <- uniqueN(dt$Date)
  say("  %-14s %8d행 · 고유 Date %4d (%s ~ %s) · 고유 Ticker %5d · 컬럼 %s",
      nm, nrow(dt), nd, min(dt$Date), max(dt$Date), uniqueN(dt$Ticker), paste(names(dt), collapse=","))
  ## ★핵심: 특정 sig_date 기준 Ticker 당 이력 깊이
  for (sd_ in as.Date(c("2010-06-30","2020-06-30","2026-07-31"))) {
    h <- dt[Date <= sd_]
    if (!nrow(h)) { say("      sig=%s: 이력 0행", sd_); next }
    dep <- h[, .N, by=Ticker]$N
    say("      sig=%s ⇒ Ticker당 이력 깊이: 중앙 %.0f · 최소 %d · 최대 %d · 깊이>=2 비율 %.4f · 깊이>=4 비율 %.4f",
        sd_, median(dep), min(dep), max(dep), mean(dep>=2), mean(dep>=4))
  }
}
say("완료")
