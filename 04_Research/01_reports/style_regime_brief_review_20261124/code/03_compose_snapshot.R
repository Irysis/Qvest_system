## 03_compose_snapshot.R — 오늘 아침(11-24 07:19) 발송 본문을 사본 입력으로 다시 조립한다(발송 없음 · 파일 I/O = 사본만).
##   운영 조립 함수 style_brief_lib.R::sw_compose_brief() 를 그대로 부른다(입력은 전부 인자 — 순수 함수).
##   인자: <사본 폴더> <style_brief_lib.R 경로> [<now KST, 기본 2026-11-24 07:19>]
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE)
SNAP <- a[1]; LIB <- a[2]
NOW <- as.POSIXct(if (length(a) >= 3) a[3] else "2026-11-24 07:19:00", tz = "Asia/Seoul")
source(LIB)
rj <- function(p) tryCatch(jsonlite::fromJSON(file.path(SNAP, p)), error = function(e) NULL)
FF <- as.data.table(read_parquet(file.path(SNAP, "ff5_kr_monthly.parquet")))
SB <- as.data.table(read_parquet(file.path(SNAP, "smartbeta_kr_monthly.parquet")))
out <- sw_compose_brief(FF, SB, mtd5 = rj("ff5_kr_mtd.json"), sbm = rj("smartbeta_kr_mtd.json"),
                        ib = rj("index_factor_beta.json"), now = NOW)
cat(paste(sw_dryrun_lines(out, charts_root = SNAP), collapse = "\n"), "\n")
