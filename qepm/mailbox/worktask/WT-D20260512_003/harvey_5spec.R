# WT-D20260512_003 — Step 6d: Harvey-t 5-spec robustness (Harvey-Liu-Zhu 2016 RFS)
# 다중검정 보정 + Newey-West HAC + 5 specifications

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
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

# === 5 specs ===
# Spec 1: Composite z_blend (full universe, all months)
# Spec 2: R05_Tail_Risk standalone
# Spec 3: Composite z_blend stress only (CAUTION+CRISIS)
# Spec 4: Composite z_blend full but exclude 2008 (COVID + GFC sensitivity)
# Spec 5: Composite z_blend Pearson cor IC (vs Spearman in Spec 1)

run_spec <- function(p_in, alpha_col, label, ret_col = "Ret_1m",
                     month_filter = NULL, cor_method = "spearman") {
  pp <- copy(p_in)
  if (!is.null(month_filter)) pp <- pp[regime_state %in% month_filter]
  ic_dt <- pp[, .(ic = if (.N >= 5) cor(get(alpha_col), get(ret_col), method=cor_method) else NA_real_,
                   n = .N),
               by = Date]
  ic_dt <- ic_dt[!is.na(ic)]
  T_ic <- nrow(ic_dt)
  ic_mean <- mean(ic_dt$ic); ic_sd <- sd(ic_dt$ic)
  plain_t <- ic_mean / (ic_sd / sqrt(T_ic))
  nw_lag <- max(1L, floor(4 * (T_ic/100)^(2/9)))
  fit <- lm(ic ~ 1, data = ic_dt)
  nw_se <- sqrt(NeweyWest(fit, lag = nw_lag, prewhite = FALSE)[1,1])
  nw_t <- coef(fit)[1] / nw_se
  icir <- ic_mean / ic_sd * sqrt(12)
  data.table(spec = label, T = T_ic,
             ic_mean = round(ic_mean, 5), ic_sd = round(ic_sd, 4),
             plain_t = round(plain_t, 3), nw_t = round(nw_t, 3),
             icir = round(icir, 3))
}

specs <- list(
  run_spec(p, "z_blend", "Spec1_composite_full_spearman"),
  run_spec(p, "R05_Tail_Risk", "Spec2_R05_standalone_spearman"),
  run_spec(p, "z_blend", "Spec3_composite_stress_only",
           month_filter = c("CAUTION", "CRISIS")),
  run_spec(p[Date >= as.Date("2010-01-01")], "z_blend", "Spec4_composite_2010+_post_GFC"),
  run_spec(p, "z_blend", "Spec5_composite_pearson", cor_method = "pearson")
)
all_specs <- rbindlist(specs)

# HLZ deflation thresholds
N_TRIALS <- 20
hlz_bonf <- qnorm(1 - 0.05 / (2 * N_TRIALS))  # ~3.023
hlz_holm <- 3.0 + 0.5 * log(N_TRIALS)  # ~4.498
all_specs[, hlz_bonf_threshold := round(hlz_bonf, 3)]
all_specs[, hlz_pass_bonf := abs(nw_t) > hlz_bonf]
all_specs[, hlz_pass_3.0 := abs(nw_t) > 3.0]
cat("\n=== Harvey-t 5-spec Robustness ===\n")
print(all_specs)

n_pass <- sum(all_specs$hlz_pass_bonf)
cat(sprintf("\nSpecs passing HLZ Bonferroni (NW-t > %.3f): %d / 5\n",
            hlz_bonf, n_pass))

fwrite(all_specs, "stage_artifacts/WT_D20260512_003/harvey_5spec.csv")
cat("[saved] harvey_5spec.csv\n")
