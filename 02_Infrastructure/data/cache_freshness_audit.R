#==============================================================================
# cache_freshness_audit.R — Registry 기반 Freshness Logger (L3)
#
# 도훈 mandate 2026-05-15 영구 보호망 L3:
#   - Registry에 등록된 cache의 mtime + max(Date) vs max_lag_days 비교
#   - Registry에 등록되지 않은 .cache/*.parquet = ORPHAN alert
#   - 양방향 검증으로 silent gap 차단
#
# 2026-07-03 (감사 DATA-P0-1) 값-sanity 섹션 추가:
#   - 신선도(mtime/max Date) 단일축의 맹점 보완 — RAWDATA BM_Ret +581% 손상값이
#     FRESH로 판정되고 7월 factor DB가 이를 소비해 59~60팩터(M08 포함) 결손되던
#     사고 재발 방지. registry 항목의 value_checks 선언 소비:
#       abs_ret_max   : |col| > threshold 건수 (값 폭주 탐지)
#       required_cols : 필수 컬럼 존재 (K200/KQ150 strip 사고 탐지)
#       parity        : 기준 캐시 대비 월수익(log1p 합) 상관 (손상 구간 탐지)
#   - 위반 = VALUE_FAIL / CRITICAL (등록 캐시로 취급 → telegram alert 경로 포함)
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

  # ─── (1b) Value-sanity checks — registry value_checks 소비 (2026-07-03) ─────
  #   신선도와 독립인 별도 result 항목("<path>::value")으로 기록. 파일 자체가 없으면
  #   (1)의 MISSING/CRITICAL이 이미 커버하므로 스킵. parquet 전용 (col_select로
  #   필요 컬럼만 read — RAWDATA 417MB full-load 회피). 위반 시 CRITICAL.
  for (c in caches) {
    if (is.null(c$value_checks)) next
    cache_path <- file.path(PROJECT_ROOT, c$path)
    vres <- list(
      path = paste0(c$path, "::value"),
      tier = c$tier, schedule = c$schedule,
      registered = TRUE, check = "value_sanity"
    )
    if (!file.exists(cache_path) || !grepl("\\.parquet$", cache_path)) {
      vres$status <- "VALUE_SKIP"; vres$severity <- "OK"
      vres$note <- "파일 없음 또는 비-parquet — (1) freshness 결과 참조"
      results[[vres$path]] <- vres
      next
    }
    vc <- c$value_checks
    viol <- character(0)

    # 스키마 (lazy scan — full read 없이 컬럼명만)
    sch_names <- tryCatch(arrow::open_dataset(cache_path)$schema$names,
                          error = function(e) NULL)

    # (a) required_cols — K200/KQ150 등 Layer2 컬럼 strip 사고 탐지
    if (!is.null(vc$required_cols)) {
      req <- unlist(vc$required_cols)
      if (is.null(sch_names)) {
        viol <- c(viol, "required_cols: 스키마 read 실패")
      } else {
        miss <- setdiff(req, sch_names)
        if (length(miss) > 0)
          viol <- c(viol, sprintf("required_cols 누락: %s", paste(miss, collapse = ",")))
        vres$required_cols_missing <- if (length(miss) > 0) miss else NULL
      }
    }

    # 대상 컬럼 read helper — Date + 지정 컬럼만, 날짜별 unique (RAWDATA는
    # BM_Ret가 종목 행마다 반복이므로 날짜 단위로 축약)
    .read_date_col <- function(path, col) {
      if (is.null(sch_names) && path == cache_path) return(NULL)
      dt <- tryCatch(
        as.data.table(read_parquet(path, col_select = tidyselect::all_of(c("Date", col)))),
        error = function(e) NULL)
      if (is.null(dt) || !all(c("Date", col) %in% names(dt))) return(NULL)
      dt <- dt[!is.na(get(col))]
      dt[, Date := as.Date(Date)]
      unique(dt, by = "Date")[, .(Date, v = get(col))]
    }

    # (b) abs_ret_max — 값 폭주 (예: BM_Ret +581% 손상)
    if (!is.null(vc$abs_ret_max)) {
      arm <- vc$abs_ret_max
      d <- .read_date_col(cache_path, arm$col)
      if (is.null(d)) {
        viol <- c(viol, sprintf("abs_ret_max: 컬럼 %s read 실패", arm$col))
      } else {
        thr <- arm$threshold %||% 0.15
        max_v <- arm$max_violations %||% 0L
        n_bad <- d[abs(v) > thr, .N]
        vres$abs_ret_n_violations <- n_bad
        vres$abs_ret_max_abs <- round(max(abs(d$v), na.rm = TRUE), 4)
        if (n_bad > max_v) {
          bad_dates <- d[abs(v) > thr][order(-abs(v))][seq_len(min(5L, n_bad))]
          viol <- c(viol, sprintf("|%s|>%.2f %d건 (max=%.4f, 예: %s)",
                                  arm$col, thr, n_bad, vres$abs_ret_max_abs,
                                  paste(format(bad_dates$Date), collapse = ",")))
        }
      }
    }

    # (c) parity — 기준 캐시(benchmark.parquet) 대비 월수익 상관
    if (!is.null(vc$parity)) {
      pr <- vc$parity
      against_path <- file.path(PROJECT_ROOT, pr$against)
      d_self <- .read_date_col(cache_path, pr$col)
      d_ref  <- if (file.exists(against_path))
                  .read_date_col(against_path, pr$against_col %||% pr$col)
                else NULL
      if (is.null(d_self) || is.null(d_ref)) {
        viol <- c(viol, sprintf("parity: %s 또는 %s read 실패", c$path, pr$against))
      } else {
        m <- merge(d_self, d_ref, by = "Date", suffixes = c("_a", "_b"))
        if (nrow(m) < 60L) {
          viol <- c(viol, sprintf("parity: 공통 날짜 %d건 (<60) — 대조 불가", nrow(m)))
        } else {
          # 월수익 parity: log1p 합 기준 (데이터 무결성 대조용 — 백테스트 수익 합성 아님)
          m[, ym := format(Date, "%Y-%m")]
          mm <- m[, .(a = sum(log1p(pmax(v_a, -0.9999))),
                      b = sum(log1p(pmax(v_b, -0.9999)))), by = ym]
          mcor <- suppressWarnings(cor(mm$a, mm$b))
          vres$parity_monthly_cor <- round(mcor, 6)
          vres$parity_n_months <- nrow(mm)
          min_cor <- pr$min_monthly_cor %||% 0.99
          if (is.na(mcor) || mcor < min_cor)
            viol <- c(viol, sprintf("parity: 월수익 상관 %.4f < %.2f (vs %s)",
                                    mcor, min_cor, pr$against))
        }
      }
    }

    if (length(viol) > 0) {
      vres$status <- "VALUE_FAIL"; vres$severity <- "CRITICAL"
      vres$note <- paste(viol, collapse = " | ")
    } else {
      vres$status <- "VALUE_PASS"; vres$severity <- "OK"
    }
    results[[vres$path]] <- vres
  }

  # ─── (2) Orphan detection: .cache files NOT in registry ─────────────────────
  cache_dir <- file.path(PROJECT_ROOT, ".cache")
  if (dir.exists(cache_dir)) {
    all_files <- list.files(cache_dir, pattern = "\\.(parquet|csv|rds)$",
                             recursive = FALSE, full.names = FALSE)
    all_paths <- paste0(".cache/", all_files)
    orphans <- setdiff(all_paths, registered_paths)
    # Filter out known research/temp file patterns
    # 2026-06-26: 스크래치/임시 제외 강화 — 리서치 세션이 만드는 `_`-접두 임시 .rds/.csv,
    #   timestamp 백업(_YYYYMMDD_HHMMSS), *_corrupt_*, backfill audit 등은 데이터 소스가 아니라
    #   ephemeral → orphan 노이즈(WARN 118 중 ~110이 이것). `_`-접두 = ephemeral 컨벤션으로 제외.
    orphans <- orphans[!grepl("^\\.cache/(_|scout_|wt_|hr_v2|crisis_defense|stress_|factor_correlation|factor_overlap|factor_ic_|conditional_ic_|update_file_)",
                                orphans)]
    orphans <- orphans[!grepl("(_corrupt|_backup_|_[0-9]{8}_[0-9]{6}|backfill_v8_audit)", orphans)]
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

  # ─── 알림 트리거 = 등록 캐시의 실제 stale/missing 만 (2026-06-26) ───────────
  # orphan(registry 미등재)은 데이터 노후가 아니라 registry 위생 이슈 → JSON 로그·콘솔엔 남기되
  #   "Cache Freshness Alert"(데이터 신선도 경보) 트리거에서는 제외. orphan 노이즈로 실질
  #   stale(예: factor_db_daily)이 묻히던 문제 해소. orphan 건수는 footnote 로만 통지.
  is_orphan <- function(r) isTRUE(r$status == "ORPHAN") || !isTRUE(r$registered)
  alert_items <- Filter(function(r) r$severity %in% c("WARN", "CRITICAL") && !is_orphan(r), results)
  n_orphan    <- sum(vapply(results, function(r) isTRUE(r$status == "ORPHAN"), logical(1)))
  alert_crit  <- sum(vapply(alert_items, function(r) r$severity == "CRITICAL", logical(1)))
  alert_warn  <- sum(vapply(alert_items, function(r) r$severity == "WARN", logical(1)))

  if (telegram_alert && length(alert_items) > 0) {
    tryCatch({
      source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
      crit_list <- sapply(Filter(function(r) r$severity == "CRITICAL", alert_items),
                           function(r) sprintf("- %s (lag=%s, max=%s)", r$path, r$lag_used %||% "n/a", r$max_lag_days %||% "n/a"))
      warn_list <- sapply(Filter(function(r) r$severity == "WARN", alert_items),
                           function(r) sprintf("- %s (lag=%s, max=%s)", r$path, r$lag_used %||% "n/a", r$max_lag_days %||% "n/a"))
      orphan_note <- if (n_orphan > 0)
        sprintf("\n\n_(orphan %d건은 registry 미등재 — 로그만, 알림 제외)_", n_orphan) else ""
      msg <- sprintf("🚨 *Cache Freshness Alert*\n\nCRITICAL %d / WARN %d (등록 캐시 stale 기준)\n\n*Critical:*\n%s\n\n*Warn:*\n%s%s",
                      alert_crit, alert_warn,
                      if (length(crit_list) > 0) paste(head(crit_list, 10), collapse = "\n") else "(none)",
                      if (length(warn_list) > 0) paste(head(warn_list, 10), collapse = "\n") else "(none)",
                      orphan_note)
      tg_send(msg, parse_mode = "Markdown")
    }, error = function(e) cat(sprintf("Telegram alert failed: %s\n", e$message)))
  } else if (telegram_alert) {
    cat(sprintf("[cache_freshness] 등록 캐시 전부 fresh — 알림 생략 (orphan %d건은 로그만)\n", n_orphan))
  }

  invisible(audit)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

cat("[cache_freshness_audit] Loaded.\n")
