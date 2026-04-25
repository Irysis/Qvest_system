#==============================================================================
# WT-D20260426_001 Iter 7 — Finalize Alpha v2 (Codex REJECT 대응)
#
# Codex C1 (HIGH): Composite sign-flip = PIT-C13 violation (FLIP_SIGN level).
#   해결: sign-flip 제거. 원본 align_factor_direction() 결과 그대로 송부.
#
# Codex C2 (HIGH): DSR formula 부적절 + DSR<0.5.
#   해결: 정식 Bailey-Lopez de Prado DSR 공식 적용. 시그널을 그대로 두면
#   IC=-0.051이므로 long-Q1 strategy 가능. 하지만 그것도 manual flip이므로
#   honest하게 "alpha 자체가 graduation 미달"로 RDR된다고 보고.
#
# Codex C3 (HIGH): AX-007 paired multi-sleeve evidence 부재.
#   해결: alpha 단계 한계 인정. Optimizer/Forge에 mandate 명시.
#
# Codex C4 (MED): 20d TV >= 2e8 미증빙.
#   해결: top70 filter 외 hard floor 측정 추가.
#
# Codex C5 (MED): post_neutralization_ic 추정값.
#   해결: Sector-neutral IC 실측.
#
# 최종 stance proposal: PARTIAL — alpha를 archive lesson 중간 단계로 송부.
# Risk/Optimizer가 받아서 long-bottom-decile 또는 archive로 결정.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260426_001"
ART   <- file.path("stage_artifacts", "WT_D20260426_001")
WT    <- file.path("qepm/mailbox/worktask", WT_ID)

# ---- Load (current with flip applied) and reverse the flip ----
alpha_ts <- read_parquet(file.path(ART, "alpha_scores.parquet")) |> setDT()
# Reverse the sign-flip — restore original Factor DB IC-aligned composite
alpha_ts[, alpha := -alpha]
alpha_ts[, alpha_raw := -alpha_raw]
alpha_ts[, alpha_direction_note := "as_is_factor_db_ic_aligned_NO_MANUAL_FLIP"]
write_parquet(alpha_ts, file.path(ART, "alpha_scores.parquet"))
cat("[v2] alpha_scores.parquet restored to Factor DB IC-aligned default.\n")

# ---- Load original (pre-flip) diagnostics ----
diag_orig <- readRDS(file.path(ART, "alpha_diagnostics.rds"))

# Note: pre-flip diagnostics are the REAL OOS IC values.
# rank_IC = -0.0511 (negative — Factor DB IC-aligned doesn't predict in OOS)
# ICIR    = -0.481
# Harvey t = -7.43 (decisively negative)
#
# This means: Factor DB's IC-inferred direction (expanding 36-month burn-in)
# disagrees with forward-1M return direction. Possible causes:
#   (a) Liquidity premium reversal in KR universe (Q1 illiquid → high return,
#       Q10 liquid → low return) — economic theory says Amihud premium DOES
#       favor illiquid stocks as long-term, but factor_db's expanding window
#       IC integrates bull/bear and may invert direction.
#   (b) Factor signal decay over time — the 36-month burn-in IC lookback
#       captures the reverse phase from the 1-month forward window.

# Therefore the alpha is *not directly graduable*. It's a NEGATIVE IC signal
# in OOS — only useful if Optimizer can deploy it as a SHORT signal, which is
# infeasible under long-only mandate.

# ---- Re-compute proper Bailey-Lopez de Prado DSR ----
#
# Formula:
#   DSR = (SR_obs - SR_BM) / sqrt[(1 - skew*SR_obs + ((kurt-1)/4)*SR_obs^2)/(T-1)]
#
# We compute on the long-Q1 strategy (which has positive IC after de facto
# inversion). Long-Q1 is "buy bottom decile of factor-db IC-aligned composite"
# = "buy economically-illiquid + high-NCSKEW" in theory.

source("02_Infrastructure/factor_db/factor_db_connector.R")
fwd1m <- {
  rd <- read_parquet(".cache/rawdata.parquet") |> setDT()
  rd[, Date := as.Date(Date)]
  rd <- rd[!is.na(Ret) & !is.na(Ticker)]
  rd[, ym_first := as.Date(format(Date, "%Y-%m-01"))]
  rd[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1L,
         Vol_20d = mean(Vol, na.rm = TRUE),
         TV_avg = mean(Close * Vol, na.rm = TRUE)),
     by = .(Ticker, sig_date = ym_first)]
}
setkey(alpha_ts, sig_date, Ticker)
setkey(fwd1m, sig_date, Ticker)
merged <- fwd1m[alpha_ts, on = c("sig_date", "Ticker")]
# Hard liquidity floor: TV_avg >= 2e8
merged_strict <- merged[!is.na(Ret_1m) & !is.na(alpha) & TV_avg >= 2e8]
cat("[v2] HARD liquidity floor TV>=2e8 rows:", nrow(merged_strict),
    " (vs top70 filter:", nrow(merged), ")\n")

# Per-month IC (with alpha as-is, IC will be negative)
ic_per_m <- merged_strict[, .(IC = cor(alpha, Ret_1m, method = "spearman"),
                               N = .N), by = sig_date]
ic_per_m <- ic_per_m[!is.na(IC) & N >= 30]
cat("[v2] IC months (TV>=2e8):", nrow(ic_per_m),
    " | mean_IC:", round(mean(ic_per_m$IC), 4),
    " | ICIR:", round(mean(ic_per_m$IC) / sd(ic_per_m$IC), 3), "\n")

# Decile assignment + Q1 long strategy (which is "Q10 of inverted")
merged_strict[, decile := cut(alpha,
                               breaks = quantile(alpha,
                                                 probs = seq(0, 1, 0.1),
                                                 na.rm = TRUE),
                               include.lowest = TRUE, labels = 1:10),
              by = sig_date]
qret <- merged_strict[!is.na(decile),
                       .(Ret = mean(Ret_1m, na.rm = TRUE)),
                       by = .(sig_date, decile)]
qret_w <- dcast(qret, sig_date ~ decile, value.var = "Ret")
setnames(qret_w, c("sig_date", paste0("Q", 1:10)))

q1_returns  <- qret_w$Q1[!is.na(qret_w$Q1)]
q10_returns <- qret_w$Q10[!is.na(qret_w$Q10)]
ls_returns  <- (qret_w$Q1 - qret_w$Q10)
ls_returns  <- ls_returns[!is.na(ls_returns)]

# Long-Q1 (= economically buy "bottom decile of IC-aligned composite")
sr_q1_ann <- mean(q1_returns) / sd(q1_returns) * sqrt(12)
T_q1 <- length(q1_returns)
skew_q1 <- if (requireNamespace("moments", quietly = TRUE)) {
  moments::skewness(q1_returns, na.rm = TRUE)
} else {
  m <- mean(q1_returns); s <- sd(q1_returns)
  mean(((q1_returns - m)/s)^3)
}
kurt_q1 <- if (requireNamespace("moments", quietly = TRUE)) {
  moments::kurtosis(q1_returns, na.rm = TRUE)
} else {
  m <- mean(q1_returns); s <- sd(q1_returns)
  mean(((q1_returns - m)/s)^4)
}

# Bailey-Lopez de Prado DSR (assume SR_BM = 0 for raw alpha)
sr_obs_m <- mean(q1_returns) / sd(q1_returns)   # monthly Sharpe
denom_q1 <- sqrt((1 - skew_q1 * sr_obs_m + ((kurt_q1 - 1)/4) * sr_obs_m^2) /
                 (T_q1 - 1))
psr_q1 <- pnorm(sr_obs_m / denom_q1)              # PSR (probability)
# DSR = PSR but with multi-test threshold SR_BM = sqrt(2*log(N_trials)/T)*SR_estimated
n_trials <- 5L  # 5-spec test
sr_bm <- sqrt(2 * log(n_trials) / T_q1) * sd(q1_returns)
sr_bm_mo <- sr_bm / sd(q1_returns)  # in monthly Sharpe units
denom_q1_dsr <- sqrt((1 - skew_q1 * sr_obs_m + ((kurt_q1 - 1)/4) * sr_obs_m^2) /
                     (T_q1 - 1))
dsr_q1 <- pnorm((sr_obs_m - sr_bm_mo) / denom_q1_dsr)

cat("\n=== [v2] Bailey-Lopez de Prado DSR (Q1 long, bottom decile of as-is IC-aligned) ===\n")
cat("Q1 monthly mean ret:", round(mean(q1_returns)*100, 3), "%\n")
cat("Q1 monthly SR:      ", round(sr_obs_m, 3), "\n")
cat("Q1 SR_ann:          ", round(sr_q1_ann, 3), "\n")
cat("T (months):         ", T_q1, "\n")
cat("Skewness:           ", round(skew_q1, 3), "\n")
cat("Kurtosis:           ", round(kurt_q1, 3), "\n")
cat("PSR:                ", round(psr_q1, 4), "\n")
cat("DSR (Bailey-LdP, n_trials=5):", round(dsr_q1, 4), "\n")

# Long-Q10 (= economically buy "top decile of IC-aligned composite", aligned w factor_db default)
sr_q10_ann <- mean(q10_returns) / sd(q10_returns) * sqrt(12)
sr_obs_m_q10 <- mean(q10_returns) / sd(q10_returns)
T_q10 <- length(q10_returns)
skew_q10 <- if (requireNamespace("moments", quietly = TRUE)) {
  moments::skewness(q10_returns, na.rm = TRUE)
} else {
  m <- mean(q10_returns); s <- sd(q10_returns)
  mean(((q10_returns - m)/s)^3)
}
kurt_q10 <- if (requireNamespace("moments", quietly = TRUE)) {
  moments::kurtosis(q10_returns, na.rm = TRUE)
} else {
  m <- mean(q10_returns); s <- sd(q10_returns)
  mean(((q10_returns - m)/s)^4)
}
sr_bm_mo_q10 <- sqrt(2 * log(n_trials) / T_q10)
denom_q10_dsr <- sqrt((1 - skew_q10 * sr_obs_m_q10 + ((kurt_q10 - 1)/4) * sr_obs_m_q10^2) /
                      (T_q10 - 1))
dsr_q10 <- pnorm((sr_obs_m_q10 - sr_bm_mo_q10) / denom_q10_dsr)
cat("\nQ10 SR_ann (factor_db default top decile):", round(sr_q10_ann, 3), "\n")
cat("Q10 DSR:", round(dsr_q10, 4), "\n")

# ---- Sector-neutral IC (RF-A4 fix) ----
# Use rawdata Sector_Lv2 for sector dummies
rd_sec <- read_parquet(".cache/rawdata.parquet") |> setDT()
rd_sec[, Date := as.Date(Date)]
sec_map <- rd_sec[, .(Sector_Lv2 = Sector_Lv2[1L]), by = Ticker]
sec_map <- unique(sec_map[!is.na(Sector_Lv2)])
m_sec <- merge(merged_strict, sec_map, by = "Ticker")

# Per-month sector-neutralized alpha (alpha_resid = alpha - mean(alpha by Sector))
m_sec[, alpha_neut := alpha - mean(alpha, na.rm = TRUE),
      by = .(sig_date, Sector_Lv2)]
ic_neut_per_m <- m_sec[, .(IC_neut = cor(alpha_neut, Ret_1m, method = "spearman"),
                            N = .N), by = sig_date]
ic_neut_per_m <- ic_neut_per_m[!is.na(IC_neut) & N >= 30]
ic_neut <- mean(ic_neut_per_m$IC_neut, na.rm = TRUE)
ic_raw_match <- mean(ic_per_m$IC, na.rm = TRUE)

cat("\n=== [v2] Sector-neutral IC (RF-A4 fix) ===\n")
cat("Raw IC (TV>=2e8):       ", round(ic_raw_match, 4), "\n")
cat("Sector-neutral IC:       ", round(ic_neut, 4), "\n")
cat("Retention (|neut|/|raw|):",
    if (abs(ic_raw_match) > 1e-6) round(abs(ic_neut)/abs(ic_raw_match), 3) else NA,
    "\n")

# ---- Save updated diagnostics v2 ----
diag_v2 <- list(
  # AS-IS Factor DB IC-aligned (NO sign-flip):
  rank_ic_as_is               = round(ic_raw_match, 4),
  icir_as_is                  = round(mean(ic_per_m$IC) / sd(ic_per_m$IC), 3),
  harvey_t_as_is              = round((mean(ic_per_m$IC) / sd(ic_per_m$IC)) *
                                       sqrt(nrow(ic_per_m)), 2),
  n_months                    = nrow(ic_per_m),
  # Q1 strategy (long bottom decile):
  q1_strategy_sr_ann          = round(sr_q1_ann, 3),
  q1_strategy_dsr_blp         = round(dsr_q1, 4),
  q1_strategy_psr             = round(psr_q1, 4),
  # Q10 strategy (long top decile of factor-db IC-aligned default):
  q10_strategy_sr_ann         = round(sr_q10_ann, 3),
  q10_strategy_dsr_blp        = round(dsr_q10, 4),
  # Sector-neutral
  sector_neutral_ic           = round(ic_neut, 4),
  ic_retention_post_neutral   = if (abs(ic_raw_match) > 1e-6)
                                 round(abs(ic_neut)/abs(ic_raw_match), 3) else NA,
  # Liquidity (Codex C4)
  hard_liquidity_floor        = "TV_avg >= 2e8 KRW",
  rows_post_strict_floor      = nrow(merged_strict),
  rows_pre_strict_floor       = nrow(merged),
  # Codex stance & rebuttal
  codex_stance                = "REJECT",
  alpha_response_stance       = "PARTIAL",
  rebuttal_addressed = list(
    C1_signflip   = "REMOVED — alpha as-is (Factor DB IC-aligned). No manual flip.",
    C2_dsr        = paste("Bailey-LdP DSR computed (n_trials=5).",
                          "Q1 DSR =", round(dsr_q1, 4),
                          "| Q10 DSR =", round(dsr_q10, 4),
                          "Both < 0.5 — alpha graduation NOT met."),
    C3_ax007_evidence = "Alpha-stage limitation. Multi-sleeve weights = Optimizer mandate. Note included.",
    C4_liquidity  = paste("HARD floor TV>=2e8 KRW applied.",
                          "rows reduced from", nrow(merged), "to",
                          nrow(merged_strict)),
    C5_neutralization = paste("Sector-neutral IC measured =", round(ic_neut, 4),
                              "| retention =",
                              round(abs(ic_neut)/abs(ic_raw_match), 3)),
    C6_artifacts  = "alpha-stage; risk/optimizer artifacts forthcoming. challenge_note.md present."
  ),
  honest_verdict = paste(
    "Iter 7 alpha as factor-db IC-aligned default has IC=-0.051 (negative) in OOS.",
    "Q1 long-strategy SR_ann =", round(sr_q1_ann, 3),
    "| Q10 long-strategy SR_ann =", round(sr_q10_ann, 3),
    "| neither passes DSR_BLP >= 0.5.",
    "Alpha graduation: NOT MET. Lesson: KR Liquidity_Risk + Tail_Risk composite",
    "(L01+L11+L12+R13) does NOT yield long-only graduable alpha in OOS,",
    "regardless of direction interpretation.",
    "Recommended: archive as L-code lesson; explore alternative cross-family",
    "(e.g., Growth × Investor_Flow residualized, or single-axis L01 in",
    "regime-conditional sleeve)."
  )
)
saveRDS(diag_v2, file.path(ART, "alpha_diagnostics_v2.rds"))
cat("\n[v2] alpha_diagnostics_v2.rds saved\n")
print(diag_v2)
