# WT-D20260512_003 — Augment: Monotonicity (decile return spread)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]

SCHEME <- list(BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80)
p[, w_new := fcase(
  regime_state == "BULL", SCHEME$BULL,
  regime_state == "NORMAL", SCHEME$NORMAL,
  regime_state == "CAUTION", SCHEME$CAUTION,
  regime_state == "CRISIS", SCHEME$CRISIS,
  default = 0.0
)]
p[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

# Decile assignment per month
p[, decile := as.integer(cut(z_blend,
                              breaks = quantile(z_blend, probs = seq(0, 1, by = 0.1), na.rm = TRUE),
                              labels = 1:10, include.lowest = TRUE)), by = Date]

decile_ret <- p[!is.na(decile), .(mean_ret = mean(Ret_1m, na.rm = TRUE),
                                   n = .N), by = .(Date, decile)]
decile_ret_overall <- decile_ret[, .(mean_ret = mean(mean_ret),
                                       sd_ret = sd(mean_ret),
                                       n_months = .N), by = decile]
setorder(decile_ret_overall, decile)
cat("=== Decile mean returns (composite z_blend) ===\n")
print(decile_ret_overall)

# Monotonicity score: how monotonic is the relationship D1 to D10?
# Spearman rank correlation of (decile, mean_ret)
mono_spearman <- cor(decile_ret_overall$decile, decile_ret_overall$mean_ret, method = "spearman")
mono_pearson <- cor(decile_ret_overall$decile, decile_ret_overall$mean_ret, method = "pearson")
top_bottom_spread <- decile_ret_overall[decile == 10, mean_ret] - decile_ret_overall[decile == 1, mean_ret]

cat(sprintf("\nMonotonicity Spearman: %.3f\n", mono_spearman))
cat(sprintf("Monotonicity Pearson:  %.3f\n", mono_pearson))
cat(sprintf("Top-bottom spread (D10-D1): %.4f (monthly)\n", top_bottom_spread))

# Per regime
cat("\n=== Decile spread per regime ===\n")
for (reg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  ic_reg <- p[regime_state == reg]
  if (nrow(ic_reg) == 0) next
  ic_reg[, decile_r := as.integer(cut(z_blend,
                                       breaks = quantile(z_blend, probs = seq(0, 1, by = 0.1), na.rm = TRUE),
                                       labels = 1:10, include.lowest = TRUE)), by = Date]
  dr <- ic_reg[!is.na(decile_r), .(mean_ret = mean(Ret_1m, na.rm = TRUE)), by = decile_r]
  setorder(dr, decile_r)
  if (nrow(dr) >= 2) {
    sp <- cor(dr$decile_r, dr$mean_ret, method = "spearman")
    spread <- dr[decile_r == 10, mean_ret] - dr[decile_r == 1, mean_ret]
    cat(sprintf("%s: monotonicity=%.3f, D10-D1 spread=%.4f\n", reg, sp, spread))
  }
}

saveRDS(list(decile_overall = decile_ret_overall,
              mono_spearman = mono_spearman,
              mono_pearson = mono_pearson,
              top_bottom_spread = top_bottom_spread),
         "stage_artifacts/WT_D20260512_003/monotonicity.rds")
cat("\n[saved] monotonicity.rds\n")
