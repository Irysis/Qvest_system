## run_02_source_diag.R — coverage.parquet 원천 무결성 진단
##   의심: cov~Size 상관 +0.016(비정상적으로 0 근접) + 연도별 중앙값 요동(1→15→1→13) + 중앙값0 달 23개
##   가설: 원천 날짜 갭(수동 export 공백) → 30일 as-of 창이 전원 0 처리 → 게이트가 '데이터 갭 지표'로 오염
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(4)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_008"

cov <- as.data.table(read_parquet(".cache/consensus/coverage.parquet"))
cov[, Date := as.Date(Date)]

## [1] 날짜 연속성 — 월별 관측일수 + 최대 갭
dts <- sort(unique(cov$Date))
gap <- data.table(d = dts, gap_prev = c(NA, as.numeric(diff(dts))))
cat("[갭] 관측일 간격 > 7일 (상위 20):\n")
print(head(gap[gap_prev > 7][order(-gap_prev)], 20))
mo <- data.table(d = dts)[, .(n_days = .N), by = .(ym = format(d, "%Y-%m"))]
cat(sprintf("[월별 관측일수] 월수=%d  n_days 분포: min=%d q25=%.0f med=%.0f max=%d | n_days<5 인 달=%d\n",
            nrow(mo), min(mo$n_days), quantile(mo$n_days,.25), median(mo$n_days), max(mo$n_days),
            sum(mo$n_days < 5)))
print(mo[n_days < 5])

## [2] 월별 커버 티커수 시계열 (요동 진단)
tk <- cov[, .(n_tk = uniqueN(Ticker), med_cov = median(coverage)), by = .(ym = format(Date, "%Y-%m"))][order(ym)]
cat("[월별 커버 티커수] 분포: "); print(quantile(tk$n_tk, c(0,.25,.5,.75,1)))
cat("[커버 티커수 < 200 인 달]:\n"); print(tk[n_tk < 200])

## [3] 개별 대형주 시계열 스팟체크 — 삼성전자(005930) 커버리지 연속성
sam <- cov[Ticker %in% c("005930", "A005930", "KR7005930003")]
cat(sprintf("[삼성전자] rows=%d  ticker형=%s\n", nrow(sam), paste(unique(sam$Ticker), collapse=",")))
if (nrow(sam) == 0) { cat("  → ticker 포맷 확인 필요. 샘플 5개:\n"); print(head(unique(cov$Ticker), 5)) }
if (nrow(sam) > 0) {
  sam <- sam[order(Date)]
  sg <- data.table(d = sam$Date, gap = c(NA, as.numeric(diff(sam$Date))))
  cat(sprintf("  기간 %s~%s  관측 %d일  갭>30일 구간 = %d\n", min(sam$Date), max(sam$Date), nrow(sam), sum(sg$gap > 30, na.rm=TRUE)))
  print(head(sg[gap > 30][order(-gap)], 10))
  yr <- sam[, .(med = median(coverage), mx = max(coverage)), by = year(Date)]
  cat("  삼성전자 연도별 커버리지 중앙값/최대:\n"); print(yr)
}
cat("[DONE]\n")
