# =============================================================================
# run_hill_tail_wrapper.R
# Hill tail index (paper 2607.16450) alpha search wrapper
# Usage: Rscript 02_Infrastructure/alpha_search/run_hill_tail_wrapper.R
# =============================================================================
# Rscript -e 멀티라인 금지 규칙 준수 (MEMORY: reference-rscript-e-korean-segfault)
# =============================================================================

# 1. Project root resolution (r-portability.md: CLAUDE_PROJECT_DIR 우선)
.find_root <- function() {
  cand <- c(
    Sys.getenv("CLAUDE_PROJECT_DIR", ""),
    Sys.getenv("QM_ROOT", ""),
    getwd()
  )
  is_root <- function(p) nzchar(p) && dir.exists(p) &&
    file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in cand) if (is_root(p)) return(normalizePath(p, winslash = "/"))
  cur <- normalizePath(getwd(), winslash = "/")
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("Project root not found. Set CLAUDE_PROJECT_DIR.")
}

PROJECT_ROOT <- .find_root()
cat(sprintf("[wrapper] PROJECT_ROOT = %s\n", PROJECT_ROOT))

# 2. Source run_alpha_search
run_as_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "alpha_search", "run_alpha_search.R")
source(run_as_path)

# 3. Execute
fe_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "alpha_search", "fe_hill_tail_index.R")

result <- run_alpha_search(
  strategy_name      = "HILL_TAIL_IDX_v1",
  strategy_idea      = "Hill 극단값 분포 꼬리지수 — 252d rolling Hill estimator(k=15) 분위별 꼬리두께. 꼬리 두꺼운 종목(alpha_hill 낮음) = 극단 하방위험 프리미엄 가설",
  factor_engine_path = fe_path,
  n_holdings         = 20L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)

# 4. Print summary
cat(sprintf("\n=== RESULT SUMMARY ===\n"))
cat(sprintf("strategy_id : %s\n", result$strategy_id))
cat(sprintf("grade       : %s\n", result$grade))
cat(sprintf("score       : %.1f\n", result$score %||% 0))
cat(sprintf("pass        : %s\n", result$pass))
cat(sprintf("out_dir     : %s\n", result$out_dir))

# 5. Dump result as JSON to stdout for parsing
library(jsonlite)
cat("\n===JSON_RESULT_START===\n")
cat(toJSON(result, auto_unbox = TRUE, null = "null", na = "null"), "\n")
cat("===JSON_RESULT_END===\n")
