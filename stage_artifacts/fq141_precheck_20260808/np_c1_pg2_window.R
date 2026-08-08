## NP-c1 — PG2 baseline 측정 창의 벤치 핸디캡 d 실측 (라벨 산출, 보정 아님)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
D <- fread(file.path(OUT, "np157c2a1_d_extended.csv"))
D[, Date := as.Date(Date)]; setorder(D, Date)
say <- function(fmt, ...) cat(sprintf(paste0("[np-c1] ", fmt, "\n"), ...))
say("확장 d 계열 %d개월 (%s ~ %s)", nrow(D), min(D$Date), max(D$Date))

win <- function(lo, hi, lab) {
  w <- D[Date >= as.Date(lo) & Date <= as.Date(hi)]
  say("%-28s %s~%s  n=%3d  d_ann=%+.4f  (월 %+.5f)", lab, lo, hi, nrow(w),
      mean(w$d)*12, mean(w$d))
  invisible(mean(w$d)*12)
}
say("--- PG2 baseline 후보 창 ---")
win("2004-02-01","2026-06-30","269m clean (admit baseline)")
win("2004-02-01","2026-08-31","live series 전체 271m")
win("2005-02-01","2026-05-31","256m S3")
win("2001-08-01","2026-03-31","296m window")

say("--- 대조: 최근 짧은 창 ---")
win("2025-01-01","2026-07-31","최근 19m")
win("2023-08-01","2026-07-31","최근 36m")
say("--- 대조: 순풍기 ---")
win("2010-01-01","2014-12-31","2010~2014 순풍기")
