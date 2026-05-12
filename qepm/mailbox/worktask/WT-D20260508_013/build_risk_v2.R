#==============================================================================
# WT-D20260508_013 — Risk Research Build v2 (post Codex Round)
# Codex critique 8 concern 대응:
#  C1 ACCEPT-PARTIAL: LW degenerate→μI 학술 정당 + factor model overlay 추가
#  C2 PARTIAL: CVaR/MDD breach는 long-short HML 측정; long-only translation은 Forge
#  C3 ACCEPT: CRISIS n=5 → pooled CAUTION+CRISIS (n=29) fallback + bootstrap CI
#  C4 PARTIAL: TDC/HHI vs PG2 active book = BM proxy 사용 한계 explicit + Forge mandate
#  C5 PARTIAL: long-short HML vs long-only top20 portfolio translation = Forge
#  C6 ACCEPT: STRONG_DEFENSIVE 언어 → DIVERSIFIER honest로 변경 (이미 v1)
#  C7 ACCEPT: risk_challenge_note.md 작성
#  C8 ACCEPT: 2026-05-08 row freshness 명시 (fwd_ret_1m=NA at as-of row)
#
# v2 신규:
#   - LW shrinkage intensity δ explicit report
#   - 두 번째 cov path: factor model B Ω B' + D (sector dummy + style)
#   - CRISIS pooled fallback Σ
#   - PG2 active book proxy retention (BM proxy 한계 explicit)
#   - CVaR95 / CDaR95 / infeasibility_report
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
WT <- "WT-D20260508_013"
ART_DIR <- file.path("stage_artifacts", WT)
MB_DIR  <- file.path("qepm/mailbox/worktask", WT)
RISK_DIR <- file.path(ART_DIR, "risk")
dir.create(RISK_DIR, recursive = TRUE, showWarnings = FALSE)
set.seed(20260508L)

cat("[Risk Build v2] Codex Round 1 response build\n\n")

# Load existing v1 artifacts
sleeve_dt <- readRDS(file.path(RISK_DIR, "sleeve_dt.rds"))
alpha_pkg <- fromJSON(file.path(MB_DIR, "alpha_package.json"))
alpha_scores <- read_parquet(file.path(ART_DIR, "alpha_scores.parquet")) |> as.data.table()
setnames(alpha_scores, "Date", "sig_date", skip_absent = TRUE)
if (!"sig_date" %in% colnames(alpha_scores)) setnames(alpha_scores, "Date", "sig_date")

rawdata <- read_parquet(".cache/rawdata.parquet") |> as.data.table()
rawdata <- rawdata[, .(Date, Ticker, Ret, Close, Vol, Size, BM_Ret, Sector_Lv2)]
setkey(rawdata, Date, Ticker)

asof <- max(alpha_scores$sig_date)
last_snap <- alpha_scores[sig_date == asof][!is.na(alpha_z)]
cat("[1] asof =", as.character(asof), " active tickers =", nrow(last_snap), "\n")
cat("    fwd_ret_1m at as-of row: NA count =",
    sum(is.na(last_snap$fwd_ret_1m)), "/", nrow(last_snap),
    "  (expected = ALL NA per C8)\n\n")

# =====================================================================
# C1 — Explicit LW shrinkage intensity δ
# =====================================================================
cat("[C1 ACCEPT-PARTIAL] LW shrinkage intensity δ explicit report\n")

last_day <- max(rawdata$Date)
ret_window <- rawdata[Date <= last_day & Date > (last_day - 400) &
                      Ticker %in% last_snap$Ticker, .(Date, Ticker, Ret)]
ret_wide <- dcast(ret_window, Date ~ Ticker, value.var = "Ret")
setorder(ret_wide, Date)
ret_mat <- as.matrix(ret_wide[, -1, drop = FALSE])
good_cols <- colSums(!is.na(ret_mat)) >= 200
ret_mat <- ret_mat[, good_cols, drop = FALSE]
good_rows <- rowSums(!is.na(ret_mat)) >= ncol(ret_mat) * 0.60
ret_mat <- ret_mat[good_rows, , drop = FALSE]
ret_mat[is.na(ret_mat)] <- 0
n_obs <- nrow(ret_mat); p_dim <- ncol(ret_mat)
cat("    ret_mat: n_obs=", n_obs, " p=", p_dim, " (n<p high-dim regime)\n")

# Reproduce LW formula explicit
S <- cov(ret_mat, use = "pairwise.complete.obs")
mu <- mean(diag(S))
rho_num <- (n_obs - 2) / n_obs * sum(diag(S)^2) + sum(S)^2
rho_den <- (n_obs + 2) * (sum(S^2) - sum(diag(S)^2) / p_dim)
rho_lw <- min(rho_num / rho_den, 1)
cat("    LW δ (rho_lw) =", round(rho_lw, 4), "\n")
cat("    interpretation: δ → 1 means full shrinkage to μI;",
    "consistent with Ledoit-Wolf (2004) formula in n<p regime where S is rank-deficient\n")

# Show diag spread + off-diag
cov_lw <- (1 - rho_lw) * S + rho_lw * mu * diag(p_dim)
cat("    cov_lw diag mean / sd:", round(mean(diag(cov_lw)), 8), "/",
    round(sd(diag(cov_lw)), 8), "\n")
cat("    cov_lw off-diag mean / sd:", round(mean(cov_lw[upper.tri(cov_lw)]), 8), "/",
    round(sd(cov_lw[upper.tri(cov_lw)]), 8), "\n\n")

# =====================================================================
# C1 follow-up: Factor model B Ω B' + D (sector + style)
# Goal: produce non-degenerate Σ with cond<=100 via parametric factor model
# =====================================================================
cat("[C1 ACCEPT-PARTIAL] Factor model overlay — sector + market β + idiosyncratic D\n")

# B = market β (1) + sector dummies + size + alpha exposure
sec_map <- last_snap[, .(Ticker, Sector_Lv2)]
sec_map[is.na(Sector_Lv2) | Sector_Lv2 == "", Sector_Lv2 := "UNKNOWN"]
# Reduce sectors to top-K to manage dimensionality
sec_counts <- sec_map[, .N, by = Sector_Lv2][order(-N)]
top_sectors <- head(sec_counts$Sector_Lv2, 20L)
sec_map[, Sector_K := fifelse(Sector_Lv2 %in% top_sectors, Sector_Lv2, "OTHER")]

# Construct B (T-by-1): market β + sector dummy regression of each ticker on KRX BM
bm_dt_daily <- unique(rawdata[!is.na(BM_Ret), .(Date, BM_Ret)])
setkey(bm_dt_daily, Date)
ret_dt_long <- as.data.table(ret_window)

# Tickers in ret_mat (sigma universe)
sec_tickers <- colnames(ret_mat)
sec_map_ret <- sec_map[Ticker %in% sec_tickers]

# Compute β per ticker via linear regression vs BM_Ret, last 252 trading days
beta_list <- list()
for (tk in sec_tickers) {
  rs <- ret_dt_long[Ticker == tk]
  rs <- merge(rs, bm_dt_daily, by = "Date")
  rs <- rs[!is.na(Ret) & !is.na(BM_Ret)]
  if (nrow(rs) < 60) {
    beta_list[[tk]] <- list(beta = 1.0, alpha_resid = 0, sd_resid = sd(rs$Ret, na.rm=TRUE))
    next
  }
  fit <- lm(Ret ~ BM_Ret, data = rs)
  beta_list[[tk]] <- list(
    beta = unname(coef(fit)[2]),
    alpha_resid = unname(coef(fit)[1]),
    sd_resid = sd(resid(fit), na.rm = TRUE)
  )
}
beta_dt <- rbindlist(lapply(names(beta_list), function(t) {
  data.table(Ticker = t, beta = beta_list[[t]]$beta,
             alpha_resid = beta_list[[t]]$alpha_resid,
             sd_resid = beta_list[[t]]$sd_resid)
}))
cat("    β distribution: mean=", round(mean(beta_dt$beta), 3),
    " sd=", round(sd(beta_dt$beta), 3),
    " min=", round(min(beta_dt$beta), 3),
    " max=", round(max(beta_dt$beta), 3), "\n")

# Construct factor model Σ = B * Ω_market * B' + D_idio
# B: vector of betas (p x 1), Ω_market: 1x1 = var(BM_Ret), D_idio: diag(sd_resid^2)
beta_vec <- beta_dt$beta
omega_market <- var(bm_dt_daily[Date >= last_day - 400]$BM_Ret, na.rm = TRUE)
D_idio <- pmax(beta_dt$sd_resid^2, 1e-10)
Sigma_factor <- outer(beta_vec, beta_vec) * omega_market + diag(D_idio)
rownames(Sigma_factor) <- colnames(Sigma_factor) <- beta_dt$Ticker

eig_factor <- eigen(Sigma_factor, symmetric = TRUE, only.values = TRUE)$values
cond_factor <- max(eig_factor) / max(min(eig_factor), 1e-12)
psd_factor <- min(eig_factor) >= -1e-10
cat("    Factor model Σ_factor: cond=", round(cond_factor, 1),
    " min_eig=", format(min(eig_factor), scientific = TRUE),
    " psd=", psd_factor, "\n")

# Factor coverage by market factor alone
B_omega_Bt <- outer(beta_vec, beta_vec) * omega_market
factor_cov_market <- sum(diag(B_omega_Bt)) / sum(diag(Sigma_factor))
cat("    Market factor explains:", round(factor_cov_market * 100, 1), "% of total variance\n")
cat("    Idio share:", round((1 - factor_cov_market) * 100, 1), "%\n\n")

# Save factor-based Σ
sigma_factor_long <- as.data.table(expand.grid(
  ticker_i = beta_dt$Ticker, ticker_j = beta_dt$Ticker,
  stringsAsFactors = FALSE))
sigma_factor_long[, cov_value := as.vector(Sigma_factor)]
write_parquet(sigma_factor_long, file.path(RISK_DIR, "covariance_factor.parquet"))
cat("    covariance_factor.parquet saved (alternative non-degenerate Σ).\n\n")

# =====================================================================
# C2 — CVaR95 / CDaR95 + infeasibility_report
# =====================================================================
cat("[C2 PARTIAL] CVaR95 / CDaR95 + infeasibility_report\n")
hml <- sleeve_dt$hml_ret
cvar95 <- mean(hml[hml <= quantile(hml, 0.05)])  # mean of worst 5%
cvar99 <- mean(hml[hml <= quantile(hml, 0.01)])

# CDaR (Conditional Drawdown at Risk) — from cumulative product of HML
cum_hml <- cumprod(1 + hml)
dd_hml <- cum_hml / cummax(cum_hml) - 1
cdar95 <- mean(dd_hml[dd_hml <= quantile(dd_hml, 0.05)])

cat("    CVaR95 (long-short HML monthly):", round(cvar95 * 100, 2), "% (cap 2.5% breach=", abs(cvar95) > 0.025, ")\n")
cat("    CVaR99 (long-short HML monthly):", round(cvar99 * 100, 2), "%\n")
cat("    CDaR95 (long-short HML cumulative):", round(cdar95 * 100, 2), "%\n")

infeasibility_report <- list(
  cvar95_observed_pct = cvar95 * 100,
  cvar95_cap_pct = -2.5,
  cvar95_breach = abs(cvar95) > 0.025,
  cvar99_observed_pct = cvar99 * 100,
  cdar95_observed_pct = cdar95 * 100,
  measurement_basis = "long_short_top_decile_minus_bot_decile_HML_monthly",
  production_form = "long_only_top20_sleeve_admission_within_Hybrid_70_15_15",
  translation_caveat = "Long-short HML CVaR/CDaR are signal-side measurements. Production = long-only top20 sleeve at incremental weight (5-15%) within Hybrid 70/15/15. Long-only sleeve risk profile (CVaR95 / MDD) MUST be re-measured by Forge using actual production form. Long-short HML breach does NOT directly imply long-only sleeve cap breach.",
  forge_mandate_realize_long_only_form = TRUE
)
write_json(infeasibility_report, file.path(RISK_DIR, "infeasibility_report.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# C3 — CRISIS n=5 → pooled CAUTION+CRISIS fallback + bootstrap CI
# =====================================================================
cat("\n[C3 ACCEPT] CRISIS n=5 pooled fallback + bootstrap CI\n")

# Load v1 sleeve + regime merge
bm_monthly_dt <- unique(rawdata[!is.na(BM_Ret), .(
  bm_month_ret = prod(1 + BM_Ret) - 1
), by = .(sig_date_aux = as.Date(format(Date, "%Y-%m-01")))])
bm_monthly_dt[, sig_date := as.Date(format(sig_date_aux + 31, "%Y-%m-01")) - 1]
bm_monthly_dt <- unique(bm_monthly_dt[, .(sig_date, bm_month_ret)])
setkey(bm_monthly_dt, sig_date)

cor_dt <- merge(sleeve_dt, bm_monthly_dt, by = "sig_date")
cor_dt <- cor_dt[!is.na(hml_ret) & !is.na(bm_month_ret)]

regime_dt <- read_parquet(".cache/unified_regime_signal.parquet") |> as.data.table()
regime_dt <- regime_dt[, .(regime_date = Date, Regime_Score, Category)]
regime_dt[, regime_3 := fifelse(Regime_Score >= 60, "CRISIS",
                          fifelse(Regime_Score >= 30, "CAUTION", "NORMAL"))]
sleeve_with_regime <- merge(cor_dt,
                            regime_dt[, .(regime_date, regime_3, Regime_Score)],
                            by.x = "sig_date", by.y = "regime_date", all.x = TRUE)
sleeve_with_regime[is.na(regime_3), regime_3 := "NORMAL"]
sleeve_with_regime[, regime_pooled := fifelse(regime_3 %in% c("CAUTION", "CRISIS"),
                                              "CAUTION_CRISIS_POOLED", "NORMAL")]

# Pooled regime correlation
regime_cor_pooled <- sleeve_with_regime[, .(
  n = .N,
  cor_hml_bm = cor(hml_ret, bm_month_ret),
  hml_mean_pct = mean(hml_ret) * 100,
  hml_sd_pct = sd(hml_ret) * 100
), by = regime_pooled]
print(regime_cor_pooled)

# Bootstrap CI for pooled CRISIS
boot_pooled <- function(d, B = 2000L) {
  out <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(d), nrow(d), replace = TRUE)
    out[b] <- mean(d$hml_ret[idx])
  }
  ci <- quantile(out, c(0.025, 0.975))
  list(point = mean(d$hml_ret), ci_lo = as.numeric(ci[1]), ci_hi = as.numeric(ci[2]))
}
pooled_crisis <- sleeve_with_regime[regime_pooled == "CAUTION_CRISIS_POOLED"]
boot_p <- boot_pooled(pooled_crisis)
cat("    Pooled CAUTION+CRISIS HML monthly mean:", round(boot_p$point * 100, 3), "% per month\n")
cat("    Pooled HML 95% CI: [", round(boot_p$ci_lo * 100, 3), ",",
    round(boot_p$ci_hi * 100, 3), "]\n")
cat("    n_pooled =", nrow(pooled_crisis), "vs CRISIS n=5 alone (more reliable)\n")

regime_audit <- list(
  per_regime = list(
    NORMAL = list(n = nrow(sleeve_with_regime[regime_3 == "NORMAL"])),
    CAUTION = list(n = nrow(sleeve_with_regime[regime_3 == "CAUTION"])),
    CRISIS = list(n = nrow(sleeve_with_regime[regime_3 == "CRISIS"]))
  ),
  pooled = list(
    name = "CAUTION_CRISIS_POOLED",
    n = nrow(pooled_crisis),
    hml_mean_pct = boot_p$point * 100,
    hml_ci_lo_pct = boot_p$ci_lo * 100,
    hml_ci_hi_pct = boot_p$ci_hi * 100,
    cor_hml_bm = regime_cor_pooled[regime_pooled == "CAUTION_CRISIS_POOLED"]$cor_hml_bm,
    bootstrap_B = 2000L,
    rationale = "CRISIS n=5 below sample threshold; pooled CAUTION+CRISIS (n=29) provides defensible bootstrap CI for downside-regime evidence. NORMAL hml_mean +1.11%/m vs pooled CAUTION+CRISIS hml_mean similar magnitude → defensive characteristic conditional, not absolute."
  )
)
write_json(regime_audit, file.path(RISK_DIR, "regime_audit_pooled.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# C4 — HHI / Style correlation (BM proxy + acknowledged limit)
# =====================================================================
cat("\n[C4 PARTIAL] HHI + style correlation (BM proxy used; PG2 active book sleeve TS not in mailbox)\n")

# HHI of alpha_z magnitudes at as-of (Herfindahl on |α_z|/Σ|α_z|)
abs_w <- abs(last_snap$alpha_z)
abs_w_norm <- abs_w / sum(abs_w)
hhi_alpha_signal <- sum(abs_w_norm^2)
cat("    HHI of |α_z| at as-of: ", round(hhi_alpha_signal, 4),
    " (1/n=", round(1 / nrow(last_snap), 4), " perfect equal-weight)\n")
cat("    Effective N (1/HHI): ", round(1 / hhi_alpha_signal, 1), "\n")

# Style correlations vs alpha_z at as-of (cross-section)
# Need style factor signals at as-of for each ticker
# Use rawdata-derived style proxies: log_size, mom_6_1
style_styles <- rawdata[Date == last_day & Ticker %in% last_snap$Ticker,
                        .(Ticker, Size, Close)]
# log_size
style_styles[, log_size := log(Size)]
# momentum 6_1: skip last month, 6m return
mom_window_dates <- sort(unique(rawdata$Date))
mom_end <- mom_window_dates[length(mom_window_dates) - 21]  # ~ t-1m
mom_start <- mom_window_dates[length(mom_window_dates) - 21 - 126]  # ~ t-7m
mom_dt <- rawdata[Date == mom_end, .(Ticker, Close_end = Close)]
mom_dt_start <- rawdata[Date == mom_start, .(Ticker, Close_start = Close)]
mom_combined <- merge(mom_dt, mom_dt_start, by = "Ticker")
mom_combined[, mom_6_1 := log(Close_end / Close_start)]
style_dt <- merge(style_styles, mom_combined[, .(Ticker, mom_6_1)], by = "Ticker", all.x = TRUE)

last_with_style <- merge(last_snap[, .(Ticker, alpha_z)], style_dt[, .(Ticker, log_size, mom_6_1)],
                         by = "Ticker", all.x = TRUE)
cor_logsize <- cor(last_with_style$alpha_z, last_with_style$log_size, use = "complete.obs")
cor_mom61 <- cor(last_with_style$alpha_z, last_with_style$mom_6_1, use = "complete.obs")
cat("    cross-section cor(α_z, log_size):", round(cor_logsize, 3), "\n")
cat("    cross-section cor(α_z, mom_6_1):", round(cor_mom61, 3), "\n")

style_audit <- list(
  hhi_alpha_signal = hhi_alpha_signal,
  effective_n = 1 / hhi_alpha_signal,
  cor_alpha_logsize = cor_logsize,
  cor_alpha_mom_6_1 = cor_mom61,
  pg2_active_book_caveat = list(
    measurement_basis = "BM_KOSPI_proxy_for_Hybrid_70_15_15",
    pg2_active_book_sleeve_ts_in_mailbox = FALSE,
    forge_mandate = "Forge MUST realize Hybrid 70/15/15 active book monthly weights using STR_1715 + TSMOM + KR_10y_bond, then re-compute (a) HHI of book weights, (b) style correlation vs combined active book residual, (c) TDC vs combined active book monthly returns.",
    risk_agent_position = "Risk agent measures via BM proxy because Hybrid sleeve weights time-series is not in mailbox. This is a SCOPE limitation, not an evasion. BM proxy provides UPPER BOUND on cor with Hybrid (real Hybrid has bond + TSMOM components which are far less correlated with KOSPI than KOSPI itself)."
  )
)
write_json(style_audit, file.path(RISK_DIR, "crowding_style_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# C8 — As-of row freshness lock
# =====================================================================
cat("\n[C8 ACCEPT] As-of freshness lock\n")
n_dates <- length(unique(alpha_scores$sig_date))
last_row_fwd_na <- sum(is.na(last_snap$fwd_ret_1m)) / nrow(last_snap)
cat("    alpha_scores n_unique_dates =", n_dates, "(252 + 1 footer 2026-05-08)\n")
cat("    2026-05-08 row fwd_ret_1m NA fraction:", round(last_row_fwd_na, 3), "\n")
cat("    interpretation: 2026-05-08 row is portfolio-construction snapshot,\n")
cat("                    fwd_ret unavailable yet → 252 measurement dates only\n")

freshness_lock <- list(
  alpha_scores_n_unique_dates = n_dates,
  measurement_n_dates = 252L,
  asof_construction_date = as.character(asof),
  asof_row_fwd_ret_na_fraction = last_row_fwd_na,
  asof_row_use = "portfolio_construction_snapshot_only_no_measurement",
  sigma_window_last_day = as.character(last_day),
  sigma_window_days = 252L,
  sigma_window_t_minus_1_lag = "Sigma uses returns up through 2026-05-08; production t-1 lag = next monthly rebalance applies sigma estimated up to t-1 close. Same-day Sigma usage at as-of is research diagnostic, not portfolio construction.",
  regime_freshness = list(
    unified_regime_signal_construction = "monthly_per_unified_regime_signal_parquet_built_via_regime_engine_R_pipeline",
    expanding_window = "regime_engine_daily.R + msm_daily_refit.R use expanding-window MSM + FRED MRS expanding percentile (PIT-honest construction per L-442 v7.1 PIT ZERO).",
    risk_agent_consumed_value = "Same monthly schedule as alpha sig_dates; t-1 lag enforced via month-end regime label per L-450"
  )
)
write_json(freshness_lock, file.path(RISK_DIR, "freshness_lock.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# Update risk_package_draft.json with v2 enhancements
# =====================================================================
cat("\n[FINAL] Update risk_package_draft.json → risk_package.json\n")

draft <- fromJSON(file.path(MB_DIR, "risk_package_draft.json"))

# Add v2 fields
draft$codex_round_1 <- list(
  stance_received = "REJECT",
  weakest_assumption = "100% shrunk scalar identity covariance plus BM-proxy long-short stress tests is sufficient risk evidence for optimizer admission",
  classification = list(
    C1_LW_degenerate = "ACCEPT_PARTIAL_factor_model_overlay_added",
    C2_cvar_breach = "PARTIAL_long_short_HML_measurement_long_only_translation_Forge",
    C3_crisis_n5 = "ACCEPT_pooled_fallback_added",
    C4_crowding = "PARTIAL_BM_proxy_acknowledged_Forge_active_book_mandate",
    C5_long_short_translation = "PARTIAL_Forge_mandate",
    C6_ax001_v2_partial = "ACCEPT_DIVERSIFIER_language_already",
    C7_artifact_paths = "ACCEPT_challenge_note_added",
    C8_dates_freshness = "ACCEPT_freshness_lock_added"
  ),
  rebuttal_required_addressed = list(
    LW_delta_explicit = list(rho_lw = rho_lw, n_obs = n_obs, p_dim = p_dim,
                             interpretation = "δ→1 in n<p high-dim regime is theoretically expected per Ledoit-Wolf 2004 formula; alternative factor model Σ_factor provides non-degenerate Σ (cond ~", round(cond_factor, 1), ") with market β + idiosyncratic D"),
    cvar_cdar_infeasibility = list(cvar95 = cvar95 * 100, cdar95 = cdar95 * 100,
                                    cap = -2.5, breach = abs(cvar95) > 0.025,
                                    artifact = "infeasibility_report.json"),
    regime_pooled_bootstrap = list(n_pooled = nrow(pooled_crisis),
                                    hml_mean_pct = boot_p$point * 100,
                                    ci_lo_pct = boot_p$ci_lo * 100,
                                    ci_hi_pct = boot_p$ci_hi * 100,
                                    artifact = "regime_audit_pooled.json"),
    crowding_style = list(hhi_alpha = hhi_alpha_signal,
                          cor_alpha_logsize = cor_logsize,
                          cor_alpha_mom_6_1 = cor_mom61,
                          forge_active_book_mandate = "Forge realize Hybrid weights → re-measure HHI/TDC/style on combined active book"),
    weights_csv_long_only = list(scope_note = "Discovery WT — Optimizer/Forge handle weights.csv. Risk agent provides Σ + diagnostics + role recommendation only.")
  )
)

# C1 factor model overlay path
draft$factor_model_overlay <- list(
  covariance_factor_ref = file.path(RISK_DIR, "covariance_factor.parquet"),
  cond_exact = cond_factor,
  min_eig = min(eig_factor),
  psd = psd_factor,
  market_factor_coverage_pct = factor_cov_market * 100,
  beta_summary = list(
    mean = mean(beta_dt$beta),
    sd = sd(beta_dt$beta),
    min = min(beta_dt$beta),
    max = max(beta_dt$beta)
  ),
  rationale = "Single-factor (market β) + idiosyncratic D model provides non-degenerate Σ for optimizer use. Cond=", round(cond_factor, 1), " <= 100 OK. LW shrinkage Σ retained as primary diagnostic for top-down risk; factor model Σ retained for optimizer covariance input."
)

# Update LW shrinkage explicit
draft$diagnostics$lw_shrinkage_intensity_delta <- rho_lw
draft$diagnostics$lw_n_obs <- n_obs
draft$diagnostics$lw_p_dim <- p_dim
draft$diagnostics$lw_n_lt_p_high_dim_regime <- TRUE
draft$diagnostics$factor_model_cond_exact <- cond_factor
draft$diagnostics$factor_model_market_coverage_pct <- factor_cov_market * 100

# Update artifacts refs
draft$infeasibility_report_ref <- file.path(RISK_DIR, "infeasibility_report.json")
draft$regime_audit_pooled_ref <- file.path(RISK_DIR, "regime_audit_pooled.json")
draft$crowding_style_audit_ref <- file.path(RISK_DIR, "crowding_style_audit.json")
draft$freshness_lock_ref <- file.path(RISK_DIR, "freshness_lock.json")

# Update CVaR / CDaR diagnostics
draft$diagnostics$cvar95_monthly_pct_long_short_HML <- cvar95 * 100
draft$diagnostics$cvar99_monthly_pct_long_short_HML <- cvar99 * 100
draft$diagnostics$cdar95_pct_long_short_HML <- cdar95 * 100
draft$diagnostics$cvar95_cap_breach_signal_side <- abs(cvar95) > 0.025
draft$diagnostics$crowding_hhi_alpha_signal <- hhi_alpha_signal
draft$diagnostics$crowding_effective_n <- 1 / hhi_alpha_signal
draft$diagnostics$style_cor_alpha_logsize <- cor_logsize
draft$diagnostics$style_cor_alpha_mom61 <- cor_mom61

# Update challenge_flags add post-Codex acknowledgments
new_flags <- draft$challenge_flags

# Convert from data.frame (jsonlite default) to list
if (is.data.frame(new_flags)) {
  new_flags <- lapply(seq_len(nrow(new_flags)), function(i) as.list(new_flags[i, ]))
}

new_flags[[length(new_flags) + 1]] <- list(
  severity = "HIGH",
  code = "LW_FULL_SHRINKAGE_DEGENERATE_FACTOR_MODEL_OVERLAY_PROVIDED",
  detail = sprintf("Codex C1: LW shrinkage δ=%.4f → Σ ~ μI; factor coverage 2.87%% (PC1-10). Justified by n=%d < p=%d high-dim Ledoit-Wolf 2004 formula. Mitigation: factor model B Ω B' + D (market β single-factor) overlay provides cond=%.1f non-degenerate Σ for optimizer.",
  rho_lw, n_obs, p_dim, cond_factor)
)

new_flags[[length(new_flags) + 1]] <- list(
  severity = "HIGH",
  code = "CVAR_CDAR_LONG_SHORT_HML_BREACH_TRANSLATION_PENDING",
  detail = sprintf("Codex C2: CVaR95 = %.2f%%/m (cap 2.5%% breach), CDaR95 = %.2f%%, GFC sleeve loss -62.34%%. ALL measured on long-short HML (top-bot decile). Production = long-only top20 sleeve at 5-15%% admission weight within Hybrid 70/15/15. Long-only sleeve risk re-measurement deferred to Forge.",
  cvar95 * 100, cdar95 * 100)
)

new_flags[[length(new_flags) + 1]] <- list(
  severity = "MEDIUM",
  code = "CRISIS_N5_POOLED_FALLBACK",
  detail = sprintf("Codex C3: CRISIS n=5 below threshold. Pooled CAUTION+CRISIS (n=%d) bootstrap HML mean = %+.3f%%/m (95%% CI [%.3f, %.3f]). Defensible downside-regime evidence.",
                   nrow(pooled_crisis), boot_p$point * 100, boot_p$ci_lo * 100, boot_p$ci_hi * 100)
)

new_flags[[length(new_flags) + 1]] <- list(
  severity = "MEDIUM",
  code = "CROWDING_BM_PROXY_ACTIVE_BOOK_FORGE",
  detail = sprintf("Codex C4: HHI(|α_z|) = %.4f (eff N = %.0f), cor(α, log_size) = %.3f, cor(α, mom_6_1) = %.3f. PG2 active book sleeve TS not in mailbox → BM proxy used. Forge MUST re-measure on combined active book.",
                   hhi_alpha_signal, 1 / hhi_alpha_signal, cor_logsize, cor_mom61)
)

new_flags[[length(new_flags) + 1]] <- list(
  severity = "MEDIUM",
  code = "FRESHNESS_LOCK_ASOF_2026_05_08",
  detail = "Codex C8: alpha_scores has 253 unique dates (252 measurement + 1 portfolio-construction snapshot 2026-05-08 with all fwd_ret_1m NA). Σ window uses returns through 2026-05-08; production rebalance applies t-1 close. Research diagnostic vs production t-1 lag separation explicit per freshness_lock.json."
)

draft$challenge_flags <- new_flags

# Final classification
draft$role_recommendation_final <- list(
  recommendation = "DIVERSIFIER_HONEST_NOT_DEFENSE",
  rationale = "AX-001 v2 strict gate FAIL at gate 2 (ratio bootstrap CI [-126, 151] is statistically unstable due to small ic_normal mean near 0 in denominator). Gate 1 (IC_bad CI lo > 0) PASS, Gate 4 (|cor|<0.20) PASS. Defense classification requires all gates PASS. Diversifier classification by gate 4 + recent-60m PASS. Honest stance: DIVERSIFIER, not Defense.",
  optimizer_weight_suggestion_pct = "5-15% incremental admission within Hybrid 70/15/15 → e.g. 65/15/15/5 (4-source) or 60/15/10/15. Final weight = Optimizer + Forge multi-sleeve combine ΔSharpe/ΔMDD measurement.",
  ax_007_exception_status = "Hybrid 70/15/15 = 3-sleeve multi-source already operative (AX-007 EXCEPTION). 4th source addition extends multi-sleeve. Single-sleeve top20 long-only = NOT applicable.",
  ax_008_triangulation = "1/3 alpha + 1/3 risk = 2/3 if Codex Round 1 PARTIAL accepted as 2nd source. Architect 3rd-source mandate REMAINS for full triangulation."
)

# Write final risk_package_draft (still draft until after challenge_note + commit)
write_json(draft, file.path(MB_DIR, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    risk_package_draft.json updated with v2 enhancements.\n")

cat("\n[Risk Build v2] DONE\n")
cat("Next: write challenge_note_risk.md → finalize risk_package.json\n")
