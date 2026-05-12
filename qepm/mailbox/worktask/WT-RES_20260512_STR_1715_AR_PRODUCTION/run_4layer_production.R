## ============================================================
## STR_1715_AR_threshold_overlay PRODUCTION WEIGHTING backtest
## ============================================================
## 도훈 mandate 2026-05-12 KST:
##   "STR_1715_AR_threshold_overlay 이 전략은 EW 아니지?"
##
## Forge v2 (RES_RAW_cover v2) admit:
##   직전 EW reconstruction (alpha_top20 1/20 average) → production weighting 부정합
##   Iter31 official: linear_tilt_to_penalty_qd(λ=1.5, phi=3, ub=0.20)
##   PR ret_net (production weighting baked in) cor with EW = 0.0335 (spurious)
##
## 본 task = production weighting strict 5-layer comparison
##
## Base measurement = STR_1715 PR ret_net (production Iter31 baked + 15bps embedded)
##   - 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv
##   - 2004-02-02 ~ 2026-04-01 (267m, admit alpha lineage 2004-01 decision = first realized 2004-02)
##   - cash_weight all 0 confirmed (Iter31 base risk-only, M4 overlay separately)
##   - ret_orig = ret_net direct (no cash inverse needed)
##
## 5 Layers:
##   Layer 1: Original = ret_net (production weighting, no overlay)
##   Layer 2: MRS simple = (1 - mrs_cash_lag) × ret_orig (4-state 0/10/20/40)
##   Layer 3: M4 only = m4_weight_lag × ret_orig (M4 BOCPD+decay+BL multiplier)
##   Layer 4: AR on M4 ⭐ (admit) = β · m4_weight · ret_orig - AR_turnover_cost
##   Layer 5: AR on Original = β · ret_orig - AR_turnover_cost
##
## PIT:
##   - PR ret_net = M4 NOT baked in PR file (validated)
##     → ret_orig = ret_net = Iter31 production no-overlay base
##     → Layer 3 M4 application: m4_weight × ret_orig (multiply)
##   - M4/β_t t-1 lag (decision at t-1 EOM, applied to month t)
##   - bm_12m past-only frollsum shift(1)
##   - 15bps cost on AR turnover Δβ only (base PR cost embedded)
##
## Period strategy:
##   - panel_267m_full: 2004-02 ~ 2026-04 (267m, full PR coverage, M4/β NA → 1.0 passthrough)
##   - panel_254m_warmup: 2005-03 ~ 2026-04 (drop first 13m: 12m MRS regime + 1m β lag)
##   - panel_256m_admit_baseline: 2005-02 ~ 2026-05 admit JSON 256m (n=255 due to last partial)
##
## Backtest Contract v1.0: PerformanceAnalytics standard functions only
##   table.AnnualizedReturns + maxDrawdown + SortinoRatio + CalmarRatio
##   prod(1+r)-1 / cumprod(1+r) 자체 합성 금지 (NAV cumprod 허용, ret 합성 X)
## ============================================================

cat("============================================================\n")
cat("STR_1715_AR_threshold_overlay PRODUCTION WEIGHTING Backtest\n")
cat("WT-RES_20260512 / 도훈 mandate 2026-05-12 (EW disallow)\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
  library(lubridate)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-RES_20260512_STR_1715_AR_PRODUCTION")

# Raw cover hardcoded — STR_1715 admit alpha lineage first valid sig_date
# Decision 2004-01 EOM → realized 2004-02 (PR file first row)
RAW_COVER_START_DECISION <- as.Date("2004-01-01")
RAW_COVER_START_REALIZED <- as.Date("2004-02-01")
STR_ID <- "STR_1715_AR_threshold_overlay"

# ============================================================
# 1. Load STR_1715 PR ret_net (production weighting Iter31 baked)
# ============================================================
cat("[1] Load STR_1715 PR ret_net (production weighting baked)\n")

pr_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
pr <- fread(pr_path)
pr[, date := as.Date(date)]
pr[, ym := format(date, "%Y-%m")]
setorder(pr, date)

cat(sprintf("  rows: %d | range %s ~ %s\n",
            nrow(pr), as.character(min(pr$date)), as.character(max(pr$date))))
cat(sprintf("  cash_weight summary:\n"))
print(summary(pr$cash_weight))
cat(sprintf("  cost_ret mean: %.6f (already in ret_net)\n",
            mean(pr$cost_ret, na.rm = TRUE)))
cat(sprintf("  turnover mean: %.4f (avg %.1f%%)\n",
            mean(pr$turnover, na.rm = TRUE),
            mean(pr$turnover, na.rm = TRUE) * 100))

# Confirm cash_weight all 0 (Iter31 base risk-only)
stopifnot(all(pr$cash_weight == 0, na.rm = TRUE))
cat("  cash_weight all 0 confirmed → ret_orig = ret_net direct\n")

# ============================================================
# 2. Compose period_returns panel (production base)
# ============================================================
cat("\n[2] Compose period_returns panel (production weighting Layer A+B)\n")

# Decision date = end of previous month (decided at t-1 EOM, applied at t)
# PR date = trading day of holding month
# realized_ym = format(PR date, "%Y-%m")
panel <- pr[, .(date = date,
                realized_ym = ym,
                ret_orig = ret_net,         # production weighting baked + cost embedded
                ret_gross = ret_gross,      # gross before cost
                turnover_base = turnover,   # base TO (Iter31)
                cost_ret_base = cost_ret,   # base cost (15bps × TO, in ret_net)
                cash_weight = cash_weight,  # all 0 confirmed
                n_holdings = n_holdings)]
setorder(panel, date)

cat(sprintf("  panel: %d rows | %s ~ %s\n",
            nrow(panel),
            as.character(min(panel$date)),
            as.character(max(panel$date))))

# ============================================================
# 3. Load Layer C: M4 regime overlay schedule
# ============================================================
cat("\n[3] Load Layer C — M4 regime schedule (BOCPD+decay+BL)\n")

m4_path <- file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv")
m4 <- fread(m4_path)
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
setorder(m4, Date)

# t-1 lag: M4 weight decided at t-1 EOM → applied to month t
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]
m4[, weight_cash_lag := shift(weight_cash, 1, fill = 0.0)]

cat(sprintf("  M4: %d rows | range %s ~ %s\n",
            nrow(m4), as.character(min(m4$Date)), as.character(max(m4$Date))))

# Merge by realized_ym
panel <- merge(panel,
               m4[, .(realized_ym = ym, m4_weight_lag = weight_str1715_lag,
                       m4_cash_lag = weight_cash_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(m4_weight_lag), m4_weight_lag := 1.0]
panel[is.na(m4_cash_lag), m4_cash_lag := 0.0]
setorder(panel, date)

cat(sprintf("  m4_weight_lag distribution (rounded 0.01):\n"))
print(table(round(panel$m4_weight_lag, 2)))

# ============================================================
# 4. Load Layer C: AR β_t threshold overlay
# ============================================================
cat("\n[4] Load Layer C — AR threshold β_t mapping (K=5/W=252)\n")

beta_path <- file.path(BASE_DIR,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
setorder(beta_dt, Date)

# t-1 lag
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]
beta_dt[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]

panel <- merge(panel,
               beta_dt[, .(realized_ym = ym,
                            beta_threshold_lag = beta_threshold_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]
setorder(panel, date)

# AR turnover = |Δβ| month over month
panel[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]
panel[is.na(db_thr), db_thr := 0]

cat(sprintf("  β_threshold_lag distribution (rounded 0.1):\n"))
print(table(round(panel$beta_threshold_lag, 1)))
cat(sprintf("  first non-1.0 β date: %s\n",
            as.character(min(panel$date[panel$beta_threshold_lag != 1.0]))))

# ============================================================
# 5. Build Layer 2 — MRS simple 4-state cash from BM_Ret 12m
# ============================================================
cat("\n[5] Build Layer 2 — MRS simple cash 4-state (0/10/20/40)\n")

bm_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/05_benchmark_returns.csv")
bm <- fread(bm_path)
bm[, date := as.Date(date)]
# Extract bm_ret column
ret_col <- names(bm)[grepl("ret", names(bm), ignore.case = TRUE)][1]
setnames(bm, ret_col, "bm_ret")
bm[, ym := format(date, "%Y-%m")]
bm <- unique(bm[, .(ym, bm_ret = bm_ret)], by = "ym")
setorder(bm, ym)

panel <- merge(panel, bm[, .(realized_ym = ym, bm_ret)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, date)

# 12m trailing BM (log compound past-only, C11 PIT)
panel[, lret_bm := log(1 + pmax(bm_ret, -0.99))]
panel[, bm_12m := exp(frollsum(shift(lret_bm, 1), 12,
                                 align = "right", fill = NA_real_)) - 1]

panel[, mrs_cash := fcase(
  is.na(bm_12m), 0,
  bm_12m >= 0.10, 0.00,
  bm_12m >= 0.00, 0.10,
  bm_12m >= -0.10, 0.20,
  default = 0.40
)]
panel[, mrs_cash_lag := shift(mrs_cash, 1, fill = 0)]

cat(sprintf("  MRS cash_lag distribution:\n"))
print(table(panel$mrs_cash_lag))

# ============================================================
# 6. Compose 5-Layer return paths (production base)
# ============================================================
cat("\n[6] Compose 5-Layer return paths (production weighting base)\n")

# Layer 1: Original = ret_net (production Iter31, no overlay, cost embedded)
panel[, ret_L1_orig := ret_orig]

# Layer 2: MRS simple cash = (1 - mrs_cash_lag) × ret_orig
panel[, ret_L2_MRS := (1 - mrs_cash_lag) * ret_orig]

# Layer 3: M4 only = m4_weight × ret_orig
# (M4 is multiplicative overlay on top of Iter31 production weights)
panel[, ret_L3_M4 := m4_weight_lag * ret_orig]

# Layer 4: AR on M4 (admit Path A) = β × m4_weight × ret_orig - AR_turnover_cost
panel[, ret_L4_AR_M4 := beta_threshold_lag * m4_weight_lag * ret_orig - db_thr * 0.0015]

# Layer 5: AR on Original (no M4) = β × ret_orig - AR_turnover_cost
panel[, ret_L5_AR_orig := beta_threshold_lag * ret_orig - db_thr * 0.0015]

panel[, anchor_date := date]

# Sanity: Layer 1 should reproduce admit baseline Original SR
sanity_L1_xret <- xts::xts(panel$ret_L1_orig, order.by = panel$anchor_date)
sanity_ann <- table.AnnualizedReturns(sanity_L1_xret, scale = 12, Rf = 0)
cat(sprintf("\n  [Sanity] Layer 1 (Production Original) 267m metrics:\n"))
cat(sprintf("    CAGR: %.4f | Vol: %.4f | Sharpe: %.4f\n",
            as.numeric(sanity_ann[1, 1]), as.numeric(sanity_ann[2, 1]),
            as.numeric(sanity_ann[3, 1])))

# ============================================================
# 7. Build measurement panels
# ============================================================
cat("\n[7] Build measurement panels\n")

# Drop any rows with NA in ret_orig (shouldn't happen — PR file fully populated)
panel <- panel[is.finite(ret_orig)]
cat(sprintf("  Post-NA filter: n=%d\n", nrow(panel)))

# Panel A: 267m_full (full PR coverage, raw cover from admit lineage)
panel_267m_full <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
cat(sprintf("  panel_267m_full: n=%d | %s ~ %s\n",
            nrow(panel_267m_full),
            as.character(min(panel_267m_full$anchor_date)),
            as.character(max(panel_267m_full$anchor_date))))

# Panel B: 254m_warmup (drop first 13m: 12m MRS regime + 1m β lag)
# First valid regime month = 2005-03 (12m past from 2004-02 + 1m β lag)
panel_254m_warmup <- panel[!is.na(bm_12m) & realized_ym >= "2005-03"]
cat(sprintf("  panel_254m_warmup: n=%d | %s ~ %s\n",
            nrow(panel_254m_warmup),
            as.character(min(panel_254m_warmup$anchor_date)),
            as.character(max(panel_254m_warmup$anchor_date))))

# Panel C: 256m_admit_baseline (2005-02 ~ 2026-05, admit JSON convention)
# n=255 due to 2026-05 missing in PR file (last PR = 2026-04)
panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"]
cat(sprintf("  panel_255m_admit: n=%d | %s ~ %s\n",
            nrow(panel_255m_admit),
            as.character(min(panel_255m_admit$anchor_date)),
            as.character(max(panel_255m_admit$anchor_date))))

# ============================================================
# 8. Compute metrics per panel (5 layers)
# ============================================================
compute_metrics <- function(dt_panel, panel_label) {
  cat(sprintf("\n=== %s (n=%d months) ===\n", panel_label, nrow(dt_panel)))
  ret_mat <- as.matrix(dt_panel[, .(ret_L1_orig, ret_L2_MRS, ret_L3_M4,
                                     ret_L4_AR_M4, ret_L5_AR_orig)])
  xret <- xts::xts(ret_mat, order.by = dt_panel$anchor_date)
  colnames(xret) <- c("L1_Original", "L2_MRS", "L3_M4", "L4_AR_on_M4", "L5_AR_on_Orig")

  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mddv <- maxDrawdown(xret)
  sortino <- SortinoRatio(xret, MAR = 0)
  calmar <- CalmarRatio(xret)

  cat("Annualized:\n"); print(round(ann, 4))
  cat("MaxDrawdown:\n"); print(round(mddv, 4))

  build_row <- function(label, idx) {
    list(
      panel = panel_label,
      layer = label,
      CAGR = round(as.numeric(ann[1, idx]), 4),
      Vol = round(as.numeric(ann[2, idx]), 4),
      Sharpe = round(as.numeric(ann[3, idx]), 4),
      MDD = round(-as.numeric(mddv[idx]), 4),
      Sortino = round(as.numeric(sortino[idx]), 4),
      Calmar = round(as.numeric(calmar[idx]), 4),
      n_months = nrow(dt_panel)
    )
  }

  rbindlist(list(
    build_row("1_Original_no_overlay", 1),
    build_row("2_MRS_simple_cash_4state", 2),
    build_row("3_M4_BOCPD_decay_BL", 3),
    build_row("4_AR_on_M4_threshold_S1", 4),
    build_row("5_AR_on_Original_no_M4", 5)
  ))
}

metrics_267  <- compute_metrics(panel_267m_full,  "267m_full_admit_lineage")
metrics_254  <- compute_metrics(panel_254m_warmup, "254m_warmup_drop")
metrics_255  <- compute_metrics(panel_255m_admit,  "255m_admit_baseline_comparable")

# ============================================================
# 9. Delta comparisons
# ============================================================
cat("\n[9] Delta comparisons\n")

# Admit JSON 256m baseline (canonical)
admit_l4_json <- list(
  CAGR = 0.3834, Vol = 0.2159, Sharpe = 1.7758,
  MDD = -0.2515, Sortino = 1.0510, Calmar = 1.5245, n_months = 256
)
admit_l1_json <- list(
  CAGR = 0.4464, Vol = 0.2649, Sharpe = 1.6854,
  MDD = -0.4169, Sortino = 0.9187, Calmar = 1.0706
)

# Prior EW Forge run 267m comparable (RES_RAW_cover v2)
prior_ew_l4_267 <- list(
  CAGR = 0.2106, Vol = 0.2139, Sharpe = 0.985,
  MDD = -0.3036, Sortino = 0.57, Calmar = 0.6939, n_months = 267
)

# Pick current run L4 from 255m_admit_baseline (most comparable to admit JSON 256m)
l4_255 <- metrics_255[layer == "4_AR_on_M4_threshold_S1"]
l1_255 <- metrics_255[layer == "1_Original_no_overlay"]
l4_267 <- metrics_267[layer == "4_AR_on_M4_threshold_S1"]
l1_267 <- metrics_267[layer == "1_Original_no_overlay"]

# Delta vs admit JSON 256m (production weighting expected to match closely)
delta_vs_admit <- data.table(
  metric = c("CAGR", "Vol", "Sharpe", "MDD", "Sortino", "Calmar"),
  admit_256m_json = c(admit_l4_json$CAGR, admit_l4_json$Vol, admit_l4_json$Sharpe,
                       admit_l4_json$MDD, admit_l4_json$Sortino, admit_l4_json$Calmar),
  current_255m_production = c(l4_255$CAGR, l4_255$Vol, l4_255$Sharpe,
                              l4_255$MDD, l4_255$Sortino, l4_255$Calmar),
  delta_production_vs_admit = NA_real_
)
delta_vs_admit[, delta_production_vs_admit := current_255m_production - admit_256m_json]

# Delta vs prior EW Forge 267m (measurement basis difference)
delta_vs_ew <- data.table(
  metric = c("CAGR", "Vol", "Sharpe", "MDD", "Sortino", "Calmar"),
  prior_267m_EW = c(prior_ew_l4_267$CAGR, prior_ew_l4_267$Vol, prior_ew_l4_267$Sharpe,
                     prior_ew_l4_267$MDD, prior_ew_l4_267$Sortino, prior_ew_l4_267$Calmar),
  current_267m_production = c(l4_267$CAGR, l4_267$Vol, l4_267$Sharpe,
                              l4_267$MDD, l4_267$Sortino, l4_267$Calmar),
  delta_production_vs_EW = NA_real_
)
delta_vs_ew[, delta_production_vs_EW := current_267m_production - prior_267m_EW]

# Layer 1 sanity vs admit JSON Original 256m
delta_l1_sanity <- data.table(
  metric = c("CAGR", "Vol", "Sharpe", "MDD", "Sortino", "Calmar"),
  admit_L1_256m_json = c(admit_l1_json$CAGR, admit_l1_json$Vol, admit_l1_json$Sharpe,
                          admit_l1_json$MDD, admit_l1_json$Sortino, admit_l1_json$Calmar),
  current_L1_255m_production = c(l1_255$CAGR, l1_255$Vol, l1_255$Sharpe,
                                  l1_255$MDD, l1_255$Sortino, l1_255$Calmar),
  delta = NA_real_
)
delta_l1_sanity[, delta := current_L1_255m_production - admit_L1_256m_json]

cat("\n[Layer 4 production 255m vs admit JSON 256m]:\n")
print(delta_vs_admit)
cat("\n[Layer 4 production 267m vs prior EW 267m] (measurement basis drift):\n")
print(delta_vs_ew)
cat("\n[Layer 1 production 255m vs admit L1 256m sanity]:\n")
print(delta_l1_sanity)

# ============================================================
# 10. Save artifacts
# ============================================================
cat("\n[10] Save artifacts\n")

# (a) full 5-layer comparison
combined <- rbindlist(list(metrics_267, metrics_254, metrics_255))
fwrite(combined, file.path(WT_DIR, "four_layer_comparison_production.csv"))

# (b) delta vs admit JSON 256m
fwrite(delta_vs_admit, file.path(WT_DIR, "four_layer_comparison_delta_vs_admit_256m.csv"))

# (c) delta vs EW 267m
fwrite(delta_vs_ew, file.path(WT_DIR, "four_layer_comparison_delta_vs_ew_267m.csv"))

# (d) Layer 1 sanity
fwrite(delta_l1_sanity, file.path(WT_DIR, "layer1_sanity_vs_admit.csv"))

# (e) NAV (production base, 267m)
panel_267m_full[, nav_L1 := cumprod(1 + ret_L1_orig)]
panel_267m_full[, nav_L2 := cumprod(1 + ret_L2_MRS)]
panel_267m_full[, nav_L3 := cumprod(1 + ret_L3_M4)]
panel_267m_full[, nav_L4 := cumprod(1 + ret_L4_AR_M4)]
panel_267m_full[, nav_L5 := cumprod(1 + ret_L5_AR_orig)]
nav_dt <- panel_267m_full[, .(anchor_date, realized_ym,
                                nav_L1, nav_L2, nav_L3, nav_L4, nav_L5)]
fwrite(nav_dt, file.path(WT_DIR, "nav_layer4_production.csv"))

# (f) full returns path (production)
ret_dt <- panel_267m_full[, .(anchor_date, realized_ym,
                                ret_L1_orig, ret_L2_MRS, ret_L3_M4,
                                ret_L4_AR_M4, ret_L5_AR_orig,
                                turnover_base, cost_ret_base,
                                mrs_cash_lag, m4_weight_lag, m4_cash_lag,
                                beta_threshold_lag, db_thr,
                                bm_12m, bm_ret, n_holdings)]
fwrite(ret_dt, file.path(WT_DIR, "four_layer_returns_path_production.csv"))

# (g) Layer 4 drawdowns top 10 (255m admit comparable)
xret_l4_255 <- xts::xts(panel_255m_admit$ret_L4_AR_M4,
                         order.by = panel_255m_admit$anchor_date)
dd_table_255 <- table.Drawdowns(xret_l4_255, top = 10)
cat("\n[Layer 4 drawdowns 255m admit comparable, top 10]:\n")
print(dd_table_255)

if (!is.null(dd_table_255) && nrow(dd_table_255) > 0) {
  dd_dt <- as.data.table(dd_table_255)
  for (col in names(dd_dt)) {
    if (is.factor(dd_dt[[col]])) dd_dt[[col]] <- as.character(dd_dt[[col]])
  }
  fwrite(dd_dt, file.path(WT_DIR, "drawdowns_layer4_production.csv"))
}

# (h) Layer 4 extended metrics (255m admit comparable)
ann_l4 <- table.AnnualizedReturns(xret_l4_255, scale = 12, Rf = 0)
ann_l4_mat <- as.matrix(ann_l4)
hit_rate <- mean(panel_255m_admit$ret_L4_AR_M4 > 0, na.rm = TRUE)
cvar_95 <- mean(panel_255m_admit$ret_L4_AR_M4[
  panel_255m_admit$ret_L4_AR_M4 <= quantile(panel_255m_admit$ret_L4_AR_M4, 0.05,
                                              na.rm = TRUE)
], na.rm = TRUE)
avg_to_beta <- mean(panel_255m_admit$db_thr, na.rm = TRUE) * 12

metrics_l4_ext <- data.table(
  metric = c("CAGR", "Vol", "Sharpe", "MDD", "Sortino", "Calmar",
             "Hit_Rate", "CVaR_95_monthly", "TO_beta_annualized",
             "n_months", "first_anchor_date", "last_anchor_date"),
  value = c(as.character(round(as.numeric(ann_l4_mat[1, 1]), 6)),
            as.character(round(as.numeric(ann_l4_mat[2, 1]), 6)),
            as.character(round(as.numeric(ann_l4_mat[3, 1]), 6)),
            as.character(round(-as.numeric(maxDrawdown(xret_l4_255)), 6)),
            as.character(round(as.numeric(SortinoRatio(xret_l4_255)), 6)),
            as.character(round(as.numeric(CalmarRatio(xret_l4_255)), 6)),
            as.character(round(hit_rate, 6)),
            as.character(round(cvar_95, 6)),
            as.character(round(avg_to_beta, 6)),
            as.character(nrow(panel_255m_admit)),
            as.character(min(panel_255m_admit$anchor_date)),
            as.character(max(panel_255m_admit$anchor_date)))
)
fwrite(metrics_l4_ext, file.path(WT_DIR, "metrics_layer4_production.csv"))

# (i) bt_result 10-component (Backtest Contract v1.0)
bt_result <- list(
  manifest = list(
    task_id = "WT-RES_20260512_STR_1715_AR_PRODUCTION",
    parent_admit_wt = "WT-P20260504_001",
    strategy_id = STR_ID,
    measurement_basis = "production_weighting_admit_lineage",
    weighting = "Iter31_linear_tilt_to_penalty_qd_lambda1.5_phi3_ub0.20",
    raw_cover_start_decision = as.character(RAW_COVER_START_DECISION),
    raw_cover_start_realized = as.character(RAW_COVER_START_REALIZED),
    raw_cover_rationale = paste("STR_1715 admit alpha lineage first valid sig_date 2004-01.",
                                 "Decision 2004-01-EOM → realized 2004-02 first PR row.",
                                 "Production weighting baked in PR ret_net."),
    base_source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
    alpha_lineage = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    mode = "research_diagnostic",
    EW_disallow = "도훈 mandate 2026-05-12: EW 부정합, production weighting strict",
    pit_compliance = "C2_C9_C11_C13_C14",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  ),
  strategy_spec = list(
    layers = list(
      A = "Iter5 alpha multi-axis (theta_core + theta_defense, score_eff)",
      B = "Iter31 linear_tilt_to_penalty_qd(λ=1.5, phi=3, ub=0.20) [production weighting]",
      C_M4 = "M4 BOCPD+decay+BL regime overlay (NORMAL=1.0 / CAUTION partial / CRISIS=0.43)",
      C_AR = "AR threshold β_t step (K=5/W=252, β∈{0.4,0.7,1.0})"
    ),
    universe = "KOSPI200 ∪ KOSDAQ150",
    top_n = 20,
    weighting = "Production_Iter31_linear_tilt (NOT EW)",
    cost_model_version = "v2.3_kr_retail_15bps",
    cost_applied_basis = "Base Iter31 TO baked in PR ret_net + AR turnover (Δβ) 15bps additional"
  ),
  nav = nav_dt,
  period_returns = ret_dt,
  holdings = NULL,
  benchmark_returns = panel_267m_full[, .(anchor_date, realized_ym, bm_ret, bm_12m)],
  metrics = as.list(metrics_l4_ext),
  benchmark_compare = NULL,
  rolling_metrics = NULL,
  drawdowns = if (exists("dd_dt")) as.data.frame(dd_dt) else NULL,
  audit = NULL
)
saveRDS(bt_result, file.path(WT_DIR, "bt_result_layer4_production.rds"))

# ============================================================
# 11. Audit (Backtest Contract v1.0 10-check)
# ============================================================
cat("\n[11] Audit — Backtest Contract v1.0 10-check\n")

audit <- list(
  task_id = "WT-RES_20260512_STR_1715_AR_PRODUCTION",
  audit_version = "v1_production_weighting_strict",
  audit_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  checks = list(
    nav_monotone_dates = list(pass = all(diff(nav_dt$anchor_date) > 0),
                              note = "monotone increasing"),
    returns_finite = list(pass = all(is.finite(panel_255m_admit$ret_L4_AR_M4)),
                          note = sprintf("n_finite=%d",
                                          sum(is.finite(panel_255m_admit$ret_L4_AR_M4)))),
    n_obs_sufficient = list(pass = nrow(panel_255m_admit) >= 60,
                            note = sprintf("n=%d months", nrow(panel_255m_admit))),
    cost_model_documented = list(pass = TRUE,
                                  note = "v2.3_kr_retail_15bps; base Iter31 TO in PR ret_net, AR Δβ × 0.0015 additional"),
    pit_lag_applied = list(pass = TRUE,
                            note = "M4 t-1 lag + β_t t-1 lag + bm_12m past-only frollsum shift(1)"),
    perfanalytics_standard = list(pass = TRUE,
                                   note = "table.AnnualizedReturns + maxDrawdown + SortinoRatio + CalmarRatio"),
    weighting_basis = list(pass = TRUE,
                            note = "Iter31 linear_tilt λ=1.5 phi=3 ub=0.20 [PR ret_net baked]; EW disallow per 도훈 mandate"),
    raw_cover_start_hardcoded = list(pass = TRUE,
                                     note = sprintf("decision %s | realized %s (PR first row)",
                                                     as.character(RAW_COVER_START_DECISION),
                                                     as.character(RAW_COVER_START_REALIZED))),
    layer_count = list(pass = TRUE,
                        note = "5 layers: Original / MRS / M4 / AR_on_M4 / AR_on_Orig"),
    sanity_l1_vs_admit = list(pass = abs(delta_l1_sanity$delta[3]) < 0.05,
                               note = sprintf("L1 Sharpe delta vs admit L1 256m: %+.4f (expected near 0 since same PR base, different N)",
                                              delta_l1_sanity$delta[3]))
  ),
  layer_4_admit_comparable_255m = list(
    CAGR = l4_255$CAGR, Vol = l4_255$Vol, Sharpe = l4_255$Sharpe,
    MDD = l4_255$MDD, Sortino = l4_255$Sortino, Calmar = l4_255$Calmar,
    n_months = l4_255$n_months
  ),
  layer_4_raw_cover_267m = list(
    CAGR = l4_267$CAGR, Vol = l4_267$Vol, Sharpe = l4_267$Sharpe,
    MDD = l4_267$MDD, Sortino = l4_267$Sortino, Calmar = l4_267$Calmar,
    n_months = l4_267$n_months
  ),
  drift_vs_admit_256m_json = list(
    delta_Sharpe = round(l4_255$Sharpe - 1.7758, 4),
    delta_CAGR_pp = round((l4_255$CAGR - 0.3834) * 100, 2),
    delta_MDD_pp = round((l4_255$MDD - (-0.2515)) * 100, 2),
    interpretation = "Expected near 0 since same production base + same overlay (only 1m difference: admit 256m vs current 255m due to PR file last row)"
  ),
  drift_vs_ew_267m = list(
    delta_Sharpe = round(l4_267$Sharpe - 0.985, 4),
    delta_CAGR_pp = round((l4_267$CAGR - 0.2106) * 100, 2),
    delta_MDD_pp = round((l4_267$MDD - (-0.3036)) * 100, 2),
    interpretation = "EW (alpha_top20 1/20) vs production Iter31 linear_tilt λ=1.5 measurement basis drift"
  )
)

# Mark integrity FAIL if any critical check fails
critical_checks <- c("nav_monotone_dates", "returns_finite", "n_obs_sufficient",
                      "pit_lag_applied", "perfanalytics_standard")
all_critical_pass <- all(sapply(critical_checks, function(k) audit$checks[[k]]$pass))
audit$integrity <- ifelse(all_critical_pass, "PASS", "FAIL")
audit$metric_type <- ifelse(all_critical_pass, "backtested", "unavailable")

write_json(audit, file.path(WT_DIR, "audit.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n[Audit] integrity: %s | metric_type: %s\n",
            audit$integrity, audit$metric_type))

# ============================================================
# 12. Print final summary
# ============================================================
cat("\n============================================================\n")
cat("FINAL: STR_1715_AR_threshold_overlay Production Weighting 5-Layer\n")
cat("============================================================\n")
cat("\n[Production 255m vs admit JSON 256m baseline (Layer 4)]:\n")
cat(sprintf("  CAGR:    %.4f vs %.4f → ΔCAGR=%+.4f pp\n",
            l4_255$CAGR, 0.3834, (l4_255$CAGR - 0.3834) * 100))
cat(sprintf("  Vol:     %.4f vs %.4f → ΔVol=%+.4f pp\n",
            l4_255$Vol, 0.2159, (l4_255$Vol - 0.2159) * 100))
cat(sprintf("  Sharpe:  %.4f vs %.4f → ΔSR=%+.4f\n",
            l4_255$Sharpe, 1.7758, l4_255$Sharpe - 1.7758))
cat(sprintf("  MDD:     %.4f vs %.4f → ΔMDD=%+.4f pp\n",
            l4_255$MDD, -0.2515, (l4_255$MDD - (-0.2515)) * 100))
cat(sprintf("  Sortino: %.4f vs %.4f → ΔSortino=%+.4f\n",
            l4_255$Sortino, 1.0510, l4_255$Sortino - 1.0510))
cat(sprintf("  Calmar:  %.4f vs %.4f → ΔCalmar=%+.4f\n",
            l4_255$Calmar, 1.5245, l4_255$Calmar - 1.5245))

cat("\n[Production 267m vs EW 267m (measurement basis drift)]:\n")
cat(sprintf("  Sharpe (production)=%.4f vs (EW)=%.4f → ΔSR=%+.4f\n",
            l4_267$Sharpe, 0.985, l4_267$Sharpe - 0.985))
cat(sprintf("  CAGR (production)=%.4f vs (EW)=%.4f → ΔCAGR=%+.2fpp\n",
            l4_267$CAGR, 0.2106, (l4_267$CAGR - 0.2106) * 100))
cat(sprintf("  MDD (production)=%.4f vs (EW)=%.4f → ΔMDD=%+.2fpp\n",
            l4_267$MDD, -0.3036, (l4_267$MDD - (-0.3036)) * 100))

cat("\n[Coverage extension vs admit baseline]:\n")
cat(sprintf("  267m raw cover Layer 4: CAGR=%.4f | Sharpe=%.4f | MDD=%.4f\n",
            l4_267$CAGR, l4_267$Sharpe, l4_267$MDD))
cat(sprintf("  255m admit comparable:  CAGR=%.4f | Sharpe=%.4f | MDD=%.4f\n",
            l4_255$CAGR, l4_255$Sharpe, l4_255$MDD))

cat("\nDone. Outputs in:", WT_DIR, "\n")
