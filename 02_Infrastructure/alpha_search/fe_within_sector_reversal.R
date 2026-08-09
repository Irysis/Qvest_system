# within_sector_reversal — 섹터-중립 단기역전
# Source: Döbelt (2026) arXiv:2608.05755 "Cross-Sectional Heterogeneity in LSTM Networks"
#   LSTM + sector embeddings attribution → predictive signal is sector-neutral short-term reversal
# Signal: Score_i = -(r_{i,t} - sector_avg_{r_t})
#   r_{i,t}        : 종목 i의 당월 수익률 (month-end t close vs month-end t-1 close)
#   sector_avg_r_t : 동일 KRX 섹터 유니버스 내 평균 수익률 (LiqPass=TRUE 기준)
#   음수 부호: 섹터-조정 저성과 종목 long (역전 기대)
# Differentiator vs M02/fe_streversal: 섹터 공통 드리프트 제거 → 순수 stock-specific 역전
# PIT: signal at month-end t uses Close[t] / Close[t-1 month-end] - 1 (완료 정보, C2/C3 클린)
# Guard: 섹터 내 유니버스 < 3종목이면 해당 종목 제외 (통계 불안정)
#         섹터 코드 없는 종목 → 전체 유니버스 평균 대체 (not skip)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# Step 1: Month-end dates
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me_dates <- RAWDATA[, .(me_date = max(Date)), by = .ym]$me_date

# Step 2: Month-end panel (Close + Sector + LiqPass)
.me <- RAWDATA[Date %in% .me_dates, .(Date, Ticker, Close, Sector, LiqPass)]
setorder(.me, Ticker, Date)

# Step 3: Monthly return (PIT-safe: Close[t] / Close[t-1 month-end] - 1)
.me[, .ret_m := Close / shift(Close) - 1, by = Ticker]

# Step 4: Named-sector averages (LiqPass=TRUE universe only)
.named_avg <- .me[
  LiqPass == TRUE & is.finite(.ret_m) & !is.na(Sector) & Sector != "",
  .(sec_avg = mean(.ret_m, na.rm = TRUE)),
  by = .(Date, Sector)
]

# Step 5: Global average fallback (for NA/blank sector stocks)
.global_avg <- .me[
  LiqPass == TRUE & is.finite(.ret_m),
  .(sec_avg_global = mean(.ret_m, na.rm = TRUE)),
  by = Date
]

.me <- merge(.me, .named_avg, by = c("Date", "Sector"), all.x = TRUE)
.me <- merge(.me, .global_avg, by = "Date", all.x = TRUE)

# Fallback: no sector → use global average
.me[is.na(sec_avg) | is.na(Sector) | Sector == "", sec_avg := sec_avg_global]

# Step 6: Sector size check (min 3 in universe per month)
.sec_n <- .me[
  LiqPass == TRUE & is.finite(.ret_m) & !is.na(Sector) & Sector != "",
  .(.nsec = .N),
  by = .(Date, Sector)
]
.me <- merge(.me, .sec_n, by = c("Date", "Sector"), all.x = TRUE)

# Step 7: Within-sector reversal score
.me[, .Score := -(.ret_m - sec_avg)]

# Step 8: Filter — LiqPass + finite score + sector size guard
# Stocks with NA/blank sector use global avg → pass size guard (nsec NA → allow)
FACTORS <- .me[
  LiqPass == TRUE & is.finite(.Score) &
    (is.na(Sector) | Sector == "" | (!is.na(.nsec) & .nsec >= 3)),
  .(Date, Ticker, Score = .Score)
]

# Cleanup temp column from RAWDATA
RAWDATA[, .ym := NULL]

cat(sprintf("[within_sector_reversal] FACTORS rows=%d | signal dates=%d | avg_n_per_date=%.0f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            nrow(FACTORS) / max(1, uniqueN(FACTORS$Date))))
