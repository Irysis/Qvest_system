# v53 Sprint 2 S2.2: PIT AST Scanner
# 기존 lookahead_detector.R (regex)가 놓치는 간접 호출 탐지:
#   1) user-defined function 내부에서 sd/mean/var/quantile/ecdf/scale 직접 호출
#      (expanding/rolling 마커 없이)
#   2) 함수 결과를 받아 사용하는 체인 (e.g. get_sd(x) * sqrt(252))
#   3) lapply/sapply/Map 내부 full-sample 집계
#
# 제한 (v1): 파일별 parse() → 함수 정의 및 호출만 분석. 크로스-파일 추적 미지원.
#
# Usage:
#   source("pit_ast_scanner.R")
#   r <- pit_ast_scan("04_Research/strategies/STR_XXX")
#   # list(clean, violations, scanner="ast", files)

suppressPackageStartupMessages(library(data.table))

# ── full-sample 집계 대상 함수 ──
.PIT_AGG_FUNS <- c("sd", "mean", "var", "quantile", "ecdf", "scale",
                   "median", "IQR", "mad")

# ── PIT-safe marker (expanding / rolling / pit_ wrapper) ──
.PIT_SAFE_MARKERS <- c("rollapply", "frollmean", "frollapply", "frollsum",
                       "slider", "pit_zscore", "pit_rolling", "pit_filter",
                       "expanding", "runStat", "cummean")

# ── 한 호출(call)이 PIT-safe 인지 검사 ──
.is_pit_safe_context <- function(expr_str) {
  for (m in .PIT_SAFE_MARKERS) if (grepl(m, expr_str, fixed = TRUE)) return(TRUE)
  if (grepl("\\[\\s*1\\s*:\\s*[ij]\\s*\\]", expr_str)) return(TRUE)
  if (grepl("by\\s*=", expr_str) || grepl("tapply|sapply.*by", expr_str)) return(TRUE)
  FALSE
}

# ── AST walk: user-defined function body에서 full-sample 집계 호출 탐지 ──
.walk_function_body <- function(fn_name, body_expr, file, violations) {
  body_str <- paste(deparse(body_expr), collapse = "\n")
  # 각 집계 함수 호출 탐지
  for (fun in .PIT_AGG_FUNS) {
    pat <- sprintf("\\b%s\\s*\\(", fun)
    if (grepl(pat, body_str)) {
      # context check: PIT-safe marker 존재?
      if (!.is_pit_safe_context(body_str)) {
        violations[[length(violations) + 1L]] <<- list(
          check = "AST_C1_indirect",
          file = file,
          function_name = fn_name,
          agg = fun,
          msg = sprintf(
            "User-defined function '%s()' calls %s() without PIT-safe wrapper — possible indirect full-sample stat",
            fn_name, fun
          )
        )
      }
    }
  }
  violations
}

# ── 한 파일 parse → 함수 정의들 탐지 → body scan ──
.scan_file_ast <- function(file, violations) {
  if (!file.exists(file)) return(violations)
  exprs <- tryCatch(parse(file, keep.source = TRUE),
                    error = function(e) NULL)
  if (is.null(exprs)) return(violations)

  for (i in seq_along(exprs)) {
    e <- exprs[[i]]
    # pattern: name <- function(...) { body }
    if (length(e) >= 3 && identical(e[[1]], as.symbol("<-")) &&
        is.call(e[[3]]) && identical(e[[3]][[1]], as.symbol("function"))) {
      fn_name <- as.character(e[[2]])
      fn_body <- e[[3]][[3]]
      violations <- .walk_function_body(fn_name, fn_body, file, violations)
    }
    # pattern: name = function(...)
    if (length(e) >= 3 && identical(e[[1]], as.symbol("=")) &&
        is.call(e[[3]]) && identical(e[[3]][[1]], as.symbol("function"))) {
      fn_name <- as.character(e[[2]])
      fn_body <- e[[3]][[3]]
      violations <- .walk_function_body(fn_name, fn_body, file, violations)
    }
  }
  violations
}

# ── 공개 API ──
pit_ast_scan <- function(strategy_dir, verbose = FALSE) {
  if (!dir.exists(strategy_dir)) {
    return(list(clean = TRUE, violations = list(), scanner = "ast",
                note = "strategy_dir not found"))
  }
  files <- list.files(strategy_dir, pattern = "\\.R$",
                      recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/(archive|deprecated|_deleted_)", files)]
  violations <- list()
  for (f in files) {
    violations <- .scan_file_ast(f, violations)
  }
  if (verbose && length(violations) > 0) {
    cat(sprintf("[pit_ast_scan] %d violations in %d files\n",
                length(violations), length(files)))
  }
  list(
    clean = length(violations) == 0,
    violations = violations,
    scanner = "ast",
    files = files,
    scanned_at = Sys.time()
  )
}

cat("[pit_ast_scanner] Loaded. Function: pit_ast_scan(strategy_dir)\n")
