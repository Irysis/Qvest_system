# Sprint 4 AX-P3: Axiom Dashboard
# 현재 active/candidate/pending/deprecated 카운트 + 최근 승격/deprecate 이력.
# briefing_daily.R와 통합 가능.
#
# Usage: source("qepm/R/axiom_dashboard.R"); axiom_status()

suppressPackageStartupMessages({
  library(jsonlite)
})

.dash_root <- function() {
  cands <- c(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                             (length(a) == 1 && is.na(a))) b else a

axiom_status <- function(verbose = TRUE) {
  root <- .dash_root()
  ax_dir <- file.path(root, "qepm", "memory", "axioms")

  .count_dir <- function(sub) {
    d <- file.path(ax_dir, sub)
    if (!dir.exists(d)) return(0L)
    length(list.files(d, pattern = "\\.json$", recursive = TRUE))  # mode-local 포함
  }

  counts <- list(
    active     = .count_dir("active"),
    candidates = .count_dir("candidates"),
    review_log = .count_dir("review_log"),
    deprecated = .count_dir("deprecated")
  )

  # Active axiom 상세
  active_files <- list.files(file.path(ax_dir, "active"),
                              pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)
  active_detail <- list()
  for (f in active_files) {
    ax <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ax)) next
    active_detail[[length(active_detail) + 1L]] <- list(
      axiom_id = ax$axiom_id %||% ax$id %||% basename(f),
      statement = substr(ax$statement %||% ax$text %||% "", 1, 80),
      type = ax$type %||% ax$grade %||% "?",
      polarity = ax$polarity %||% "?",
      n_supporting = length(ax$supporting_l_codes %||% list()),
      promoted_at = ax$promotion$promoted_at %||% ax$metadata$promoted_date %||% "N/A",
      next_review = ax$promotion$next_review %||% "N/A"
    )
  }

  # 최근 승격 (promote_log 또는 mtime 기반)
  recent_events <- list()
  if (length(active_files) > 0L) {
    mts <- file.info(active_files)$mtime
    ord <- order(mts, decreasing = TRUE)
    for (i in head(ord, 3L)) {
      ax <- tryCatch(fromJSON(active_files[i], simplifyVector = FALSE),
                     error = function(e) NULL)
      if (is.null(ax)) next
      recent_events[[length(recent_events) + 1L]] <- list(
        event = "active",
        axiom_id = ax$axiom_id %||% ax$id %||% basename(active_files[i]),
        when = as.character(mts[i])
      )
    }
  }
  dep_files <- list.files(file.path(ax_dir, "deprecated"),
                          pattern = "\\.json$", full.names = TRUE)
  if (length(dep_files) > 0L) {
    mts <- file.info(dep_files)$mtime
    ord <- order(mts, decreasing = TRUE)
    for (i in head(ord, 2L)) {
      ax <- tryCatch(fromJSON(dep_files[i], simplifyVector = FALSE),
                     error = function(e) NULL)
      if (is.null(ax)) next
      recent_events[[length(recent_events) + 1L]] <- list(
        event = "deprecated",
        axiom_id = ax$axiom_id %||% ax$id %||% basename(dep_files[i]),
        when = as.character(mts[i])
      )
    }
  }

  result <- list(
    as_of = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    counts = counts,
    active = active_detail,
    recent_events = recent_events
  )

  if (verbose) {
    cat("=== Axiom Engine Status ===\n")
    cat(sprintf("Active: %d | Candidates: %d | Review_log: %d | Deprecated: %d\n",
                counts$active, counts$candidates, counts$review_log, counts$deprecated))
    cat("\n[Active Axioms]\n")
    for (a in active_detail) {
      cat(sprintf("  %s [%s/%s] supporting=%d next=%s\n    %s\n",
                  a$axiom_id, a$type, a$polarity, a$n_supporting,
                  a$next_review, a$statement))
    }
    cat("\n[Recent Events]\n")
    for (e in recent_events) {
      cat(sprintf("  [%s] %s @ %s\n", e$event, e$axiom_id, e$when))
    }
  }

  invisible(result)
}

cat("[axiom_dashboard] Loaded. Function: axiom_status()\n")
