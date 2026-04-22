#==============================================================================
# PG2 Portfolio Risk Validation — rev5 Governor 8-Strategy Rebalanced
# Risk Manager L13 Engine 4-Axis Validation
# CVaR_95 / CDaR_95 / Tail Dependence / Q25 Exposure
#
# rev4 -> rev5 weight changes (Governor rebalance):
#   STR_1631: 22% -> 18%   H_1688: 14% -> 10%   H_1676: 13% -> 8%
#   H_1685: 9% -> 13%      H_1682: 10% -> 16%    H_1689: 8% -> 11%
#   STR_1679v2: 12% unchanged  STR_1656: 12% unchanged
#
# Conservative base: rho = 0.3
# CDaR/MDD ratio: 0.75 (specified)
# TDC: t-copula nu=4, Longin-Solnik 2x crisis factor
# H_1676 scenario A/B TDC analysis
#==============================================================================

cat("=== [RiskMgr] PG2 CVaR Validation rev5 ===\n")
cat("=== Governor rev5 8-Strategy Rebalanced Portfolio ===\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"

# Source tail risk engine
source(file.path(BASE, "02_Infrastructure/portfolio/tail_risk_engine.R"))

#==============================================================================
# 1. REV5 STRATEGY PROFILES (weights updated per Governor rev5)
#==============================================================================
cat("[1/4] Building rev5 strategy risk profiles...\n")

# Strategy-level parameters preserved from rev4; only weights changed.
# Risk parameters: sr, cagr, annvol, mdd, es99_m, skew, kurt, q25_share
strategies <- list(
  STR_1631 = list(
    name = "Core_Primary STR_1631_SYN_05 consensus_C19",
    weight = 0.18,  # rev4: 0.22 -> rev5: 0.18
    sr = 1.248, cagr = 0.2253, annvol = 0.1806, mdd = 0.3386,
    es99_m = 0.138, skew = -0.50, kurt = 5.4,
    role = "Core_Primary", family = "consensus",
    q25_share = 0.00
  ),
  H_1688 = list(
    name = "Core_Secondary H_1688 residual_momentum",
    weight = 0.10,  # rev4: 0.14 -> rev5: 0.10
    sr = 1.05, cagr = 0.16, annvol = 0.22, mdd = 0.35,
    es99_m = 0.18, skew = -0.7, kurt = 6.0,
    role = "Core_Secondary", family = "momentum_residual",
    q25_share = 0.00
  ),
  H_1676 = list(
    name = "Div_1 H_1676 consensus_residual",
    weight = 0.08,  # rev4: 0.13 -> rev5: 0.08
    sr = 0.55, cagr = 0.10, annvol = 0.20, mdd = 0.38,
    es99_m = 0.17, skew = -0.55, kurt = 5.5,
    role = "Diversifier_1", family = "consensus_residual",
    q25_share = 0.00
  ),
  H_1685 = list(
    name = "Div_2 H_1685 investor_flow",
    weight = 0.13,  # rev4: 0.09 -> rev5: 0.13
    sr = 0.70, cagr = 0.12, annvol = 0.22, mdd = 0.33,
    es99_m = 0.19, skew = -0.60, kurt = 5.8,
    role = "Diversifier_2", family = "investor_flow",
    q25_share = 0.00
  ),
  STR_1679v2 = list(
    name = "Core_MSCD STR_1679v2",
    weight = 0.12,  # unchanged
    sr = 1.266, cagr = 0.2471, annvol = 0.1952, mdd = 0.2906,
    es99_m = 0.132, skew = -0.4888, kurt = 5.3751,
    role = "Core_MSCD", family = "multi_sleeve_active_defense",
    q25_share = 0.00
  ),
  STR_1656 = list(
    name = "Div_ML STR_1656_MLRA_M05",
    weight = 0.12,  # unchanged
    sr = 0.927, cagr = 0.2282, annvol = 0.22, mdd = 0.7484,
    es99_m = 0.20, skew = -0.65, kurt = 6.5,
    role = "Diversifier_ML", family = "ML_complexity",
    q25_share = 0.05
  ),
  H_1682 = list(
    name = "Def_1 H_1682 distress_calmar",
    weight = 0.16,  # rev4: 0.10 -> rev5: 0.16
    sr = 0.65, cagr = 0.08, annvol = 0.18, mdd = 0.30,
    es99_m = 0.15, skew = -0.40, kurt = 4.5,
    role = "Defense_1", family = "distress_path",
    q25_share = 0.60
  ),
  H_1689 = list(
    name = "Def_2 H_1689 quality_4axis",
    weight = 0.11,  # rev4: 0.08 -> rev5: 0.11
    sr = 0.95, cagr = 0.14, annvol = 0.20, mdd = 0.35,
    es99_m = 0.17, skew = -0.50, kurt = 5.2,
    role = "Defense_2", family = "quality_multi_axis",
    q25_share = 0.25
  )
)

# Verify weights sum to 1
total_w <- sum(sapply(strategies, `[[`, "weight"))
cat("  Total weight: ", total_w, "\n")
stopifnot(abs(total_w - 1.0) < 0.001)

# Extract vectors
w_vec <- sapply(strategies, `[[`, "weight")
vol_vec <- sapply(strategies, `[[`, "annvol")
skew_vec <- sapply(strategies, `[[`, "skew")
kurt_vec <- sapply(strategies, `[[`, "kurt")
cagr_vec <- sapply(strategies, `[[`, "cagr")
mdd_vec <- sapply(strategies, `[[`, "mdd")

# Weighted portfolio return
port_cagr <- sum(w_vec * cagr_vec)
cat("  Portfolio weighted CAGR: ", round(port_cagr * 100, 2), "%\n")

# Weight change summary
cat("\n  rev4 -> rev5 weight changes:\n")
rev4_w <- c(STR_1631=0.22, H_1688=0.14, H_1676=0.13, H_1685=0.09,
            STR_1679v2=0.12, STR_1656=0.12, H_1682=0.10, H_1689=0.08)
for(nm in names(w_vec)) {
  delta <- w_vec[nm] - rev4_w[nm]
  if(abs(delta) > 0.001) {
    cat(sprintf("    %s: %.0f%% -> %.0f%% (%+.0f%%)\n",
                nm, rev4_w[nm]*100, w_vec[nm]*100, delta*100))
  }
}

#==============================================================================
# 2. AXIS 1: CVaR_95 Annual (Cornish-Fisher)
#==============================================================================
cat("\n[2/4] AXIS 1: CVaR_95 annual (Cornish-Fisher)...\n")

compute_port_vol <- function(w, sigma, rho_off_diag) {
  n <- length(w)
  cor_mat <- matrix(rho_off_diag, n, n)
  diag(cor_mat) <- 1.0
  cov_mat <- diag(sigma) %*% cor_mat %*% diag(sigma)
  sqrt(as.numeric(t(w) %*% cov_mat %*% w))
}

# rho = 0.3 conservative base (primary)
rho_base <- 0.3
port_vol <- compute_port_vol(w_vec, vol_vec, rho_base)

# Portfolio higher moments (weighted approx)
port_skew <- sum(w_vec^3 * skew_vec) / sum(w_vec^3)
port_kurt <- sum(w_vec^4 * kurt_vec) / sum(w_vec^4)

cat("  rho = ", rho_base, "\n")
cat("  Portfolio annualized vol: ", round(port_vol * 100, 2), "%\n")
cat("  Portfolio approx skew: ", round(port_skew, 3), "\n")
cat("  Portfolio approx excess kurt: ", round(port_kurt, 3), "\n")

# Cornish-Fisher CVaR 95%
alpha <- 0.05
z <- qnorm(alpha)
S <- port_skew
K <- port_kurt - 3  # excess kurtosis
z_cf <- z + (z^2 - 1) * S / 6 + (z^3 - 3*z) * K / 24 - (2*z^3 - 5*z) * S^2 / 36
var_cf <- -(port_cagr + z_cf * port_vol)
cvar_cf <- var_cf + port_vol * dnorm(z_cf) / alpha

# CVaR as annual loss (negative = loss)
cvar_95_annual <- -cvar_cf  # negative value means loss

cat(sprintf("  CF-VaR_95: %.2f%%\n", -var_cf * 100))
cat(sprintf("  CF-CVaR_95: %.2f%%\n", cvar_95_annual * 100))
cat(sprintf("  Threshold: >= -15%%\n"))
pass_cvar <- cvar_95_annual >= -0.15
cat(sprintf("  VERDICT: %.2f%% -> %s\n", cvar_95_annual * 100, ifelse(pass_cvar, "PASS", "FAIL")))

#==============================================================================
# 3. AXIS 2: CDaR_95 (CDaR/MDD ratio = 0.75 specified)
#==============================================================================
cat("\n[3/4] AXIS 2: CDaR_95 (CDaR/MDD ratio = 0.75)...\n")

cdar_mdd_ratio <- 0.75  # specified by request

# Crisis-adjusted portfolio MDD estimation
crisis_rho_multiplier <- 2.0
crisis_rho <- min(rho_base * crisis_rho_multiplier, 0.95)

# Portfolio MDD via drawdown-space correlation
port_mdd_est <- compute_port_vol(w_vec, mdd_vec, crisis_rho)

# CDaR = MDD * ratio
cdar_95_est <- port_mdd_est * cdar_mdd_ratio

cat(sprintf("  Crisis rho: %.2f (base %.1f x %.1f)\n", crisis_rho, rho_base, crisis_rho_multiplier))
cat(sprintf("  Portfolio MDD estimate: %.2f%%\n", port_mdd_est * 100))
cat(sprintf("  CDaR/MDD ratio: %.2f (specified)\n", cdar_mdd_ratio))
cat(sprintf("  CDaR_95 estimate: %.2f%%\n", cdar_95_est * 100))
cat(sprintf("  Threshold: <= 22%%\n"))
pass_cdar <- cdar_95_est <= 0.22
cat(sprintf("  VERDICT: %.2f%% -> %s\n", cdar_95_est * 100, ifelse(pass_cdar, "PASS", "FAIL")))

#==============================================================================
# 4. AXIS 3: Pairwise TDC Maximum (t-copula nu=4, Longin-Solnik 2x)
#==============================================================================
cat("\n[4/4] AXIS 3: Tail Dependence Coefficient...\n")

nu_est <- 4  # t-copula df

estimate_tail_dependence <- function(rho, nu = 4) {
  arg <- -sqrt((nu + 1) * (1 - rho) / (1 + rho))
  lambda_L <- 2 * pt(arg, df = nu + 1)
  lambda_L
}

# Pairwise base correlation matrix (same structure as rev4)
n_strat <- 8
strat_names <- names(strategies)
pairwise_rho <- matrix(0.2, n_strat, n_strat)
diag(pairwise_rho) <- 1.0
rownames(pairwise_rho) <- colnames(pairwise_rho) <- strat_names

# Structural correlation estimates (base, pre-crisis)
# Core-Core
pairwise_rho["STR_1631", "STR_1679v2"] <- 0.45
pairwise_rho["STR_1679v2", "STR_1631"] <- 0.45
pairwise_rho["STR_1631", "H_1688"] <- 0.35
pairwise_rho["H_1688", "STR_1631"] <- 0.35
pairwise_rho["STR_1679v2", "H_1688"] <- 0.30
pairwise_rho["H_1688", "STR_1679v2"] <- 0.30

# Consensus family cluster: STR_1631 <-> H_1676
pairwise_rho["STR_1631", "H_1676"] <- 0.55
pairwise_rho["H_1676", "STR_1631"] <- 0.55

# Defense-Core: low
pairwise_rho["H_1682", c("STR_1631","STR_1679v2","H_1688")] <- c(0.10, 0.15, 0.10)
pairwise_rho[c("STR_1631","STR_1679v2","H_1688"), "H_1682"] <- c(0.10, 0.15, 0.10)

# Q25 sharing: H_1682 vs H_1689
pairwise_rho["H_1682", "H_1689"] <- 0.40
pairwise_rho["H_1689", "H_1682"] <- 0.40

# Flow divergence mostly independent
pairwise_rho["H_1685", ] <- 0.15
pairwise_rho[, "H_1685"] <- 0.15
pairwise_rho["H_1685", "H_1685"] <- 1.0

# ML complexity moderate
pairwise_rho["STR_1656", ] <- 0.25
pairwise_rho[, "STR_1656"] <- 0.25
pairwise_rho["STR_1656", "STR_1656"] <- 1.0

# H_1689 Defense_2 vs Core: low-moderate
pairwise_rho["H_1689", c("STR_1631","STR_1679v2","H_1688")] <- c(0.15, 0.20, 0.15)
pairwise_rho[c("STR_1631","STR_1679v2","H_1688"), "H_1689"] <- c(0.15, 0.20, 0.15)

# H_1676 vs other diversifiers
pairwise_rho["H_1676", "H_1685"] <- 0.15
pairwise_rho["H_1685", "H_1676"] <- 0.15
pairwise_rho["H_1676", "STR_1656"] <- 0.25
pairwise_rho["STR_1656", "H_1676"] <- 0.25
pairwise_rho["H_1676", "STR_1679v2"] <- 0.35
pairwise_rho["STR_1679v2", "H_1676"] <- 0.35
pairwise_rho["H_1676", "H_1688"] <- 0.25
pairwise_rho["H_1688", "H_1676"] <- 0.25
pairwise_rho["H_1676", "H_1682"] <- 0.10
pairwise_rho["H_1682", "H_1676"] <- 0.10
pairwise_rho["H_1676", "H_1689"] <- 0.15
pairwise_rho["H_1689", "H_1676"] <- 0.15

# Compute TDC matrix with crisis amplification
crisis_factor <- 2.0  # Longin-Solnik
tail_dep_mat <- matrix(NA, n_strat, n_strat)
rownames(tail_dep_mat) <- colnames(tail_dep_mat) <- strat_names

for(i in 1:n_strat) {
  for(j in 1:n_strat) {
    if(i == j) {
      tail_dep_mat[i,j] <- 1.0
    } else {
      crisis_rho_ij <- min(pairwise_rho[i,j] * crisis_factor, 0.95)
      tail_dep_mat[i,j] <- estimate_tail_dependence(crisis_rho_ij, nu_est)
    }
  }
}

# Max pairwise TDC
max_td <- max(tail_dep_mat[upper.tri(tail_dep_mat)])
max_td_idx <- which(tail_dep_mat == max_td & upper.tri(tail_dep_mat), arr.ind = TRUE)
max_td_pair <- paste(rownames(tail_dep_mat)[max_td_idx[1,1]],
                     colnames(tail_dep_mat)[max_td_idx[1,2]], sep=" <-> ")

cat(sprintf("  Max pairwise TDC: %.4f (%s)\n", max_td, max_td_pair))
cat(sprintf("  Threshold: <= 0.40\n"))
pass_td <- max_td <= 0.40
cat(sprintf("  VERDICT: %.4f -> %s\n", max_td, ifelse(pass_td, "PASS", "FAIL")))

# Top 5 pairs
td_pairs <- data.table(pair = character(), tdc = numeric())
for(i in 1:(n_strat-1)) {
  for(j in (i+1):n_strat) {
    td_pairs <- rbind(td_pairs, data.table(
      pair = paste(strat_names[i], "<->", strat_names[j]),
      tdc = tail_dep_mat[i,j]
    ))
  }
}
setorder(td_pairs, -tdc)
cat("\n  Top 5 pairwise TDC:\n")
for(k in 1:min(5, nrow(td_pairs))) {
  cat(sprintf("    %s: %.4f\n", td_pairs$pair[k], td_pairs$tdc[k]))
}

#==============================================================================
# 4b. H_1676 SCENARIO A/B TDC vs STR_1631
#==============================================================================
cat("\n[4b] H_1676 Scenario A/B TDC vs STR_1631...\n")

# Scenario A: spec 강화 후 (residualization reduces crisis rho from 0.55 to ~0.35)
# Rationale: H_1676 residualizes C13 against size+idiovol, removing common factor
# exposure that drives crisis correlation with STR_1631 (C19 consensus).
# Post-residualization, structural rho drops to ~0.30-0.35.
rho_A_base <- 0.35  # post-residualization estimate
rho_A_crisis <- min(rho_A_base * crisis_factor, 0.95)
tdc_A <- estimate_tail_dependence(rho_A_crisis, nu_est)

# Scenario B: 현 spec 유지 (rho = 0.55, same as rev4)
rho_B_base <- 0.55  # current consensus family proximity
rho_B_crisis <- min(rho_B_base * crisis_factor, 0.95)
tdc_B <- estimate_tail_dependence(rho_B_crisis, nu_est)

cat(sprintf("  Scenario A (spec strengthened): base rho=%.2f, crisis rho=%.2f, TDC=%.4f\n",
            rho_A_base, rho_A_crisis, tdc_A))
cat(sprintf("  Scenario B (current spec):      base rho=%.2f, crisis rho=%.2f, TDC=%.4f\n",
            rho_B_base, rho_B_crisis, tdc_B))
cat(sprintf("  TDC reduction A vs B: %.4f (%.1f%%)\n",
            tdc_B - tdc_A, (tdc_B - tdc_A) / tdc_B * 100))

# Under scenario A, does max TDC change?
# Recompute with H_1676 rho adjusted
tail_dep_mat_A <- tail_dep_mat
# Update STR_1631 <-> H_1676
idx_1631 <- which(strat_names == "STR_1631")
idx_1676 <- which(strat_names == "H_1676")
tail_dep_mat_A[idx_1631, idx_1676] <- tdc_A
tail_dep_mat_A[idx_1676, idx_1631] <- tdc_A
max_td_A <- max(tail_dep_mat_A[upper.tri(tail_dep_mat_A)])
max_td_A_idx <- which(tail_dep_mat_A == max_td_A & upper.tri(tail_dep_mat_A), arr.ind = TRUE)
max_td_A_pair <- paste(rownames(tail_dep_mat_A)[max_td_A_idx[1,1]],
                       colnames(tail_dep_mat_A)[max_td_A_idx[1,2]], sep=" <-> ")

cat(sprintf("\n  Scenario A max pairwise TDC: %.4f (%s) -> %s\n",
            max_td_A, max_td_A_pair, ifelse(max_td_A <= 0.40, "PASS", "FAIL")))

#==============================================================================
# 5. AXIS 4: Q25 Weighted Exposure
#==============================================================================
cat("\n[5] AXIS 4: Q25 weighted portfolio exposure...\n")

q25_shares <- sapply(strategies, `[[`, "q25_share")
q25_portfolio_exposure <- sum(w_vec * q25_shares)

cat("  Contributions:\n")
for(s in names(strategies)) {
  if(strategies[[s]]$q25_share > 0) {
    cat(sprintf("    %s: w=%.2f, q25_share=%.2f, contribution=%.4f\n",
                s, strategies[[s]]$weight, strategies[[s]]$q25_share,
                strategies[[s]]$weight * strategies[[s]]$q25_share))
  }
}
cat(sprintf("  Portfolio Q25 exposure: %.2f%%\n", q25_portfolio_exposure * 100))
cat(sprintf("  Threshold: <= 35%%\n"))
pass_q25 <- q25_portfolio_exposure <= 0.35
cat(sprintf("  VERDICT: %.2f%% -> %s\n", q25_portfolio_exposure * 100, ifelse(pass_q25, "PASS", "FAIL")))

#==============================================================================
# 6. SUMMARY + rev4 COMPARISON
#==============================================================================
cat("\n========================================\n")
cat("  REV5 4-AXIS VALIDATION SUMMARY\n")
cat("========================================\n\n")

axis_results <- list(
  cvar_95_annual = list(
    value = round(cvar_95_annual, 4),
    threshold = -0.15,
    pass = pass_cvar,
    note = sprintf("CVaR_95 annual = %.2f%% at rho=0.3 (CF expansion)", cvar_95_annual * 100)
  ),
  cdar_95 = list(
    value = round(cdar_95_est, 4),
    threshold = 0.22,
    pass = pass_cdar,
    note = sprintf("CDaR_95 = %.2f%% (MDD est %.2f%% x ratio 0.75, crisis rho %.2f)",
                   cdar_95_est * 100, port_mdd_est * 100, crisis_rho)
  ),
  tail_dependence_max = list(
    value = round(max_td, 4),
    threshold = 0.40,
    pass = pass_td,
    note = sprintf("Max pairwise TDC = %.4f (%s), nu=%d, crisis_factor=%.0fx",
                   max_td, max_td_pair, nu_est, crisis_factor)
  ),
  q25_weighted_exposure = list(
    value = round(q25_portfolio_exposure, 4),
    threshold = 0.35,
    pass = pass_q25,
    note = sprintf("Portfolio Q25 exposure = %.2f%% (H_1682 w=0.16 q25=60%%, H_1689 w=0.11 q25=25%%, STR_1656 w=0.12 q25=5%%)",
                   q25_portfolio_exposure * 100)
  )
)

pass_count <- sum(sapply(axis_results, `[[`, "pass"))

for(ax_name in names(axis_results)) {
  ax <- axis_results[[ax_name]]
  flag <- ifelse(ax$pass, "PASS", "FAIL")
  cat(sprintf("  [%s] %s: value=%.4f, threshold=%.4f\n", flag, ax_name, ax$value, ax$threshold))
  cat(sprintf("         %s\n", ax$note))
}

overall_pass <- pass_count == 4
cat(sprintf("\n  Overall: %d/4 %s\n", pass_count, ifelse(overall_pass, "PASS", "FAIL")))

# rev4 comparison
cat("\n  rev4 -> rev5 comparison:\n")
cat(sprintf("    CVaR_95:  -26.70%% -> %.2f%% (delta %+.2f pp)\n",
            cvar_95_annual * 100, (cvar_95_annual - (-0.267)) * 100))
cat(sprintf("    CDaR_95:  23.63%% -> %.2f%% (delta %+.2f pp)\n",
            cdar_95_est * 100, (cdar_95_est - 0.2363) * 100))
cat(sprintf("    TDC max:  0.7349 -> %.4f (delta %+.4f)\n",
            max_td, max_td - 0.7349))
cat(sprintf("    Q25:      8.60%% -> %.2f%% (delta %+.2f pp)\n",
            q25_portfolio_exposure * 100, (q25_portfolio_exposure - 0.086) * 100))
cat(sprintf("    Pass:     1/4 -> %d/4\n", pass_count))

# Recommendations
recommendations <- list()

if(!pass_cvar) {
  recommendations <- c(recommendations,
    sprintf("CVaR_95 BREACH (%.2f%% vs -15%% threshold). Core+momentum vol still dominates. Consider further H_1682 increase or H_1688 cut.", cvar_95_annual * 100))
}
if(!pass_cdar) {
  recommendations <- c(recommendations,
    sprintf("CDaR_95 BREACH (%.2f%% vs 22%% threshold). STR_1656 MDD 74.84%% is the structural outlier. Consider reducing STR_1656 or enforcing CDaR cap.", cdar_95_est * 100))
}
if(!pass_td) {
  recommendations <- c(recommendations,
    sprintf("TDC BREACH max=%.4f (%s). %s",
            max_td, max_td_pair,
            ifelse(max_td_pair == "STR_1631 <-> H_1676",
                   paste0("H_1676 spec strengthening (scenario A) reduces this to ", sprintf("%.4f", tdc_A), ". MANDATORY."),
                   "Reduce weight of more volatile strategy in pair.")))
}

# H_1676 scenario A recommendation (always)
recommendations <- c(recommendations,
  sprintf("H_1676 scenario A (residualization strengthened) reduces STR_1631<->H_1676 TDC from %.4f to %.4f. Portfolio max TDC under A: %.4f (%s). %s.",
          tdc_B, tdc_A, max_td_A, max_td_A_pair,
          ifelse(max_td_A <= 0.40, "PASSES threshold", "Still FAILS")))

# L-115/L-106 standing warnings
recommendations <- c(recommendations,
  "L-115 reminder: beta reduction does not equal correlation reduction. Residualization targets cross-sectional correlation but portfolio-level beta dominance persists in crisis.",
  "L-106 reminder: market beta dominates in stress. All 8 strategies share KR equity market exposure. True diversification requires cross-asset, which is out of scope."
)

cat("\n  Recommendations:\n")
for(i in seq_along(recommendations)) {
  cat(sprintf("  [R%d] %s\n", i, recommendations[i]))
}

#==============================================================================
# 7. WRITE OUTPUT JSON
#==============================================================================
cat("\n[OUTPUT] Writing validation JSON...\n")

# Custom paste operator for string concat
`%+%` <- function(a, b) paste0(a, b)

output <- list(
  from = "Risk_Manager",
  to = "Q-Lead",
  type = "PG2_CVAR_VALIDATION",
  stage = "PG2_rev5_4axis_validation",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  session = "current",

  portfolio_composition = lapply(strategies, function(s) {
    list(name = s$name, weight = s$weight, role = s$role, family = s$family)
  }),

  validation_4axis = axis_results,
  pass_count = paste0(pass_count, "/4"),
  overall_verdict = ifelse(overall_pass, "PASS", "FAIL"),

  rev4_comparison = list(
    cvar_95 = list(rev4 = -0.267, rev5 = round(cvar_95_annual, 4)),
    cdar_95 = list(rev4 = 0.2363, rev5 = round(cdar_95_est, 4)),
    tdc_max = list(rev4 = 0.7349, rev5 = round(max_td, 4)),
    q25     = list(rev4 = 0.086, rev5 = round(q25_portfolio_exposure, 4)),
    pass    = list(rev4 = "1/4", rev5 = paste0(pass_count, "/4"))
  ),

  h1676_scenario_ab = list(
    scenario_A = list(
      description = "H_1676 spec strengthened (size+idiovol residualization tightened)",
      base_rho = rho_A_base,
      crisis_rho = rho_A_crisis,
      tdc_vs_str1631 = round(tdc_A, 4),
      portfolio_max_tdc = round(max_td_A, 4),
      max_tdc_pair = max_td_A_pair,
      pass = max_td_A <= 0.40
    ),
    scenario_B = list(
      description = "H_1676 current spec maintained",
      base_rho = rho_B_base,
      crisis_rho = rho_B_crisis,
      tdc_vs_str1631 = round(tdc_B, 4),
      portfolio_max_tdc = round(max_td, 4),
      max_tdc_pair = max_td_pair,
      pass = max_td <= 0.40
    )
  ),

  tail_dependence_detail = list(
    top_5_pairs = lapply(1:min(5, nrow(td_pairs)), function(k) {
      list(pair = td_pairs$pair[k], tdc = round(td_pairs$tdc[k], 4))
    }),
    nu_df = nu_est,
    crisis_rho_multiplier = crisis_factor
  ),

  q25_detail = list(
    H_1682 = list(weight = 0.16, q25_share = 0.60, contribution = round(0.16 * 0.60, 4)),
    H_1689 = list(weight = 0.11, q25_share = 0.25, contribution = round(0.11 * 0.25, 4)),
    STR_1656 = list(weight = 0.12, q25_share = 0.05, contribution = round(0.12 * 0.05, 4)),
    total = round(q25_portfolio_exposure, 4)
  ),

  recommendations = recommendations,

  methodology = list(
    cvar = "Cornish-Fisher CVaR_95 annual, portfolio-level moment approx",
    cdar = "CDaR/MDD ratio 0.75 (specified), MDD via drawdown-space Longin-Solnik crisis correlation",
    tdc = "Bivariate t-copula (nu=4), Longin-Solnik 2x crisis escalation (Demarta-McNeil 2005)",
    q25 = "Linear weighted portfolio Q25 Ohlson O exposure",
    conservative_base = "rho=0.3 (NOT optimistic 0.2)",
    references = c(
      "Pfaff (2016) Ch.6-7",
      "Chekhlov et al. (2005) CDaR",
      "Longin & Solnik (2001)",
      "Demarta & McNeil (2005)",
      "L-115 (beta != correlation)",
      "L-106 (market beta dominates)"
    )
  )
)

out_dir <- file.path(BASE, "qepm/mailbox/risk_manager/outbox")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "pg2_cvar_validation_rev5.json")
jsonlite::write_json(output, out_path, auto_unbox = TRUE, pretty = TRUE)

cat("\n  Output saved to: ", out_path, "\n")
cat("\n=== [RiskMgr] PG2 CVaR Validation rev5 COMPLETE ===\n")
