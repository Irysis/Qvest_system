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

  # 각 STR의 latest WT 찾기 (governor_admission.json str_id로 매칭)
  find_latest_wt <- function(str_id, wt_root) {
    if (!dir.exists(wt_root)) return(NULL)
    wt_dirs <- list.dirs(wt_root, full.names = TRUE, recursive = FALSE)
    wt_dirs <- grep("^WT-", basename(wt_dirs), value = FALSE)
    candidates <- list()
    for (wd in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
      ga_path <- file.path(wd, "governor_admission.json")
      if (!file.exists(ga_path)) next
      ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE),
                     error = function(e) NULL)
      if (is.null(ga)) next
      if (isTRUE(ga$str_id == str_id)) {
        candidates[[length(candidates) + 1]] <- list(
          wt_dir = wd,
          generated_at = ga$generated_at %||% ""
        )
      }
    }
    if (length(candidates) == 0) return(NULL)
    # 단순화: 첫 번째 매치 사용 (정확한 latest 정렬은 hook 검증 부담)
    candidates[[1]]$wt_dir
  }

  per_str <- list()
  total_score <- 0
  for (str_id in admitted_ids) {
    wt_dir <- find_latest_wt(str_id, wt_root)
    score <- 0
    components <- list()

    if (is.null(wt_dir)) {
      per_str[[str_id]] <- list(
        score = 0, tier = "NO_WT", components = list(),
        note = "governor_admission.json with this str_id not found"
      )
      next
    }

    # 1. sr_provenance_certificate (+30)
    sr_cert_path <- file.path(wt_dir, "sr_provenance_certificate.json")
    if (file.exists(sr_cert_path)) {
      score <- score + 30
      components$sr_provenance_certificate <- 30
    } else {
      components$sr_provenance_certificate <- 0
    }

    # 2. forge_package measurement_basis_primary (+20)
    forge_path <- file.path(wt_dir, "forge_package.json")
    forge_pkg <- if (file.exists(forge_path)) {
      tryCatch(fromJSON(forge_path, simplifyVector = FALSE),
               error = function(e) NULL)
    } else NULL

    if (!is.null(forge_pkg) && isTRUE(forge_pkg$measurement_basis_primary ==
                                        "forge_realized_share_based")) {
      score <- score + 20
      components$measurement_basis_primary <- 20
    } else {
      components$measurement_basis_primary <- 0
    }

    # 3. schedule_density_ratio >= 0.95 (+20)
    if (!is.null(forge_pkg) && !is.null(forge_pkg$schedule_density_ratio) &&
        forge_pkg$schedule_density_ratio >= 0.95) {
      score <- score + 20
      components$schedule_density <- 20
    } else {
      components$schedule_density <- 0
    }

    # 4. factor_engine vs realized divergence < 0.3pp (+20)
    diverg <- forge_pkg$divergence_factor_engine_vs_realized_pp %||%
              forge_pkg$vs_factor_engine$divergence_pp %||% NA
    if (!is.na(diverg) && abs(diverg) < 0.3) {
      score <- score + 20
      components$divergence_low <- 20
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
      components = components, wt_dir = wt_dir
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
