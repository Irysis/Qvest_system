# WT-D20260512_003 — Step 6: FINAL validation of selected scheme
# Best scheme: BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80
# Run: NW-t composite + DSR Bailey-LdP + Subperiod stability + sensitivity

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]

# Best scheme
SCHEME <- list(BULL = 0.05, NORMAL = 0.05, CAUTION = 0.80, CRISIS = 0.80)
p[, w_new := fcase(
  regime_state == "BULL", SCHEME$BULL,
  regime_state == "NORMAL", SCHEME$NORMAL,
  regime_state == "CAUTION", SCHEME$CAUTION,
  regime_state == "CRISIS", SCHEME$CRISIS,
  default = 0.0
)]
p[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

# === IC time series ===
ic_dt <- p[, .(ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_,
                ic_base = if (.N >= 5) cor(score_eff, Ret_1m, method="spearman") else NA_real_,
                ic_r05 = if (.N >= 5) cor(R05_Tail_Risk, Ret_1m, method="spearman") else NA_real_,
                n = .N, regime = regime_state[1]),
            by = Date]
ic_dt <- ic_dt[!is.na(ic) & !is.na(ic_base) & !is.na(ic_r05)]
T_ic <- nrow(ic_dt)
cat("[final] T_ic:", T_ic, "\n")

# === Newey-West Harvey-t (composite) ===
ic_mean <- mean(ic_dt$ic)
ic_sd <- sd(ic_dt$ic)
nw_lag <- floor(4 * (T_ic/100)^(2/9))
fit <- lm(ic ~ 1, data = ic_dt)
nw_se <- sqrt(NeweyWest(fit, lag = nw_lag, prewhite = FALSE)[1,1])
nw_t <- coef(fit)[1] / nw_se
plain_t <- ic_mean / (ic_sd / sqrt(T_ic))
icir <- ic_mean / ic_sd * sqrt(12)

cat("[final-composite] IC mean:", round(ic_mean, 5), "SD:", round(ic_sd, 4), "\n")
cat("[final-composite] plain t:", round(plain_t, 3), "NW t (lag", nw_lag, "):", round(nw_t, 3), "\n")
cat("[final-composite] ICIR:", round(icir, 3), "\n")

# Harvey-Liu-Zhu threshold for N=20 trials
N_TRIALS <- 20
hlz_threshold_bonf <- qnorm(1 - 0.05 / (2 * N_TRIALS))  # Bonferroni
hlz_threshold_holm <- 3.0 + 0.5 * log(N_TRIALS)
cat("[final-composite] HLZ Bonferroni threshold (N=20):", round(hlz_threshold_bonf, 3),
    "  Holm-like:", round(hlz_threshold_holm, 3), "\n")
cat("[final-composite] Pass Bonferroni:", nw_t > hlz_threshold_bonf,
    "  Pass Holm:", nw_t > hlz_threshold_holm, "\n")

# === DSR Bailey-Lopez de Prado 2014 ===
# DSR = (SR - SR_0) / sigma_SR; SR_0 = sqrt(2 ln(N))/sqrt(T)
# Apply on IC-based pseudo-SR
T_obs <- T_ic
SR_threshold_DSR <- sqrt(2 * log(N_TRIALS)) / sqrt(T_obs)
SR_observed <- ic_mean / ic_sd  # monthly SR
# variance: based on autocorr-adjusted; here approximate
SR_var <- (1 - SR_observed * mean(ic_dt$ic) + 0.5 * SR_observed^2 *
            (mean(ic_dt$ic^2) - mean(ic_dt$ic)^2)) / (T_obs - 1)
SR_var <- max(SR_var, 1e-6)
DSR_z <- (SR_observed - SR_threshold_DSR) / sqrt(SR_var)
DSR_pval <- 1 - pnorm(DSR_z)
cat("[final-composite] SR_observed (monthly):", round(SR_observed, 4),
    "SR_threshold (DSR):", round(SR_threshold_DSR, 4), "\n")
cat("[final-composite] DSR-z:", round(DSR_z, 3), "DSR-p:", round(DSR_pval, 5),
    "DSR_pass (z>0):", DSR_z > 0, "\n")

# === Subperiod stability ===
ic_dt[, sp := cut(Date, breaks = c(as.Date("2003-12-31"), as.Date("2014-12-31"),
                                    as.Date("2019-12-31"), as.Date("2026-12-31")),
                  labels = c("p2008_2014", "p2015_2019", "p2020_2026"))]
sp_summary <- ic_dt[!is.na(sp), .(
  mean_ic = mean(ic), sd_ic = sd(ic), icir = mean(ic)/sd(ic)*sqrt(12),
  hit = mean(ic > 0), n = .N
), by = sp]
sp_pass <- mean(sp_summary$mean_ic > 0)
cat("\n[final-composite] Subperiod stability:\n")
print(sp_summary)
cat("[final-composite] Subperiod sign consistency:", round(sp_pass, 3), "(>=0.5 required)\n")

# === Regime-conditional final ===
regime_summary <- ic_dt[, .(mean_ic = mean(ic), sd_ic = sd(ic),
                             sr_proxy = mean(ic)/sd(ic)*sqrt(12),
                             ic_base_mean = mean(ic_base),
                             ic_base_sr = mean(ic_base)/sd(ic_base)*sqrt(12),
                             ic_r05_mean = mean(ic_r05),
                             ic_r05_sr = mean(ic_r05)/sd(ic_r05)*sqrt(12),
                             n = .N), by = regime]
cat("\n[final-composite] Regime breakdown (composite vs baseline vs R05 alone):\n")
print(regime_summary)

# === Cross-sectional cor vs STR_1715 (orthogonality) ===
cor_dt <- p[, .(rho = if (.N >= 5) cor(R05_Tail_Risk, score_eff, method="spearman") else NA_real_),
             by = Date]
cor_dt <- cor_dt[!is.na(rho)]
cat("\n[final-composite] R05 vs score_eff Spearman cor stats:\n")
cat("  mean rho:", round(mean(cor_dt$rho), 4), "  median:", round(median(cor_dt$rho), 4), "\n")
cat("  range:", round(range(cor_dt$rho), 4), "\n")
cat("  Hard constraint cor<0.30:", mean(cor_dt$rho) < 0.30, "(strict pass)\n")

# === Turnover proxy (top20 holding rotation) ===
# Per month: top 20 by z_blend; m-over-m overlap
p[, rank_blend := frank(-z_blend, ties.method="random"), by = Date]
top20 <- p[rank_blend <= 20, .(Date, Ticker, rank_blend)]
setorder(top20, Date, rank_blend)
top20_dates <- sort(unique(top20$Date))
overlap_dt <- rbindlist(lapply(seq_len(length(top20_dates) - 1), function(i) {
  d1 <- top20_dates[i]; d2 <- top20_dates[i+1]
  s1 <- top20[Date == d1, Ticker]
  s2 <- top20[Date == d2, Ticker]
  data.table(Date = d2, retained = length(intersect(s1, s2)), turnover = 20 - length(intersect(s1, s2)))
}))
mean_turnover <- mean(overlap_dt$turnover)
ann_turnover_one_way <- (mean_turnover / 20) * 12  # one-way annual rate
cat("\n[final-composite] Top20 turnover (monthly):", round(mean_turnover, 2),
    "/ 20  ann one-way rate:", round(ann_turnover_one_way, 2), "\n")

# === Cost estimate: 15bps × annual turnover ===
# Total cost = 2 * 0.0015 * one-way annual rate
cost_bps_annual <- 2 * 15 * ann_turnover_one_way
cat("[final-composite] Estimated annual cost (15bps × 2way × annual turnover):",
    round(cost_bps_annual, 1), "bps\n")
cat("[final-composite] Hard constraint cost<50bps/y:", cost_bps_annual < 50, "\n")

# === Anti-self-rationalization audit ===
cat("\n=== ANTI-SELF-RATIONALIZATION AUDIT ===\n")
red_flags <- c()
if (sp_summary[sp == "p2020_2026", icir] < 0.20) {
  red_flags <- c(red_flags, "RF-A3: recent 3Y ICIR < 0.20 (alpha decay suspicion)")
}
if (mean(cor_dt$rho) > 0.30) {
  red_flags <- c(red_flags, "RF-A: cor>0.30 vs STR_1715 (lack of orthogonality)")
}
if (nw_t < 3.0) {
  red_flags <- c(red_flags, "RF-A-stat: NW-t<3.0 (Harvey-Liu-Zhu fail base)")
}
if (regime_summary[regime == "CAUTION", sr_proxy] <= 0) {
  red_flags <- c(red_flags, "RF-AX001v2: CAUTION SR <= 0 strict (conditional defense fail)")
}
if (regime_summary[regime == "CRISIS", sr_proxy] <= 0) {
  red_flags <- c(red_flags, "RF-AX001v2: CRISIS SR <= 0 strict (conditional defense fail)")
}
if (length(red_flags) == 0) {
  cat("No red flags detected.\n")
} else {
  cat("Red flags:\n"); for (rf in red_flags) cat("  -", rf, "\n")
}

# === Save final artifacts ===
final <- list(
  scheme = SCHEME,
  T_ic = T_ic, ic_mean = ic_mean, ic_sd = ic_sd, icir = icir,
  plain_t = plain_t, nw_t = nw_t, nw_lag = nw_lag,
  hlz_bonf_threshold = hlz_threshold_bonf,
  hlz_pass_bonf = nw_t > hlz_threshold_bonf,
  DSR_z = DSR_z, DSR_pval = DSR_pval, DSR_pass = DSR_z > 0,
  subperiod = sp_summary, sp_pass_ratio = sp_pass,
  regime = regime_summary,
  cor_vs_str1715 = list(mean = mean(cor_dt$rho), median = median(cor_dt$rho),
                         pass_cor_30 = mean(cor_dt$rho) < 0.30),
  turnover = list(monthly = mean_turnover, ann_one_way = ann_turnover_one_way,
                   cost_bps = cost_bps_annual, pass_50bps = cost_bps_annual < 50),
  red_flags = red_flags
)
saveRDS(final, "stage_artifacts/WT_D20260512_003/final_validation.rds")
fwrite(ic_dt, "stage_artifacts/WT_D20260512_003/final_ic_monthly.csv")
fwrite(overlap_dt, "stage_artifacts/WT_D20260512_003/top20_turnover_monthly.csv")
cat("\n[final] artifacts saved.\n")

# === Print summary ===
cat("\n\n=========== SUMMARY ===========\n")
cat("Selected scheme:", paste(names(SCHEME), unlist(SCHEME), sep="=", collapse=", "), "\n")
cat("Overall ICIR:", round(icir, 3),
    "(baseline pure STR_1715:", round(mean(ic_dt$ic_base)/sd(ic_dt$ic_base)*sqrt(12), 3), ")\n")
cat("NW-t (composite):", round(nw_t, 3), "vs HLZ_threshold (N=20):", round(hlz_threshold_bonf, 3), "\n")
cat("DSR-z:", round(DSR_z, 3), "DSR pass:", DSR_z > 0, "\n")
cat("Subperiod consistency:", round(sp_pass, 3), "\n")
cat("Regime SR (composite): BULL", round(regime_summary[regime=="BULL", sr_proxy], 2),
    "/ NORMAL", round(regime_summary[regime=="NORMAL", sr_proxy], 2),
    "/ CAUTION", round(regime_summary[regime=="CAUTION", sr_proxy], 2),
    "/ CRISIS", round(regime_summary[regime=="CRISIS", sr_proxy], 2), "\n")
cat("Regime SR (baseline): BULL", round(regime_summary[regime=="BULL", ic_base_sr], 2),
    "/ NORMAL", round(regime_summary[regime=="NORMAL", ic_base_sr], 2),
    "/ CAUTION", round(regime_summary[regime=="CAUTION", ic_base_sr], 2),
    "/ CRISIS", round(regime_summary[regime=="CRISIS", ic_base_sr], 2), "\n")
cat("Cor vs STR_1715 (mean):", round(mean(cor_dt$rho), 4),
    " (strict<0.30:", mean(cor_dt$rho) < 0.30, ")\n")
cat("Annual turnover one-way:", round(ann_turnover_one_way, 2),
    " Cost bps:", round(cost_bps_annual, 1), " (<50:", cost_bps_annual < 50, ")\n")
cat("Red flags:", length(red_flags), "\n")
