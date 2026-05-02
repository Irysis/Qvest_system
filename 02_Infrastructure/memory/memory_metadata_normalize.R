# memory_metadata_normalize.R — v7.2.1 promote helper
# 객체 입력 + 파일 입력 + dry-run + fallback chain
# 위반 시 hard fail (memory_id / canonical_statement)

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(a, b) {
  if (!is.null(a) && length(a) > 0 && nzchar(as.character(a))) a else b
}

normalize_axiom_metadata <- function(axiom = NULL,
                                      axiom_class = NULL,
                                      memory_kind = NULL,
                                      authority = NULL,
                                      review_policy = NULL,
                                      enforcement_mode = NULL,
                                      write = FALSE,
                                      path = NULL) {
  # axiom: list 객체 (직접 input) 또는 NULL (path에서 read)
  # write=FALSE: dry-run (객체 return only)
  # write=TRUE + path: file 작성

  if (is.null(axiom) && !is.null(path)) {
    axiom <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  }
  if (is.null(axiom)) {
    stop("[normalize] axiom or path required")
  }

  # ─── memory_id fallback chain ───
  axiom$memory_id <- axiom$memory_id %||%
    axiom$axiom_id %||%
    axiom$id %||%
    axiom$candidate_id
  if (is.null(axiom$memory_id) || !nzchar(as.character(axiom$memory_id))) {
    stop("[normalize] HARD FAIL — memory_id resolution failed (axiom_id/id/candidate_id 모두 부재)")
  }

  # ─── canonical_statement fallback chain ───
  axiom$canonical_statement <- axiom$canonical_statement %||%
    axiom$statement %||%
    axiom$text %||%
    axiom$statement_draft
  if (is.null(axiom$canonical_statement) || !nzchar(as.character(axiom$canonical_statement))) {
    stop("[normalize] HARD FAIL — canonical_statement resolution failed (statement/text/statement_draft 모두 부재)")
  }

  # ─── defaults ───
  defaults <- list(
    memory_kind = memory_kind %||% axiom$memory_kind %||% "axiom_active",
    axiom_class = axiom_class %||% axiom$axiom_class %||% "methodological",
    authority = authority %||% axiom$authority %||% "high",
    review_policy = review_policy %||% axiom$review_policy %||% "quarterly",
    enforcement_mode = enforcement_mode %||% axiom$enforcement_mode %||% "documented"
  )

  for (f in names(defaults)) {
    if (is.null(axiom[[f]]) || !nzchar(as.character(axiom[[f]]))) {
      axiom[[f]] <- defaults[[f]]
    }
  }

  # ─── enum validation (warn only, hard fail은 schema validation에서) ───
  valid_kinds <- c("axiom_active", "axiom_candidate", "axiom_deprecated")
  if (!axiom$memory_kind %in% valid_kinds) {
    warning(sprintf("[normalize] memory_kind '%s' outside enum (%s)",
                    axiom$memory_kind, paste(valid_kinds, collapse = "|")))
  }
  valid_modes <- c("documented", "advisory", "block", "none")
  if (!axiom$enforcement_mode %in% valid_modes) {
    warning(sprintf("[normalize] enforcement_mode '%s' outside enum (%s)",
                    axiom$enforcement_mode, paste(valid_modes, collapse = "|")))
  }

  # ─── write back ───
  if (isTRUE(write) && !is.null(path)) {
    jsonlite::write_json(axiom, path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  }

  invisible(axiom)
}

# ─── batch normalize ───
normalize_axiom_dir <- function(dir,
                                 default_memory_kind,
                                 default_authority,
                                 default_review_policy,
                                 default_enforcement_mode,
                                 write = FALSE) {
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  result <- data.frame(
    file = character(),
    memory_id = character(),
    status = character(),
    note = character(),
    stringsAsFactors = FALSE
  )
  for (f in files) {
    out <- tryCatch({
      normalize_axiom_metadata(
        path = f,
        memory_kind = default_memory_kind,
        authority = default_authority,
        review_policy = default_review_policy,
        enforcement_mode = default_enforcement_mode,
        write = write
      )
    }, error = function(e) {
      list(memory_id = basename(f), error = conditionMessage(e))
    })
    if (!is.null(out$error)) {
      result <- rbind(result, data.frame(
        file = basename(f),
        memory_id = NA_character_,
        status = "ERROR",
        note = out$error,
        stringsAsFactors = FALSE
      ))
    } else {
      result <- rbind(result, data.frame(
        file = basename(f),
        memory_id = out$memory_id,
        status = if (write) "WRITTEN" else "DRY_RUN",
        note = sprintf("kind=%s mode=%s", out$memory_kind, out$enforcement_mode),
        stringsAsFactors = FALSE
      ))
    }
  }
  result
}

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  args <- commandArgs(trailingOnly = TRUE)
  cat("[normalize] CLI selftest\n")
  test1 <- normalize_axiom_metadata(
    axiom = list(id = "AX-TEST", name = "test", text = "test statement"),
    write = FALSE
  )
  required <- c("memory_id", "memory_kind", "axiom_class", "authority",
                "review_policy", "enforcement_mode", "canonical_statement")
  stopifnot(all(required %in% names(test1)))
  cat(sprintf("  test1 PASS — memory_id=%s canonical_statement=%s\n",
              test1$memory_id, test1$canonical_statement))

  test2 <- tryCatch(
    normalize_axiom_metadata(axiom = list(name = "no_id_no_text"), write = FALSE),
    error = function(e) conditionMessage(e)
  )
  stopifnot(grepl("HARD FAIL.*memory_id", test2))
  cat("  test2 PASS — hard fail on missing memory_id\n")
  cat("[normalize] selftest 2/2 PASS\n")
}
