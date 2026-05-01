#==============================================================================
# wt_timeline.R — v7.0 Sprint 6 WT Timeline Builder
#
# Per-WT timeline 산출 (events.jsonl + governance_log.json + cert files +
# codex_critic_response + status.json 통합).
#
# Output: qepm/observability/timelines/wt_{WT_ID}.json
#
# Fields:
#   - events[]      — governance_log + ledger entries chronological
#   - phases[]      — start/end/duration per phase
#   - certs[]       — 5 cert × ISSUED/NOT_ISSUED/REVOKED + reason
#   - failures[]    — codex stance + critical_concerns + abort reason
#   - retry_count   — codex round REVISE 후 재산출 횟수
#   - artifact_lineage[] — alpha → risk → optimizer → forge chain
#
# Usage:
#   Rscript wt_timeline.R --wt-id WT-D20260501_003
#   Rscript wt_timeline.R --rebuild-active-book   # bootstrap 자동
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
if (PROJ_ROOT == "" || !dir.exists(PROJ_ROOT)) {
  PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

OBSERVABILITY_DIR <- file.path(PROJ_ROOT, "qepm/observability")
LEDGER_PATH <- file.path(OBSERVABILITY_DIR, "events.jsonl")
TIMELINES_DIR <- file.path(OBSERVABILITY_DIR, "timelines")
WT_ROOT <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")

dir.create(TIMELINES_DIR, recursive = TRUE, showWarnings = FALSE)

build_wt_timeline <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  if (!dir.exists(wt_dir)) {
    return(list(error = sprintf("WT dir not found: %s", wt_id)))
  }

  # 1. events from governance_log + events.jsonl
  events <- list()

  gov_path <- file.path(wt_dir, "governance_log.json")
  if (file.exists(gov_path)) {
    gov <- tryCatch(fromJSON(gov_path, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (!is.null(gov$events)) {
      for (e in gov$events) {
        events[[length(events) + 1]] <- list(
          source = "governance_log",
          timestamp = e$timestamp %||% "",
          agent = e$agent %||% "",
          action = e$action %||% "",
          summary = e$summary %||% ""
        )
      }
    }
  }

  if (file.exists(LEDGER_PATH)) {
    ledger_lines <- tryCatch(readLines(LEDGER_PATH, warn = FALSE),
                              error = function(e) character())
    for (line in ledger_lines) {
      if (!nzchar(line)) next
      entry <- tryCatch(fromJSON(line, simplifyVector = FALSE),
                         error = function(e) NULL)
      if (is.null(entry)) next
      if (!is.null(entry$wt_id) && entry$wt_id == wt_id) {
        events[[length(events) + 1]] <- list(
          source = "events_jsonl",
          timestamp = entry$timestamp %||% "",
          agent = entry$agent_role %||% "",
          action = entry$event_type %||% "",
          summary = sprintf("hook=%s decision=%s",
                            entry$hook_name %||% "?", entry$decision %||% "?")
        )
      }
    }
  }

  # Sort events by timestamp
  if (length(events) > 0) {
    ts <- sapply(events, function(x) x$timestamp)
    events <- events[order(ts)]
  }

  # 2. phases — extract PHASE_ADVANCE entries
  phases <- list()
  current_start <- NA
  current_phase <- NA
  for (e in events) {
    if (grepl("PHASE_ADVANCE", e$action %||% "")) {
      if (!is.na(current_phase)) {
        phases[[length(phases) + 1]] <- list(
          phase = current_phase,
          start = current_start,
          end = e$timestamp,
          duration_seconds = NA  # parse 비용 회피
        )
      }
      current_start <- e$timestamp
      m <- regmatches(e$summary, regexec("-> (\\w+)", e$summary))
      if (length(m[[1]]) >= 2) current_phase <- m[[1]][2]
    }
  }
  if (!is.na(current_phase)) {
    phases[[length(phases) + 1]] <- list(
      phase = current_phase, start = current_start, end = NA,
      duration_seconds = NA
    )
  }

  # 3. certs — 5 cert status
  cert_types <- c("alpha_discovery", "sr_provenance", "schedule_fidelity",
                  "forge_package_validated", "governor_concord")
  certs <- list()
  for (ct in cert_types) {
    cert_path <- file.path(wt_dir, sprintf("%s_certificate.json", ct))
    if (file.exists(cert_path)) {
      cert_data <- tryCatch(fromJSON(cert_path, simplifyVector = FALSE),
                             error = function(e) NULL)
      if (!is.null(cert_data)) {
        certs[[ct]] <- list(
          status = if (isTRUE(cert_data$issued)) "ISSUED" else "NOT_ISSUED",
          issued_at = cert_data$issued_at %||% "",
          reason = if (isTRUE(cert_data$issued)) "all_pass" else
                    (cert_data$non_issuance_reason %||% "")
        )
      }
    } else {
      certs[[ct]] <- list(status = "ABSENT", issued_at = "", reason = "")
    }
  }

  # 4. failures — codex stance + critical_concerns
  failures <- list()
  codex_files <- list.files(wt_dir, pattern = "^codex_critic_response_",
                             full.names = TRUE)
  for (cf in codex_files) {
    cresp <- tryCatch(fromJSON(cf, simplifyVector = FALSE),
                       error = function(e) NULL)
    if (is.null(cresp)) next
    if (!is.null(cresp$stance) && cresp$stance != "APPROVE") {
      n_high <- sum(sapply(cresp$critical_concerns %||% list(),
                            function(c) identical(c$severity, "HIGH")))
      failures[[length(failures) + 1]] <- list(
        source = basename(cf),
        agent_role = cresp$agent_role %||% "",
        stance = cresp$stance,
        critical_concerns_count = length(cresp$critical_concerns %||% list()),
        high_count = n_high,
        weakest_assumption = cresp$weakest_assumption %||% ""
      )
    }
  }

  # 5. retry_count — count REVISE events
  retry_count <- sum(sapply(events, function(e) {
    grepl("REVISE|REVISION", e$action %||% "")
  }))

  # 6. artifact_lineage — alpha → risk → opt → forge → judge → governor
  lineage <- list()
  artifact_files <- list(
    list(role = "alpha", file = "alpha_package.json"),
    list(role = "risk", file = "risk_package.json"),
    list(role = "optimizer", file = "optimization_package.json"),
    list(role = "forge", file = "forge_package.json"),
    list(role = "judge", file = "judge_verdict.json"),
    list(role = "governor", file = "governor_admission.json")
  )
  for (af in artifact_files) {
    fp <- file.path(wt_dir, af$file)
    if (file.exists(fp)) {
      info <- file.info(fp)
      lineage[[length(lineage) + 1]] <- list(
        role = af$role,
        artifact_path = file.path("qepm/mailbox/worktask", wt_id, af$file),
        generated_at = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
        size_bytes = info$size
      )
    }
  }

  status_path <- file.path(wt_dir, "status.json")
  current_status <- if (file.exists(status_path)) {
    tryCatch(fromJSON(status_path, simplifyVector = TRUE),
             error = function(e) NULL)
  } else NULL

  list(
    wt_id = wt_id,
    timeline_built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    current_phase = current_status$current_phase %||% "UNKNOWN",
    events = events,
    phases = phases,
    certs = certs,
    failures = failures,
    retry_count = retry_count,
    artifact_lineage = lineage
  )
}

save_wt_timeline <- function(wt_id) {
  tl <- build_wt_timeline(wt_id)
  if (!is.null(tl$error)) {
    cat(sprintf("[ERROR] %s\n", tl$error))
    return(invisible(FALSE))
  }
  out <- file.path(TIMELINES_DIR, sprintf("wt_%s.json", wt_id))
  write_json(tl, out, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[OK] timeline saved: %s (events=%d phases=%d certs=%d failures=%d)\n",
              out, length(tl$events), length(tl$phases),
              length(tl$certs), length(tl$failures)))
  invisible(TRUE)
}

rebuild_active_book <- function() {
  bs_path <- file.path(PROJ_ROOT, "qepm/mailbox/governor/book_state.json")
  if (!file.exists(bs_path)) {
    cat("[INFO] book_state not found — skip\n")
    return(invisible(FALSE))
  }
  bs <- tryCatch(fromJSON(bs_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs) || length(bs$admitted_ids %||% list()) == 0) {
    cat("[INFO] no admitted_ids — skip\n")
    return(invisible(FALSE))
  }
  count <- 0
  for (str_id in bs$admitted_ids) {
    str_id <- as.character(str_id)
    # find lineage WT_id
    candidate_dirs <- list.dirs(WT_ROOT, full.names = FALSE, recursive = FALSE)
    for (wt in candidate_dirs) {
      ga <- file.path(WT_ROOT, wt, "governor_admission.json")
      if (!file.exists(ga)) next
      ga_data <- tryCatch(fromJSON(ga, simplifyVector = FALSE),
                           error = function(e) NULL)
      if (is.null(ga_data)) next
      if (identical(ga_data$str_id, str_id) ||
          str_id %in% names(ga_data$allocation_decided %||% list())) {
        save_wt_timeline(wt)
        count <- count + 1
      }
    }
  }
  cat(sprintf("[OK] rebuilt %d active book timelines\n", count))
  invisible(count)
}

# CLI
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0) {
    cat("Usage: Rscript wt_timeline.R --wt-id WT-XXX | --rebuild-active-book\n")
    quit(status = 1)
  }
  if ("--rebuild-active-book" %in% args) {
    rebuild_active_book()
  } else {
    idx <- which(args == "--wt-id")
    if (length(idx) == 1 && idx + 1 <= length(args)) {
      save_wt_timeline(args[idx + 1])
    } else {
      cat("[ERROR] missing --wt-id <ID>\n")
      quit(status = 1)
    }
  }
}
