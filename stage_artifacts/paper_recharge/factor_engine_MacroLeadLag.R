# =============================================================================
# factor_engine_MacroLeadLag.R — MacroLeadLag_PureBeta 알파 서칭
# =============================================================================
# 가설: 매크로 지표(예: BBB 신용스프레드, KRW/USD, VIX, 산업생산)가 먼저 움직인 후
#       해당 지표에 beta가 높은 종목이 후행해서 반응하는 현상을 포착.
#
# 신호 = signal_i = sum_m [ beta_{i,m} * delta_macro_m_lagged ]
#   beta_{i,m}: 과거 12개월 롤링 회귀 (월별 Ret_i ~ delta_macro_m), IS 데이터만
#   delta_macro_m: 매크로 지표의 전월대비 변화율, PIT lag 준수 (t-2 사용)
#
# PIT 준수:
#   C1: rolling window 12개월, 동일시점 순환참조 없음
#   C5: 신호는 홀딩월 시작 전 데이터만 (t-2 매크로 사용으로 동월 look-ahead 차단)
#   C11: 계열별 publication lag 적용
#         - Monthly (US_CPI, US_IndProd, US_Unemployment, Housing_Permits,
#                    UMich_Sentiment, Fed_Funds_Rate, US_M2, Copper_Price): +2개월 lag
#         - Daily (KRW_USD, VIX, Term_Spread, BBB_Spread, HY_Spread,
#                  Breakeven_5Y, Breakeven_Infl): 1개월 lag (이전달 값)
#         - Weekly (Init_Claims, StL_Fin_Stress, Chi_Fin_Cond, Fed_BalSheet): 1개월 lag
#         -> 보수적 안전 규칙: 모두 t-2 사용 (가장 최근 t-1은 정체/미수신 위험)
#   C2: 동일시점 참조 없음 (shift 2개월 이상)
#
# Lane D (v8.4 mandate): 매크로 상태 조건부 비대칭 알파 도출 직결
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

# ---- 필요 패키지 ----
suppressWarnings(suppressMessages({
  library(arrow)
  library(data.table)
}))

PROJECT_ROOT_FE <- Sys.getenv("CLAUDE_PROJECT_DIR",
                    Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

# ---- 1. 매크로 데이터 로드 ----
macro_path <- file.path(PROJECT_ROOT_FE, ".cache", "fred_macro.parquet")
if (!file.exists(macro_path)) {
  stop("[MacroLeadLag] fred_macro.parquet 없음: SKIP_NO_DATA")
}

MACRO_RAW <- as.data.table(read_parquet(macro_path))
cat(sprintf("[MacroLeadLag] MACRO_RAW: %d rows, series=%d\n",
            nrow(MACRO_RAW), uniqueN(MACRO_RAW$Series)))

# ---- 2. 사용할 매크로 계열 선정 (충분한 히스토리 + 종목 beta 연관성 높은 계열) ----
# 선정 기준: 2005-01-01 이전부터 데이터 존재 + 일별/주별/월별 공히 포함
MACRO_SERIES <- c(
  "KRW_USD",        # 환율 (daily) — 수출주, 내수주 비대칭
  "VIX",            # 변동성 지수 (daily) — 방어주 선행
  "Term_Spread",    # 장단기 금리차 (daily) — 금융주, 성장주 선행
  "US_IndProd",     # 미국 산업생산 (monthly, t+50d lag) — 소재/산업 선행
  "US_CPI",         # 미국 CPI (monthly, t+45d lag) — 인플레이션 beta
  "Init_Claims",    # 실업수당 청구건수 (weekly) — 경기 선행
  "StL_Fin_Stress"  # 세인트루이스 금융스트레스 (weekly) — 금융 beta
)

# ---- 3. 매크로 데이터를 월별 패널로 집계 (PIT-safe: 전월 평균 또는 월말값) ----
# C11/C5 준수: 월말 기준 t-2 시프트 (가장 최근 t-1은 정체/지연 위험으로 추가 1개월 버퍼)
MACRO_MONTH <- MACRO_RAW[Series %in% MACRO_SERIES][, {
  # 월별 대표값: daily/weekly는 월 평균, monthly는 월말값
  .(macro_val = mean(Value, na.rm = TRUE),
    n_obs = .N)
}, by = .(ym = format(Date, "%Y-%m"), Series)]

MACRO_MONTH[, Date := as.Date(paste0(ym, "-01"))]

# wide 변환
MACRO_WIDE <- dcast(MACRO_MONTH, Date ~ Series, value.var = "macro_val")
setorder(MACRO_WIDE, Date)

# ---- 4. 전월대비 변화율 (delta_macro) 산출 ----
# 각 계열별 MoM change
macro_cols <- MACRO_SERIES[MACRO_SERIES %in% names(MACRO_WIDE)]
for (col in macro_cols) {
  MACRO_WIDE[, paste0("d_", col) := get(col) / shift(get(col), 1L) - 1]
}

# ---- 5. PIT 시프트 적용: t-2 (2개월 전 값을 홀딩월에 적용) ----
# C5/C11: 홀딩월 = 수익이 실현되는 달. 신호는 그 달이 시작되기 전 데이터만.
# t-2 → 예를 들어 3월 홀딩이면 1월 값 사용 (2월 값은 3월 초에도 미게재 계열 존재)
delta_cols <- paste0("d_", macro_cols)
for (col in delta_cols) {
  MACRO_WIDE[, paste0(col, "_lag2") := shift(get(col), 2L)]
}
lag2_cols <- paste0(delta_cols, "_lag2")

cat(sprintf("[MacroLeadLag] MACRO_WIDE: %d months, macro_cols=%d\n",
            nrow(MACRO_WIDE), length(macro_cols)))

# ---- 6. RAWDATA 월별 수익률 패널 준비 ----
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y-%m")]

# 월별 수익률: 해당 월의 누적 수익률 (합성 — PerformanceAnalytics 경유 대신 간이 월간 집계)
# 여기서는 월 단위 팩터를 추정하기 위한 종속변수로만 사용
# 월말 종가 기준 MoM 수익률 (PIT-safe: 해당 달 내 마감값)
RAWDATA[, .month_ret := (Close / shift(Close, 1L)) - 1, by = Ticker]
# 월말 일에만 keep
RAWDATA[, .is_month_end := (Date == max(Date)), by = .(.ym, Ticker)]
MONTHLY_RET <- RAWDATA[.is_month_end == TRUE, .(
  Date = max(Date),
  ym   = .ym[1],
  Ret  = .month_ret[.N]
), by = .(Ticker, .ym)]
setorder(MONTHLY_RET, Ticker, ym)

# MACRO와 merge: ym 기준 join
MONTHLY_RET[, ym := format(Date, "%Y-%m")]
MACRO_WIDE[,  ym := format(Date, "%Y-%m")]

# ---- 7. 롤링 beta 추정 (12개월 윈도우) ----
# beta_{i,m}: 각 (Ticker, macro_series) 쌍에 대해
# 과거 12개월 window에서 OLS: ret_i ~ delta_macro_m_lag2
# 완전 IS — 홀딩월 t의 beta는 t-1까지의 12개월 데이터로 추정

# merge 준비
PANEL <- merge(MONTHLY_RET[, .(Ticker, ym, Ret)],
               MACRO_WIDE[, c("ym", lag2_cols), with = FALSE],
               by = "ym", all.x = FALSE)
setorder(PANEL, Ticker, ym)

# beta 계산 함수 (벡터화) — data.table 컬럼이 넘어올 때 명시적 as.numeric 변환
.rolling_beta <- function(y, x, w = 12L) {
  y <- as.numeric(y)
  x <- as.numeric(x)
  n <- length(y)
  if (n < w) return(rep(NA_real_, n))
  betas <- rep(NA_real_, n)
  for (i in seq(w, n)) {
    idx <- (i - w + 1L):i
    yi <- y[idx]
    xi <- x[idx]
    valid <- is.finite(yi) & is.finite(xi)
    if (sum(valid) >= 6L && sd(xi[valid], na.rm = TRUE) > 1e-10) {
      fit <- lm.fit(cbind(1, xi[valid]), yi[valid])
      betas[i] <- coef(fit)[2]
    }
  }
  betas
}

# 각 매크로 계열별 rolling beta 추정
cat("[MacroLeadLag] 롤링 beta 추정 시작...\n")
BETAS_LIST <- vector("list", length(lag2_cols))
for (j in seq_along(lag2_cols)) {
  col <- lag2_cols[j]
  beta_col <- paste0("beta_", j)
  PANEL[, (beta_col) := .rolling_beta(Ret, get(col)), by = Ticker]
  BETAS_LIST[[j]] <- beta_col
  cat(sprintf("  beta[%d/%d]: %s\n", j, length(lag2_cols), col))
}
cat("[MacroLeadLag] 롤링 beta 추정 완료\n")

# ---- 8. 신호 합성: signal_i = sum_m [ beta_{i,m} * delta_macro_m_lag2 ] ----
# 각 달의 lag2 매크로 값과 beta를 곱해 합산
PANEL[, .Signal := {
  score <- rep(0, .N)
  n_valid <- rep(0L, .N)
  for (j in seq_along(lag2_cols)) {
    mac_val <- get(lag2_cols[j])
    bet_val <- get(paste0("beta_", j))
    contrib <- bet_val * mac_val
    valid_mask <- is.finite(contrib)
    score[valid_mask] <- score[valid_mask] + contrib[valid_mask]
    n_valid[valid_mask] <- n_valid[valid_mask] + 1L
  }
  # 유효 계열이 2개 이상인 경우만 신호 사용 (희소 데이터 차단)
  ifelse(n_valid >= 2L, score, NA_real_)
}]

cat(sprintf("[MacroLeadLag] Signal 유효 행: %d / %d (NA 제외)\n",
            sum(is.finite(PANEL$.Signal)), nrow(PANEL)))

# ---- 9. 월말 시그널 날짜 추출 ----
# RAWDATA 월말 날짜와 맵핑
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_dt <- RAWDATA[, .(Date = max(Date)), by = .ym]
setnames(.month_ends_dt, ".ym", "ym")

PANEL_DATED <- merge(PANEL[is.finite(.Signal), .(Ticker, ym, Score = .Signal)],
                     .month_ends_dt,
                     by = "ym", all.x = TRUE)
PANEL_DATED <- PANEL_DATED[is.finite(Score) & !is.na(Date)]

# ---- 10. 유동성 필터 적용 ----
# RAWDATA의 LiqPass 기준 (월말 시점)
LIQ_FILTER <- RAWDATA[.is_month_end == TRUE & LiqPass == TRUE, .(Date, Ticker)]
FACTORS <- merge(PANEL_DATED[, .(Date, Ticker, Score)],
                 LIQ_FILTER,
                 by = c("Date", "Ticker"))

RAWDATA[, c(".ym", ".month_ret", ".is_month_end") := NULL]

cat(sprintf("[MacroLeadLag] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
cat(sprintf("[MacroLeadLag] Date range: %s to %s\n",
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))
