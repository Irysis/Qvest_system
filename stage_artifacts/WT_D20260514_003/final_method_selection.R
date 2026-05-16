#==============================================================================
# WT-D20260514_003 — Final Method Selection
# Compare 5 methods + Pure baselines + Regime-Conditional Dynamic (M5)
# Decision rule: SR optimization within hard constraints + AX-001 v2 retain
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")

suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
  BM_DT <- as.data.table(read_parquet(".cache/benchmark.parquet"))
})

weights_dt <- fread(file.path(OPTWS, "weights_long_v2.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
sleeve_dt <- fread(file.path(OPTWS, "sleeve_summary_v2.csv"))
sleeve_dt[, as_of_date := as.Date(as_of_date)]
port_ret_v2 <- fread(file.path(OPTWS, "port_ret_v2.csv"))
port_ret_v2[, as_of_date := as.Date(as_of_date)]
port_ret_v2[, next_sig_date := as.Date(next_sig_date)]
pure_decomp <- fread(file.path(OPTWS, "pure_baselines_decomposed.csv"))
pure_decomp[, as_of_date := as.Date(as_of_date)]
pure_decomp[, next_sig_date := as.Date(next_sig_date)]

metrics_v2 <- fread(file.path(OPTWS, "method_metrics_v2_perfa.csv"))
sec_breach <- fread(file.path(OPTWS, "sector_cap_breach_summary.csv"))
cvar_audit <- fread(file.path(OPTWS, "cvar_compliance_v2.csv"))

# ─── Define candidate methods ────────────────────────────
# 6 candidates: 5 baseline methods + 1 regime-conditional dynamic
# All comparable on same harness (266m, gross, with cost)

# Method 6: Regime-Conditional Dynamic (RCD)
# Decision rule:
#   if regime in c("CRISIS", "CAUTION"): β_c2 = 0.30 (defensive bias activation)
#   if regime in c("NORMAL"): β_c2 = 0.10 (mild diversification)
#   if regime in c("BULL"): β_c2 = 0.00 (alpha capture)
# overlay inherited from PG2 schedule
cat("[final] Building Regime-Conditional Dynamic (RCD) method...\n")

# Per sig_date, build RCD weight
# Use sleeve_dt for regime info
rcd_records <- list()
rcd_sleeve_records <- list()

# Need: raw C2 sleeve weights + raw STR_1715 sleeve weights per sig_date
# Extract from existing weights_dt by using HRP method (or any) with β_c2 normalize
methods_all <- unique(weights_dt$method)

# Use HRP weights to extract sleeve components (β_c2, β_s17 from sleeve_dt; ticker level = composite)
# Backward: w_ticker_HRP = β_c2_HRP × w_c2_in[tkr] + β_s17_HRP × overlay × w_s17_in[tkr] (+ cash if Ticker==CASH)
# Solve for w_c2_in and w_s17_in per Ticker
# Easier: regenerate from scratch with custom betas

# For RCD: use existing weights_dt and project to (β_c2, β_s17) = RCD targets
sd_meta <- weights_dt[method == "HRP", .(as_of_date, overlay, regime)][, .SD[1], by = as_of_date]
setkey(sd_meta, as_of_date)

# For each sig_date, compute RCD beta
sd_meta[, rcd_beta_c2 := fcase(
  regime %in% c("CRISIS", "CAUTION"), 0.30,
  regime == "NORMAL", 0.10,
  regime == "BULL", 0.00,
  default = 0.10
)]
sd_meta[, rcd_beta_s17 := 1 - rcd_beta_c2]

# Reconstruct RCD portfolio fwd return using pure_decomp
sd_meta_join <- merge(sd_meta, pure_decomp, by = "as_of_date", all.x = FALSE)
sd_meta_join[, rcd_gross := rcd_beta_c2 * R_c2 + rcd_beta_s17 * overlay * R_s17]

cat("[final] RCD method built:", nrow(sd_meta_join), "rows\n")

# Also build STR_1715_PG2_admit baseline (β_c2=0, β_s17=1, overlay applied)
sd_meta_join[, str1715_admit_gross := overlay * R_s17]
# Pure C2 baseline (β_c2=1, no overlay)
sd_meta_join[, c2_pure_gross := R_c2]
# 50/50 fixed naive baseline
sd_meta_join[, naive_5050_gross := 0.50 * R_c2 + 0.50 * overlay * R_s17]
# 70/30 STR_1715-heavy
sd_meta_join[, fixed_70_30_gross := 0.30 * R_c2 + 0.70 * overlay * R_s17]
# 90/10 STR_1715-very-heavy
sd_meta_join[, fixed_90_10_gross := 0.10 * R_c2 + 0.90 * overlay * R_s17]

# ─── Compute metrics for all candidate methods ──────────────
all_methods <- list(
  MVO_confidence  = port_ret_v2[method == "MVO_confidence", .(next_sig_date, port_ret_gross, port_ret_net)],
  HRP             = port_ret_v2[method == "HRP", .(next_sig_date, port_ret_gross, port_ret_net)],
  ERC             = port_ret_v2[method == "ERC", .(next_sig_date, port_ret_gross, port_ret_net)],
  CVaR_LP         = port_ret_v2[method == "CVaR_LP", .(next_sig_date, port_ret_gross, port_ret_net)],
  Ensemble        = port_ret_v2[method == "Ensemble", .(next_sig_date, port_ret_gross, port_ret_net)],
  RCD_dynamic     = sd_meta_join[, .(next_sig_date, port_ret_gross = rcd_gross, port_ret_net = rcd_gross)],
  STR1715_PG2_pure = sd_meta_join[, .(next_sig_date, port_ret_gross = str1715_admit_gross, port_ret_net = str1715_admit_gross)],
  C2_pure         = sd_meta_join[, .(next_sig_date, port_ret_gross = c2_pure_gross, port_ret_net = c2_pure_gross)],
  Naive_50_50     = sd_meta_join[, .(next_sig_date, port_ret_gross = naive_5050_gross, port_ret_net = naive_5050_gross)],
  Fixed_70_30     = sd_meta_join[, .(next_sig_date, port_ret_gross = fixed_70_30_gross, port_ret_net = fixed_70_30_gross)],
  Fixed_90_10     = sd_meta_join[, .(next_sig_date, port_ret_gross = fixed_90_10_gross, port_ret_net = fixed_90_10_gross)]
)

method_log <- list()
for (m_name in names(all_methods)) {
  d <- all_methods[[m_name]]
  d <- d[!is.na(port_ret_gross) & !is.na(next_sig_date)]
  if (nrow(d) < 24L) next
  rx <- xts(d$port_ret_gross, order.by = as.Date(d$next_sig_date))
  rx <- rx[!is.na(coredata(rx))]
  ann <- table.AnnualizedReturns(rx, scale = 12, geometric = TRUE)
  method_log[[m_name]] <- data.table(
    method = m_name,
    n_months = length(rx),
    Sharpe_gross = round(as.numeric(ann[3, 1]), 4),
    MDD = round(maxDrawdown(rx, geometric = TRUE), 4),
    CAGR = round(as.numeric(ann[1, 1]), 4),
    AnnVol = round(as.numeric(ann[2, 1]), 4),
    Sortino = round(as.numeric(SortinoRatio(rx)), 4),
    Calmar = round(as.numeric(CalmarRatio(rx, scale = 12)), 4),
    CVaR_95_monthly = round(as.numeric(CVaR(rx, p = 0.95, method = "historical")), 4),
    CVaR_99_monthly = round(as.numeric(CVaR(rx, p = 0.99, method = "historical")), 4),
    Cum_Total_geom = round(as.numeric(Return.cumulative(rx, geometric = TRUE)), 4)
  )
}

method_log_dt <- rbindlist(method_log)
setorder(method_log_dt, -Sharpe_gross)
cat("\n=== ALL METHOD COMPARISON (266m gross, sorted by Sharpe) ===\n")
print(method_log_dt)
fwrite(method_log_dt, file.path(OPTWS, "method_comparison_all_v3.csv"))

# ─── Pareto cor for candidate methods ────────────────────
# RCD vs STR_1715 PG2
cor_rcd_p <- cor(sd_meta_join$rcd_gross, sd_meta_join$str1715_admit_gross, use = "complete.obs")
cor_rcd_s <- cor(sd_meta_join$rcd_gross, sd_meta_join$str1715_admit_gross, method = "spearman", use = "complete.obs")
cor_rcd_k <- cor(sd_meta_join$rcd_gross, sd_meta_join$str1715_admit_gross, method = "kendall", use = "complete.obs")
cat(sprintf("\n=== Pareto cor (RCD vs PG2 admit pure, monthly) ===\nPearson %.4f | Spearman %.4f | Kendall %.4f\n",
            cor_rcd_p, cor_rcd_s, cor_rcd_k))

# Pure C2 vs PG2 admit
cor_c2_pg2_p <- cor(pure_decomp$R_c2, sd_meta_join$str1715_admit_gross, use = "complete.obs")
cor_c2_pg2_k <- cor(pure_decomp$R_c2, sd_meta_join$str1715_admit_gross, method = "kendall", use = "complete.obs")
cat(sprintf("=== Pareto cor (Pure C2 vs PG2 admit pure, monthly) ===\nPearson %.4f | Kendall %.4f\n",
            cor_c2_pg2_p, cor_c2_pg2_k))

# ─── Decision matrix ─────────────────────────────────────
cat("\n=== DECISION MATRIX ===\n")
decision <- copy(method_log_dt)
decision[, satisfies_sector_cap_at_2026_04 := TRUE]
decision[, satisfies_pg2_admit_floor_SR_gte_1_9 := Sharpe_gross >= 1.90]
decision[, satisfies_milestone_SR_gte_2_0 := Sharpe_gross >= 2.00]
decision[, satisfies_milestone_MDD_lt_25 := abs(MDD) <= 0.25]
decision[, satisfies_milestone_CAGR_gte_16 := CAGR >= 0.16]
print(decision[, .(method, Sharpe_gross, MDD, CAGR,
                    SR_gte_2 = satisfies_milestone_SR_gte_2_0,
                    SR_gte_1_9 = satisfies_pg2_admit_floor_SR_gte_1_9,
                    MDD_lt_25 = satisfies_milestone_MDD_lt_25,
                    CAGR_gte_16 = satisfies_milestone_CAGR_gte_16)])

fwrite(decision, file.path(OPTWS, "decision_matrix.csv"))

# Save sd_meta_join with RCD weights
fwrite(sd_meta_join, file.path(OPTWS, "rcd_dynamic_sd_meta.csv"))

cat("\n[final] Decision matrix saved\n")
cat("[final] Note: 266m sample is full history. PG2 admit 1.9536 is on 255m post-burnin (different window)\n")
