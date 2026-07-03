#!/usr/bin/env Rscript
# Execute runnable rows from build_strategy_pool_execution_plan.R.
# This intentionally runs only rows with an explicit runnable_command.

suppressPackageStartupMessages({
  library(parallel)
})

args <- commandArgs(trailingOnly = TRUE)
ready_csv <- if (length(args) >= 1L) args[[1]] else {
  Sys.glob("stage_artifacts/batch_434/*/ready_commands.csv") |>
    sort(decreasing = TRUE) |>
    head(1L)
}
if (!length(ready_csv) || !file.exists(ready_csv)) stop("ready_commands.csv not found")

max_parallel <- as.integer(Sys.getenv("QVEST_BATCH_MAX_PARALLEL", "4"))
if (is.na(max_parallel) || max_parallel < 1L) max_parallel <- 1L

ready <- read.csv(ready_csv, stringsAsFactors = FALSE, na.strings = c("", "NA"))
ready <- ready[!is.na(ready$runnable_command) & nzchar(ready$runnable_command), , drop = FALSE]
if (!nrow(ready)) {
  cat("[ready-runner] no runnable rows\n")
  quit(status = 0L)
}

batch_dir <- dirname(normalizePath(ready_csv, winslash = "/", mustWork = TRUE))
log_dir <- file.path(batch_dir, "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

read_status_file <- function(path) {
  x <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (!is.null(x) && nrow(x)) x$status_file <- normalizePath(path, winslash = "/", mustWork = FALSE)
  x
}

latest_status_by_item <- function(status) {
  if (is.null(status) || !nrow(status)) return(status)
  status$exit_code <- suppressWarnings(as.integer(status$exit_code))
  status$finished_sort <- suppressWarnings(as.POSIXct(status$finished, tz = Sys.timezone()))
  status <- status[order(status$item_id, status$finished_sort, na.last = TRUE), , drop = FALSE]
  status <- status[!duplicated(status$item_id, fromLast = TRUE), , drop = FALSE]
  status$finished_sort <- NULL
  status
}

existing_status_files <- list.files(log_dir, pattern = "\\.status$", full.names = TRUE)
existing_status <- if (length(existing_status_files)) {
  do.call(rbind, Filter(Negate(is.null), lapply(existing_status_files, read_status_file)))
} else {
  NULL
}

completed_ids <- character(0)
if (!is.null(existing_status) && nrow(existing_status) > 0) {
  existing_status <- latest_status_by_item(existing_status)
  completed_ids <- unique(existing_status$item_id[existing_status$exit_code == 0L])
}

run_one <- function(i) {
  row <- ready[i, , drop = FALSE]
  id <- gsub("[^A-Za-z0-9_.-]", "_", row$item_id)
  log_path <- file.path(log_dir, sprintf("%03d_%s.log", i, id))
  status_path <- file.path(log_dir, sprintf("%03d_%s.status", i, id))
  started <- Sys.time()
  cmd <- sprintf(
    "cd %s && %s",
    shQuote(normalizePath(row$run_dir, winslash = "/", mustWork = FALSE)),
    row$runnable_command
  )
  cat(sprintf("[ready-runner] start %s | %s\n", row$item_id, row$execution_class))
  exit <- system2("bash", c("-lc", shQuote(cmd)), stdout = log_path, stderr = log_path)
  finished <- Sys.time()
  status <- data.frame(
    item_id = row$item_id,
    execution_class = row$execution_class,
    exit_code = exit,
    started = format(started, "%Y-%m-%d %H:%M:%S"),
    finished = format(finished, "%Y-%m-%d %H:%M:%S"),
    elapsed_sec = round(as.numeric(difftime(finished, started, units = "secs")), 1),
    log_path = log_path,
    stringsAsFactors = FALSE
  )
  write.csv(status, status_path, row.names = FALSE)
  cat(sprintf("[ready-runner] done %s | exit=%s | %.1fs\n",
              row$item_id, exit, status$elapsed_sec))
  status
}

idx_all <- seq_len(nrow(ready))
idx <- idx_all[!(ready$item_id %in% completed_ids)]
cat(sprintf("[ready-runner] rows=%d | already_done=%d | to_run=%d | max_parallel=%d\n",
            nrow(ready), length(setdiff(idx_all, idx)), length(idx), max_parallel))

all_status <- if (!is.null(existing_status) && nrow(existing_status) > 0) {
  split(existing_status, seq_len(nrow(existing_status)))
} else {
  list()
}

if (length(idx) > 0) {
  # Dynamic scheduling: fast NOT_BACKTESTED rows should immediately free a worker
  # for the next strategy instead of idling until the whole static chunk ends.
  res <- mclapply(
    idx,
    run_one,
    mc.cores = min(max_parallel, length(idx)),
    mc.preschedule = FALSE
  )
  all_status <- c(all_status, res)
}

summary <- latest_status_by_item(do.call(rbind, all_status))
summary_path <- file.path(batch_dir, "ready_run_summary.csv")
write.csv(summary, summary_path, row.names = FALSE)
cat(sprintf("[ready-runner] summary=%s\n", summary_path))
print(summary, row.names = FALSE)
