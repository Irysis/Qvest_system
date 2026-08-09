## A1b — FAC 재빌드 (load_month_factors 산출 컬럼은 Z_Score_Aligned = C13 정합)
## a1 초판이 "Z_Score" 를 intersect 해 값 컬럼을 전량 탈락시켰다 → 값 없는 패널이 저장됨.
## ★검사기 0/결측 = 정지 신호 규약대로, 값 컬럼 존재를 assert 한다.
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(future.apply) })
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
say <- function(fmt, ...) cat(sprintf(paste0("[A1b] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds"))
sig_dates <- P$sig_dates
GF <- c("C01_SUE", "C02_EPS_Chg_1m", "M26_Revenue_Mom")

plan(multisession, workers = min(8L, max(1L, parallel::detectCores() - 1L)))
fl <- future_lapply(seq_along(sig_dates), function(i) {
  suppressPackageStartupMessages(library(data.table))
  d <- sig_dates[i]
  x <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = GF),
                error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  x <- as.data.table(x)
  if (!"Z_Score_Aligned" %in% names(x)) return(NULL)
  x[, .(sig_date = d, Ticker, Factor_Name, z = Z_Score_Aligned)]
}, future.seed = TRUE)
plan(sequential)

FAC <- rbindlist(fl, fill = TRUE)
stopifnot("z" %in% names(FAC), nrow(FAC) > 0)
say("FAC %s행 · sig_date %d · z 결측 %.2f%%",
    format(nrow(FAC), big.mark = ","), uniqueN(FAC$sig_date), 100 * mean(is.na(FAC$z)))
print(FAC[, .(n = .N, n_z = sum(!is.na(z)), mean_z = mean(z, na.rm = TRUE),
              sd_z = sd(z, na.rm = TRUE)), by = Factor_Name])

P$FAC <- FAC
saveRDS(P, file.path(OUT, "panels.rds"))
say("panels.rds 갱신 완료")
