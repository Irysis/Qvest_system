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
# [2026-07-14 Q] as_of 순환성 수리 — 구현(benchmark-max 유도)은 '부분 stale'만 잡고,
#   '전면 stale'(아침 갱신 전체 미도래)이면 as_of가 데이터와 같이 끌려 내려가 전부 FRESH 오판
#   (07-14 실사고: 07:11 감사가 as_of=07-10으로 KTRI 전전영업일 발송을 통과시킴).
#   기준일은 데이터가 아닌 달력에서: 주말 제외 직전 평일 후보 → trading_calendar(QW ground
#   truth)가 후보를 커버하면 휴일 보정, 미커버면 후보 유지(보수 — 드문 평일휴일 아침 오탐은
#   mrs '보류 알림'으로 표면화, 침묵-stale보다 낫다). 도훈 06-01 월요일 오탐 제거 목적은
#   주말 스킵 + 달력 휴일 보정으로 유지된다.
.prev_bd <- function(d) { t <- d - 1; while (format(t, "%u") %in% c("6", "7")) t <- t - 1; t }
as_of <- .prev_bd(today)
.cal <- tryCatch(as.Date(as.data.table(read_parquet(".cache/trading_calendar.parquet"))$Date),
                 error = function(e) as.Date(character(0)))
if (length(.cal) && max(.cal, na.rm = TRUE) >= as_of && !(as_of %in% .cal)) {
  as_of <- max(.cal[.cal < as_of])
}
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

# 기계 판독용 단일 라인 (2026-08-03) — ensure_data_current.sh 가 이 줄만 grep 한다.
#   ★JSON 을 다시 읽는 별도 Rscript 를 띄우지 않는다: R 세션 기동 비용도 있지만
#     더 중요한 건 그 하위 프로세스가 조용히 죽으면 호출자가 **빈 문자열**을 받고
#     그걸 "stale 없음"으로 읽을 수 있다는 점이다(실측으로 그 상태를 봤다).
#     판정을 만든 바로 그 프로세스가 판정을 직접 뱉는 게 가장 짧은 신뢰 경로다.
cat(sprintf("EDC_RESULT stale=%d as_of=%s\n", length(stale_items), as.character(as_of)))

# Stale 시 Telegram alert (mrs_daily 의 07:30 brief 전에)
if (length(stale_items) > 0) {
  cat(sprintf("\n⚠️ STALE detected (%d items): %s\n", length(stale_items),
              paste(stale_items, collapse = ", ")))
  # QVEST_FRESHNESS_QUIET=1 → 판정·JSON 은 그대로 내되 Telegram 발송만 억제 (2026-08-03).
  #   ensure_data_current.sh 가 "고칠지 말지" 정하려고 **사전** 감사를 한 번 돌린다.
  #   그 단계의 stale 은 곧 고쳐질 수 있으므로 알릴 이유가 없고, 알리면 같은 아침에
  #   경보가 두 번 간다(사후 감사에서 한 번 더). ★억제되는 것은 발송뿐 — 판정과
  #   morning_freshness_latest.json 기록은 항상 남는다(조용한 통과가 아니다).
  if (identical(Sys.getenv("QVEST_FRESHNESS_QUIET"), "1")) {
    cat("[freshness] QVEST_FRESHNESS_QUIET=1 — Telegram 발송 억제 (판정/JSON 은 기록됨)\n")
  } else {
    source("02_Infrastructure/telegram/telegram_notify.R")
    msg <- sprintf("\U0001F6A8 Morning Freshness Audit — %d stale\n\n%s\n\nbrief 07:30 송신 전 점검 필요",
                   length(stale_items),
                   paste(sprintf("- %s", stale_items), collapse = "\n"))
    tryCatch(tg_send(msg), error = function(e) cat(sprintf("Telegram alert failed: %s\n", e$message)))
  }
} else {
  cat("\n✅ All sources FRESH — brief 07:30 발송 OK\n")
}
