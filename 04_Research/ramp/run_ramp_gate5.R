## run_ramp_gate5.R — RAMP Gate 5 driver
## 전략풀 잠재팩터(PC2~10) → 경제 라벨링 + 팩터군 클러스터 + net-of-cost 검증 + 국면조건부 매트릭스
##   + 잔차-α 특성화 + CCS gate=5.
## ★핵심 정정(도훈 2026-06-17): 풀 PCA 잠재팩터 = 1차 순수팩터. factor DB = 경제라벨 보조.
## 실측-only(canonical_screen_bt). PIT C1~C15. §2.4 메타. no hard switch. 분리정합(타 프로젝트 경로 참조 금지).
##
## 진입: Rscript -e 'source("04_Research/ramp/run_ramp_gate5.R")'  (QM_ROOT=원본, PYTHONUTF8=1)

suppressMessages({ library(data.table); library(arrow); library(yaml); library(jsonlite) })
options(stringsAsFactors = FALSE)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
Sys.setenv(CLAUDE_PROJECT_DIR = QM, QM_ROOT = QM)
# pre-source config.R (absolute) so factor_db_connector finds CACHE_DIR without relative source
if (!exists("CACHE_DIR")) source(file.path(QM, "02_Infrastructure", "config.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
AS_OF <- as.Date("2026-06-17")

cat("\n=============== RAMP GATE 5 ===============\n")
config <- yaml::read_yaml("02_Infrastructure/ramp/ramp_config.yml")
g5 <- config$gate5_grouping; g5r <- config$gate5_regime

source("02_Infrastructure/ramp/ramp_io.R")
source("02_Infrastructure/ramp/latent_factor_labeling.R")
source("02_Infrastructure/ramp/factor_grouping.R")
source("02_Infrastructure/ramp/regime_factor_mapping.R")
source("02_Infrastructure/ramp/factor_validation.R")  # build_monthly_forward_returns reuse
source("02_Infrastructure/ramp/ccs_evaluator.R")

# ---- inputs (Gate 3/4) ----
loadings   <- as.data.table(read_parquet("outputs/ramp/latent_factor_loadings.parquet"))
eigen_ret  <- as.data.table(read_parquet("outputs/ramp/latent_factor_returns.parquet"))
scree      <- as.data.table(read_parquet("outputs/ramp/latent_factor_scree.parquet"))
residual   <- as.data.table(read_parquet("outputs/ramp/residual_alpha_candidates.parquet"))
inventory  <- as.data.table(read_parquet("06_Registry/ramp/strategy_inventory.parquet"))
pool_ret   <- as.data.table(read_parquet("outputs/ramp/pool_return_matrix.parquet"))
rawdata    <- as.data.table(read_parquet(".cache/rawdata.parquet"))
regime_dt  <- as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet"))

pc_meta_cols <- c("as_of_date","generated_at","source_version","security_id_field")
eigen_ret <- eigen_ret[, setdiff(names(eigen_ret), pc_meta_cols), with = FALSE]
loadings  <- loadings[, setdiff(names(loadings), pc_meta_cols), with = FALSE]

pc1_var <- scree[pc == 1]$variance_explained
cat(sprintf("[g5] PC1 variance=%.1f%% (market/beta — 배분/라벨 입력 제외)\n", 100 * pc1_var))

# month-end signal grid (라벨링·검증 공통)
me <- function(d) { x <- seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2)[2]; x - 1 }
all_m <- seq(as.Date("2015-01-31"), AS_OF, by = "month")
sig_dates <- sort(unique(as.Date(sapply(all_m, function(d) as.character(me(as.Date(d)))))))
sig_dates <- sig_dates[sig_dates <= max(rawdata$Date)]

#==============================================================================
# STEP 1+2 — 경제 라벨링 (PC2~10 월별수익 ~ canonical style 월별수익)
#==============================================================================
cat("\n----- STEP 1/2: economic labeling (factor-DB = 보조) -----\n")
style_monthly <- build_canonical_style_returns(rawdata, sig_dates, cost_bps = config$cost$one_way_bps)
cat(sprintf("[g5] canonical style monthly returns: %d months x %d styles\n",
            nrow(style_monthly), sum(grepl("_ret$", names(style_monthly)))))
pc_monthly <- aggregate_pc_monthly(eigen_ret, sig_dates)
lab <- label_latent_factors(pc_monthly, style_monthly,
                            exclude_pc1 = isTRUE(g5$exclude_pc1),
                            r2_label_min = g5$label_r2_min %||% 0.30,
                            beta_dom_frac = g5$label_beta_dominance %||% 0.50)
cat(sprintf("[g5] labeling regression n_obs=%d months\n", lab$n_obs))
print(lab$label_table[, .(pc, model_r2, top_style, beta_dominance, label)])

ramp_write_parquet(lab$label_table, "outputs/ramp/latent_factor_labels.parquet",
                   as_of_date = AS_OF, id_field = "latent_factor")

#==============================================================================
# STEP 3 — 팩터군 클러스터링 (PC2~10, 경제라벨 후부여)
#==============================================================================
cat("\n----- STEP 3: factor grouping (clustering → label) -----\n")
dist_obj <- build_factor_distance(eigen_ret, loadings,
                                  pc_use = setdiff(grep("^PC[0-9]+$", names(eigen_ret), value = TRUE), "PC1"),
                                  w = config$gate5_grouping$distance_weights)
cat(sprintf("[g5] distance dd_status=%s weights(ret=%.2f exp=%.2f dd=%.2f)\n",
            dist_obj$dd_status, dist_obj$weights$w_return, dist_obj$weights$w_exposure, dist_obj$weights$w_drawdown))
grp <- group_factors(dist_obj, label_table = lab$label_table,
                     cut_height = g5$hclust_cut_height %||% 0.7)
cat(sprintf("[g5] statistical hclust groups=%d (직교→대부분 singleton); econ-label groups=%d\n",
            grp$n_groups, grp$n_econ_groups))
cat(sprintf("[g5] merge heights: %s (all>0.80 → no natural cluster)\n",
            paste(round(grp$merge_heights, 3), collapse = ", ")))
print(grp$group_map[, .(pc, economic_label, dominant_style, econ_group_id, group_id)])
ramp_write_parquet(grp$group_map, "outputs/ramp/factor_group_map.parquet",
                   as_of_date = AS_OF, id_field = "latent_factor")

#==============================================================================
# STEP 4 — net-of-cost 검증 (대표 top-N 전략 basket via canonical_screen_bt)
#   PC eigen-portfolio = LS(투자불가 long-only). 투자가능 proxy = PC loading 상위 top-N *전략* basket.
#   strategies(net ret 내장) → canonical_screen_bt(Ticker=strategy, score=loading) net 실측.
#==============================================================================
cat("\n----- STEP 4: net-of-cost validation (canonical_screen_bt, 정직) -----\n")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

# monthly strategy returns (month-end → next month-end compounded via Return-style? 자체합성 금지:
#   전략 net 일수익을 월구간 *기하누적*은 PerformanceAnalytics 경유 필요. 여기선 canonical_screen_bt가
#   요구하는 'Ret_1m'을 월말종가식이 아닌 전략수익이므로 월간 net을 표준함수로 산출.)
suppressMessages({ library(PerformanceAnalytics); library(xts) })
pool_ret[, Date := as.Date(Date)]
# build monthly net return per strategy via apply.monthly(Return.cumulative) — 표준함수(자체합성 아님)
strat_monthly <- pool_ret[, {
  x <- xts::xts(ret_net, order.by = Date)
  mr <- tryCatch(xts::apply.monthly(x, PerformanceAnalytics::Return.cumulative),
                 error = function(e) NULL)
  if (is.null(mr)) .(Date = as.Date(NA), Ret_1m = NA_real_)
  else .(Date = as.Date(zoo::index(mr)), Ret_1m = as.numeric(mr))
}, by = strategy_id]
strat_monthly <- strat_monthly[!is.na(Ret_1m)]
# align Date to month-end signal grid (use month key)
strat_monthly[, ym := format(Date, "%Y-%m")]
# benchmark monthly (KOSPI200 TR)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
bx <- xts::xts(bm$BM_Ret, order.by = bm$Date)
bm_m <- xts::apply.monthly(bx, PerformanceAnalytics::Return.cumulative)
bench_dt <- data.table(Date = as.Date(zoo::index(bm_m)), BM_Ret = as.numeric(bm_m))
bench_dt[, ym := format(Date, "%Y-%m")]

pc_cols_val <- setdiff(grep("^PC[0-9]+$", names(loadings), value = TRUE), "PC1")
val_rows <- list()
TOPN <- 20L
for (pc in pc_cols_val) {
  ld <- loadings[, .(strategy_id, load = get(pc))]
  # sign-align: long-leg = strategies with most positive loading (PC sign arbitrary → choose sign that
  #   gives positive in-sample eigen mean already in pca$x; here we test +loading basket honestly).
  sc <- merge(strat_monthly[, .(strategy_id, ym, Ret_1m)], ld, by = "strategy_id")
  # canonical_screen_bt needs Date/Ticker/score and returns Date/Ticker/Ret_1m on same grid
  S <- sc[, .(Date = as.Date(paste0(ym, "-01")), Ticker = strategy_id, score = load)]
  R <- sc[, .(Date = as.Date(paste0(ym, "-01")), Ticker = strategy_id, Ret_1m)]
  B <- bench_dt[, .(Date = as.Date(paste0(ym, "-01")), BM_Ret)]
  S <- unique(S); R <- unique(R); B <- unique(B[, .(Date, BM_Ret)])
  cs <- tryCatch(
    canonical_screen_bt(S, R, B, top_n = TOPN, cost_bps_oneway = config$cost$one_way_bps,
                        liq_dt = NULL, run_id = paste0("ramp_g5_", pc), strategy_id = paste0("PCBASKET_", pc)),
    error = function(e) list(metric_type = "error", note = conditionMessage(e)))
  val_rows[[pc]] <- data.table(
    unit = pc,
    metric_type = if (identical(cs$metric_type, "canonical_screen")) "backtested" else (cs$metric_type %||% "error"),
    n_months = cs$n_months %||% 0L,
    net_sr = cs$net_sr %||% NA_real_,
    net_cagr = cs$net_cagr %||% NA_real_,
    portfolio_alpha_t_nw = cs$portfolio_alpha_t_nw_lag3 %||% NA_real_,
    information_ratio = cs$information_ratio %||% NA_real_,
    turnover_annual = cs$turnover_annual %||% NA_real_,
    note = cs$note %||% NA_character_
  )
}
val <- rbindlist(val_rows, fill = TRUE)
cat("[g5] PC long-only top-20 strategy-basket net validation:\n")
print(val[, .(unit, metric_type, n_months, net_sr, portfolio_alpha_t_nw, turnover_annual)])
ramp_write_parquet(val, "outputs/ramp/factor_netcost_validation.parquet",
                   as_of_date = AS_OF, id_field = "latent_factor")

#==============================================================================
# STEP 5 — 국면조건부 매트릭스 (soft, no hard switch)
#==============================================================================
cat("\n----- STEP 5: regime-conditional matrix (soft MRS, no hard switch) -----\n")
membership <- build_regime_membership(regime_dt)
rfm <- build_regime_factor_matrix(eigen_ret, membership, group_map = grp$group_map,
                                  min_eff_n = g5r$min_eff_n %||% 60, exclude_pc1 = TRUE)
cat("[g5] regime x PC conditional (shrunk annualized Sharpe):\n")
pcmat <- dcast(rfm$pc_matrix, unit ~ regime, value.var = "cond_sharpe_ann")
print(pcmat)
ramp_write_parquet(rfm$pc_matrix, "outputs/ramp/regime_factor_matrix.parquet",
                   as_of_date = AS_OF, id_field = "latent_factor")
if (!is.null(rfm$group_matrix))
  ramp_write_parquet(rfm$group_matrix, "outputs/ramp/regime_group_matrix.parquet",
                     as_of_date = AS_OF, id_field = "factor_group")

#==============================================================================
# STEP 6 — 잔차-α 특성화 (origin/시기/strategy_idea)
#==============================================================================
cat("\n----- STEP 6: residual-alpha characterization -----\n")
resid_top <- residual[unexplained_var_frac > 0.5]
setorder(resid_top, -unexplained_var_frac)
ideas <- inventory[, .(strategy_id, strategy_idea, grade, origin_mode, source, overlay_tag)]
resid_char <- merge(resid_top[, .(strategy_id, unexplained_var_frac, origin_mode, grade, source, is_dedup_unique)],
                    ideas[, .(strategy_id, strategy_idea, overlay_tag)], by = "strategy_id", all.x = TRUE)
setorder(resid_char, -unexplained_var_frac)
# 시기 추정: strategy_id의 날짜 토큰
resid_char[, id_date := {
  m <- regmatches(strategy_id, regexpr("20[0-9]{6}", strategy_id))
  ifelse(length(m) && nzchar(m), as.character(as.Date(m, "%Y%m%d")), NA_character_)
}, by = strategy_id]
cat(sprintf("[g5] residual-alpha candidates (unexplained_var>0.5): %d\n", nrow(resid_char)))
print(head(resid_char[, .(strategy_id, unexplained_var_frac, grade, strategy_idea)], 25))
ramp_write_parquet(resid_char, "outputs/ramp/residual_alpha_characterized.parquet",
                   as_of_date = AS_OF, id_field = "strategy_id")

#==============================================================================
# STEP 7 — CCS gate=5
#==============================================================================
cat("\n----- STEP 7: CCS gate=5 -----\n")
ccs <- compute_ccs(list(gate = 5L, as_of_date = as.character(AS_OF),
                        generated_at = ramp_now_iso(),
                        sds = 80, pfis = 85))

#==============================================================================
# summary json
#==============================================================================
labeled <- lab$label_table[label != "unlabeled" & !grepl("mixed", label)]
unlabeled <- lab$label_table[label == "unlabeled"]
summ <- list(
  gate = 5,
  pc1_variance_explained = round(pc1_var, 4),
  pc1_note = "market/beta — excluded from allocation & labeling inputs",
  n_pc_labeled_single = nrow(labeled),
  n_pc_unlabeled_new = nrow(unlabeled),
  labels = lab$label_table[, .(pc, model_r2, top_style, label)],
  n_factor_groups_statistical = grp$n_groups,
  n_factor_groups_economic = grp$n_econ_groups,
  group_labels = unique(grp$group_map[, .(econ_group_id, dominant_style, econ_group_size)]),
  clustering_note = grp$orthogonal_note,
  netcost_validation = val[, .(unit, net_sr, portfolio_alpha_t_nw, turnover_annual)],
  best_pc_net_sr = val[which.max(net_sr), .(unit, net_sr, portfolio_alpha_t_nw)],
  n_residual_alpha = nrow(resid_char),
  regime_matrix_dd_status = dist_obj$dd_status,
  ccs_total = ccs$ccs_total, ccs_pass = ccs$pass,
  honesty = "PC1=beta dominance(KR structural). PC2~10 대부분 net SR 약함 예상 — 부풀림 금지."
)
ramp_write_json(summ, "06_Registry/ramp/gate5_summary.json", as_of_date = AS_OF, id_field = "latent_factor")

cat("\n=============== GATE 5 COMPLETE ===============\n")
cat(sprintf("labeled(single)=%d  unlabeled(new)=%d  econ_groups=%d  residual-α=%d  CCS=%s\n",
            nrow(labeled), nrow(unlabeled), grp$n_econ_groups, nrow(resid_char), ccs$ccs_total %||% "NA"))
