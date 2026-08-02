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

# ─── 경로 계약 (r-portability.md 금칙 ③) ────────────────────────────────────
# lockbox 접근기록 경로는 bash 훅과 **공유**되므로 리터럴을 여기 두지 않는다.
# 단일 정의 = worktask/lockbox_paths.R (bash 짝 = hooks/lockbox_paths.sh).
.wnd_find_root <- function() {
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  for (cand in cands[nzchar(cands)]) {
    p <- normalizePath(gsub("\\\\", "/", cand), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(p, marker))) return(p)
  }
  here <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(here, marker))) return(here)
    parent <- dirname(here)
    if (identical(parent, here)) break
    here <- parent
  }
  stop("[windowing] project root 미발견 — CLAUDE_PROJECT_DIR 또는 QM_ROOT 설정 필요")
}
if (!exists("qvest_lockbox_log", mode = "function")) {
  source(file.path(.wnd_find_root(), "02_Infrastructure/worktask/lockbox_paths.R"))
}

# ─── Split windows 자동 계산 ─────────────────────────────
# as_of_date 기준 과거로 거슬러 split.
# train_start가 주어지면 train을 그 날짜부터 시작 (train_years 무시). 기본: 1990-01-04 (benchmark 시작).
split_windows <- function(as_of_date,
                          train_start = "1990-01-04",
                          train_years = NULL,
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
  # 경로는 lockbox_paths.R 단일 정의 경유 (구 선행슬래시 tmp 리터럴 → Windows R 은 C:/tmp,
  # bash 훅은 AppData\Local\Temp 로 갈렸다. 2026-08-02 수리)
  log_file <- qvest_lockbox_log(task_id, create_dir = TRUE)
  entry <- sprintf("%s | %s | %s\n",
                   format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
                   agent_name,
                   file_path)
  cat(entry, file = log_file, append = TRUE)
  # 발화 사실 기록 — 감사가 "기록 0건"과 "검출기 사망"을 구별하는 근거 (bash 훅과 동일 계약)
  cat(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "\n",
      file = qvest_lockbox_heartbeat_path(), sep = "")
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

cat("[windowing.R] Loaded (v1.1 — train_start default 1990-01-04). Functions:\n")
cat("  split_windows(as_of_date, train_start='1990-01-04', val_years=2, lockbox_years=2, paper_months=3)\n")
cat("  filter_by_window(data, date_col, window)\n")
cat("  log_lockbox_access(task_id, agent_name, file_path)\n")
cat("  is_lockbox_sealed(task_id)\n")
