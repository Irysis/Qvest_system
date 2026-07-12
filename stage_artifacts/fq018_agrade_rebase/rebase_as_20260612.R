# =============================================================================
# FQ-018 — A급 원장 재베이스: AS 06-12 2건 (벤치 IKS001버그기 실측 → IKS200 교정벤치 재판정)
# 절차: (a) 보존 bt_result.rds + 저장벤치로 PORT_t 재현(파이프라인 sanity)
#       (b) pin_cache 고정 교정 benchmark.parquet로 benchmark_returns/compare 교체
#       (c) essence_score(selection_type="chain") canonical 재판정 — HARD 3종 병기
# 자체합성 금지 준수: build_benchmark_compare / essence_score 계약 함수만 사용.
# 원 L-code JSON 무수정 (원장 불변) — 산출은 본 디렉토리 JSON.
# =============================================================================
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

# --- pin benchmark (measurement-graduation §7) --------------------------------
tag <- format(Sys.time(), "fq018_%Y%m%d_%H%M%S")
pin_cache(BM_CACHE, tag)
bm <- as.data.table(arrow::read_parquet(read_pinned(BM_CACHE, tag)))
bm[, date := as.Date(Date)]
bm_corr <- bm[, .(date, benchmark_ret = BM_Ret)]
cat("[pin]", tag, "| bench rows:", nrow(bm_corr), "range:",
    format(min(bm_corr$date)), "~", format(max(bm_corr$date)), "\n")

runs <- list(
  list(id = "STR_AS_20260612_154914_1055315",
       dir = "stage_artifacts/alpha_search/20260612_154914_1055315",
       old_port_t = 2.523, old_oos = -0.191),
  list(id = "STR_AS_20260612_160537_1226361",
       dir = "stage_artifacts/alpha_search/20260612_160537_1226361",
       old_port_t = 1.938, old_oos = -0.496)
)

results <- list()
for (r in runs) {
  cat("\n==============================", r$id, "==============================\n")
  bt <- readRDS(file.path(ROOT, r$dir, "bt_result.rds"))
  pr <- as.data.table(bt$period_returns)
  pr[, date := as.Date(date)]
  br_old <- as.data.table(bt$benchmark_returns)
  br_old[, date := as.Date(date)]

  run_id <- pr$run_id[1]; strat_id <- pr$strategy_id[1]

  # (a) sanity: 저장벤치 재현 (기대값 = 원 authoritative_remeasure PORT_t)
  bc_repro <- build_benchmark_compare(pr, br_old, run_id, strat_id,
                                      annualization_factor = 252)
  t_repro <- as.numeric(bc_repro[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value])
  cat(sprintf("[sanity] stored-bench PORT_t = %.3f (원 기록 %.3f)\n", t_repro, r$old_port_t))

  # 구/교정 벤치 시계열 차이 정량화 (동일 날짜 교집합)
  bdiff <- merge(br_old[, .(date, old_ret = benchmark_ret)],
                 bm_corr[, .(date, new_ret = benchmark_ret)], by = "date")
  cum_old <- as.numeric(Return.cumulative(xts(bdiff$old_ret, bdiff$date)))
  cum_new <- as.numeric(Return.cumulative(xts(bdiff$new_ret, bdiff$date)))
  cat(sprintf("[bench-diff] n=%d cor=%.6f mean|d|=%.6f cumret old=%.2f new=%.2f\n",
              nrow(bdiff), cor(bdiff$old_ret, bdiff$new_ret),
              mean(abs(bdiff$old_ret - bdiff$new_ret)), cum_old, cum_new))

  # (b) 교정벤치 재베이스
  br_new <- bm_corr[date %in% pr$date]
  br_new_tbl <- data.table(
    benchmark_id = "KOSPI200_IKS200_corr", benchmark_name = "KOSPI 200 (IKS200 corrected)",
    date = br_new$date, frequency = "daily",
    benchmark_ret = br_new$benchmark_ret,
    benchmark_nav = cumprod(1 + br_new$benchmark_ret),
    risk_free_ret = 0, benchmark_excess_ret = br_new$benchmark_ret)
  bc_new <- build_benchmark_compare(pr, br_new_tbl, run_id, strat_id,
                                    annualization_factor = 252)
  t_new  <- as.numeric(bc_new[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value])
  ir_new <- as.numeric(bc_new[metric_name == "Information_Ratio", active_value])
  cat(sprintf("[rebase] corrected-bench PORT_t = %.3f | net_IR = %.3f\n", t_new, ir_new))

  # (c) essence 재판정 (canonical) — bt_result 사본에 교정 벤치 주입
  bt2 <- bt
  bt2$benchmark_returns <- br_new_tbl
  bt2$benchmark_compare <- bc_new
  es <- essence_score(bt2, selection_type = "chain")
  cat(sprintf("[essence v2] grade=%s port_t=%.3f oos_retention=%.3f calmar=%.3f\n",
              es$grade, as.numeric(es$essence$portfolio_alpha_t_nw_lag3),
              as.numeric(es$essence$oos_retention),
              as.numeric(es$essence$calmar)))
  # HARD 3종 판정 병기
  pt_v  <- t_new
  oos_v <- as.numeric(es$essence$oos_retention)
  cal_v <- as.numeric(es$essence$calmar)
  hard <- list(
    port_t   = list(value = pt_v,  pass = isTRUE(pt_v  >= 2.95)),
    oos_ret  = list(value = oos_v, pass = isTRUE(oos_v >= 0.7)),
    calmar   = list(value = cal_v, pass = isTRUE(cal_v >= 0.64)))
  cat(sprintf("[HARD3] PORT_t %.3f (>=2.95 %s) | oos %.3f (>=0.7 %s) | calmar %.3f (>=0.64 %s)\n",
              pt_v, hard$port_t$pass, oos_v, hard$oos_ret$pass, cal_v, hard$calmar$pass))

  results[[r$id]] <- list(
    strategy_id = r$id, pin_tag = tag,
    sanity_repro_port_t = round(t_repro, 3),
    original_port_t = r$old_port_t, original_oos = r$old_oos,
    bench_diff = list(n = nrow(bdiff), cor = round(cor(bdiff$old_ret, bdiff$new_ret), 6),
                      cum_old = round(cum_old, 3), cum_new = round(cum_new, 3)),
    rebased = list(port_t_nw_lag3 = round(t_new, 3), net_ir = round(ir_new, 3),
                   oos_retention_v2 = round(oos_v, 3), calmar = round(cal_v, 3),
                   essence_grade = es$grade,
                   oos_splits = es$oos_retention_splits),
    hard3 = hard,
    metric_type = "backtested",
    note = "FQ-018 rebase: preserved bt_result.rds period_returns + IKS200 corrected pinned bench; build_benchmark_compare + essence_score(chain) canonical path")
  cat("\n")
}

out_path <- file.path(ROOT, "stage_artifacts/fq018_agrade_rebase/rebase_results_20260712.json")
write_json(results, out_path, auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[saved]", out_path, "\n")
