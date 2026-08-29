#==============================================================================
# QEPM Work Task Windowing — v10 (2026-08-29 도훈 지시: lockbox 제도 폐지)
#
# 3-Window split: train / validation / paper-trade
#
# ★v10 변경: lockbox 창 산출·접근기록·봉인 검사 전부 폐지 — 모든 에이전트는
#   가용 데이터 **전기간**을 쓴다(도훈 "lock box 개념은 삭제. 반박 금지").
#   - IS/OOS anchored 분할(essence_score oos_retention)은 lockbox 가 아니라
#     측정 규율이다 — 그쪽은 essence_score.R 이 자체 수행하며 여기와 무관.
#   - log_lockbox_access / is_lockbox_sealed 는 잔존 호출자가 죽지 않도록
#     no-op stub 으로만 존치(신규 코드에서 호출 금지).
#   - 구판(4-window + lockbox_paths.R 연동)은 git 사료: pre-v10-2layer.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

# ─── Split windows 자동 계산 ─────────────────────────────
# as_of_date 기준 과거로 거슬러 split.
# train_start가 주어지면 train을 그 날짜부터 시작 (train_years 무시). 기본: 1990-01-04 (benchmark 시작).
# lockbox_years 인자는 하위호환으로만 받고 **무시**한다(v10 — 창을 만들지 않는다).
split_windows <- function(as_of_date,
                          train_start = "1990-01-04",
                          train_years = NULL,
                          val_years = 2,
                          lockbox_years = 0,
                          paper_months = 3) {

  asof <- as.Date(as_of_date)

  paper_end <- asof
  paper_start <- seq(paper_end, length = 2, by = sprintf("-%d months", paper_months))[2]

  val_end <- paper_start - 1
  val_start <- seq(val_end, length = 2, by = sprintf("-%d years", val_years))[2]

  train_end <- val_start - 1

  # train_start 우선 (explicit date). 없으면 train_years로 역산 (backward compat).
  if (!is.null(train_start)) {
    train_start <- as.Date(train_start)
  } else if (!is.null(train_years)) {
    train_start <- seq(train_end, length = 2, by = sprintf("-%d years", train_years))[2]
  } else {
    train_start <- as.Date("1990-01-04")
  }

  train_years_actual <- as.numeric(train_end - train_start) / 365.25

  list(
    train_window = list(
      start = format(train_start, "%Y-%m-%d"),
      end = format(train_end, "%Y-%m-%d"),
      years = round(train_years_actual, 2),
      role = "factor_selection + signal_engineering (Alpha) — v10: 전기간 접근 허용"
    ),
    validation_window = list(
      start = format(val_start, "%Y-%m-%d"),
      end = format(val_end, "%Y-%m-%d"),
      role = "model_selection + hyperparam tuning (Risk + Optimizer)"
    ),
    paper_trade_window = list(
      start = format(paper_start, "%Y-%m-%d"),
      end = format(paper_end, "%Y-%m-%d"),
      role = "post-registration tracking (BOOK)"
    )
  )
}

# ─── Window 내 데이터 필터 ──────────────────────────────
filter_by_window <- function(data, date_col, window) {
  data[as.Date(data[[date_col]]) >= as.Date(window$start) &
       as.Date(data[[date_col]]) <= as.Date(window$end), ]
}

# ─── v10 no-op stubs (구 lockbox 계약 잔존 호출자 보호 — 신규 호출 금지) ────
log_lockbox_access <- function(task_id, agent_name, file_path) {
  # RETIRED (v10 2026-08-29): lockbox 폐지 — 기록하지 않는다.
  invisible(NULL)
}

is_lockbox_sealed <- function(task_id) {
  # RETIRED (v10 2026-08-29): lockbox 폐지 — 항상 FALSE.
  FALSE
}

cat("[windowing.R] Loaded (v10 — lockbox 폐지, 3-window). Functions:\n")
cat("  split_windows(as_of_date, train_start='1990-01-04', val_years=2, paper_months=3)\n")
cat("  filter_by_window(data, date_col, window)\n")
cat("  (stub) log_lockbox_access / is_lockbox_sealed — RETIRED no-op\n")
