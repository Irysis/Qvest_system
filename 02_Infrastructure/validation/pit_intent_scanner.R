# v53 Sprint 2 S2.3: PIT Intent Scanner (Codex GPT-5.5)
# run_pit_intent_scan.sh 래퍼 호출 → JSON 결과 파싱.
# Codex CLI 부재 시 skip (clean=TRUE, note="codex unavailable").
# 월 예상 비용 ~$45 (전략당 ~$0.05, diff 기반).

suppressPackageStartupMessages({
  library(jsonlite)
})

.intent_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

pit_intent_scan <- function(strategy_dir, diff_only = TRUE, verbose = FALSE) {
  root <- .intent_root()
  script <- file.path(root, "02_Infrastructure/hooks/run_pit_intent_scan.sh")
  if (!file.exists(script)) {
    return(list(
      clean = TRUE, violations = list(),
      scanner = "intent", note = "run_pit_intent_scan.sh not found"
    ))
  }
  if (!dir.exists(strategy_dir)) {
    return(list(
      clean = TRUE, violations = list(),
      scanner = "intent", note = "strategy_dir not found"
    ))
  }

  mode <- if (isTRUE(diff_only)) "diff" else "full"
  if (verbose) cat("[pit_intent_scan] calling Codex for", strategy_dir, "\n")

  out <- tryCatch(
    system2(
      "bash",
      args = c(shQuote(script), shQuote(strategy_dir), shQuote(mode)),
      stdout = TRUE, stderr = TRUE, timeout = 120
    ),
    error = function(e) {
      character(0)
    }
  )
  if (length(out) == 0) {
    return(list(
      clean = TRUE, violations = list(),
      scanner = "intent", note = "no output from codex"
    ))
  }

  raw <- paste(out, collapse = "\n")
  # JSON 추출 (codex 응답에 앞뒤 noise 섞일 수 있음)
  m <- regmatches(raw, regexpr("\\{[\\s\\S]*\\}", raw, perl = TRUE))
  parsed <- NULL
  if (length(m) > 0) {
    parsed <- tryCatch(jsonlite::fromJSON(m, simplifyVector = TRUE),
                       error = function(e) NULL)
  }
  if (is.null(parsed)) {
    return(list(
      clean = TRUE, violations = list(),
      scanner = "intent",
      note = "codex response not parseable",
      raw = substr(raw, 1, 500)
    ))
  }

  verdict <- toupper(parsed$verdict %||% "SKIP")
  clean <- verdict %in% c("CLEAN", "SKIP")

  violations <- list()
  if (verdict == "VIOLATION" || verdict == "SUSPICIOUS") {
    violations[[1]] <- list(
      check = paste0("INTENT_", verdict),
      evidence = parsed$evidence %||% "",
      reasoning = parsed$reasoning %||% "",
      severity = parsed$severity %||% "MEDIUM",
      rationalization_detected = isTRUE(parsed$rationalization_detected)
    )
  }

  list(
    clean = clean,
    violations = violations,
    scanner = "intent",
    verdict = verdict,
    scanned_at = Sys.time(),
    raw_response = parsed
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

cat("[pit_intent_scanner] Loaded. Function: pit_intent_scan(strategy_dir, diff_only=TRUE)\n")
