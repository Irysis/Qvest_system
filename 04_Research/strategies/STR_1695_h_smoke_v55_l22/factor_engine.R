# STR_1695 Factor Engine — LIQ_THRESHOLD=2e8 frollmean(TradVal,20d) (OPT-10)
#==============================================================================
# H_SMOKE_v55: L22_Ret_Autocorr 단일 팩터 (v55 smoke run)
#
# Mechanism: -|AC1(일간수익률, 252d)| → 낮은 자기상관 = 유동성 프리미엄
#   (Lo & MacKinlay 1988, Amihud & Mendelson 1986 조건부 해석)
#
# PIT 체크리스트:
#   C1:  Factor DB의 rolling 252d 자기상관만 사용 (full-sample 금지)
#   C13: Z_Score_Aligned 그대로 사용 (수동 flip 금지)
#   C14: load_month_factors(sig_date) → Usable_Date <= sig_date 자동 적용
#   C15: load_month_factors() 경유만 허용 (parquet 직접 로드 금지)
#==============================================================================

cat("[factor_engine H_SMOKE_v55] L22_Ret_Autocorr single factor smoke\n")

suppressPackageStartupMessages(library(data.table))

# 필수 변수 기본값 (run_all.R에서 이미 설정되어 있으면 덮어쓰지 않음)
if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

# ---- Factor DB connector 로드 ----
FACTOR_DB_CONN <- file.path(FUNC_PATH, "factor_db", "factor_db_connector.R")
if (!exists("load_month_factors")) source(FACTOR_DB_CONN)

# ---- Signal dates: RAWDATA 월말 기준 ----
monthend_dt <- RAWDATA[, .(sig_date = max(Date)),
                       by = .(ym = format(Date, "%Y-%m"))]
sig_dates <- sort(monthend_dt[sig_date >= as.Date("2004-01-01"), sig_date])

cat(sprintf("[factor_engine] Signal dates: %d months (%s ~ %s)\n",
            length(sig_dates), min(sig_dates), max(sig_dates)))

# ---- Factor DB 로드: L22만 (1회 rbindlist, C15) ----
cat("[factor_engine] Loading L22_Ret_Autocorr via load_month_factors()...\n")

FDB <- rbindlist(lapply(sig_dates, function(sd) {
  dt <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(dt) || nrow(dt) == 0L) return(NULL)
  dt <- dt[Factor_Name == "L22_Ret_Autocorr"]
  if (nrow(dt) == 0L) return(NULL)
  dt[, Date := sd]
  dt
}), use.names = TRUE, fill = TRUE)

if (is.null(FDB) || nrow(FDB) == 0L)
  stop("[factor_engine] L22_Ret_Autocorr not found in Factor DB")

setkey(FDB, Date, Ticker)
cat(sprintf("[factor_engine] FDB: %s rows | %d dates | %d unique tickers\n",
            format(nrow(FDB), big.mark = ","),
            uniqueN(FDB$Date), uniqueN(FDB$Ticker)))

# ---- C13 검증: Z_Score_Aligned 사용, flip 없음 ----
if (!"Z_Score_Aligned" %in% names(FDB))
  stop("[factor_engine] Z_Score_Aligned column missing — C13 violation")

# ---- 유동성 필터 적용 (C10: LiqPass는 run_all.R에서 설정됨) ----
liq_tickers <- unique(RAWDATA[LiqPass == TRUE, Ticker])
FDB <- FDB[Ticker %in% liq_tickers]
cat(sprintf("[factor_engine] After liquidity filter: %d rows\n", nrow(FDB)))

# ---- FACTORS 출력 (Date, Ticker, Score) ----
FACTORS <- FDB[, .(Date, Ticker, Score = Z_Score_Aligned)]
rm(FDB); gc(verbose = FALSE)

cat(sprintf("[factor_engine] FACTORS: %d rows | %d dates | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
