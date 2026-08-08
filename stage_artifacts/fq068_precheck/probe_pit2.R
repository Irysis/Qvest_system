suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[pit] ",fmt,"\n"),...))
key <- Sys.getenv("FRED_API_KEY"); if (!nzchar(key)) key <- FRED_API_KEY

r <- GET("https://api.stlouisfed.org/fred/series/observations", query=list(
  series_id="PCU334413334413", api_key=key, file_type="json",
  observation_start="2024-01-01",
  realtime_start="2024-01-01", realtime_end="9999-12-31"), timeout(40))
say("HTTP %d", status_code(r))
if (status_code(r) == 200) {
  j <- fromJSON(content(r,"text",encoding="UTF-8"))
  o <- as.data.table(j$observations)
  say("vintage 관측 %d행 · 컬럼 %s", nrow(o), paste(names(o), collapse=","))
  o[, `:=`(d=as.Date(date), rs=as.Date(realtime_start))]
  first <- o[, .(first_pub = min(rs)), by=d][order(d)]
  first[, lag_days := as.integer(first_pub - d)]
  print(tail(first, 8))
  say("발표 지연: 중앙 %d일 · 범위 %d~%d", median(first$lag_days), min(first$lag_days), max(first$lag_days))
  say("★참조월 M 값은 M말 기준 약 %d일 뒤 공개 ⇒ 홀딩월 M+1 시작 시점에 확보 가능한 최신 참조월 = %s",
      round(median(first$lag_days)),
      if (median(first$lag_days) <= 31) "M-1 (직전월)" else "M-2")
} else say("본문: %s", substr(content(r,"text",encoding="UTF-8"),1,200))
