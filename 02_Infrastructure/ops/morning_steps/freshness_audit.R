# freshness_audit.R — morning_briefing [5/5] freshness audit (외부화, 2026-06-13)
# 인라인 Rscript -e 에 한글/이모지(⚠️🚨✅→) 리터럴이 들어가면 bash→Windows-R 코드페이지
# 변환이 멀티바이트를 깨뜨려 "Execution halted"/SIGSEGV 발생. 외부 .R 파일은 UTF-8로 정상
# read 되므로 본 블록을 파일로 분리. 호출: Rscript -e 'source(".../freshness_audit.R")'
# 전제: morning_briefing.sh 가 cd "$BASE" 후 호출 (CWD = project root).

root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root) || !dir.exists(root)) root <- getwd()
setwd(root)
source("02_Infrastructure/config.R")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})

today <- Sys.Date()
# as_of = 직전 거래일 (benchmark KOSPI200 max). calendar today 대신 이걸 기준으로 lag 계산
# → 월요일/연휴 오탐 제거 (도훈 2026-06-01).
as_of <- tryCatch(max(as.Date(as.data.table(read_parquet(".cache/benchmark.parquet"))$Date), na.rm = TRUE),
                  error = function(e) today)
if (length(as_of) != 1 || is.na(as_of) || as_of > today) as_of <- today

audits <- list()
check_freshness <- function(name, path, col, max_lag_days) {
  if (!file.exists(path)) return(list(name = name, status = "MISSING", path = path))
  dt <- tryCatch(as.data.table(read_parquet(path)), error = function(e) NULL)
  if (is.null(dt)) {
    csv_try <- tryCatch(fread(path), error = function(e) NULL)
    if (!is.null(csv_try)) dt <- csv_try
  }
  if (is.null(dt) || !col %in% names(dt)) return(list(name = name, status = "PARSE_FAIL", path = path))
  last_d <- max(as.Date(dt[[col]]), na.rm = TRUE)
  lag_d <- as.integer(as_of - last_d)
  status <- if (lag_d <= max_lag_days) "FRESH" else "STALE"
  list(name = name, status = status, last_date = as.character(last_d), lag_days = lag_d, max_lag = max_lag_days)
}
audits$msm_daily       <- check_freshness("msm_daily",       ".cache/msm_daily_latest.parquet",        "Date", 3)
audits$msm_hybrid      <- check_freshness("msm_hybrid",      ".cache/msm_hybrid_latest.parquet",       "Date", 3)
audits$fred            <- check_freshness("fred",            ".cache/fred_macro.parquet",              "Date", 4)
audits$ktri_indices    <- check_freshness("ktri_indices",    ".cache/ktri_indices.parquet",            "Date", 3)
audits$ktri_v3_signals <- check_freshness("ktri_v3_signals", "04_Research/regime_comparison/output/ktri_v3_signals.csv", "DATE", 3)
audits$regime_daily    <- check_freshness("regime_daily",    ".cache/unified_regime_signal_daily.parquet", "Date", 3)
audits$benchmark       <- check_freshness("benchmark",       ".cache/benchmark.parquet",               "Date", 2)  # KOSPI200 종가
audits$p3_forecast     <- check_freshness("p3_forecast",     "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet", "Date", 3)

cat("=== Freshness Audit ===\n")
stale_items <- c()
for (a in audits) {
  cat(sprintf("  %-18s [%s] last=%s lag=%dd (max %dd)\n",
              a$name, a$status, a$last_date %||% "n/a", a$lag_days %||% -1L, a$max_lag %||% -1L))
  if (isTRUE(a$status == "STALE") || isTRUE(a$status == "MISSING")) {
    stale_items <- c(stale_items, sprintf("%s(%s,lag=%dd)", a$name, a$status, a$lag_days %||% -1L))
  }
}
audit_path <- "qepm/observability/morning_freshness_latest.json"
dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
write_json(list(ran_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                as_of = as.character(as_of),
                audits = audits,
                stale_count = length(stale_items),
                stale_items = if (length(stale_items) > 0) I(as.character(stale_items)) else list()),
           audit_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("Audit saved: %s\n", audit_path))

# Stale 시 Telegram alert (mrs_daily 의 07:30 brief 전에)
if (length(stale_items) > 0) {
  cat(sprintf("\n⚠️ STALE detected (%d items): %s\n", length(stale_items),
              paste(stale_items, collapse = ", ")))
  source("02_Infrastructure/telegram/telegram_notify.R")
  msg <- sprintf("\U0001F6A8 Morning Freshness Audit — %d stale\n\n%s\n\nbrief 07:30 송신 전 점검 필요",
                 length(stale_items),
                 paste(sprintf("- %s", stale_items), collapse = "\n"))
  tryCatch(tg_send(msg), error = function(e) cat(sprintf("Telegram alert failed: %s\n", e$message)))
} else {
  cat("\n✅ All sources FRESH — brief 07:30 발송 OK\n")
}
