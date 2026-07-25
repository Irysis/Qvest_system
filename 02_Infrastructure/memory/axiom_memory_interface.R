#==============================================================================
# V7 Research Engine — Axiom Memory Interface
# axiom_memory_interface.R
#
# Bridge between the V7 stage gate pipeline and the qepm axiom/memory system.
# Reads axiom signals (reuse penalty, family cooldown, failure clusters,
# method fatigue) and writes back results (verdicts, portfolio updates, lessons).
# Also provides methodology memory sync.
#
# Usage:
#   source("02_Infrastructure/axiom_memory_interface.R")
#   signals <- sg_read_axiom_signals("all")
#   path    <- sg_write_axiom_result("strategy_verdict", verdict_data, "STR_1435")
#   sync    <- sg_sync_methodology_memory()
#
# Dependencies: jsonlite, data.table
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

# ─── Config: find project root ───────────────────────────────────────────────
if (!exists("PROJECT_ROOT")) {
  .ami_root_candidates <- c(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
  )
  PROJECT_ROOT <- .ami_root_candidates[sapply(.ami_root_candidates, dir.exists)][1]
  if (is.na(PROJECT_ROOT)) {
    PROJECT_ROOT <- Sys.getenv("QM_ROOT",
      unset = Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")))
  }
  rm(.ami_root_candidates)
}

# ─── Paths ───────────────────────────────────────────────────────────────────
.AMI_CACHE_DIR       <- file.path(PROJECT_ROOT, ".cache")
.AMI_SIGNALS_FILE    <- file.path(.AMI_CACHE_DIR, "axiom_signals.json")
.AMI_RESULTS_DIR     <- file.path(.AMI_CACHE_DIR, "axiom_results")
.AMI_AXIOMS_DIR      <- file.path(PROJECT_ROOT, "qepm", "memory", "axioms", "active")
.AMI_METHODOLOGY_MD  <- file.path(PROJECT_ROOT, "qepm", "memory", "methodology_memory.md")
.AMI_STAGE_ARTIFACTS <- file.path(PROJECT_ROOT, "04_Research", "strategies")

# Ensure output directories exist
for (.d in c(.AMI_CACHE_DIR, .AMI_RESULTS_DIR)) {
  if (!dir.exists(.d)) dir.create(.d, recursive = TRUE, showWarnings = FALSE)
}

# ─── Default axiom signals (created if file does not exist) ──────────────────
.AMI_DEFAULT_SIGNALS <- list(
  reuse_penalty = list(
    description = "Penalty for reusing recently failed factor combinations",
    active = TRUE,
    decay_days = 30L,
    penalty_weight = 0.5,
    entries = list()
  ),
  family_cooldown = list(
    description = "Cooldown period for factor families after saturation",
    active = TRUE,
    cooldown_days = 14L,
    max_concurrent = 3L,
    entries = list()
  ),
  failure_cluster = list(
    description = "Cluster of recently failed strategies with common traits",
    active = TRUE,
    cluster_window_days = 60L,
    min_cluster_size = 3L,
    entries = list()
  ),
  method_fatigue = list(
    description = "Diminishing returns from overusing the same methodology",
    active = TRUE,
    fatigue_threshold = 5L,
    lookback_days = 90L,
    entries = list()
  ),
  last_updated = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

#==============================================================================
# sg_read_axiom_signals — Read axiom signals from cache + active axioms
#==============================================================================

#' Read axiom signals
#'
#' @param signal_type Character. One of: "reuse_penalty", "family_cooldown",
#'   "failure_cluster", "method_fatigue", "all"
#' @param as_of_date Date. Reference date for signal freshness (default: yesterday, PIT compliant)
#' @return List with requested signal data
sg_read_axiom_signals <- function(signal_type = "all",
                                  as_of_date = Sys.Date() - 1) {

  cat(sprintf("[axiom_interface] Reading axiom signals: %s (as_of: %s)\n",
              signal_type, as_of_date))

  valid_types <- c("reuse_penalty", "family_cooldown", "failure_cluster",
                    "method_fatigue", "all")
  if (!signal_type %in% valid_types) {
    stop(sprintf("[axiom_interface] Invalid signal_type '%s'. Valid: %s",
                 signal_type, paste(valid_types, collapse = ", ")))
  }

  # Load or create axiom_signals.json
  signals <- tryCatch({
    if (file.exists(.AMI_SIGNALS_FILE)) {
      fromJSON(.AMI_SIGNALS_FILE, simplifyVector = FALSE)
    } else {
      cat("[axiom_interface] axiom_signals.json not found. Creating defaults.\n")
      write_json(.AMI_DEFAULT_SIGNALS, .AMI_SIGNALS_FILE, pretty = TRUE, auto_unbox = TRUE)
      .AMI_DEFAULT_SIGNALS
    }
  }, error = function(e) {
    warning(sprintf("[axiom_interface] Error reading axiom_signals.json: %s. Using defaults.", e$message))
    .AMI_DEFAULT_SIGNALS
  })

  # Also scan active axiom files from qepm
  active_axioms <- list()
  if (dir.exists(.AMI_AXIOMS_DIR)) {
    axiom_files <- list.files(.AMI_AXIOMS_DIR, pattern = "\\.json$", full.names = TRUE)
    for (af in axiom_files) {
      tryCatch({
        ax <- fromJSON(af, simplifyVector = FALSE)
        ax_name <- tools::file_path_sans_ext(basename(af))
        active_axioms[[ax_name]] <- ax
      }, error = function(e) {
        cat(sprintf("[axiom_interface] Warning: cannot read axiom file %s: %s\n",
                    basename(af), e$message))
      })
    }
  }

  # Filter signals by as_of_date (PIT: t-1 lag)
  # Remove entries newer than as_of_date
  .filter_entries <- function(entries) {
    if (is.null(entries) || length(entries) == 0) return(entries)
    Filter(function(entry) {
      entry_date <- as.Date(entry$date %||% entry$created %||% "1900-01-01")
      entry_date <= as_of_date
    }, entries)
  }

  for (sig_name in c("reuse_penalty", "family_cooldown", "failure_cluster", "method_fatigue")) {
    if (!is.null(signals[[sig_name]]$entries)) {
      signals[[sig_name]]$entries <- .filter_entries(signals[[sig_name]]$entries)
    }
  }

  # Compose result
  result <- list(
    as_of_date    = as.character(as_of_date),
    active_axioms = active_axioms
  )

  if (signal_type == "all") {
    result$reuse_penalty   <- signals$reuse_penalty
    result$family_cooldown <- signals$family_cooldown
    result$failure_cluster <- signals$failure_cluster
    result$method_fatigue  <- signals$method_fatigue
  } else {
    result[[signal_type]] <- signals[[signal_type]]
  }

  cat(sprintf("[axiom_interface] Loaded %d signal type(s), %d active axiom(s)\n",
              if (signal_type == "all") 4L else 1L, length(active_axioms)))

  result
}

#==============================================================================
# sg_write_axiom_result — Write result back to cache
#==============================================================================

#' Write an axiom result to the cache
#'
#' @param result_type Character. One of: "strategy_verdict", "portfolio_update", "lesson"
#' @param result_data List. The data to write
#' @param strategy_id Character. Associated strategy ID (optional)
#' @return Invisible file path of the written file
sg_write_axiom_result <- function(result_type,
                                  result_data,
                                  strategy_id = NULL) {

  valid_types <- c("strategy_verdict", "portfolio_update", "lesson")
  if (!result_type %in% valid_types) {
    stop(sprintf("[axiom_interface] Invalid result_type '%s'. Valid: %s",
                 result_type, paste(valid_types, collapse = ", ")))
  }

  if (!dir.exists(.AMI_RESULTS_DIR)) {
    dir.create(.AMI_RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
  }

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  filename <- sprintf("%s_%s.json", result_type, timestamp)
  filepath <- file.path(.AMI_RESULTS_DIR, filename)

  # Compose output object
  output <- list(
    result_type = result_type,
    strategy_id = strategy_id,
    timestamp   = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    data        = result_data
  )

  tryCatch({
    write_json(output, filepath, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("[axiom_interface] Written %s → %s\n", result_type, basename(filepath)))
  }, error = function(e) {
    warning(sprintf("[axiom_interface] Failed to write %s: %s", filepath, e$message))
  })

  # If it's a lesson, also update the axiom_signals.json with relevant entries
  if (result_type == "lesson" && !is.null(result_data$l_code)) {
    tryCatch({
      signals <- if (file.exists(.AMI_SIGNALS_FILE)) {
        fromJSON(.AMI_SIGNALS_FILE, simplifyVector = FALSE)
      } else {
        .AMI_DEFAULT_SIGNALS
      }

      # Add to failure_cluster if it's a failure lesson
      if (isTRUE(result_data$is_failure)) {
        new_entry <- list(
          l_code      = result_data$l_code,
          strategy_id = strategy_id,
          date        = as.character(Sys.Date()),
          family      = result_data$family %||% "unknown",
          method      = result_data$method %||% "unknown",
          reason      = result_data$reason %||% ""
        )
        signals$failure_cluster$entries <- c(
          signals$failure_cluster$entries, list(new_entry)
        )
      }

      # Add to reuse_penalty if factor combo failed
      if (!is.null(result_data$factors_used)) {
        penalty_entry <- list(
          factors     = result_data$factors_used,
          strategy_id = strategy_id,
          date        = as.character(Sys.Date()),
          l_code      = result_data$l_code
        )
        signals$reuse_penalty$entries <- c(
          signals$reuse_penalty$entries, list(penalty_entry)
        )
      }

      signals$last_updated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      write_json(signals, .AMI_SIGNALS_FILE, pretty = TRUE, auto_unbox = TRUE)
    }, error = function(e) {
      cat(sprintf("[axiom_interface] Warning: failed to update axiom_signals: %s\n", e$message))
    })
  }

  invisible(filepath)
}

#==============================================================================
# sg_sync_methodology_memory — Sync L-codes from stage artifacts to memory
#==============================================================================

#' Synchronize methodology memory with stage artifacts
#'
#' Scans all stage_artifacts/ directories for l_code_*.json files, extracts
#' L-codes, and appends any missing ones to methodology_memory.md.
#'
#' @return List with synced (integer count), already_present (integer), errors (character vector)
sg_sync_methodology_memory <- function() {

  cat("[axiom_interface] Syncing methodology memory with stage artifacts...\n")

  errors <- character(0)
  synced <- 0L
  already_present <- 0L

  # Find all l_code JSON files in strategy directories
  l_code_files <- character(0)
  if (dir.exists(.AMI_STAGE_ARTIFACTS)) {
    strategy_dirs <- list.dirs(.AMI_STAGE_ARTIFACTS, recursive = FALSE, full.names = TRUE)
    for (sdir in strategy_dirs) {
      artifacts_dir <- file.path(sdir, "stage_artifacts")
      if (dir.exists(artifacts_dir)) {
        found <- list.files(artifacts_dir, pattern = "^l_code.*\\.json$",
                            full.names = TRUE, recursive = FALSE)
        l_code_files <- c(l_code_files, found)
      }
    }
  }

  if (length(l_code_files) == 0) {
    cat("[axiom_interface] No l_code files found in stage_artifacts/.\n")
    return(list(status = "OK_NOTHING_FOUND", synced = 0L, already_present = 0L,
                errors = errors))
  }

  cat(sprintf("[axiom_interface] Found %d l_code file(s) to scan.\n", length(l_code_files)))

  # Extract L-codes from JSON files
  # 2026-07-25 침묵 드롭 수리: 전략트리 아티팩트는 2개 스키마가 공존한다.
  #   구: l_code       / lesson      / factor_id      (2026-03 QEPM 배치, 42건)
  #   신: l_code_id    / lesson_text / core_reference (26건)
  # 종전 코드는 `l_code`+`lesson`만 읽어 신스키마 ID를 통째로 버리고(=미적립),
  # 구스키마 외 lesson을 빈 문자열로 만들었다. 두 스키마 모두 인식한다.
  new_lcodes <- list()
  skipped_no_id <- character(0)
  for (lf in l_code_files) {
    tryCatch({
      content <- fromJSON(lf, simplifyVector = FALSE)
      l_code <- content$l_code %||% content$l_code_id %||% content$lcode %||%
                content$code %||% NULL
      l_text <- content$lesson_text %||% content$lesson %||% content$text %||%
                content$description %||% ""

      if (!is.null(l_code) && nchar(l_code) > 0) {
        new_lcodes[[l_code]] <- list(
          code = l_code,
          text = l_text,
          source = basename(dirname(dirname(lf))),  # strategy ID
          file = basename(lf)
        )
      } else {
        # ID 미발급 아티팩트 — 어떤 파이프라인도 잡을 수 없으므로 조용히 흘리지 않고 계상한다.
        skipped_no_id <- c(skipped_no_id,
                           file.path(basename(dirname(dirname(lf))), basename(lf)))
      }
    }, error = function(e) {
      errors <<- c(errors, sprintf("Error reading %s: %s", basename(lf), e$message))
    })
  }

  if (length(skipped_no_id) > 0) {
    warning(sprintf(
      "[axiom_interface] l_code 아티팩트 %d건에 L-code ID가 없어 적립 불가: %s",
      length(skipped_no_id), paste(head(skipped_no_id, 5), collapse = ", ")),
      call. = FALSE)
    errors <- c(errors, sprintf("%d artifact(s) without l_code id", length(skipped_no_id)))
  }

  if (length(new_lcodes) == 0) {
    cat("[axiom_interface] No valid L-codes extracted.\n")
    return(list(status = "OK_NOTHING_EXTRACTED", synced = 0L, already_present = 0L,
                skipped_no_id = skipped_no_id, errors = errors))
  }

  # Check which L-codes already exist in methodology_memory.md
  # 2026-07-25: 죽은 WSL 경로(/home/quant/...) 제거 — 다른 머신의 레거시 경로였다.
  mm_paths <- unique(c(
    .AMI_METHODOLOGY_MD,
    file.path(PROJECT_ROOT, "qepm", "memory", "methodology_memory.md")
  ))

  mm_path <- NULL
  mm_content <- ""
  for (mp in mm_paths) {
    if (file.exists(mp)) {
      mm_path <- mp
      tryCatch({
        mm_content <- paste(readLines(mp, warn = FALSE), collapse = "\n")
      }, error = function(e) {
        mm_content <<- ""
      })
      break
    }
  }

  # ── 침묵 드롭 차단 (2026-07-25) ────────────────────────────────────────────
  # 종전: sink 부재 시 synced=0 을 정상 반환 → 호출부(hook_batch_runner.R:67/113)가
  # 반환값을 보지 않으므로 "적립됨"과 구분 불가. 실측 결과 L-code 68건 + ID미발급
  # 14건이 이 경로로 유실됐다. 이제 명시 실패로 승격한다.
  #   · warning() — 훅의 tryCatch(error=)는 warning 을 잡지 않으므로 하류(PG0 gap /
  #     Scout TODO)를 죽이지 않으면서 표면화된다.
  #   · 결손 원장을 .cache 에 남겨 세션이 끝나도 증거가 사라지지 않게 한다.
  if (is.null(mm_path)) {
    defect <- list(
      detected_at   = as.character(Sys.time()),
      defect        = "sink_absent",
      expected_sink = mm_paths,
      dropped_n     = length(new_lcodes),
      dropped       = names(new_lcodes),
      skipped_no_id = skipped_no_id
    )
    tryCatch({
      write_json(defect,
                 file.path(.AMI_CACHE_DIR, "lcode_sync_defect.json"),
                 auto_unbox = TRUE, pretty = TRUE)
    }, error = function(e) invisible(NULL))

    msg <- sprintf(paste0(
      "[axiom_interface] SYNC FAILED — sink 부재로 L-code %d건 적립 불가. ",
      "기대 경로: %s. 결손 원장: .cache/lcode_sync_defect.json"),
      length(new_lcodes), paste(mm_paths, collapse = " | "))
    cat(msg, "\n")
    warning(msg, call. = FALSE)

    return(list(
      status          = "FAILED_NO_SINK",
      synced          = 0L,
      already_present = 0L,
      dropped         = length(new_lcodes),
      new_lcodes      = names(new_lcodes),
      skipped_no_id   = skipped_no_id,
      errors          = c(errors, "methodology_memory.md not found — L-codes dropped")
    ))
  }

  # Filter to only new L-codes
  # 2026-07-25: fixed=TRUE substring 매칭은 L-17 이 L-170 에 오매칭돼 미적립을
  # "이미 있음"으로 위장했다. 토큰 경계로 판정한다
  # (cf. [[project-lcode-family-substring-rootcause-fix]] 동일 부류).
  to_append <- list()
  for (lc_name in names(new_lcodes)) {
    present <- grepl(sprintf("(^|[^A-Za-z0-9_-])%s([^A-Za-z0-9_-]|$)",
                             gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", lc_name)),
                     mm_content, perl = TRUE)
    if (present) {
      already_present <- already_present + 1L
    } else {
      to_append[[lc_name]] <- new_lcodes[[lc_name]]
    }
  }

  if (length(to_append) == 0) {
    cat(sprintf("[axiom_interface] All %d L-codes already present. Nothing to sync.\n",
                already_present))
    return(list(status = "OK_UP_TO_DATE", synced = 0L,
                already_present = already_present,
                skipped_no_id = skipped_no_id, errors = errors))
  }

  # Append new L-codes to methodology_memory.md
  append_lines <- character(0)
  append_lines <- c(append_lines, "",
    sprintf("## Auto-synced L-codes (%s)", format(Sys.time(), "%Y-%m-%d %H:%M")),
    "")

  for (lc_name in names(to_append)) {
    lc <- to_append[[lc_name]]
    append_lines <- c(append_lines,
      sprintf("- **%s** (%s): %s", lc$code, lc$source, lc$text))
    synced <- synced + 1L
  }

  tryCatch({
    writeLines(c(readLines(mm_path, warn = FALSE), append_lines), mm_path)
    cat(sprintf("[axiom_interface] Appended %d new L-code(s) to %s\n",
                synced, basename(mm_path)))
  }, error = function(e) {
    errors <- c(errors, sprintf("Failed to write to %s: %s", mm_path, e$message))
    cat(sprintf("[axiom_interface] ERROR: %s\n", e$message))
  })

  list(
    status          = if (length(errors) > 0) "PARTIAL" else "OK_SYNCED",
    synced          = synced,
    already_present = already_present,
    new_lcodes      = names(to_append),
    skipped_no_id   = skipped_no_id,
    errors          = errors
  )
}

#==============================================================================
# sg_axiom_lcode_trace — AX-code ↔ L-code 양방향 추적 (v53 Sprint 4 AX-P1)
#==============================================================================

#' Trace L-codes that support an axiom, or find axiom promoted from an L-code
#'
#' @param axiom_id Character. AX-XXX to trace (returns supporting_l_codes)
#' @param l_code Character. L-XXX to trace (returns promoted_to_axiom)
#' @return List with traced relation
sg_axiom_lcode_trace <- function(axiom_id = NULL, l_code = NULL) {
  if (is.null(axiom_id) && is.null(l_code)) {
    stop("[axiom_trace] axiom_id 또는 l_code 중 하나 필수")
  }

  if (!is.null(axiom_id)) {
    ax_path <- file.path(.AMI_AXIOMS_DIR, paste0(axiom_id, ".json"))
    if (!file.exists(ax_path)) {
      return(list(found = FALSE, axiom_id = axiom_id,
                  reason = "active axiom 파일 없음"))
    }
    ax <- fromJSON(ax_path, simplifyVector = FALSE)
    return(list(
      found = TRUE,
      axiom_id = axiom_id,
      statement = ax$statement %||% "",
      supporting_l_codes = ax$supporting_l_codes %||% character(0),
      type = ax$type,
      polarity = ax$polarity,
      promoted_at = ax$promotion$promoted_at %||% NA
    ))
  }

  # l_code 역추적
  root <- dirname(dirname(.AMI_AXIOMS_DIR))
  stage_arts <- file.path(PROJECT_ROOT, "stage_artifacts")
  if (!dir.exists(stage_arts)) {
    stage_arts <- file.path(root, "..", "stage_artifacts")
  }
  lc_files <- list.files(stage_arts, pattern = "^l_code_.*\\.json$", full.names = TRUE)
  for (f in lc_files) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    if (identical(d$l_code, l_code)) {
      return(list(
        found = TRUE,
        l_code = l_code,
        strategy_id = d$strategy_id %||% NA,
        promoted_to_axiom = d$promoted_to_axiom %||% NULL,
        source_file = f
      ))
    }
  }
  list(found = FALSE, l_code = l_code, reason = "l_code JSON 파일 없음")
}

cat("[axiom_memory_interface] Loaded — 4 axiom interface functions available.\n")
