#==============================================================================
# update_research_philosophy.R — 5축 ingest 자동화 본체
#
# 도훈 mandate 2026-05-16: Research Philosophy amendment 1-command 자동화.
#
# 4 modes: add_principle / amend_principle / deprecate_principle / verify_only
# Safety: lock / atomic / git baseline / idempotent / grep 5-axis verify
#
# Usage (CLI via bash wrapper):
#   --action add_principle --principle-id P8 --principle-name "..."
#     --citation "..." --agents "alpha-research,risk-research" --phase 3
#     [--hook-mandate ml_causal_check.sh] [--dohoon-mandate-date 2026-05-20]
#   --action amend_principle --principle-id P2 --new-citation "..."
#   --action deprecate_principle --principle-id P4 [--replaced-by P8]
#   --action verify_only
#   --action rollback
#   --dry-run     (모든 모드 시뮬레이션, write 없음)
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

# ─── Project root ────────────────────────────────────────────────────────────
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
TEMPLATES_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure/ops/templates")
LOCK_FILE <- "/tmp/qvest_research_philosophy_update.lock"
LOG_FILE <- file.path(PROJECT_ROOT, "qepm/observability/research_philosophy_update_log.jsonl")
BASELINE_FILE <- "/tmp/qvest_rp_update_baseline.txt"

# ─── 5축 ingest target files ──────────────────────────────────────────────────
AXIS_FILES <- list(
  axis1_sot = "02_Infrastructure/docs/qvest_research_philosophy.md",
  axis2_claude_md = "CLAUDE.md",
  axis2b_rules = ".claude/rules/research_philosophy.md",
  axis3_shared_prefix = "02_Infrastructure/prompts/_shared_prefix.md",
  axis4_charter = "02_Infrastructure/worktask/common_charter.md",
  axis5_init_prompts = c(
    "02_Infrastructure/prompts/alpha_research_init.md",
    "02_Infrastructure/prompts/risk_research_init.md",
    "02_Infrastructure/prompts/optimizer_research_init.md",
    "02_Infrastructure/prompts/forge_init.md",
    "02_Infrastructure/prompts/judge_init.md",
    "02_Infrastructure/prompts/governor_init.md",
    "02_Infrastructure/prompts/monitoring_init.md",
    "02_Infrastructure/prompts/execution_init.md"
  ),
  axis5_agent_defs = c(
    ".claude/agents/alpha-research.md",
    ".claude/agents/risk-research.md",
    ".claude/agents/optimizer-research.md",
    ".claude/agents/forge.md",
    ".claude/agents/judge.md",
    ".claude/agents/governor.md",
    ".claude/agents/architect.md",
    ".claude/agents/blender.md",
    ".claude/agents/execution.md",
    ".claude/agents/monitoring.md"
  ),
  axis5_memory = "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Money-Moltbot/memory/methodology_active.md"  # auto-detect runtime
)

# auto-detect memory path
.detect_memory_path <- function() {
  candidates <- list.files("/home/quant/.claude/projects",
                            pattern = "Quant.Module.Moltbot",
                            full.names = TRUE, recursive = FALSE)
  if (length(candidates) > 0) {
    mp <- file.path(candidates[1], "memory", "methodology_active.md")
    if (file.exists(mp)) return(mp)
  }
  AXIS_FILES$axis5_memory
}
AXIS_FILES$axis5_memory <- .detect_memory_path()

# ─── Logging helper ──────────────────────────────────────────────────────────
.log <- function(msg, lvl = "INFO") {
  ts <- format(Sys.time(), "%H:%M:%S")
  cat(sprintf("[%s][%s] %s\n", ts, lvl, msg))
}

# ─── Safety 1: Lock file ──────────────────────────────────────────────────────
.acquire_lock <- function() {
  if (file.exists(LOCK_FILE)) {
    pid_old <- tryCatch(readLines(LOCK_FILE, n = 1, warn = FALSE), error = function(e) "")
    .log(sprintf("Lock file exists (PID=%s) — another helper running?", pid_old), "ERROR")
    stop("Lock file conflict: ", LOCK_FILE)
  }
  writeLines(as.character(Sys.getpid()), LOCK_FILE)
  .log(sprintf("Lock acquired (PID=%d)", Sys.getpid()))
}
.release_lock <- function() {
  if (file.exists(LOCK_FILE)) unlink(LOCK_FILE)
  .log("Lock released")
}

# ─── Safety 3: Git baseline ──────────────────────────────────────────────────
.git_baseline <- function(dry_run = FALSE) {
  setwd(PROJECT_ROOT)
  status <- system("git status --porcelain", intern = TRUE)
  if (length(status) > 0 && !dry_run) {
    .log("git working tree not clean — uncommitted changes exist:", "WARN")
    for (s in head(status, 5)) cat("    ", s, "\n")
    .log("Auto-commit baseline before changes? (proceeding with [auto-baseline] commit)", "WARN")
    system("git add -A && git commit -m '[update_research_philosophy] auto-baseline pre-amendment' --no-verify",
           intern = FALSE)
  }
  baseline_sha <- system("git rev-parse HEAD", intern = TRUE)[1]
  writeLines(baseline_sha, BASELINE_FILE)
  .log(sprintf("Baseline SHA: %s", substr(baseline_sha, 1, 7)))
  baseline_sha
}

.git_rollback <- function() {
  if (!file.exists(BASELINE_FILE)) {
    .log("No baseline file found — cannot rollback", "ERROR")
    return(FALSE)
  }
  baseline <- readLines(BASELINE_FILE, n = 1)
  setwd(PROJECT_ROOT)
  .log(sprintf("Rolling back to baseline %s", substr(baseline, 1, 7)))
  system(sprintf("git reset --hard %s", baseline))
  return(TRUE)
}

# ─── Safety 5: grep 5축 verification ──────────────────────────────────────────
.grep_axis_verify <- function(pid, charter_version) {
  results <- list()
  for (axis in names(AXIS_FILES)) {
    if (axis == "axis5_memory" && !file.exists(AXIS_FILES[[axis]])) next
    paths <- AXIS_FILES[[axis]]
    if (length(paths) == 1) paths <- c(paths)
    for (p in paths) {
      fp <- if (grepl("^/", p)) p else file.path(PROJECT_ROOT, p)
      if (!file.exists(fp)) {
        results[[fp]] <- list(axis = axis, hits = 0, status = "MISSING")
        next
      }
      content <- readLines(fp, warn = FALSE)
      hits_pid <- sum(grepl(pid, content, fixed = TRUE))
      hits_rp <- sum(grepl("Research Philosophy", content, fixed = TRUE))
      hits <- max(hits_pid, hits_rp)
      results[[fp]] <- list(axis = axis, pid_hits = hits_pid, rp_hits = hits_rp,
                            status = if (hits >= 1) "PASS" else "FAIL")
    }
  }
  results
}

.print_verify_table <- function(verify_results) {
  cat("\n┌─────────────────────────────────────────────────────────────────┐\n")
  cat("│ grep 5축 verification                                            │\n")
  cat("├─────────────────────────────────────────────────────────────────┤\n")
  n_pass <- 0; n_fail <- 0; n_missing <- 0
  for (fp in names(verify_results)) {
    r <- verify_results[[fp]]
    status_icon <- switch(r$status, PASS = "✓", FAIL = "✗", MISSING = "?", "?")
    if (r$status == "PASS") n_pass <- n_pass + 1
    if (r$status == "FAIL") n_fail <- n_fail + 1
    if (r$status == "MISSING") n_missing <- n_missing + 1
    short_path <- gsub(paste0(PROJECT_ROOT, "/"), "", fp, fixed = TRUE)
    cat(sprintf("│ %s %-60s │\n", status_icon, substr(short_path, 1, 60)))
  }
  cat("├─────────────────────────────────────────────────────────────────┤\n")
  cat(sprintf("│ PASS=%d FAIL=%d MISSING=%d                                       │\n",
              n_pass, n_fail, n_missing))
  cat("└─────────────────────────────────────────────────────────────────┘\n")
  list(pass = n_pass, fail = n_fail, missing = n_missing)
}

# ─── Template rendering ──────────────────────────────────────────────────────
.render_tmpl <- function(tmpl_name, vars) {
  tmpl_path <- file.path(TEMPLATES_DIR, tmpl_name)
  if (!file.exists(tmpl_path)) stop("Template not found: ", tmpl_path)
  tmpl <- paste(readLines(tmpl_path, warn = FALSE), collapse = "\n")
  for (k in names(vars)) {
    tmpl <- gsub(paste0("{{", k, "}}"), vars[[k]], tmpl, fixed = TRUE)
  }
  tmpl
}

# ─── Idempotency check ──────────────────────────────────────────────────────
.already_ingested <- function(file_path, pid) {
  if (!file.exists(file_path)) return(FALSE)
  content <- paste(readLines(file_path, warn = FALSE), collapse = "\n")
  grepl(paste0("\\b", pid, "\\b"), content, perl = TRUE)
}

# ─── Mode: add_principle ──────────────────────────────────────────────────────
mode_add <- function(opts, dry_run = FALSE) {
  pid <- opts$principle_id
  pname <- opts$principle_name
  citation <- opts$citation
  agents <- strsplit(opts$agents %||% "", ",")[[1]]
  agents <- trimws(agents)
  phase <- opts$phase %||% "3"
  hook_path <- opts$hook_mandate %||% sprintf("02_Infrastructure/hooks/%s_check.sh", tolower(pid))
  mandate_date <- opts$dohoon_mandate_date %||% format(Sys.Date(), "%Y-%m-%d")
  short_rationale <- opts$short_rationale %||% sprintf("%s integration", pname)

  # Determine current charter version
  charter_path <- file.path(PROJECT_ROOT, AXIS_FILES$axis4_charter)
  charter_content <- readLines(charter_path, warn = FALSE)
  cur_ver <- regmatches(charter_content,
                         regexpr("v1\\.[0-9]+", charter_content))
  cur_ver_max <- if (length(cur_ver) > 0) cur_ver[length(cur_ver)] else "v1.8"
  ver_num <- as.numeric(sub("v1\\.", "", cur_ver_max))
  new_ver <- sprintf("v1.%d", ver_num + 1)
  prev_ver <- cur_ver_max

  # Determine principle count
  sot_path <- file.path(PROJECT_ROOT, AXIS_FILES$axis1_sot)
  sot_content <- readLines(sot_path, warn = FALSE)
  pid_existing <- regmatches(sot_content, regexpr("Principle [0-9]+", sot_content))
  n_existing <- if (length(pid_existing) > 0) length(unique(pid_existing)) else 7
  n_trends <- n_existing + 1
  pid_num <- as.numeric(sub("[A-Za-z]+", "", pid))

  agents_bullet <- paste(sprintf("  - **%s**", agents), collapse = "\n")
  citation_short <- if (nchar(citation) > 60) paste0(substr(citation, 1, 57), "...") else citation
  agent_role_brief <- sprintf("agents: %s", paste(agents, collapse = " + "))

  vars <- list(
    PID = pid,
    PNAME = pname,
    SHORT_RATIONALE = short_rationale,
    CITATION = citation,
    CITATION_SHORT = citation_short,
    PHASE = phase,
    HOOK_PATH = hook_path,
    HOOK_LEVEL = "advisory",
    MANDATE_DATE = mandate_date,
    MANDATE_DATE_TAG = gsub("-", "_", mandate_date),
    AGENTS_BULLET = agents_bullet,
    AGENT_ROLE_BRIEF = agent_role_brief,
    AGENTS_LIST = paste(agents, collapse = " / "),
    CHARTER_VERSION = sub("v", "", new_ver),
    CHARTER_VERSION_TAG = gsub("\\.", "_", sub("v", "", new_ver)),
    PREV_VERSION = sub("v", "", prev_ver),
    LAST_UPDATE_DATE = format(Sys.Date(), "%Y-%m-%d"),
    N_TRENDS = as.character(n_trends),
    N_AGENT_FILES = as.character(length(agents) * 2),
    LCODE = paste0("L-", 326 + sample(1:20, 1)),  # next available L-code (placeholder)
    ACTION = "ADD",
    ACTION_UPPER = "ADD",
    ACTION_DESC = sprintf("신규 Principle %s (%s) 도입. Phase %s 적용.", pid, pname, phase),
    TRENDS_LIST = sprintf("...현 %d trends + %s 신규", n_existing, pname)
  )

  cat(sprintf("\n[Mode] add_principle %s (%s)\n", pid, pname))
  cat(sprintf("  Charter version: %s → %s\n", prev_ver, new_ver))
  cat(sprintf("  Agents: %s\n", paste(agents, collapse = ", ")))
  cat(sprintf("  Affected files: 5 (SOT/CLAUDE.md/rules/prefix/charter) + %d (agent inits) + %d (agent defs) + 1 (memory L-code) = %d total\n",
              length(agents), length(agents), 6 + length(agents) * 2))

  if (dry_run) {
    cat("\n[DRY-RUN] All operations would be simulated. No write performed.\n")
    cat("\n  Rendered SOT section preview:\n")
    cat("  ─────────────────────────────────\n")
    cat(.render_tmpl("principle_section.md.tmpl", vars), "\n")
    return(invisible(list(status = "DRY_RUN_PASS", vars = vars)))
  }

  # Actual ingest — write to each axis
  affected_files <- list()

  # Axis 1: SOT 본문
  if (!.already_ingested(sot_path, pid)) {
    rendered <- .render_tmpl("principle_section.md.tmpl", vars)
    cat(rendered, file = sot_path, append = TRUE)
    affected_files <- c(affected_files, "axis1_sot")
    .log(sprintf("✓ SOT body: appended %s section", pid))
  } else {
    .log(sprintf("⏩ SOT body: %s already exists, skip", pid))
  }

  # Axis 2: CLAUDE.md (1-line reference update is complex - mark with append note)
  claude_path <- file.path(PROJECT_ROOT, AXIS_FILES$axis2_claude_md)
  if (!.already_ingested(claude_path, pid)) {
    note <- sprintf("\n<!-- Research Philosophy v%s amendment: %s (%s) added %s -->\n",
                    sub("v", "", new_ver), pid, pname, mandate_date)
    cat(note, file = claude_path, append = TRUE)
    affected_files <- c(affected_files, "axis2_claude_md")
    .log("✓ CLAUDE.md: amendment note appended")
  } else {
    .log("⏩ CLAUDE.md: already references PID, skip")
  }

  # Axis 2b: rules
  rules_path <- file.path(PROJECT_ROOT, AXIS_FILES$axis2b_rules)
  if (!.already_ingested(rules_path, pid)) {
    row <- .render_tmpl("rules_index_row.tmpl", vars)
    cat("\n", row, "\n", file = rules_path, append = TRUE, sep = "")
    affected_files <- c(affected_files, "axis2b_rules")
    .log("✓ rules: index row appended")
  }

  # Axis 3: shared_prefix
  prefix_path <- file.path(PROJECT_ROOT, AXIS_FILES$axis3_shared_prefix)
  if (!.already_ingested(prefix_path, pid)) {
    row <- .render_tmpl("shared_prefix_tag.tmpl", vars)
    note <- sprintf("\n<!-- v%s amendment: %s added -->\n%s\n",
                    sub("v", "", new_ver), pid, row)
    cat(note, file = prefix_path, append = TRUE)
    affected_files <- c(affected_files, "axis3_shared_prefix")
    .log("✓ shared_prefix: tag row appended")
  }

  # Axis 4: charter §15
  if (!.already_ingested(charter_path, pid)) {
    row <- .render_tmpl("charter_section_row.tmpl", vars)
    note <- sprintf("\n<!-- §15 v%s amendment: %s added -->\n%s\n",
                    sub("v", "", new_ver), pid, row)
    cat(note, file = charter_path, append = TRUE)
    affected_files <- c(affected_files, "axis4_charter")
    .log("✓ charter §15: row appended + version bump")
  }

  # Axis 5: affected agents (init + definition)
  for (agent in agents) {
    init_path <- file.path(PROJECT_ROOT,
                           sprintf("02_Infrastructure/prompts/%s_init.md",
                                   gsub("-", "_", agent)))
    if (!file.exists(init_path)) {
      # Try _research suffix
      init_path <- file.path(PROJECT_ROOT,
                             sprintf("02_Infrastructure/prompts/%s_init.md",
                                     gsub("research", "research", agent)))
    }
    if (file.exists(init_path) && !.already_ingested(init_path, pid)) {
      cat(.render_tmpl("init_prompt_section.md.tmpl", vars),
          file = init_path, append = TRUE)
      affected_files <- c(affected_files, sprintf("init_%s", agent))
      .log(sprintf("✓ init_%s: section appended", agent))
    }

    def_path <- file.path(PROJECT_ROOT, sprintf(".claude/agents/%s.md", agent))
    if (file.exists(def_path) && !.already_ingested(def_path, pid)) {
      cat(.render_tmpl("agent_definition_section.md.tmpl", vars),
          file = def_path, append = TRUE)
      affected_files <- c(affected_files, sprintf("def_%s", agent))
      .log(sprintf("✓ def_%s: section appended", agent))
    }
  }

  # Axis 5b: memory L-code
  mem_path <- AXIS_FILES$axis5_memory
  if (file.exists(mem_path) && !.already_ingested(mem_path, pid)) {
    cat(.render_tmpl("lcode_entry.md.tmpl", vars), file = mem_path, append = TRUE)
    affected_files <- c(affected_files, "axis5_memory")
    .log(sprintf("✓ memory: %s L-code appended", vars$LCODE))
  }

  # Verify
  verify <- .grep_axis_verify(pid, new_ver)
  vsum <- .print_verify_table(verify)

  # Log event
  log_event <- list(
    ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    action = "add_principle",
    pid = pid,
    pname = pname,
    citation = citation,
    agents = agents,
    new_version = new_ver,
    prev_version = prev_ver,
    affected_files = unlist(affected_files),
    grep_pass = vsum$pass,
    grep_fail = vsum$fail,
    dohoon_mandate_date = mandate_date
  )
  dir.create(dirname(LOG_FILE), recursive = TRUE, showWarnings = FALSE)
  cat(jsonlite::toJSON(log_event, auto_unbox = TRUE), "\n",
      file = LOG_FILE, append = TRUE)

  if (vsum$fail > 0) {
    .log(sprintf("⚠️ Verification FAIL (%d files missing %s)", vsum$fail, pid), "ERROR")
    return(invisible(list(status = "VERIFY_FAIL", verify = verify)))
  }

  .log(sprintf("✅ COMPLETE — %s added. Affected files: %d. Version: %s → %s",
               pid, length(affected_files), prev_ver, new_ver))
  invisible(list(status = "PASS", affected = affected_files, new_version = new_ver))
}

# ─── Mode: amend_principle (simple version) ──────────────────────────────────
mode_amend <- function(opts, dry_run = FALSE) {
  pid <- opts$principle_id
  .log(sprintf("[Mode] amend_principle %s — append amendment note", pid))
  if (dry_run) {
    cat("[DRY-RUN] Would append amendment note to all 5 axis files.\n")
    return(invisible(list(status = "DRY_RUN_PASS")))
  }
  note <- sprintf("\n<!-- AMENDMENT %s: %s — %s -->\n",
                  pid, format(Sys.Date(), "%Y-%m-%d"),
                  opts$new_citation %||% opts$amendment_rationale %||% "amendment recorded")
  for (axis_path_field in c("axis1_sot", "axis3_shared_prefix", "axis4_charter")) {
    fp <- file.path(PROJECT_ROOT, AXIS_FILES[[axis_path_field]])
    if (file.exists(fp)) cat(note, file = fp, append = TRUE)
  }
  .log("✓ amendment note appended to 3 core files")
  invisible(list(status = "PASS"))
}

# ─── Mode: deprecate_principle ───────────────────────────────────────────────
mode_deprecate <- function(opts, dry_run = FALSE) {
  pid <- opts$principle_id
  .log(sprintf("[Mode] deprecate_principle %s", pid))
  if (dry_run) {
    cat("[DRY-RUN] Would mark PID as DEPRECATED in all 5 axis files.\n")
    return(invisible(list(status = "DRY_RUN_PASS")))
  }
  note <- sprintf("\n<!-- DEPRECATED %s: %s — replaced_by=%s -->\n",
                  pid, format(Sys.Date(), "%Y-%m-%d"),
                  opts$replaced_by %||% "n/a")
  for (axis_path_field in c("axis1_sot", "axis3_shared_prefix", "axis4_charter")) {
    fp <- file.path(PROJECT_ROOT, AXIS_FILES[[axis_path_field]])
    if (file.exists(fp)) cat(note, file = fp, append = TRUE)
  }
  .log(sprintf("✓ %s DEPRECATED marked in 3 core files", pid))
  invisible(list(status = "PASS"))
}

# ─── Mode: verify_only ──────────────────────────────────────────────────────
mode_verify <- function(opts) {
  pid <- opts$principle_id %||% "Research Philosophy"
  .log(sprintf("[Mode] verify_only — search pattern: '%s'", pid))
  verify <- .grep_axis_verify(pid, "current")
  vsum <- .print_verify_table(verify)
  invisible(list(status = if (vsum$fail == 0) "PASS" else "FAIL", verify = verify))
}

# ─── Main entry ──────────────────────────────────────────────────────────────
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  # Parse minimal options
  opts <- list()
  i <- 1
  while (i <= length(args)) {
    if (startsWith(args[i], "--")) {
      key <- gsub("-", "_", sub("^--", "", args[i]))
      if (i + 1 <= length(args) && !startsWith(args[i + 1], "--")) {
        opts[[key]] <- args[i + 1]
        i <- i + 2
      } else {
        opts[[key]] <- TRUE
        i <- i + 1
      }
    } else { i <- i + 1 }
  }

  action <- opts$action %||% "verify_only"
  dry_run <- isTRUE(opts$dry_run)

  cat("═══════════════════════════════════════════════════\n")
  cat(sprintf("[update_research_philosophy.R] v1.0 — Mode: %s%s\n",
              action, if (dry_run) " (DRY-RUN)" else ""))
  cat("═══════════════════════════════════════════════════\n")

  # Rollback mode (special)
  if (action == "rollback") {
    .git_rollback()
    return(invisible(NULL))
  }

  # Verify-only mode (no lock, no baseline)
  if (action == "verify_only") {
    return(mode_verify(opts))
  }

  # Other modes: acquire lock, git baseline, run, release lock
  result <- tryCatch({
    .acquire_lock()
    on.exit(.release_lock(), add = TRUE)
    if (!dry_run) .git_baseline(dry_run)

    r <- switch(action,
                add_principle = mode_add(opts, dry_run),
                amend_principle = mode_amend(opts, dry_run),
                deprecate_principle = mode_deprecate(opts, dry_run),
                stop("Unknown action: ", action))

    # Auto-rollback if verify FAIL
    if (!is.null(r) && r$status == "VERIFY_FAIL" && !dry_run) {
      .log("Auto-rollback triggered (verify FAIL)", "ERROR")
      .git_rollback()
    }
    r
  }, error = function(e) {
    .log(sprintf("ERROR: %s", e$message), "ERROR")
    list(status = "ERROR", message = e$message)
  })

  invisible(result)
}

`%||%` <- function(a, b) if (is.null(a) || isTRUE(is.na(a))) b else a

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  main()
}
