#==============================================================================
# Quant Module — FRED Robust Fetcher (Step 4, v1.0)
# Author: Q-Lead (Session 70 — 2026-04-24)
#
# 책임:
#   1. 22 FRED macro series를 per-series retry + graceful degrade 방식으로 수집
#   2. Long + Wide 양 format 동시 저장 (backward compat)
#   3. Schema validation + staleness metrics 제공
#   4. 실패 격리: 개별 series fail → 나머지 저장 (cache 무결성 유지)
#
# 참조:
#   - Series list: 02_Infrastructure/data/data_collector_fred.R (변경 금지, 참조만)
#   - 설계 문서: 02_Infrastructure/regime/README.md (Step 4)
#
# Public API:
#   fred_robust_fetch_all(start_date="2000-01-01", force=FALSE) → invisible(list)
#   fred_robust_health()                                         → data.table
#   fred_robust_wide_load()                                      → data.table (Date × series)
#
# Schema Spec (`.cache/fred_macro_wide.parquet`):
#   Date           Date                  거래일 (ISO date)
#   <Series_Name>  numeric               각 22 series 중 fetch 성공한 컬럼
#
# Schema Spec (`.cache/fred_macro.parquet` long, backward compat):
#   Date           Date
#   Series         character  (friendly name — e.g. "VIX", "HY_Spread")
#   Series_ID      character  (FRED ID — e.g. "VIXCLS", "BAMLH0A0HYM2")
#   Frequency      character  (d/w/m/q)
#   Value          numeric
#
# Log:
#   /tmp/qvest_fred_robust.log — per-series status, row count, elapsed
#
# 실행 시 Telegram 발송 금지 (briefing은 별도).
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  .config_path <- tryCatch({
    .here <- dirname(sys.frame(1)$ofile)
    file.path(dirname(.here), "config.R")
  }, error = function(e) {
    file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
              "02_Infrastructure", "config.R")
  })
  source(.config_path)
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(httr)
  library(jsonlite)
})

# ─── Paths ──────────────────────────────────────────────────────────────────
FRED_ROBUST_LONG  <- file.path(CACHE_DIR, "fred_macro.parquet")
FRED_ROBUST_WIDE  <- file.path(CACHE_DIR, "fred_macro_wide.parquet")
FRED_ROBUST_LOG   <- "/tmp/qvest_fred_robust.log"

# ─── Series list (data_collector_fred.R 에서 참조) ──────────────────────────
# 원본 상수 추출. data_collector_fred.R 수정 금지 지시에 따라 source()하여 참조.
.load_fred_series_list <- function() {
  collector_path <- file.path(FUNC_PATH, "data", "data_collector_fred.R")
  if (!file.exists(collector_path)) {
    stop("[fred_robust] data_collector_fred.R not found: ", collector_path)
  }
  # source() in isolated env to pick up FRED_SERIES
  env <- new.env()
  suppressMessages(sys.source(collector_path, envir = env, keep.source = FALSE))
  if (!exists("FRED_SERIES", envir = env)) {
    stop("[fred_robust] FRED_SERIES not found after sourcing data_collector_fred.R")
  }
  env$FRED_SERIES
}

# ─── API Key loader (telegram_notify.R 의 .tg_load_env 와 동일 패턴) ────────
.load_fred_api_key <- function() {
  env_path <- file.path(PROJECT_ROOT, ".env")
  if (!file.exists(env_path)) {
    stop("[fred_robust] .env not found: ", env_path)
  }
  lines <- readLines(env_path, warn = FALSE)
  key <- NULL
  for (line in lines) {
    if (grepl("^FRED_API_KEY=", line)) {
      key <- sub("^FRED_API_KEY=", "", trimws(line))
      break
    }
  }
  if (is.null(key) || nchar(key) < 10) {
    stop("[fred_robust] FRED_API_KEY missing/too short in .env")
  }
  key
}

# ─── Log helper ─────────────────────────────────────────────────────────────
.flog <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] %s\n", ts, msg)
  cat(line)
  tryCatch(cat(line, file = FRED_ROBUST_LOG, append = TRUE), error = function(e) NULL)
}

# ─── Single series fetch with retry ─────────────────────────────────────────
.fred_fetch_with_retry <- function(series_id, api_key, start_date, end_date = NULL,
                                    max_retries = 3L) {
  if (is.null(end_date)) end_date <- format(Sys.Date(), "%Y-%m-%d")
  url <- "https://api.stlouisfed.org/fred/series/observations"

  attempt <- 0L
  last_err <- NULL
  while (attempt < max_retries) {
    attempt <- attempt + 1L
    resp <- tryCatch(
      GET(url, query = list(
        series_id         = series_id,
        api_key           = api_key,
        file_type         = "json",
        observation_start = start_date,
        observation_end   = end_date
      ), timeout(30)),
      error = function(e) { last_err <<- conditionMessage(e); NULL }
    )

    if (!is.null(resp) && status_code(resp) == 200) {
      body <- content(resp, "text", encoding = "UTF-8")
      json <- tryCatch(fromJSON(body), error = function(e) NULL)
      if (!is.null(json) && !is.null(json$observations)) {
        obs <- as.data.table(json$observations)
        if (nrow(obs) == 0) {
          return(list(ok = TRUE, dt = NULL, retries = attempt - 1L,
                      msg = "empty"))
        }
        obs[, value := suppressWarnings(as.numeric(value))]
        obs[, date  := as.Date(date)]
        obs <- obs[!is.na(value), .(Date = date, Value = value)]
        return(list(ok = TRUE, dt = obs, retries = attempt - 1L,
                    msg = sprintf("%d obs", nrow(obs))))
      }
      last_err <- "malformed JSON"
    } else if (!is.null(resp)) {
      last_err <- sprintf("HTTP %d", status_code(resp))
    }

    # Exponential backoff: 1s, 2s, 4s
    if (attempt < max_retries) {
      sleep_s <- 2 ^ (attempt - 1L)
      Sys.sleep(sleep_s)
    }
  }

  list(ok = FALSE, dt = NULL, retries = max_retries,
       msg = sprintf("FAIL after %d attempts: %s", max_retries,
                     last_err %||% "unknown"))
}

# NULL coalesce
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#==============================================================================
# 1. fred_robust_fetch_all
#==============================================================================
fred_robust_fetch_all <- function(start_date = "2000-01-01", force = FALSE) {
  t0 <- Sys.time()
  # reset log for this run
  tryCatch(cat("", file = FRED_ROBUST_LOG, append = FALSE), error = function(e) NULL)
  .flog("=== fred_robust_fetch_all START ===")
  .flog(sprintf("start_date=%s | force=%s", start_date, force))

  # Backup existing long parquet (once per day)
  if (file.exists(FRED_ROBUST_LONG)) {
    bak_path <- paste0(FRED_ROBUST_LONG, ".bak_", format(Sys.Date(), "%Y%m%d"))
    if (!file.exists(bak_path)) {
      tryCatch(file.copy(FRED_ROBUST_LONG, bak_path, overwrite = FALSE),
               error = function(e) .flog(sprintf("backup skip: %s", e$message)))
      .flog(sprintf("backup: %s", bak_path))
    }
  }

  series_list <- .load_fred_series_list()
  .flog(sprintf("Loaded %d series definitions", length(series_list)))

  api_key <- .load_fred_api_key()

  results <- list()
  per_series_status <- list()
  n_ok <- 0L; n_empty <- 0L; n_fail <- 0L

  for (s in series_list) {
    ts0 <- Sys.time()
    r <- .fred_fetch_with_retry(s$id, api_key, start_date, max_retries = 3L)
    elapsed <- as.numeric(difftime(Sys.time(), ts0, units = "secs"))

    status <- if (r$ok && !is.null(r$dt) && nrow(r$dt) > 0) "OK" else
              if (r$ok && is.null(r$dt)) "EMPTY" else "FAIL"

    if (status == "OK") {
      dt <- copy(r$dt)
      dt[, Series    := s$name]
      dt[, Series_ID := s$id]
      dt[, Frequency := s$freq]
      results[[s$name]] <- dt
      n_ok <- n_ok + 1L
      .flog(sprintf("  %-20s (%-14s) OK    | %d obs | retries=%d | %.2fs",
                    s$name, s$id, nrow(dt), r$retries, elapsed))
    } else if (status == "EMPTY") {
      n_empty <- n_empty + 1L
      .flog(sprintf("  %-20s (%-14s) EMPTY | retries=%d | %.2fs",
                    s$name, s$id, r$retries, elapsed))
    } else {
      n_fail <- n_fail + 1L
      .flog(sprintf("  %-20s (%-14s) FAIL  | %s | %.2fs",
                    s$name, s$id, r$msg, elapsed))
    }

    per_series_status[[s$name]] <- data.table(
      Series = s$name, Series_ID = s$id, Frequency = s$freq,
      status = status, rows = if (status == "OK") nrow(r$dt) else 0L,
      retries = r$retries, elapsed_sec = round(elapsed, 2),
      msg = r$msg
    )

    Sys.sleep(0.3)  # rate-limit safety (FRED: 120/min)
  }

  total_elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  .flog(sprintf("Fetch summary: %d OK / %d EMPTY / %d FAIL (total %d)",
                n_ok, n_empty, n_fail, length(series_list)))
  .flog(sprintf("Total elapsed: %.2fs", total_elapsed))

  # Guard: all failed → abort (preserve existing cache)
  if (length(results) == 0) {
    .flog("ABORT: no series fetched. Cache not overwritten.")
    warning("[fred_robust] all series failed. Existing cache preserved.")
    return(invisible(list(ok = FALSE,
                          status = rbindlist(per_series_status, fill = TRUE))))
  }

  # ── Long format ──
  long_dt <- rbindlist(results, fill = TRUE)
  setcolorder(long_dt, c("Date", "Series", "Series_ID", "Frequency", "Value"))
  setorder(long_dt, Series, Date)

  # ── Wide format ──
  wide_dt <- dcast(long_dt, Date ~ Series, value.var = "Value")
  setorder(wide_dt, Date)

  # ── Atomic write: tmp → rename ──
  .atomic_write_parquet <- function(dt, path) {
    tmp <- paste0(path, ".tmp")
    write_parquet(dt, tmp)
    file.rename(tmp, path)
  }

  .atomic_write_parquet(long_dt, FRED_ROBUST_LONG)
  .atomic_write_parquet(wide_dt, FRED_ROBUST_WIDE)

  .flog(sprintf("Saved long: %s (%d rows, %d series)",
                FRED_ROBUST_LONG, nrow(long_dt), uniqueN(long_dt$Series)))
  .flog(sprintf("Saved wide: %s (%d rows, %d cols)",
                FRED_ROBUST_WIDE, nrow(wide_dt), ncol(wide_dt) - 1L))
  .flog("=== fred_robust_fetch_all END ===")

  invisible(list(
    ok = TRUE,
    long = long_dt,
    wide = wide_dt,
    status = rbindlist(per_series_status, fill = TRUE),
    n_ok = n_ok, n_empty = n_empty, n_fail = n_fail,
    elapsed_sec = round(total_elapsed, 2)
  ))
}

#==============================================================================
# 2. fred_robust_health — cache 진단 (staleness + schema + NA ratio)
#==============================================================================
fred_robust_health <- function() {
  out_rows <- list()

  for (info in list(
    list(path = FRED_ROBUST_WIDE, tag = "wide"),
    list(path = FRED_ROBUST_LONG, tag = "long")
  )) {
    if (!file.exists(info$path)) {
      out_rows[[info$tag]] <- data.table(
        tag = info$tag, path = info$path, exists = FALSE,
        series = NA_character_, n = 0L,
        min_date = as.Date(NA), max_date = as.Date(NA),
        staleness_days = NA_integer_, na_ratio = NA_real_, status = "MISSING"
      )
      next
    }
    dt <- tryCatch(as.data.table(read_parquet(info$path)),
                   error = function(e) NULL)
    if (is.null(dt) || nrow(dt) == 0) {
      out_rows[[info$tag]] <- data.table(
        tag = info$tag, path = info$path, exists = TRUE,
        series = NA_character_, n = 0L,
        min_date = as.Date(NA), max_date = as.Date(NA),
        staleness_days = NA_integer_, na_ratio = NA_real_, status = "EMPTY"
      )
      next
    }

    # Normalize Date col (both 'Date' and 'date' accepted)
    date_col <- intersect(c("Date", "date"), names(dt))[1]
    if (is.na(date_col)) {
      out_rows[[info$tag]] <- data.table(
        tag = info$tag, path = info$path, exists = TRUE,
        series = NA_character_, n = nrow(dt),
        min_date = as.Date(NA), max_date = as.Date(NA),
        staleness_days = NA_integer_, na_ratio = NA_real_,
        status = "NO_DATE_COL"
      )
      next
    }
    dt[, (date_col) := as.Date(get(date_col))]

    if (info$tag == "wide") {
      value_cols <- setdiff(names(dt), date_col)
      for (vc in value_cols) {
        vals <- dt[[vc]]
        nz <- sum(!is.na(vals))
        if (nz == 0) {
          out_rows[[paste0("wide_", vc)]] <- data.table(
            tag = "wide", path = info$path, exists = TRUE,
            series = vc, n = 0L,
            min_date = as.Date(NA), max_date = as.Date(NA),
            staleness_days = NA_integer_, na_ratio = 1,
            status = "ALL_NA"
          )
          next
        }
        obs_dates <- dt[[date_col]][!is.na(vals)]
        mx <- max(obs_dates)
        stale <- as.integer(Sys.Date() - mx)
        na_r  <- 1 - (nz / nrow(dt))
        status <- if (stale <= 7) "OK" else if (stale <= 30) "STALE" else "VERY_STALE"
        out_rows[[paste0("wide_", vc)]] <- data.table(
          tag = "wide", path = info$path, exists = TRUE,
          series = vc, n = nz,
          min_date = min(obs_dates), max_date = mx,
          staleness_days = stale, na_ratio = round(na_r, 3),
          status = status
        )
      }
    } else {
      # long: per Series
      if (!"Series" %in% names(dt)) {
        out_rows[["long_schema"]] <- data.table(
          tag = "long", path = info$path, exists = TRUE,
          series = NA_character_, n = nrow(dt),
          min_date = as.Date(NA), max_date = as.Date(NA),
          staleness_days = NA_integer_, na_ratio = NA_real_,
          status = "NO_SERIES_COL"
        )
      } else {
        per <- dt[, .(n = .N,
                      min_date = min(get(date_col)),
                      max_date = max(get(date_col))),
                   by = Series]
        per[, staleness_days := as.integer(Sys.Date() - max_date)]
        per[, status := fifelse(staleness_days <= 7, "OK",
                         fifelse(staleness_days <= 30, "STALE", "VERY_STALE"))]
        per[, tag := "long"]; per[, path := info$path]; per[, exists := TRUE]
        per[, na_ratio := 0]  # long format: NA already filtered on fetch
        setnames(per, "Series", "series")
        setcolorder(per, c("tag", "path", "exists", "series", "n",
                           "min_date", "max_date", "staleness_days",
                           "na_ratio", "status"))
        out_rows[["long_per_series"]] <- per
      }
    }
  }

  result <- rbindlist(out_rows, fill = TRUE)
  setorder(result, tag, series)

  # Print summary
  cat("\n[fred_robust_health] Summary\n")
  cat(rep("=", 60), sep = ""); cat("\n")
  wide_part <- result[tag == "wide" & !is.na(series)]
  if (nrow(wide_part) > 0) {
    cat(sprintf("Wide: %d series | OK=%d STALE=%d VERY_STALE=%d ALL_NA=%d\n",
                nrow(wide_part),
                sum(wide_part$status == "OK"),
                sum(wide_part$status == "STALE"),
                sum(wide_part$status == "VERY_STALE"),
                sum(wide_part$status == "ALL_NA")))
    stale_list <- wide_part[status != "OK", series]
    if (length(stale_list) > 0) {
      cat("  stale/missing:", paste(stale_list, collapse = ", "), "\n")
    }
  }
  long_part <- result[tag == "long" & !is.na(series)]
  if (nrow(long_part) > 0) {
    cat(sprintf("Long: %d series | OK=%d STALE=%d VERY_STALE=%d\n",
                nrow(long_part),
                sum(long_part$status == "OK"),
                sum(long_part$status == "STALE"),
                sum(long_part$status == "VERY_STALE")))
  }
  cat(rep("=", 60), sep = ""); cat("\n\n")

  invisible(result)
}

#==============================================================================
# 3. fred_robust_wide_load — wide format read (with long fallback)
#==============================================================================
fred_robust_wide_load <- function(prefer_wide = TRUE) {
  if (prefer_wide && file.exists(FRED_ROBUST_WIDE)) {
    dt <- as.data.table(read_parquet(FRED_ROBUST_WIDE))
    date_col <- intersect(c("Date", "date"), names(dt))[1]
    if (!is.na(date_col)) {
      dt[, (date_col) := as.Date(get(date_col))]
      if (date_col != "Date") setnames(dt, date_col, "Date")
    }
    setorder(dt, Date)
    return(dt)
  }

  # Fallback: reshape long → wide on the fly
  if (file.exists(FRED_ROBUST_LONG)) {
    long_dt <- as.data.table(read_parquet(FRED_ROBUST_LONG))
    date_col <- intersect(c("Date", "date"), names(long_dt))[1]
    if (!is.na(date_col) && date_col != "Date") setnames(long_dt, date_col, "Date")
    long_dt[, Date := as.Date(Date)]
    if (!"Series" %in% names(long_dt) || !"Value" %in% names(long_dt)) {
      stop("[fred_robust_wide_load] long parquet missing Series/Value cols")
    }
    wide_dt <- dcast(long_dt, Date ~ Series, value.var = "Value")
    setorder(wide_dt, Date)
    return(wide_dt)
  }

  stop("[fred_robust_wide_load] neither wide nor long parquet exists. ",
       "Run fred_robust_fetch_all() first.")
}

cat("[fred_robust] Loaded. Functions:",
    "fred_robust_fetch_all(), fred_robust_health(), fred_robust_wide_load()\n")
