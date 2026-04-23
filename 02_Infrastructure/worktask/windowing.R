#==============================================================================
# QEPM Work Task Windowing — v6.1 R2 P2 Data Separation
# 2026-04-24
#
# 4-Window split: train / validation / lockbox / paper-trade
#
# - Alpha / Risk / Optimizer agents → train + validation만 접근
# - Judge → lockbox만 접근
# - Execution Agent → paper_trade만 접근
#
# Lockbox 오염 시 WT 전체 무효 (selection_contamination_detector.sh 강제)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

# ─── Split windows 자동 계산 ─────────────────────────────
# as_of_date 기준 과거로 거슬러 split
split_windows <- function(as_of_date,
                          train_years = 10,
                          val_years = 2,
                          lockbox_years = 2,
                          paper_months = 3) {

  asof <- as.Date(as_of_date)

  paper_end <- asof
  paper_start <- seq(paper_end, length = 2, by = sprintf("-%d months", paper_months))[2]

  lockbox_end <- paper_start - 1
  lockbox_start <- seq(lockbox_end, length = 2, by = sprintf("-%d years", lockbox_years))[2]

  val_end <- lockbox_start - 1
  val_start <- seq(val_end, length = 2, by = sprintf("-%d years", val_years))[2]

  train_end <- val_start - 1
  train_start <- seq(train_end, length = 2, by = sprintf("-%d years", train_years))[2]

  list(
    train_window = list(
      start = format(train_start, "%Y-%m-%d"),
      end = format(train_end, "%Y-%m-%d"),
      role = "factor_selection + signal_engineering (Alpha)"
    ),
    validation_window = list(
      start = format(val_start, "%Y-%m-%d"),
      end = format(val_end, "%Y-%m-%d"),
      role = "model_selection + hyperparam tuning (Risk + Optimizer)"
    ),
    lockbox_window = list(
      start = format(lockbox_start, "%Y-%m-%d"),
      end = format(lockbox_end, "%Y-%m-%d"),
      sealed = TRUE,
      role = "final pass/fail judgment (Judge only)"
    ),
    paper_trade_window = list(
      start = format(paper_start, "%Y-%m-%d"),
      end = format(paper_end, "%Y-%m-%d"),
      role = "pre-deployment validation (Execution)"
    )
  )
}

# ─── Window 내 데이터 필터 ──────────────────────────────
filter_by_window <- function(data, date_col, window) {
  data[as.Date(data[[date_col]]) >= as.Date(window$start) &
       as.Date(data[[date_col]]) <= as.Date(window$end), ]
}

# ─── Lockbox access 로그 ─────────────────────────────────
log_lockbox_access <- function(task_id, agent_name, file_path) {
  log_file <- sprintf("/tmp/qvest_lockbox_access_%s.log", task_id)
  entry <- sprintf("%s | %s | %s\n",
                   format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
                   agent_name,
                   file_path)
  cat(entry, file = log_file, append = TRUE)
  invisible(log_file)
}

# ─── Sealed 상태 확인 ───────────────────────────────────
is_lockbox_sealed <- function(task_id) {
  status_path <- sprintf("qepm/mailbox/worktask/%s/status.json", task_id)
  if (!file.exists(status_path)) return(FALSE)
  st <- fromJSON(status_path, simplifyVector = TRUE)
  # Judge가 판정 완료했으면 sealed
  st$current_phase %in% c("JUDGE_PASSED", "JUDGE_FAILED",
                          "GOVERNOR_PENDING", "GOVERNOR_ADMITTED",
                          "GOVERNOR_REJECTED", "COMPLETED")
}

cat("[windowing.R] Loaded. Functions:\n")
cat("  split_windows(as_of_date, train_years=10, val_years=2, lockbox_years=2, paper_months=3)\n")
cat("  filter_by_window(data, date_col, window)\n")
cat("  log_lockbox_access(task_id, agent_name, file_path)\n")
cat("  is_lockbox_sealed(task_id)\n")
