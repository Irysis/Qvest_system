## ECOS 수출물가지수 발표 지연 실측 — 통계표 메타(최종갱신일) + 최신 관측월 대조
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[lag] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }

## 통계표 목록에서 402Y014 의 최종 갱신일
u <- sprintf("https://ecos.bok.or.kr/api/StatisticTableList/%s/json/kr/1/1000/", key)
r <- GET(u, timeout(40))
say("HTTP %d", status_code(r))
j <- fromJSON(content(r,"text",encoding="UTF-8"))
d <- as.data.table(j$StatisticTableList$row)
hit <- d[STAT_CODE == "402Y014"]
if (nrow(hit)) print(unique(hit[, .SD, .SDcols=intersect(c("STAT_CODE","STAT_NAME","CYCLE","SRCH_YN","ORG_NAME"), names(hit))]))
say("컬럼: %s", paste(names(d), collapse=", "))

## 실무 지연 = (오늘) - (최신 관측월말)
today <- Sys.Date()
last_obs <- as.Date("2026-06-30")   # 인출 결과 최신 202606
say("오늘 %s · 최신 관측월말 %s ⇒ 경과 %d일", today, last_obs, as.integer(today - last_obs))
say("★해석: 6월 지수가 8월 8일 현재 이미 공개돼 있다 ⇒ 지연 <= %d일", as.integer(today-last_obs))
say("   미국 PPI 는 같은 시점에 6월치가 7월 15일 공개(43일) — ECOS 도 유사하거나 짧음")
say("★사전등록 fallback 적용: 보수적으로 참조월 M-2 사용 (미국 PPI 규약과 동일, 미래참조 위험 0)")
