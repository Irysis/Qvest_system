## FQ-182 적대검증 (mechanical_selection) — STEP 0: 입력 실측 + dd252 정의 역공학
## 목적: 귀무 시뮬레이션이 데이터와 **동일한 정의**로 조건을 걸도록 dd252 생성규칙을 확정한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv0] ", fmt, "\n"), ...)); flush.console() }

P0 <- readRDS(file.path(OUT, "p0.rds"))
say("p0.rds 최상위 원소: %s", paste(names(P0), collapse=", "))
D <- as.data.table(P0$D)
say("=== 입력 실측 ===")
say("  행수 = %d · 컬럼 = %s", nrow(D), paste(names(D), collapse=", "))
say("  Date class = %s · 범위 %s ~ %s", class(D$Date)[1], as.character(min(D$Date)), as.character(max(D$Date)))
dd <- as.numeric(diff(as.Date(D$Date)))
say("  연속 Date 간격: median %.1f일 · mean %.2f · max %d  => 관측단위 = %s",
    median(dd), mean(dd), max(dd), if (median(dd) <= 2) "DAILY" else "NON-DAILY")
say("  연도 수 = %d (%d ~ %d) · 연평균 관측 %.1f",
    length(unique(format(as.Date(D$Date), "%Y"))),
    as.integer(format(min(as.Date(D$Date)),"%Y")), as.integer(format(max(as.Date(D$Date)),"%Y")),
    nrow(D)/length(unique(format(as.Date(D$Date), "%Y"))))
say("  BM_Ret: mean %.6f · sd %.6f · min %.4f · max %.4f · NA %d",
    mean(D$BM_Ret), sd(D$BM_Ret), min(D$BM_Ret), max(D$BM_Ret), sum(is.na(D$BM_Ret)))
say("  dd252 : min %.4f · median %.4f · max %.4f · NA %d",
    min(D$dd252), median(D$dd252), max(D$dd252), sum(is.na(D$dd252)))
say("  dd252 <= -10%%/-20%%/-30%% 일수 = %d / %d / %d",
    sum(D$dd252<=-0.10), sum(D$dd252<=-0.20), sum(D$dd252<=-0.30))

## ---- dd252 정의 역공학 -------------------------------------------------------
has_frollmax <- exists("frollmax", where = asNamespace("data.table"))
say("  data.table::frollmax 존재 = %s (version %s)", has_frollmax, as.character(packageVersion("data.table")))
rmax_w <- function(x, k) {
  if (has_frollmax) return(data.table::frollmax(x, k, align = "right"))
  data.table::frollapply(x, k, max, align = "right")
}
idx <- cumprod(1 + D$BM_Ret)
for (k in c(252L, 250L)) {
  rm_ <- rmax_w(idx, k)
  cand <- idx / rm_ - 1
  ok <- is.finite(cand) & is.finite(D$dd252)
  say("  [정의검정 k=%d] cor = %.6f · max|diff| = %.6f · n_cmp = %d",
      k, suppressWarnings(cor(cand[ok], D$dd252[ok])), max(abs(cand[ok] - D$dd252[ok])), sum(ok))
}
## 관측 시작점 기준(첫 251일 NA 제거 여부) 진단
rm252 <- rmax_w(idx, 252L)
say("  첫 유효 rollmax index = %d (즉 D 는 rollmax 워밍업 %s)",
    which(is.finite(rm252))[1], if (which(is.finite(rm252))[1] == 1) "제거 후 저장 아님" else "포함")
saveRDS(list(D = D, idx = idx), file.path(OUT, "adv_ms_input.rds"))
say("=== STEP 0 완료 ===")
