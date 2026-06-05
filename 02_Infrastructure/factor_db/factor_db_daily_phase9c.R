##=============================================================================
## factor_db_daily_phase9c.R — M21_Seasonality 구현
## 동월 역사적 수익률 평균 (최근 252일 제외, 최소 504일 역사 필요)
## Heston-Sadka (2008): same-calendar-month return predicts future returns
##=============================================================================

cat("═══ Phase 9c: M21_Seasonality ═══\n")
cat("시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(Rcpp)
})

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")
t0 <- proc.time()

# ─── 1. RAWDATA 로드 + 월간 수익률 계산 ─────────────────────────────────────
cat("[1/3] 월간 수익률 계산...\n")
RW <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(RW, Ticker, Date)

# 월별 수익률 (일간 수익률의 복리 합산)
RW[, YM := format(Date, "%Y%m")]
RW[, CalMonth := as.integer(format(Date, "%m"))]
monthly_ret <- RW[, .(
  MonthRet = prod(1 + Ret, na.rm = TRUE) - 1,
  LastDate = max(Date),
  CalMonth = CalMonth[1]
), by = .(Ticker, YM)]

cat(sprintf("  %s 월간 수익률 (%d tickers)\n\n",
            format(nrow(monthly_ret), big.mark = ","), length(unique(monthly_ret$Ticker))))

# ─── 2. Seasonality 계산 (by=Ticker, 벡터화) ────────────────────────────────
cat("[2/3] Seasonality 계산 (by=Ticker)...\n")
t1 <- proc.time()

# 각 종목의 각 월에 대해: 같은 calendar month의 과거 수익률 평균
# 최근 12개월(252일 ≈ 1년) 제외, 최소 2년치(24개월) 이상 필요
setkey(monthly_ret, Ticker, YM)

SEASON <- monthly_ret[, {
  n <- .N
  seas <- rep(NA_real_, n)
  for (j in seq_len(n)) {
    cm <- CalMonth[j]
    # 같은 달, 현재 제외, 최근 12개월 제외
    past_idx <- which(CalMonth == cm & seq_len(n) < (j - 12L))
    if (length(past_idx) >= 2L) {
      seas[j] <- mean(MonthRet[past_idx], na.rm = TRUE)
    }
  }
  .(YM = YM, M21_Seasonality = seas)
}, by = Ticker]

cat(sprintf("  valid: %d/%d (%.1f%%) — %.1fs\n\n",
            sum(!is.na(SEASON$M21_Seasonality)), nrow(SEASON),
            sum(!is.na(SEASON$M21_Seasonality)) / nrow(SEASON) * 100,
            (proc.time() - t1)["elapsed"]))

# ─── 3. 일간 parquet에 merge ────────────────────────────────────────────────
cat("[3/3] 월별 merge...\n")
t2 <- proc.time()

files <- sort(list.files(FDB_DIR, pattern = "fdb_daily_.*parquet", full.names = TRUE))
pb <- max(1L, length(files) %/% 20L)

for (i in seq_along(files)) {
  ym <- gsub(".*fdb_daily_(\\d+)\\.parquet", "\\1", basename(files[i]))
  dt <- as.data.table(read_parquet(files[i]))

  # 기존 M21 제거
  if ("M21_Seasonality" %in% names(dt)) dt[, M21_Seasonality := NULL]

  # 해당 월 seasonality merge (월간 값 → 일간 모든 행에 동일)
  s_ym <- SEASON[YM == ym, .(Ticker, M21_Seasonality)]
  if (nrow(s_ym) > 0) {
    dt <- merge(dt, s_ym, by = "Ticker", all.x = TRUE)
  } else {
    dt[, M21_Seasonality := NA_real_]
  }

  write_parquet(dt, files[i], compression = "snappy")
  if (i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s\n", i, length(files), ym))
}

total_min <- (proc.time() - t0)["elapsed"] / 60
cat(sprintf("\n═══ Phase 9c 완료 (%.1f분) ═══\n", total_min))

# 검증
dt_check <- as.data.table(read_parquet(file.path(FDB_DIR, "fdb_daily_202012.parquet")))
v <- sum(!is.na(dt_check$M21_Seasonality))
cat(sprintf("  M21_Seasonality: %d/%d (%.1f%%)\n", v, nrow(dt_check), v / nrow(dt_check) * 100))

# 전체 NA 팩터 확인
facs <- setdiff(names(dt_check), c("Date", "Ticker"))
all_na <- sum(sapply(facs, function(f) all(is.na(dt_check[[f]]))))
cat(sprintf("  전체 NA 팩터: %d개\n", all_na))

tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  tg_send(sprintf("✅ [Q-Lead] M21_Seasonality 구축 완료!\n\n📊 동월 역사적 수익률 (Heston-Sadka 2008)\n⏱️ %.1f분 | 전체 NA 팩터: %d개", total_min, all_na))
}, error = function(e) NULL)
