## WT-D20260809_003 (FQ-166) P0b — 동일 프레임 병합 패널 실측
## 목적: 4재료(M26 · Q01_EB · D03_EWMA · M01_PATHQ)를 **동일 행** 위에 올릴 수 있는지, 규모가 라운드를 지탱하는지.
## read-only 진단. 결과에 따라 라운드 설계가 바뀐다(사전 확인이 설계를 바꾼 선례 4/4).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_003")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0b] ", fmt, "\n"), ...)); flush.console() }

W1 <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet"))
M2 <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_002/alpha_scores.parquet"))
W3 <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_003/alpha_scores.parquet"))
for (D in list(W1, M2, W3)) D[, Date := as.Date(Date)]

say("=== 입력 실측 ===")
say("  W1 (D03/Q01/M01) %d행 %d월 %d종목", nrow(W1), uniqueN(W1$Date), uniqueN(W1$Ticker))
say("  M2 (M26)         %d행 %d월 %d종목", nrow(M2), uniqueN(M2$Date), uniqueN(M2$Ticker))
say("  W3 (Q01 중립)    %d행 %d월 %d종목", nrow(W3), uniqueN(W3$Date), uniqueN(W3$Ticker))

A <- merge(W1[, .(Date, Ticker, D03_EWMA, Q01_EB, M01_PATHQ)],
           M2[, .(Date, Ticker, M26_Revenue_Mom)], by = c("Date","Ticker"))
say("=== W1 x M2 내부조인 ===")
say("  %d행 · %d월 (%s ~ %s) · %d종목", nrow(A), uniqueN(A$Date), min(A$Date), max(A$Date), uniqueN(A$Ticker))
say("  W1 대비 잔존율 %.3f · M2 대비 잔존율 %.3f", nrow(A)/nrow(W1), nrow(A)/nrow(M2))
say("  월별 종목수: 중앙 %.0f · 최소 %d · 최대 %d",
    median(A[, .N, by = Date]$N), min(A[, .N, by = Date]$N), max(A[, .N, by = Date]$N))

B <- merge(A, W3[, .(Date, Ticker, z_raw, z_neutral)], by = c("Date","Ticker"), all.x = TRUE)
say("=== + W3 중립판 좌조인 ===")
say("  z_neutral 커버리지 %.4f (%d/%d)", mean(!is.na(B$z_neutral)), sum(!is.na(B$z_neutral)), nrow(B))
say("  z_raw vs Q01_EB 상관(비결측): %.4f",
    suppressWarnings(cor(B$z_raw, B$Q01_EB, use = "complete.obs")))

say("=== 결측 구조 (재료별) ===")
for (k in c("D03_EWMA","Q01_EB","M01_PATHQ","M26_Revenue_Mom","z_neutral"))
  say("  %-16s 비결측 %.4f", k, mean(!is.na(B[[k]])))

say("=== 라운드 성립 판정 ===")
n_mo <- uniqueN(A$Date); n_med <- median(A[, .N, by = Date]$N)
say("  월수 %d (문턱 200) %s · 월중앙 종목 %.0f (decile 당 %.0f, 문턱 10) %s",
    n_mo, n_mo >= 200, n_med, n_med/10, n_med/10 >= 10)
ok <- n_mo >= 200 && n_med/10 >= 10
say("  ★동일-행 프레임 성립: %s", ok)
if (!ok) say("  ★미달 시 대안 = 재료별 자기 유니버스 + 창/분위수만 통일(약한 동일프레임)")

saveRDS(B, file.path(OUT, "merged_panel.rds"))
say("=== P0b 완료 → merged_panel.rds ===")
