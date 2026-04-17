## 핵심아이디어: Q04(Piotroski F-Score) + L22(Return Autocorrelation)
## 2팩터 EW z-score composite → diversifier (SR 개선 목표)
## Piotroski (2000, TAR): 9-point financial strength → quality signal
## Lo & MacKinlay (1990, RFS): Negate abs(AR(1)) → microstructure signal
## M11 consensus와 3중 직교 diversifier 설계 (quality × liquidity)
##
## PIT 체크리스트:
## C4: Q04 Piotroski → 재무제표 quarterly → Factor DB lag 내부 처리 (Usable_Date)
## C5: L22 Ret Autocorr → Factor DB lag 내부 처리 (Date <= sig_d)
## C10: 유동성 필터 → 20일 평균 거래대금, t-1 lag 적용
## C13: Z_Score_Aligned만 사용. 수동 방향 반전 금지 (both higher_better)
## C14: Usable_Date 기반 접근 (load_month_factors 내부 처리)
## C15: load_month_factors() 경유 필수
## L-591: L22는 Z_Score_Aligned 원시값 그대로. rolling z-score 추가 변환 절대 금지.

cat("[factor_engine] STR_1636: Q04 Piotroski + L22 Ret Autocorr EW composite...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("Q04_Piotroski_F", "L22_Ret_Autocorr")

# RAWDATA 전처리: 월별 시그널 날짜 추출
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
# 재무 팩터 유효 시작: 2005-07 이후 (Q04 Piotroski DART 데이터 안정화)
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]

# 유동성 지표 사전 계산 (C10: 당일 거래량 금지 → 20일 평균, t-1 lag)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"), 1L, type = "lag"),
        by = Ticker]

factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])

  # 유동성 스냅샷 (C10: AvgTV20 = t-1 lag 기반)
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 &
               !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30L) { n_skip <- n_skip + 1L; next }

  # Factor DB 로드 (C15: load_month_factors 경유)
  fdt_all <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) NULL
  )
  if (is.null(fdt_all) || nrow(fdt_all) == 0L) { n_skip <- n_skip + 1L; next }

  # 2팩터 필터
  fdt <- fdt_all[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) { n_skip <- n_skip + 1L; next }

  # Wide format 변환 (C13: Z_Score_Aligned만 사용)
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # 유동성 필터와 join
  dt <- merge(snap, fdt_wide, by = "Ticker")
  fcols <- intersect(NEEDED_FACTORS, names(dt))
  if (length(fcols) == 0L) { n_skip <- n_skip + 1L; next }

  # EW composite: 2팩터 z-score 단순 평균 (feedback_composite_zscore.md 준수)
  # C13: Z_Score_Aligned 그대로 사용 — 방향 반전 없음 (both higher_better)
  # L-591: L22는 Factor DB의 Z_Score_Aligned 원시값만. 추가 rolling z-score 변환 금지.
  # Q04: Piotroski F-score, higher = stronger fundamentals (higher_better)
  # L22: Negate abs(AR(1)), higher = less autocorrelation = better microstructure (higher_better)
  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  dt <- dt[!is.na(Score)]
  if (nrow(dt) < 10L) { n_skip <- n_skip + 1L; next }

  dt[, Date := sig_d]
  factor_list[[i]] <- dt[, .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# 임시 컬럼 정리
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
