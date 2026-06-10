#!/usr/bin/env Rscript
# dpl_ortho_eval_contract.R — Qvest v8.x DPL 직교-피처 변형 contract-grade 평가.
#
# 비교군 (동일 OOS·동일 benchmark·동일 contract build_benchmark_compare 단일경로, NW lag-3):
#   ORTHO_grid_best  : 102f 96-cell net-Sharpe grid best (직교 피처)
#   ORTHO_DPL_C      : 102f active-alpha DPL_C (cell37 HP, 직교 피처)
#   DPL_C_90f        : 90f baseline DPL_C (기존 OOS 최고 α-t 2.906) — apples-to-apples 직교효과 격리
#   EW_top20 / MVO   : naive baselines (기존)
#   STR_1715         : incumbent (α-t 5.344, OOS retention 0.91)
# metric_type=backtested. 자체합성 금지(R Return-free; build_benchmark_compare 단일경로).
#
# IS/OOS retention: OOS active SR / IS active SR (과적합 게이트, measurement-graduation §3 oos_retention≥0.7).

suppressPackageStartupMessages({ library(arrow); library(data.table) })

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT  <- file.path(ROOT, "stage_artifacts", "WT_DPL_ORTHO")
GPU  <- file.path(ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

ym_key <- function(d) format(as.Date(d), "%Y-%m")

bm <- as.data.table(read_parquet(file.path(OUT, "benchmark_monthly.parquet")))
bm[, ymk := ym_key(date)]
bm_keyed <- bm[, .(ymk, benchmark_ret = BM_Ret_1m)]

rd <- function(p) if (file.exists(p)) as.data.table(read_parquet(p)) else NULL

# ── series 적재 ───────────────────────────────────────────────────────
series_list <- list(); is_list <- list()

ortho_best <- rd(file.path(OUT, "ortho_best_net_returns.parquet"))
if (!is.null(ortho_best)) series_list[["ORTHO_grid_best"]] <- ortho_best[, .(ymk = ym_key(date), ret_net, traded)]

ortho_c <- rd(file.path(OUT, "ortho_dplC_net_returns.parquet"))
if (!is.null(ortho_c)) series_list[["ORTHO_DPL_C"]] <- ortho_c[, .(ymk = ym_key(date), ret_net, traded)]
ortho_c_is <- rd(file.path(OUT, "ortho_dplC_is_net_returns.parquet"))
if (!is.null(ortho_c_is)) is_list[["ORTHO_DPL_C"]] <- ortho_c_is[, .(ymk = ym_key(date), ret_net, traded)]

# 90f baseline DPL_C (cbe_C_net_returns) + IS
c90 <- rd(file.path(GPU, "cbe_C_net_returns.parquet"))
if (!is.null(c90)) series_list[["DPL_C_90f"]] <- c90[, .(ymk = ym_key(date), ret_net, traded)]
c90_is <- rd(file.path(GPU, "cbe_C_is_net_returns.parquet"))
if (!is.null(c90_is)) is_list[["DPL_C_90f"]] <- c90_is[, .(ymk = ym_key(date), ret_net, traded)]

# naive baselines
base_par <- rd(file.path(GPU, "baselines_net_returns.parquet"))
if (!is.null(base_par)) for (mth in unique(base_par$method)) {
  series_list[[mth]] <- base_par[method == mth, .(ymk = ym_key(date), ret_net, traded)]
}
# incumbent STR_1715
s1715 <- rd(file.path(ROOT, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet"))
if (!is.null(s1715)) series_list[["STR_1715"]] <- s1715[, .(ymk = ym_key(date), ret_net, traded = NA_real_)]

# ── 공통 OOS 윈도우 = ORTHO_grid_best ∩ DPL_C_90f (apples-to-apples) ──
anchor <- if (!is.null(series_list[["ORTHO_grid_best"]])) series_list[["ORTHO_grid_best"]]$ymk else series_list[["ORTHO_DPL_C"]]$ymk
ref90  <- if (!is.null(series_list[["DPL_C_90f"]])) series_list[["DPL_C_90f"]]$ymk else anchor
oos_ymk <- sort(intersect(unique(anchor), unique(ref90)))

eval_one <- function(name, dt, win) {
  dt <- merge(dt[ymk %in% win], bm_keyed, by = "ymk")
  if (nrow(dt) == 0) return(NULL)
  setorder(dt, ymk)
  dates <- as.Date(paste0(dt$ymk, "-01"))
  pr <- data.table(date = dates, ret_net = dt$ret_net, frequency = "monthly")
  br <- data.table(date = dates, benchmark_ret = dt$benchmark_ret, benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, br, run_id = paste0("dpl_ortho_", name),
                                strategy_id = name, annualization_factor = 12)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }
  active <- dt$ret_net - dt$benchmark_ret
  net_sr <- mean(active) / sd(active) * sqrt(12)
  to_ann <- if (all(is.na(dt$traded))) NA_real_ else mean(dt$traded, na.rm = TRUE) * 12
  list(strategy = name, n_months = nrow(dt),
       portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
       portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
       information_ratio = getbc("Information_Ratio"),
       alpha_annualized  = getbc("Alpha_Annualized"),
       net_active_sr = net_sr, tracking_error = getbc("Tracking_Error"),
       turnover_annual = to_ann, metric_type = "backtested")
}

res <- list()
for (nm in names(series_list)) {
  r <- eval_one(nm, series_list[[nm]], oos_ymk)
  if (!is.null(r)) res[[nm]] <- r
}

# IS active SR (retention 계산용) — IS series는 자기 전체 윈도우
is_sr <- list()
for (nm in names(is_list)) {
  dt <- merge(is_list[[nm]], bm_keyed, by = "ymk"); setorder(dt, ymk)
  a <- dt$ret_net - dt$benchmark_ret
  is_sr[[nm]] <- if (length(a) > 6) mean(a) / sd(a) * sqrt(12) else NA_real_
}

cat("\n===== DPL ORTHO contract-grade comparison (OOS, NW lag-3) =====\n")
cat(sprintf("OOS window: %s .. %s (%d months)\n", oos_ymk[1], oos_ymk[length(oos_ymk)], length(oos_ymk)))
cat(sprintf("%-16s %8s %9s %8s %8s %8s %8s\n", "strategy", "alpha_t", "p_val", "IR", "net_SR", "TE", "TO/yr"))
ord <- c("ORTHO_grid_best","ORTHO_DPL_C","DPL_C_90f","EW_top20","MVO_2stage","STR_1715")
for (nm in ord) {
  if (is.null(res[[nm]])) next
  r <- res[[nm]]
  cat(sprintf("%-16s %8.3f %9.4f %8.3f %8.3f %8.3f %8s\n",
              r$strategy, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue,
              r$information_ratio, r$net_active_sr, r$tracking_error,
              ifelse(is.na(r$turnover_annual), "NA", sprintf("%.2f", r$turnover_annual))))
}
cat("\n--- IS/OOS retention (oos_retention >= 0.7 게이트, measurement-graduation §3) ---\n")
for (nm in names(is_sr)) {
  oos <- if (!is.null(res[[nm]])) res[[nm]]$net_active_sr else NA_real_
  ret <- if (!is.na(is_sr[[nm]]) && is_sr[[nm]] != 0) oos / is_sr[[nm]] else NA_real_
  cat(sprintf("  %-16s IS_SR=%6.3f  OOS_SR=%6.3f  retention=%6.3f %s\n",
              nm, is_sr[[nm]], oos, ret, ifelse(!is.na(ret) && ret >= 0.7, "[PASS]", "[fail]")))
}
cat("\nHarvey-Liu-Zhu 2016 hurdle: portfolio-alpha t >= 2.95\n")
cat("baseline 90f DPL_C: alpha_t 2.906 / net_SR 0.703 (apples-to-apples 직교효과 = ORTHO − this)\n")
cat("incumbent STR_1715: alpha_t 5.344 / net_SR 1.071 / OOS retention 0.91\n")

jsonlite::write_json(list(oos_window = c(oos_ymk[1], oos_ymk[length(oos_ymk)]),
                          n_oos_months = length(oos_ymk),
                          results = res, is_active_sr = is_sr),
                     file.path(OUT, "ortho_eval_contract.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[eval] -> %s\n", file.path(OUT, "ortho_eval_contract.json")))
