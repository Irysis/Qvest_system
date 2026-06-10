#==============================================================================
# Memory Logger — 방법론 비교실험 자동 기록 시스템
# Version: 1.0.0
#
# methodology_memory.md에 실험 결과를 자동으로 구조화 기록.
# L-code 자동 부여, 섹션 자동 분류, MEMORY.md 카운트 자동 갱신.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(stringr)
})

# ─── Paths ───────────────────────────────────────────────────────────────────
MEMORY_DIR <- local({
  .c <- c(file.path(Sys.getenv("USERPROFILE", unset = "C:/Users/99922"), ".claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory"),  # Windows OneDrive canonical (2026-06-10)
          file.path(Sys.getenv("USERPROFILE", unset = "C:/Users/99922"), ".claude/projects/G--Quant-Module-Moltbot/memory"),                        # legacy G: era (2026-06-04)
          "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory")
  .e <- .c[dir.exists(.c)]; if (length(.e)) .e[1] else .c[1]
})
# v3.0: auto-generated 결과는 experiment_log.md로 분리.
# methodology_memory.md는 Q-Lead 수동 승격만 허용.
METHODOLOGY_PATH <- file.path(MEMORY_DIR, "experiment_log.md")
MEMORY_MD_PATH   <- file.path(MEMORY_DIR, "MEMORY.md")

# ─── Category → Section Header Mapping ──────────────────────────────────────
CATEGORY_MAP <- list(
  factor_combination = "## [팩터 결합]",
  neutralization     = "## [섹터/시총 중립화]",
  weighting          = "## [포트폴리오 가중]",
  rebalancing        = "## [리밸런싱/실행]",
  regime             = "## [레짐 조건부]",
  gate               = "## [실패 패턴 요약]",
  beta               = "## [Kalman Filter Beta]",
  vol_target         = "## [Vol Targeting]",
  multi_sleeve       = "## [Multi-Sleeve 탐색 실험]",
  ensemble           = "## [앙상블 실험 결과]",
  diversity          = "## [_deleted_FreshIdea-Inspired Gates]"
)

# ─── get_next_l_code() ──────────────────────────────────────────────────────
#' Scan methodology_memory.md for the highest L-XXX number and return next.
#' @return integer: next available L-code number
get_next_l_code <- function() {
  if (!file.exists(METHODOLOGY_PATH)) {
    message("[memory_logger] methodology_memory.md not found at: ", METHODOLOGY_PATH)
    return(1L)
  }

  lines <- readLines(METHODOLOGY_PATH, warn = FALSE)

  # Match patterns like L-01, L-123, L-276 etc.
  # Covers: **L-XXX**, L-XXX:, L-XXX , L-XXX(
  l_matches <- str_extract_all(lines, "L-\\d+")
  all_codes <- unlist(l_matches)

  if (length(all_codes) == 0L) return(1L)

  nums <- as.integer(str_extract(all_codes, "\\d+"))
  max_num <- max(nums, na.rm = TRUE)

  return(max_num + 1L)
}

# ─── log_experiment() ───────────────────────────────────────────────────────
#' Log an experiment result to methodology_memory.md
#'
#' @param category   character: one of names(CATEGORY_MAP)
#' @param title      character: experiment title
#' @param comparison character: what was compared (A vs B)
#' @param conditions character: experimental conditions
#' @param result     character: outcome summary
#' @param rationale  character: theoretical basis / citation
#' @param scope      character: where this finding applies
#' @param strategy   character: strategy code(s) e.g. "STR_XXX"
#' @param l_codes    character vector: lesson text lines (L-code numbers auto-assigned)
#' @return invisible(TRUE) on success
log_experiment <- function(category,
                           title,
                           comparison = "N/A",
                           conditions = "N/A",
                           result,
                           rationale = "auto-generated",
                           scope = "N/A",
                           strategy,
                           l_codes = character(0)) {

  # ── Validate category (with dynamic fallback) ──
  if (!category %in% names(CATEGORY_MAP)) {
    CATEGORY_MAP[[category]] <<- sprintf("## [%s]", category)
    message(sprintf("[memory_logger] New category '%s' auto-registered as '%s'",
                    category, CATEGORY_MAP[[category]]))
  }

  if (!file.exists(METHODOLOGY_PATH)) {
    stop("[memory_logger] methodology_memory.md not found: ", METHODOLOGY_PATH)
  }

  # ── Get next L-code number ──
  next_l <- get_next_l_code()

  # ── Build L-code lines ──
  l_lines <- character(0)
  if (length(l_codes) > 0L) {
    l_nums <- seq(next_l, next_l + length(l_codes) - 1L)
    l_lines <- sprintf("- **L-%d**: %s", l_nums, l_codes)
  }

  # ── Build experiment block ──
  entry_lines <- c(
    "",
    sprintf("### 실험: %s", title),
    sprintf("- 비교: %s", comparison),
    sprintf("- 조건: %s", conditions),
    sprintf("- 결과: %s", result),
    sprintf("- 근거: %s", rationale),
    sprintf("- 적용 범위: %s", scope),
    sprintf("- 전략 사례: %s", strategy),
    l_lines,
    ""
  )

  # ── Find target section and insert ──
  lines <- readLines(METHODOLOGY_PATH, warn = FALSE)
  section_header <- CATEGORY_MAP[[category]]

  # Find the line index of the target section header
  header_idx <- which(lines == section_header)

  if (length(header_idx) == 0L) {
    # Section header not found — try partial match
    header_idx <- grep(fixed(section_header), lines, fixed = TRUE)
  }

  if (length(header_idx) == 0L) {
    # Still not found — append to end of file
    message(sprintf("[memory_logger] Section '%s' not found. Appending to end.", section_header))
    lines <- c(lines, "", section_header, entry_lines)
  } else {
    # Find the NEXT section header (## [) to know where this section ends
    header_line <- header_idx[1]
    remaining <- lines[(header_line + 1):length(lines)]
    next_section_rel <- grep("^## \\[", remaining)

    if (length(next_section_rel) == 0L) {
      # Last section — append at end
      insert_pos <- length(lines)
    } else {
      # Insert just before the next section header
      insert_pos <- header_line + next_section_rel[1] - 1L
    }

    # Insert the entry
    lines <- c(
      lines[1:insert_pos],
      entry_lines,
      if (insert_pos < length(lines)) lines[(insert_pos + 1):length(lines)] else character(0)
    )
  }

  # ── Write back ──
  writeLines(lines, METHODOLOGY_PATH)

  n_lessons <- length(l_codes)
  l_range <- if (n_lessons > 0L) {
    sprintf("L-%d~L-%d", next_l, next_l + n_lessons - 1L)
  } else {
    "(no L-codes)"
  }

  message(sprintf("[memory_logger] Logged: '%s' → %s [%s, %d lessons: %s]",
                  title, section_header, category, n_lessons, l_range))

  # ── L-code JSON parallel storage (qepm/memory/lessons/) ──
  QEPM_LESSONS_DIR <- NULL
  if (exists("PROJECT_ROOT")) {
    QEPM_LESSONS_DIR <- file.path(PROJECT_ROOT, "qepm", "memory", "lessons")
  } else {
    # Fallback: derive from MEMORY_DIR
    candidate <- file.path(dirname(dirname(MEMORY_DIR)),
                           "Quant_Module_Moltbot", "qepm", "memory", "lessons")
    if (dir.exists(dirname(candidate))) QEPM_LESSONS_DIR <- candidate
  }

  if (!is.null(QEPM_LESSONS_DIR) && length(l_codes) > 0) {
    if (!dir.exists(QEPM_LESSONS_DIR)) {
      dir.create(QEPM_LESSONS_DIR, recursive = TRUE, showWarnings = FALSE)
    }
    for (k in seq_along(l_codes)) {
      l_num <- next_l + k - 1L
      lesson_json <- list(
        l_code     = sprintf("L-%d", l_num),
        category   = category,
        title      = title,
        comparison = comparison,
        conditions = conditions,
        result     = result,
        rationale  = rationale,
        scope      = scope,
        strategy   = strategy,
        lesson_text = l_codes[k],
        timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
      )
      json_path <- file.path(QEPM_LESSONS_DIR, sprintf("L-%03d.json", l_num))
      tryCatch(
        jsonlite::write_json(lesson_json, json_path, auto_unbox = TRUE, pretty = TRUE),
        error = function(e) {
          message(sprintf("[memory_logger] L-code JSON save failed for L-%d: %s",
                          l_num, conditionMessage(e)))
        }
      )
    }
    message(sprintf("[memory_logger] L-code JSON: %d files saved to %s",
                    length(l_codes), QEPM_LESSONS_DIR))
  }

  invisible(TRUE)
}

# ─── update_memory_summary() ────────────────────────────────────────────────
#' Update MEMORY.md with current L-code count from methodology_memory.md
#' PATCH 2026-04-29 (L-247): active + archive split 후 정합화
#' methodology_active.md + methodology_archive.md + experiment_log.md 합산.
#' @return invisible(list(max_l, count))
update_memory_summary <- function() {
  if (!file.exists(MEMORY_MD_PATH)) {
    stop("[memory_logger] MEMORY.md not found: ", MEMORY_MD_PATH)
  }

  # ── Count unique L-codes from active + archive + experiment_log ──
  paths_to_scan <- c(
    file.path(MEMORY_DIR, "methodology_active.md"),
    file.path(MEMORY_DIR, "methodology_archive.md"),
    file.path(MEMORY_DIR, "methodology_memory.md"),
    file.path(MEMORY_DIR, "experiment_log.md")
  )
  paths_to_scan <- paths_to_scan[file.exists(paths_to_scan)]

  if (length(paths_to_scan) == 0) {
    message("[memory_logger] No methodology file found in: ", MEMORY_DIR)
    return(invisible(list(max_l = 0L, count = 0L)))
  }

  all_codes <- unique(unlist(lapply(paths_to_scan, function(p) {
    lines <- readLines(p, warn = FALSE)
    unlist(str_extract_all(lines, "L-\\d+"))
  })))

  if (length(all_codes) == 0) {
    message("[memory_logger] No L-codes found across: ", paste(basename(paths_to_scan), collapse=", "))
    return(invisible(list(max_l = 0L, count = 0L)))
  }

  all_nums  <- sort(as.integer(str_extract(all_codes, "\\d+")))
  max_l  <- max(all_nums, na.rm = TRUE)
  count  <- length(all_nums)

  # ── Update MEMORY.md ──
  mem_lines <- readLines(MEMORY_MD_PATH, warn = FALSE)

  # Pattern: "L-01~L-XXX, NNN개" (in various contexts)
  # Update methodology_memory.md reference line
  pattern_ref <- "L-01~L-\\d+,\\s*\\d+개"
  replacement_ref <- sprintf("L-01~L-%d, %d개", max_l, count)

  updated <- FALSE
  for (i in seq_along(mem_lines)) {
    if (grepl(pattern_ref, mem_lines[i])) {
      mem_lines[i] <- str_replace(mem_lines[i], pattern_ref, replacement_ref)
      updated <- TRUE
    }
  }

  if (updated) {
    writeLines(mem_lines, MEMORY_MD_PATH)
    message(sprintf("[memory_logger] MEMORY.md updated: L-01~L-%d, %d개 기록", max_l, count))
  } else {
    message("[memory_logger] MEMORY.md: L-code count pattern not found, no update made")
  }

  invisible(list(max_l = max_l, count = count))
}

# ─── Self-Test ──────────────────────────────────────────────────────────────
if (interactive() || identical(Sys.getenv("MEMORY_LOGGER_TEST"), "1")) {
  message("=== memory_logger.R self-test ===")
  next_l <- get_next_l_code()
  message(sprintf("Next available L-code: L-%d", next_l))

  summary <- update_memory_summary()
  message(sprintf("Current count: L-01~L-%d, %d unique codes",
                  summary$max_l, summary$count))
  message("=== self-test complete ===")
}

## ── Integration Pattern ──────────────────────────────────────────────────────
## After hurdle gate in run_all.R, add:
##   source(file.path(MEMORY_DIR, "memory_logger.R"))
##   log_experiment(
##     category = "gate",
##     title = "DaysInv gate on STR_XXX",
##     comparison = "DaysInv top10% vs no gate",
##     conditions = "RA framework, Monthly+BZ, EW, N=30",
##     result = sprintf("CAGR %.1f%%, MDD %.1f%%, Score %.1f",
##                      perf$cagr * 100, perf$mdd * 100, perf$score),
##     rationale = "Gaur et al. (2005) inventory efficiency",
##     scope = "RA + Monthly+BZ strategies only",
##     strategy = "STR_XXX",
##     l_codes = c("New gate DaysInv top10% → CAGR +X%p, MDD -Y%p vs no gate")
##   )
##
## To update MEMORY.md counts after logging:
##   update_memory_summary()
##
## To check next L-code without logging:
##   next_l <- get_next_l_code()
##
## Category reference:
##   "factor_combination" → ## [팩터 결합]
##   "neutralization"     → ## [섹터/시총 중립화]
##   "weighting"          → ## [포트폴리오 가중]
##   "rebalancing"        → ## [리밸런싱/실행]
##   "regime"             → ## [레짐 조건부]
##   "gate"               → ## [실패 패턴 요약]
##   "beta"               → ## [Kalman Filter Beta]
##   "vol_target"         → ## [Vol Targeting]
##   "multi_sleeve"       → ## [Multi-Sleeve 탐색 실험]
##   "ensemble"           → ## [앙상블 실험 결과]
##   "diversity"          → ## [_deleted_FreshIdea-Inspired Gates]
## ─────────────────────────────────────────────────────────────────────────────
