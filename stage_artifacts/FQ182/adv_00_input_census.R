## FQ-182 적대검증 STEP 0 — 입력 실측 (가정 금지: 행수·관측단위·범위·에피소드 구조)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv0] ", fmt, "\n"), ...)); flush.console() }

P0 <- readRDS(file.path(OUT, "p0.rds"))
say("p0.rds 최상위 원소: %s", paste(names(P0), collapse = " / "))
D <- as.data.table(P0$D)[order(Date)]
say("=== 입력 실측 ===")
say("  행수 = %d", nrow(D))
say("  컬럼 = %s", paste(names(D), collapse = " / "))
say("  Date class = %s", paste(class(D$Date), collapse = ","))
say("  범위 = %s ~ %s", as.character(min(D$Date)), as.character(max(D$Date)))
dif <- as.numeric(diff(as.Date(D$Date)))
say("  관측단위(일차 간격) 중앙값 %.1f일 · 1일 비율 %.3f · 최대 %.0f일",
    median(dif), mean(dif == 1), max(dif))
say("  고유 Date 수 = %d (중복 %d)", uniqueN(D$Date), nrow(D) - uniqueN(D$Date))
say("  연도 수 = %d (%d~%d) · 연평균 거래일 %.1f",
    uniqueN(year(as.Date(D$Date))), min(year(as.Date(D$Date))), max(year(as.Date(D$Date))),
    nrow(D)/uniqueN(year(as.Date(D$Date))))
say("  BM_Ret: mean %+.6f sd %.6f min %+.4f max %+.4f NA %d",
    mean(D$BM_Ret), sd(D$BM_Ret), min(D$BM_Ret), max(D$BM_Ret), sum(is.na(D$BM_Ret)))
say("  dd252 : min %+.4f max %+.4f NA %d · >0 인 날 %d",
    min(D$dd252), max(D$dd252), sum(is.na(D$dd252)), sum(D$dd252 > 0))

## dd252 정의 실측 재구성 시도 (문서 아닌 데이터로 확인)
D[, roll_max := frollapply(cumprod(1 + BM_Ret), 252, max, align = "right")]
D[, nav := cumprod(1 + BM_Ret)]
D[, dd_recon := nav / frollapply(nav, 252, max, align = "right") - 1]
cc <- D[is.finite(dd_recon) & is.finite(dd252)]
say("  dd252 재구성 대조(252일 롤링 최대 대비): cor %.6f · maxabs 차이 %.6f (n=%d)",
    cor(cc$dd_recon, cc$dd252), max(abs(cc$dd_recon - cc$dd252)), nrow(cc))

## ★에피소드 구조 — 문턱별 ON 일수 / 연속 구간 수 / 최장 구간
say("=== ★문턱별 ON 표본 구조 (독립 에피소드 수가 진짜 표본크기) ===")
say("  문턱     ON일수   비율    에피소드수  최장에피(일)  ON 연도")
for (thr in seq(-0.05, -0.40, by = -0.05)) {
  on <- D$dd252 <= thr
  n1 <- sum(on)
  if (n1 == 0) { say("  %5.0f%%  %6d      -           -           -   -", thr*100, n1); next }
  r <- rle(on); runs <- r$lengths[r$values]
  yrs <- sort(unique(year(as.Date(D$Date[on]))))
  say("  %5.0f%%  %6d  %5.3f  %10d  %12d   %s", thr*100, n1, n1/nrow(D),
      length(runs), max(runs), paste(yrs, collapse = ","))
}
say("=== STEP 0 완료 ===")
