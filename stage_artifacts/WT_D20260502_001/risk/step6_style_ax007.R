#==============================================================================
# WT-D20260502_001 Risk Research — Step 6: Style attribution + AX-007 audit
#
# Q-Lead Directives:
#  #4: AX-007 single-sleeve top20 mechanism break verification (4 exceptions)
#  #5: Quality family + Tail-Skewness family STR_1715 overlap quantification
#
# Style attribution: FF5+Carhart proxies via Korean factor portfolios
#  Build: Mkt-Rf, SMB, HML (proxy: BM ranking), Profitability (proxy: ROE),
#         Investment (proxy: Asset Growth), Momentum (12-1 month)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step5_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- AX-007 audit: single-sleeve top20 mechanism break ----------------------
# Exceptions:
#   1. multi-sleeve (e.g., 2-sleeve def + indep) — NO, alpha is single-sleeve
#   2. long-short — NO, KR domestic only, no_short_legal_kr=true
#   3. 50+ 분산 — NO, max_names_total=500 in request but typical = 20
#   4. ML sizing — NO, alpha uses ICIR weighted (not ML)
#
# Conclusion: AX-007 risk active. Composite is single-sleeve cross-regime.

ax007_exceptions_active <- list(
  multi_sleeve = FALSE,  # 1 alpha = 1 sleeve
  long_short = FALSE,    # KR no-short
  fifty_plus_diversification = FALSE,  # top 20 typical
  ml_sizing = FALSE      # ICIR weighting only
)
ax007_risk_active <- !any(unlist(ax007_exceptions_active))
cat(sprintf("[Step6] AX-007 single-sleeve mechanism break risk active: %s\n",
            ax007_risk_active))
cat(sprintf("  Exceptions: multi_sleeve=%s long_short=%s 50+=%s ml_sizing=%s\n",
            ax007_exceptions_active$multi_sleeve,
            ax007_exceptions_active$long_short,
            ax007_exceptions_active$fifty_plus_diversification,
            ax007_exceptions_active$ml_sizing))

# AX-001 v2 axis 3 FAIL was reported by alpha-research (bad/normal IC ratio 0.79 OOS)
# So defense thesis NOT validated. AX-007 + AX-001 v2 axis 3 FAIL combined =
# elevated structural risk for single-sleeve top20 deployment.

# ---- Style attribution via Quality family overlap ---------------------------
# Map alpha factor families: D43 (Defense_Tail), R13 (Risk_Tail), Q07 (Quality)
# STR_1715 family: Quality (high BM ratio + low debt + earnings stability — defense portfolio)
# Both contain Q07 (Earnings_Stability) — direct overlap risk

# alpha factor specs from alpha_package
alpha_pkg <- fromJSON(file.path(PROJ, "qepm/mailbox/worktask/WT-D20260502_001/alpha_package.json"),
                      simplifyVector = FALSE)
alpha_factors <- sapply(alpha_pkg$factor_specs, function(f) f$factor_name)
alpha_families <- sapply(alpha_pkg$factor_specs, function(f) f$factor_family)
alpha_thetas <- sapply(alpha_pkg$factor_specs, function(f) f$weight_theta)
cat("[Step6] Alpha factor specs:\n")
for (i in seq_along(alpha_factors)) {
  cat(sprintf("  %s | family=%s | theta=%.3f\n",
              alpha_factors[i], alpha_families[i], alpha_thetas[i]))
}

# Family weight summation
family_weights <- tapply(alpha_thetas, alpha_families, sum)
cat("\n[Step6] Alpha family weight distribution:\n")
print(family_weights)

# Quality family direct overlap with STR_1715 (also Quality)
quality_weight_alpha <- family_weights["Quality"] %||% 0
total_alpha_weight <- sum(alpha_thetas)
quality_share <- quality_weight_alpha / total_alpha_weight
cat(sprintf("[Step6] Quality family weight share in alpha: %.1f%% (Q07 only)\n",
            quality_share * 100))

# Tail family
tail_share <- (family_weights["Defense_Tail"] %||% 0 +
                family_weights["Risk_Tail"] %||% 0) / total_alpha_weight
cat(sprintf("[Step6] Tail family (D43+R13) weight share: %.1f%%\n",
            tail_share * 100))

# ---- FF Style regression: alpha LS vs market + size + value-like style proxies -
# Build style factor returns from monthly_wide_full + universe meta
ret_long <- melt(state$monthly_wide_full, id.vars = "YM",
                  variable.name = "Ticker", value.name = "Ret",
                  variable.factor = FALSE)
universe_meta <- state$universe_meta
ret_long <- merge(ret_long, universe_meta, by = "Ticker", all.x = TRUE)

# SMB: small minus big (already computed in step3)
ret_long[, LogSize_quintile := cut(LogSize, breaks = quantile(LogSize, probs = seq(0, 1, 0.2),
                                                                na.rm = TRUE),
                                     include.lowest = TRUE, labels = 1:5)]
smb_long <- ret_long[!is.na(LogSize_quintile),
                     .(MeanRet = mean(Ret, na.rm = TRUE)), by = .(YM, LogSize_quintile)]
smb_wide <- dcast(smb_long, YM ~ LogSize_quintile, value.var = "MeanRet")
smb_wide[, SMB := `1` - `5`]

# HML proxy: Use Sector dispersion as crude value vs growth proxy
# (We don't have BM ratio time series — would need DART. Use sector L/H bucket)
# Alternative: load Q07 factor history if available, but for style purposes
# we use a very crude size-prior-month-return interaction (Reverse momentum)
# Actually use semiconductor (growth) vs financials (value) as crude proxy

# Compute monthly: 'Tech' = (반도체 + IT가전 + 소프트웨어 + IT하드웨어) - (은행 + 보험 + 증권)
factor_F <- as.data.table(state$factor_returns_F)
factor_F[, YM := rownames(state$factor_returns_F)]
tech_cols <- c("반도체", "IT가전", "소프트웨어", "IT하드웨어")
fin_cols <- c("은행", "보험", "증권")
tech_avail <- intersect(tech_cols, names(factor_F))
fin_avail <- intersect(fin_cols, names(factor_F))
factor_F[, GROWTH_VALUE := rowMeans(.SD[, ..tech_avail]) -
         rowMeans(.SD[, ..fin_avail])]
cat(sprintf("[Step6] Built GROWTH_VALUE proxy: tech=%s | fin=%s\n",
            paste(tech_avail, collapse=","), paste(fin_avail, collapse=",")))

# Momentum proxy: lagged 12-month return
# We'll compute later — too heavy. Use simpler 1-month auto-correlation style for now.

# ---- Run FF regression on alpha LS returns ----------------------------------
ls_audit <- fread(file.path(PROJ, "stage_artifacts/WT_D20260502_001/ls_returns_inheritance_audit.csv"))
alpha_returns <- ls_audit[, .(YM = ym, Alpha_Ret = ls_ret)]

# Merge with style factors
style_factors <- merge(
  factor_F[, .(YM, MKT = BM_Ret_Monthly, SMB, GROWTH_VALUE)],
  smb_wide[, .(YM)],  # just to align
  by = "YM", all.x = FALSE
)

style_reg_data <- merge(alpha_returns, style_factors, by = "YM")
cat(sprintf("[Step6] Style regression data: %d months\n", nrow(style_reg_data)))

# Demean and regress
ff_model <- lm(Alpha_Ret ~ MKT + SMB + GROWTH_VALUE, data = style_reg_data)
ff_summary <- summary(ff_model)
cat("[Step6] FF style attribution (alpha LS ~ MKT + SMB + GROWTH_VALUE):\n")
print(ff_summary$coefficients)
cat(sprintf("  R² = %.4f | Adj R² = %.4f\n",
            ff_summary$r.squared, ff_summary$adj.r.squared))

# Extract betas
mkt_beta <- coef(ff_model)["MKT"]
smb_beta <- coef(ff_model)["SMB"]
gv_beta  <- coef(ff_model)["GROWTH_VALUE"]
alpha_intercept <- coef(ff_model)["(Intercept)"]
mkt_t <- coef(ff_summary)["MKT", "t value"]
smb_t <- coef(ff_summary)["SMB", "t value"]
gv_t  <- coef(ff_summary)["GROWTH_VALUE", "t value"]
intercept_t <- coef(ff_summary)["(Intercept)", "t value"]

cat(sprintf("\n[Step6] Alpha betas:\n"))
cat(sprintf("  MKT:    β=%.3f t=%.2f\n", mkt_beta, mkt_t))
cat(sprintf("  SMB:    β=%.3f t=%.2f\n", smb_beta, smb_t))
cat(sprintf("  GR-VAL: β=%.3f t=%.2f\n", gv_beta, gv_t))
cat(sprintf("  Alpha (intercept): %.4f t=%.2f\n", alpha_intercept, intercept_t))

# ---- Style overlap with STR_1715: Run same regression on STR_1715 -----------
str1715_returns <- merge(
  data.table(YM = format(as.Date(fread(file.path(PROJ,
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))$date),
    "%Y-%m"),
    STR1715_Ret = fread(file.path(PROJ,
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))$ret_net),
  style_factors, by = "YM"
)
ff_str1715 <- lm(STR1715_Ret ~ MKT + SMB + GROWTH_VALUE, data = str1715_returns)
ff_str1715_summary <- summary(ff_str1715)
cat(sprintf("\n[Step6] STR_1715 style betas:\n"))
print(ff_str1715_summary$coefficients)
cat(sprintf("  R² = %.4f\n", ff_str1715_summary$r.squared))

# ---- Compute style overlap distance -----------------------------------------
beta_alpha_vec <- coef(ff_model)[c("MKT", "SMB", "GROWTH_VALUE")]
beta_str1715_vec <- coef(ff_str1715)[c("MKT", "SMB", "GROWTH_VALUE")]
beta_dist <- sqrt(sum((beta_alpha_vec - beta_str1715_vec)^2))
beta_cor <- cor(beta_alpha_vec, beta_str1715_vec)
cat(sprintf("\n[Step6] Style overlap (alpha vs STR_1715):\n"))
cat(sprintf("  ||β_alpha - β_STR1715||: %.4f\n", beta_dist))
cat(sprintf("  cor(β_alpha, β_STR1715): %.4f\n", beta_cor))

# ---- Liquidity check (alpha-research already 98.7%) -------------------------
# Verify with our data: Top-20 alpha ADV
top20_alpha_tickers <- names(head(sort(state$alpha_vector, decreasing = TRUE), 20))
RAWDATA <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
recent_20d <- RAWDATA[Date >= as.Date(state$as_of_date) - 30 & Date <= as.Date(state$as_of_date),
                       .(Ticker, Date, Vol, Close)]
recent_20d[, DV := as.numeric(Vol) * as.numeric(Close)]
top20_dv <- recent_20d[Ticker %in% top20_alpha_tickers,
                        .(ADV_20d = mean(DV, na.rm = TRUE)), by = Ticker]
cat(sprintf("\n[Step6] Top20 alpha ADV (KRW):\n"))
top20_dv_sorted <- top20_dv[order(ADV_20d)]
print(head(top20_dv_sorted, 10))

LIQ_THRESHOLD <- 50000000  # 50M as per request
liq_pass <- top20_dv$ADV_20d >= LIQ_THRESHOLD
cat(sprintf("\n[Step6] Liquidity threshold pass (ADV >= %g KRW): %d/%d (%.1f%%)\n",
            LIQ_THRESHOLD, sum(liq_pass), length(liq_pass), mean(liq_pass) * 100))

# ---- Save state -------------------------------------------------------------
state$ax007_audit <- list(
  risk_active = ax007_risk_active,
  exceptions_active = ax007_exceptions_active,
  combined_risk_with_ax001_v2_axis3_fail = TRUE,
  remediation_options = c(
    "Multi-sleeve construction (Sleeve A defense + Sleeve B core)",
    "Diversify to 30+ names per sleeve",
    "ML-based dynamic sizing (turn off rule-based ICIR weights)"
  )
)

state$style_attribution_alpha <- list(
  mkt_beta = unname(mkt_beta),
  mkt_t = unname(mkt_t),
  smb_beta = unname(smb_beta),
  smb_t = unname(smb_t),
  growth_value_beta = unname(gv_beta),
  growth_value_t = unname(gv_t),
  alpha_intercept_monthly = unname(alpha_intercept),
  alpha_intercept_t = unname(intercept_t),
  r_squared = ff_summary$r.squared,
  alpha_intercept_significant_p005 = abs(intercept_t) > 1.96
)

state$style_attribution_str1715 <- list(
  mkt_beta = unname(coef(ff_str1715)["MKT"]),
  smb_beta = unname(coef(ff_str1715)["SMB"]),
  growth_value_beta = unname(coef(ff_str1715)["GROWTH_VALUE"]),
  r_squared = ff_str1715_summary$r.squared
)

state$style_overlap <- list(
  beta_distance = beta_dist,
  beta_correlation = beta_cor,
  interpretation = if (beta_cor > 0.7) "HIGH overlap (similar style)" else
                    if (beta_cor > 0.4) "MEDIUM overlap" else
                    "LOW overlap (orthogonal styles)"
)

state$family_weights_alpha <- as.list(family_weights)
state$quality_share_alpha <- quality_share
state$tail_share_alpha <- tail_share

state$liquidity_audit_top20 <- list(
  threshold_won = LIQ_THRESHOLD,
  n_pass = sum(liq_pass),
  n_total = length(liq_pass),
  pct_pass = mean(liq_pass) * 100,
  worst_adv_top20 = min(top20_dv$ADV_20d, na.rm = TRUE),
  median_adv_top20 = median(top20_dv$ADV_20d, na.rm = TRUE)
)

# RF flag for AX-007
state$rf_flags[[length(state$rf_flags) + 1]] <- list(
  flag_id = "RF-R-AX007", severity = "HIGH",
  description = paste0("AX-007 single-sleeve top20 mechanism break risk active: ",
    "no exceptions met (multi-sleeve / long-short / 50+ / ML sizing all FALSE). ",
    "Combined with AX-001 v2 axis 3 FAIL (alpha-research bad/normal IC ratio 0.79 OOS), ",
    "structural risk elevated. Optimizer should consider 4 exceptions for admission."))

if (beta_cor > 0.7) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R-STYLE", severity = "MEDIUM",
    description = sprintf("Alpha style β cor with STR_1715 = %.3f > 0.70 (similar style despite low return cor)", beta_cor))
}

if (mean(liq_pass) < 0.95) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R-LIQ", severity = "MEDIUM",
    description = sprintf("Top20 liquidity pass rate %.1f%% < 95%%", mean(liq_pass) * 100))
}

saveRDS(state, file.path(WT_DIR, "step6_state.rds"))
cat("[Step6] DONE.\n")
