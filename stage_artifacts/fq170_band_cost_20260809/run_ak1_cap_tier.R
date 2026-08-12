## AK1 — cap-w 미달이 mega-cap 벤치 아티팩트인가 (라우팅 확정)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AI1: m=12 arm 이 cap-w PORT_t 2.137 미달 / EW-uni 3.593 초과. dual-basis 격차의 정체를 묻는다.
##  ★진단 1: 보유 종목의 cap tier 분포(size_dt) — 밴드 교체가 어느 tier 를 늘리나
##  ★진단 2: 벤치 자체 비교 — cap-w 벤치(BM_Ret) vs EW-유니버스 수익의 시대별 격차
##   AL1 아티팩트: 벤치 격차가 arm 의 tier 노출과 정합(밴드가 non-MEGA 로 이동) → screen_route 등재
##   AL2 실질: tier 이동이 없는데 격차가 있으면 cap-w 미달은 실질
##  AL3 자본 자격 주장 없음
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
sz <- if (!is.null(P$size_dt)) as.data.table(P$size_dt) else NULL
cat("[size_dt]", if (is.null(sz)) "없음" else paste(names(sz), collapse=","), "\n")

B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
D <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
D <- merge(D, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
D <- D[is.na(adv) | adv >= 2e8]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q  := cut(frank(D03_EWMA, ties.method="first"),
              breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
              include.lowest=TRUE, labels=FALSE), by=Date]
if (!is.null(sz) && all(c("Date","Ticker") %in% names(sz))) {
  szc <- setdiff(names(sz), c("Date","Ticker"))[1]
  D <- merge(D, sz[, c("Date","Ticker",szc), with=FALSE], by=c("Date","Ticker"), all.x=TRUE)
  setnames(D, szc, "mcap")
  D[, sz_pct := frank(mcap, ties.method="first")/.N, by=Date]
} else D[, sz_pct := NA_real_]

sel <- function(m) D[, {
  keep <- .SD[order(rk)][seq_len(min(25L-m,.N))]$Ticker
  pool <- .SD[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
  .(Ticker = c(keep,pool)) }, by=Date]

cat("\n=== 진단1: arm 별 시총 분위 프로파일 (1=소형, 1.0=대형) ===\n")
for (m in c(0L,12L,25L)) {
  S <- merge(sel(m), D[, .(Date,Ticker,sz_pct,Ret_1m)], by=c("Date","Ticker"))
  cat(sprintf("  m=%-2d  평균 sz_pct=%s  MEGA(>0.9) 비중=%s  n=%d\n", m,
      if (all(is.na(S$sz_pct))) "NA" else sprintf("%.3f", mean(S$sz_pct, na.rm=TRUE)),
      if (all(is.na(S$sz_pct))) "NA" else sprintf("%.3f", mean(S$sz_pct > 0.9, na.rm=TRUE)),
      uniqueN(S$Date)))
}
cat("\n=== 진단2: 벤치(cap-w) vs EW-유니버스 시대별 연수익 ===\n")
U <- D[, .(ew = mean(Ret_1m)), by=Date]
M <- merge(U, bench, by="Date")
M[, era := ifelse(Date < as.Date("2010-01-01"), "~2009",
           ifelse(Date < as.Date("2017-01-01"), "2010-16", "2017~"))]
print(M[, .(n=.N, EWuni_ann=round(mean(ew)*1200,2), BM_ann=round(mean(BM_Ret)*1200,2),
            gap=round((mean(ew)-mean(BM_Ret))*1200,2)), by=era][order(era)])
cat(sprintf("\n전기간 격차(EW-uni − BM) = %.2f%%p/yr\n", (mean(M$ew)-mean(M$BM_Ret))*1200))
write_json(list(note="AK1 diagnostic", n_months=nrow(M)),
           file.path(OUT,"ak1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
