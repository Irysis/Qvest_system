# v53 Sprint 2 S2.11: Role Honesty Auto-runner
# Judge S6 completion 시 artifact_validator Hook에서 자동 호출.
# Input : stage_artifacts/s6_judge_*.json (또는 s6_validation_*.json)
# Output: stage_artifacts/role_honesty_STR_*.json
#
# Usage:
#   Rscript 02_Infrastructure/validation/role_honesty_runner.R <s6_judge_path>

suppressPackageStartupMessages({
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  cat("usage: Rscript role_honesty_runner.R <s6_judge_path>\n", file = stderr())
  quit(status = 2L)
}

.s6_path <- args[1]
if (!file.exists(.s6_path)) {
  cat(sprintf("[role_honesty_runner] not found: %s\n", .s6_path), file = stderr())
  quit(status = 2L)
}

.root <- tryCatch({
  cand <- c(
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    Sys.getenv("PROJECT_ROOT", ""),
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    getwd()
  )
  out <- NA_character_
  for (p in cand) if (nzchar(p) && dir.exists(p)) { out <- p; break }
  if (is.na(out)) stop("project root not found")
  out
}, error = function(e) getwd())

source(file.path(.root, "02_Infrastructure", "validation", "role_honesty_audit.R"))

# strategy_id 추출
.s6 <- tryCatch(jsonlite::fromJSON(.s6_path, simplifyVector = FALSE),
                error = function(e) NULL)
if (is.null(.s6)) {
  cat(sprintf("[role_honesty_runner] invalid JSON: %s\n", .s6_path), file = stderr())
  quit(status = 2L)
}

.sid <- .s6$strategy_id %||% .s6$factor_id %||%
        regmatches(basename(.s6_path),
                   regexpr("STR_[0-9A-Za-z_]+", basename(.s6_path)))
.sid <- if (length(.sid) == 0 || !nzchar(.sid)) "UNKNOWN" else .sid[1]

.declared <- .s6$declared_role %||% .s6$role %||%
             .s6$provisional_role %||% "core_alpha"

# 선행 artifact 로드 (S2/S3/S4)
.load_if <- function(glob) {
  files <- Sys.glob(file.path(.root, "stage_artifacts", glob))
  if (!length(files)) return(NULL)
  tryCatch(jsonlite::fromJSON(files[1], simplifyVector = FALSE),
           error = function(e) NULL)
}

.s2 <- .load_if(sprintf("s2_profile_%s*.json", .sid))
.s3 <- .load_if(sprintf("s3_orthogonality_%s*.json", .sid))
.s4 <- .load_if(sprintf("s4_integration_%s*.json", .sid))
if (is.null(.s4)) .s4 <- .load_if(sprintf("s4_marginal_%s*.json", .sid))

.audit <- tryCatch(
  sg_audit_role_honesty(.sid, .declared, .s2, .s3, .s4, NULL),
  error = function(e) {
    cat(sprintf("[role_honesty_runner] audit error: %s\n", conditionMessage(e)),
        file = stderr())
    list(strategy_id = .sid, honest = NA, declared_role = .declared,
         detected_role = "unknown", violations = character(0),
         confidence = 0, error = conditionMessage(e))
  }
)

.audit$stage         <- "S6_ROLE_HONESTY"
.audit$strategy_id   <- .sid
.audit$source_s6     <- basename(.s6_path)
.audit$timestamp     <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
.audit$schema_version <- "v53_s2_11"

# NaN 정리 (JSON 직렬화 가능하도록)
.audit <- rapply(.audit, function(x) if (is.numeric(x) && !is.finite(x)) NA_real_ else x,
                 how = "replace")

.out <- file.path(.root, "stage_artifacts",
                  sprintf("role_honesty_%s.json", .sid))
writeLines(
  jsonlite::toJSON(.audit, pretty = TRUE, auto_unbox = TRUE, null = "null"),
  .out
)

cat(sprintf("[role_honesty_runner] %s: declared=%s detected=%s honest=%s -> %s\n",
            .sid, .audit$declared_role, .audit$detected_role,
            as.character(.audit$honest %||% "?"), .out))

# PIT check: honesty 위반이면 exit code 1 (hook이 감지)
if (isFALSE(.audit$honest) && length(.audit$violations) > 0) {
  quit(status = 1L)
}
quit(status = 0L)
