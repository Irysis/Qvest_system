# 03_method_comparison_metrics.R — WT-S20260504_002
# Computes numeric net_IR / cost-adjusted metrics for 3 variants (S1 / DCC / M4+DCC).
# Uses STR_1715 monthly net returns as base; multiplies by sleeve weight + cash 0% return.
# Sleeve-level proxy backtest (NOT full stock-level walk-forward — that is forge phase).
#
# Output: stage_artifacts/WT_WT-S20260504_002/method_comparison_metrics.json

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
stage_dir <- file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID))

ret <- as.data.table(read_parquet(file.path(stage_dir, "str1715_monthly_returns.parquet")))
ret[, ym := format(date, "%Y-%m")]
setnames(ret, "ret_net", "str_ret_net")
setnames(ret, "ret_gross", "str_ret_gross")

# Load 3 variants
load_variant <- function(name) {
  if (name == "M4+DCC_VolTarget") {
    p <- file.path(stage_dir, "weights_variants/M4+DCC_VolTarget.csv")
  } else {
    p <- file.path(stage_dir, paste0("weights_variants/", name, ".csv"))
  }
  v <- fread(p)
  v[, ym := format(as.Date(Date), "%Y-%m")]
  v
}

S1 <- load_variant("S1")
DCC <- load_variant("DCC_VolTarget")
M4DCC <- load_variant("M4+DCC_VolTarget")

# Merge each with returns, compute combined sleeve+cash return
# cash return = 0 (proxy — no money market return modeled per sleeve-level convention)
compute_variant_returns <- function(variant_dt, name) {
  m <- merge(ret[, .(ym, str_ret_net)], variant_dt[, .(ym, weight_str1715, weight_cash)],
             by = "ym", all.x = TRUE, sort = TRUE)
  # default weights for any missing month: full sleeve (1, 0)
  m[is.na(weight_str1715), weight_str1715 := 1]
  m[is.na(weight_cash), weight_cash := 0]
  m[, port_ret_pre_to_cost := weight_str1715 * str_ret_net + weight_cash * 0]

  # Sleeve turnover penalty (allocation-only TO, not inside-sleeve TO which is in str_ret_net already)
  # Δw_sleeve_t = |w_str1715_t - w_str1715_{t-1}|. round-trip = ×2.
  # 15bps one-way → 30bps round-trip on the changed share.
  m[, dw := c(0, abs(diff(weight_str1715)))]
  m[, sleeve_to_cost := dw * 2 * 0.0015]  # round-trip cost on changed sleeve share
  m[, port_ret_net := port_ret_pre_to_cost - sleeve_to_cost]
  m[, ret_excess_vs_S1 := port_ret_net - str_ret_net]
  m
}

S1_r <- compute_variant_returns(S1, "S1")
DCC_r <- compute_variant_returns(DCC, "DCC_VolTarget")
M4DCC_r <- compute_variant_returns(M4DCC, "M4+DCC_VolTarget")

# Metric helpers
ann_ret <- function(r) prod(1 + r) ^ (12 / length(r)) - 1
ann_vol <- function(r) sd(r) * sqrt(12)
sharpe <- function(r) {
  if (sd(r) == 0) return(NA_real_)
  ann_ret(r) / ann_vol(r)
}
mdd <- function(r) {
  cum <- cumprod(1 + r)
  peak <- cummax(cum)
  -min(cum / peak - 1)
}
sortino <- function(r) {
  ds <- sqrt(mean(pmin(r, 0) ^ 2)) * sqrt(12)
  if (ds == 0) return(NA_real_)
  ann_ret(r) / ds
}
calmar <- function(r) ann_ret(r) / mdd(r)

# IR vs S1 (active = port - S1)
compute_ir <- function(r_active) {
  if (sd(r_active) == 0) return(0)
  mean(r_active) * 12 / (sd(r_active) * sqrt(12))
}

# Compute metrics
metrics <- list()
for (name in c("S1", "DCC_VolTarget", "M4+DCC_VolTarget")) {
  d <- switch(name,
              "S1" = S1_r,
              "DCC_VolTarget" = DCC_r,
              "M4+DCC_VolTarget" = M4DCC_r)
  r <- d$port_ret_net
  ra <- d$ret_excess_vs_S1
  metrics[[name]] <- list(
    n_months = nrow(d),
    ann_return_net = round(ann_ret(r), 6),
    ann_vol = round(ann_vol(r), 6),
    sharpe_net = round(sharpe(r), 4),
    mdd = round(mdd(r), 6),
    sortino = round(sortino(r), 4),
    calmar = round(calmar(r), 4),
    sleeve_to_cost_total_bps = round(sum(d$sleeve_to_cost) * 1e4, 2),
    sleeve_to_cost_annualized_bps = round(mean(d$sleeve_to_cost) * 12 * 1e4, 2),
    information_ratio_vs_S1 = round(compute_ir(ra), 4),
    active_return_ann = round(mean(ra) * 12, 6),
    active_te_ann = round(sd(ra) * sqrt(12), 6),
    pct_negative_months = round(mean(r < 0), 4),
    # net_IR: vs S1, after sleeve TO cost — primary selection_objective metric
    net_ir = round(compute_ir(ra), 4),
    # to_adj_ret: ann_ret - turnover cost penalty
    to_adj_ret = round(ann_ret(r), 6)
  )
}

# Selection table
selection_table <- data.table(
  method = c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"),
  ann_return = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$ann_return_net),
  ann_vol = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$ann_vol),
  sharpe = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$sharpe_net),
  mdd = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$mdd),
  sortino = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$sortino),
  calmar = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$calmar),
  net_ir_vs_S1 = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$net_ir),
  sleeve_to_bps_ann = sapply(c("S1", "DCC_VolTarget", "M4+DCC_VolTarget"), function(n) metrics[[n]]$sleeve_to_cost_annualized_bps)
)

cat("=== Method Comparison Metrics (sleeve-level proxy backtest) ===\n\n")
print(selection_table)

# Save
out <- list(
  task_id = WT_ID,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  method_basis_label = "optimizer_sleeve_level_proxy_backtest",
  production_grade = FALSE,
  basis_caveat = "Sleeve-level proxy: port_ret = w_str1715 * STR_1715_monthly_net + w_cash * 0. Sleeve TO cost = |Δw_str1715| * 2 * 15bps. Stock-level walk-forward backtest deferred to Forge phase.",
  selection_objective = "to_adj_ret",
  selection_objective_audit = list(
    primary_metric = "net_ir_vs_S1 (sleeve-level, after sleeve TO cost)",
    tie_breaker = "mdd (lower better, defensive priority)",
    forbidden_metric_avoided = "sharpe_net standalone (R4-A compliance)",
    decision_rule = "M4+DCC_VolTarget if mdd < S1 mdd by >= 3pp AND ann_return >= 20% floor"
  ),
  metrics = metrics,
  selection_table = as.list(selection_table),
  cost_audit = list(
    transaction_cost_bps_one_way = 15,
    sleeve_TO_cost_basis = "|Δw_str1715_t| * 2 * 0.0015 (round-trip applied to sleeve share change)",
    inside_sleeve_TO_cost_basis = "Inherited from STR_1715 monthly net return (already includes 15bps inside-sleeve TO cost)",
    no_double_counting = TRUE
  ),
  decision_rule_check = list(
    rule_recall = "PASS = CAGR ≥20% + (MDD ≤-25% OR -3pp improvement vs S1)",
    S1_baseline_mdd = round(mdd(S1_r$port_ret_net), 6),
    M4_DCC_mdd = round(mdd(M4DCC_r$port_ret_net), 6),
    mdd_improvement_pp_M4DCC_vs_S1 = round((mdd(S1_r$port_ret_net) - mdd(M4DCC_r$port_ret_net)) * 100, 2),
    S1_cagr = round(ann_ret(S1_r$port_ret_net), 6),
    M4_DCC_cagr = round(ann_ret(M4DCC_r$port_ret_net), 6),
    M4_DCC_meets_cagr_floor_20pct = ann_ret(M4DCC_r$port_ret_net) >= 0.20,
    M4_DCC_meets_mdd_target_25pct = mdd(M4DCC_r$port_ret_net) <= 0.25,
    M4_DCC_meets_mdd_3pp_improvement = (mdd(S1_r$port_ret_net) - mdd(M4DCC_r$port_ret_net)) >= 0.03
  )
)

write_json(out, file.path(stage_dir, "method_comparison_metrics.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("\nWrote method_comparison_metrics.json\n")
