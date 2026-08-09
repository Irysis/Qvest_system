## STEP 0b: 워밍업 251일 구간의 dd252 규칙 확정 + fwd1 일치 확인
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv0b] ", fmt, "\n"), ...)); flush.console() }
S <- readRDS(file.path(OUT, "adv_ms_input.rds")); D <- S$D; idx <- S$idx

## 후보 A: 워밍업 = expanding cummax (partial window)
ddA <- idx / cummax(idx) - 1
rm252 <- data.table::frollapply(idx, 252L, max, align = "right")
ddB <- idx / rm252 - 1
w <- 1:251
say("워밍업 1:251 — expanding cummax 정의와 max|diff| = %.8f", max(abs(ddA[w] - D$dd252[w])))
say("전체 8752 — 혼합정의(1:251 expanding, 252+: roll252) max|diff| = %.8f",
    max(abs(c(ddA[w], ddB[252:length(idx)]) - D$dd252)))
say("★확정: dd252 = idx / rollmax(idx, 252, partial=TRUE) - 1")

f1 <- shift(D$BM_Ret, 1L, type = "lead")
say("fwd1 저장본 vs 재계산: max|diff| = %.10f (NA %d)",
    max(abs(D$fwd1 - f1), na.rm = TRUE), sum(is.na(D$fwd1)))
say("★동시점 미사용 확인: cor(dd252[t], BM_Ret[t]) = %+.4f  vs  cor(dd252[t], fwd1[t]) = %+.4f",
    cor(D$dd252, D$BM_Ret), cor(D$dd252[-nrow(D)], D$fwd1[-nrow(D)]))
