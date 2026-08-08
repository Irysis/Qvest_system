## NP-c3 — 조회표 분산 병기 + 핸디캡의 '기간 구조'
## 발단: 256m(+0.0060) vs 269m(-0.0079) 부호 반전 = 중앙값 단일값 소비 위험 실측.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
D <- fread(file.path(OUT, "np157c2a1_d_extended.csv")); D[, Date := as.Date(Date)]; setorder(D, Date)
say <- function(fmt, ...) cat(sprintf(paste0("[np-c3] ", fmt, "\n"), ...))
say("d 계열 %d개월 (%s ~ %s)", nrow(D), min(D$Date), max(D$Date))

## ── ① 고정 종료월(최신)에서 창 길이별 d = 핸디캡 기간 구조 ────────────────
n <- nrow(D)
lens <- c(6,12,18,24,36,48,60,84,120,150,167,180,200,220,240,256,269,280,300,340,380,420,439)
TS <- rbindlist(lapply(lens[lens<=n], function(L){
  w <- D[(n-L+1L):n]; data.table(len=L, d_ann=mean(w$d)*12, start=min(w$Date))
}))
say("--- 고정 종료(%s)에서 창 길이별 d_ann = 기간 구조 ---", max(D$Date))
print(TS[, .(len, start, d_ann=round(d_ann,4))])
fl <- TS[order(len)][, .(len, d_ann)]
sgn <- sign(fl$d_ann); flips <- which(diff(sgn)!=0)
if (length(flips)) for (i in flips)
  say("  ★부호 반전: len %d (%+.4f) -> len %d (%+.4f)", fl$len[i], fl$d_ann[i], fl$len[i+1], fl$d_ann[i+1])

## ── ② (길이, 종료연도) 셀별 분산 병기 ────────────────────────────────────
dts <- D$Date
cell <- rbindlist(lapply(c(36,120,269), function(L){
  rbindlist(lapply(seq(L, n), function(i){
    w <- D[(i-L+1L):i]
    data.table(len=L, end_year=as.integer(format(max(w$Date),"%Y")), d_ann=mean(w$d)*12)
  }))
}))
Q <- cell[, .(n_win=.N, q25=quantile(d_ann,.25), med=median(d_ann), q75=quantile(d_ann,.75),
              spread=quantile(d_ann,.75)-quantile(d_ann,.25)), by=.(len,end_year)]
say("--- 셀별 사분위 (len 36 / 269, 종료연도 2018~2026) ---")
print(Q[len %in% c(36,269) & end_year>=2018][order(len,end_year)][
  , .(len,end_year,n_win,q25=round(q25,4),med=round(med,4),q75=round(q75,4),spread=round(spread,4))])

say("--- 셀 내 스프레드(q75-q25) 요약: 라벨의 단일값 취약성 ---")
print(Q[, .(median_spread=round(median(spread),4), max_spread=round(max(spread),4)), by=len])
fwrite(TS, file.path(OUT,"np_c3_term_structure.csv"))
fwrite(Q,  file.path(OUT,"np_c3_lookup_quartiles.csv"))
say("저장: np_c3_term_structure.csv · np_c3_lookup_quartiles.csv")
