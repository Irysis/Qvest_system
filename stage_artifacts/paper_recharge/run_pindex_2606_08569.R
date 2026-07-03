# Driver: p-index (2606.08569) — both directions A(LOW) and B(HIGH), KR faithful.
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))
try(arrow::set_io_thread_count(1L), silent = TRUE)
try(arrow::set_cpu_thread_count(1L), silent = TRUE)
setDTthreads(1L)
options(mc.cores = 1L)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))

ENGINE <- file.path(ROOT, "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R")
IDEA <- "p-index(유럽형 put 보험료/현재가, 이항모형 closed-form) 횡단면 정렬 — 저보험료(저다운사이드) 롱"

run_one <- function(dir_tag, strat_name, idea) {
  Sys.setenv(PINDEX_DIRECTION = dir_tag)
  cat(sprintf("\n##### RUN direction=%s #####\n", dir_tag))
  res <- run_alpha_search(
    strategy_name      = strat_name,
    strategy_idea      = idea,
    factor_engine_path = ENGINE,
    n_holdings    = 25L,          # 논문 decile(SSE50 top10%≈5) vs KR 유니버스(~350) — production max25 적용(충돌 명시)
    weight_method = "equal",      # 논문: equally-weighted portfolio
    commission    = 0.0015,
    start_date    = "2005-01-01",
    universe      = "K200_KQ150",
    send_telegram = FALSE,        # 라우터가 종합 발송
    factor_analysis = TRUE
  )
  cat(sprintf("##### DONE direction=%s grade=%s out=%s #####\n",
              dir_tag, res$grade %||% "?", res$out_dir %||% "?"))
  saveRDS(res, file.path(ROOT, "stage_artifacts/paper_recharge",
                         paste0("pindex_res_", dir_tag, ".rds")))
  res
}

resA <- tryCatch(run_one("LOW",
   "STR_AS_PINDEX_LOW_2606_08569",
   paste(IDEA, "[방향A: LOW p-index 롱]")),
   error = function(e) { cat("[ERR A]", conditionMessage(e), "\n"); NULL })

resB <- tryCatch(run_one("HIGH",
   "STR_AS_PINDEX_HIGH_2606_08569",
   "p-index 횡단면 정렬 — 고보험료(고다운사이드) 롱 [방향B: HIGH p-index 롱]"),
   error = function(e) { cat("[ERR B]", conditionMessage(e), "\n"); NULL })

cat("\n===== SUMMARY =====\n")
for (nm in c("A_LOW","B_HIGH")) {
  r <- if (nm=="A_LOW") resA else resB
  if (is.null(r)) { cat(nm, ": FAILED\n"); next }
  cat(sprintf("%s: grade=%s score=%s excess=%s out=%s\n",
      nm, r$grade %||% "?", r$score %||% "?", r$excess_cagr %||% "?", r$out_dir %||% "?"))
}
cat("===== END =====\n")
