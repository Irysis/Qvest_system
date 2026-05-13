# WT-D20260512_003 — Step 5: Regime-conditional Z-score blend
# Spec: w_new(t) varies by regime, w_str(t) = 1 - w_new(t)
# Hard constraint (b): CAUTION+CRISIS SR > 0 strict (composite)
# Soft: BULL/NORMAL SR retain >= baseline

suppressPackageStartupMessages({
  library(data.table); library(arrow)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]

# === Strategy: regime-conditional w_new ===
# Per regime grid: w_new in [BULL, NORMAL, CAUTION, CRISIS]
# Constraint: max w_new = 0.70 (alpha integrity: STR_1715 retain >= 30%)
#             min w_new = 0.00 (option to fully off in regime)

# Test specific regime-conditional schemes
schemes <- list(
  scheme_A_balance = list(BULL = 0.10, NORMAL = 0.15, CAUTION = 0.50, CRISIS = 0.60),
  scheme_B_aggressive_stress = list(BULL = 0.05, NORMAL = 0.10, CAUTION = 0.70, CRISIS = 0.70),
  scheme_C_conservative = list(BULL = 0.10, NORMAL = 0.20, CAUTION = 0.35, CRISIS = 0.40),
  scheme_D_strong_caution = list(BULL = 0.05, NORMAL = 0.10, CAUTION = 0.80, CRISIS = 0.50),
  scheme_E_minimal = list(BULL = 0.10, NORMAL = 0.10, CAUTION = 0.50, CRISIS = 0.50)
)

test_scheme <- function(scheme, p_data) {
  p_data[, w_new := fcase(
    regime_state == "BULL", scheme$BULL,
    regime_state == "NORMAL", scheme$NORMAL,
    regime_state == "CAUTION", scheme$CAUTION,
    regime_state == "CRISIS", scheme$CRISIS,
    default = 0.0
  )]
  p_data[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]
  ic_dt <- p_data[, .(ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_,
                       n = .N, regime = regime_state[1]),
                   by = Date]
  ic_dt <- ic_dt[!is.na(ic)]
  regime_summary <- ic_dt[, .(mean_ic = mean(ic), sd_ic = sd(ic),
                               sr_proxy = mean(ic)/sd(ic)*sqrt(12),
                               n = .N, hit = mean(ic > 0)), by = regime]
  overall <- ic_dt[, .(mean_ic = mean(ic), icir = mean(ic)/sd(ic)*sqrt(12), n = .N)]
  list(scheme_params = scheme, regime = regime_summary, overall = overall)
}

# Test all schemes
results <- lapply(names(schemes), function(name) {
  res <- test_scheme(schemes[[name]], copy(p))
  res$name <- name
  res
})

# Print
for (r in results) {
  cat("\n========", r$name, "========\n")
  cat("Params:", paste(names(r$scheme_params),
                       sprintf("%.2f", unlist(r$scheme_params)), sep="=", collapse=", "), "\n")
  cat("Overall IC:", round(r$overall$mean_ic, 5),
      "ICIR:", round(r$overall$icir, 3), "\n")
  print(r$regime[, .(regime, mean_ic = round(mean_ic, 5),
                      sr_proxy = round(sr_proxy, 3), n)])
}

# === Optimizer: find optimal scheme via grid search ===
cat("\n\n=== Fine Grid Search (regime-conditional weights) ===\n")
# BULL/NORMAL grid: [0.05, 0.10, 0.15]
# CAUTION/CRISIS grid: [0.30, 0.40, 0.50, 0.60, 0.70]
b_grid <- c(0.05, 0.10, 0.15)
n_grid <- c(0.05, 0.10, 0.15)
k_grid <- c(0.30, 0.40, 0.50, 0.60, 0.70, 0.80)
c_grid <- c(0.30, 0.40, 0.50, 0.60, 0.70, 0.80)

all_combos <- expand.grid(BULL=b_grid, NORMAL=n_grid, CAUTION=k_grid, CRISIS=c_grid)
cat("Total combos:", nrow(all_combos), "\n")

grid_results <- rbindlist(lapply(seq_len(nrow(all_combos)), function(i) {
  sch <- as.list(all_combos[i, ])
  res <- test_scheme(sch, copy(p))
  data.table(
    BULL_w = sch$BULL, NORMAL_w = sch$NORMAL, CAUTION_w = sch$CAUTION, CRISIS_w = sch$CRISIS,
    overall_ic = res$overall$mean_ic, overall_icir = res$overall$icir,
    bull_ic = res$regime[regime=="BULL", mean_ic], bull_sr = res$regime[regime=="BULL", sr_proxy],
    normal_ic = res$regime[regime=="NORMAL", mean_ic], normal_sr = res$regime[regime=="NORMAL", sr_proxy],
    caution_ic = res$regime[regime=="CAUTION", mean_ic], caution_sr = res$regime[regime=="CAUTION", sr_proxy],
    crisis_ic = res$regime[regime=="CRISIS", mean_ic], crisis_sr = res$regime[regime=="CRISIS", sr_proxy]
  )
}))

# Pass constraint: CAUTION+CRISIS both SR > 0
grid_results[, stress_pass := caution_sr > 0 & crisis_sr > 0]
n_pass <- sum(grid_results$stress_pass)
cat("Schemes with CAUTION+CRISIS strict positive SR:", n_pass, "/", nrow(grid_results), "\n")

if (n_pass > 0) {
  passers <- grid_results[stress_pass == TRUE]
  # Sort by overall_icir (best composite)
  setorder(passers, -overall_icir)
  cat("\n=== TOP 15 schemes (CAUTION+CRISIS SR>0 strict) ===\n")
  print(passers[1:min(15, nrow(passers)), .(
    BULL_w, NORMAL_w, CAUTION_w, CRISIS_w,
    overall_icir = round(overall_icir, 3),
    bull_sr = round(bull_sr, 3),
    normal_sr = round(normal_sr, 3),
    caution_sr = round(caution_sr, 3),
    crisis_sr = round(crisis_sr, 3)
  )])
}

fwrite(grid_results, "stage_artifacts/WT_D20260512_003/regime_blend_grid_full.csv")
cat("\n[saved] regime_blend_grid_full.csv\n")
