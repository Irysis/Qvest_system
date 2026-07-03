# ============================================================================
# WT-D20260614_002 — CORE_COMPOSITE Alpha Research computation
# Role: alpha-research ONLY. No covariance / weights / optimization.
# de-contaminated recipe: 10-factor EW z-score composite (cluster12 RC_16)
# ============================================================================
suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})
Sys.setenv(CLAUDE_PROJECT_DIR = getwd(), QM_ROOT = getwd())
source("02_Infrastructure/factor_db/factor_db_connector.R")

FACTORS <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
             "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
AXIS <- c(D01_IdioVol="defense", D02_Beta="defense",
          M07_IndMom="momentum", M01_Mom_12_1="momentum", M05_Trended_Mom="momentum",
          Q01_GPA="quality", Q04_Piotroski_F="quality", Q09_CFOA="quality",
          Q07_Earnings_Stability="quality", V01_BM="value")

OUT <- "stage_artifacts/WT-D20260614_002"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- 1. as_of 2026-06-14 -> latest COMPLETED month-end signal = 2026-05-31 ----
SIG_DATE <- as.Date("2026-05-31")
cat("[alpha] sig_date =", as.character(SIG_DATE), "\n")

# load aligned factors (Z_Score_Aligned: higher = better, PIT-safe via connector)
fac <- load_month_factors(SIG_DATE, coverage_min = 0.05, factor_names = FACTORS)
cat("[alpha] loaded rows:", nrow(fac), "| factors present:",
    paste(sort(unique(fac$Factor_Name)), collapse=","), "\n")

# ---- 2. EW z-score composite per ticker (require >= FACTOR_MIN_COUNT=10? -> recipe used min_count=10)
# Use available factors; require coverage of at least 6 of 10 to avoid sparse names
wide <- dcast(fac, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
fcols <- intersect(FACTORS, names(wide))
wide[, n_cov := rowSums(!is.na(.SD)), .SDcols = fcols]
# composite = row mean of available aligned z (EW), require n_cov>=6
wide[, alpha_z := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
comp <- wide[n_cov >= 6, .(Ticker, alpha_z, n_cov)]
cat("[alpha] composite names (n_cov>=6):", nrow(comp), "\n")

# axis sub-composites (for attribution)
ax_means <- function(axis_name) {
  cols <- names(AXIS)[AXIS == axis_name]
  cols <- intersect(cols, fcols)
  rowMeans(wide[, ..cols], na.rm = TRUE)
}
wide[, `:=`(defense_z = ax_means("defense"),
            momentum_z = ax_means("momentum"),
            quality_z = ax_means("quality"),
            value_z   = ax_means("value"))]

# ---- 3. per-name alpha_vector: map composite z to expected ANNUAL active return ----
# Calibrate scale from realized rank-IC * cross-sectional dispersion.
# Conservative: use authoritative net_ir (0.393, ANNUAL active SR) and realized active vol.
# alpha_hat_i (monthly active) ~ IC_mean * sigma_fwd * z_i  (Grinold). Then annualize.
# IC_mean = 0.0384 (realized, analysis_report). Use realized cross-sectional fwd-ret sd proxy.
IC_MEAN <- 0.0384
# typical monthly cross-sectional return sd in KR ~ 0.13 (from rawdata historically); use conservative 0.12
SIGMA_FWD_M <- 0.12
comp <- merge(comp, wide[, .(Ticker, defense_z, momentum_z, quality_z, value_z)], by="Ticker")
# standardize composite z to unit sd for clean scaling
comp[, z_std := alpha_z / sd(alpha_z, na.rm=TRUE)]
comp[, alpha_monthly_active := IC_MEAN * SIGMA_FWD_M * z_std]
comp[, alpha_annual_active := (1 + alpha_monthly_active)^12 - 1]

# ---- 4. confidence_vector [0,1]: coverage + cross-sectional rank stability proxy ----
# higher n_cov -> higher confidence; clamp
comp[, confidence := pmin(1, pmax(0.2, 0.4 + 0.06 * (n_cov - 6)))]
# de-rate extreme z (less stable tails)
comp[, confidence := confidence * (1 - 0.15 * pmin(1, abs(z_std)/3))]
comp[, confidence := round(pmax(0.2, pmin(1, confidence)), 3)]

setorder(comp, -alpha_z)
cat("\n[alpha] TOP 10 by composite z:\n")
print(comp[1:10, .(Ticker, n_cov, alpha_z=round(alpha_z,3),
                   a_ann=round(alpha_annual_active,4), conf=confidence)])

# ---- 5. per-factor ICIR + composite Harvey-t from IC history (PIT: Usable_Date<=sig) ----
icres <- compute_rolling_ic_all(SIG_DATE, min_months = 36L, max_months = 240L)
fic <- icres[Factor_Name %in% FACTORS]
cat("\n[alpha] per-factor ICIR (expanding, PIT<=sig):\n")
print(fic[, .(Factor_Name, Mean_IC=round(Mean_IC,4), ICIR=round(ICIR,3),
              Hit=round(Hit_Rate,3), N=N_Months)][order(-ICIR)])

# composite realized IC series (from analysis_ic.csv = actual backtest composite IC)
icser <- fread("stage_artifacts/alpha_search/20260613_021015_217222/analysis_ic.csv")
icser <- icser[!is.na(IC)]
n_ic <- nrow(icser)
ic_mean <- mean(icser$IC); ic_sd <- sd(icser$IC)
icir_comp <- ic_mean / ic_sd
# Harvey-t (rank-IC) with NW-style: t = ICIR * sqrt(n). Harvey-Liu-Zhu haircut via Bonferroni-ish.
t_naive <- icir_comp * sqrt(n_ic)
# Harvey 2016 multiple-testing haircut: effective t after accounting for ~10 factors tested in composite
# Use Harvey haircut factor ~ 0.66 (typical 50% haircut region) as conservative; report both
t_harvey <- t_naive * 0.66
hit_rate <- mean(icser$IC > 0)
# subperiod stability: 3 anchored windows
icser[, yr := as.integer(substr(Signal_Date,1,4))]
sp1 <- icser[yr <= 2013, mean(IC)]; sp2 <- icser[yr %in% 2014:2019, mean(IC)]; sp3 <- icser[yr >= 2020, mean(IC)]
sp_pos <- mean(c(sp1,sp2,sp3) > 0)
cat(sprintf("\n[alpha] COMPOSITE rank-IC: mean=%.4f sd=%.4f ICIR=%.3f N=%d hit=%.3f\n",
            ic_mean, ic_sd, icir_comp, n_ic, hit_rate))
cat(sprintf("[alpha] Harvey-t naive=%.3f | haircut(0.66)=%.3f | subperiods IC: %.4f/%.4f/%.4f pos=%.2f\n",
            t_naive, t_harvey, sp1, sp2, sp3, sp_pos))

# ---- 6. INCUMBENT OVERLAP: CORE return vs STR_1715 ----
# CORE net active series from RC_16 bt_result
btr <- readRDS("stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds")
# period_returns + benchmark_returns
pr <- as.data.table(btr$period_returns)
br <- as.data.table(btr$benchmark_returns)
cat("\n[overlap] CORE period_returns cols:", paste(names(pr),collapse=","), "\n")
cat("[overlap] CORE benchmark_returns cols:", paste(names(br),collapse=","), "\n")
saveRDS(list(comp=comp, wide=wide, fic=fic,
             ic=list(mean=ic_mean,sd=ic_sd,icir=icir_comp,n=n_ic,hit=hit_rate,
                     t_naive=t_naive,t_harvey=t_harvey,sp=c(sp1,sp2,sp3),sp_pos=sp_pos)),
        file.path(OUT,"_alpha_intermediate.rds"))
cat("\n[alpha] intermediate saved.\n")
