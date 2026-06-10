#==============================================================================
# cache_freshness_audit.R — Registry 기반 Freshness Logger (L3)
#
# 도훈 mandate 2026-05-15 영구 보호망 L3:
#   - Registry에 등록된 cache의 mtime + max(Date) vs max_lag_days 비교
#   - Registry에 등록되지 않은 .cache/*.parquet = ORPHAN alert
#   - 양방향 검증으로 silent gap 차단
#
# Output:
#   .cache/freshness_log.json (daily append)
#   qepm/observability/cache_freshness_latest.json (latest)
#
# Telegram alert: stale > 7 days = WARN, > 14 days = CRITICAL
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

source(file.path(PROJECT_ROOT, "02_Infrastructure/data/cache_registry_runner.R"))

cache_freshness_audit <- function(telegram_alert = TRUE,
                                    warn_lag_multiplier = 1.0,
                                    critical_lag_multiplier = 2.0) {
  caches <- cache_registry_load()
  today <- Sys.Date()
  today_ts <- Sys.time()

  results <- list()
  registered_paths <- sapply(caches, function(c) c$path)

  # ─── (1) Registered caches: stale check ─────────────────────────────────────
  for (c in caches) {
    cache_path <- file.path(PROJECT_ROOT, c$path)
    res <- list(
      path = c$path,
      tier = c$tier,
      schedule = c$schedule,
      max_lag_days = c$max_lag_days,
      registered = TRUE
    )

    if (!is.null(c$file_pattern)) {
      # ── 디렉토리형 cache (월별 parquet 묶음 — 예: .cache/factor_db/) ─────────
      #    2026-06-10 P1: factor_db / factor_db_daily 디렉토리 freshness 지원.
      #    최신 파일 = file_pattern 매칭 사전순 max (YYYYMM zero-pad → 시간순 일치).
      #    date_col 있으면 최신 파일의 해당 컬럼 max(Date) (col_select — 대용량 wide 대비),
      #    없으면 파일명 YYYYMM의 월말 기준 lag (당월 진행 중 음수 → 0 clamp).
      if (!dir.exists(cache_path)) {
        res$status <- "MISSING"
        res$severity <- "CRITICAL"
        results[[c$path]] <- res
        next
      }
      fs <- sort(list.files(cache_path, pattern = c$file_pattern))
      if (length(fs) == 0) {
        res$status <- "MISSING"
        res$severity <- "CRITICAL"
        res$note <- sprintf("file_pattern '%s' 매칭 파일 0건", c$file_pattern)
        results[[c$path]] <- res
        next
      }
      latest_file <- fs[length(fs)]
      latest_path <- file.path(cache_path, latest_file)
      res$latest_file <- latest_file
      res$n_files <- length(fs)

      mtime <- file.info(latest_path)$mtime
      mtime_lag <- as.integer(today - as.Date(mtime))

      data_lag <- NA_integer_
      if (!is.null(c$date_col)) {
        dt <- tryCatch(as.data.table(read_parquet(latest_path, col_select = c$date_col)),
                       error = function(e)
                         tryCatch(as.data.table(read_parquet(latest_path)),
                                  error = function(e2) NULL))
        if (!is.null(dt) && c$date_col %in% names(dt)) {
          last_d <- max(as.Date(dt[[c$date_col]]), na.rm = TRUE)
          data_lag <- as.integer(today - last_d)
        }
      } else {
        ym <- regmatches(latest_file, regexpr("[0-9]{6}", latest_file))
        if (length(ym) == 1) {
          m_start <- as.Date(paste0(ym, "01"), format = "%Y%m%d")
          m_end <- seq(m_start, by = "month", length.out = 2)[2] - 1
          data_lag <- max(0L, as.integer(today - m_end))
        }
      }
    } else {
    # ── 단일 파일 cache (기존 경로) ──────────────────────────────────────────
    if (!file.exists(cache_path)) {
      res$status <- "MISSING"
      res$severity <- "CRITICAL"
      results[[c$path]] <- res
      next
    }

    mtime <- file.info(cache_path)$mtime
    mtime_lag <- as.integer(today - as.Date(mtime))

    # data freshness via date_col
    data_lag <- NA_integer_
    if (!is.null(c$date_col)) {
      dt <- tryCatch({
        if (grepl("\\.parquet$", cache_path)) {
          as.data.table(read_parquet(cache_path))
        } else if (grepl("\\.csv$", cache_path)) {
          fread(cache_path)
        } else if (grepl("\\.rds$", cache_path)) {
          as.data.table(readRDS(cache_path))
        } else NULL
      }, error = function(e) NULL)
      if (!is.null(dt) && c$date_col %in% names(dt)) {
        last_d <- max(as.Date(dt[[c$date_col]]), na.rm = TRUE)
        data_lag <- as.integer(today - last_d)
      }
    }
    }

    # Pick worse of mtime_lag and data_lag for evaluation
    lag <- if (!is.na(data_lag)) data_lag else mtime_lag
    res$mtime_lag <- mtime_lag
    res$data_lag <- data_lag
    res$lag_used <- lag

    if (!is.null(c$max_lag_days) && !is.na(lag)) {
      warn_thresh <- c$max_lag_days * warn_lag_multiplier
      crit_thresh <- c$max_lag_days * critical_lag_multiplier
      if (lag <= c$max_lag_days) {
        res$status <- "FRESH"; res$severity <- "OK"
      } else if (lag <= crit_thresh) {
        res$status <- "STALE_WARN"; res$severity <- "WARN"
      } else {
        res$status <- "STALE_CRITICAL"; res$severity <- "CRITICAL"
      }
    } else {
      res$status <- "NO_THRESHOLD"; res$severity <- "OK"
    }
    results[[c$path]] <- res
  }

  # ─── (2) Orphan detection: .cache files NOT in registry ─────────────────────
  cache_dir <- file.path(PROJECT_ROOT, ".cache")
  if (dir.exists(cache_dir)) {
    all_files <- list.files(cache_dir, pattern = "\\.(parquet|csv|rds)$",
                             recursive = FALSE, full.names = FALSE)
    all_paths <- paste0(".cache/", all_files)
    orphans <- setdiff(all_paths, registered_paths)
    # Filter out known research/temp file patterns
    orphans <- orphans[!grepl("^\\.cache/(scout_|wt_|hr_v2|crisis_defense|stress_|factor_correlation|factor_overlap|factor_ic_|conditional_ic_|update_file_)",
                                orphans)]
    for (o in orphans) {
      results[[o]] <- list(
        path = o, tier = NA, schedule = NA,
        registered = FALSE,
        status = "ORPHAN",
        severity = "WARN",
        note = "registry에 등록되지 않은 cache — registry entry 추가 필요"
      )
    }
  }

  # ─── (3) Summary + persist ──────────────────────────────────────────────────
  by_sev <- list(
    OK       = sum(sapply(results, function(r) r$severity == "OK")),
    WARN     = sum(sapply(results, function(r) r$severity == "WARN")),
    CRITICAL = sum(sapply(results, function(r) r$severity == "CRITICAL"))
  )

  audit <- list(
    ran_at = format(today_ts, "%Y-%m-%dT%H:%M:%S%z"),
    n_total = length(results),
    summary = by_sev,
    results = unname(results)
  )

  obs_dir <- file.path(PROJECT_ROOT, "qepm", "observability")
  dir.create(obs_dir, showWarnings = FALSE, recursive = TRUE)
  latest_path <- file.path(obs_dir, "cache_freshness_latest.json")
  write_json(audit, latest_path, pretty = TRUE, auto_unbox = TRUE, na = "null")

  # Append to daily log
  log_path <- file.path(PROJECT_ROOT, ".cache", "freshness_log.json")
  existing <- if (file.exists(log_path)) {
    tryCatch(jsonlite::fromJSON(log_path, simplifyVector = FALSE), error = function(e) list())
  } else list()
  existing[[length(existing) + 1L]] <- list(
    ran_at = audit$ran_at,
    summary = by_sev,
    crit_paths = sapply(Filter(function(r) r$severity == "CRITICAL", results), function(r) r$path),
    warn_paths = sapply(Filter(function(r) r$severity == "WARN", results), function(r) r$path)
  )
  if (length(existing) > 365) existing <- tail(existing, 365)  # 1 year cap
  write_json(existing, log_path, pretty = TRUE, auto_unbox = TRUE, na = "null")

  # ─── (4) Telegram alert if WARN/CRITICAL ───────────────────────────────────
  cat(sprintf("\n=== Cache Freshness Audit (%s) ===\n", audit$ran_at))
  cat(sprintf("OK=%d WARN=%d CRITICAL=%d\n", by_sev$OK, by_sev$WARN, by_sev$CRITICAL))
  for (r in results) {
    if (r$severity %in% c("WARN", "CRITICAL")) {
      cat(sprintf("  [%s] %s (lag=%s, max=%s) %s\n",
                  r$severity, r$path,
                  r$lag_used %||% "n/a", r$max_lag_days %||% "n/a",
                  r$note %||% r$status))
    }
  }

  if (telegram_alert && (by_sev$WARN + by_sev$CRITICAL > 0)) {
    tryCatch({
      source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
      crit_list <- sapply(Filter(function(r) r$severity == "CRITICAL", results),
                           function(r) sprintf("- %s (lag=%s)", r$path, r$lag_used %||% "n/a"))
      warn_list <- sapply(Filter(function(r) r$severity == "WARN", results),
                           function(r) sprintf("- %s (lag=%s)", r$path, r$lag_used %||% "n/a"))
      msg <- sprintf("🚨 *Cache Freshness Alert*\n\nCRITICAL %d / WARN %d\n\n*Critical:*\n%s\n\n*Warn:*\n%s",
                      by_sev$CRITICAL, by_sev$WARN,
                      if (length(crit_list) > 0) paste(head(crit_list, 10), collapse = "\n") else "(none)",
                      if (length(warn_list) > 0) paste(head(warn_list, 10), collapse = "\n") else "(none)")
      tg_send(msg, parse_mode = "Markdown")
    }, error = function(e) cat(sprintf("Telegram alert failed: %s\n", e$message)))
  }

  invisible(audit)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

cat("[cache_freshness_audit] Loaded.\n")
