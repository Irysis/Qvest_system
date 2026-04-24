#==============================================================================
# Quant Module — Regime Healthcheck (Step 7, v1.0)
# Author: Q-Lead (Session 70 — 2026-04-24)
#
# 책임:
#   1. 각 regime-infra cache 의 staleness + schema 검증
#   2. frequency-aware threshold 적용 (daily 7d / weekly 14d / monthly 45d / quarterly 120d)
#   3. FRED series 개별 frequency 적용 (`fred_macro.parquet` long Frequency 컬럼 활용)
#   4. 문제 감지 시 Telegram alert (tg_send_rich + tg_format_table) + log 기록
#
# 금지:
#   - 기존 cache 파일 수정 금지 (read-only 검사만)
#   - 기존 regime_signal.R / fred_robust.R 등 수정 금지
#
# Public API:
#   regime_health_check(alert_on_fail = TRUE, severity_threshold = "WARN")
#                                              # data.frame 반환 + alert 발송
#   regime_health_summary()                    # 콘솔 요약 (이모지)
#
# Internal:
#   .check_single_cache(spec)                  # 단일 spec 검사
#   .check_fred_per_series()                   # FRED long frequency-aware per-series 확장
#
# Status:
#   OK      : staleness ≤ threshold + schema valid + non-empty
#   STALE   : staleness > threshold                                (severity WARN)
#   BROKEN  : schema violation / rows=0 / Date 대량 NA             (severity HIGH)
#   MISSING : 파일 없음                                            (severity HIGH)
#
# Log:
#   /tmp/qvest_regime_health.log         — 매 실행 timestamp + 요약
#   /tmp/qvest_regime_health_alerts.log  — 문제 감지 시 alert 본문 append
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  .config_path <- tryCatch({
    .here <- dirname(sys.frame(1)$ofile)
    file.path(dirname(.here), "config.R")
  }, error = function(e) {
    file.path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
              "02_Infrastructure", "config.R")
  })
  source(.config_path)
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ─── Constants ──────────────────────────────────────────────────────────────
REGIME_HEALTH_LOG        <- "/tmp/qvest_regime_health.log"
REGIME_HEALTH_ALERTS_LOG <- "/tmp/qvest_regime_health_alerts.log"

# Frequency-aware staleness thresholds (days)
FREQ_THRESHOLDS <- list(
  daily     = 7L,    # 평일 기준 1주
  weekly    = 14L,
  monthly   = 45L,   # release delay 고려
  quarterly = 120L   # 재무제표 수준
)

# FRED Frequency 코드(d/w/m/q) → threshold 매핑
.fred_freq_to_key <- function(f) {
  f <- tolower(as.character(f))
  switch(f,
         "d" = "daily",
         "w" = "weekly",
         "m" = "monthly",
         "q" = "quarterly",
         "daily")  # default
}

# ─── Schema Specs ───────────────────────────────────────────────────────────
# 각 cache 별 expected schema + frequency + min bounds
SCHEMA_SPECS <- list(
  msm_daily = list(
    name          = "msm_daily",
    path          = file.path(CACHE_DIR, "msm_daily_latest.parquet"),
    format        = "parquet",
    freq          = "daily",
    required_cols = c("Date", "Price", "Vol_Est", "Crisis_Prob", "HMM_State"),
    min_rows      = 1000L,
    date_col      = "Date"
  ),
  fred_wide = list(
    name          = "fred_wide",
    path          = file.path(CACHE_DIR, "fred_macro_wide.parquet"),
    format        = "parquet",
    freq          = "daily",
    required_cols = c("Date"),
    min_cols      = 20L,   # 22 series + Date → ≥ 20 permissive
    min_rows      = 1000L,
    date_col      = "Date"
  ),
  fred_long = list(
    name          = "fred_long",
    path          = file.path(CACHE_DIR, "fred_macro.parquet"),
    format        = "parquet",
    freq          = "daily",  # overall; per-series checked separately
    required_cols = c("Date", "Series", "Series_ID", "Frequency", "Value"),
    min_rows      = 5000L,
    date_col      = "Date"
  ),
  ktri_daily = list(
    name          = "ktri_daily",
    path          = file.path(PROJECT_ROOT,
                              "04_Research/regime_comparison/output/ktri_v3_signals.csv"),
    format        = "csv",
    freq          = "daily",
    required_cols = c("DATE", "KTRI", "VEA", "IKS200", "Delta_KTRI", "Action_v3"),
    min_rows      = 1000L,
    date_col      = "DATE"
  ),
  regime_unified_monthly = list(
    name          = "regime_unified_monthly",
    path          = file.path(CACHE_DIR, "unified_regime_signal.parquet"),
    format        = "parquet",
    freq          = "monthly",
    required_cols = c("Date", "YM", "MSM_Crisis_Prob", "FRED_MRS",
                      "KTRI_Score", "Regime_Score", "Category"),
    min_rows      = 200L,
    date_col      = "Date"
  ),
  regime_unified_daily = list(
    name          = "regime_unified_daily",
    path          = file.path(CACHE_DIR, "unified_regime_signal_daily.parquet"),
    format        = "parquet",
    freq          = "daily",
    required_cols = c("Date", "YM", "Regime_Score", "Category",
                      "Active_Layers", "Is_Month_End"),
    min_rows      = 5000L,
    date_col      = "Date"
  ),
  benchmark = list(
    name          = "benchmark",
    path          = file.path(CACHE_DIR, "benchmark.parquet"),
    format        = "parquet",
    freq          = "daily",
    required_cols = c("Date", "BM_Close", "BM_Ret"),
    min_rows      = 1000L,
    date_col      = "Date"
  )
)

# ─── Internal Helpers ───────────────────────────────────────────────────────

# 단일 parquet/csv 로드 (silent on error)
.safe_read <- function(path, format = "parquet") {
  tryCatch({
    if (format == "parquet") {
      as.data.table(read_parquet(path))
    } else if (format == "csv") {
      fread(path, showProgress = FALSE)
    } else {
      NULL
    }
  }, error = function(e) {
    attr(e, "failed_path") <- path
    e
  })
}

# 단일 cache spec 에 대한 status 산출
.check_single_cache <- function(spec) {
  row_tpl <- data.table(
    cache_name      = spec$name,
    path            = spec$path,
    format          = spec$format,
    freq            = spec$freq,
    n_rows          = NA_integer_,
    n_cols          = NA_integer_,
    min_date        = as.Date(NA),
    max_date        = as.Date(NA),
    staleness_days  = NA_integer_,
    threshold_days  = as.integer(FREQ_THRESHOLDS[[spec$freq]] %||% 7L),
    missing_cols    = NA_character_,
    status          = NA_character_,
    severity        = NA_character_,
    note            = NA_character_
  )

  if (!file.exists(spec$path)) {
    row_tpl[, `:=`(status = "MISSING", severity = "HIGH",
                   note = "file not found")]
    return(row_tpl)
  }

  dt <- .safe_read(spec$path, spec$format)
  if (inherits(dt, "error") || is.null(dt)) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   note = paste0("read failed: ",
                                 if (inherits(dt, "error")) conditionMessage(dt)
                                 else "NULL"))]
    return(row_tpl)
  }
  row_tpl[, `:=`(n_rows = nrow(dt), n_cols = ncol(dt))]

  # rows=0 → BROKEN
  if (nrow(dt) == 0) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH", note = "0 rows")]
    return(row_tpl)
  }

  # Required columns
  missing <- setdiff(spec$required_cols, names(dt))
  if (length(missing) > 0) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   missing_cols = paste(missing, collapse = ","),
                   note = "schema missing cols")]
    return(row_tpl)
  }

  # min_rows
  if (!is.null(spec$min_rows) && nrow(dt) < spec$min_rows) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   note = sprintf("n_rows %d < min %d",
                                  nrow(dt), spec$min_rows))]
    return(row_tpl)
  }

  # min_cols
  if (!is.null(spec$min_cols) && ncol(dt) < spec$min_cols) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   note = sprintf("n_cols %d < min %d",
                                  ncol(dt), spec$min_cols))]
    return(row_tpl)
  }

  # Date column sanity
  dc <- spec$date_col
  if (!dc %in% names(dt)) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   note = sprintf("date col '%s' absent", dc))]
    return(row_tpl)
  }
  date_vec <- suppressWarnings(as.Date(dt[[dc]]))
  n_na <- sum(is.na(date_vec))
  if (n_na > nrow(dt) * 0.5) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   note = sprintf("%d/%d Date col NA (>50%%)",
                                  n_na, nrow(dt)))]
    return(row_tpl)
  }
  mn <- suppressWarnings(min(date_vec, na.rm = TRUE))
  mx <- suppressWarnings(max(date_vec, na.rm = TRUE))
  if (!is.finite(mn) || !is.finite(mx)) {
    row_tpl[, `:=`(status = "BROKEN", severity = "HIGH",
                   note = "Date col no finite values")]
    return(row_tpl)
  }
  stale <- as.integer(Sys.Date() - mx)
  thr   <- FREQ_THRESHOLDS[[spec$freq]] %||% 7L

  status_val   <- if (stale <= thr) "OK" else "STALE"
  severity_val <- if (status_val == "OK") "OK" else "WARN"
  note_val     <- if (status_val == "OK") "healthy"
                  else sprintf("%dd > %dd", stale, thr)

  row_tpl[, `:=`(
    min_date       = mn,
    max_date       = mx,
    staleness_days = stale,
    threshold_days = as.integer(thr),
    status         = status_val,
    severity       = severity_val,
    note           = note_val
  )]
  row_tpl
}

# %||% helper
`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1 && is.na(x))) y else x

# FRED long 파일 내 series 별 frequency-aware staleness 확장
.check_fred_per_series <- function(path = file.path(CACHE_DIR, "fred_macro.parquet")) {
  if (!file.exists(path)) return(NULL)
  dt <- .safe_read(path, "parquet")
  if (inherits(dt, "error") || is.null(dt) || nrow(dt) == 0) return(NULL)
  needed <- c("Date", "Series", "Frequency", "Value")
  if (any(!needed %in% names(dt))) return(NULL)

  per <- dt[, .(
    Frequency = first(Frequency),
    n         = .N,
    min_date  = min(Date, na.rm = TRUE),
    max_date  = max(Date, na.rm = TRUE)
  ), by = Series]
  per[, freq_key       := sapply(Frequency, .fred_freq_to_key)]
  per[, threshold_days := sapply(freq_key,
                                  function(k) FREQ_THRESHOLDS[[k]] %||% 7L)]
  per[, staleness_days := as.integer(Sys.Date() - max_date)]
  per[, status         := fifelse(staleness_days <= threshold_days, "OK", "STALE")]
  per[, severity       := fifelse(status == "OK", "OK", "WARN")]
  setnames(per, "Series", "cache_name")
  per[, path   := path]
  per[, format := "parquet"]
  per[, freq   := freq_key]
  per[, n_rows := n]
  per[, n_cols := NA_integer_]
  per[, missing_cols := NA_character_]
  per[, note := fifelse(status == "OK", "healthy",
                         sprintf("%dd > %dd (%s)",
                                 staleness_days, threshold_days, Frequency))]
  per[, cache_name := paste0("fred_series.", cache_name)]
  setcolorder(per, c("cache_name", "path", "format", "freq",
                     "n_rows", "n_cols", "min_date", "max_date",
                     "staleness_days", "threshold_days",
                     "missing_cols", "status", "severity", "note"))
  per[, Frequency := NULL]
  per[, freq_key  := NULL]
  per[, n         := NULL]
  per
}

# ─── Telegram alert composition ─────────────────────────────────────────────
.build_alert_message <- function(issues_dt, all_dt) {
  # all_dt: 전체 (OK + 문제). issues_dt: 문제만.
  src_tg <- tryCatch({
    source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(src_tg)) return(invisible(NULL))

  total_issues <- nrow(issues_dt)
  n_missing <- sum(issues_dt$status == "MISSING")
  n_broken  <- sum(issues_dt$status == "BROKEN")
  n_stale   <- sum(issues_dt$status == "STALE")

  # Top 부분: 요약
  header <- sprintf(
    "[Health] ⚠️ Regime Infra — %d건 문제 감지",
    total_issues
  )
  sep    <- "━━━━━━━━━━━━━━━"
  summary_line <- sprintf(
    "\U0001F4CA Summary: MISSING=%d / BROKEN=%d / STALE=%d",
    n_missing, n_broken, n_stale
  )

  # 상태 Table (문제 + OK 합산, max 10개 먼저)
  show_dt <- copy(all_dt[, .(cache_name, status, staleness_days, threshold_days, note)])
  show_dt[, stale := ifelse(is.na(staleness_days), "-",
                             paste0(staleness_days, "d"))]
  show_dt[, thr   := ifelse(is.na(threshold_days), "-",
                             paste0(threshold_days, "d"))]
  # 정렬: 문제 먼저 (MISSING/BROKEN/STALE → OK)
  show_dt[, prio := fifelse(status == "MISSING", 1L,
                     fifelse(status == "BROKEN", 2L,
                      fifelse(status == "STALE", 3L, 4L)))]
  setorder(show_dt, prio, cache_name)
  show_dt <- show_dt[1:min(.N, 15)]   # 15행 cap
  tbl_df <- data.frame(
    Cache    = substr(show_dt$cache_name, 1, 24),
    Status   = show_dt$status,
    Stale    = show_dt$stale,
    Thr      = show_dt$thr,
    stringsAsFactors = FALSE
  )

  # Note (문제만)
  note_lines <- if (nrow(issues_dt) > 0) {
    sapply(seq_len(min(nrow(issues_dt), 10)), function(i) {
      emoji <- switch(issues_dt$status[i],
                      "MISSING" = "❌",
                      "BROKEN"  = "❌",
                      "STALE"   = "⚠️",
                      "ℹ️")
      sprintf("%s %s %s — %s",
              emoji, issues_dt$status[i],
              tg_html_escape(issues_dt$cache_name[i]),
              tg_html_escape(issues_dt$note[i]))
    })
  } else character(0)

  # 권고 조치
  reco <- character(0)
  if (n_missing > 0) {
    reco <- c(reco,
              "• MISSING → daily_refresh.sh 재실행 필요")
  }
  if (n_broken > 0) {
    reco <- c(reco,
              "• BROKEN → schema 검증 + builder 로그 확인")
  }
  if (n_stale > 0) {
    reco <- c(reco,
              "• STALE → cron 스케줄 검증 (fred_robust / ktri_v3_builder)")
  }
  if (length(reco) == 0) reco <- "• 딥 조치 불요"

  msg <- paste(
    header, sep,
    summary_line,
    "",
    "\U0001F4CB Cache 상태",
    tg_format_table(tbl_df),
    if (length(note_lines) > 0) paste(c("", "\U0001F50D Details",
                                         note_lines), collapse = "\n") else "",
    "",
    "\U0001F6E0️ 권고 조치",
    paste(reco, collapse = "\n"),
    sep = "\n"
  )
  msg
}

# 로그 append helper
.append_log <- function(path, txt) {
  tryCatch({
    con <- file(path, "a")
    on.exit(close(con), add = TRUE)
    writeLines(txt, con)
  }, error = function(e) invisible(NULL))
}

# ─── Public: regime_health_check ────────────────────────────────────────────
# severity_threshold: "OK" = 전체 report, "WARN" = WARN 이상, "HIGH" = HIGH만
regime_health_check <- function(alert_on_fail      = TRUE,
                                 severity_threshold = "WARN",
                                 include_fred_per_series = TRUE) {
  ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  rows <- lapply(SCHEMA_SPECS, .check_single_cache)
  result <- rbindlist(rows, fill = TRUE)

  if (isTRUE(include_fred_per_series)) {
    per <- tryCatch(.check_fred_per_series(),
                    error = function(e) NULL)
    if (!is.null(per) && nrow(per) > 0) {
      result <- rbindlist(list(result, per), fill = TRUE)
    }
  }

  # Filter by severity for alert
  sev_rank <- c("OK" = 0L, "WARN" = 1L, "HIGH" = 2L)
  thr_rank <- sev_rank[severity_threshold] %||% 1L
  issues <- result[sev_rank[severity] >= thr_rank & status != "OK"]

  # Summary log
  summary <- sprintf(
    "[%s] regime_health_check: total=%d OK=%d STALE=%d BROKEN=%d MISSING=%d",
    ts, nrow(result),
    sum(result$status == "OK", na.rm = TRUE),
    sum(result$status == "STALE", na.rm = TRUE),
    sum(result$status == "BROKEN", na.rm = TRUE),
    sum(result$status == "MISSING", na.rm = TRUE)
  )
  .append_log(REGIME_HEALTH_LOG, summary)
  # detailed per-row log
  if (nrow(issues) > 0) {
    detail <- sapply(seq_len(nrow(issues)), function(i) {
      sprintf("[%s]   %s: %s (%s)", ts,
              issues$cache_name[i], issues$status[i], issues$note[i])
    })
    .append_log(REGIME_HEALTH_LOG, detail)
  }

  # Alert
  alerted <- FALSE
  if (isTRUE(alert_on_fail) && nrow(issues) > 0) {
    msg <- tryCatch(.build_alert_message(issues, result),
                    error = function(e) NULL)
    if (!is.null(msg) && nchar(msg) > 0) {
      .append_log(REGIME_HEALTH_ALERTS_LOG,
                  paste0("[", ts, "]\n", msg, "\n---"))
      send_ok <- tryCatch({
        tg_send_rich(msg)
        TRUE
      }, error = function(e) {
        .append_log(REGIME_HEALTH_ALERTS_LOG,
                    sprintf("[%s] tg_send_rich error: %s",
                            ts, conditionMessage(e)))
        FALSE
      })
      alerted <- isTRUE(send_ok)
    }
  }

  attr(result, "alerted")   <- alerted
  attr(result, "issues_n")  <- nrow(issues)
  attr(result, "timestamp") <- ts
  invisible(result)
}

# ─── Public: regime_health_summary ──────────────────────────────────────────
# 콘솔 pretty print — 이모지 + 요약
regime_health_summary <- function() {
  res <- regime_health_check(alert_on_fail = FALSE,
                              severity_threshold = "OK")
  cat("\n")
  cat("━━━ Regime Infra Healthcheck ━━━\n")
  cat(sprintf("Time: %s | Caches: %d\n",
              attr(res, "timestamp"), nrow(res)))
  cat(sprintf("  OK=%d | STALE=%d | BROKEN=%d | MISSING=%d\n",
              sum(res$status == "OK", na.rm = TRUE),
              sum(res$status == "STALE", na.rm = TRUE),
              sum(res$status == "BROKEN", na.rm = TRUE),
              sum(res$status == "MISSING", na.rm = TRUE)))
  cat("\n")

  emoji_map <- list(OK = "✅", STALE = "⚠️",
                    BROKEN = "❌", MISSING = "❌")
  for (i in seq_len(nrow(res))) {
    em <- emoji_map[[res$status[i]]] %||% "ℹ️"
    stale <- if (is.na(res$staleness_days[i])) "-"
             else paste0(res$staleness_days[i], "d")
    thr <- if (is.na(res$threshold_days[i])) "-"
           else paste0(res$threshold_days[i], "d")
    cat(sprintf("  %s %-28s %-8s stale=%-6s thr=%-6s | %s\n",
                em,
                substr(res$cache_name[i], 1, 28),
                res$status[i], stale, thr,
                res$note[i]))
  }
  cat("\n")
  invisible(res)
}

# ─── Message on source ──────────────────────────────────────────────────────
if (interactive() ||
    (exists("VERBOSE_REGIME_HEALTH") && isTRUE(VERBOSE_REGIME_HEALTH))) {
  cat("[regime_healthcheck] loaded.\n")
  cat("  regime_health_check(alert_on_fail = TRUE, severity_threshold = 'WARN')\n")
  cat("  regime_health_summary()\n")
}
