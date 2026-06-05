# v53 Sprint 2 S2.12: Audit Logger — append-only 이벤트 기록
# 기존 17개 Hook 로그(/tmp/*.log)는 유지. 신규 v53 이벤트만 audit_log/로.
# 점진 전환: Sprint 2~3 동안 기존 Hook도 audit_logger 경유로 이관.
#
# 구조:
#   audit_log/YYYY-MM-DD/
#     scout/*.jsonl
#     forge/*.jsonl
#     judge/*.jsonl
#     governor/*.jsonl
#     hook/*.jsonl
#     strategy/{STR_ID}.jsonl
#
# 무결성: 각 jsonl 파일에 SHA256 chain. 일별 마지막 라인 해시를 index에 append.
#
# Usage:
#   source("02_Infrastructure/validation/audit_logger.R")
#   audit_append("judge", "grade_assigned",
#                list(strategy="STR_1631", grade="A", dsr=1.2))

suppressPackageStartupMessages({
  library(jsonlite)
})

.audit_root <- function() {
  cands <- c(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

audit_append <- function(actor, event, payload = list(),
                         strategy_id = NULL) {
  root <- .audit_root()
  day <- format(Sys.Date(), "%Y-%m-%d")
  dir <- file.path(root, "audit_log", day, actor)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)

  record <- list(
    timestamp = as.character(Sys.time()),
    actor = actor,
    event = event,
    strategy_id = strategy_id %||% NA_character_,
    payload = payload
  )

  # 해시 체인: 직전 라인 해시를 현재 레코드 prev_hash에 포함
  fname <- sprintf("%s.jsonl", event)
  fpath <- file.path(dir, fname)
  prev_hash <- NA_character_
  if (file.exists(fpath)) {
    last_line <- tryCatch(tail(readLines(fpath, warn = FALSE), 1),
                          error = function(e) "")
    if (nchar(last_line) > 0) {
      prev_hash <- digest_sha256(last_line)
    }
  }
  record$prev_hash <- prev_hash
  line <- jsonlite::toJSON(record, auto_unbox = TRUE, null = "null")
  cat(paste0(line, "\n"), file = fpath, append = TRUE)

  # 전략별 life-cycle aggregate
  if (!is.null(strategy_id) && nzchar(strategy_id) && !is.na(strategy_id)) {
    strat_dir <- file.path(root, "audit_log", day, "strategy")
    dir.create(strat_dir, showWarnings = FALSE, recursive = TRUE)
    strat_path <- file.path(strat_dir, paste0(strategy_id, ".jsonl"))
    cat(paste0(line, "\n"), file = strat_path, append = TRUE)
  }

  invisible(list(file = fpath, hash = digest_sha256(line)))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                             (length(a) == 1 && is.na(a))) b else a

digest_sha256 <- function(s) {
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(s, algo = "sha256", serialize = FALSE))
  }
  # openssl fallback
  tmp <- tempfile()
  writeLines(s, tmp)
  on.exit(unlink(tmp), add = TRUE)
  res <- tryCatch(system2("sha256sum", args = tmp,
                          stdout = TRUE, stderr = FALSE),
                  error = function(e) character(0))
  if (length(res) > 0) sub(" .*", "", res[1]) else NA_character_
}

# 전략 life-cycle 읽기
audit_life_cycle <- function(strategy_id, days = 30L) {
  root <- .audit_root()
  today <- Sys.Date()
  records <- list()
  for (d in seq(0L, days - 1L)) {
    day <- format(today - d, "%Y-%m-%d")
    path <- file.path(root, "audit_log", day, "strategy",
                      paste0(strategy_id, ".jsonl"))
    if (file.exists(path)) {
      lines <- readLines(path, warn = FALSE)
      for (ln in lines) {
        r <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE),
                      error = function(e) NULL)
        if (!is.null(r)) records[[length(records) + 1L]] <- r
      }
    }
  }
  records
}

cat("[audit_logger] Loaded. Functions: audit_append(actor, event, payload) / audit_life_cycle(strategy_id)\n")
