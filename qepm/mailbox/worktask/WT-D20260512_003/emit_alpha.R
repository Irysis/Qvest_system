# WT-D20260512_003 — Step 7: Emit alpha_package + alpha_scores
# Composite blend: z_blend(t,i) = (1-w_new(t)) * score_eff(t,i) + w_new(t) * R05_Tail_Risk_Z_Aligned(t,i)
# w_new(t) regime-conditional: BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]

SCHEME <- list(BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80)
panel[, w_new := fcase(
  regime_state == "BULL", SCHEME$BULL,
  regime_state == "NORMAL", SCHEME$NORMAL,
  regime_state == "CAUTION", SCHEME$CAUTION,
  regime_state == "CRISIS", SCHEME$CRISIS,
  default = 0.0
)]
panel[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

# Confidence vector based on:
# - Data availability (score_eff + R05 both non-NA)
# - Regime stability (CAUTION/CRISIS less confidence due to small n)
# - Z-score magnitude (low extreme implies higher confidence)
panel[, has_str1715 := !is.na(score_eff)]
panel[, has_r05 := !is.na(R05_Tail_Risk)]
panel[, base_conf := as.integer(has_str1715) * 0.5 + as.integer(has_r05) * 0.5]
panel[, regime_conf := fcase(
  regime_state == "BULL", 0.9,
  regime_state == "NORMAL", 0.9,
  regime_state == "CAUTION", 0.6,  # less data
  regime_state == "CRISIS", 0.5,
  default = 0.5
)]
# Combine
panel[, confidence := pmin(1.0, base_conf * regime_conf)]

# === Save alpha_scores_new.parquet (full panel 268m × all tickers) ===
alpha_scores <- panel[, .(Date, Ticker, score_eff, score_core_z, score_defense_z,
                          R05_Tail_Risk_Z = R05_Tail_Risk,
                          w_new_regime = w_new, z_blend_composite = z_blend,
                          confidence, Ret_1m, regime_state)]
dir.create("stage_artifacts/WT_D20260512_003", showWarnings = FALSE, recursive = TRUE)
write_parquet(alpha_scores, "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")
cat("[emit] alpha_scores_new.parquet rows:", nrow(alpha_scores), "\n")

# === As-of 2026-04-01 alpha_vector (deployment ready) ===
as_of <- as.Date("2026-04-01")
av_dt <- panel[Date == as_of & !is.na(z_blend)]
cat("[emit] as-of", as.character(as_of), "ticker count:", nrow(av_dt), "\n")
cat("[emit] regime state at as-of:", av_dt$regime_state[1], "w_new:", av_dt$w_new[1], "\n")

alpha_vector <- setNames(as.numeric(av_dt$z_blend), av_dt$Ticker)
confidence_vector <- setNames(as.numeric(av_dt$confidence), av_dt$Ticker)

# Top 20 preview
av_top <- av_dt[order(-z_blend)][1:20, .(rank=.I, Ticker,
                                          z_blend = round(z_blend, 4),
                                          score_eff = round(score_eff, 4),
                                          R05 = round(R05_Tail_Risk, 4))]
cat("\n[emit] Top 20 (as-of 2026-04-01):\n")
print(av_top)

# === Save alpha_vector for deployment ===
fwrite(av_dt[, .(Ticker, z_blend_composite = z_blend, score_eff_str1715 = score_eff,
                  R05_Tail_Risk_Z = R05_Tail_Risk, regime_state, w_new, confidence)],
       "stage_artifacts/WT_D20260512_003/alpha_vector_20260401.csv")
cat("[emit] alpha_vector_20260401.csv saved\n")

# === Save summary stats for package ===
av_summary <- list(
  as_of = as.character(as_of),
  n_tickers = nrow(av_dt),
  regime_at_asof = av_dt$regime_state[1],
  w_new_at_asof = av_dt$w_new[1],
  alpha_mean = round(mean(av_dt$z_blend), 5),
  alpha_sd = round(sd(av_dt$z_blend), 5),
  alpha_top20_min = round(av_top[20, z_blend], 5),
  alpha_top20_max = round(av_top[1, z_blend], 5)
)
cat("\nSummary:\n")
print(av_summary)
saveRDS(list(alpha_scores = alpha_scores, alpha_vector = alpha_vector,
              confidence_vector = confidence_vector,
              av_top20 = av_top, summary = av_summary, scheme = SCHEME),
         "stage_artifacts/WT_D20260512_003/alpha_emission.rds")
cat("[emit] alpha_emission.rds saved\n")
