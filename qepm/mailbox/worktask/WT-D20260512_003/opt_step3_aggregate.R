#==============================================================================
# WT-D20260512_003 Optimizer Step 3 — Aggregate metrics + Selection
#
# Inputs:
#   stage_artifacts/WT_D20260512_003/opt_method_shopping_raw.rds
#   (9 methods × 268m walk-forward monthly results)
#
# Outputs:
#   stage_artifacts/WT_D20260512_003/opt_method_comparison.csv
#   stage_artifacts/WT_D20260512_003/opt_selection_table.json
#
# Metrics (per method):
#   - SR_gross / SR_net (PerformanceAnalytics convention: ann_ret/ann_vol)
#   - CAGR / MDD / Sortino / Calmar
#   - Regime SR (BULL / NORMAL / CAUTION / CRISIS)
#   - Turnover (mean annual one-way + total cost)
#   - HHI mean (concentration penalty term)
#   - F_QMJ loading mean (factor concentration penalty)
#   - Top20 holdings 2026-04-01 cross-sectional (final live weight check)
#
# Selection objective (R4 P3 enum: crowding_adj_ret):
#   score = SR_net - λ_HHI × HHI_mean - λ_TO × TO_excess - λ_FQMJ × F_QMJ_excess
#   λ_HHI = 1.0 (penalize HHI > 0.10)
#   λ_TO = 0.001 (penalize TO > 4.0 annual)
#   λ_FQMJ = 0.5 (penalize F_QMJ > 1.0 — V5 failure axis)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step3] Aggregate Metrics + Method Selection\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
stage <- file.path("stage_artifacts", "WT_D20260512_003")
mailbox <- file.path("qepm/mailbox/worktask", WT)

results_raw <- readRDS(file.path(stage, "opt_method_shopping_raw.rds"))

# Load exposure for F_QMJ check
emat <- as.data.table(read_parquet(file.path(stage, "exposure_matrix.parquet")))
setkey(emat, Ticker)

# ─── Method metrics aggregation ────────────────────────────────
agg_method <- function(monthly) {
  monthly <- monthly[!is.na(port_ret_gross)]
  if (nrow(monthly) == 0L) return(NULL)
  setorder(monthly, sig_date)

  # Annualization (monthly → annual)
  rets <- monthly$port_ret_net
  rets_g <- monthly$port_ret_gross
  n <- length(rets)

  ann_mu <- mean(rets) * 12
  ann_sd <- sd(rets) * sqrt(12)
  ann_mu_g <- mean(rets_g) * 12
  ann_sd_g <- sd(rets_g) * sqrt(12)

  sr_net <- if (ann_sd > 0) ann_mu / ann_sd else NA
  sr_gross <- if (ann_sd_g > 0) ann_mu_g / ann_sd_g else NA

  cagr <- prod(1 + rets, na.rm=TRUE)^(12/n) - 1
  cagr_g <- prod(1 + rets_g, na.rm=TRUE)^(12/n) - 1

  # MDD on equity curve
  eq <- cumprod(1 + rets)
  peak <- cummax(eq)
  dd <- eq / peak - 1
  mdd <- min(dd, na.rm=TRUE)

  # Sortino (downside vol)
  neg_rets <- rets[rets < 0]
  ds_vol <- if (length(neg_rets) > 1) sd(neg_rets) * sqrt(12) else NA
  sortino <- if (!is.na(ds_vol) && ds_vol > 0) ann_mu / ds_vol else NA
  calmar <- if (mdd < 0) ann_mu / abs(mdd) else NA

  # Regime SR
  regime_sr <- monthly[, .(
    n_obs = .N,
    sr = if (sd(port_ret_net) > 0) (mean(port_ret_net) * 12) / (sd(port_ret_net) * sqrt(12)) else NA,
    mean_ret = mean(port_ret_net) * 12
  ), by = regime]

  # Turnover (annual)
  to_annual <- mean(monthly$turnover[-1], na.rm = TRUE) * 12  # exclude initial
  cost_total_bps <- sum(monthly$cost) * 10000

  list(
    n_obs = n,
    sr_net = sr_net,
    sr_gross = sr_gross,
    ann_ret_net = ann_mu,
    ann_ret_gross = ann_mu_g,
    ann_vol_net = ann_sd,
    cagr = cagr,
    cagr_gross = cagr_g,
    mdd = mdd,
    sortino = sortino,
    calmar = calmar,
    regime_sr_BULL = regime_sr[regime == "BULL", sr],
    regime_sr_NORMAL = regime_sr[regime == "NORMAL", sr],
    regime_sr_CAUTION = regime_sr[regime == "CAUTION", sr],
    regime_sr_CRISIS = regime_sr[regime == "CRISIS", sr],
    regime_n_BULL = regime_sr[regime == "BULL", n_obs],
    regime_n_NORMAL = regime_sr[regime == "NORMAL", n_obs],
    regime_n_CAUTION = regime_sr[regime == "CAUTION", n_obs],
    regime_n_CRISIS = regime_sr[regime == "CRISIS", n_obs],
    turnover_annual = to_annual,
    cost_total_bps = cost_total_bps
  )
}

agg_list <- lapply(results_raw, agg_method)
agg_dt <- rbindlist(lapply(names(agg_list), function(m) {
  x <- agg_list[[m]]
  if (is.null(x)) return(NULL)
  data.table(method = m, !!!x)
}), fill = TRUE)

# Convert NULL fields to NA for table display
for (col in names(agg_dt)) {
  if (is.list(agg_dt[[col]])) {
    agg_dt[[col]] <- sapply(agg_dt[[col]], function(x) if (is.null(x) || length(x) == 0) NA else x[[1]])
  }
}

# ─── HHI + F_QMJ for 2026-04 single-snapshot ─────────────────
# Walk-forward 평가 끝나면 final live weight @ 2026-04-01 sig_date 별도 계산
# (각 method의 last period weight를 risk_package Σ로 single-snapshot validation)
# Step 4에서 별도. 본 Step에서는 placeholder NA.
agg_dt[, hhi_mean := NA_real_]
agg_dt[, f_qmj_loading := NA_real_]

# ─── Selection objective ────────────────────────────────────────
# crowding_adj_ret = SR_net - λ_HHI × max(0, HHI_mean - 0.10) - λ_TO × max(0, (TO - 4.0)/4.0) - λ_FQMJ × max(0, F_QMJ - 1.0)
LAMBDA_HHI <- 1.0
LAMBDA_TO <- 0.05
LAMBDA_FQMJ <- 0.2

# Without HHI/F_QMJ data: just SR_net + TO penalty
agg_dt[, crowding_adj_ret := sr_net -
         LAMBDA_TO * pmax(0, (turnover_annual - 4.0) / 4.0)]

# Print summary
agg_dt_print <- agg_dt[, .(method, sr_net = round(sr_net, 4),
                            sr_gross = round(sr_gross, 4),
                            cagr = round(cagr * 100, 2),
                            mdd_pct = round(mdd * 100, 2),
                            sortino = round(sortino, 4),
                            calmar = round(calmar, 4),
                            BULL = round(regime_sr_BULL, 3),
                            NORMAL = round(regime_sr_NORMAL, 3),
                            CAUTION = round(regime_sr_CAUTION, 3),
                            CRISIS = round(regime_sr_CRISIS, 3),
                            TO = round(turnover_annual, 3),
                            cost_bps = round(cost_total_bps, 1),
                            obj = round(crowding_adj_ret, 4))]
setorder(agg_dt_print, -obj)
cat("\n[Method Shopping Results — sorted by selection objective]\n")
print(agg_dt_print)

# ─── Save ───────────────────────────────────────────────────────
fwrite(agg_dt, file.path(stage, "opt_method_comparison.csv"))
fwrite(agg_dt_print, file.path(stage, "opt_method_comparison_print.csv"))
cat(sprintf("\nSaved: %s\n", file.path(stage, "opt_method_comparison.csv")))

# Save JSON for downstream
selection_table <- list(
  task_id = WT,
  agent = "optimizer-research",
  step = 3,
  selection_objective = "crowding_adj_ret",
  selection_objective_formula = "SR_net - λ_TO × max(0, (TO - 4.0)/4.0)  (HHI/F_QMJ added Step 4)",
  lambda_TO = LAMBDA_TO,
  best_method = agg_dt_print$method[1],
  best_obj = agg_dt_print$obj[1],
  best_sr_net = agg_dt_print$sr_net[1],
  ranking = agg_dt_print$method,
  full_table = agg_dt
)
write_json(selection_table, file.path(stage, "opt_selection_table.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("Saved: %s\n", file.path(stage, "opt_selection_table.json")))

cat("[OPT-Step3] DONE\n")
