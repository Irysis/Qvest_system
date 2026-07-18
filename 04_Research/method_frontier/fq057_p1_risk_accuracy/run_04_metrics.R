# =============================================================================
# FQ-057 NP4-P1 run_04: 손실지표(QLIKE/RMSE/MZ) + paired Diebold-Mariano
#   - 공통 스코어셋 = 4 arm 모두 가용 홀딩월(ewma_direct 12m warmup 바인딩)
#   - structural pair(lw_nls vs lw_linear)는 3 structural full-set 병행 보고
#   - 판정: (a) risk_package 대형-유니버스 Σ  (b) monitoring TE 기준선
#   Output: p1_metrics.json
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "04_Research/method_frontier/fq057_p1_risk_accuracy/p1_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

P <- as.data.table(read_parquet(file.path(OUT_DIR, "p1_pairs.parquet")))
ARMS_STRUCT <- c("lw_linear","lw_nls","ewma_struct")
ALL_ARMS <- c(ARMS_STRUCT, "ewma_direct")

# ---- (portfolio,target) 별 wide (holding_ym x arm pred_var) + realized -------
make_wide <- function(pf, tg, arms) {
  s <- P[portfolio==pf & target==tg & arm %in% arms]
  w <- dcast(s, holding_ym + realized_var ~ arm, value.var="pred_var")
  # 모든 arm 컬럼 존재 + 완전행만 (공통 스코어셋)
  need <- intersect(arms, colnames(w))
  w <- w[complete.cases(w[, ..need])]
  w[order(holding_ym)]
}

# per-arm 손실요약
arm_summary <- function(w, arms) {
  rv <- w$realized_var
  out <- list()
  for (a in arms) {
    pv <- w[[a]]
    mz <- mz_reg(rv, pv)
    out[[a]] <- list(
      mean_qlike = round(mean_qlike(rv, pv), 5),
      rmse_vol_ann = round(rmse_vol_ann(rv, pv, scale=12), 5),
      median_pred_vol_ann = round(sqrt(median(pv))*sqrt(12), 4),
      mz_a = round(mz$a, 6), mz_b = round(mz$b, 4), mz_r2 = round(mz$r2, 4))
  }
  out
}
# paired DM (QLIKE): arm A vs B  → 음수 t = A 우월
dm_pair <- function(w, A, B, lag=3L) {
  rv <- w$realized_var
  lA <- qlike_loss(rv, w[[A]]); lB <- qlike_loss(rv, w[[B]])
  r <- dm_nw(lA, lB, lag=lag)
  list(pair=paste0(A," - ",B), mean_qlike_diff=round(r$mean_d,5),
       dm_nw_t_lag3=round(r$t,4), n=r$n,
       verdict = if (is.na(r$t)) "NA" else if (r$t <= -2.0) paste0(A,"_better") else if (r$t >= 2.0) paste0(B,"_better") else "tie")
}

results <- list()
for (pf in c("capw_tilt_top25","ew_top25")) for (tg in c("te","total")) {
  key <- paste(pf, tg, sep="/")
  w_all <- make_wide(pf, tg, ALL_ARMS)          # 공통 4-arm 셋
  w_str <- make_wide(pf, tg, ARMS_STRUCT)       # structural 3-arm full-set
  results[[key]] <- list(
    portfolio=pf, target=tg,
    common_set = list(n=nrow(w_all), holding_range=if(nrow(w_all)>0) range(w_all$holding_ym) else NA,
                      realized_vol_ann=round(sqrt(median(w_all$realized_var))*sqrt(12),4),
                      arm_summary = arm_summary(w_all, ALL_ARMS),
                      paired = list(
                        a_lwnls_vs_lwlinear = dm_pair(w_all,"lw_nls","lw_linear"),
                        lwnls_vs_ewma_struct = dm_pair(w_all,"lw_nls","ewma_struct"),
                        b_lwnls_vs_ewma_direct = dm_pair(w_all,"lw_nls","ewma_direct"))),
    structural_fullset = list(n=nrow(w_str), holding_range=if(nrow(w_str)>0) range(w_str$holding_ym) else NA,
                      arm_summary = arm_summary(w_str, ARMS_STRUCT),
                      paired = list(
                        a_lwnls_vs_lwlinear = dm_pair(w_str,"lw_nls","lw_linear"),
                        lwnls_vs_ewma_struct = dm_pair(w_str,"lw_nls","ewma_struct"))))
}

# ---- 판정 (사전등록 규칙) ---------------------------------------------------
prim <- results[["capw_tilt_top25/te"]]$common_set
ctrl <- results[["ew_top25/te"]]$common_set
a_prim <- prim$paired$a_lwnls_vs_lwlinear
a_ctrl <- ctrl$paired$a_lwnls_vs_lwlinear
b_prim <- prim$paired$b_lwnls_vs_ewma_direct

decide_a <- (!is.na(a_prim$dm_nw_t_lag3) && a_prim$dm_nw_t_lag3 <= -2.0 &&
             a_prim$mean_qlike_diff < 0 && a_ctrl$mean_qlike_diff < 0)
decide_b <- (!is.na(b_prim$dm_nw_t_lag3) && b_prim$dm_nw_t_lag3 <= -2.0 &&
             b_prim$mean_qlike_diff < 0)

decision <- list(
  a_risk_package_large_universe_sigma = list(
    rule = "capw/te DM(lw_nls-lw_linear) t<=-2 ∧ mean_qlike_diff<0 ∧ EW control 동일방향",
    primary_dm_t = a_prim$dm_nw_t_lag3, primary_qlike_diff = a_prim$mean_qlike_diff,
    control_qlike_diff = a_ctrl$mean_qlike_diff,
    verdict = if (decide_a) "ADOPT_lw_nls_for_large_universe_sigma" else "HOLD_or_reroute"),
  b_monitoring_te_baseline = list(
    rule = "capw/te DM(lw_nls-ewma_direct) t<=-2 ∧ mean_qlike_diff<0 → lw_nls 채택; 아니면 EWMA-direct 유지",
    primary_dm_t = b_prim$dm_nw_t_lag3, primary_qlike_diff = b_prim$mean_qlike_diff,
    verdict = if (decide_b) "ADOPT_lw_nls_predicted_te" else "KEEP_ewma_direct_baseline"))

metrics <- list(pin_tag="fq057_20260718_171024", measured_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
                metric_type="risk_forecast_accuracy_diagnostic",
                loss="QLIKE (Patton 2011) primary; RMSE(vol_ann) secondary; MZ calibration",
                paired_test="Diebold-Mariano NW HAC lag3 on per-month QLIKE diffs (neg t = left arm better)",
                ewma_lambda=0.94,
                results=results, decision=decision)
write_json(metrics, file.path(OUT_DIR,"p1_metrics.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("[done] run_04. decision_a =", decision$a_risk_package_large_universe_sigma$verdict,
    "| decision_b =", decision$b_monitoring_te_baseline$verdict, "\n")
