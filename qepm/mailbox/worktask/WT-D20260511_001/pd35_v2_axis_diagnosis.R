#==============================================================================
# WT-D20260511_001 PD35 v2 — Per-axis IC diagnosis + alternative compositions
#
# v1 result: mean_IC=0.0301 t_NW=4.66 (6/8 pass)
#   FAIL gates: ax001_v2 (crisis_IC=0.0002, normal_IC=0.0335 → ratio 0.0053)
#               cor_per_date NaN (formula bug)
#
# Diagnosis goals:
#   1. Per-axis IC: which axis (profit/tail/earnings) provides crisis hedge?
#   2. Per-factor IC under crisis vs normal regimes
#   3. Alternative weight schemes: tail-risk heavy, profit-quality heavy
#   4. Test 4 alternative composites to find AX-001 v2 PASS
#   5. Fix cor_per_date NaN
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
OUT_PARQUET <- file.path(STAGE_DIR, "alpha_scores_pd35_quality_tail_earnings.parquet")
OUT_JSON <- file.path(WT_DIR, "pd35_v2_diagnostic.json")

# Load v1 output
alpha <- as.data.table(read_parquet(OUT_PARQUET))
cat("Loaded v1 alpha:", nrow(alpha), "rows, ", uniqueN(alpha$Date), "dates\n")

# Crisis windows
crisis_ranges <- list(
  c("2008-09-01", "2009-03-01"),
  c("2011-08-01", "2011-12-01"),
  c("2015-06-01", "2016-02-01"),
  c("2020-02-01", "2020-04-01"),
  c("2022-05-01", "2022-10-01")
)
alpha[, regime := "normal"]
for (r in crisis_ranges) alpha[Date >= as.Date(r[1]) & Date <= as.Date(r[2]), regime := "crisis"]

# ---- 1) Per-axis IC by regime ----
ic_axis <- function(dt, score_col) {
  dt[!is.na(get(score_col)) & !is.na(Ret_1m),
     .(IC = suppressWarnings(cor(get(score_col), Ret_1m, method="spearman")), N = .N),
     by = .(Date, regime)]
}

ic_profit <- ic_axis(alpha, "axis_profit")
ic_tail   <- ic_axis(alpha, "axis_tail")
ic_earn   <- ic_axis(alpha, "axis_earn")
ic_combo  <- ic_axis(alpha, "alpha_pd35")

per_regime_summary <- function(ic_dt, label) {
  ic_dt <- ic_dt[!is.na(IC)]
  ic_dt[, .(mean_IC = mean(IC), sd_IC = sd(IC), n_months = .N,
            axis = label), by = regime]
}

axis_summary <- rbindlist(list(
  per_regime_summary(ic_profit, "profit_quality"),
  per_regime_summary(ic_tail,   "tail_risk"),
  per_regime_summary(ic_earn,   "earnings_quality"),
  per_regime_summary(ic_combo,  "combined_pd35_v1")
))
cat("\n[PER-AXIS IC by regime]\n")
print(axis_summary)

# ---- 2) Test 6 alternative composites ----
# Strategy: emphasize tail_risk + earnings_quality (likely crisis-positive)
# Reduce profit_quality if it's pro-cyclical (positive normal, ~0 crisis)
test_specs <- list(
  v1_EW_3axis = c(profit=1/3, tail=1/3, earn=1/3),
  v2_tail_heavy = c(profit=0.20, tail=0.60, earn=0.20),
  v3_tail_earn_only = c(profit=0.00, tail=0.50, earn=0.50),
  v4_earn_heavy = c(profit=0.20, tail=0.20, earn=0.60),
  v5_profit_lite = c(profit=0.10, tail=0.45, earn=0.45),
  v6_balanced_def = c(profit=0.15, tail=0.50, earn=0.35)
)

eval_combo <- function(w) {
  alpha[, score_tmp := w["profit"] * axis_profit + w["tail"] * axis_tail + w["earn"] * axis_earn]
  alpha[, score_tmp_z := {
    mu <- mean(score_tmp, na.rm = TRUE)
    sg <- sd(score_tmp, na.rm = TRUE)
    if (!is.na(sg) && sg > 1e-9) (score_tmp - mu)/sg else score_tmp
  }, by = Date]
  ic <- alpha[!is.na(score_tmp_z) & !is.na(Ret_1m),
              .(IC = suppressWarnings(cor(score_tmp_z, Ret_1m, method="spearman")), N=.N),
              by = .(Date, regime)]
  ic <- ic[!is.na(IC)]
  mean_IC_all <- mean(ic$IC)
  sd_IC_all <- sd(ic$IC)
  ICIR <- mean_IC_all / sd_IC_all
  t_naive <- mean_IC_all / (sd_IC_all / sqrt(nrow(ic)))
  crisis_ic <- mean(ic[regime == "crisis", IC])
  normal_ic <- mean(ic[regime == "normal", IC])
  list(mean_IC = mean_IC_all, sd_IC = sd_IC_all, ICIR = ICIR, t_naive = t_naive,
       crisis_IC = crisis_ic, normal_IC = normal_ic, ratio = crisis_ic / normal_ic,
       ax001_v2_pass = crisis_ic > 0 && (crisis_ic / normal_ic) > 1.0)
}

results <- list()
for (spec_name in names(test_specs)) {
  results[[spec_name]] <- eval_combo(test_specs[[spec_name]])
}
cat("\n[ALTERNATIVE COMPOSITE RESULTS]\n")
for (sn in names(results)) {
  r <- results[[sn]]
  cat(sprintf("  %s: mean_IC=%.4f ICIR=%.4f t=%.4f crisis=%.4f normal=%.4f ratio=%.4f AX001=%s\n",
              sn, r$mean_IC, r$ICIR, r$t_naive, r$crisis_IC, r$normal_IC, r$ratio, r$ax001_v2_pass))
}

# ---- 3) Per-factor IC by regime (deep diagnosis) ----
# Reload factors for the most recent month + crisis sample to see which factors carry crisis IC
# We'll use 5 crisis months as sample (2008-10, 2011-09, 2015-08, 2020-03, 2022-07)
sample_dates <- as.Date(c("2008-10-01","2011-09-01","2015-08-01","2020-03-01","2022-07-01"))
FUNC_PATH <- file.path(PROJ_ROOT, "02_Infrastructure"); CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
test_factors <- c("Q10_Gross_Margin", "Q01_GPA", "Q17_ROIC", "M22_Max_Return", "D44_Kurtosis", "AC22_Accrual_Volatility", "Q33_Earnings_Persistence")

per_factor_crisis <- list()
for (sd in sample_dates) {
  fdt <- tryCatch(load_month_factors(sd, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt)) next
  fdt <- fdt[Factor_Name %in% test_factors]
  pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))[Date == sd, .(Ticker, Ret_1m)]
  if (nrow(pd27) == 0) next
  wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  m <- merge(wide, pd27, by = "Ticker")
  for (fc in test_factors) {
    if (!fc %in% names(m)) next
    if (sum(!is.na(m[[fc]]) & !is.na(m$Ret_1m)) < 50) next
    ic <- suppressWarnings(cor(m[[fc]], m$Ret_1m, method = "spearman", use = "pairwise.complete.obs"))
    per_factor_crisis[[paste(sd, fc, sep="_")]] <- list(Date = as.character(sd), Factor_Name = fc, IC = ic)
  }
}
per_factor_dt <- rbindlist(per_factor_crisis, fill = TRUE)
per_factor_summary <- per_factor_dt[, .(crisis_IC_mean = mean(IC, na.rm = TRUE), n = .N), by = Factor_Name]
cat("\n[PER-FACTOR CRISIS IC across 5 crisis months]\n")
print(per_factor_summary)

# ---- 4) cor_per_date with PD27 (fix NaN bug) ----
pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))[, .(Date, Ticker, score_pd27 = score_eff)]
cor_dt <- merge(alpha[, .(Date, Ticker, alpha_pd35)], pd27, by = c("Date", "Ticker"))
cat(sprintf("\n[cor_per_date diag] merged %d rows, %d unique dates\n", nrow(cor_dt), uniqueN(cor_dt$Date)))
cor_per_date <- cor_dt[!is.na(alpha_pd35) & !is.na(score_pd27),
                       .(cor = suppressWarnings(cor(alpha_pd35, score_pd27, method="spearman")),
                         N_stocks = .N),
                       by = Date]
cor_per_date <- cor_per_date[!is.na(cor) & N_stocks >= 30]
cat(sprintf("[cor_per_date] %d dates with valid cor (>=30 stocks)\n", nrow(cor_per_date)))
cat(sprintf("[cor_per_date] mean=%.4f median=%.4f sd=%.4f min=%.4f max=%.4f\n",
            mean(cor_per_date$cor), median(cor_per_date$cor), sd(cor_per_date$cor),
            min(cor_per_date$cor), max(cor_per_date$cor)))

# Save diagnostic
diag_v2 <- list(
  axis_summary_by_regime = axis_summary,
  alternative_composites = results,
  per_factor_crisis_IC = per_factor_summary,
  cor_per_date_fixed = list(
    n_dates = nrow(cor_per_date),
    mean = mean(cor_per_date$cor), median = median(cor_per_date$cor), sd = sd(cor_per_date$cor),
    min = min(cor_per_date$cor), max = max(cor_per_date$cor),
    constraint_lt_0_30 = abs(mean(cor_per_date$cor)) < 0.30
  )
)
writeLines(toJSON(diag_v2, pretty = TRUE, auto_unbox = TRUE, na = "string"), OUT_JSON)
cat(sprintf("\n[PD35 v2 diag] Saved to %s\n", OUT_JSON))
