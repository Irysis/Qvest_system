#==============================================================================
# Preflight Memory Check — 전략 실행 전 기억 순환 자동 경고
#
# run_all.R 상단에서 호출. 콘솔에 2~5줄 핵심 경고만 출력.
# 토큰 소비 0 (R이 처리), Q-Lead 빠뜨림 방지용 안전장치.
#
# Usage:
#   source("02_Infrastructure/preflight_memory.R")
#   preflight_check("STR_978", family = "tp_gap_overlay")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

preflight_check <- function(strategy_name, family = NULL) {
  cat("\n--- Preflight Memory Check ---\n")
  warnings <- 0L

  # 1. Family fail streak
  if (!is.null(family)) {
    tracker_path <- file.path(PROJECT_ROOT, "qepm", "registry", "families.json")
    if (file.exists(tracker_path)) {
      fam_data <- tryCatch(fromJSON(tracker_path, simplifyVector = FALSE), error = function(e) list())
      for (fn in names(fam_data)) {
        if (grepl(family, fn, fixed = TRUE) || grepl(fn, family, fixed = TRUE)) {
          fs <- fam_data[[fn]]$fail_streak %||% 0L
          trials <- fam_data[[fn]]$total_trials %||% 0L
          pass <- fam_data[[fn]]$grade_a_count %||% 0L
          if (fs >= 3) {
            cat(sprintf("  [WARN] Family '%s': %d consecutive failures (total %d trials, %d pass)\n",
                        fn, fs, trials, pass))
            warnings <- warnings + 1L
          } else if (trials > 0) {
            cat(sprintf("  [INFO] Family '%s': %d trials, %d pass, streak %d\n",
                        fn, trials, pass, fs))
          }
        }
      }
    }
  }

  # 2. Similar strategy duplicate check (Grade A catalog)
  catalog_path <- file.path(PROJECT_ROOT, "04_Research", "grade_a_catalog.json")
  if (file.exists(catalog_path) && !is.null(family)) {
    catalog <- tryCatch(fromJSON(catalog_path, simplifyVector = FALSE), error = function(e) list())
    similar <- Filter(function(x) {
      sid <- x$strategy_id %||% ""
      grepl(family, sid, ignore.case = TRUE)
    }, catalog)
    if (length(similar) > 0) {
      best <- similar[[which.max(sapply(similar, function(x) as.numeric(x$sharpe %||% 0)))]]
      cat(sprintf("  [INFO] Similar Grade A exists: %s (SR %.3f, CAGR %.1f%%, Score %.1f)\n",
                  best$strategy_id, as.numeric(best$sharpe), as.numeric(best$cagr), as.numeric(best$score)))
    }
  }

  # 3. Recent L-codes (last 3 from methodology_memory.md)
  meth_path <- "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory/methodology_memory.md"
  if (file.exists(meth_path)) {
    lines <- readLines(meth_path, warn = FALSE)
    l_lines <- grep("^- \\*\\*L-\\d+\\*\\*:", lines, value = TRUE)
    if (length(l_lines) > 0) {
      recent <- tail(l_lines, 3)
      cat("  [RECENT L-codes]\n")
      for (ll in recent) {
        # Truncate to 120 chars
        cat(sprintf("    %s\n", substr(ll, 1, 120)))
      }
    }
  }

  # 4. Lookahead detection (C1~C9)
  la_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "validation", "lookahead_detector.R")
  if (file.exists(la_path)) {
    tryCatch({
      source(la_path, local = TRUE)
      # Try to find run_all.R in current working directory
      run_all_candidates <- c(
        file.path(getwd(), "run_all.R"),
        file.path(".", "run_all.R")
      )
      run_all_found <- Filter(file.exists, run_all_candidates)
      if (length(run_all_found) > 0) {
        la_result <- detect_lookahead(run_all_found[1], verbose = FALSE)
        if (!la_result$clean) {
          warnings <- warnings + length(la_result$violations)
          cat(sprintf("  [CRITICAL] %d lookahead violation(s) detected!\n",
                      length(la_result$violations)))
          for (v in la_result$violations) {
            cat(sprintf("    [%s] Line %d: %s\n", v$check, v$line, v$msg))
          }
          cat("  FIX ALL VIOLATIONS BEFORE RUNNING.\n")
        } else {
          cat("  [OK] Lookahead check: CLEAN\n")
        }
      }
    }, error = function(e) {
      cat(sprintf("  [WARN] Lookahead detector error: %s\n", e$message))
    })
  }

  if (warnings == 0) cat("  [OK] No warnings.\n")
  cat("--- End Preflight ---\n\n")
  invisible(warnings)
}
