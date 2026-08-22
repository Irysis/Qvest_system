# =============================================================================
# macro_beta_mom_engine.R — macro_beta_momentum 팩터 엔진
# =============================================================================
# 논문: arXiv 2608.12283 "Large Language Model-Driven Small-Capitalization Trading"
# 팩터: pure-beta trigger (rolling 60d OLS beta × 20d macro change)
#
# Score_i = sum_j [ beta_ij × Δm_j_20d ]
# where:
#   beta_ij = OLS slope from lm(Δr_i ~ Δm_j) over rolling 60 trading days
#   Δm_j_20d = m_j[t-1] - m_j[t-21]  (PIT: t-1 이전 데이터만)
#
# 매크로 시계열 (3종 — 전기간 커버리지 있는 일별 시리즈):
#   1. Term_Spread (T10Y2Y)     : 수익률 곡선 기울기
#   2. VIX (VIXCLS)             : 변동성/공포 지수
#   3. KRW_USD (DEXKOUS)        : 원달러 환율
#
# [L4 Fidelity Note] 논문 원본의 4번째 팩터 HY_Spread(BAMLH0A0HYM2)는
# FRED 원천이 2023-08-21 이후만 제공(롤링 3년 창). 백테스트 기간 2005~2026에서
# 커버리지 부족으로 제외. 3개 팩터로 구현. MEMORY.md 기록 정합.
#
# PIT: C1(rolling-only, 전체표본 통계 금지), C2(동일시점 순환 금지),
#       C11(일별 시리즈만 — 월별 FRED 제외)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

suppressWarnings(suppressMessages({
  library(arrow)
  library(data.table)
}))

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

# ---- 1. FRED 일별 매크로 데이터 로드 및 wide 변환 -------------------------
.fred_path <- file.path(PROJ, ".cache", "fred_macro.parquet")
stopifnot(file.exists(.fred_path))

.fred_long <- as.data.table(read_parquet(.fred_path))
# 일별(d) 시리즈 3종만 선택 (C11: 월별/분기별 시리즈 제외)
.target_series <- c("Term_Spread", "VIX", "KRW_USD")

.fred_sub <- .fred_long[Series %in% .target_series & Frequency == "d",
                        .(Date, Series, Value)]
stopifnot(nrow(.fred_sub) > 0)
cat(sprintf("[macro_beta_mom] FRED rows=%d | series=%s\n",
            nrow(.fred_sub), paste(.target_series, collapse=",")))

# Wide 변환: Date × [Term_Spread, VIX, KRW_USD]
.fred_wide <- dcast(.fred_sub, Date ~ Series, value.var = "Value")
setorder(.fred_wide, Date)

# LOCF 처리: 주말/휴일 NA 채우기 (PIT-safe: 과거 carry-forward)
for (col in .target_series) {
  set(.fred_wide, j = col, value = nafill(.fred_wide[[col]], type = "locf"))
}
cat(sprintf("[macro_beta_mom] fred_wide rows=%d | date: %s ~ %s\n",
            nrow(.fred_wide),
            as.character(min(.fred_wide$Date)),
            as.character(max(.fred_wide$Date))))

# ---- 2. RAWDATA 준비 -------------------------------------------------------
setorder(RAWDATA, Ticker, Date)

# 일별 수익률 확인 (이미 RAWDATA에 Ret 컬럼 존재)
stopifnot("Ret" %in% names(RAWDATA))

# ---- 3. 월말 리밸런스 날짜 목록 -------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym][order(Date)]$Date
.month_ends <- .month_ends[.month_ends >= as.Date("2005-01-01")]
cat(sprintf("[macro_beta_mom] rebalance dates=%d | %s ~ %s\n",
            length(.month_ends),
            as.character(min(.month_ends)),
            as.character(max(.month_ends))))

# ---- 4. 각 리밸런스 날짜에서 Score 계산 -----------------------------------
# beta_window = 60 trading days
# macro_change_window = 20 calendar days
.BETA_WINDOW  <- 60L
.MACRO_WINDOW <- 20L

# FRED date lookup 함수: date d 에서 d 이전 가장 최근 FRED 행 반환 (PIT: t-1 lag)
.fred_lookup <- function(d) {
  # PIT: 당일(d) FRED 미확정 → d-1 이전 최신값 사용
  .idx <- which(.fred_wide$Date < d)
  if (length(.idx) == 0L) return(NULL)
  .fred_wide[max(.idx)]
}

.fred_lookup_n <- function(d, n_days_back) {
  # n_days_back 이전의 날짜에서 FRED 값 반환 (캘린더 일수 기준)
  .cutoff <- d - n_days_back
  .idx <- which(.fred_wide$Date <= .cutoff)
  if (length(.idx) == 0L) return(NULL)
  .fred_wide[max(.idx)]
}

# 종목별 RAWDATA 분리 (효율을 위해 한 번만 분리)
.raw_by_ticker <- split(RAWDATA[, .(Date, Ticker, Ret)], by = "Ticker", keep.by = TRUE)

# 결과 저장
.scores_list <- vector("list", length(.month_ends))

for (.i in seq_along(.month_ends)) {
  .rebal_date <- .month_ends[.i]

  # --- FRED 매크로 값 추출 (PIT: rebal_date 이전 데이터만) ---
  .m_cur <- .fred_lookup(.rebal_date)         # rebal_date - 1 이전 최신
  .m_lag <- .fred_lookup_n(.rebal_date, .MACRO_WINDOW)  # ~20일 전

  if (is.null(.m_cur) || is.null(.m_lag)) {
    .scores_list[[.i]] <- NULL
    next
  }

  # Δm_j_20d: 최근 1일 전 vs 21일 전 (PIT 준수)
  .delta_m <- numeric(length(.target_series))
  names(.delta_m) <- .target_series
  .valid_macro <- TRUE
  for (.j in .target_series) {
    .v_cur <- .m_cur[[.j]]
    .v_lag <- .m_lag[[.j]]
    if (is.null(.v_cur) || is.null(.v_lag) ||
        is.na(.v_cur) || is.na(.v_lag)) {
      .valid_macro <- FALSE
      break
    }
    .delta_m[.j] <- .v_cur - .v_lag
  }
  if (!.valid_macro) {
    .scores_list[[.i]] <- NULL
    next
  }

  # --- 종목별 rolling 60d OLS beta 계산 ---
  # 과거 60 trading days: rebal_date 이전 60거래일 (당일 포함 — 월말 종가)
  # PIT: 과거 데이터만 사용, 동일시점 순환 없음
  .date_cutoff_hi <- .rebal_date  # 월말 종가 포함 OK (당일 종가로 매수 기준)
  .date_cutoff_lo <- RAWDATA[Date <= .date_cutoff_hi, unique(Date)]
  .date_cutoff_lo <- sort(.date_cutoff_lo)
  if (length(.date_cutoff_lo) < .BETA_WINDOW) {
    .scores_list[[.i]] <- NULL
    next
  }
  .window_dates <- tail(.date_cutoff_lo, .BETA_WINDOW)

  # FRED 일별 변화량 (window 내 — PIT-safe: 과거 데이터)
  .fred_window <- .fred_wide[Date %in% .window_dates, ]
  if (nrow(.fred_window) < 10L) {
    .scores_list[[.i]] <- NULL
    next
  }

  # FRED 일별 변화량 계산 (lag 1)
  .fred_window_dt <- copy(.fred_window)
  setorder(.fred_window_dt, Date)
  for (.j in .target_series) {
    set(.fred_window_dt, j = paste0("d_", .j),
        value = c(NA_real_, diff(.fred_window_dt[[.j]])))
  }

  # 각 종목에 대해 OLS beta 계산
  .tickers_in_window <- RAWDATA[Date %in% .window_dates & LiqPass == TRUE,
                                unique(Ticker)]

  .score_rows <- lapply(.tickers_in_window, function(.tk) {
    .r_sub <- RAWDATA[Ticker == .tk & Date %in% .window_dates, .(Date, Ret)]
    if (nrow(.r_sub) < 20L) return(NULL)

    # 날짜 align: 주식 수익률과 FRED 변화량 공통 날짜
    .merged <- merge(.r_sub, .fred_window_dt, by = "Date", all = FALSE)
    # NA 제거 (FRED 변화량 첫 행 NA)
    .macro_cols <- paste0("d_", .target_series)
    .merged <- .merged[complete.cases(.merged[, c("Ret", .macro_cols), with = FALSE])]
    if (nrow(.merged) < 15L) return(NULL)

    # OLS: Ret ~ d_Term_Spread + d_VIX + d_KRW_USD
    .X <- as.matrix(.merged[, .macro_cols, with = FALSE])
    .y <- .merged$Ret
    # 단순 OLS (행렬 연산)
    .XtX <- t(.X) %*% .X
    if (rcond(.XtX) < 1e-12) return(NULL)  # 다중공선성 체크
    .Xty <- t(.X) %*% .y
    .beta_vec <- tryCatch(solve(.XtX, .Xty), error = function(e) NULL)
    if (is.null(.beta_vec)) return(NULL)

    # Score = sum_j(beta_ij × Δm_j_20d)
    .score <- sum(.beta_vec * .delta_m[.target_series])
    if (!is.finite(.score)) return(NULL)

    data.table(Date = .rebal_date, Ticker = .tk, Score = .score)
  })

  .scores_month <- rbindlist(.score_rows, fill = TRUE)
  .scores_list[[.i]] <- if (nrow(.scores_month) > 0L) .scores_month else NULL

  if (.i %% 12L == 0L) {
    cat(sprintf("[macro_beta_mom] rebal %d/%d (%s): n_scores=%d\n",
                .i, length(.month_ends), as.character(.rebal_date),
                nrow(.scores_month %||% data.table())))
  }
}

# ---- 5. FACTORS 산출 -------------------------------------------------------
FACTORS <- rbindlist(.scores_list, fill = TRUE)
FACTORS <- FACTORS[!is.na(Score) & is.finite(Score)]
setorder(FACTORS, Date, Ticker)

# 유동성 통과 종목만 (RAWDATA의 LiqPass 기준)
.liq_pass <- RAWDATA[LiqPass == TRUE, .(Date, Ticker)]
FACTORS <- merge(FACTORS, .liq_pass, by = c("Date", "Ticker"), all = FALSE)

cat(sprintf("[macro_beta_mom] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# 임시 컬럼 정리
if (".ym" %in% names(RAWDATA)) RAWDATA[, .ym := NULL]
