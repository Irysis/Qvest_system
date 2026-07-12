# FQ-018 보조검증 — AS 07-09 건 (측정 07-09 = IKS200 수리 후이나 rawdata 4월-소실 복구(07-11)·벤치 캐시 07-12 갱신 이전)
# 보존 bt_result.rds를 07-12 pinned 교정벤치로 재판정 (canonical: build_benchmark_compare + essence_score)
suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
  library(jsonlite); library(arrow)
})
data.table::setDTthreads(1L)
arrow::set_io_thread_count(2)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/data/pin_cache.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"))

tag <- format(Sys.time(), "fq018b_%Y%m%d_%H%M%S")
pin_cache(BM_CACHE, tag)
bm <- as.data.table(arrow::read_parquet(read_pinned(BM_CACHE, tag)))
bm[, date := as.Date(Date)]
bm_corr <- bm[, .(date, benchmark_ret = BM_Ret)]

dirp <- "stage_artifacts/alpha_search/20260709_074129_30048"
bt <- readRDS(file.path(ROOT, dirp, "bt_result.rds"))
pr <- as.data.table(bt$period_returns); pr[, date := as.Date(date)]
br_old <- as.data.table(bt$benchmark_returns); br_old[, date := as.Date(date)]
run_id <- pr$run_id[1]; strat_id <- pr$strategy_id[1]

bc_repro <- build_benchmark_compare(pr, br_old, run_id, strat_id, annualization_factor = 252)
t_repro <- as.numeric(bc_repro[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value])
cat(sprintf("[sanity] stored-bench PORT_t = %.3f (원 기록 2.584)\n", t_repro))

bdiff <- merge(br_old[, .(date, old_ret = benchmark_ret)],
               bm_corr[, .(date, new_ret = benchmark_ret)], by = "date")
cat(sprintf("[bench-diff] n=%d cor=%.6f mean|d|=%.8f n_differing=%d\n",
            nrow(bdiff), cor(bdiff$old_ret, bdiff$new_ret),
            mean(abs(bdiff$old_ret - bdiff$new_ret)),
            sum(abs(bdiff$old_ret - bdiff$new_ret) > 1e-10)))

br_new <- bm_corr[date %in% pr$date]
br_new_tbl <- data.table(
  benchmark_id = "KOSPI200_IKS200_corr", benchmark_name = "KOSPI 200 (IKS200 corrected, 20260712 cache)",
  date = br_new$date, frequency = "daily",
  benchmark_ret = br_new$benchmark_ret,
  benchmark_nav = cumprod(1 + br_new$benchmark_ret),
  risk_free_ret = 0, benchmark_excess_ret = br_new$benchmark_ret)
bc_new <- build_benchmark_compare(pr, br_new_tbl, run_id, strat_id, annualization_factor = 252)
t_new  <- as.numeric(bc_new[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value])

bt2 <- bt; bt2$benchmark_returns <- br_new_tbl; bt2$benchmark_compare <- bc_new
es <- essence_score(bt2, selection_type = "chain")
cat(sprintf("[rebase 0712-pin] PORT_t=%.3f oos=%.3f calmar=%.3f grade=%s\n",
            t_new, as.numeric(es$essence$oos_retention), as.numeric(es$essence$calmar), es$grade))
cat(sprintf("[HARD3] PORT_t %s | oos %s | calmar %s\n",
            t_new >= 2.95, as.numeric(es$essence$oos_retention) >= 0.7,
            as.numeric(es$essence$calmar) >= 0.64))

res <- list(strategy_id = strat_id, pin_tag = tag, sanity_repro = round(t_repro, 3),
            original_port_t = 2.584, original_oos = -0.052,
            rebased = list(port_t = round(t_new, 3),
                           oos_retention_v2 = round(as.numeric(es$essence$oos_retention), 3),
                           calmar = round(as.numeric(es$essence$calmar), 3),
                           essence_grade = es$grade))
write_json(res, file.path(ROOT, "stage_artifacts/fq018_agrade_rebase/verify_as_20260709.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("[saved] verify_as_20260709.json\n")
