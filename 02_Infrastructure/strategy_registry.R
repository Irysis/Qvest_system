#==============================================================================
# Strategy Registry — QEPM Lawbook v1.4 Ch.17/19/21
# Strategy Fingerprint, Factor Label Taxonomy, Lifecycle State
#
# Usage:
#   source("strategy_registry.R")
#   fp  <- compute_fingerprint(config_list)
#   lab <- assign_factor_labels(factor_name, ...)
#   reg <- load_registry(); reg <- update_lifecycle(reg, "STR_401", "CANDIDATE")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(digest)
})

cat("[strategy_registry] Loaded.\n")

#==============================================================================
# 1. STRATEGY FINGERPRINT (Ch.17)
# Hash-based duplicate detection. Two strategies with same fingerprint
# are structurally identical regardless of naming.
#==============================================================================

compute_fingerprint <- function(config) {
  # config: list with standardized fields
  # Returns: 8-char hex hash
  fp_fields <- list(
    universe    = config$universe    %||% "KOSPI200_KOSDAQ150",
    factor_fam  = sort(config$factor_family %||% "unknown"),
    rebal_freq  = config$rebal_freq  %||% "monthly",
    n_holdings  = config$n_holdings  %||% 30L,
    weight      = config$weight_method %||% "equal",
    risk_overlay = config$risk_overlay %||% "none",
    bz_keep     = config$bz_keep_n   %||% 0L,
    bz_entry    = config$bz_entry_n  %||% 0L,
    gate        = sort(config$gate   %||% "none"),
    commission  = config$commission  %||% 0.0015
  )
  hash <- digest(fp_fields, algo = "md5")
  substr(hash, 1, 8)
}

#==============================================================================
# 2. FACTOR LABEL TAXONOMY (Ch.19)
# 6-dimension labeling system for every factor used in research.
#==============================================================================

# v1.4 Ch.19 원본 기준
VALID_ECONOMIC_FAMILY <- c(
  "value", "momentum", "quality", "investment", "low-risk",
  "profitability", "event", "seasonality", "microstructure",
  "regime", "cross-domain"
)

VALID_CONSTRUCTION <- c(
  "raw_ratio", "rank", "zscore", "residualized", "spread",
  "sleeve", "integrated_score", "overlay"
)

VALID_NEUTRALITY <- c("none", "sector", "beta", "size", "vol", "multi")
VALID_HORIZON    <- c("short", "medium", "long")  # <3M, 3-12M, >12M
VALID_CAPACITY   <- c("low", "medium", "high")
VALID_EVIDENCE   <- c("A", "B", "C")  # A=학술+실증+재현, B=학술일부+초기, C=가설

assign_factor_labels <- function(factor_name,
                                  economic_family = "cross-domain",
                                  construction    = "raw_ratio",
                                  neutrality      = "none",
                                  horizon         = "medium",
                                  capacity_bucket = "medium",
                                  evidence_tier   = "C") {
  list(
    factor_name      = factor_name,
    economic_family  = match.arg(economic_family, VALID_ECONOMIC_FAMILY),
    construction     = match.arg(construction, VALID_CONSTRUCTION),
    neutrality       = match.arg(neutrality, VALID_NEUTRALITY),
    horizon          = match.arg(horizon, VALID_HORIZON),
    capacity_bucket  = match.arg(capacity_bucket, VALID_CAPACITY),
    evidence_tier    = match.arg(evidence_tier, VALID_EVIDENCE)
  )
}

#==============================================================================
# 3. STRATEGY LIFECYCLE (Ch.21)
# States: IDEA → ALPHA_LAB → RESEARCH_PASS → CANDIDATE → PAPER → PRODUCTION
#         → WATCHLIST → RETIRED
#==============================================================================

VALID_LIFECYCLE <- c(
  "IDEA", "ALPHA_LAB", "RESEARCH_PASS", "CANDIDATE",
  "PAPER", "PRODUCTION", "WATCHLIST", "RETIRED"
)

REGISTRY_PATH <- file.path(
  ifelse(exists("CACHE_DIR"), CACHE_DIR,
         "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache"),
  "strategy_registry.json"
)

load_registry <- function(path = REGISTRY_PATH) {
  if (file.exists(path)) {
    fromJSON(path, simplifyDataFrame = FALSE)
  } else {
    list()
  }
}

save_registry <- function(registry, path = REGISTRY_PATH) {
  write_json(registry, path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[registry] Saved: %s (%d strategies)\n", path, length(registry)))
}

register_strategy <- function(registry, strategy_name, config,
                               grade = NA, score = NA,
                               factor_labels = list(),
                               state = "RESEARCH_PASS",
                               data_snapshot_id = NULL) {
  fp <- compute_fingerprint(config)

  # Compute data_snapshot_id if not provided
  if (is.null(data_snapshot_id)) {
    data_snapshot_id <- tryCatch({
      cache_dir <- ifelse(exists("CACHE_DIR"), CACHE_DIR, ".cache")
      key_files <- c("RAWDATA.parquet", "benchmark.parquet", "fundamental_dart.parquet")
      mtimes <- sapply(file.path(cache_dir, key_files), function(f) {
        if (file.exists(f)) format(file.mtime(f), "%Y%m%d_%H%M") else "missing"
      })
      substr(digest(paste(mtimes, collapse = "|"), algo = "md5"), 1, 8)
    }, error = function(e) "unknown")
  }

  # Check for duplicate fingerprint
  for (nm in names(registry)) {
    if (!is.null(registry[[nm]]$fingerprint) && registry[[nm]]$fingerprint == fp &&
        nm != strategy_name) {
      cat(sprintf("[registry] WARNING: %s has same fingerprint as %s\n",
                  strategy_name, nm))
    }
  }

  registry[[strategy_name]] <- list(
    fingerprint      = fp,
    data_snapshot_id = data_snapshot_id,
    config           = config,
    grade            = grade,
    score            = score,
    factor_labels    = factor_labels,
    lifecycle        = state,
    created          = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    last_updated     = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    history          = list(list(
      state = state,
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ))
  )
  registry
}

update_lifecycle <- function(registry, strategy_name, new_state, note = "") {
  new_state <- match.arg(new_state, VALID_LIFECYCLE)
  if (is.null(registry[[strategy_name]])) {
    cat(sprintf("[registry] %s not found in registry\n", strategy_name))
    return(registry)
  }

  old_state <- registry[[strategy_name]]$lifecycle
  registry[[strategy_name]]$lifecycle <- new_state
  registry[[strategy_name]]$last_updated <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  registry[[strategy_name]]$history <- c(
    registry[[strategy_name]]$history,
    list(list(
      state = new_state,
      from  = old_state,
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      note  = note
    ))
  )

  cat(sprintf("[registry] %s: %s → %s\n", strategy_name, old_state, new_state))
  registry
}

#==============================================================================
# 4. RESEARCHOPS PRIORITY SCORE (Ch.21)
# Priority = 0.30*Gain + 0.25*Learning + 0.20*Novelty
#          - 0.15*Cost - 0.10*DependencyRisk - FamilyPenalty
#==============================================================================

compute_priority <- function(expected_gain,    # 0-10: estimated CAGR/Sharpe improvement
                              learning_value,   # 0-10: new knowledge expected
                              novelty,          # 0-10: how different from existing
                              cost,             # 0-10: compute/time cost
                              dependency_risk,  # 0-10: external data/infra needs
                              family_n_trials = 0L) {
  base <- 0.30 * expected_gain +
          0.25 * learning_value +
          0.20 * novelty -
          0.15 * cost -
          0.10 * dependency_risk

  # Family penalty: diminishing returns after many trials in same family
  family_penalty <- if (family_n_trials > 5) {
    min(2.0, log(family_n_trials / 5) * 0.5)
  } else {
    0
  }

  round(base - family_penalty, 2)
}

compute_label_signature <- function(labels) {
  paste(labels$economic_family, labels$construction, labels$neutrality,
        labels$horizon, labels$capacity_bucket, labels$evidence_tier,
        sep = "|")
}

cat("[strategy_registry] Functions: compute_fingerprint(), assign_factor_labels(), compute_label_signature(), register_strategy(), update_lifecycle(), compute_priority()\n")
