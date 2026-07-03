# Single-direction driver A (LOW) — isolate segfault.
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
try(arrow::set_io_thread_count(1L), silent = TRUE)
try(arrow::set_cpu_thread_count(1L), silent = TRUE)
setDTthreads(1L); options(mc.cores = 1L)
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1")

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))
ENGINE <- file.path(ROOT, "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R")
Sys.setenv(PINDEX_DIRECTION = "LOW")
res <- run_alpha_search(
  strategy_name      = "STR_AS_PINDEX_LOW_2606_08569",
  strategy_idea      = "p-index(이항 put 보험료/현재가) 횡단면 정렬 — 저보험료(저다운사이드) 롱 [방향A]",
  factor_engine_path = ENGINE,
  n_holdings    = 25L, weight_method = "equal", commission = 0.0015,
  start_date    = "2005-01-01", universe = "K200_KQ150",
  send_telegram = FALSE, factor_analysis = TRUE)
saveRDS(res, file.path(ROOT, "stage_artifacts/paper_recharge/pindex_res_LOW.rds"))
cat(sprintf("\n[A DONE] grade=%s score=%s excess=%s out=%s\n",
            res$grade %||% "?", res$score %||% "?", res$excess_cagr %||% "?", res$out_dir %||% "?"))
