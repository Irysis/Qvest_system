#==============================================================================
# V7 Research Engine — AX_CAND 2/3 → 3rd Member Screening (Gate 14)
# ax_cand_3rd_member_screening.R
#
# Scans qepm/memory/axioms/candidates/*.json for AX_CAND entries currently
# at supporting_l_codes 2/3 (PENDING) and screens an incoming strategy/L-code
# against each PENDING family's scope. Flags 3rd member promotion candidates.
#
# Used at S6 by Judge to detect when a new VALIDATED_HARD_FAIL or
# VALIDATED_SUCCESS L-code would trigger AX promotion (3 supporting members).
#
# Reference:
#   qepm/memory/axioms/candidates/CAND_*.json (PENDING_2of3 suffix)
#   methodology_memory.md L-160/L-165 family
#   admission_rule_v3.7 retroactive_audit_required
#
# Usage:
#   source("02_Infrastructure/validation/ax_cand_3rd_member_screening.R")
#   r <- screen_ax_cand_3rd_member(
#          strategy_id      = "STR_1689",
#          provisional_l    = "L-168",
#          provisional_role = "defense",
#          family_tags      = c("SIGNAL_PORTFOLIO_TRANSLATION_FAILURE"),
#          gate_13_verdict  = "HARD_FAIL"  # from signal_portfolio_translation_audit
#        )
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

.AX_CAND_DIR <- "qepm/memory/axioms/candidates"

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ─── Load all PENDING (2/3) candidates ───────────────────────────────────────
.load_pending_candidates <- function(cand_dir = .AX_CAND_DIR) {
  if (!dir.exists(cand_dir)) {
    return(list())
  }
  files <- list.files(cand_dir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  out <- list()
  for (f in files) {
    j <- tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE),
                  error = function(e) NULL)
    if (is.null(j)) next
    n_support <- length(j$supporting_l_codes %||% list())
    is_pending_2of3 <- grepl("PENDING_2of3", basename(f), fixed = TRUE) ||
                       (n_support == 2L)
    if (is_pending_2of3) {
      out[[basename(f)]] <- list(
        path                = f,
        candidate_id        = j$candidate_id,
        type                = j$type,
        polarity            = j$polarity,
        supporting_l_codes  = unlist(j$supporting_l_codes),
        n_supporting        = n_support,
        scope_market        = j$scope_draft$market %||% NA_character_,
        scope_family        = j$scope_draft$factor_family %||% NA_character_,
        scope_universe      = j$scope_draft$universe %||% NA_character_,
        scope_tags          = unlist(j$scope_draft$tags %||% list()),
        exclusion           = unlist(j$scope_draft$exclusion %||% list())
      )
    }
  }
  out
}

# ─── Single-candidate screen ─────────────────────────────────────────────────
.screen_one <- function(cand, strategy_id, provisional_l, provisional_role,
                        family_tags, gate_13_verdict) {
  hits <- character(0); misses <- character(0)

  # Tag overlap
  tag_overlap <- intersect(toupper(family_tags %||% character(0)),
                           toupper(cand$scope_tags %||% character(0)))
  if (length(tag_overlap) > 0) {
    hits <- c(hits, sprintf("tag overlap: %s", paste(tag_overlap, collapse = ",")))
  } else {
    misses <- c(misses, "no tag overlap with candidate scope")
  }

  # Role / family alignment
  fam <- tolower(cand$scope_family %||% "")
  if (nzchar(fam) && grepl(tolower(provisional_role %||% ""), fam, fixed = TRUE)) {
    hits <- c(hits, sprintf("role aligned: %s in family '%s'", provisional_role, fam))
  }

  # Direct verdict signal (Gate 16 hard_fail = strong evidence for translation family)
  is_translation_family <- any(grepl("TRANSLATION_FAILURE",
                                     toupper(cand$scope_tags %||% character(0))))
  if (is_translation_family && identical(gate_13_verdict, "HARD_FAIL")) {
    hits <- c(hits, "Gate 16 HARD_FAIL aligns with translation failure family")
  }

  # Exclusion clause check
  excluded <- FALSE
  if (length(cand$exclusion) > 0) {
    for (ex in cand$exclusion) {
      if (grepl(tolower(provisional_role %||% ""), tolower(ex), fixed = TRUE) &&
          grepl("scope 밖", ex, fixed = TRUE)) {
        excluded <- TRUE
        misses <- c(misses, sprintf("exclusion clause matched: %s", substr(ex, 1, 80)))
      }
    }
  }

  # Verdict
  verdict <- if (excluded) {
    "EXCLUDED_BY_SCOPE"
  } else if (length(hits) >= 2) {
    "STRONG_3RD_MEMBER_CANDIDATE"
  } else if (length(hits) == 1) {
    "WEAK_3RD_MEMBER_CANDIDATE"
  } else {
    "NO_MATCH"
  }

  list(
    candidate_id        = cand$candidate_id,
    n_supporting_now    = cand$n_supporting,
    would_promote_to    = if (verdict == "STRONG_3RD_MEMBER_CANDIDATE") 3L else cand$n_supporting,
    verdict             = verdict,
    hits                = hits,
    misses              = misses,
    incoming_l_code     = provisional_l,
    incoming_strategy   = strategy_id
  )
}

#==============================================================================
# Public API
#==============================================================================
screen_ax_cand_3rd_member <- function(strategy_id,
                                      provisional_l,
                                      provisional_role  = NA_character_,
                                      family_tags       = character(0),
                                      gate_13_verdict   = NA_character_,
                                      cand_dir          = .AX_CAND_DIR,
                                      output_path       = NULL) {
  pending <- .load_pending_candidates(cand_dir)
  per_candidate <- lapply(pending, .screen_one,
                          strategy_id = strategy_id,
                          provisional_l = provisional_l,
                          provisional_role = provisional_role,
                          family_tags = family_tags,
                          gate_13_verdict = gate_13_verdict)

  # Aggregate
  n_pending <- length(per_candidate)
  strong    <- Filter(function(x) x$verdict == "STRONG_3RD_MEMBER_CANDIDATE", per_candidate)
  weak      <- Filter(function(x) x$verdict == "WEAK_3RD_MEMBER_CANDIDATE",   per_candidate)
  excluded  <- Filter(function(x) x$verdict == "EXCLUDED_BY_SCOPE",            per_candidate)

  overall <- if (length(strong) > 0) "PROMOTE_TRIGGER"
             else if (length(weak) > 0) "REVIEW_NEEDED"
             else "NO_TRIGGER"

  result <- list(
    schema_version       = "v1.0",
    gate_id              = "Gate 18 (AX_CAND 2/3 → 3rd Member Screening)",
    audited_at           = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    incoming_strategy    = strategy_id,
    incoming_l_code      = provisional_l,
    n_pending_candidates = n_pending,
    overall_verdict      = overall,
    strong_matches       = strong,
    weak_matches         = weak,
    excluded_matches     = excluded,
    per_candidate        = per_candidate,
    next_action = if (overall == "PROMOTE_TRIGGER") {
      "1) finalize incoming L-code  2) update CAND JSON supporting_l_codes (+1)  3) trigger promote.R"
    } else if (overall == "REVIEW_NEEDED") {
      "Judge custodian manual review — partial scope match, decide inclusion"
    } else {
      "No action — incoming L-code does not match any pending family"
    }
  )

  if (!is.null(output_path)) {
    dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
    result$artifact_path <- output_path
  }
  result
}

# ─── Helper: print summary ───────────────────────────────────────────────────
print_ax_cand_screening <- function(r) {
  cat("=== Gate 18 — AX_CAND 3rd Member Screening ===\n")
  cat(sprintf("Incoming: %s (%s)\n", r$incoming_strategy, r$incoming_l_code))
  cat(sprintf("Pending candidates scanned: %d\n", r$n_pending_candidates))
  cat(sprintf("Overall verdict: %s\n", r$overall_verdict))
  for (m in r$strong_matches) {
    cat(sprintf("  [STRONG] %s — would promote 2/3 → 3/3\n", m$candidate_id))
    for (h in m$hits) cat(sprintf("    + %s\n", h))
  }
  for (m in r$weak_matches) {
    cat(sprintf("  [WEAK]   %s — review needed\n", m$candidate_id))
  }
  for (m in r$excluded_matches) {
    cat(sprintf("  [EXCL]   %s — scope excluded\n", m$candidate_id))
  }
  cat(sprintf("Next: %s\n", r$next_action))
}
