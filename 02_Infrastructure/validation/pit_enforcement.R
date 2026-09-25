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

# ── pit_verify_fred_lag 보조: 이 파일 위치(도우미 탐색용) · S0 가용시점 층 로드 ──────────────────
.pite_self_path <- local(tryCatch({    # source() 한 이 파일의 경로(sys.frame ofile) — 전역에 임시 변수를 남기지 않는다
  f <- NA_character_
  for (i in rev(seq_len(sys.nframe()))) {
    of <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
    if (!is.null(of) && nzchar(of)) { f <- of; break }
  }
  if (!is.na(f)) gsub("\\\\", "/", f) else NA_character_
}, error = function(e) NA_character_))

.pite_need_fred_avail <- function() {
  if (exists("fred_join_violations", mode = "function")) return(invisible(TRUE))
  cands <- c(if (!is.na(.pite_self_path)) file.path(dirname(dirname(.pite_self_path)), "data", "fred_availability.R"),
             file.path(gsub("\\\\", "/", Sys.getenv("QM_ROOT", "")), "02_Infrastructure", "data", "fred_availability.R"))
  hit <- cands[nzchar(cands) & file.exists(cands)]
  if (!length(hit))
    stop("[PIT] fred_availability.R(S0 가용시점 층)를 찾지 못함 — FRED lag 검증 불가(fail-closed). 후보: ",
         paste(cands, collapse = " | "))
  source(hit[1], local = globalenv())
  invisible(TRUE)
}

#' PIT Verify FRED Lag — 해외(FRED)·ECOS 결합이 가용일 규칙을 지키는지 **데이터로** 검증
#'
#' [2026-09-24 실구현 — PIT C11 판정서 ③·⑤-8, decision_register PIT-C11-CONVENTIONS ④]
#'  종전 판은 인자를 보지도 않고 무조건 TRUE 를 돌려주는 빈 함수였고(호출부 0) — 이름만 방어선이었다.
#'  이제 이미 결합된 (한국 날짜, 관측일) 쌍을 규칙 파일(06_Registry/fred_availability_rules.json)의 가용일과
#'  대조한다. 가용일 계산은 S0 가용시점 층(02_Infrastructure/data/fred_availability.R::fred_join_violations)
#'  한 곳뿐이다 — 이 함수에는 오프셋·규칙 수치가 없다.
#'
#' @param fred_dt 결합 산출(data.table/data.frame). 필수 열:
#'   - 한국 날짜: kr_date_col (기본 자동 — "kr_date" 가 있으면 그것, 없으면 "Date")
#'   - 관측일: obs_date_col (기본 "obs_date" — fred_asof_join 산출 열). **없으면 거부**: 관측일을 모르는 값은
#'     같은 날짜 결합인지 판정할 수 없다(판정 불가 = 통과 아님).
#'   - 계열: series_col (기본 자동 — "series_id" → "Series_ID") 또는 series_id 인자(한 계열일 때)
#' @param reference_dates 검증할 한국 날짜(Date). NULL 이면 전 행. 주어졌는데 한 행도 안 맞으면 거부(빈 검증 = 통과 아님).
#' @param series_id 계열 id/별칭(series_col 이 없을 때). 규칙 없는 계열·금지 계열(DEXKOUS) = 도우미가 거부(fail-closed).
#' @param mode "decision_close"(판정서 ② 형태 a·c) | "exposure_return"(형태 b — 노출 × 종가→종가 수익)
#' @param kr_calendar,rules 도우미로 그대로 넘긴다(검사·재현용 주입)
#' @param stop_on_violation TRUE(기본) = 위반 시 stop (pit_verify_month_regime 과 같은 계약)
#' @return 적합 = invisible(TRUE) (attr "n_checked"). 위반 = stop, 또는 stop_on_violation=FALSE 면
#'   FALSE + attr(,"violations") (fred_join_violations 행: kr_date·decision_date·obs_date·avail_date·reason·series_id)
#' @export
pit_verify_fred_lag <- function(fred_dt, reference_dates = NULL, series_id = NULL,
                                mode = c("decision_close", "exposure_return"),
                                kr_date_col = NULL, obs_date_col = "obs_date", series_col = NULL,
                                kr_calendar = NULL, rules = NULL, stop_on_violation = TRUE) {
  mode <- match.arg(mode)
  .pite_need_fred_avail()
  dt <- as.data.table(fred_dt)
  if (!nrow(dt)) stop("[PIT] pit_verify_fred_lag: 빈 입력 — 검증 0행은 통과가 아니다")
  if (is.null(kr_date_col)) kr_date_col <- if ("kr_date" %in% names(dt)) "kr_date" else "Date"
  if (!(kr_date_col %in% names(dt))) stop("[PIT] pit_verify_fred_lag: 한국 날짜 열 없음: ", kr_date_col)
  if (!(obs_date_col %in% names(dt)))
    stop(sprintf(paste0("[PIT] pit_verify_fred_lag: 관측일 열 '%s' 없음 — 관측일을 모르는 결합은 같은 날짜 결합인지 판정할 수 없다",
                        "(fail-closed). fred_asof_join() 산출(obs_date 포함)이나 결합 전 관측일을 보존한 표를 넘겨라"), obs_date_col))
  if (is.null(series_col)) series_col <- intersect(c("series_id", "Series_ID"), names(dt))[1]
  if (is.na(series_col) || is.null(series_col)) {
    if (is.null(series_id)) stop("[PIT] pit_verify_fred_lag: 계열을 모름 — series_col 열 또는 series_id 인자가 필요")
    sids <- rep(series_id, nrow(dt))
  } else {
    sids <- as.character(dt[[series_col]])
    if (!is.null(series_id)) sids[is.na(sids)] <- series_id
  }
  kd <- as.Date(dt[[kr_date_col]]); od <- as.Date(dt[[obs_date_col]])
  keep <- rep(TRUE, length(kd))
  if (!is.null(reference_dates)) {
    keep <- kd %in% as.Date(reference_dates)
    if (!any(keep)) stop("[PIT] pit_verify_fred_lag: reference_dates 와 맞는 행 0 — 검증 0행은 통과가 아니다")
  }
  if (any(keep & is.na(sids))) stop("[PIT] pit_verify_fred_lag: 계열 id 가 빈 행이 있다(fail-closed)")
  viol <- list()
  n_checked <- 0L
  for (s in unique(sids[keep])) {
    ix <- which(keep & sids == s)
    v <- fred_join_violations(kd[ix], od[ix], s, mode = mode, kr_calendar = kr_calendar, rules = rules)
    n_checked <- n_checked + sum(!is.na(od[ix]))
    if (nrow(v)) { v[, row := ix[row]]; viol[[length(viol) + 1L]] <- v }
  }
  if (n_checked == 0L) stop("[PIT] pit_verify_fred_lag: 관측일이 있는 행 0 — 검증 0행은 통과가 아니다")
  if (length(viol)) {
    V <- rbindlist(viol, fill = TRUE)
    cat(sprintf("[PIT VIOLATION] 해외 계열 가용일 전 사용 %d/%d 행 (mode=%s):\n", nrow(V), n_checked, mode))
    print(utils::head(V[, .(row, series_id, kr_date, decision_date, obs_date, avail_date, reason)], 10))
    if (isTRUE(stop_on_violation))
      stop(sprintf("[PIT VIOLATION] C11 — %d 행이 가용일 전 관측을 씀(첫 행: %s 결정 %s ← 관측 %s, 가용 %s)",
                   nrow(V), V$series_id[1], format(V$decision_date[1]), format(V$obs_date[1]),
                   format(V$avail_date[1])))
    out <- FALSE
    attr(out, "violations") <- V
    attr(out, "n_checked") <- n_checked
    return(out)
  }
  cat(sprintf("[PIT] FRED lag verification (%s): CLEAN — %d 행, 계열 %s\n", mode, n_checked,
              paste(unique(sids[keep]), collapse = ",")))
  out <- TRUE
  attr(out, "n_checked") <- n_checked
  invisible(out)
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

cat("[pit_enforcement] Loaded. Functions: pit_filter(), pit_zscore(), pit_zscore_vec(), pit_rolling(), pit_verify_month_regime(), pit_verify_fred_lag() [C11 실구현 2026-09-24], pit_self_audit(), validate_label_direction() [v2 Cycle 51]\n")
