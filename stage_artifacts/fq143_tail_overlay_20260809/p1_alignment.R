## FQ-143 P1 — 홀딩월 정체 확정 (이름이 아니라 실측으로)
## 왜: 패널에 realized_ym / return_ym / anchor_date 3개 시간축이 있고, 어느 것이 홀딩월인지에 따라
##     오버레이 신호의 PIT 컷오프가 통째로 달라진다(BearProb 실사고 = 이 축을 틀린 것).
##     명명 규약을 믿지 않고 시장 월수익과의 정합으로 판정한다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
p <- readRDS(file.path(DIR, "panel_p0.rds"))

bm <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
cat(sprintf("[P1-0] 벤치 일별 실측: n=%d  범위 %s ~ %s  (관측단위=일간)\n", nrow(bm), min(bm$Date), max(bm$Date)))

## 캘린더월 벤치 수익 (일별 복리 — PerformanceAnalytics 표준)
bm[, ym := format(Date, "%Y-%m")]
bmm <- bm[, .(bm_ret = as.numeric(Return.cumulative(xts(BM_Ret, order.by = Date)))), by = ym]
cat(sprintf("[P1-1] 벤치 캘린더월: n=%d  %s ~ %s\n", nrow(bmm), min(bmm$ym), max(bmm$ym)))

## 두 가설 정렬로 상관 비교
tst <- function(key, lab) {
  m <- merge(p[, .(k = get(key), ret_orig)], bmm[, .(k = ym, bm_ret)], by = "k")
  ct <- cor(m$ret_orig, m$bm_ret, use = "complete.obs")
  cat(sprintf("  %-28s n=%3d  cor(ret_orig, bm_ret)=%+.4f\n", lab, nrow(m), ct))
  ct
}
cat("\n=== [P1-2] 홀딩월 판별: ret_orig 가 어느 캘린더월의 시장수익과 붙는가 ===\n")
c_real <- tst("realized_ym", "H1: 홀딩월 = realized_ym")
c_retm <- tst("return_ym",   "H2: 홀딩월 = return_ym")
cat(sprintf("\n  판정: %s (격차 %.4f)\n",
            if (c_real > c_retm) "H1 — 홀딩월 = realized_ym (anchor_date = 홀딩월 첫 거래일)"
            else "H2 — 홀딩월 = return_ym (anchor_date = 홀딩월 다음달 = 구 BearShare 배치)",
            abs(c_real - c_retm)))

## regime 라벨의 시간 정체: 라벨이 어느 달의 시장수익과 가장 붙는가(동월 = look-ahead 의심)
cat("\n=== [P1-3] regime 라벨 시간 정체 (라벨 ON 시 각 시점 시장수익 평균) ===\n")
p[, lab_on := regime %chin% c("CRISIS", "CAUTION")]
bmm[, idx := .I]
getbm <- function(ymv, off) {
  i <- match(ymv, bmm$ym); j <- i + off
  ifelse(!is.na(j) & j >= 1 & j <= nrow(bmm), bmm$bm_ret[pmax(pmin(j, nrow(bmm)), 1)], NA_real_)
}
for (off in -2:2) {
  v_on  <- getbm(p$realized_ym[p$lab_on], off)
  v_off <- getbm(p$realized_ym[!p$lab_on], off)
  cat(sprintf("  realized_ym%+d 월 시장수익:  ON 평균 %+.4f (n=%d)  OFF 평균 %+.4f  차 %+.4f\n",
              off, mean(v_on, na.rm = TRUE), sum(is.finite(v_on)), mean(v_off, na.rm = TRUE),
              mean(v_on, na.rm = TRUE) - mean(v_off, na.rm = TRUE)))
}

## beta_R05 / m4 의 시간 정체도 같은 방식으로 (스케일이 어느 달을 보고 정해졌나)
cat("\n=== [P1-4] 스케일(beta_R05*m4) 시간 정체: 축소월 대비 각 시점 시장수익 ===\n")
p[, scale_cur := beta_R05 * m4]
p[, cut_on := scale_cur < 0.95]
for (off in -2:2) {
  v_on  <- getbm(p$realized_ym[p$cut_on], off)
  v_off <- getbm(p$realized_ym[!p$cut_on], off)
  cat(sprintf("  realized_ym%+d 월 시장수익:  축소ON 평균 %+.4f (n=%d)  OFF %+.4f  차 %+.4f\n",
              off, mean(v_on, na.rm = TRUE), sum(is.finite(v_on)), mean(v_off, na.rm = TRUE),
              mean(v_on, na.rm = TRUE) - mean(v_off, na.rm = TRUE)))
}
saveRDS(list(bmm = bmm, c_real = c_real, c_retm = c_retm), file.path(DIR, "p1_alignment.rds"))
cat("\n[P1 DONE]\n")
