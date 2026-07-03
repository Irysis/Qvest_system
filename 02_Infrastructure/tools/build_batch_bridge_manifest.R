#!/usr/bin/env Rscript
# Build a cross-mode manifest for a strategy-pool execution batch.
# The manifest is intentionally conservative: alpha-search artifacts are recorded
# for QEPM traceability, and factor-rotation borrowing remains grade-agnostic.
# FR admission is RCMA/contract-floor driven, not overall-grade driven: an F
# overall module can still be useful in one regime. This manifest therefore
# marks borrow candidates by execution/provenance/PIT status only; contract-backed
# freezing and RCMA decide actual FR consumption later.

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

args <- commandArgs(trailingOnly = TRUE)
plan_csv <- if (length(args) >= 1L) args[[1]] else {
  Sys.glob("stage_artifacts/batch_434/*/execution_plan.csv") |>
    sort(decreasing = TRUE) |>
    head(1L)
}
if (!length(plan_csv) || !file.exists(plan_csv)) stop("execution_plan.csv not found")

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
plan_csv <- normalizePath(plan_csv, winslash = "/", mustWork = TRUE)
batch_dir <- dirname(plan_csv)
log_dir <- file.path(batch_dir, "logs")

safe_chr <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  x <- x[[1]]
  if (is.null(x) || length(x) == 0L || is.na(x)) NA_character_ else as.character(x)
}

safe_num <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_real_)
  suppressWarnings(as.numeric(x[[1]]))
}

safe_lgl <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA)
  as.logical(x[[1]])
}

safe_collapse <- function(x, sep = " | ") {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  x <- as.character(x)
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) NA_character_ else paste(unique(x), collapse = sep)
}

read_json_safe <- function(path) {
  if (is.na(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
}

read_statuses <- function() {
  files <- Sys.glob(file.path(log_dir, "*.status"))
  if (!length(files)) return(data.frame())
  rows <- lapply(files, function(f) {
    x <- tryCatch(read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
    if (is.null(x) || !nrow(x)) return(NULL)
    x$status_file <- normalizePath(f, winslash = "/", mustWork = FALSE)
    x
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  out$finished_sort <- suppressWarnings(as.POSIXct(out$finished, tz = Sys.timezone()))
  out <- out[order(out$item_id, out$finished_sort, na.last = TRUE), , drop = FALSE]
  out <- out[!duplicated(out$item_id, fromLast = TRUE), , drop = FALSE]
  out$finished_sort <- NULL
  out
}

find_log_path <- function(item_id, statuses) {
  hit <- statuses[statuses$item_id == item_id, , drop = FALSE]
  if (nrow(hit) && nzchar(hit$log_path[[1]]) && file.exists(hit$log_path[[1]])) {
    return(normalizePath(hit$log_path[[1]], winslash = "/", mustWork = FALSE))
  }
  safe_id <- gsub("[^A-Za-z0-9_.-]", "_", item_id)
  files <- Sys.glob(file.path(log_dir, sprintf("*_%s.log", safe_id)))
  if (length(files)) normalizePath(files[[length(files)]], winslash = "/", mustWork = FALSE) else NA_character_
}

extract_first <- function(lines, pattern) {
  m <- regmatches(lines, regexpr(pattern, lines, perl = TRUE))
  m <- m[nzchar(m)]
  if (length(m)) tail(unique(m), 1L) else NA_character_
}

parse_log <- function(log_path) {
  empty <- list(
    alpha_dir = NA_character_,
    hurdle_path = NA_character_,
    auth_path = NA_character_,
    bt_result_path = NA_character_,
    strategy_manifest_path = NA_character_,
    module_id = NA_character_,
    module_quarantine_path = NA_character_,
    fmt_codes = NA_character_,
    telegram_loaded = FALSE,
    telegram_attempted = FALSE,
    qepm_commit_seen = FALSE
  )
  if (is.na(log_path) || !file.exists(log_path)) return(empty)
  lines <- tryCatch(readLines(log_path, warn = FALSE), error = function(e) character())
  if (!length(lines)) return(empty)

  rel_alpha <- extract_first(lines, "stage_artifacts/alpha_search/[0-9_]+")
  alpha_dir <- if (!is.na(rel_alpha)) file.path(root, rel_alpha) else NA_character_
  hurdle_path <- if (!is.na(alpha_dir)) file.path(alpha_dir, "hurdle_result.json") else NA_character_
  auth_path <- if (!is.na(alpha_dir)) file.path(alpha_dir, "authoritative_remeasure.json") else NA_character_
  bt_result_path <- if (!is.na(alpha_dir)) file.path(alpha_dir, "bt_result.rds") else NA_character_
  strategy_manifest_path <- if (!is.na(alpha_dir)) file.path(alpha_dir, "strategy_manifest.json") else NA_character_

  module_id <- extract_first(lines, "STR_AS_[0-9_]+")
  module_quarantine_path <- if (!is.na(module_id)) {
    file.path(root, "stage_artifacts", "module_quarantine", module_id, "sim_result.rds")
  } else {
    NA_character_
  }
  fmt_line <- tail(grep("FMT.*자동판정", lines, value = TRUE), 1L)
  fmt_codes <- if (length(fmt_line)) {
    codes <- regmatches(fmt_line, gregexpr("FMT-[0-9]+", fmt_line, perl = TRUE))[[1]]
    if (length(codes)) paste(unique(codes), collapse = ";") else NA_character_
  } else {
    NA_character_
  }

  list(
    alpha_dir = if (!is.na(alpha_dir)) normalizePath(alpha_dir, winslash = "/", mustWork = FALSE) else NA_character_,
    hurdle_path = if (file.exists(hurdle_path)) normalizePath(hurdle_path, winslash = "/", mustWork = FALSE) else NA_character_,
    auth_path = if (file.exists(auth_path)) normalizePath(auth_path, winslash = "/", mustWork = FALSE) else NA_character_,
    bt_result_path = if (file.exists(bt_result_path)) normalizePath(bt_result_path, winslash = "/", mustWork = FALSE) else NA_character_,
    strategy_manifest_path = if (file.exists(strategy_manifest_path)) normalizePath(strategy_manifest_path, winslash = "/", mustWork = FALSE) else NA_character_,
    module_id = module_id,
    module_quarantine_path = if (file.exists(module_quarantine_path)) normalizePath(module_quarantine_path, winslash = "/", mustWork = FALSE) else NA_character_,
    fmt_codes = fmt_codes,
    telegram_loaded = any(grepl("\\[telegram_notify\\] Loaded", lines)),
    telegram_attempted = any(grepl("telegram|tg_", lines, ignore.case = TRUE)),
    qepm_commit_seen = any(grepl("QEPM auto-commit completed|\\[hybrid_commit\\]", lines))
  )
}

inspect_return_series <- function(bt_result_path, module_sim_path) {
  empty <- list(
    status = "MISSING",
    source = NA_character_,
    n_obs = NA_integer_,
    start_date = NA_character_,
    end_date = NA_character_,
    post2008_obs = NA_integer_,
    post2008_gap = NA,
    path = NA_character_
  )
  inspect_table <- function(d, date_col, ret_col, source, path) {
    if (is.null(d) || !is.data.frame(d) || !all(c(date_col, ret_col) %in% names(d))) {
      return(empty)
    }
    dd <- suppressWarnings(as.Date(d[[date_col]]))
    rr <- suppressWarnings(as.numeric(d[[ret_col]]))
    ok <- !is.na(dd) & is.finite(rr)
    if (!any(ok)) {
      out <- empty
      out$status <- "NO_VALID_RETURNS"
      out$source <- source
      out$path <- path
      return(out)
    }
    n_post2008 <- sum(dd[ok] >= as.Date("2008-01-01"), na.rm = TRUE)
    list(
      status = "OK",
      source = source,
      n_obs = sum(ok),
      start_date = as.character(min(dd[ok], na.rm = TRUE)),
      end_date = as.character(max(dd[ok], na.rm = TRUE)),
      post2008_obs = n_post2008,
      post2008_gap = isTRUE(n_post2008 < 100L),
      path = path
    )
  }

  if (!is.na(bt_result_path) && nzchar(bt_result_path) && file.exists(bt_result_path)) {
    bt <- tryCatch(readRDS(bt_result_path), error = function(e) NULL)
    if (!is.null(bt) && !is.null(bt$period_returns)) {
      out <- inspect_table(as.data.frame(bt$period_returns), "date", "ret_net",
                           "bt_result.period_returns", bt_result_path)
      if (identical(out$status, "OK")) return(out)
    }
  }
  if (!is.na(module_sim_path) && nzchar(module_sim_path) && file.exists(module_sim_path)) {
    sim <- tryCatch(readRDS(module_sim_path), error = function(e) NULL)
    if (!is.null(sim) && !is.null(sim$DAILY_NAV_DT)) {
      out <- inspect_table(as.data.frame(sim$DAILY_NAV_DT), "Date", "Strategy_Ret",
                           "module_sim.DAILY_NAV_DT", module_sim_path)
      if (!identical(out$status, "MISSING")) return(out)
    }
  }
  empty
}

cross_mode_status <- function(row, exit_code, fail_reasons, alpha_dir) {
  mq <- row$mapping_quality %||% "UNKNOWN"
  ec <- row$execution_class %||% "UNKNOWN"
  if (is.na(exit_code)) {
    return(switch(ec,
      BUILD_THEN_RUN = "BUILD_REQUIRED",
      DIAGNOSTIC_BUILD_THEN_RUN = "DIAGNOSTIC_BUILD_REQUIRED",
      ML_BUILD_THEN_RUN = "ML_REQUIRED",
      DATA_FIRST = "DATA_REQUIRED",
      LOW_PRIORITY_RUN = "LOW_PRIORITY_NOT_RUN",
      MISSING_BASE_CODE = "MISSING_BASE_CODE",
      "READY_NOT_RUN"
    ))
  }
  if (!identical(as.integer(exit_code), 0L)) return("EXECUTION_FAILED")
  if (is.na(alpha_dir) || !nzchar(alpha_dir)) return("QEPM_RECORDED_NO_ALPHA_ARTIFACT")
  if (!is.na(fail_reasons) && grepl("PIT violation", fail_reasons, ignore.case = TRUE)) {
    return("QEPM_RECORDED_PIT_BLOCKED")
  }
  if (identical(mq, "PROXY_SPEC_MISMATCH")) return("FR_PROXY_BORROW_CANDIDATE_NEEDS_CONTRACT")
  if (identical(mq, "BASE_SIGNAL_ONLY")) return("FR_BASE_SIGNAL_CANDIDATE_NEEDS_CONTRACT")
  "FR_BORROW_CANDIDATE_NEEDS_CONTRACT"
}

plan <- read.csv(plan_csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
if (!"mapping_quality" %in% names(plan)) plan$mapping_quality <- "UNKNOWN_LEGACY_PLAN"
if (!"mapping_notes" %in% names(plan)) plan$mapping_notes <- plan$reason %||% NA_character_

statuses <- read_statuses()
rows <- vector("list", nrow(plan))

for (i in seq_len(nrow(plan))) {
  p <- plan[i, , drop = FALSE]
  item_id <- p$item_id[[1]]
  st <- statuses[statuses$item_id == item_id, , drop = FALSE]
  exit_code <- if (nrow(st)) suppressWarnings(as.integer(st$exit_code[[1]])) else NA_integer_
  log_path <- find_log_path(item_id, statuses)
  parsed <- parse_log(log_path)
  hurdle <- read_json_safe(parsed$hurdle_path)
  auth <- read_json_safe(parsed$auth_path)
  strategy_manifest <- read_json_safe(parsed$strategy_manifest_path)

  grade <- safe_chr(hurdle$grade)
  pass <- safe_lgl(hurdle$pass)
  hard_fail <- safe_lgl(hurdle$hard_fail)
  metrics <- hurdle$metrics %||% list()
  dd <- hurdle$drawdown_profile %||% hurdle$score_breakdown$mdd %||% list()
  screening <- hurdle$screening %||% list()

  auth_grade <- safe_chr(auth$essence_grade)
  auth_hard_fail <- safe_lgl(auth$hard_fail)
  auth_metric_type <- safe_chr(auth$metric_type)
  f_grade_reasons <- safe_collapse(strategy_manifest$verdict$f_grade_reasons)
  if (is.na(f_grade_reasons) && identical(grade, "F")) {
    fallback <- character(0)
    fr <- hurdle$fail_reasons %||% character(0)
    if (is.list(fr)) fr <- unlist(fr, use.names = FALSE)
    fr <- as.character(fr)
    fr <- fr[!is.na(fr) & nzchar(fr)]
    if (length(fr)) fallback <- c(fallback, paste0("게이트 사유: ", fr))
    if (!is.na(parsed$fmt_codes)) fallback <- c(fallback, paste0("FMT 자동판정: ", parsed$fmt_codes))
    if (!length(fallback)) fallback <- "F등급이나 상세 사유 명세 없음"
    f_grade_reasons <- safe_collapse(fallback)
  }

  qepm_mode_status <- if (!is.na(exit_code) && identical(exit_code, 0L) && !is.na(parsed$alpha_dir)) {
    if (identical(p$mapping_quality[[1]], "PROXY_SPEC_MISMATCH")) {
      "RECORDED_PROXY"
    } else if (identical(p$mapping_quality[[1]], "BASE_SIGNAL_ONLY")) {
      "RECORDED_BASE_SIGNAL"
    } else {
      "RECORDED_ALPHA_SEARCH"
    }
  } else if (!is.na(exit_code) && !identical(exit_code, 0L)) {
    "EXECUTION_FAILED"
  } else {
    "NOT_EXECUTED"
  }

  fail_reasons <- safe_chr(hurdle$fail_reasons)
  factor_rotation_status <- cross_mode_status(p, exit_code, fail_reasons, parsed$alpha_dir)
  ret_series <- inspect_return_series(parsed$bt_result_path, parsed$module_quarantine_path)
  if (!is.na(exit_code) && identical(as.integer(exit_code), 0L) &&
      !is.na(parsed$alpha_dir) && nzchar(parsed$alpha_dir) &&
      (!identical(ret_series$status, "OK") || isTRUE(ret_series$post2008_gap))) {
    factor_rotation_status <- "FR_RETURN_SERIES_GAP"
  }

  rows[[i]] <- data.frame(
    item_id = item_id,
    title = p$title[[1]],
    status = p$status[[1]],
    execution_class = p$execution_class[[1]],
    mapping_quality = p$mapping_quality[[1]],
    mapping_notes = p$mapping_notes[[1]],
    exit_code = exit_code,
    elapsed_sec = if (nrow(st)) suppressWarnings(as.numeric(st$elapsed_sec[[1]])) else NA_real_,
    alpha_search_dir = parsed$alpha_dir,
    hurdle_result_json = parsed$hurdle_path,
    strategy_manifest_json = parsed$strategy_manifest_path,
    authoritative_remeasure_json = parsed$auth_path,
    bt_result_rds = parsed$bt_result_path,
    module_id = parsed$module_id,
    module_quarantine_rds = parsed$module_quarantine_path,
    return_series_status = ret_series$status,
    return_series_source = ret_series$source,
    return_series_n_obs = ret_series$n_obs,
    return_series_start = ret_series$start_date,
    return_series_end = ret_series$end_date,
    return_series_post2008_obs = ret_series$post2008_obs,
    return_series_post2008_gap = ret_series$post2008_gap,
    return_series_path = ret_series$path,
    batch_result_rds = {
      rp <- file.path(batch_dir, sprintf("%s_result.rds", item_id))
      if (file.exists(rp)) normalizePath(rp, winslash = "/", mustWork = FALSE) else NA_character_
    },
    qepm_mode_status = qepm_mode_status,
    factor_rotation_status = factor_rotation_status,
    grade = grade,
    pass = pass,
    hard_fail = hard_fail,
    fail_reasons = fail_reasons,
    f_grade_reasons = f_grade_reasons,
    score = safe_num(hurdle$total_score),
    cagr_pct = safe_num(metrics$CAGR),
    sharpe = safe_num(metrics$Sharpe),
    ir = safe_num(metrics$IR),
    mdd_pct = safe_num(metrics$MDD),
    turnover_ann_pct = safe_num(metrics$Turnover_Ann),
    severe45_count = safe_num(dd$severe45_count),
    severe55_count = safe_num(dd$severe55_count),
    severe45_max_days = safe_num(dd$severe45_max_days),
    drawdown_tail_review = safe_lgl(screening$drawdown_tail_review),
    screening_pass = safe_lgl(screening$screen_pass),
    screening_route = safe_chr(screening$screen_route),
    fmt_codes = parsed$fmt_codes,
    telegram_loaded = parsed$telegram_loaded,
    telegram_attempted = parsed$telegram_attempted,
    qepm_commit_seen = parsed$qepm_commit_seen,
    auth_metric_type = auth_metric_type,
    auth_grade = auth_grade,
    auth_hard_fail = auth_hard_fail,
    log_path = log_path,
    file = p$file[[1]],
    stringsAsFactors = FALSE
  )
}

manifest <- do.call(rbind, rows)
manifest_csv <- file.path(batch_dir, "cross_mode_bridge_manifest.csv")
write.csv(manifest, manifest_csv, row.names = FALSE, fileEncoding = "UTF-8")

count_lines <- function(x) {
  if (!length(x)) return(character())
  tab <- sort(table(x), decreasing = TRUE)
  sprintf("- %s: %d", names(tab), as.integer(tab))
}

summary_md <- file.path(batch_dir, "cross_mode_bridge_summary.md")
lines <- c(
  sprintf("# Cross-Mode Bridge Summary"),
  "",
  sprintf("- batch_dir: `%s`", batch_dir),
  sprintf("- plan_rows: %d", nrow(plan)),
  sprintf("- status_rows: %d", nrow(statuses)),
  sprintf("- manifest: `%s`", manifest_csv),
  "",
  "## Execution Classes",
  count_lines(manifest$execution_class),
  "",
  "## Mapping Quality",
  count_lines(manifest$mapping_quality),
  "",
  "## QEPM Mode Status",
  count_lines(manifest$qepm_mode_status),
  "",
  "## Factor Rotation Status",
  count_lines(manifest$factor_rotation_status),
  "",
  "## Return Series",
  count_lines(manifest$return_series_status),
  sprintf("- post-2008 gap flags: %d", sum(manifest$return_series_post2008_gap %in% TRUE, na.rm = TRUE)),
  "",
  "## Grades",
  count_lines(manifest$grade[!is.na(manifest$grade) & nzchar(manifest$grade)]),
  "",
  "## Notes",
  "- FR borrow-candidate statuses are grade-agnostic. Overall A/B/C/F is recorded for diagnostics only.",
  "- `BASE_SIGNAL_ONLY` and `PROXY_SPEC_MISMATCH` are allowed as borrow candidates only under their own identity, not as exact source-strategy equivalence.",
  "- Actual FR consumption still requires authoritative contract/freeze/hash registration outside alpha-search quarantine plus RCMA admission."
)
writeLines(lines, summary_md, useBytes = TRUE)

cat(sprintf("manifest=%s\n", manifest_csv))
cat(sprintf("summary=%s\n", summary_md))
cat(sprintf("rows=%d\n", nrow(manifest)))
print(sort(table(manifest$factor_rotation_status), decreasing = TRUE))
