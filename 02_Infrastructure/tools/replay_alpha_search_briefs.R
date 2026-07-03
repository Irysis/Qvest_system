#!/usr/bin/env Rscript

suppressWarnings(suppressMessages({
  library(jsonlite)
}))

find_root <- function() {
  candidates <- unique(c(
    Sys.getenv("CLAUDE_PROJECT_DIR", ""),
    Sys.getenv("QM_ROOT", ""),
    getwd(),
    normalizePath(file.path(getwd(), "../.."), winslash = "/", mustWork = FALSE)
  ))
  is_root <- function(p) nzchar(p) && file.exists(file.path(p, "02_Infrastructure", "config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  stop("[replay_alpha_search_briefs] project root not found")
}

root <- find_root()
setwd(root)
source(file.path(root, "02_Infrastructure", "alpha_search", "run_alpha_search.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

args <- commandArgs(trailingOnly = TRUE)
summary_path <- if (length(args) >= 1L && nzchar(args[[1]])) {
  args[[1]]
} else {
  file.path(root, "stage_artifacts", "batch_434", "20260612_rerun_turnover1100", "ready_run_summary.csv")
}
if (!file.exists(summary_path)) stop("ready_run_summary.csv not found: ", summary_path)

dry_run <- tolower(Sys.getenv("QVEST_TG_DRY_RUN", "false")) %in% c("1", "true", "yes")
replay_all <- tolower(Sys.getenv("QVEST_REPLAY_ALL_ALPHA_BRIEFS", "false")) %in% c("1", "true", "yes")

summary <- read.csv(summary_path, stringsAsFactors = FALSE)
extract_alpha_dir <- function(log_path) {
  if (!file.exists(log_path)) return(NA_character_)
  lines <- readLines(log_path, warn = FALSE)
  hits <- regmatches(lines, gregexpr("stage_artifacts/alpha_search/[0-9_]+", lines))
  hits <- unique(unlist(hits, use.names = FALSE))
  if (!length(hits)) return(NA_character_)
  file.path(root, tail(hits, 1L))
}
main_failed <- function(log_path) {
  if (!file.exists(log_path)) return(FALSE)
  lines <- readLines(log_path, warn = FALSE)
  any(grepl("\\[AlphaSearch\\]\\[TG\\] 발송 실패", lines))
}

rows <- summary[grepl("^ALPHA_", summary$item_id) & summary$exit_code == 0, , drop = FALSE]
rows$alpha_dir <- vapply(rows$log_path, extract_alpha_dir, character(1))
rows$main_failed <- vapply(rows$log_path, main_failed, logical(1))
rows$manifest_path <- file.path(rows$alpha_dir, "strategy_manifest.json")
rows <- rows[file.exists(rows$manifest_path), , drop = FALSE]
if (!replay_all) rows <- rows[rows$main_failed, , drop = FALSE]

if (!nrow(rows)) {
  cat("[replay_alpha_search_briefs] replay target 없음\n")
  quit(save = "no", status = 0)
}

send_one <- function(row) {
  manifest <- fromJSON(row$manifest_path, simplifyVector = FALSE)
  m <- manifest$metrics %||% list()
  f_reasons <- manifest$verdict$f_grade_reasons %||% character(0)
  if (is.list(f_reasons)) f_reasons <- unlist(f_reasons, use.names = FALSE)
  charts <- Filter(file.exists, file.path(row$alpha_dir, c("equity_curve.png", "annual_returns.png")))
  cat(sprintf("[replay_alpha_search_briefs] %s -> %s (%s)\n",
              row$item_id, manifest$strategy_name, manifest$verdict$grade %||% "?"))
  res <- .send_alpha_search_brief(
    strategy_name = manifest$strategy_name %||% row$item_id,
    strategy_idea = manifest$strategy_idea %||% "전략 아이디어 미기록",
    strategy_id = paste0(manifest$strategy_id %||% row$item_id, "_replay"),
    grade = manifest$verdict$grade %||% "unknown",
    score = as.numeric(manifest$verdict$score %||% NA_real_),
    m = m,
    sdef = list(),
    excess_cagr = as.numeric(manifest$excess_cagr_pct %||% NA_real_),
    charts = charts,
    universe = manifest$execution$universe %||% "ALL",
    universe_n = as.integer(manifest$execution$universe_n %||% NA_integer_),
    out_dir = row$alpha_dir,
    hg = list(),
    fmt = manifest$fmt %||% list(),
    auth = manifest$authoritative,
    f_reasons = f_reasons,
    dry_run = dry_run
  )
  data.frame(
    item_id = row$item_id,
    strategy_id = manifest$strategy_id %||% NA_character_,
    strategy_name = manifest$strategy_name %||% NA_character_,
    grade = manifest$verdict$grade %||% NA_character_,
    ok = isTRUE(res$ok),
    fallback = res$fallback %||% NA_character_,
    error = res$error %||% NA_character_,
    stringsAsFactors = FALSE
  )
}

out <- do.call(rbind, lapply(seq_len(nrow(rows)), function(i) send_one(rows[i, , drop = FALSE])))
out_path <- file.path(dirname(summary_path), "alpha_brief_replay_summary.csv")
write.csv(out, out_path, row.names = FALSE)
cat("[replay_alpha_search_briefs] summary=", out_path, "\n", sep = "")
print(out, row.names = FALSE)
