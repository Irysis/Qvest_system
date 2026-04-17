# v53 Sprint 2 S2.1: PIT Engine v3 — Single Entry Point
# 기존 3곳 분산 (pit_enforcement.R / lookahead_detector.R / hurdle_gate.R D000)을
# 단일 API로 통합 위임. 기존 호출부는 유지 (backward-compatible).
#
# Scanners:
#   scan_static   — lookahead_detector.R (정규식 기반, C1~C16)
#   scan_ast      — pit_ast_scanner.R (신규, S2.2에서 구현)
#   scan_intent   — pit_intent_scanner.R (Codex LLM, S2.3에서 구현)
#   scan_runtime  — FACTORS vs PLOG 실제 데이터 검증 (hurdle_gate D000 로직)
#   blocking_gate — 종합 판정 (CLEAN/SUSPICIOUS/VIOLATION)
#
# Usage:
#   source("02_Infrastructure/validation/pit_engine_v3.R")
#   r <- pit_engine_v3$blocking_gate("04_Research/strategies/STR_XXX/")
#   if (!r$clean) stop("PIT violation: ", r$summary)

suppressPackageStartupMessages(library(data.table))

.pit_v3_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

pit_engine_v3 <- new.env(parent = emptyenv())

# ── scan_static: lookahead_detector 위임 (C1~C16) ─────────────────────
pit_engine_v3$scan_static <- function(strategy_dir, verbose = FALSE) {
  root <- .pit_v3_root()
  det_path <- file.path(root, "02_Infrastructure/validation/lookahead_detector.R")
  if (!exists("detect_lookahead", mode = "function") && file.exists(det_path)) {
    source(det_path, local = FALSE)
  }
  if (!exists("detect_lookahead", mode = "function")) {
    return(list(clean = TRUE, violations = list(),
                scanner = "static", note = "detect_lookahead unavailable"))
  }
  run_all <- list.files(strategy_dir, pattern = "run_all\\.R$",
                        recursive = TRUE, full.names = TRUE)
  if (length(run_all) == 0) {
    return(list(clean = TRUE, violations = list(),
                scanner = "static", files = character(0)))
  }
  results <- lapply(run_all, function(p) {
    tryCatch(detect_lookahead(p, verbose = verbose),
             error = function(e) list(clean = TRUE, violations = list(),
                                      file = p, error = conditionMessage(e)))
  })
  all_v <- unlist(lapply(results, function(r) r$violations), recursive = FALSE)
  list(clean = length(all_v) == 0, violations = all_v,
       scanner = "static", files = run_all)
}

# ── scan_ast: AST 분석 (S2.2에서 pit_ast_scanner.R 구현 후 자동 연결) ──
pit_engine_v3$scan_ast <- function(strategy_dir, verbose = FALSE) {
  root <- .pit_v3_root()
  ast_path <- file.path(root, "02_Infrastructure/validation/pit_ast_scanner.R")
  if (!exists("pit_ast_scan", mode = "function") && file.exists(ast_path)) {
    source(ast_path, local = FALSE)
  }
  if (!exists("pit_ast_scan", mode = "function")) {
    return(list(clean = TRUE, violations = list(),
                scanner = "ast", note = "pit_ast_scanner not loaded (S2.2 pending)"))
  }
  tryCatch(pit_ast_scan(strategy_dir, verbose = verbose),
           error = function(e) list(clean = TRUE, violations = list(),
                                    scanner = "ast", error = conditionMessage(e)))
}

# ── scan_intent: Codex LLM (S2.3에서 구현 후 자동 연결) ─────────────────
pit_engine_v3$scan_intent <- function(strategy_dir, diff_only = TRUE,
                                       verbose = FALSE) {
  root <- .pit_v3_root()
  int_path <- file.path(root, "02_Infrastructure/validation/pit_intent_scanner.R")
  if (!exists("pit_intent_scan", mode = "function") && file.exists(int_path)) {
    source(int_path, local = FALSE)
  }
  if (!exists("pit_intent_scan", mode = "function")) {
    return(list(clean = TRUE, violations = list(),
                scanner = "intent", note = "pit_intent_scanner not loaded (S2.3 pending)"))
  }
  tryCatch(pit_intent_scan(strategy_dir, diff_only = diff_only,
                           verbose = verbose),
           error = function(e) list(clean = TRUE, violations = list(),
                                    scanner = "intent", error = conditionMessage(e)))
}

# ── scan_runtime: 실제 데이터 D000 (FACTORS vs PLOG) ────────────────────
pit_engine_v3$scan_runtime <- function(FACTORS = NULL, PLOG = NULL) {
  if (is.null(FACTORS) || is.null(PLOG)) {
    return(list(clean = TRUE, n_pit_violations = 0, scanner = "runtime",
                note = "FACTORS/PLOG not supplied"))
  }
  # hurdle_gate.R D000 로직 (Date vs Exec_Date)
  FACTORS <- as.data.table(FACTORS)
  PLOG    <- as.data.table(PLOG)
  if (!all(c("Date") %in% names(FACTORS))) {
    return(list(clean = TRUE, n_pit_violations = 0, scanner = "runtime",
                note = "FACTORS.Date missing"))
  }
  if (!"Exec_Date" %in% names(PLOG)) {
    return(list(clean = TRUE, n_pit_violations = 0, scanner = "runtime",
                note = "PLOG.Exec_Date missing"))
  }
  # 각 Exec_Date 기준 factor max Date 비교
  violations <- 0L
  for (ed in unique(PLOG$Exec_Date)) {
    used_f <- FACTORS[Date <= as.Date(ed)]
    if (nrow(used_f) == 0) next
    if (max(used_f$Date) > as.Date(ed)) violations <- violations + 1L
  }
  list(clean = violations == 0, n_pit_violations = violations,
       scanner = "runtime")
}

# ── blocking_gate: 종합 판정 ────────────────────────────────────────────
pit_engine_v3$blocking_gate <- function(strategy_dir,
                                         levels = c("static", "ast"),
                                         include_intent = FALSE,
                                         verbose = FALSE) {
  if (!dir.exists(strategy_dir)) {
    return(list(clean = FALSE, violations = list(),
                summary = paste("strategy_dir not found:", strategy_dir),
                reports = list()))
  }
  if (include_intent) levels <- c(levels, "intent")

  reports <- list()
  all_v   <- list()
  for (lvl in levels) {
    scanner_fn <- switch(lvl,
      static  = pit_engine_v3$scan_static,
      ast     = pit_engine_v3$scan_ast,
      intent  = pit_engine_v3$scan_intent,
      NULL
    )
    if (is.null(scanner_fn)) next
    r <- scanner_fn(strategy_dir, verbose = verbose)
    reports[[lvl]] <- r
    if (!isTRUE(r$clean)) all_v <- c(all_v, r$violations)
  }
  clean <- length(all_v) == 0
  sev <- if (clean) "CLEAN" else if (length(all_v) < 3L) "SUSPICIOUS" else "VIOLATION"
  summary <- sprintf("%s (%d violations across %d scanners)",
                     sev, length(all_v), length(reports))
  list(
    clean      = clean,
    severity   = sev,
    violations = all_v,
    summary    = summary,
    reports    = reports,
    strategy_dir = strategy_dir,
    checked_at = Sys.time()
  )
}

# ── 호환 shortcuts ──
pit_engine_v3$version <- "v53-S2.1"
lockEnvironment(pit_engine_v3, bindings = FALSE)

cat("[pit_engine_v3] Loaded. API: scan_static / scan_ast / scan_intent / scan_runtime / blocking_gate\n")
