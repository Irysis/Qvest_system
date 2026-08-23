# regime_data_gate.R — mrs 송신 전 데이터-조건 게이트 (2026-07-14 Q, 실사고 수리)
# 사고: 07-14 mrs가 07:12 발사(wake catch-up, 의도 07:30) → DailyRefresh(07:15 완료) 이전
#   vintage(07-10)로 KTRI 전전영업일 차트 발송. 07:10 빌드 KTRI=53.9 "Neutral" vs
#   07:15 신선 재빌드 KTRI=32.3 "Defensive Bias" — 국면 메시지가 실질적으로 달랐다.
# 판정: 브리프가 실제 렌더하는 2개 산출물(unified_regime_signal_daily.parquet +
#   ktri_v3_signals.csv) 둘 다 '전영업일' 도달 시 OK. 전영업일 = 주말 제외 직전 평일 후보를
#   trading_calendar(QW ground truth, realized-only)가 커버하면 휴일 보정, 미커버면 후보 유지.
# 한계(정직): 평일 휴일 다음날 아침은 달력이 후보를 커버 못해 WAIT→타임아웃 경로(~연 수회,
#   최대 30분 지연 후 발송)로 빠질 수 있음 — 침묵-stale 발송보다 우선한다는 설계 선택.
# stdout 마지막 줄: "OK" | "WAIT unified=... v3=... need=..." (mrs_daily_briefing.sh 루프 소비)
suppressPackageStartupMessages({library(arrow); library(data.table)})
root <- Sys.getenv("QM_ROOT", ""); if (!nzchar(root) || !dir.exists(root)) root <- getwd()
setwd(root)

.prev_bd <- function(d) { t <- d - 1; while (format(t, "%u") %in% c("6", "7")) t <- t - 1; t }
need <- .prev_bd(Sys.Date())
cal <- tryCatch(as.Date(as.data.table(read_parquet(".cache/trading_calendar.parquet"))$Date),
                error = function(e) as.Date(character(0)))
## ★2026-08-24 v9.2 S1b — `max()` 가 빈 입력에서 내는 것은 에러가 아니라 **경고 + -Inf** 다.
##   tryCatch(error=) 를 통과하고 is.na() 도 FALSE 라 하류로 흘러간다(형제 사고:
##   paper_research_dispatch.R:83 이 as.Date("-Inf-01") 로 4일 연속 abort).
##   ⇒ 여기서는 **유한성**으로 판정한다. 판독 실패는 '최신'이 아니라 '판정 불가'다.
.fin_date <- function(x, fallback) {
  x <- suppressWarnings(x)
  if (length(x) != 1L || is.na(x) || !is.finite(as.numeric(x))) return(fallback)
  as.Date(x, origin = "1970-01-01")
}
if (length(cal) && is.finite(as.numeric(suppressWarnings(max(cal, na.rm = TRUE)))) &&
    max(cal, na.rm = TRUE) >= need && !(need %in% cal)) {
  .prior <- cal[cal < need]
  if (length(.prior)) need <- max(.prior)   # 빈 집합이면 need 유지(-Inf 로 내려앉지 않는다)
}

last_u <- .fin_date(tryCatch(max(as.Date(as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet"))$Date), na.rm = TRUE),
                   error = function(e) as.Date("1900-01-01")), as.Date("1900-01-01"))
v3p <- "04_Research/regime_comparison/output/ktri_v3_signals.csv"
last_v <- .fin_date(tryCatch(max(as.Date(fread(v3p)$DATE), na.rm = TRUE),
                   error = function(e) as.Date("1900-01-01")), as.Date("1900-01-01"))

if (last_u >= need && last_v >= need) {
  cat("OK\n")
} else {
  cat(sprintf("WAIT unified=%s v3=%s need=%s\n", last_u, last_v, need))
}
