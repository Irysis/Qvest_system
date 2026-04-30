#==============================================================================
# Measurement Basis Audit — v1.2 Charter §10 Health Score Module
# 02_Infrastructure/portfolio/measurement_basis_audit.R
#
# Purpose: active book의 measurement_basis 일관성을 0-100 점수로 산출.
#   bootstrap.sh + monitoring agent 양쪽에서 호출 가능.
#
# Health Score 계산식 (per STR_id, max 100):
#   sr_provenance_certificate 보유:                 +30
#   measurement_basis_primary == 'forge_realized':  +20
#   schedule_density_ratio >= 0.95:                 +20
#   factor_engine vs realized divergence < 0.3pp:   +20
#   governor_concord_certificate 보유:              +10
#
# Tier:
#   Healthy >= 90 / Warning 70-89 / Drifted < 70
#
# Reference: STR_1715 OVERRIDE_006 사후 — measurement_basis 미명시 산출물이 PG2 통과한 사고.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

audit_book_measurement_coherence <- function(book_state_path,
                                             wt_root = "qepm/mailbox/worktask",
                                             governor_dir = NULL) {
  if (!file.exists(book_state_path)) {
    return(list(
      score = NA, tier = "BOOK_STATE_MISSING",
      details = list(), error = "book_state.json not found"
    ))
  }

  bs <- tryCatch(fromJSON(book_state_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs)) {
    return(list(
      score = NA, tier = "BOOK_STATE_PARSE_FAIL",
      details = list(), error = "JSON parse fail"
    ))
  }

  admitted_ids <- bs$admitted_ids
  if (is.null(admitted_ids) || length(admitted_ids) == 0) {
    return(list(score = NA, tier = "NO_ADMITTED_IDS", details = list()))
  }

  # governor mailbox dir 추론
  if (is.null(governor_dir)) {
    governor_dir <- dirname(book_state_path)
  }

  # v1.7 lineage-aware: generated_at timestamp 정렬 + lineage chain 추적
  find_latest_wt <- function(str_id, wt_root) {
    if (!dir.exists(wt_root)) return(NULL)
    str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id)

    primary <- list()
    lineage <- list()
    for (wd in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
      ga_path <- file.path(wd, "governor_admission.json")
      if (!file.exists(ga_path)) next
      ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE),
                     error = function(e) NULL)
      if (is.null(ga)) next

      ga_str_id <- as.character(ga$str_id %||% "")
      gen_at <- as.character(ga$generated_at %||% "")
      discovery_of <- paste(as.character(ga$discovery_of %||% ""),
                            as.character(ga$wt_lifecycle$discovery_of %||% ""))

      if (identical(ga_str_id, str_id)) {
        primary[[length(primary) + 1]] <- list(wt_dir = wd, generated_at = gen_at)
      } else if (nchar(ga_str_id) > 0 && (grepl(str_id, ga_str_id, fixed = TRUE) ||
                  (nchar(str_id_root) > 0 && grepl(str_id_root, ga_str_id, fixed = TRUE)))) {
        lineage[[length(lineage) + 1]] <- list(wt_dir = wd, generated_at = gen_at)
      } else if (grepl(str_id, discovery_of, fixed = TRUE) ||
                 (nchar(str_id_root) > 0 && grepl(str_id_root, discovery_of, fixed = TRUE))) {
        lineage[[length(lineage) + 1]] <- list(wt_dir = wd, generated_at = gen_at)
      }
    }
    # primary 우선, 없으면 lineage. 동일 카테고리 내 generated_at 정렬 (latest 우선)
    sort_by_gen_at <- function(lst) {
      if (length(lst) <= 1) return(lst)
      gens <- sapply(lst, function(x) x$generated_at)
      lst[order(gens, decreasing = TRUE)]
    }
    primary <- sort_by_gen_at(primary)
    lineage <- sort_by_gen_at(lineage)

    if (length(primary) > 0) return(primary[[1]]$wt_dir)
    if (length(lineage) > 0) return(lineage[[1]]$wt_dir)
    NULL
  }

  # v1.7: lineage WT의 cert도 점수에 inherit (deployment alpha_discovery / sizing_only sr_provenance 등)
  find_lineage_wts <- function(str_id, wt_root) {
    if (!dir.exists(wt_root)) return(character(0))
    str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id)
    out <- character(0)
    for (wd in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
      ga_path <- file.path(wd, "governor_admission.json")
      fp_path <- file.path(wd, "forge_package.json")
      if (!file.exists(ga_path) && !file.exists(fp_path)) next
      hit <- FALSE
      if (file.exists(ga_path)) {
        ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE),
                       error = function(e) NULL)
        if (!is.null(ga)) {
          ga_str <- as.character(ga$str_id %||% "")
          dof <- paste(as.character(ga$discovery_of %||% ""),
                       as.character(ga$wt_lifecycle$discovery_of %||% ""))
          if (grepl(str_id, ga_str, fixed = TRUE) ||
              grepl(str_id, dof, fixed = TRUE) ||
              (nchar(str_id_root) > 0 &&
                (grepl(str_id_root, ga_str, fixed = TRUE) ||
                 grepl(str_id_root, dof, fixed = TRUE)))) {
            hit <- TRUE
          }
        }
      }
      if (!hit && file.exists(fp_path)) {
        fp <- tryCatch(fromJSON(fp_path, simplifyVector = FALSE),
                        error = function(e) NULL)
        if (!is.null(fp)) {
          dl <- paste(unlist(fp$deployment_lineage %||% list()),
                      unlist(fp$alpha_lineage_chain %||% list()), collapse = " ")
          if (grepl(str_id, dl, fixed = TRUE) ||
              (nchar(str_id_root) > 0 && grepl(str_id_root, dl, fixed = TRUE))) {
            hit <- TRUE
          }
        }
      }
      if (hit) out <- c(out, wd)
    }
    unique(out)
  }

  per_str <- list()
  total_score <- 0
  for (str_id in admitted_ids) {
    wt_dir <- find_latest_wt(str_id, wt_root)
    score <- 0
    components <- list()
    inherited_from <- list()

    if (is.null(wt_dir)) {
      per_str[[str_id]] <- list(
        score = 0, tier = "NO_WT", components = list(),
        note = "governor_admission.json with this str_id not found"
      )
      next
    }

    # v1.7 lineage WT 후보 (본 WT 외) — 누락 cert/field inherit fallback
    lineage_wts <- setdiff(find_lineage_wts(str_id, wt_root), wt_dir)

    # 1. sr_provenance_certificate (+30) — 본 WT 우선, 없으면 lineage WT inherit
    sr_cert_path <- file.path(wt_dir, "sr_provenance_certificate.json")
    if (file.exists(sr_cert_path)) {
      score <- score + 30
      components$sr_provenance_certificate <- 30
    } else {
      sr_inherit_wt <- NULL
      for (lw in lineage_wts) {
        if (file.exists(file.path(lw, "sr_provenance_certificate.json"))) {
          sr_inherit_wt <- basename(lw); break
        }
      }
      if (!is.null(sr_inherit_wt)) {
        score <- score + 30
        components$sr_provenance_certificate <- 30
        inherited_from$sr_provenance_certificate <- sr_inherit_wt
      } else {
        components$sr_provenance_certificate <- 0
      }
    }

    # 2~4: forge_package fields — 본 WT 우선, 없으면 lineage WT 내 forge_package에서 inherit
    forge_path <- file.path(wt_dir, "forge_package.json")
    forge_pkg <- if (file.exists(forge_path)) {
      tryCatch(fromJSON(forge_path, simplifyVector = FALSE),
               error = function(e) NULL)
    } else NULL
    forge_inherit_wt <- NULL
    if (is.null(forge_pkg)) {
      for (lw in lineage_wts) {
        lp <- file.path(lw, "forge_package.json")
        if (file.exists(lp)) {
          forge_pkg <- tryCatch(fromJSON(lp, simplifyVector = FALSE),
                                error = function(e) NULL)
          if (!is.null(forge_pkg)) { forge_inherit_wt <- basename(lw); break }
        }
      }
    }

    if (!is.null(forge_pkg) && isTRUE(forge_pkg$measurement_basis_primary ==
                                        "forge_realized_share_based")) {
      score <- score + 20
      components$measurement_basis_primary <- 20
      if (!is.null(forge_inherit_wt)) {
        inherited_from$measurement_basis_primary <- forge_inherit_wt
      }
    } else {
      components$measurement_basis_primary <- 0
    }

    if (!is.null(forge_pkg) && !is.null(forge_pkg$schedule_density_ratio) &&
        forge_pkg$schedule_density_ratio >= 0.95) {
      score <- score + 20
      components$schedule_density <- 20
      if (!is.null(forge_inherit_wt)) {
        inherited_from$schedule_density <- forge_inherit_wt
      }
    } else {
      components$schedule_density <- 0
    }

    diverg <- forge_pkg$divergence_factor_engine_vs_realized_pp %||%
              forge_pkg$vs_factor_engine$divergence_pp %||% NA
    if (!is.na(diverg) && abs(diverg) < 0.3) {
      score <- score + 20
      components$divergence_low <- 20
      if (!is.null(forge_inherit_wt)) {
        inherited_from$divergence_low <- forge_inherit_wt
      }
    } else {
      components$divergence_low <- 0
    }

    # 5. governor_concord_certificate (+10)
    concord_path <- file.path(governor_dir, "governor_concord_certificate.json")
    waiver_path <- file.path(governor_dir,
                             "governor_concord_with_waiver_certificate.json")
    if (file.exists(concord_path) || file.exists(waiver_path)) {
      score <- score + 10
      components$governor_concord <- 10
    } else {
      components$governor_concord <- 0
    }

    tier <- if (score >= 90) "HEALTHY" else if (score >= 70) "WARNING" else "DRIFTED"
    per_str[[str_id]] <- list(
      score = score, tier = tier,
      components = components, wt_dir = wt_dir,
      lineage_inherited_from = if (length(inherited_from) > 0) inherited_from else NULL,
      lineage_wts_audited = if (length(lineage_wts) > 0) basename(lineage_wts) else NULL
    )
    total_score <- total_score + score
  }

  # Book-level mean
  book_score <- if (length(per_str) > 0) total_score / length(per_str) else NA
  book_tier <- if (is.na(book_score)) "UNKNOWN" else
               if (book_score >= 90) "HEALTHY" else
               if (book_score >= 70) "WARNING" else "DRIFTED"

  list(
    score = round(book_score, 1),
    tier = book_tier,
    n_admitted = length(admitted_ids),
    per_str = per_str,
    audited_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    charter_ref = "v1.2 §10 Measurement Coherence Health Score"
  )
}

# Defensive %||%
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# CLI entrypoint (Rscript 호출용)
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  args <- commandArgs(trailingOnly = TRUE)
  bs_path <- args[1]
  wt_root_arg <- if (length(args) >= 2) args[2] else "qepm/mailbox/worktask"
  result <- audit_book_measurement_coherence(bs_path, wt_root = wt_root_arg)
  cat(sprintf("=== Measurement Coherence Health ===\n"))
  cat(sprintf("Book score: %s / 100\n", result$score))
  cat(sprintf("Tier: %s\n", result$tier))
  cat(sprintf("N admitted: %s\n", result$n_admitted))
  for (sid in names(result$per_str)) {
    s <- result$per_str[[sid]]
    cat(sprintf("  %s: %d/100 [%s]\n", sid, s$score, s$tier))
  }
  log_path <- "/tmp/measurement_coherence_health.log"
  writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE), log_path)
  cat(sprintf("Log: %s\n", log_path))
}
