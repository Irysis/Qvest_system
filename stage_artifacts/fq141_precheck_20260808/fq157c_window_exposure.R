# =============================================================================
# fq157c_window_exposure.R — NP-157c: 측정 창 길이가 핸디캡 d 를 얼마나 싣는가
#
# FQ-157 확정: d(cap-w 벤치 − EW 벤치)는 시대 의존이며 2025~2026 에 극단 집중.
# 질문: 2026-06 에 끝나는 측정 창의 **길이**에 따라 평균 d 가 얼마나 달라지는가.
#       짧은(최근) 창일수록 핸디캡이 크다면, 그 창에서 수집된 cap-w 기각은
#       시대 성분을 크게 싣고 있다는 뜻이고, 재측정 우선순위가 창 길이로 정렬된다.
#
# ★포트폴리오 무관 — 벤치 두 계열만. 자체합성 없음(월 평균 기술통계).
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
say <- function(fmt, ...) cat(sprintf(paste0("[fq157c] ", fmt, "\n"), ...))

main <- function() {
  R <- readRDS(file.path(OUT, "fq157_results.rds"))
  D <- as.data.table(R$D)[order(Date)]
  say("입력 d 계열 %d개월 (%s ~ %s)", nrow(D), min(D$Date), max(D$Date))

  ## ── 1. 2026-06 에 끝나는 창 길이별 평균 d ────────────────────────────────
  lens <- c(12, 24, 36, 48, 60, 84, 120, 167)
  rows <- lapply(lens, function(L) {
    if (L > nrow(D)) return(NULL)
    w <- tail(D, L)
    data.table(window_months = L,
               start = min(w$Date), end = max(w$Date),
               d_ann = mean(w$d) * 12,
               capw_ann = mean(w$BM_Ret) * 12,
               ew_ann = mean(w$ew) * 12,
               share_2025plus = mean(w$year >= 2025))
  })
  W <- rbindlist(Filter(Negate(is.null), rows))
  say("--- 2026-06 종료 창 길이별 핸디캡 ---")
  print(W[, .(window_months, d_ann = round(d_ann, 4), capw_ann = round(capw_ann, 4),
              ew_ann = round(ew_ann, 4), share_2025plus = round(share_2025plus, 3))])

  ## ── 2. 2025+ 를 제외하면 핸디캡이 어떻게 되는가 (기여 분해) ──────────────
  ex <- D[year < 2025]
  say("--- 2025+ 제외 (%d개월, %s~%s) ---", nrow(ex), min(ex$Date), max(ex$Date))
  say("    d_ann = %.4f  (전기간 %.4f) — 차이 %.4f", mean(ex$d)*12, mean(D$d)*12,
      mean(D$d)*12 - mean(ex$d)*12)
  inc <- D[year >= 2025]
  say("    2025+ 구간(%d개월) 단독 d_ann = %.4f · 전기간 평균에 대한 기여 = %.4f (%.1f%%)",
      nrow(inc), mean(inc$d)*12,
      (mean(inc$d) - mean(D$d)) * nrow(inc) / nrow(D) * 12,
      abs((mean(inc$d) - mean(D$d)) * nrow(inc) / nrow(D) / mean(D$d)) * 100)

  ## ── 3. 판정 함의: 창 길이별 "핸디캡 지불액"을 PORT_t 단위로 환산 ─────────
  ##    active 표준편차를 알아야 t 환산이 되므로, d 자체의 월 sd 로 하한 감각만 제시.
  say("--- 창 길이별 d 의 t (핸디캡 자체의 유의성, NW 미적용 단순 t) ---")
  TT <- rbindlist(lapply(lens[lens <= nrow(D)], function(L) {
    w <- tail(D, L)
    tt <- tryCatch(t.test(w$d), error = function(e) NULL)
    data.table(window_months = L, d_mean_m = mean(w$d), sd_m = sd(w$d),
               t = if (is.null(tt)) NA_real_ else unname(tt$statistic),
               p = if (is.null(tt)) NA_real_ else tt$p.value)
  }))
  print(TT[, .(window_months, d_mean_m = round(d_mean_m, 5), sd_m = round(sd_m, 4),
               t = round(t, 3), p = round(p, 4))])

  fwrite(W, file.path(OUT, "fq157c_window_exposure.csv"))
  saveRDS(list(W = W, TT = TT), file.path(OUT, "fq157c_results.rds"))
  say("저장: fq157c_window_exposure.csv · fq157c_results.rds")
  invisible(0L)
}

main()
