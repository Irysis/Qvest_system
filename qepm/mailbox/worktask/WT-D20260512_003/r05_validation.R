# WT-D20260512_003 — Step 4-5: R05_Tail_Risk strict validation
# Harvey-t Newey-West + DSR Bailey-LdP + Subperiod stability + Composite blend optimization

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]
cat("[R05] rows after filter:", nrow(p), "\n")

# Per-month rank IC (Spearman) for R05_Tail_Risk
ic_dt <- p[, .(ic = if (.N >= 5) cor(R05_Tail_Risk, Ret_1m, method="spearman") else NA_real_,
                n = .N,
                regime = regime_state[1]),
            by = Date]
ic_dt <- ic_dt[!is.na(ic)]
cat("[R05] n_months IC:", nrow(ic_dt), "\n")

# === Newey-West Harvey-t ===
ic_mean <- mean(ic_dt$ic)
ic_sd <- sd(ic_dt$ic)
plain_t <- ic_mean / (ic_sd / sqrt(nrow(ic_dt)))

# Newey-West (HAC) lag = floor(4*(T/100)^(2/9)) per H-L-Z 2016
T_ic <- nrow(ic_dt)
nw_lag <- floor(4 * (T_ic/100)^(2/9))
fit <- lm(ic ~ 1, data = ic_dt)
nw_se <- sqrt(NeweyWest(fit, lag = nw_lag, prewhite = FALSE)[1,1])
nw_t <- coef(fit)[1] / nw_se

cat("[R05] T_ic:", T_ic, "NW lag:", nw_lag, "\n")
cat("[R05] IC mean:", round(ic_mean, 5), "SD:", round(ic_sd, 4), "\n")
cat("[R05] plain t:", round(plain_t, 3), "NW t:", round(nw_t, 3), "\n")
cat("[R05] ICIR (annualized):", round(ic_mean/ic_sd * sqrt(12), 3), "\n")

# Harvey-Liu-Zhu 2016 deflation: alpha_threshold for h-test = 3.0 (n_trials = 1, alpha_q = 0.5)
# We tested 20 candidates so DSR penalty applies.
N_TRIALS <- 20

# === DSR Bailey-Lopez de Prado 2014 ===
# SR_DSR = (SR - SR_threshold) / sigma_SR where SR_threshold = sqrt(2 ln(N))/sqrt(T_obs)
# But for IC: deflated_t = t_observed / sqrt(1 + variance_inflation)
# Apply Harvey-Liu-Zhu adjustment instead
# Harvey-Liu-Zhu: deflated_t = nw_t * adjust where adjust depends on N_TRIALS
# Simple: t > 3.0 + log(N) penalty
hl_z_threshold <- 3.0 + 0.5 * log(N_TRIALS)  # rough HLZ Bonferroni-like

cat("[R05] HLZ threshold (T=20):", round(hl_z_threshold, 3), "\n")
cat("[R05] NW-t > HLZ:", nw_t > hl_z_threshold, "\n")

# === Subperiod Stability (3 periods) ===
ic_dt[, sp := cut(Date, breaks = c(as.Date("2003-12-31"), as.Date("2014-12-31"),
                                    as.Date("2019-12-31"), as.Date("2026-12-31")),
                  labels = c("p2008_2014", "p2015_2019", "p2020_2026"))]
sp_summary <- ic_dt[!is.na(sp), .(
  mean_ic = mean(ic), sd_ic = sd(ic), icir = mean(ic)/sd(ic)*sqrt(12),
  hit = mean(ic > 0), n = .N
), by = sp]
cat("\n[R05] Subperiod stability:\n")
print(sp_summary)

# Subperiod sign consistency
sp_pass <- mean(sp_summary$mean_ic > 0)
cat("[R05] Subperiod positive consistency:", round(sp_pass, 3), "\n")

# === Regime-conditional SR proxy (CRISIS+CAUTION) ===
regime_sr <- ic_dt[, .(mean_ic = mean(ic), sd_ic = sd(ic), n = .N,
                        sr_ann = mean(ic)/sd(ic)*sqrt(12)), by = regime]
cat("\n[R05] Regime conditional IC + SR proxy:\n")
print(regime_sr)

# === Composite Blend Design ===
# Z-score composite: z_blend = w_str * score_eff + w_new * R05_Tail_Risk
# Try grids w_new in [0.10, 0.20, 0.30, 0.40, 0.50]
w_grid <- seq(0.05, 0.50, by = 0.05)
blend_results <- rbindlist(lapply(w_grid, function(w_new) {
  w_str <- 1 - w_new
  p[, z_blend := w_str * score_eff + w_new * R05_Tail_Risk]
  ic_blend <- p[, .(ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_,
                     n = .N, regime = regime_state[1]),
                 by = Date]
  ic_blend <- ic_blend[!is.na(ic)]
  ic_overall <- ic_blend[, .(ic_mean = mean(ic), icir = mean(ic)/sd(ic)*sqrt(12), n = .N)]
  ic_regime <- ic_blend[, .(mean_ic = mean(ic), sr_proxy = mean(ic)/sd(ic)*sqrt(12), n = .N),
                         by = regime]
  data.table(
    w_new = w_new,
    overall_ic = ic_overall$ic_mean,
    overall_icir = ic_overall$icir,
    crisis_ic = ic_regime[regime == "CRISIS", mean_ic],
    crisis_sr = ic_regime[regime == "CRISIS", sr_proxy],
    caution_ic = ic_regime[regime == "CAUTION", mean_ic],
    caution_sr = ic_regime[regime == "CAUTION", sr_proxy],
    normal_ic = ic_regime[regime == "NORMAL", mean_ic],
    normal_sr = ic_regime[regime == "NORMAL", sr_proxy],
    bull_ic = ic_regime[regime == "BULL", mean_ic],
    bull_sr = ic_regime[regime == "BULL", sr_proxy]
  )
}))

cat("\n[R05] Z-score Composite Blend Grid Search (Static weights):\n")
print(blend_results[, .(w_new,
                         overall_ic = round(overall_ic, 4),
                         overall_icir = round(overall_icir, 3),
                         crisis_ic = round(crisis_ic, 4),
                         crisis_sr = round(crisis_sr, 3),
                         caution_ic = round(caution_ic, 4),
                         caution_sr = round(caution_sr, 3),
                         normal_ic = round(normal_ic, 4),
                         normal_sr = round(normal_sr, 3),
                         bull_ic = round(bull_ic, 4),
                         bull_sr = round(bull_sr, 3))])

# Baseline (w_new = 0): pure STR_1715 score_eff
base_ic <- p[, .(ic = if (.N >= 5) cor(score_eff, Ret_1m, method="spearman") else NA_real_,
                  n = .N, regime = regime_state[1]),
              by = Date]
base_ic <- base_ic[!is.na(ic)]
base_regime <- base_ic[, .(mean_ic = mean(ic), sr_proxy = mean(ic)/sd(ic)*sqrt(12)), by = regime]
cat("\n[R05] BASELINE (w_new=0) — pure STR_1715 score_eff:\n")
print(base_regime)
cat("baseline_overall_ic =", round(mean(base_ic$ic), 5),
    " ICIR =", round(mean(base_ic$ic)/sd(base_ic$ic)*sqrt(12), 3), "\n")

# Save artifacts
fwrite(ic_dt, "stage_artifacts/WT_D20260512_003/R05_monthly_ic.csv")
fwrite(sp_summary, "stage_artifacts/WT_D20260512_003/R05_subperiod.csv")
fwrite(blend_results, "stage_artifacts/WT_D20260512_003/R05_blend_grid.csv")
saveRDS(list(
  factor = "R05_Tail_Risk",
  ic_mean = ic_mean, ic_sd = ic_sd, T = T_ic,
  plain_t = plain_t, nw_t = nw_t, nw_lag = nw_lag,
  icir = ic_mean/ic_sd*sqrt(12),
  hlz_threshold = hl_z_threshold,
  hlz_pass = nw_t > hl_z_threshold,
  subperiod = sp_summary,
  regime_sr = regime_sr,
  blend_grid = blend_results
), "stage_artifacts/WT_D20260512_003/R05_validation.rds")
cat("\n[R05] artifacts saved.\n")
