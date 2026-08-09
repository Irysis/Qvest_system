## FQ-182 P5 — ★2026-07-31 벤치 +19.98% 의 정체 검사
## 왜: 36년 전체 최대 일간값이고, 적대검증이 지목한 live 에피소드의 한복판이다.
##   지수가 하루 +20% 는 2008 최대(+12.2%)를 압도한다 — 물리적으로 극히 이례적.
## ★정체 검사 방법 = **크기 휴리스틱 금지**(memory: feedback-identify-before-existence-check).
##   벤치가 진짜 그날 올랐다면 **개별 종목 수익 분포가 같이 움직여야** 한다.
##   벤치만 +20% 이고 종목 중앙값이 +2% 면 = 데이터 인공물 확정.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

say("=== 1. RAWDATA 에서 해당 일자들의 종목-수준 수익 ===")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Ret","Close","BM_Ret","K200","KQ150")))
RAW[, Date := as.Date(Date)]
tgt <- as.Date(c("2026-07-31","2026-07-28","2026-06-23","2026-03-04","2008-10-30","2008-10-24"))
say("  RAWDATA %d행 · 컬럼 %s", nrow(RAW), paste(names(RAW), collapse=", "))

say("=== 2. ★벤치 vs 종목 분포 대조 (정체 검사의 핵심) ===")
say("   날짜        벤치      종목중앙   종목평균   종목n   |벤치-중앙|")
rows <- list()
for (d in tgt) {
  S <- RAW[Date == d & !is.na(Ret)]
  if (!nrow(S)) { say("  %s : 종목 데이터 없음", format(d)); next }
  bm <- S$BM_Ret[1]
  med <- median(S$Ret); mn <- mean(S$Ret)
  say("  %s  %+8.4f  %+8.4f  %+8.4f  %6d  %8.4f",
      format(as.Date(d)), bm, med, mn, nrow(S), abs(bm - med))
  rows[[length(rows)+1L]] <- data.table(Date = as.Date(d), bm = bm, med = med, mean = mn,
                                        n = nrow(S), gap = abs(bm - med))
}
R <- rbindlist(rows)
say("  ★해석: 정상일이면 |벤치 − 종목중앙| 이 작다. 2008 대조군과 2026 을 비교하라.")

say("=== 3. 전체 기간 |벤치 − 종목중앙| 분포 (기준선) ===")
G <- RAW[!is.na(Ret) & !is.na(BM_Ret), .(bm = BM_Ret[1], med = median(Ret), n = .N), by = Date]
G[, gap := abs(bm - med)]
say("  일자 %d · gap 중앙 %.4f · p95 %.4f · p99 %.4f · 최대 %.4f",
    nrow(G), median(G$gap), quantile(G$gap, .95), quantile(G$gap, .99), max(G$gap))
say("  ★gap 상위 10일:")
for (i in order(-G$gap)[1:10])
  say("    %s  벤치 %+.4f · 종목중앙 %+.4f · gap %.4f (n=%d)",
      G$Date[i], G$bm[i], G$med[i], G$gap[i], G$n[i])

say("=== 4. 2026 연도 진단 ===")
G26 <- G[Date >= as.Date("2026-01-01")]
say("  2026 일자 %d · gap 중앙 %.4f (전체 중앙 %.4f 의 %.1f배)",
    nrow(G26), median(G26$gap), median(G$gap), median(G26$gap)/median(G$gap))
say("  2026 벤치 sd %.4f vs 종목중앙 sd %.4f (배율 %.2f)",
    sd(G26$bm), sd(G26$med), sd(G26$bm)/sd(G26$med))
GG <- G[Date < as.Date("2026-01-01")]
say("  2026 이전 벤치 sd %.4f vs 종목중앙 sd %.4f (배율 %.2f)",
    sd(GG$bm), sd(GG$med), sd(GG$bm)/sd(GG$med))
say("  ★배율이 2026 에서만 크면 = 벤치 계열 고유 결함(종목은 정상)")

say("=== 5. 판정 ===")
g731 <- G[Date == as.Date("2026-07-31")]
if (nrow(g731)) {
  pct <- mean(G$gap <= g731$gap)
  say("  2026-07-31 gap %.4f = 전체 %.2f 백분위", g731$gap, pct*100)
  say("  ⇒ %s", if (g731$gap > quantile(G$gap, .99))
    "★★벤치와 종목이 따로 논다 — **데이터 인공물 강한 의심**" else "종목과 정합 — 실제 시장 움직임")
}
say("  ★이 판정이 중요한 이유: 적대검증이 지목한 live 에피소드 기여(31~43%%)가 이 날에 걸려 있다.")
fwrite(G, file.path(OUT, "p5_bench_stock_gap.csv"))
saveRDS(list(targets = R, gap = G), file.path(OUT, "p5.rds"))
say("=== P5 완료 ===")
