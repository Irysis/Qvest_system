#==============================================================================
# STR_CASH_v1 factor_engine.R — Regime-Conditional Cash Signal
#
# role = cash_allocation (v55 신규, 유동성 필터 면제)
# Trail: standard
# 출력: monthly Date × cash_weight (t-1 lag 적용, C5 준수)
#==============================================================================

# v55 allocation role — 종목 선택 전략 아님, LIQ_THRESHOLD 무관
STR_CASH_V1_ROLE <- "cash_allocation"
STR_CASH_V1_TRAIL <- "standard"

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

#' Generate monthly cash weight from regime signal
#'
#' @param regime_data data.table with Date (Date) + MRS (0-100 score)
#' @param thresholds list with good/normal/bad MRS thresholds
#' @param cash_weights list with good/normal/bad/crisis cash % (0-1)
#' @return data.table with Date + cash_weight (t-1 lag 적용)
generate_cash_signal <- function(regime_data,
                                  thresholds = list(good=30, normal=50, bad=70),
                                  cash_weights = list(good=0.0, normal=0.05,
                                                      bad=0.15, crisis=0.30)) {

  dt <- as.data.table(regime_data)

  # MRS 필드 자동 감지
  mrs_col <- intersect(c("MRS", "mrs", "regime_score", "state_score"), names(dt))[1]
  if (is.na(mrs_col)) {
    stop("regime_data MRS 컬럼 필요")
  }

  if (!inherits(dt$Date, "Date")) dt[, Date := as.Date(Date)]

  dt[, cash_weight := fcase(
    get(mrs_col) < thresholds$good,   cash_weights$good,
    get(mrs_col) < thresholds$normal, cash_weights$normal,
    get(mrs_col) < thresholds$bad,    cash_weights$bad,
    default =                          cash_weights$crisis
  )]

  # C5 준수: t-1 lag
  setorder(dt, Date)
  dt[, cash_weight_lag := shift(cash_weight, 1, fill = cash_weights$normal)]

  dt[, regime_state := fcase(
    get(mrs_col) < thresholds$good,   "Good",
    get(mrs_col) < thresholds$normal, "Normal",
    get(mrs_col) < thresholds$bad,    "Bad",
    default =                          "Crisis"
  )]

  dt[, .(Date, mrs = get(mrs_col), regime_state, cash_weight = cash_weight_lag)]
}

#' Load regime_v7.parquet and generate cash signal
load_and_generate_cash_signal <- function(regime_path = ".cache/regime_v7.parquet") {
  if (!file.exists(regime_path)) {
    stop(sprintf("regime 신호 파일 없음: %s", regime_path))
  }

  regime_raw <- arrow::read_parquet(regime_path)
  regime_dt <- as.data.table(regime_raw)

  candidate_cols <- c("MRS", "mrs", "regime_score", "mrs_score", "state_score")
  mrs_col <- intersect(candidate_cols, names(regime_dt))[1]

  if (is.na(mrs_col)) {
    state_cols <- intersect(c("state_4", "regime_state", "state", "regime"),
                            names(regime_dt))
    if (length(state_cols) > 0) {
      regime_dt[, MRS := fcase(
        get(state_cols[1]) %in% c("Good","G","1"),    15,
        get(state_cols[1]) %in% c("Normal","N","2"),  40,
        get(state_cols[1]) %in% c("Bad","B","3"),     60,
        get(state_cols[1]) %in% c("Crisis","C","4"),  85,
        default =                                      50
      )]
      mrs_col <- "MRS"
    } else {
      stop("regime MRS 또는 state 컬럼 없음")
    }
  }

  if (!"Date" %in% names(regime_dt)) {
    date_candidates <- c("date", "month_end", "apply_start", "yearmon")
    date_col <- intersect(date_candidates, names(regime_dt))[1]
    if (is.na(date_col)) stop("regime Date 컬럼 없음 (Date/month_end/apply_start)")
    setnames(regime_dt, date_col, "Date")
  }

  generate_cash_signal(regime_dt[, .(Date, MRS = get(mrs_col))])
}

cat("[factor_engine] STR_CASH_v1 (role=cash_allocation) loaded.\n")
