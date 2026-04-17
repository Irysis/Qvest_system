#==============================================================================
# Evolution Tracker — Layer 2: Intelligence (행동 제안 + 전략 계보)
#
# R0~R7 (Evidence)과 분리된 별도 레이어.
# "무엇이 일어났는가"가 아닌 "다음에 무엇을 해야 하는가"를 관리.
#
# 3-Layer Architecture:
#   Layer 1: R0~R7 Evidence — 사실 기록 (기존, 수정 없음)
#   Layer 2: evolution_tracker — 행동 제안 + 계보 (이 파일)
#   Layer 3: methodology_memory L-codes — 확립된 교훈 (기존, 수정 없음)
#
# Usage:
#   source("02_Infrastructure/evolution_tracker.R")
#   evo_record(parent, child, evolution_type, description, expected_impact)
#   evo_get_children(strategy_id)
#   evo_get_unrealized(family)
#   evo_get_lineage(strategy_id)
#   evo_summary()
#   evo_axiom_support(family)  # Axiom 스캔 시 호출
#==============================================================================

cat("[evolution_tracker] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
}

EVO_PATH <- file.path(PROJECT_ROOT, "qepm", "memory", "evolution_tracker.json")

#' Load evolution tracker (create if not exists)
.evo_load <- function() {
  if (file.exists(EVO_PATH)) {
    tryCatch(
      fromJSON(EVO_PATH, simplifyDataFrame = FALSE),
      error = function(e) {
        cat("[evolution_tracker] Parse error, creating fresh.\n")
        list(records = list(), metadata = list(created = as.character(Sys.time()), version = 1))
      }
    )
  } else {
    list(records = list(), metadata = list(created = as.character(Sys.time()), version = 1))
  }
}

#' Save evolution tracker
.evo_save <- function(tracker) {
  dir.create(dirname(EVO_PATH), recursive = TRUE, showWarnings = FALSE)
  tracker$metadata$last_updated <- as.character(Sys.time())
  tracker$metadata$n_records <- length(tracker$records)
  write_json(tracker, EVO_PATH, pretty = TRUE, auto_unbox = TRUE)
}

#==============================================================================
# Core Functions
#==============================================================================

#' Record an evolution path (Judge가 검증 후 호출)
#'
#' @param parent_id 부모 전략 ID (e.g., "STR_1048")
#' @param child_id 자식 전략 ID (NULL if not yet created)
#' @param family factor family (e.g., "stock_ensemble")
#' @param evolution_type 발전 유형: "improvement", "variant", "falsification", "extension"
#' @param description 발전 내용 설명
#' @param expected_impact 예상 효과 (e.g., "SR +0.15", "MDD -2%p")
#' @param realized 실현 여부 (FALSE = 아직 미실행, TRUE = Forge가 실행 완료)
#' @param realized_metrics 실현된 경우 실제 성과 (list)
#' @param judge_commentary Judge의 원본 commentary (보존)
evo_record <- function(parent_id, child_id = NULL, family = NULL,
                       evolution_type = "improvement",
                       description, expected_impact = NULL,
                       realized = FALSE, realized_metrics = NULL,
                       judge_commentary = NULL) {

  tracker <- .evo_load()

  record <- list(
    evo_id = sprintf("EVO_%s_%s", format(Sys.time(), "%Y%m%d_%H%M%S"),
                     sample(1000:9999, 1)),
    parent_id = parent_id,
    child_id = child_id,
    family = family,
    evolution_type = evolution_type,
    description = description,
    expected_impact = expected_impact,
    realized = realized,
    realized_metrics = realized_metrics,
    judge_commentary = judge_commentary,
    created_at = as.character(Sys.time()),
    realized_at = if (realized) as.character(Sys.time()) else NULL
  )

  tracker$records <- c(tracker$records, list(record))
  .evo_save(tracker)

  cat(sprintf("[evolution_tracker] Recorded: %s → %s (%s)\n",
              parent_id, child_id %||% "pending", description))

  invisible(record$evo_id)
}

#' Mark an evolution path as realized (Forge 완료 후 호출)
#'
#' @param parent_id 부모 전략
#' @param child_id 자식 전략 (실현된)
#' @param metrics 실제 성과 list(sr, cagr, mdd, grade, score)
evo_realize <- function(parent_id, child_id, metrics = NULL) {
  tracker <- .evo_load()

  matched <- FALSE
  for (i in seq_along(tracker$records)) {
    r <- tracker$records[[i]]
    if (r$parent_id == parent_id && !isTRUE(r$realized)) {
      tracker$records[[i]]$child_id <- child_id
      tracker$records[[i]]$realized <- TRUE
      tracker$records[[i]]$realized_at <- as.character(Sys.time())
      tracker$records[[i]]$realized_metrics <- metrics
      matched <- TRUE
      break
    }
  }

  if (!matched) {
    # No pending record — create a new realized record
    evo_record(parent_id, child_id, family = NULL,
               evolution_type = "improvement",
               description = sprintf("Realized from %s", parent_id),
               realized = TRUE, realized_metrics = metrics)
  } else {
    .evo_save(tracker)
  }

  cat(sprintf("[evolution_tracker] Realized: %s → %s\n", parent_id, child_id))
}

#' Get all children of a strategy
evo_get_children <- function(strategy_id) {
  tracker <- .evo_load()
  children <- Filter(function(r) r$parent_id == strategy_id, tracker$records)
  children
}

#' Get unrealized evolution paths (Forge가 아직 안 한 것)
evo_get_unrealized <- function(family = NULL) {
  tracker <- .evo_load()
  unrealized <- Filter(function(r) !isTRUE(r$realized), tracker$records)
  if (!is.null(family)) {
    unrealized <- Filter(function(r) identical(r$family, family), unrealized)
  }
  unrealized
}

#' Get full lineage tree for a strategy (조상 → 본인 → 자식)
evo_get_lineage <- function(strategy_id) {
  tracker <- .evo_load()

  # Find ancestors (trace back)
  ancestors <- list()
  current <- strategy_id
  for (depth in 1:20) {  # max depth 20
    parents <- Filter(function(r) identical(r$child_id, current), tracker$records)
    if (length(parents) == 0) break
    current <- parents[[1]]$parent_id
    ancestors <- c(list(parents[[1]]), ancestors)
  }

  # Find descendants (trace forward)
  descendants <- list()
  queue <- list(strategy_id)
  while (length(queue) > 0) {
    current <- queue[[1]]
    queue <- queue[-1]
    children <- Filter(function(r) r$parent_id == current && isTRUE(r$realized),
                       tracker$records)
    for (ch in children) {
      descendants <- c(descendants, list(ch))
      queue <- c(queue, list(ch$child_id))
    }
  }

  list(
    strategy_id = strategy_id,
    ancestors = ancestors,
    descendants = descendants,
    generation = length(ancestors) + 1,
    total_lineage = length(ancestors) + 1 + length(descendants)
  )
}

#' Summary of evolution tracker
evo_summary <- function() {
  tracker <- .evo_load()
  n <- length(tracker$records)

  if (n == 0) {
    cat("[evolution_tracker] Empty. No records.\n")
    return(invisible(NULL))
  }

  realized <- sum(sapply(tracker$records, function(r) isTRUE(r$realized)))
  unrealized <- n - realized

  # Unique families
  families <- unique(sapply(tracker$records, function(r) r$family %||% "unknown"))

  # Unique parents
  parents <- unique(sapply(tracker$records, function(r) r$parent_id))

  # Evolution types
  types <- table(sapply(tracker$records, function(r) r$evolution_type %||% "unknown"))

  cat(sprintf("[evolution_tracker] Summary:\n"))
  cat(sprintf("  Total records: %d (realized: %d, pending: %d)\n", n, realized, unrealized))
  cat(sprintf("  Unique parents: %d\n", length(parents)))
  cat(sprintf("  Families: %s\n", paste(families, collapse = ", ")))
  cat(sprintf("  Types: %s\n", paste(names(types), types, sep = "=", collapse = ", ")))

  invisible(list(
    total = n, realized = realized, unrealized = unrealized,
    families = families, parents = parents, types = types
  ))
}

#==============================================================================
# Axiom Support — Axiom 스캔 시 호출
#==============================================================================

#' Axiom 5축 지원 데이터 제공
#'
#' @param family factor family to evaluate
#' @return list with independence_support, falsification_support, mechanism_support
evo_axiom_support <- function(family) {
  tracker <- .evo_load()

  family_records <- Filter(function(r) identical(r$family, family), tracker$records)
  realized_records <- Filter(function(r) isTRUE(r$realized), family_records)

  # Independence support: 다른 construction에서 같은 결론
  # = realized children with different evolution_type that all succeed
  types_realized <- unique(sapply(realized_records, function(r) r$evolution_type %||% "unknown"))
  n_independent_paths <- length(types_realized)

  # Direction consistency: 부모 대비 자식이 개선되었는지
  improvements <- 0; total_children <- 0
  for (r in realized_records) {
    if (!is.null(r$realized_metrics)) {
      total_children <- total_children + 1
      parent_score <- r$realized_metrics$parent_score %||% 0
      child_score <- r$realized_metrics$score %||% r$realized_metrics$child_score %||% 0
      if (child_score > parent_score) improvements <- improvements + 1
    }
  }
  direction_consistency <- if (total_children > 0) improvements / total_children else 0

  # Falsification support: "falsification" 타입 실험이 있고 생존했는지
  falsification_attempts <- Filter(
    function(r) r$evolution_type == "falsification" && isTRUE(r$realized),
    family_records
  )
  falsification_survived <- Filter(
    function(r) {
      m <- r$realized_metrics
      !is.null(m) && (m$grade %in% c("A", "B") || (m$score %||% 0) > 40)
    },
    falsification_attempts
  )

  # Generation depth: 가장 긴 계보
  max_generation <- 0
  for (r in realized_records) {
    if (!is.null(r$child_id)) {
      lineage <- evo_get_lineage(r$child_id)
      max_generation <- max(max_generation, lineage$generation)
    }
  }

  result <- list(
    family = family,
    total_records = length(family_records),
    realized = length(realized_records),
    unrealized = length(family_records) - length(realized_records),
    n_independent_paths = n_independent_paths,
    direction_consistency = round(direction_consistency, 3),
    falsification_attempts = length(falsification_attempts),
    falsification_survived = length(falsification_survived),
    max_generation = max_generation,
    # Axiom 축 지원 여부
    supports_independence = n_independent_paths >= 2 && direction_consistency >= 0.7,
    supports_falsification = length(falsification_attempts) >= 1 && length(falsification_survived) >= 1
  )

  cat(sprintf("[evolution_tracker] Axiom support for '%s':\n", family))
  cat(sprintf("  Independent paths: %d | Direction: %.1f%% | Falsification: %d/%d survived\n",
              n_independent_paths, direction_consistency * 100,
              length(falsification_survived), length(falsification_attempts)))
  cat(sprintf("  Max generation: %d | Supports independence: %s | Supports falsification: %s\n",
              max_generation, result$supports_independence, result$supports_falsification))

  result
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

cat("[evolution_tracker] Loaded. Functions:\n")
cat("  evo_record(parent, child, family, type, desc, impact)\n")
cat("  evo_realize(parent, child, metrics)\n")
cat("  evo_get_children(strategy_id)\n")
cat("  evo_get_unrealized(family)\n")
cat("  evo_get_lineage(strategy_id)\n")
cat("  evo_summary()\n")
cat("  evo_axiom_support(family)  # Axiom 스캔 시\n")
