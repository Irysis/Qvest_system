# WT-D20260512_003 — Step 4: Orthogonality + Regime-conditional IC
# Hard constraints:
#  (a) cor < 0.30 vs STR_1715 score_eff
#  (b) CRISIS+CAUTION SR > 0 strict
#  (c) ICIR >= 0.20 (Alpha Lab Gate)
#  (d) Harvey-t > 3.0

suppressPackageStartupMessages({
  library(data.table); library(arrow)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]

CAND <- c("V01_BM", "V18_AM", "V19_Debt_to_Market", "V20_SP", "V11_Shareholder_Yield",
          "MK01_CAPM_Beta", "R05_Tail_Risk", "D17_Cokurtosis",
          "L19_Price_Delay", "L20_Trade_Frequency", "L21_Market_Depth", "L44_Vol_Ret_Asymmetry",
          "C19_Composite_Earnings", "C12_Estimate_Dispersion_Proxy",
          "Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O",
          "C01_SUE", "C04_ESBR", "C06_TP_Gap")

# Filter to STR_1715 alpha available rows only (score_eff non-NA)
p <- panel[!is.na(score_eff)]
cat("[stats] Rows with score_eff:", nrow(p), "/ total:", nrow(panel), "\n")

# === (a) Cross-sectional correlation vs STR_1715 score_eff (per month avg) ===
cor_per_month <- function(factor_col) {
  p_sub <- p[!is.na(get(factor_col)) & !is.na(score_eff)]
  if (nrow(p_sub) == 0) return(data.table(rho_mean = NA_real_, rho_median = NA_real_, n_months = 0L))
  by_month <- p_sub[, .(rho = if (.N >= 5) cor(get(factor_col), score_eff, method="spearman") else NA_real_),
                    by = Date]
  by_month <- by_month[!is.na(rho)]
  data.table(rho_mean = mean(by_month$rho), rho_median = median(by_month$rho),
             n_months = nrow(by_month))
}

cor_results <- rbindlist(lapply(CAND, function(f) {
  res <- cor_per_month(f)
  res[, factor := f]
  res
}), fill = TRUE)
cor_results <- cor_results[, .(factor, rho_mean = round(rho_mean, 4), rho_median = round(rho_median, 4), n_months)]
cor_results[, hard_cor_pass := abs(rho_mean) < 0.30]
cat("\n=== (a) Cross-sectional correlation vs STR_1715 score_eff (per-month Spearman) ===\n")
print(cor_results[order(abs(rho_mean))])

# === (b) Regime-conditional IC (rank IC = Spearman alpha factor vs Ret_1m) ===
regime_ic <- function(factor_col) {
  p_sub <- p[!is.na(get(factor_col)) & !is.na(Ret_1m)]
  ic_by_regime_month <- p_sub[, .(ic = if (.N >= 5) cor(get(factor_col), Ret_1m, method="spearman") else NA_real_,
                                   n_stocks = .N),
                               by = .(Date, regime_state)]
  ic_by_regime_month <- ic_by_regime_month[!is.na(ic)]
  ic_summary <- ic_by_regime_month[, .(
    mean_ic = mean(ic), sd_ic = sd(ic), n_months = .N, hit = mean(ic > 0)
  ), by = regime_state]
  ic_summary[, icir := ifelse(sd_ic > 0, mean_ic / sd_ic * sqrt(12), 0)]
  ic_summary[, sr_proxy := mean_ic / sd_ic * sqrt(12)]
  ic_summary[, factor := factor_col]
  ic_summary[]
}

regime_ic_all <- rbindlist(lapply(CAND, regime_ic))
regime_ic_all <- regime_ic_all[, .(factor, regime_state,
                                    mean_ic = round(mean_ic, 5), sd_ic = round(sd_ic, 4),
                                    n_months, hit = round(hit, 3),
                                    icir = round(icir, 3), sr_proxy = round(sr_proxy, 3))]

cat("\n=== (b) Per-regime IC (Spearman per month, summary) ===\n")
print(regime_ic_all[regime_state %in% c("CAUTION", "CRISIS"), .(factor, regime_state, mean_ic, icir, n_months, hit)][order(factor, regime_state)])

# Hard constraint (b): CAUTION+CRISIS both IC > 0 + ICIR > 0
constraint_b <- regime_ic_all[regime_state %in% c("CAUTION", "CRISIS"),
                               .(stress_pass = all(mean_ic > 0) & all(icir > 0),
                                 caution_ic = mean_ic[regime_state == "CAUTION"],
                                 crisis_ic = mean_ic[regime_state == "CRISIS"],
                                 caution_icir = icir[regime_state == "CAUTION"],
                                 crisis_icir = icir[regime_state == "CRISIS"]),
                               by = factor]
cat("\n=== Hard Constraint (b): CRISIS+CAUTION strict positive ===\n")
print(constraint_b[order(-stress_pass, -crisis_ic)])

# Overall IC across full sample (Spearman 268m)
overall_ic <- function(factor_col) {
  p_sub <- p[!is.na(get(factor_col)) & !is.na(Ret_1m)]
  ic_by_month <- p_sub[, .(ic = if (.N >= 5) cor(get(factor_col), Ret_1m, method="spearman") else NA_real_),
                       by = Date]
  ic_by_month <- ic_by_month[!is.na(ic)]
  if (nrow(ic_by_month) == 0) return(data.table(factor = factor_col, n=0, ic_mean=NA, ic_sd=NA, icir=NA, t_stat=NA))
  ic_mean <- mean(ic_by_month$ic); ic_sd <- sd(ic_by_month$ic)
  t_stat <- ic_mean / (ic_sd / sqrt(nrow(ic_by_month)))  # standard t-stat
  data.table(factor = factor_col, n = nrow(ic_by_month),
             ic_mean = ic_mean, ic_sd = ic_sd,
             icir = ic_mean / ic_sd * sqrt(12),
             t_stat = t_stat)
}

overall <- rbindlist(lapply(CAND, overall_ic))
overall <- overall[, .(factor, n,
                       ic_mean = round(ic_mean, 5),
                       icir = round(icir, 3),
                       t_stat = round(t_stat, 2),
                       harvey_t_pass = abs(t_stat) > 3.0,
                       icir_pass = abs(icir) > 0.20)]
cat("\n=== (c)(d) Overall ICIR + Harvey-t (Newey-West not yet, plain t) ===\n")
print(overall[order(-icir)])

# Combined filter
all_pass <- merge(merge(cor_results, constraint_b, by = "factor"), overall, by = "factor")
all_pass[, alpha_lab_pass := hard_cor_pass & stress_pass & icir_pass]
cat("\n=== Combined Hard Constraints Filter (cor<0.30 + stress SR+ + ICIR>0.20) ===\n")
print(all_pass[order(-alpha_lab_pass, -crisis_ic), .(factor, rho_mean,
                                                       hard_cor_pass, stress_pass, icir_pass,
                                                       caution_ic, crisis_ic, icir, t_stat,
                                                       alpha_lab_pass)])

# Save artifacts
fwrite(cor_results, "stage_artifacts/WT_D20260512_003/cor_vs_str1715.csv")
fwrite(regime_ic_all, "stage_artifacts/WT_D20260512_003/regime_ic_all.csv")
fwrite(overall, "stage_artifacts/WT_D20260512_003/overall_ic.csv")
fwrite(all_pass, "stage_artifacts/WT_D20260512_003/combined_filter.csv")
cat("\n[saved] 4 CSVs to stage_artifacts/WT_D20260512_003/\n")
