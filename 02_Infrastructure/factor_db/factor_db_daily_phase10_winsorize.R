##=============================================================================
## factor_db_daily_phase10_winsorize.R — Cross-Sectional Winsorizing
## 날짜별 1st/99th percentile capping (월간 DB의 ±3 Z_Score clip과 대응)
## 재현성을 위해 .R 파일로 저장
##=============================================================================

cat("═══ Phase 10: Cross-Sectional Winsorizing ═══\n")

suppressPackageStartupMessages({ library(data.table); library(arrow) })

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))

FDB <- file.path(CACHE_DIR, "factor_db_daily")
files <- sort(list.files(FDB, pattern = "fdb_daily_.*parquet", full.names = TRUE))

# 제외 컬럼 (winsorize 부적절한 팩터)
SKIP <- c("bps_1y","dps_1y","eps_1y","target_price",
          "RE_MRS","RE_exposure","RE_VIX_z","RE_HY_z","RE_TS_z",
          "S01_Size","S02_Float_Size","L26_Log_MktCap","L27_Price_Level","L37_Relative_Vol")

winsorize <- function(x) {
  if (sum(!is.na(x)) < 20L) return(x)
  q01 <- quantile(x, 0.01, na.rm = TRUE)
  q99 <- quantile(x, 0.99, na.rm = TRUE)
  pmin(pmax(x, q01), q99)
}

t0 <- proc.time()
pb <- max(1L, length(files) %/% 20L)

for (i in seq_along(files)) {
  dt <- as.data.table(read_parquet(files[i]))
  fac_cols <- setdiff(names(dt), c("Date", "Ticker"))
  fac_cols <- setdiff(fac_cols, SKIP)
  dt[, (fac_cols) := lapply(.SD, winsorize), .SDcols = fac_cols, by = Date]
  write_parquet(dt, files[i], compression = "snappy")
  if (i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s\n", i, length(files),
        gsub(".*fdb_daily_(\\d+)\\.parquet", "\\1", basename(files[i]))))
}

cat(sprintf("\n═══ Phase 10 완료 (%.1f분) ═══\n", (proc.time() - t0)["elapsed"] / 60))
