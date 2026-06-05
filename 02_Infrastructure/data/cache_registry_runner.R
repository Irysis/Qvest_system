#==============================================================================
# cache_registry_runner.R — Registry-driven cache execution
#
# 7 QEPM Modern Trends + 도훈 mandate 2026-05-15 (영구 데이터 최신화 보호망)
#
# 4-Layer 영구 보호망 L2:
#   L1 (SOT): 02_Infrastructure/data/cache_registry.json
#   L2 (Auto-execution): 본 파일 — schedule별 registry iterate
#   L3 (Freshness logger): cache_freshness_audit.R
#   L4 (Hook enforcement): hooks/cache_registry_enforce.sh
#
# Usage:
#   source("02_Infrastructure/data/cache_registry_runner.R")
#   cache_registry_run(schedule = "daily")     # daily entries만
#   cache_registry_run(schedule = "weekly")    # daily + weekly
#   cache_registry_run(schedule = "monthly")   # daily + weekly + monthly
#   cache_registry_run(tier_max = 1)           # tier ≤ 1만 (critical only)
#   cache_registry_run(only = c(".cache/msm_daily_latest.parquet"))  # 특정 항목만
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

REGISTRY_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure/data/cache_registry.json")

cache_registry_load <- function() {
  if (!file.exists(REGISTRY_PATH)) stop("Registry not found: ", REGISTRY_PATH)
  r <- jsonlite::fromJSON(REGISTRY_PATH, simplifyVector = FALSE)
  r$caches
}

# ─── Topological sort by depends_on ───────────────────────────────────────────
.topo_sort <- function(caches) {
  path_to_idx <- setNames(seq_along(caches), sapply(caches, function(c) c$path))
  visited <- rep(FALSE, length(caches))
  order <- integer(0)

  visit <- function(i) {
    if (visited[i]) return(invisible())
    visited[i] <<- TRUE
    deps <- caches[[i]]$depends_on
    if (length(deps) > 0) {
      for (d in unlist(deps)) {
        if (d %in% names(path_to_idx)) visit(path_to_idx[[d]])
      }
    }
    order <<- c(order, i)
  }
  for (i in seq_along(caches)) visit(i)
  caches[order]
}

# ─── Schedule filter ──────────────────────────────────────────────────────────
.schedule_matches <- function(cache_sched, run_sched) {
  if (run_sched == "monthly") return(cache_sched %in% c("daily", "weekly", "monthly"))
  if (run_sched == "weekly")  return(cache_sched %in% c("daily", "weekly"))
  if (run_sched == "daily")   return(cache_sched == "daily")
  if (run_sched == "all")     return(TRUE)
  FALSE
}

# ─── Single cache execution ───────────────────────────────────────────────────
.execute_cache <- function(c, dry_run = FALSE) {
  producer_path <- file.path(PROJECT_ROOT, c$producer)
  entry_fn <- c$entry_fn
  args <- c$args
  path_rel <- c$path

  cat(sprintf("\n── [%s] tier=%d sched=%s\n", path_rel, c$tier, c$schedule))
  cat(sprintf("  Producer: %s\n  Entry: %s\n", c$producer, entry_fn))

  if (dry_run) {
    cat("  DRY-RUN — would execute\n")
    return(list(status = "DRY_RUN", path = path_rel))
  }

  if (!file.exists(producer_path)) {
    cat(sprintf("  ❌ FAIL — producer file not found: %s\n", producer_path))
    return(list(status = "FAIL_NO_PRODUCER", path = path_rel))
  }

  result <- tryCatch({
    if (entry_fn == "(source)") {
      # Top-level execution script
      source(producer_path)
    } else if (entry_fn == "(orchestrated)" || entry_fn == "(orchestrated_via_daily_refresh_steps_0_to_3)") {
      # Orchestrated upstream (RAWDATA etc.) — skip standalone execution
      cat("  ⏩ SKIP — orchestrated upstream (e.g., RAWDATA built in daily_refresh steps 0-3)\n")
      return(list(status = "SKIP_ORCHESTRATED", path = path_rel))
    } else {
      # Source script, then call entry_fn
      source(producer_path)
      fn <- get(entry_fn, envir = .GlobalEnv)
      if (!is.null(args) && length(args) > 0) {
        do.call(fn, args)
      } else {
        fn()
      }
    }
    list(status = "PASS", path = path_rel)
  }, error = function(e) {
    cat(sprintf("  ❌ FAIL — %s\n", e$message))
    list(status = "FAIL", path = path_rel, error = e$message)
  })

  if (result$status == "PASS") cat("  ✓ PASS\n")
  result
}

# ─── Main runner ──────────────────────────────────────────────────────────────
cache_registry_run <- function(schedule = "daily",
                                tier_max = 3L,
                                only = NULL,
                                dry_run = FALSE) {
  caches <- cache_registry_load()
  cat(sprintf("═══════════════════════════════════════════════════\n"))
  cat(sprintf("[cache_registry_runner] schedule=%s tier_max=%d (loaded %d caches)\n",
              schedule, tier_max, length(caches)))
  cat(sprintf("═══════════════════════════════════════════════════\n"))

  # Filter
  filtered <- Filter(function(c) {
    sched_ok <- .schedule_matches(c$schedule, schedule)
    tier_ok <- (c$tier %||% 3) <= tier_max
    only_ok <- is.null(only) || (c$path %in% only)
    sched_ok && tier_ok && only_ok
  }, caches)

  if (length(filtered) == 0) {
    cat("[cache_registry_runner] No caches matched filter\n")
    return(invisible(NULL))
  }

  # Topological order
  sorted <- .topo_sort(filtered)
  cat(sprintf("[cache_registry_runner] Executing %d caches in topological order\n",
              length(sorted)))

  # Execute
  results <- list()
  for (c in sorted) {
    results[[c$path]] <- .execute_cache(c, dry_run = dry_run)
  }

  # Summary
  cat("\n═══════════════════════════════════════════════════\n")
  cat("[cache_registry_runner] Summary:\n")
  n_pass <- sum(sapply(results, function(r) r$status == "PASS"))
  n_skip <- sum(sapply(results, function(r) grepl("SKIP", r$status)))
  n_fail <- sum(sapply(results, function(r) grepl("FAIL", r$status)))
  cat(sprintf("  PASS=%d SKIP=%d FAIL=%d\n", n_pass, n_skip, n_fail))
  if (n_fail > 0) {
    cat("  Failures:\n")
    for (r in results) {
      if (grepl("FAIL", r$status)) {
        cat(sprintf("    - %s [%s]: %s\n",
                    r$path, r$status, r$error %||% "(no message)"))
      }
    }
  }
  cat("═══════════════════════════════════════════════════\n")

  invisible(results)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

cat("[cache_registry_runner] Loaded.\n")
