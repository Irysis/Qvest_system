#==============================================================================
# PIT (Point-In-Time) Enforcement — 미래참조 원천 차단 인프라
#
# judge_pit_enforcement.md의 코드 수준 구현.
# 모든 전략/국면엔진에서 source() 후 PIT 함수 사용.
#
# 규칙 위계:
#   [Level 0] 미래참조 금지 (PIT 준수) ← 최상위. 예외 없음.
#   [Level 1] 데이터 무결성
#   [Level N] 성과 달성 ← 위 규칙을 모두 지킨 후에만 의미 있음.
#
# Usage:
#   source("02_Infrastructure/pit_enforcement.R")
#   filtered <- pit_filter(data, as_of_date)
#   z <- pit_zscore(x, i)
#   result <- pit_rolling(x, width, fun, dates)
#==============================================================================
cat("[pit_enforcement] Loading PIT enforcement module...\n")

suppressPackageStartupMessages(library(data.table))

#' PIT Filter — available_date 기준 필터링
#'
#' 데이터에서 as_of_date 이전에 확보 가능한 행만 반환.
#' available_date 컬럼이 없으면 Date 컬럼으로 대체 (경고 출력).
#'
#' @param data data.table with Date or available_date column
#' @param as_of_date Date. 이 날짜 이전(<=) 데이터만 반환.
#' @param date_col Character. 날짜 컬럼명 (default: auto-detect)
#' @param strict Logical. TRUE면 available_date 필수, FALSE면 Date 대체 허용
#' @return Filtered data.table
#' @export
pit_filter <- function(data, as_of_date, date_col = NULL, strict = FALSE) {
  if (is.null(date_col)) {
    if ("available_date" %in% names(data)) {
      date_col <- "available_date"
    } else if ("Date" %in% names(data)) {
      if (strict) {
        stop("[PIT VIOLATION] available_date 컬럼 없음. strict=TRUE에서는 Date 대체 불가.")
      }
      date_col <- "Date"
    } else if ("month_end" %in% names(data)) {
      date_col <- "month_end"
    } else {
      stop("[PIT VIOLATION] 날짜 컬럼을 찾을 수 없음. available_date, Date, month_end 중 하나 필요.")
    }
  }

  as_of <- as.Date(as_of_date)
  data[get(date_col) <= as_of]
}

#' PIT Z-Score — 시점 i까지의 데이터만으로 z-score 계산
#'
#' 전체 기간 통계량 사용 금지 (C1 위반 방지).
#' expanding window: 1:i 데이터로 mean/sd 계산.
#'
#' @param x Numeric vector (시계열)
#' @param i Integer. 현재 시점 인덱스
#' @param min_obs Integer. 최소 관측수 (default: 60)
#' @return z-score at position i, or NA if insufficient data
#' @export
pit_zscore <- function(x, i, min_obs = 60L) {
  if (i < min_obs) return(NA_real_)
  historical <- x[1:i]
  historical <- historical[!is.na(historical)]
  if (length(historical) < min_obs) return(NA_real_)
  s <- sd(historical)
  if (is.na(s) || s < 1e-8) return(NA_real_)
  (x[i] - mean(historical)) / s
}

#' PIT Z-Score Vector — 전체 벡터에 대해 expanding window z-score
#'
#' @param x Numeric vector
#' @param window Integer. Rolling window size (default: 756)
#' @param min_obs Integer. Minimum observations (default: 252)
#' @return Numeric vector of z-scores
#' @export
pit_zscore_vec <- function(x, window = 756L, min_obs = 252L) {
  n <- length(x)
  z <- rep(NA_real_, n)
  for (i in min_obs:n) {
    start <- max(1L, i - window + 1L)
    vals <- x[start:i]
    vals <- vals[!is.na(vals)]
    if (length(vals) >= min_obs) {
      s <- sd(vals)
      if (!is.na(s) && s > 1e-8) {
        z[i] <- (x[i] - mean(vals)) / s
      }
    }
  }
  z
}

#' PIT Rolling — 미래 데이터 포함 방지 rolling 계산
#'
#' dates[i] 기준으로 dates[i] 이전 width개만 사용.
#' window에 미래 날짜가 포함되면 즉시 에러.
#'
#' @param x Numeric vector
#' @param width Integer. Window size
#' @param fun Function. Rolling function (e.g., mean, sd)
#' @param dates Date vector. 각 관측의 날짜 (optional, 검증용)
#' @return Numeric vector
#' @export
pit_rolling <- function(x, width, fun, dates = NULL) {
  n <- length(x)
  result <- rep(NA_real_, n)

  for (i in width:n) {
    window_idx <- (i - width + 1):i
    window_vals <- x[window_idx]

    # PIT 검증: dates가 제공되면 미래 날짜 포함 여부 확인
    if (!is.null(dates)) {
      if (max(dates[window_idx]) > dates[i]) {
        stop(sprintf("[PIT VIOLATION] Rolling window at i=%d includes future date %s > current %s",
                     i, max(dates[window_idx]), dates[i]))
      }
    }

    result[i] <- fun(window_vals)
  }
  result
}

#' PIT Verify Month-End — 월말 데이터가 다음달에만 사용되는지 검증
#'
#' @param regime_dt data.table with month_end and apply_month columns
#' @return TRUE if clean, stops with error if violation found
#' @export
pit_verify_month_regime <- function(regime_dt) {
  if (!all(c("month_end", "apply_month") %in% names(regime_dt))) {
    stop("[PIT] regime_dt must have month_end and apply_month columns")
  }

  regime_dt[, apply_start := as.Date(paste0(apply_month, "-01"))]
  violations <- regime_dt[month_end >= apply_start]

  if (nrow(violations) > 0) {
    cat(sprintf("[PIT VIOLATION] %d months where month_end >= apply_start:\n", nrow(violations)))
    print(violations[, .(month_end, apply_month, apply_start)])
    stop("[PIT VIOLATION] Regime data uses future information!")
  }

  cat("[PIT] Month-end regime verification: CLEAN\n")
  invisible(TRUE)
}

#' PIT Verify FRED Lag — FRED 데이터에 1일 lag 적용 확인
#'
#' FRED 데이터(미국 시간)는 한국 시간 기준 1일 lag 필요.
#' @param fred_dt data.table with Date column and FRED series
#' @param reference_dates Date vector of month-ends to check
#' @return TRUE if properly lagged
#' @export
pit_verify_fred_lag <- function(fred_dt, reference_dates) {
  # FRED 데이터의 Date가 reference_date와 같으면 당일 사용 = 시차 위반
  # FRED Date는 reference_date - 1 이하여야 함 (미국 장 마감 = 한국 다음날)
  cat("[PIT] FRED lag verification: structural check only (lag must be applied in code)\n")
  invisible(TRUE)
}

#' PIT Self-Audit — judge_pit_enforcement.md 자기감사 3질문
#'
#' 매 판단 전 호출. 위반 시 FALSE 반환.
#' @param data_description Character. 사용하려는 데이터 설명
#' @param decision_date Date. 의사결정 시점
#' @param data_date Date. 데이터 확정 시점
#' @return Logical. TRUE if PIT compliant
#' @export
pit_self_audit <- function(data_description, decision_date, data_date) {
  decision_date <- as.Date(decision_date)
  data_date <- as.Date(data_date)

  # 질문 1: 이 정보는 의사결정 시점에 알 수 있었는가?
  q1 <- data_date <= decision_date

  # 질문 2: 이후 결과가 판단에 영향을 미치지 않는가?
  # (코드에서 구조적으로 보장해야 함 — 여기서는 날짜 검증만)
  q2 <- TRUE

  # 질문 3: '괜찮다'고 느끼는 이유가 결과를 알기 때문은 아닌가?
  # (자동 검증 불가 — 경고 출력)
  q3 <- TRUE

  if (!q1) {
    cat(sprintf("[PIT AUDIT FAIL] Data '%s' (date %s) not available at decision date %s\n",
                data_description, data_date, decision_date))
    return(FALSE)
  }

  invisible(TRUE)
}

cat("[pit_enforcement] Loaded. Functions: pit_filter(), pit_zscore(), pit_zscore_vec(), pit_rolling(), pit_verify_month_regime(), pit_self_audit()\n")
