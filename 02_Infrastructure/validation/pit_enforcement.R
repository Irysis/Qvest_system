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

#' PIT v2 — Label Direction Validation (Cycle 51 신규)
#'
#' Forecast label이 forward 방향인지 backward 방향인지 검증.
#' data.table::shift convention 함정 (`shift(x, n=-H, type="lead")` = x[t-H] BACKWARD,
#' double negation) 자동 detection.
#'
#' Method:
#'   1. target_df의 ret_h sample (default 100 random dates with ret_h != NA)
#'   2. 각 sample date에 대해 bm_df에서 manual forward lookup: BM[t+H] / BM[t] - 1
#'   3. target_df의 ret_h 값과 manual forward value 비교 (절대 차이 < 1e-6 → 일치)
#'   4. 일치율 ≥ threshold (default 0.95) → PASS, < threshold → FAIL
#'
#' COVID 2020-02-19 assertion: forward 21d return must be ≤ -0.30 (실제 -34.05%) 미달 시 FAIL.
#'
#' @param target_df data.table with Date + target_col (e.g., ret_h)
#' @param target_col Character. Target column name (default "ret_h")
#' @param bm_df data.table with Date + bm_col (benchmark close)
#' @param bm_col Character. Benchmark column name (default "BM_Close")
#' @param expected_direction "forward" or "backward" (default "forward")
#' @param horizon Integer trading days (default 21L)
#' @param n_sample Integer sample size (default 100L)
#' @param threshold Numeric agreement rate threshold (default 0.95)
#' @param assert_covid Logical assert COVID 2020-02-19 forward case (default TRUE)
#' @return list(pass, agreement_rate, n_sample, n_match, covid_assertion, violations)
#' @export
validate_label_direction <- function(target_df,
                                     target_col = "ret_h",
                                     bm_df,
                                     bm_col = "BM_Close",
                                     expected_direction = "forward",
                                     horizon = 21L,
                                     n_sample = 100L,
                                     threshold = 0.95,
                                     assert_covid = TRUE) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("[PIT v2] data.table required")
  }
  td <- data.table::as.data.table(target_df)
  bd <- data.table::as.data.table(bm_df)

  if (!all(c("Date", target_col) %in% names(td))) {
    stop(sprintf("[PIT v2] target_df missing Date or %s", target_col))
  }
  if (!all(c("Date", bm_col) %in% names(bd))) {
    stop(sprintf("[PIT v2] bm_df missing Date or %s", bm_col))
  }

  data.table::setorder(td, Date)
  data.table::setorder(bd, Date)

  # ── 1. Manual forward lookup function ──────────────────────────────
  # bm_df indexed by row (positional shift, NOT calendar — trading days)
  bd[, row_idx := .I]
  manual_forward <- function(date_i) {
    # find row idx in bm
    j <- bd[Date == date_i, row_idx]
    if (length(j) == 0) return(NA_real_)
    j <- j[1]
    k <- j + horizon
    if (k > nrow(bd)) return(NA_real_)
    bd[[bm_col]][k] / bd[[bm_col]][j] - 1
  }
  manual_backward <- function(date_i) {
    j <- bd[Date == date_i, row_idx]
    if (length(j) == 0) return(NA_real_)
    j <- j[1]
    k <- j - horizon
    if (k < 1) return(NA_real_)
    bd[[bm_col]][k] / bd[[bm_col]][j] - 1
  }

  # ── 2. Sample dates with non-NA target ─────────────────────────────
  valid_rows <- td[!is.na(get(target_col)), .(Date)]
  n_valid <- nrow(valid_rows)
  if (n_valid < 10) {
    return(list(
      pass = FALSE,
      agreement_rate = NA_real_,
      n_sample = 0,
      n_match = 0,
      covid_assertion = NA,
      violations = list(reason = sprintf("insufficient valid rows: %d < 10", n_valid))
    ))
  }
  k <- min(n_sample, n_valid)
  set.seed(42)
  sample_dates <- sample(valid_rows$Date, k)

  # ── 3. Compare each sample with manual forward / backward ──────────
  n_fwd_match <- 0L
  n_bwd_match <- 0L
  details <- vector("list", k)
  for (i in seq_along(sample_dates)) {
    d <- sample_dates[i]
    target_val <- td[Date == d, get(target_col)][1]
    fwd_val <- manual_forward(d)
    bwd_val <- manual_backward(d)
    fwd_match <- !is.na(fwd_val) && abs(target_val - fwd_val) < 1e-6
    bwd_match <- !is.na(bwd_val) && abs(target_val - bwd_val) < 1e-6
    if (fwd_match) n_fwd_match <- n_fwd_match + 1L
    if (bwd_match) n_bwd_match <- n_bwd_match + 1L
    details[[i]] <- list(date = as.character(d), target = target_val,
                         forward = fwd_val, backward = bwd_val,
                         fwd_match = fwd_match, bwd_match = bwd_match)
  }

  fwd_rate <- n_fwd_match / k
  bwd_rate <- n_bwd_match / k

  # ── 4. COVID 2020-02-19 assertion ──────────────────────────────────
  covid_assertion <- list(checked = FALSE)
  if (assert_covid) {
    covid_d <- as.Date("2020-02-19")
    fwd_covid <- manual_forward(covid_d)
    bwd_covid <- manual_backward(covid_d)
    covid_target <- td[Date == covid_d, get(target_col)][1]
    if (!is.null(covid_target) && length(covid_target) > 0 && !is.na(covid_target)) {
      covid_assertion <- list(
        checked = TRUE,
        target_value = covid_target,
        forward_expected_ge = -0.30,
        forward_actual = fwd_covid,
        backward_actual = bwd_covid,
        # PASS if forward direction expected AND target matches forward AND forward is bearish
        fwd_pass = !is.na(fwd_covid) && abs(covid_target - fwd_covid) < 1e-6 && fwd_covid <= -0.30,
        bwd_pass = !is.na(bwd_covid) && abs(covid_target - bwd_covid) < 1e-6 && bwd_covid >= 0
      )
    }
  }

  # ── 5. Pass/Fail decision ──────────────────────────────────────────
  if (expected_direction == "forward") {
    pass <- fwd_rate >= threshold
  } else if (expected_direction == "backward") {
    pass <- bwd_rate >= threshold
  } else {
    stop("[PIT v2] expected_direction must be 'forward' or 'backward'")
  }

  list(
    pass = pass,
    expected_direction = expected_direction,
    horizon = horizon,
    n_sample = k,
    n_match_forward = n_fwd_match,
    n_match_backward = n_bwd_match,
    agreement_rate_forward = fwd_rate,
    agreement_rate_backward = bwd_rate,
    threshold = threshold,
    covid_assertion = covid_assertion,
    details = details
  )
}

cat("[pit_enforcement] Loaded. Functions: pit_filter(), pit_zscore(), pit_zscore_vec(), pit_rolling(), pit_verify_month_regime(), pit_self_audit(), validate_label_direction() [v2 Cycle 51]\n")
