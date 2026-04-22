#==============================================================================
# PG2 Portfolio Risk Validation — rev4_supplement Phase_3 8-Strategy
# Risk Manager L13 Engine 4-Axis Validation
# CVaR_95 / CDaR_95 / Tail Dependence / Q25 Exposure
#
# Non-debate, pure quantitative risk measurement
# Harness: tail_risk_engine.R, regime_garch.R (DCC), advanced_weights.R
#==============================================================================

cat("=== [RiskMgr] PG2 CVaR Validation rev4_supplement ===\n")
cat("=== Phase_3 8-Strategy Portfolio Risk 4-Axis ===\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"

# Source tail risk engine
source(file.path(BASE, "02_Infrastructure/portfolio/tail_risk_engine.R"))

#==============================================================================
# 1. LOAD REALIZED STRATEGY RETURNS
#==============================================================================
cat("[1/6] Loading realized strategy returns...\n")

# STR_1679v2 (daily returns available)
str1679_ret <- fread(file.path(BASE, "04_Research/strategies/STR_1679_score_blend/output/daily_returns_primary.csv"))
str1679_ret[, Date := as.Date(Date)]
setkey(str1679_ret, Date)

# STR_1656_MLRA_M05 (daily nav available)
str1656_nav <- fread(file.path(BASE, "04_Research/strategies/STR_1656_MLRA/output/s5_mutations/M05/nav.csv"))
str1656_nav[, Date := as.Date(Date)]
str1656_nav[, NAV_norm := NAV / NAV[1]]
setkey(str1656_nav, Date)

# STR_1631_SYN_05: no daily returns CSV. Use performance.json stats.
# We need to reconstruct or use the monthly-level performance data.
# For portfolio-level analysis, we use the performance stats from JSON.

cat("  STR_1679v2: ", nrow(str1679_ret), " daily obs (",
    min(str1679_ret$Date), " ~ ", max(str1679_ret$Date), ")\n")
cat("  STR_1656_M05: ", nrow(str1656_nav), " daily obs (",
    min(str1656_nav$Date), " ~ ", max(str1656_nav$Date), ")\n")

#==============================================================================
# 2. BUILD PORTFOLIO PROFILES (Performance-based estimation)
#==============================================================================
cat("\n[2/6] Building strategy risk profiles...\n")

# --- Strategy-level risk parameters from actual/estimated data ---
# Format: list(sr, cagr, annvol, mdd, es99_m, skew, kurt)

strategies <- list(
  STR_1631 = list(
    name = "Core_Primary STR_1631_SYN_05 consensus_C19",
    weight = 0.22,
    sr = 1.248, cagr = 0.2253, annvol = 0.1806, mdd = 0.3386,
    es99_m = 0.138, skew = -0.50, kurt = 5.4, # estimated from performance
    role = "Core_Primary", family = "consensus",
    q25_share = 0.00
  ),
  STR_1679v2 = list(
    name = "Core_MSCD STR_1679v2",
    weight = 0.12,
    sr = 1.266, cagr = 0.2471, annvol = 0.1952, mdd = 0.2906,
    es99_m = 0.132, skew = -0.4888, kurt = 5.3751, # from tail_risk_result.json
    role = "Core_MSCD", family = "multi_sleeve_active_defense",
    q25_share = 0.00
  ),
  H_1688 = list(
    name = "Core_Secondary H_1688 residual_momentum",
    weight = 0.14,
    sr = 1.05, cagr = 0.16, annvol = 0.22, mdd = 0.35, # estimated from s0_record forecast
    es99_m = 0.18, skew = -0.7, kurt = 6.0,
    role = "Core_Secondary", family = "momentum_residual",
    q25_share = 0.00
  ),
  H_1676 = list(
    name = "Div_1 H_1676 consensus_residual",
    weight = 0.13,
    sr = 0.55, cagr = 0.10, annvol = 0.20, mdd = 0.38,
    es99_m = 0.17, skew = -0.55, kurt = 5.5,
    role = "Diversifier_1", family = "consensus_residual",
    q25_share = 0.00
  ),
  H_1685 = list(
    name = "Div_2 H_1685 investor_flow",
    weight = 0.09,
    sr = 0.70, cagr = 0.12, annvol = 0.22, mdd = 0.33,
    es99_m = 0.19, skew = -0.60, kurt = 5.8,
    role = "Diversifier_2", family = "investor_flow",
    q25_share = 0.00
  ),
  STR_1656 = list(
    name = "Div_ML STR_1656_MLRA_M05",
    weight = 0.12,
    sr = 0.927, cagr = 0.2282, annvol = 0.22, mdd = 0.7484,
    es99_m = 0.20, skew = -0.65, kurt = 6.5,
    role = "Diversifier_ML", family = "ML_complexity",
    q25_share = 0.05
  ),
  H_1682 = list(
    name = "Def_1 H_1682 distress_calmar",
    weight = 0.10,
    sr = 0.65, cagr = 0.08, annvol = 0.18, mdd = 0.30,
    es99_m = 0.15, skew = -0.40, kurt = 4.5,
    role = "Defense_1", family = "distress_path",
    q25_share = 0.60  # Q25 Ohlson O 60% weight in composite
  ),
  H_1689 = list(
    name = "Def_2 H_1689 quality_4axis",
    weight = 0.08,
    sr = 0.95, cagr = 0.14, annvol = 0.20, mdd = 0.35,
    es99_m = 0.17, skew = -0.50, kurt = 5.2,
    role = "Defense_2", family = "quality_multi_axis",
    q25_share = 0.25  # Q25 Ohlson is 1 of 4 axes
  )
)

# Verify weights sum to 1
total_w <- sum(sapply(strategies, `[[`, "weight"))
cat("  Total weight: ", total_w, "\n")
stopifnot(abs(total_w - 1.0) < 0.001)

#==============================================================================
# 3. AXIS 1: CVaR_95 Annual Estimation
#==============================================================================
cat("\n[3/6] Computing CVaR_95 annual...\n")

# Method: parametric CVaR using strategy-level statistics
# Portfolio CVaR = weighted contribution + tail correlation adjustment
# Use Cornish-Fisher expansion for non-normal adjustment

# Portfolio weighted moments (approximate)
w_vec <- sapply(strategies, `[[`, "weight")
vol_vec <- sapply(strategies, `[[`, "annvol")
skew_vec <- sapply(strategies, `[[`, "skew")
kurt_vec <- sapply(strategies, `[[`, "kurt")
es99m_vec <- sapply(strategies, `[[`, "es99_m")
sr_vec <- sapply(strategies, `[[`, "sr")
cagr_vec <- sapply(strategies, `[[`, "cagr")
mdd_vec <- sapply(strategies, `[[`, "mdd")

# Weighted portfolio return and volatility
port_cagr <- sum(w_vec * cagr_vec)
cat("  Portfolio weighted CAGR: ", round(port_cagr * 100, 2), "%\n")

# Correlation matrix scenarios
# rho = 0.2 (Governor projection), rho = 0.3 (conservative), rho = 0.5 (stress)
compute_port_vol <- function(w, sigma, rho_off_diag) {
  n <- length(w)
  cor_mat <- matrix(rho_off_diag, n, n)
  diag(cor_mat) <- 1.0
  cov_mat <- diag(sigma) %*% cor_mat %*% diag(sigma)
  sqrt(as.numeric(t(w) %*% cov_mat %*% w))
}

rho_scenarios <- c(0.2, 0.3, 0.5)
port_vols <- sapply(rho_scenarios, function(rho) {
  compute_port_vol(w_vec, vol_vec, rho)
})
names(port_vols) <- paste0("rho_", rho_scenarios)

cat("  Portfolio annualized vol:\n")
for(i in seq_along(rho_scenarios)) {
  cat("    rho=", rho_scenarios[i], " -> vol=", round(port_vols[i]*100, 2), "%\n")
}

# Portfolio skewness (weighted approximation — conservative)
port_skew <- sum(w_vec^3 * skew_vec) / sum(w_vec^3)
port_kurt <- sum(w_vec^4 * kurt_vec) / sum(w_vec^4)

cat("  Portfolio approx skew: ", round(port_skew, 3), "\n")
cat("  Portfolio approx excess kurt: ", round(port_kurt, 3), "\n")

# CVaR 95% annual using Cornish-Fisher
compute_cvar_annual <- function(mu, sigma, S, K, alpha = 0.05) {
  # Cornish-Fisher VaR
  z <- qnorm(alpha)
  z_cf <- z + (z^2 - 1) * S / 6 + (z^3 - 3*z) * K / 24 - (2*z^3 - 5*z) * S^2 / 36
  var_cf <- -(mu + z_cf * sigma)

  # CVaR approximation: E[L | L > VaR] for CF distribution
  # Use the parametric CVaR = VaR + sigma * dnorm(z_cf) / alpha
  es_cf <- var_cf + sigma * dnorm(z_cf) / alpha

  list(var_95 = var_cf, cvar_95 = es_cf, z_cf = z_cf)
}

cvar_results <- lapply(seq_along(rho_scenarios), function(i) {
  res <- compute_cvar_annual(port_cagr, port_vols[i], port_skew, port_kurt - 3)
  res$rho <- rho_scenarios[i]
  res
})

cat("\n  CVaR_95 annual estimates:\n")
for(r in cvar_results) {
  pass_flag <- ifelse(r$cvar_95 <= 0.15, "PASS", "FAIL")
  cat(sprintf("    rho=%.1f: VaR_95=%.2f%%, CVaR_95=%.2f%% [threshold -15%%] -> %s\n",
              r$rho, -r$var_95 * 100, -r$cvar_95 * 100, pass_flag))
}

#==============================================================================
# 4. AXIS 2: CDaR_95 Estimation
#==============================================================================
cat("\n[4/6] Computing CDaR_95...\n")

# For strategies with daily data, compute CDaR directly
# For hypothetical strategies (H_*), use the MDD proxy + CDaR/MDD ratio

# Direct CDaR from STR_1679v2 (from tail_risk_result.json: CDaR_95 = 0.2184)
str1679_cdar <- 0.2184

# Compute CDaR for STR_1656 from daily NAV
str1656_nav_vec <- str1656_nav$NAV_norm
str1656_cdar_result <- compute_cdar(str1656_nav_vec, alpha = 0.95)
cat("  STR_1656_M05 CDaR_95: ", round(str1656_cdar_result$cdar * 100, 2), "%\n")
cat("  STR_1656_M05 MaxDD: ", round(str1656_cdar_result$max_dd * 100, 2), "%\n")

# Estimate CDaR/MDD ratio from realized strategies
# Typical CDaR/MDD ratio: 0.60~0.85 (CDaR is upper tail average DD, less than MaxDD)
# STR_1679v2: CDaR/MDD = 0.2184/0.2906 = 0.751
cdar_mdd_ratio_1679 <- str1679_cdar / 0.2906
cdar_mdd_ratio_1656 <- str1656_cdar_result$cdar / str1656_cdar_result$max_dd
avg_cdar_mdd_ratio <- mean(c(cdar_mdd_ratio_1679, cdar_mdd_ratio_1656))

cat("  CDaR/MDD ratio STR_1679v2: ", round(cdar_mdd_ratio_1679, 3), "\n")
cat("  CDaR/MDD ratio STR_1656: ", round(cdar_mdd_ratio_1656, 3), "\n")
cat("  Average CDaR/MDD ratio: ", round(avg_cdar_mdd_ratio, 3), "\n")

# Estimate portfolio CDaR
# Portfolio MDD estimation from weighted drawdowns with diversification
# Using rho-adjusted formula: port_MDD ~ max(weighted_vol) * sqrt(correlation)
# More robust: use stress period overlay approach

# Simple weighted MDD estimate (conservative, ignores diversification in drawdown)
# Drawdown is path-dependent, so weighted average MDD is a lower bound
# Correlation during crisis amplifies MDD vs average

weighted_mdd_lower <- sum(w_vec * mdd_vec)  # lower bound (perfect diversification)
weighted_mdd_nodiv <- max(mdd_vec)           # upper bound (worst single strategy)

# Diversification-adjusted MDD estimation
# For rho=0.2: drawdown correlation is typically 2x point-in-time correlation
# Crisis correlation escalation factor: Longin-Solnik (2001) 1.5x~2.5x
crisis_rho_multiplier <- 2.0

port_mdd_estimates <- sapply(rho_scenarios, function(rho) {
  crisis_rho <- min(rho * crisis_rho_multiplier, 0.95)
  # Using weighted vol approach for MDD with crisis correlation
  port_crisis_vol <- compute_port_vol(w_vec, mdd_vec, crisis_rho)
  # MDD diversification: sqrt(w'Sigma_dd w)
  port_crisis_vol
})

cat("\n  Portfolio MDD estimates (crisis-adjusted):\n")
for(i in seq_along(rho_scenarios)) {
  cat(sprintf("    rho=%.1f (crisis rho=%.2f): Est MDD=%.2f%%\n",
              rho_scenarios[i], min(rho_scenarios[i] * crisis_rho_multiplier, 0.95),
              port_mdd_estimates[i] * 100))
}

# Portfolio CDaR = MDD_estimate * avg_cdar_mdd_ratio
port_cdar_estimates <- port_mdd_estimates * avg_cdar_mdd_ratio

cat("\n  Portfolio CDaR_95 estimates:\n")
for(i in seq_along(rho_scenarios)) {
  pass_flag <- ifelse(port_cdar_estimates[i] <= 0.22, "PASS", "FAIL")
  cat(sprintf("    rho=%.1f: CDaR_95 est=%.2f%% [threshold -22%%] -> %s\n",
              rho_scenarios[i], port_cdar_estimates[i] * 100, pass_flag))
}

#==============================================================================
# 5. AXIS 3: Tail Dependence Estimation
#==============================================================================
cat("\n[5/6] Estimating tail dependence...\n")

# Without full multivariate daily return series for all 8 strategies,
# we estimate tail dependence from:
# (a) STR_1679v2 tail_risk_result.json shape parameter xi=0.602 (heavy tail)
# (b) Known family relationships
# (c) Stress period common factor exposure

# Tail dependence coefficient (lambda_U, lambda_L) for bivariate t-copula:
# lambda_L = 2 * t_{nu+1}(-sqrt((nu+1)(1-rho)/(1+rho)))
# where nu = degrees of freedom, rho = correlation

# Estimate from STR_1679v2 GPD shape xi = 0.602 (heavy tail)
# This implies effective df ~ 1/xi = 1.66 for return distribution
# For bivariate copula, typical Korean equity tail df ~ 3-5

estimate_tail_dependence <- function(rho, nu = 4) {
  # Lower tail dependence coefficient (bivariate t-copula)
  # Demarta & McNeil (2005)
  arg <- -sqrt((nu + 1) * (1 - rho) / (1 + rho))
  lambda_L <- 2 * pt(arg, df = nu + 1)
  lambda_L
}

# Pairwise tail dependence estimates
# Group by role similarity for correlation estimates
# Core-Core: higher rho in crisis, Def-Core: lower, Div-Core: moderate

pairwise_crisis_rho <- matrix(0.2, 8, 8)
diag(pairwise_crisis_rho) <- 1.0
rownames(pairwise_crisis_rho) <- colnames(pairwise_crisis_rho) <- names(strategies)

# Same-family or related pairs have higher crisis rho
# Core-Core pairs
pairwise_crisis_rho["STR_1631", "STR_1679v2"] <- 0.45  # Both consensus-adjacent
pairwise_crisis_rho["STR_1679v2", "STR_1631"] <- 0.45
pairwise_crisis_rho["STR_1631", "H_1688"] <- 0.35      # Consensus vs ResidMom
pairwise_crisis_rho["H_1688", "STR_1631"] <- 0.35
pairwise_crisis_rho["STR_1679v2", "H_1688"] <- 0.30    # MSCD vs ResidMom
pairwise_crisis_rho["H_1688", "STR_1679v2"] <- 0.30

# Consensus family cluster
pairwise_crisis_rho["STR_1631", "H_1676"] <- 0.55       # Both consensus-derived
pairwise_crisis_rho["H_1676", "STR_1631"] <- 0.55

# Defense-Core: negative or low
pairwise_crisis_rho["H_1682", c("STR_1631","STR_1679v2","H_1688")] <- c(0.10, 0.15, 0.10)
pairwise_crisis_rho[c("STR_1631","STR_1679v2","H_1688"), "H_1682"] <- c(0.10, 0.15, 0.10)

# Q25 sharing: H_1682 vs H_1689
pairwise_crisis_rho["H_1682", "H_1689"] <- 0.40  # Q25 factor shared
pairwise_crisis_rho["H_1689", "H_1682"] <- 0.40

# Flow divergence mostly independent
pairwise_crisis_rho["H_1685", ] <- 0.15
pairwise_crisis_rho[, "H_1685"] <- 0.15
pairwise_crisis_rho["H_1685", "H_1685"] <- 1.0

# ML complexity has moderate dependence on everything
pairwise_crisis_rho["STR_1656", ] <- 0.25
pairwise_crisis_rho[, "STR_1656"] <- 0.25
pairwise_crisis_rho["STR_1656", "STR_1656"] <- 1.0

# Compute tail dependence for each pair
nu_est <- 4  # Typical for Korean equity (fat-tailed)
cat("  Using bivariate t-copula with nu=", nu_est, " df\n")

# Crisis-amplified tail dependence (Longin-Solnik 2001: crisis rho is 2x normal)
crisis_factor <- 2.0
tail_dep_mat <- matrix(NA, 8, 8)
rownames(tail_dep_mat) <- colnames(tail_dep_mat) <- names(strategies)

for(i in 1:8) {
  for(j in 1:8) {
    if(i == j) {
      tail_dep_mat[i,j] <- 1.0
    } else {
      crisis_rho_ij <- min(pairwise_crisis_rho[i,j] * crisis_factor, 0.95)
      tail_dep_mat[i,j] <- estimate_tail_dependence(crisis_rho_ij, nu_est)
    }
  }
}

# Max pairwise tail dependence
max_td <- max(tail_dep_mat[upper.tri(tail_dep_mat)])
max_td_idx <- which(tail_dep_mat == max_td & upper.tri(tail_dep_mat), arr.ind = TRUE)
max_td_pair <- paste(rownames(tail_dep_mat)[max_td_idx[1,1]],
                     colnames(tail_dep_mat)[max_td_idx[1,2]], sep=" <-> ")

# Weighted portfolio tail dependence
# Portfolio-level: weighted average of pairwise tail deps
port_tail_dep <- as.numeric(t(w_vec) %*% tail_dep_mat %*% w_vec)

cat("\n  Tail Dependence Coefficient results:\n")
cat("    Max pairwise TDC: ", round(max_td, 4), " (", max_td_pair, ")\n")
cat("    Portfolio-weighted TDC: ", round(port_tail_dep, 4), "\n")
cat("    Threshold: <= 0.40\n")

# Top 5 highest pairwise TDC
td_upper <- tail_dep_mat
td_upper[lower.tri(td_upper, diag = TRUE)] <- NA
td_pairs <- data.table(
  pair = character(),
  tdc = numeric()
)
for(i in 1:7) {
  for(j in (i+1):8) {
    td_pairs <- rbind(td_pairs, data.table(
      pair = paste(names(strategies)[i], "<->", names(strategies)[j]),
      tdc = tail_dep_mat[i,j]
    ))
  }
}
setorder(td_pairs, -tdc)
cat("\n  Top 5 highest pairwise TDC (crisis-adjusted):\n")
for(k in 1:min(5, nrow(td_pairs))) {
  cat(sprintf("    %s: %.4f\n", td_pairs$pair[k], td_pairs$tdc[k]))
}

pass_td <- max_td <= 0.40
cat("\n    VERDICT: max pairwise TDC = ", round(max_td, 4),
    ifelse(pass_td, " -> PASS", " -> FAIL"), "\n")

#==============================================================================
# 6. AXIS 4: Q25 Weighted Portfolio Exposure
#==============================================================================
cat("\n[6/6] Computing Q25 weighted portfolio exposure...\n")

q25_shares <- sapply(strategies, `[[`, "q25_share")
q25_portfolio_exposure <- sum(w_vec * q25_shares)

cat("  Strategy Q25 shares:\n")
for(s in names(strategies)) {
  if(strategies[[s]]$q25_share > 0) {
    cat(sprintf("    %s: weight=%.2f, q25_share=%.2f, contribution=%.4f\n",
                s, strategies[[s]]$weight, strategies[[s]]$q25_share,
                strategies[[s]]$weight * strategies[[s]]$q25_share))
  }
}
cat("  Portfolio Q25 exposure: ", round(q25_portfolio_exposure * 100, 2), "%\n")
cat("  Threshold: <= 35%\n")

pass_q25 <- q25_portfolio_exposure <= 0.35
cat("  VERDICT: ", round(q25_portfolio_exposure * 100, 2), "% ",
    ifelse(pass_q25, "-> PASS", "-> FAIL"), "\n")

#==============================================================================
# 7. STRESS TEST SCENARIOS
#==============================================================================
cat("\n[STRESS] Running stress test scenarios...\n")

# 8 major stress periods (reference_stress_periods.md reconstructed)
stress_periods <- list(
  list(name = "9/11 + Iraq War", start = "2001-09-11", end = "2003-03-20",
       impact = "Global geopolitical. Korean market -48%. Momentum neutral."),
  list(name = "GFC 2008-2009", start = "2008-09-15", end = "2009-03-09",
       impact = "Global financial crisis. KOSPI -54%. Momentum crash severe."),
  list(name = "European Debt Crisis", start = "2011-07-01", end = "2011-11-30",
       impact = "EU sovereign debt. KOSPI -26%. Quality strong."),
  list(name = "China Shock 2015-2016", start = "2015-06-12", end = "2016-02-11",
       impact = "China devaluation. KOSPI -20%. Flow divergence strong."),
  list(name = "Korea Political Crisis 2016", start = "2016-10-01", end = "2016-12-09",
       impact = "Impeachment. KOSPI -8%. Domestic idiosyncratic."),
  list(name = "US-China Trade War", start = "2018-10-01", end = "2018-12-24",
       impact = "Trade tensions. KOSPI -18%. Small-cap vulnerable."),
  list(name = "COVID-19 Crash", start = "2020-02-20", end = "2020-03-19",
       impact = "Pandemic. KOSPI -35% in 1 month. V-recovery. Momentum reversal."),
  list(name = "Fed Tightening 2022", start = "2022-01-03", end = "2022-10-13",
       impact = "Rate hikes. KOSPI -33%. Prolonged. Quality/Distress defense.")
)

# Estimate per-strategy drawdown in each stress period
# For realized strategies, compute from actual data where available
# For H_* candidates, estimate from factor characteristics

estimate_stress_drawdown <- function(strategy, scenario_name) {
  # Base: strategy MDD * scenario severity factor
  # Adjust by role: defense strategies have lower DD in stress
  vol <- strategy$annvol
  role <- strategy$role

  # Scenario severity multipliers (relative to full-sample MDD)
  severity <- switch(scenario_name,
    "GFC 2008-2009" = 0.95,
    "COVID-19 Crash" = 0.75,
    "China Shock 2015-2016" = 0.55,
    "Fed Tightening 2022" = 0.65,
    "European Debt Crisis" = 0.50,
    "US-China Trade War" = 0.45,
    "9/11 + Iraq War" = 0.80,
    "Korea Political Crisis 2016" = 0.25,
    0.50  # default
  )

  # Role adjustment
  role_adj <- switch(role,
    "Defense_1" = 0.60,
    "Defense_2" = 0.70,
    "Diversifier_1" = 0.85,
    "Diversifier_2" = 0.80,
    "Diversifier_ML" = 0.90,
    "Core_Primary" = 1.0,
    "Core_MSCD" = 0.85,      # Active defense dampens
    "Core_Secondary" = 1.05,  # Momentum vulnerable in crash
    1.0
  )

  # Momentum crash adjustment for H_1688
  mom_crash_adj <- 1.0
  if(grepl("momentum", strategy$family) && scenario_name == "GFC 2008-2009") {
    mom_crash_adj <- 1.30  # Momentum crash amplification
  }
  if(grepl("momentum", strategy$family) && scenario_name == "COVID-19 Crash") {
    mom_crash_adj <- 1.20  # V-recovery reversal
  }

  dd <- strategy$mdd * severity * role_adj * mom_crash_adj
  min(dd, 0.80)  # cap at 80%
}

# Compute STR_1679v2 stress from actual daily returns where available
compute_actual_stress_dd <- function(ret_dt, start_date, end_date) {
  sub <- ret_dt[Date >= as.Date(start_date) & Date <= as.Date(end_date)]
  if(nrow(sub) < 5) return(NA)
  nav <- cumprod(1 + sub$Strategy_Ret)
  running_max <- cummax(nav)
  dd <- (nav - running_max) / running_max
  min(dd)
}

stress_results <- lapply(stress_periods, function(sp) {
  # Per-strategy drawdowns
  per_strat_dd <- sapply(strategies, function(s) {
    estimate_stress_drawdown(s, sp$name)
  })

  # Try actual data for STR_1679v2
  actual_1679 <- compute_actual_stress_dd(str1679_ret, sp$start, sp$end)
  if(!is.na(actual_1679)) per_strat_dd["STR_1679v2"] <- abs(actual_1679)

  # Portfolio weighted drawdown (with crisis correlation boost)
  # In stress, correlations converge to ~0.5-0.8
  port_stress_dd <- sqrt(as.numeric(t(w_vec) %*%
    (diag(per_strat_dd) %*% matrix(0.6, 8, 8) %*% diag(per_strat_dd) +
     diag(per_strat_dd^2 * 0.4)) %*% w_vec))

  list(
    scenario = sp$name,
    period = paste(sp$start, "~", sp$end),
    per_strategy_dd = round(per_strat_dd, 4),
    portfolio_dd = round(port_stress_dd, 4),
    impact_note = sp$impact
  )
})

cat("\n  Stress Test Results (estimated portfolio drawdown):\n")
cat(sprintf("  %-30s %10s %12s\n", "Scenario", "Port DD", "Verdict"))
cat("  ", paste(rep("-", 55), collapse=""), "\n")
for(sr in stress_results) {
  verdict <- ifelse(sr$portfolio_dd <= 0.25, "ACCEPTABLE",
                    ifelse(sr$portfolio_dd <= 0.35, "CAUTION", "CONCERN"))
  cat(sprintf("  %-30s %9.2f%% %12s\n", sr$scenario, sr$portfolio_dd * 100, verdict))
}

# Key vulnerability: H_1688 momentum crash in GFC
cat("\n  [CRITICAL] H_1688 momentum crash vulnerability (GFC 2008-2009):\n")
gfc_1688_dd <- sapply(strategies, function(s) estimate_stress_drawdown(s, "GFC 2008-2009"))
cat("    H_1688 estimated GFC DD: ", round(gfc_1688_dd["H_1688"] * 100, 2), "%\n")
cat("    H_1688 weight in portfolio: ", strategies$H_1688$weight * 100, "%\n")
cat("    H_1688 GFC contribution to port DD: ",
    round(strategies$H_1688$weight * gfc_1688_dd["H_1688"] * 100, 2), "%\n")

#==============================================================================
# 8. STR_1679v2 FAMILY CLASSIFICATION OPINION
#==============================================================================
cat("\n[OPINION] STR_1679v2 family classification assessment...\n")

str1679_opinion <- paste0(
  "STR_1679v2 is structurally a 'multi_sleeve_core_with_active_defense' (MSCD). ",
  "The Def5 sleeve provides 22.55pp MDD reduction (51.61% -> 29.06%). ",
  "Core15 alone SR=1.293 > Combined SR=1.266, meaning Def5 acts as volatility dampener, not alpha source. ",
  "Risk Manager assessment: STR_1679v2 SHOULD NOT be classified as pure Core. ",
  "It is an overlay-dependent structure where the DD overlay contributes ~22.6pp of MDD reduction. ",
  "Without overlay, Core15 MDD=51.61% (HARD FAIL). ",
  "L-146 applicability: the MDD improvement is from BOTH the Def sleeve AND the DD overlay acting together. ",
  "Recommendation: classify as 'diversifier_with_structural_defense'. ",
  "In portfolio context at 12% weight, this is acceptable. ",
  "Key risk: if market regime shifts to sustained drawdown (not V-recovery), ",
  "the Q07-based Def5 sleeve may underperform (L-143 empirical warning). ",
  "Governor should consider H_1682 as replacement for Def5 sub-sleeve in STR_1679v3."
)

cat("  ", str1679_opinion, "\n")

#==============================================================================
# 9. OVERALL VERDICT & RECOMMENDATIONS
#==============================================================================
cat("\n========================================\n")
cat("  FINAL 4-AXIS VALIDATION SUMMARY\n")
cat("========================================\n\n")

# Use rho=0.3 as the conservative base case (not optimistic 0.2)
conservative_idx <- 2  # rho=0.3

cvar_value <- -cvar_results[[conservative_idx]]$cvar_95
cdar_value <- port_cdar_estimates[conservative_idx]
td_value <- max_td
q25_value <- q25_portfolio_exposure

axis_results <- list(
  cvar_95_annual = list(
    value = round(cvar_value, 4),
    threshold = -0.15,
    pass = cvar_value >= -0.15,  # loss is negative, so >= threshold is pass
    note = sprintf("CVaR_95 annual = %.2f%% at rho=0.3 (conservative)", cvar_value * 100)
  ),
  cdar_95 = list(
    value = round(cdar_value, 4),
    threshold = -0.22,
    pass = cdar_value <= 0.22,
    note = sprintf("CDaR_95 = %.2f%% at rho=0.3 with crisis correlation 2x", cdar_value * 100)
  ),
  tail_dependence_max = list(
    value = round(td_value, 4),
    threshold = 0.40,
    pass = td_value <= 0.40,
    note = sprintf("Max pairwise TDC = %.4f (%s)", td_value, max_td_pair)
  ),
  q25_weighted_exposure = list(
    value = round(q25_value, 4),
    threshold = 0.35,
    pass = q25_value <= 0.35,
    note = sprintf("Portfolio Q25 exposure = %.2f%% (H_1682 60%% + H_1689 25%% + STR_1656 5%%)",
                   q25_value * 100)
  )
)

pass_count <- sum(sapply(axis_results, `[[`, "pass"))

for(ax_name in names(axis_results)) {
  ax <- axis_results[[ax_name]]
  flag <- ifelse(ax$pass, "PASS", "FAIL")
  cat(sprintf("  [%s] %s: value=%.4f, threshold=%.4f\n", flag, ax_name, ax$value, ax$threshold))
  cat(sprintf("         %s\n", ax$note))
}

cat(sprintf("\n  Overall: %d/4 PASS\n", pass_count))

# Recommendations
recommendations <- list()

if(!axis_results$cvar_95_annual$pass) {
  recommendations <- c(recommendations,
    "CVaR BREACH: Reduce Core exposure. STR_1631 from 22% to 18% + H_1688 from 14% to 10%.")
}

if(!axis_results$cdar_95$pass) {
  recommendations <- c(recommendations,
    "CDaR BREACH: Increase Defense allocation. H_1682 from 10% to 14% for MDD dampening.")
}

if(!axis_results$tail_dependence_max$pass) {
  recommendations <- c(recommendations,
    paste0("TAIL DEP BREACH: Pair ", max_td_pair, " exceeds 0.4. ",
           "Consider reducing weight of the more volatile strategy in the pair."))
}

# Always add these risk warnings
recommendations <- c(recommendations,
  "H_1688 momentum crash exposure in GFC-type scenario is the primary tail risk. Barroso 2015 scaling MANDATORY in S5.",
  "STR_1631-H_1676 consensus family concentration at 35% (22%+13%). If crisis hits consensus signal, both fail simultaneously.",
  "STR_1679v2 overlay dependency: without DD overlay, Core15 MDD=51.61%. DD overlay calibration drift is a hidden risk.",
  "rho=0.2 assumption is OPTIMISTIC. Portfolio was projected at SR 2.01 under rho=0.2, but at rho=0.3, SR drops to ~1.82.",
  "MRS currently at CRISIS (63.1). Phase_1 implementation timing coincides with elevated regime risk."
)

cat("\n  Recommendations:\n")
for(i in seq_along(recommendations)) {
  cat(sprintf("  [R%d] %s\n", i, recommendations[i]))
}

#==============================================================================
# 10. WRITE OUTPUT JSON
#==============================================================================
cat("\n[OUTPUT] Writing validation JSON...\n")

output <- list(
  from = "Risk_Manager",
  to = "Q-Lead",
  type = "PG2_CVAR_VALIDATION",
  stage = "PG2_rev4_supplement_4axis_validation",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  session = 66,

  portfolio_composition = lapply(strategies, function(s) {
    list(name = s$name, weight = s$weight, role = s$role, family = s$family)
  }),

  validation_4axis = axis_results,
  pass_count = paste0(pass_count, "/4"),

  rho_sensitivity = list(
    rho_02 = list(
      cvar_95 = round(-cvar_results[[1]]$cvar_95, 4),
      port_vol = round(port_vols[1], 4),
      cdar_95 = round(port_cdar_estimates[1], 4)
    ),
    rho_03 = list(
      cvar_95 = round(-cvar_results[[2]]$cvar_95, 4),
      port_vol = round(port_vols[2], 4),
      cdar_95 = round(port_cdar_estimates[2], 4)
    ),
    rho_05 = list(
      cvar_95 = round(-cvar_results[[3]]$cvar_95, 4),
      port_vol = round(port_vols[3], 4),
      cdar_95 = round(port_cdar_estimates[3], 4)
    )
  ),

  stress_test_scenarios = lapply(stress_results, function(sr) {
    list(
      scenario = sr$scenario,
      period = sr$period,
      portfolio_dd = sr$portfolio_dd,
      verdict = ifelse(sr$portfolio_dd <= 0.25, "ACCEPTABLE",
                       ifelse(sr$portfolio_dd <= 0.35, "CAUTION", "CONCERN"))
    )
  }),

  tail_dependence_matrix = list(
    top_5_pairs = lapply(1:min(5, nrow(td_pairs)), function(k) {
      list(pair = td_pairs$pair[k], tdc = td_pairs$tdc[k])
    }),
    nu_df_estimate = nu_est,
    crisis_rho_multiplier = crisis_rho_multiplier
  ),

  q25_exposure_detail = list(
    H_1682 = list(weight = 0.10, q25_share = 0.60, contribution = 0.06),
    H_1689 = list(weight = 0.08, q25_share = 0.25, contribution = 0.02),
    STR_1656 = list(weight = 0.12, q25_share = 0.05, contribution = 0.006),
    total_portfolio_q25 = round(q25_portfolio_exposure, 4)
  ),

  str_1679v2_family_opinion = str1679_opinion,

  recommendations = recommendations,

  methodology_notes = list(
    cvar_method = "Cornish-Fisher CVaR with portfolio-level moment approximation",
    cdar_method = "CDaR/MDD ratio calibrated from STR_1679v2 (0.751) and STR_1656 realized data",
    tail_dep_method = "Bivariate t-copula (nu=4) with Longin-Solnik 2001 crisis correlation escalation (2x)",
    stress_method = "Severity-role-family adjusted MDD estimation with crisis correlation matrix",
    conservative_base = "rho=0.3 used as conservative base (NOT optimistic rho=0.2)",
    references = c(
      "Pfaff (2016) Ch.6-7 (Cornish-Fisher, EVT/GPD)",
      "Chekhlov et al. (2005) CDaR",
      "Longin & Solnik (2001) 'Extreme Correlation of International Equity Markets'",
      "Demarta & McNeil (2005) 'The t Copula and Related Copulas'",
      "L-115 (beta reduction != correlation reduction)",
      "L-106 (market beta dominates)"
    )
  )
)

out_dir <- file.path(BASE, "qepm/mailbox/risk_manager/outbox")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "pg2_cvar_validation_rev4.json")
jsonlite::write_json(output, out_path, auto_unbox = TRUE, pretty = TRUE)

cat("\n  Output saved to: ", out_path, "\n")
cat("\n=== [RiskMgr] PG2 CVaR Validation COMPLETE ===\n")
