# =============================================================================
# macro_beta_mom_engine_v2.R — macro_beta_momentum 팩터 엔진 (최적화 버전)
# =============================================================================
# 논문: arXiv 2608.12283 "Large Language Model-Driven Small-Capitalization Trading"
# 팩터: pure-beta trigger (rolling 60d OLS beta × 20d macro change)
#
# Score_i,t = sum_j [ beta_ij,t × Δm_j_20d,t ]
#   beta_ij,t = OLS slope 종목i × 팩터j, rolling 60 trading days (t 포함)
#   Δm_j_20d,t = macro_j[t-1] - macro_j[t-21]  (PIT: t-1 이전 데이터)
#
# 최적화: 전체 종목 × 날짜 패널을 사전 계산 후 한 번에 처리
#   - 월별 루프 제거 → 일별 패널 rolling beta 계산 → 월말 slice
#
# 매크로 시계열 (3종 — 전기간 커버리지 있는 일별 시리즈):
#   1. Term_Spread (T10Y2Y)  : 수익률 곡선 기울기
#   2. VIX (VIXCLS)          : 변동성/공포 지수
#   3. KRW_USD (DEXKOUS)     : 원달러 환율
#
# [L4 Fidelity Note] HY_Spread(BAMLH0A0HYM2) 제외 — FRED 원천 2023-08-21~만 제공
# PIT: C1(rolling-only), C2(동일시점 순환 금지), C11(일별 시리즈만)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

suppressWarnings(suppressMessages({
  library(arrow)
  library(data.table)
}))

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

# ---- 1. FRED 일별 매크로 데이터 로드 & wide 변환 --------------------------
.fred_path <- file.path(PROJ, ".cache", "fred_macro.parquet")
stopifnot(file.exists(.fred_path))

.fred_long <- as.data.table(read_parquet(.fred_path))
.target_series <- c("Term_Spread", "VIX", "KRW_USD")

.fred_sub <- .fred_long[Series %in% .target_series & Frequency == "d",
                        .(Date, Series, Value)]
.fred_wide <- dcast(.fred_sub, Date ~ Series, value.var = "Value")
setorder(.fred_wide, Date)

# LOCF: 주말/휴일 NA
for (.col in .target_series) {
  set(.fred_wide, j = .col, value = nafill(.fred_wide[[.col]], type = "locf"))
}
cat(sprintf("[macro_beta_mom_v2] fred_wide rows=%d | %s ~ %s\n",
            nrow(.fred_wide),
            as.character(min(.fred_wide$Date)),
            as.character(max(.fred_wide$Date))))

# ---- 2. 일별 매크로 변화량 (lag 1 — PIT: 당일 FRED 미확정이므로 d-1) -----
# Δm_j[d] = m_j[d] - m_j[d-1]  (다음 단계에서 종목 수익률과 날짜 정렬)
.mac_cols <- .target_series
for (.col in .mac_cols) {
  set(.fred_wide, j = paste0("dm_", .col),
      value = c(NA_real_, diff(.fred_wide[[.col]])))
}

# Δm_j_20d[d] = m_j[d-1] - m_j[d-21]  (PIT: d 기준 1일 전 ~ 21일 전)
# 이를 월말 리밸런스에서 사용: rebal_date = month_end
# fred 날짜 기반 20 calendar days 전 값
.fred_wide[, Date_m1  := shift(Date,  1L)]   # 1일 전 날짜 (참고용)
for (.col in .mac_cols) {
  # d-1 값 (PIT lag): shift(col, 1)
  set(.fred_wide, j = paste0("m1_", .col), value = shift(.fred_wide[[.col]], 1L))
  # d-21 값: 약 20 calendar days 전
  set(.fred_wide, j = paste0("m21_", .col), value = shift(.fred_wide[[.col]], 21L))
}
# Δm_20d 계산
for (.col in .mac_cols) {
  set(.fred_wide, j = paste0("delta20_", .col),
      value = .fred_wide[[paste0("m1_", .col)]] - .fred_wide[[paste0("m21_", .col)]])
}

# ---- 3. RAWDATA 준비 -------------------------------------------------------
setorder(RAWDATA, Ticker, Date)
stopifnot("Ret" %in% names(RAWDATA))

# 유동성 통과 + 2004-01-01 이후만 (rolling 60d 워밍업 위해 2005 이전 필요)
.raw_sub <- RAWDATA[Date >= as.Date("2004-01-01"),
                    .(Date, Ticker, Ret, LiqPass)]

# FRED 날짜와 종목 날짜 alignment: 공통 날짜만
.raw_sub <- merge(.raw_sub, .fred_wide[, c("Date", paste0("dm_", .mac_cols)), with = FALSE],
                  by = "Date", all.x = FALSE)
.raw_sub <- .raw_sub[complete.cases(.raw_sub)]
setorder(.raw_sub, Ticker, Date)

cat(sprintf("[macro_beta_mom_v2] aligned panel: %d rows | %d tickers | %s ~ %s\n",
            nrow(.raw_sub), uniqueN(.raw_sub$Ticker),
            as.character(min(.raw_sub$Date)),
            as.character(max(.raw_sub$Date))))

# ---- 4. rolling 60일 OLS beta 계산 (종목별 data.table 최적화) -------------
# 각 종목에 대해: beta_j = cov(Ret, dm_j) / var(dm_j) over rolling 60 trading days
# 다중회귀 대신 단순 개별 beta × delta20 합으로 근사 (논문 방식)
# 이는 OLS 다중회귀 beta와 동일하지 않으나, 단순 버전은 각 매크로 독립 기여분 근사

# 계산 효율을 위해: 단순 rolling cov/var 방식 (data.table frollapply)
.BETA_WINDOW <- 60L

# 각 매크로 팩터별 rolling beta 계산
for (.col in .mac_cols) {
  .dm_col <- paste0("dm_", .col)
  .beta_col <- paste0("beta_", .col)

  # data.table rolling 계산: by Ticker
  .raw_sub[, (.beta_col) := {
    .n <- .N
    if (.n < .BETA_WINDOW) {
      rep(NA_real_, .n)
    } else {
      # rolling cov(Ret, dm) / var(dm) over 60 days
      sapply(seq_len(.n), function(.i) {
        if (.i < .BETA_WINDOW) return(NA_real_)
        .idx <- (.i - .BETA_WINDOW + 1L):.i
        .r <- Ret[.idx]
        .m <- get(.dm_col)[.idx]
        .valid <- !is.na(.r) & !is.na(.m)
        if (sum(.valid) < 15L) return(NA_real_)
        .r <- .r[.valid]; .m <- .m[.valid]
        .vm <- var(.m)
        if (is.na(.vm) || .vm < 1e-12) return(NA_real_)
        cov(.r, .m) / .vm
      })
    }
  }, by = Ticker]

  cat(sprintf("[macro_beta_mom_v2] beta_%s 계산 완료\n", .col))
}

# ---- 5. 월말 시그널 추출 ---------------------------------------------------
.raw_sub[, .ym := format(Date, "%Y-%m")]
.month_end_dates <- .raw_sub[, .(rebal_date = max(Date)), by = .ym]$rebal_date
.month_end_dates <- sort(.month_end_dates[.month_end_dates >= as.Date("2005-01-01")])

# delta20 값을 fred_wide에서 rebal_date로 lookup
.delta20_dt <- .fred_wide[
  Date %in% .month_end_dates,
  c("Date", paste0("delta20_", .mac_cols)), with = FALSE
]
setnames(.delta20_dt, "Date", "rebal_date")
cat(sprintf("[macro_beta_mom_v2] delta20 available: %d rebal dates\n", nrow(.delta20_dt)))

# 월말 panel: rebal_date에서 각 종목의 beta 값 추출
.panel_end <- .raw_sub[Date %in% .month_end_dates]
setnames(.panel_end, "Date", "rebal_date")

# delta20 merge
.panel_end <- merge(.panel_end, .delta20_dt, by = "rebal_date", all.x = FALSE)

# Score = sum_j (beta_j × delta20_j)
.panel_end[, Score := 0]
for (.col in .mac_cols) {
  .beta_col <- paste0("beta_", .col)
  .d20_col  <- paste0("delta20_", .col)
  .panel_end[!is.na(get(.beta_col)) & !is.na(get(.d20_col)),
             Score := Score + get(.beta_col) * get(.d20_col)]
}

# ---- 6. FACTORS 산출 -------------------------------------------------------
FACTORS <- .panel_end[
  LiqPass == TRUE & is.finite(Score),
  .(Date = rebal_date, Ticker, Score)
]
setorder(FACTORS, Date, Ticker)

cat(sprintf("[macro_beta_mom_v2] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# 임시 컬럼 정리
if (".ym" %in% names(RAWDATA)) RAWDATA[, .ym := NULL]

rm(.raw_sub, .fred_long, .fred_sub, .fred_wide, .panel_end, .delta20_dt)
gc(verbose = FALSE)
