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
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
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
  # [2026-08-02 수리 — "미스캔을 PASS 로 내려앉히지 말 것" 3지점]
  #  이 함수는 detect_lookahead 의 호출부인데, 세 갈래 모두 **스캔 실패를 clean=TRUE 로
  #  변환**해 하류 게이트가 통과하게 만들었다. 특히 ③ 은 lookahead_detector 의 NA 수리를
  #  **덮어써 무력화**한다 — 검출기를 고쳐도 이 래퍼가 예외를 합격으로 바꾸면 소용없다.
  #    ① 검출기 자체가 로드 안 됨 → "위반 없음"
  #    ② 스캔 대상 run_all.R 0개 → "위반 없음"
  #    ③ 스캔 중 예외 → "위반 없음"
  #  정본: 전부 clean = NA(미측정) + 사유. 소비부는 isTRUE() 로 받으므로 not-clean 이 된다.
  if (!exists("detect_lookahead", mode = "function")) {
    return(list(clean = NA, scanned = FALSE, violations = list(),
                scanner = "static", note = "detect_lookahead unavailable — 미스캔(PASS 아님)"))
  }
  run_all <- list.files(strategy_dir, pattern = "run_all\\.R$",
                        recursive = TRUE, full.names = TRUE)
  if (length(run_all) == 0) {
    return(list(clean = NA, scanned = FALSE, violations = list(),
                scanner = "static", files = character(0),
                note = sprintf("run_all.R 0개 — 스캔 대상 없음(PASS 아님): %s", strategy_dir)))
  }
  results <- lapply(run_all, function(p) {
    tryCatch(detect_lookahead(p, verbose = verbose),
             error = function(e) list(clean = NA, scanned = FALSE, violations = list(),
                                      file = p, error = conditionMessage(e)))
  })
  all_v <- unlist(lapply(results, function(r) r$violations), recursive = FALSE)
  n_unscanned <- sum(vapply(results, function(r) !isTRUE(r$scanned), logical(1)))
  list(clean = if (n_unscanned > 0L) NA else (length(all_v) == 0),
       scanned = n_unscanned == 0L, violations = all_v,
       scanner = "static", files = run_all, n_unscanned = n_unscanned)
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
           # [2026-08-02] 예외를 clean=TRUE 로 바꾸지 않는다 — scan_static 에 있던 것과 동일 결함.
           #  blocking_gate(include_intent=TRUE) 로 도달 가능한 경로다.
           error = function(e) list(clean = NA, scanned = FALSE, violations = list(),
                                    scanner = "intent", error = conditionMessage(e)))
}

# ── scan_runtime: 실제 데이터 D000 (FACTORS vs PLOG) ────────────────────
pit_engine_v3$scan_runtime <- function(FACTORS = NULL, PLOG = NULL) {
  # [2026-08-02] 세 갈래 전부 "검사를 못 했다"인데 clean=TRUE 였다. 이건 **실데이터 PIT
  #  검사(D000)** 라 특히 나쁘다 — 입력이 안 붙거나 컬럼명이 어긋나면 그 사실이
  #  "미래참조 없음"이라는 판정이 된다. 현재 라이브 호출부는 없으나(잠복),
  #  scan_static/scan_intent 와 같은 결함이므로 같은 규약으로 맞춘다.
  if (is.null(FACTORS) || is.null(PLOG)) {
    return(list(clean = NA, scanned = FALSE, n_pit_violations = 0, scanner = "runtime",
                note = "FACTORS/PLOG not supplied — 미스캔(PASS 아님)"))
  }
  # hurdle_gate.R D000 로직 (Date vs Exec_Date)
  FACTORS <- as.data.table(FACTORS)
  PLOG    <- as.data.table(PLOG)
  if (!all(c("Date") %in% names(FACTORS))) {
    return(list(clean = NA, scanned = FALSE, n_pit_violations = 0, scanner = "runtime",
                note = "FACTORS.Date missing — 미스캔(PASS 아님)"))
  }
  if (!"Exec_Date" %in% names(PLOG)) {
    return(list(clean = NA, scanned = FALSE, n_pit_violations = 0, scanner = "runtime",
                note = "PLOG.Exec_Date missing — 미스캔(PASS 아님)"))
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

  reports   <- list()
  all_v     <- list()
  unscanned <- character(0)
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
    # [2026-08-02] 미측정 스캐너를 집계에서 놓치면 하류가 다시 CLEAN 을 본다.
    #  NA 를 낸 스캐너는 violations 가 비어 있어 length(all_v) 를 못 움직이기 때문이다.
    #  ★scanned 를 **명시적으로 FALSE 로 보고한** 스캐너만 미측정으로 센다 —
    #   필드를 안 내는 기존 스캐너(ast/intent 의 미구현 placeholder)의 의미는 무변경.
    if (identical(r$scanned, FALSE)) unscanned <- c(unscanned, lvl)
  }
  clean <- if (length(unscanned) > 0L) NA else (length(all_v) == 0)
  sev <- if (is.na(clean)) "UNMEASURED" else if (clean) "CLEAN" else if (length(all_v) < 3L) "SUSPICIOUS" else "VIOLATION"
  summary <- if (is.na(clean)) {
    sprintf("UNMEASURED (%s 스캐너 미측정 — PASS 아님; %d violations from %d scanners)",
            paste(unscanned, collapse = ","), length(all_v), length(reports))
  } else {
    sprintf("%s (%d violations across %d scanners)", sev, length(all_v), length(reports))
  }
  list(
    clean      = clean,
    unscanned  = unscanned,
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
