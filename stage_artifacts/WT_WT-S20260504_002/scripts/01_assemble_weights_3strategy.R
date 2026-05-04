# 01_assemble_weights_3strategy.R
# WT-S20260504_002 Optimizer Research
# 3-strategy variant assembly: S1 (baseline) / DCC_VolTarget / M4+DCC_VolTarget
#
# Input:
#   - parent weights.csv (sleeve-level, M4 cash overlay): qepm/mailbox/worktask/WT-P20260429_002/weights.csv
#   - sigma_p_forecast.csv (DCC forecast): stage_artifacts/WT_WT-S20260504_002/sigma_p_forecast.csv
#   - cash_bridge_path.csv (DCC cash bridge): stage_artifacts/WT_WT-S20260504_002/cash_bridge_path.csv
#
# Output (canonical sleeve-level, columns Date + weight_str1715 + weight_cash):
#   - stage_artifacts/WT_WT-S20260504_002/weights.csv (canonical = M4+DCC_VolTarget primary)
#   - stage_artifacts/WT_WT-S20260504_002/weights_variants/S1.csv
#   - stage_artifacts/WT_WT-S20260504_002/weights_variants/DCC_VolTarget.csv
#   - stage_artifacts/WT_WT-S20260504_002/weights_variants/M4+DCC_VolTarget.csv
#   - stage_artifacts/WT_WT-S20260504_002/cash_definition_audit.json
#
# Sleeve-level rationale:
#   - Parent strategy STR_1715 is a sleeve (top20 risk holdings).
#   - For sizing_only WT, we manage the sleeve allocation, not individual ticker weights.
#   - target_weights dict not emitted (legacy parent pattern preserved); per-ticker constraints
#     remain enforced inside parent run_all.R (max 20, bounds [0,0.20], Σw_inside_sleeve = 1).
#   - Sleeve-level Σ (weight_str1715 + weight_cash) = 1.0.
#
# Cash overlap rule (M4+DCC_VolTarget):
#   weight_cash_combined = max(weight_cash_M4, weight_cash_DCC)
#   weight_str1715_combined = 1 - weight_cash_combined
#   Rationale: defensive - whichever overlay calls for more cash dominates. NOT additive
#   (would double-count cash). Single cash sleeve (M4 or DCC, whichever is more conservative).

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
PARENT_WT <- "WT-P20260429_002"

stage_dir <- file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID))
variants_dir <- file.path(stage_dir, "weights_variants")

cat("=== 3-strategy weight variant assembly ===\n")
cat("WT:", WT_ID, "\n")
cat("Parent:", PARENT_WT, "\n\n")

# --- Load inputs ---
parent_w_path <- file.path(ROOT, "qepm/mailbox/worktask", PARENT_WT, "weights.csv")
sigma_path <- file.path(stage_dir, "sigma_p_forecast.csv")
cb_path <- file.path(stage_dir, "cash_bridge_path.csv")

parent_w <- fread(parent_w_path)
sigma <- fread(sigma_path)
cb <- fread(cb_path)

cat("Parent weights:", nrow(parent_w), "rows | range:",
    as.character(min(parent_w$Date)), "→", as.character(max(parent_w$Date)), "\n")
cat("Sigma forecast:", nrow(sigma), "rows | active:",
    sum(!is.na(sigma$sigma_p_annual_forecast)), "\n")
cat("Cash bridge:", nrow(cb), "rows | active:", sum(!is.na(cb$scale_factor)), "\n\n")

# --- Year-month join (parent uses month-start, sigma uses bizday-shifted dates) ---
parent_w[, ym := format(as.Date(Date), "%Y-%m")]
cb[, ym := format(as.Date(date), "%Y-%m")]

# cb already has scale_factor + cash_bridge. Forward-fill within year-month if duplicates.
cb_unique <- cb[, .(scale_factor = first(scale_factor),
                    cash_bridge_dcc = first(cash_bridge),
                    sigma_p_annual_forecast = NA_real_),
                by = ym]
# Pull sigma_p_annual_forecast from sigma (same ym)
sigma[, ym := format(as.Date(date), "%Y-%m")]
sigma_unique <- sigma[, .(sigma_p_annual_forecast = first(sigma_p_annual_forecast)), by = ym]

cb_unique <- merge(cb_unique[, .(ym, scale_factor, cash_bridge_dcc)],
                   sigma_unique, by = "ym", all.x = TRUE)

# Merge into parent
combined <- merge(parent_w[, .(Date, ym, weight_str1715_M4 = weight_str1715,
                              weight_cash_M4 = weight_cash)],
                  cb_unique, by = "ym", all.x = TRUE, sort = FALSE)
combined <- combined[order(Date)]

cat("Merged rows:", nrow(combined), "\n")
cat("Merged rows with DCC active:", sum(!is.na(combined$scale_factor)), "\n\n")

# --- Strategy 1: S1 baseline (no overlay) ---
S1 <- combined[, .(Date, weight_str1715 = 1.0, weight_cash = 0.0)]

# --- Strategy 2: DCC_VolTarget only (no M4) ---
# weight_str1715 = scale_factor; weight_cash = cash_bridge_dcc
# Where DCC inactive (burn-in 2004-01 ~ 2009-01): full sleeve = 1.0
DCC_VolTarget <- combined[, .(
  Date,
  weight_str1715 = ifelse(is.na(scale_factor), 1.0, scale_factor),
  weight_cash    = ifelse(is.na(cash_bridge_dcc), 0.0, cash_bridge_dcc)
)]
# Sanity: clamp to [0,1] just in case (DCC can theoretically scale > 1 if forecast < target,
# but vol target rule sets scale = min(target/forecast, 1.0) per project policy — re-enforce here)
DCC_VolTarget[, weight_str1715 := pmin(pmax(weight_str1715, 0), 1)]
DCC_VolTarget[, weight_cash := pmin(pmax(weight_cash, 0), 1)]
# Renormalize (should already be Σ=1)
DCC_VolTarget[, total := weight_str1715 + weight_cash]
DCC_VolTarget[abs(total - 1) > 1e-6, weight_cash := 1 - weight_str1715]
DCC_VolTarget[, total := NULL]

# --- Strategy 3: M4 + DCC_VolTarget (combined cash overlay) ---
# Rule: weight_cash_combined = max(M4_cash, DCC_cash) — defensive, no double-count
# weight_str1715_combined = 1 - weight_cash_combined
M4_DCC <- combined[, .(
  Date,
  weight_cash_M4   = ifelse(is.na(weight_cash_M4), 0.0, weight_cash_M4),
  weight_cash_DCC  = ifelse(is.na(cash_bridge_dcc), 0.0, cash_bridge_dcc)
)]
M4_DCC[, weight_cash := pmax(weight_cash_M4, weight_cash_DCC)]
M4_DCC[, weight_cash := pmin(pmax(weight_cash, 0), 1)]
M4_DCC[, weight_str1715 := 1 - weight_cash]
M4_DCC[, c("weight_cash_M4", "weight_cash_DCC") := NULL]
setcolorder(M4_DCC, c("Date", "weight_str1715", "weight_cash"))

# --- Validation ---
validate_variant <- function(dt, name) {
  stopifnot(all(c("Date", "weight_str1715", "weight_cash") %in% names(dt)))
  total <- dt$weight_str1715 + dt$weight_cash
  cat(sprintf("[%s] N=%d  Σ range=[%.6f, %.6f]  long-only PASS=%s\n",
              name, nrow(dt), min(total), max(total),
              all(dt$weight_str1715 >= -1e-9) && all(dt$weight_cash >= -1e-9)))
  cat(sprintf("[%s] mean(weight_str1715)=%.4f  mean(weight_cash)=%.4f  pct_active=%.1f%%\n",
              name, mean(dt$weight_str1715), mean(dt$weight_cash),
              100 * mean(dt$weight_cash > 0)))
  stopifnot(max(abs(total - 1)) < 1e-6)
  stopifnot(all(dt$weight_str1715 >= -1e-9))
  stopifnot(all(dt$weight_cash >= -1e-9))
}

cat("\n=== Variant validation ===\n")
validate_variant(S1, "S1")
validate_variant(DCC_VolTarget, "DCC_VolTarget")
validate_variant(M4_DCC, "M4+DCC_VolTarget")

# --- Schedule density check ---
# Risk pkg expects 208 active months (DCC) vs full 267 parent rows (DCC inactive 2004-01 ~ 2009-01 = 60 burn-in months).
# Schedule density (vs parent reference 267 monthly schedule):
n_parent <- nrow(parent_w)
density_S1 <- nrow(S1) / n_parent
density_DCC <- nrow(DCC_VolTarget) / n_parent
density_M4DCC <- nrow(M4_DCC) / n_parent
cat(sprintf("\nSchedule density vs parent (%d months):\n", n_parent))
cat(sprintf("  S1: %.4f  DCC_VolTarget: %.4f  M4+DCC_VolTarget: %.4f\n",
            density_S1, density_DCC, density_M4DCC))
stopifnot(density_S1 >= 0.95, density_DCC >= 0.95, density_M4DCC >= 0.95)

# --- Write outputs ---
fwrite(S1[, .(Date, weight_str1715, weight_cash)], file.path(variants_dir, "S1.csv"))
fwrite(DCC_VolTarget[, .(Date, weight_str1715, weight_cash)], file.path(variants_dir, "DCC_VolTarget.csv"))
fwrite(M4_DCC[, .(Date, weight_str1715, weight_cash)], file.path(variants_dir, "M4+DCC_VolTarget.csv"))

# Canonical = M4+DCC_VolTarget (primary recommendation per request: combined defensive)
fwrite(M4_DCC[, .(Date, weight_str1715, weight_cash)], file.path(stage_dir, "weights.csv"))

cat("\nWritten:\n")
cat("  ", file.path(variants_dir, "S1.csv"), "\n")
cat("  ", file.path(variants_dir, "DCC_VolTarget.csv"), "\n")
cat("  ", file.path(variants_dir, "M4+DCC_VolTarget.csv"), "\n")
cat("  ", file.path(stage_dir, "weights.csv"), " (canonical = M4+DCC_VolTarget)\n")

# --- Cash definition audit (M4 vs DCC overlap stats) ---
overlap_dt <- combined[, .(Date, weight_cash_M4 = weight_cash_M4,
                            weight_cash_DCC = ifelse(is.na(cash_bridge_dcc), 0, cash_bridge_dcc))]
overlap_dt[, weight_cash_M4 := ifelse(is.na(weight_cash_M4), 0, weight_cash_M4)]
overlap_dt[, both_active := weight_cash_M4 > 0 & weight_cash_DCC > 0]
overlap_dt[, only_M4_active := weight_cash_M4 > 0 & weight_cash_DCC == 0]
overlap_dt[, only_DCC_active := weight_cash_M4 == 0 & weight_cash_DCC > 0]
overlap_dt[, neither_active := weight_cash_M4 == 0 & weight_cash_DCC == 0]

cash_audit <- list(
  task_id = WT_ID,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  cash_combination_rule = "weight_cash_combined = max(weight_cash_M4, weight_cash_DCC); weight_str1715 = 1 - weight_cash_combined",
  rationale_choice = "max() over additive — additive sums would double-count defense allocation, breach Σ=1, drop weight_str1715 below 0",
  alternative_considered = "additive (M4 + DCC capped at some ceiling) — rejected for brittleness + interpretability",
  total_months = nrow(overlap_dt),
  cash_activation = list(
    M4_active_months = sum(overlap_dt$weight_cash_M4 > 0),
    DCC_active_months = sum(overlap_dt$weight_cash_DCC > 0),
    both_active = sum(overlap_dt$both_active),
    only_M4_active = sum(overlap_dt$only_M4_active),
    only_DCC_active = sum(overlap_dt$only_DCC_active),
    neither_active = sum(overlap_dt$neither_active)
  ),
  cash_levels = list(
    mean_cash_M4_total_sample = mean(overlap_dt$weight_cash_M4),
    mean_cash_DCC_total_sample = mean(overlap_dt$weight_cash_DCC),
    mean_cash_combined_total_sample = mean(pmax(overlap_dt$weight_cash_M4, overlap_dt$weight_cash_DCC)),
    mean_cash_M4_when_active = ifelse(sum(overlap_dt$weight_cash_M4 > 0) > 0,
                                       mean(overlap_dt$weight_cash_M4[overlap_dt$weight_cash_M4 > 0]),
                                       NA_real_),
    mean_cash_DCC_when_active = ifelse(sum(overlap_dt$weight_cash_DCC > 0) > 0,
                                        mean(overlap_dt$weight_cash_DCC[overlap_dt$weight_cash_DCC > 0]),
                                        NA_real_)
  ),
  dominance_when_both_active = list(
    M4_dominates = sum(overlap_dt$both_active & overlap_dt$weight_cash_M4 >= overlap_dt$weight_cash_DCC),
    DCC_dominates = sum(overlap_dt$both_active & overlap_dt$weight_cash_DCC > overlap_dt$weight_cash_M4)
  ),
  schedule_density = list(
    S1 = density_S1,
    DCC_VolTarget = density_DCC,
    M4_plus_DCC_VolTarget = density_M4DCC,
    parent_n_dates = n_parent,
    threshold = 0.95,
    pass = all(c(density_S1, density_DCC, density_M4DCC) >= 0.95)
  )
)
write_json(cash_audit, file.path(stage_dir, "cash_definition_audit.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("Wrote cash_definition_audit.json\n")

# --- LRO MRC stub (sleeve-level — parent strategy + cash, MRC trivial under fully-invested sleeve) ---
# For sizing_only sleeve-level WT, MRC is trivial (str1715 contributes ~all risk, cash 0).
# Provide tabular stub for downstream forge / judge inheritance.
lro_mrc <- data.table(
  Date = combined$Date,
  weight_str1715 = M4_DCC$weight_str1715,
  weight_cash = M4_DCC$weight_cash,
  sigma_p_annual_forecast = combined$sigma_p_annual_forecast,
  scale_factor = combined$scale_factor,
  mrc_str1715_share = 1.0,  # cash σ = 0, all risk in sleeve
  mrc_cash_share = 0.0,
  effective_sigma_p_annual = ifelse(is.na(combined$sigma_p_annual_forecast), NA_real_,
                                     M4_DCC$weight_str1715 * combined$sigma_p_annual_forecast)
)
fwrite(lro_mrc, file.path(stage_dir, "lro_portfolio_mrc.csv"))
cat("Wrote lro_portfolio_mrc.csv\n")

cat("\n=== SUCCESS — 3 variants assembled ===\n")
