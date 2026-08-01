# run_search.R — C_VolRankStability_3M 알파 서칭 실행 스크립트
# Rscript -e 'source(...)' 세그폴트 방지: 한글을 .R 파일에 격리

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

fe_path <- normalizePath(
  "04_Research/strategies/AS_C_VolRankStability_20260802/factor_engine.R",
  winslash = "/"
)

source("02_Infrastructure/alpha_search/run_alpha_search.R")

result <- run_alpha_search(
  strategy_name      = "C_VolRankStability_3M",
  strategy_idea      = "3M vol rank delta signal — arxiv:2607.27461 Halperin 2026: Markov vol rank, long improved rank",
  factor_engine_path = fe_path,
  n_holdings         = 20L,
  weight_method      = "ivol",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE,
  tg_dry_run         = FALSE
)

cat(sprintf("\n=== RESULT ===\ngrade=%s | score=%.1f | pass=%s\n",
            result$grade %||% "NA",
            result$score %||% NA,
            result$pass  %||% "NA"))
cat(sprintf("excess_cagr=%.2f%% | out_dir=%s\n",
            result$excess_cagr %||% NA,
            result$out_dir     %||% ""))
cat(sprintf("l_code=%s\n", result$l_code %||% ""))
