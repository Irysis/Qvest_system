## FQ-068 PIT 전제 확인 — PPI 발표 지연 실측 (ALFRED vintage)
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[pit] ",fmt,"\n"),...))
key <- Sys.getenv("FRED_API_KEY"); if (!nzchar(key)) key <- FRED_API_KEY

## ALFRED: 각 관측치가 '언제 처음 발표됐는지'(realtime_start) 조회
r <- GET("https://api.stlouisfed.org/fred/series/observations", query=list(
  series_id="PCU334413334413", api_key=key, file_type="json",
  observation_start="2023-01-01", output_type=4L), timeout(30))   # output_type=4 = initial release only
say("HTTP %d", status_code(r))
j <- fromJSON(content(r,"text",encoding="UTF-8"))
o <- as.data.table(j$observations)
o[, `:=`(date=as.Date(date), rt=as.Date(realtime_start))]
o[, lag_days := as.integer(rt - date)]
say("초판 발표 관측 %d건", nrow(o))
print(tail(o[, .(참조월=date, 최초발표일=rt, 지연일=lag_days)], 10))
say("--- 발표 지연 분포 ---")
say("  중앙 %d일 · 최소 %d · 최대 %d", median(o$lag_days), min(o$lag_days), max(o$lag_days))
say("★참조월 M 의 값은 평균 M+%d일에 처음 나온다 ⇒ 홀딩월 시작 전 사용 가능한 최신 참조월 = M-2",
    round(median(o$lag_days)))
