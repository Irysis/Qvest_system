## NP-보고c — 소비면 순회 중 실측 가능 축: 각 모드의 표준 측정 창이 역풍인가 순풍인가
## alpha-search 는 기간 2005~ 고정(헌법), PG2 는 2004-02~, RAMP/FR 은 모듈 소비.
## 창별 핸디캡 조회표에 대입하면 "그 모드의 기존 판정이 오염됐는가"가 바로 나온다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq141_precheck_20260808")
D <- fread(file.path(OUT,"np157c2a1_d_extended.csv")); D[, Date := as.Date(Date)]; setorder(D, Date)
say <- function(fmt,...) cat(sprintf(paste0("[sweep] ",fmt,"\n"),...))

win <- function(lo, hi, lab){
  w <- D[Date >= as.Date(lo) & Date <= as.Date(hi)]
  d <- mean(w$d)*12
  say("%-34s %s~%s  n=%3d  d_ann=%+.4f  %s", lab, substr(lo,1,7), substr(hi,1,7), nrow(w), d,
      if (d < -0.005) "순풍" else if (d > 0.005) "역풍" else "중립")
  invisible(d)
}
say("--- 모드별 표준 측정 창의 벤치 핸디캡 ---")
win("2005-01-01","2026-07-31","alpha-search 고정창(2005~, 헌법)")
win("2004-02-01","2026-06-30","PG2 admit baseline(269m)")
win("2012-12-01","2026-06-30","WT-006/007 OOS 창(163m)")
win("2019-12-01","2026-07-31","계약 재료 패널(80m)")
win("2023-08-01","2026-07-31","최근 36m")
win("2025-08-01","2026-07-31","최근 12m")
