# probe_inputs_fu.R — verification_followup 착수 전 입력 실측 (가정 금지)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
say <- function(fmt, ...) cat(sprintf(paste0("[probe] ", fmt, "\n"), ...))

say("=== 1. wt122_results.rds — 보고된 F2/F3 원값 ===")
R <- readRDS(file.path(OUT, "wt122_results.rds"))
say("top-level names: %s", paste(names(R), collapse=", "))
str(R$F2, max.level = 3)
str(R$F3, max.level = 3)

say("=== 2. wt122_addendum.rds ===")
A <- readRDS(file.path(OUT, "wt122_addendum.rds"))
say("names: %s", paste(names(A), collapse=", "))
str(A[grep("F2_size_ctl", names(A))], max.level = 3)

say("=== 3. RAWDATA 컬럼 (Sector 존재 여부) ===")
sch <- arrow::open_dataset(".cache/RAWDATA.parquet")$schema
say("RAWDATA cols: %s", paste(names(sch), collapse=", "))

say("=== 4. 섹터 소스 후보 탐색 ===")
cand <- c(".cache/sector_map.parquet", ".cache/stock_master.parquet",
          ".cache/industry.parquet", ".cache/krx_sector.parquet")
for (p in cand) say("  %s : %s", p, file.exists(p))
lc <- list.files(".cache", pattern = "sector|industry|master|wics|gics|krx", ignore.case = TRUE)
say("  .cache 후보 파일: %s", if (length(lc)) paste(lc, collapse=", ") else "(없음)")
lf <- list.files("02_Infrastructure/factor_db", pattern = "sector|industry", ignore.case = TRUE, recursive = TRUE)
say("  factor_db 후보: %s", if (length(lf)) paste(head(lf, 20), collapse=", ") else "(없음)")
ld <- list.files("02_Infrastructure/data", pattern = "sector|industry", ignore.case = TRUE, recursive = TRUE)
say("  data 후보: %s", if (length(ld)) paste(head(ld, 20), collapse=", ") else "(없음)")

say("=== 5. 발행 패널 형태 ===")
P <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
say("  행 %d · 컬럼 %s", nrow(P), paste(names(P), collapse=", "))
say("  월 %d · %s ~ %s", uniqueN(P$Date), min(P$Date), max(P$Date))

say("=== 6. fwd_cache liq_dt 형태 ===")
fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
say("  fwd names: %s", paste(names(fwd), collapse=", "))
L <- as.data.table(fwd$liq_dt)
say("  liq_dt 행 %d · 컬럼 %s · 월 %d · %s~%s", nrow(L), paste(names(L), collapse=","),
    uniqueN(L$Date), min(L$Date), max(L$Date))
say("  adv 분포: min %.3e / q05 %.3e / med %.3e", min(L$adv, na.rm=TRUE),
    quantile(L$adv, 0.05, na.rm=TRUE), median(L$adv, na.rm=TRUE))
say("  adv < 2e8 비율 %.4f", mean(L$adv < 2e8, na.rm=TRUE))

say("=== 7. 계약 함수 존재 확인 ===")
for (p in c("02_Infrastructure/contracts/canonical_screen_bt.R",
            "02_Infrastructure/contracts/required_effect_size.R",
            "02_Infrastructure/ramp/factor_validation.R")) say("  %s : %s", p, file.exists(p))
