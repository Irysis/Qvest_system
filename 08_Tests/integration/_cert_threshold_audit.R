#==============================================================================
# _cert_threshold_audit.R — v7.1-lite Sprint 0.2 strictness test
#
# Goal: cert_rules.R::cr_check_* 함수 본문에서 numeric threshold literal 0건 검증.
# Comment / sprintf format string의 string literal "0.95" / "3" 등은 허용.
# 함수 body 안의 NUM_CONST (parser AST)만 검출.
#
# Allow list (legitimate numeric literals):
#   - 0L (zero default)
#   - 1 (single increment)
#   - %||% list() / list() 안의 정상 수치
# Strict block:
#   - 0.95 / 50 / 3 (threshold values from cert_rules.json)
#   - >= 50 / >= 3 / < 0.95 등 비교 literal (이전 hardcode 패턴)
#
# Plan: v7-1-cheerful-balloon.md Sprint 0.2 R2-1 미세조정
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

CERT_RULES_PATH <- "02_Infrastructure/worktask/cert_rules.R"
TARGET_FUNCTIONS <- c("cr_check_alpha_discovery",
                     "cr_check_sr_provenance",
                     "cr_check_forge_package_validated",
                     "cr_check_schedule_fidelity")
# cr_check_governor_concord은 별개 logic (book_state vs admission, < 0.01 tolerance retain 허용)

# Threshold values to forbid in function bodies (matches cert_rules.json)
# Note: round(x, 3L) precision은 false positive — `3L` 또는 round() 함수 인자는 audit 무시.
# Numeric literal "3" without L suffix는 hardcoded threshold 신호로 간주.
FORBIDDEN_LITERALS <- c("0.95", "50", "3")
# Allow if literal is "3L" (integer L suffix) — rounding precision 등 정합 사용
ALLOW_INT_SUFFIX <- TRUE

cat("=== v7.1-lite Sprint 0.2 cert_rules.R Threshold Audit ===\n\n")

# Parse with srcref enabled
parsed <- parse(CERT_RULES_PATH, keep.source = TRUE)
src <- attr(parsed, "srcref")

violations <- list()

for (i in seq_along(parsed)) {
  expr <- parsed[[i]]
  # Check if this is a function assignment for one of our targets
  if (length(expr) >= 3 &&
      identical(as.character(expr[[1]]), "<-") &&
      length(expr[[2]]) == 1) {
    fn_name <- as.character(expr[[2]])
    if (fn_name %in% TARGET_FUNCTIONS) {
      # Get function body srcref
      fn_src <- src[[i]]
      body_lines <- as.character(fn_src)

      # Walk body AST for NUM_CONST tokens
      body_expr <- expr[[3]]  # function(...) { body }
      pd <- getParseData(parse(text = paste(body_lines, collapse = "\n"),
                                keep.source = TRUE))

      if (!is.null(pd) && nrow(pd) > 0) {
        num_consts <- pd[pd$token == "NUM_CONST", , drop = FALSE]
        for (r in seq_len(nrow(num_consts))) {
          val <- num_consts$text[r]
          has_int_suffix <- grepl("L$", val)
          val_clean <- gsub("L$", "", val)
          # Allow integer L-suffix literals (rounding precision, indices, etc.)
          if (has_int_suffix && ALLOW_INT_SUFFIX) next
          if (val_clean %in% FORBIDDEN_LITERALS) {
            violations[[length(violations) + 1]] <- list(
              function_name = fn_name,
              line = num_consts$line1[r],
              literal = val,
              context = body_lines[num_consts$line1[r]] %||% ""
            )
          }
        }
      }
    }
  }
}

`%||%` <- function(a, b) if (is.null(a)) b else a

if (length(violations) == 0) {
  cat(sprintf("[PASS] %d target functions audited, 0 hardcoded threshold literals\n",
              length(TARGET_FUNCTIONS)))
  for (fn in TARGET_FUNCTIONS) {
    cat(sprintf("  ✅ %s — clean\n", fn))
  }
  cat("\n=== Audit PASS ===\n")
  quit(status = 0)
} else {
  cat(sprintf("[FAIL] %d threshold literal violations:\n", length(violations)))
  for (v in violations) {
    cat(sprintf("  ❌ %s line %d: literal '%s'\n",
                v$function_name, v$line, v$literal))
    cat(sprintf("       context: %s\n", trimws(v$context)))
  }
  cat("\n=== Audit FAIL — fix by reading from cert_rules.json ===\n")
  quit(status = 1)
}
