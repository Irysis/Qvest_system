# =============================================================================
# FQ-108 run_04: QLIKE + paired Diebold-Mariano(NW lag3) + MZ calibration
#   R4 P3: 전부 estimation-quality 지표. SR/IR/PORT_t/alpha 미산출.
#   Output: fq108_metrics.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq108_tailvol_risk_axis/fq108_lib.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

P <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_pairs.parquet")))
DG <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_sigma_diag.parquet")))
CF <- as.data.table(read_parquet(file.path(OUT_DIR, "fq108_coef_panel.parquet")))

ARMS <- c("A_base", "A2_recal", "B_d35", "C_d45", "D_max", "F_sv63", "G_full",
          "H_hybrid",                     # 사후 추가 탐색 arm (파라미터 없음)
          "X_oracle", "X_perfect")        # 위반 주입 canary 2종 (판정 대상 아님)
P <- P[arm %in% ARMS]
P[, qlike := qlike_loss(realized_var, pred_var)]
P[, verr  := volsq_err(realized_var, pred_var)]

# ---- paired 공통월: 모든 arm 이 예측을 낸 홀딩월만 -------------------------
cnt <- P[, .(n_arm = uniqueN(arm)), by = .(portfolio, target, est, holding_ym)]
ok  <- cnt[n_arm == length(ARMS), .(portfolio, target, est, holding_ym)]
PC  <- merge(P, ok, by = c("portfolio", "target", "est", "holding_ym"))
cat("[paired] rows:", nrow(PC), " months(common):",
    PC[, uniqueN(holding_ym), by = .(portfolio, target, est)][, unique(V1)], "\n")

# ---- 셀별 요약 --------------------------------------------------------------
SUMM <- PC[, {
  mzr <- mz_reg(realized_var, pred_var)
  .(mean_qlike = mean(qlike[is.finite(qlike)]),
    median_qlike = median(qlike[is.finite(qlike)]),
    rmse_vol = sqrt(mean(verr[is.finite(verr)])),
    mz_b = mzr$b, mz_r2 = mzr$r2,
    bias_ratio = mean(pred_var) / mean(realized_var),
    n = .N)
}, by = .(portfolio, target, est, arm)]
setorder(SUMM, portfolio, target, est, arm)

# ---- paired DM ---------------------------------------------------------------
PAIRSPEC <- list(
  # (좌항 처치) − (우항 기준). 음수 t = 좌항 우월(손실 낮음)
  c("A2_recal", "A_base"),      # 재보정 단독 기여
  c("B_d35",    "A_base"),      # ★PRIMARY 판정
  c("B_d35",    "A2_recal"),    # ★교란통제: D35 항의 순증분
  c("C_d45",    "A_base"),
  c("C_d45",    "A2_recal"),
  c("D_max",    "A_base"),
  c("D_max",    "A2_recal"),
  c("F_sv63",   "A_base"),
  c("F_sv63",   "A2_recal"),
  c("G_full",   "F_sv63"),      # rv63 위에 D35 가 더 있나
  c("B_d35",    "F_sv63"),      # 팩터DB 횡단면 z vs rawdata 레벨
  c("H_hybrid", "A_base"),      # 사후 탐색: 파라미터 없는 운영형 하이브리드
  c("H_hybrid", "F_sv63"),
  c("X_oracle", "A_base"),      # ★위반 주입 canary 1 (미래 시장 vol 레벨)
  c("X_oracle", "A2_recal"),
  c("X_oracle", "F_sv63"),
  c("X_perfect", "A_base"),     # ★위반 주입 canary 2 (완전 미래참조) — 결정적
  c("X_perfect", "H_hybrid")
)

dm_rows <- list()
for (pf in unique(PC$portfolio)) for (tg in unique(PC$target)) for (es in unique(PC$est)) {
  sub <- PC[portfolio == pf & target == tg & est == es]
  W <- dcast(sub, holding_ym ~ arm, value.var = "qlike")
  for (sp in PAIRSPEC) {
    if (!all(sp %in% names(W))) next
    d <- dm_nw(W[[sp[1]]], W[[sp[2]]], lag = 3L)
    dm_rows[[length(dm_rows) + 1L]] <- data.table(
      portfolio = pf, target = tg, est = es,
      treatment = sp[1], baseline = sp[2],
      mean_qlike_diff = d$mean_d, dm_t = d$t, n = d$n,
      verdict = if (is.na(d$t)) "no_test" else if (d$t <= -2.0) "treatment_better"
                else if (d$t >= 2.0) "treatment_worse" else "tie")
  }
}
DM <- rbindlist(dm_rows)
setorder(DM, portfolio, target, est, treatment)

# ---- 양성 대조 (positive control): lw_nls A_base vs lw_linear A_base ---------
#   FQ-057 P1c 기지 결과(실 book total 채널 DM-t ≈ -4.0) 재현 여부 =
#   본 하네스가 '진짜 있는 개선'을 검출할 능력이 있는지의 독립 증거.
pc_rows <- list()
for (pf in unique(PC$portfolio)) for (tg in unique(PC$target)) {
  a <- PC[portfolio == pf & target == tg & est == "lw_nls" & arm == "A_base"][order(holding_ym)]
  b <- PC[portfolio == pf & target == tg & est == "lw_linear" & arm == "A_base"][order(holding_ym)]
  m <- merge(a[, .(holding_ym, q_nls = qlike)], b[, .(holding_ym, q_lin = qlike)], by = "holding_ym")
  d <- dm_nw(m$q_nls, m$q_lin, lag = 3L)
  pc_rows[[length(pc_rows) + 1L]] <- data.table(
    portfolio = pf, target = tg, comparison = "lw_nls_minus_lw_linear (A_base)",
    mean_qlike_diff = d$mean_d, dm_t = d$t, n = d$n)
}
POSCTRL <- rbindlist(pc_rows)

# ---- 흡수(absorption) 분리 ---------------------------------------------------
abs_rows <- list()
for (pf in unique(PC$portfolio)) for (tg in unique(PC$target)) {
  g <- function(es, tr, bl) DM[portfolio == pf & target == tg & est == es &
                               treatment == tr & baseline == bl]
  for (tr in c("B_d35", "F_sv63", "G_full", "C_d45", "D_max", "H_hybrid")) {
    a <- g("lw_nls", tr, "A_base"); b <- g("lw_linear", tr, "A_base")
    if (!nrow(a) || !nrow(b)) next
    abs_rows[[length(abs_rows) + 1L]] <- data.table(
      portfolio = pf, target = tg, treatment = tr,
      d_lwnls = a$mean_qlike_diff, t_lwnls = a$dm_t,
      d_lwlinear = b$mean_qlike_diff, t_lwlinear = b$dm_t,
      absorbed = (a$dm_t > -2.0) & (b$dm_t <= -2.0))
  }
}
ABS <- rbindlist(abs_rows)

# ---- Σ 진단 -----------------------------------------------------------------
SD <- DG[, .(cond_median = median(cond[is.finite(cond)]),
             cond_inf_rate = mean(!is.finite(cond)),
             min_ev_median = median(min_ev), psd_rate = mean(psd),
             logsd_cs_dispersion_median = median(sd_cs_sd),
             p_median = median(p)), by = est]

# ---- 회귀계수 요약 (FM-NW) ---------------------------------------------------
cf_rows <- list()
for (es in unique(CF$est)) for (tr in unique(CF$treatment)) {
  sub <- CF[est == es & treatment == tr]
  for (tm in unique(sub$term)) {
    v <- sub[term == tm, coef]
    f <- fm_nw_t(v, lag = 3L)
    cf_rows[[length(cf_rows) + 1L]] <- data.table(
      est = es, treatment = tr, term = tm,
      mean_coef = f$mean, fm_nw_t = f$t, n_months = f$n)
  }
}
CFS <- rbindlist(cf_rows)

# ---- primary cell 추출 -------------------------------------------------------
prim <- DM[portfolio == "real_book_overlaid" & target == "total" & est == "lw_nls"]
primary <- list(
  cell = "real_book_overlaid × total × lw_nls",
  B_d35_vs_A_base    = as.list(prim[treatment == "B_d35" & baseline == "A_base",
                                    .(mean_qlike_diff, dm_t, n, verdict)]),
  B_d35_vs_A2_recal  = as.list(prim[treatment == "B_d35" & baseline == "A2_recal",
                                    .(mean_qlike_diff, dm_t, n, verdict)]),
  A2_recal_vs_A_base = as.list(prim[treatment == "A2_recal" & baseline == "A_base",
                                    .(mean_qlike_diff, dm_t, n, verdict)]),
  F_sv63_vs_A_base   = as.list(prim[treatment == "F_sv63" & baseline == "A_base",
                                    .(mean_qlike_diff, dm_t, n, verdict)]),
  X_oracle_vs_A_base = as.list(prim[treatment == "X_oracle" & baseline == "A_base",
                                    .(mean_qlike_diff, dm_t, n, verdict)]),
  X_perfect_vs_A_base = as.list(prim[treatment == "X_perfect" & baseline == "A_base",
                                    .(mean_qlike_diff, dm_t, n, verdict)]),
  H_hybrid_vs_A_base = as.list(prim[treatment == "H_hybrid" & baseline == "A_base",
                                    .(mean_qlike_diff, dm_t, n, verdict)])
)

out <- list(
  id = "FQ-108", stage = "run_04_metrics",
  metric_type = "risk_forecast_accuracy_diagnostic",
  selection_objective = "estimation_quality (QLIKE)",
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_common_months = as.list(PC[, .(n = uniqueN(holding_ym)), by = .(portfolio, target, est)]),
  summary_by_cell = SUMM, dm_tests = DM, absorption = ABS, positive_control = POSCTRL,
  sigma_diagnostics = SD, coef_fm_nw = CFS, primary = primary)
write_json(out, file.path(OUT_DIR, "fq108_metrics.json"), auto_unbox = TRUE, pretty = TRUE,
           digits = 8, na = "null")

cat("\n===== PRIMARY CELL (real_book_overlaid x total x lw_nls) =====\n")
print(prim[, .(treatment, baseline, mean_qlike_diff = round(mean_qlike_diff, 5),
               dm_t = round(dm_t, 3), n, verdict)])
cat("\n===== ABSORPTION (lw_nls vs lw_linear) =====\n")
print(ABS[portfolio == "real_book_overlaid" & target == "total",
          .(treatment, d_lwnls = round(d_lwnls, 5), t_lwnls = round(t_lwnls, 2),
            d_lwlinear = round(d_lwlinear, 4), t_lwlinear = round(t_lwlinear, 2), absorbed)])
cat("\n===== mean QLIKE by cell (total) =====\n")
print(dcast(SUMM[target == "total"], portfolio + est ~ arm, value.var = "mean_qlike"))
cat("\n===== mean QLIKE by cell (te) =====\n")
print(dcast(SUMM[target == "te"], portfolio + est ~ arm, value.var = "mean_qlike"))
cat("\n===== Sigma diagnostics =====\n"); print(SD)
cat("\n===== coef FM-NW (lw_nls) =====\n"); print(CFS[est == "lw_nls"])
cat("[done] run_04\n")
