# ===========================================================================
# QEPM Risk Research Cycle 3 — Robustness 추가 분석
# 1. Joe-Clayton parametric copula TDC fit (사이클 2 axis_4 empirical TDC 보강)
# 2. DCC-GARCH dynamic correlation (사이클 3 axis_3 정적 covariance 보강)
# 3. Bootstrap CI for crisis PASS rate (Codex C4 사이클 2 inheritance)
# ===========================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(copula)
  library(rugarch)
  library(rmgarch)
  library(PerformanceAnalytics)
})

set.seed(20260508)

LOG <- function(msg) cat(sprintf("[%s] %s\n", format(Sys.time(),"%H:%M:%S"), msg))

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- "qepm/mailbox/research/risk_cycle3_20260507"

# Load returns
ret <- fread("qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")
ret[, date := as.Date(date)]
ret[, ym := substr(as.character(date), 1, 7)]

# ============================================================================
# Robustness 1: Joe-Clayton parametric TDC fit
# ============================================================================
LOG("Robustness 1: Joe-Clayton parametric copula TDC fit")

# 6-source post-2010 sample (axis 3 base)
ret5 <- ret[has_tsmom == TRUE & !is.na(r_AR) & !is.na(r_KR10y) & !is.na(r_TSMOM) &
            !is.na(r_commodity) & !is.na(r_defensive) & !is.na(r_vrp)]
LOG(sprintf("  6-source joint sample: n=%d", nrow(ret5)))

src_cols <- c("r_AR", "r_KR10y", "r_TSMOM", "r_defensive", "r_commodity", "r_vrp")
R5 <- as.matrix(ret5[, ..src_cols])

# Convert to pseudo-observations (uniform marginals via empirical CDF)
U <- pobs(R5)
LOG(sprintf("  pobs U dim: %d × %d", nrow(U), ncol(U)))

# Pairwise: Hybrid sources vs candidates
# Pair 1: AR vs VRP — VRP highest negative cor with AR (-0.345)
# Pair 2: AR vs Defensive — Defensive 자체가 AR cross-section 일부 동조 가능
# Pair 3: AR vs Commodity — moderate cor 0.009
# Pair 4: KR_10y vs VRP — bond hedge regime hedging
# Pair 5: TSMOM vs VRP — vol regime hedging

pairs_to_fit <- list(
  AR_VRP = c("r_AR", "r_vrp"),
  AR_DEF = c("r_AR", "r_defensive"),
  AR_COM = c("r_AR", "r_commodity"),
  KR10y_VRP = c("r_KR10y", "r_vrp"),
  TSMOM_VRP = c("r_TSMOM", "r_vrp"),
  DEF_COM = c("r_defensive", "r_commodity"),
  DEF_VRP = c("r_defensive", "r_vrp"),
  COM_VRP = c("r_commodity", "r_vrp")
)

fit_jc_copula <- function(u_pair) {
  # Joe-Clayton (BB7) decomposition: Clayton (lower TDC) + Gumbel (upper TDC) separate fit
  # Lower TDC: Clayton copula (theta > 0), lambda_L = 2^(-1/theta_clayton)
  # Upper TDC: Gumbel copula (delta >= 1), lambda_U = 2 - 2^(1/delta_gumbel)
  fit_clay <- tryCatch(
    fitCopula(claytonCopula(param=1), u_pair, method="mpl"),
    error=function(e) NULL
  )
  fit_gum <- tryCatch(
    fitCopula(gumbelCopula(param=1.5), u_pair, method="mpl"),
    error=function(e) NULL
  )
  theta_c <- if (!is.null(fit_clay)) coef(fit_clay) else NA
  delta_g <- if (!is.null(fit_gum)) coef(fit_gum) else NA
  # Clayton TDC lower
  lam_L <- if (!is.na(theta_c) && theta_c > 0) 2^(-1/theta_c) else 0
  # Gumbel TDC upper
  lam_U <- if (!is.na(delta_g) && delta_g >= 1) 2 - 2^(1/delta_g) else 0
  ll_clay <- if (!is.null(fit_clay)) fit_clay@loglik else NA
  ll_gum <- if (!is.null(fit_gum)) fit_gum@loglik else NA
  list(theta=theta_c, delta=delta_g, lambda_L=lam_L, lambda_U=lam_U,
       ll=if (!is.na(ll_clay) && !is.na(ll_gum)) ll_clay + ll_gum else NA)
}

jc_results <- list()
for (pname in names(pairs_to_fit)) {
  pcols <- pairs_to_fit[[pname]]
  ix <- match(pcols, src_cols)
  u_pair <- U[, ix]
  fr <- fit_jc_copula(u_pair)
  jc_results[[pname]] <- data.table(
    pair = pname,
    src_a = pcols[1], src_b = pcols[2],
    theta_BB7 = if (is.na(fr$theta)) NA else as.numeric(fr$theta),
    delta_BB7 = if (is.na(fr$delta)) NA else as.numeric(fr$delta),
    lambda_L_lower_TDC = if (is.na(fr$lambda_L)) NA else as.numeric(fr$lambda_L),
    lambda_U_upper_TDC = if (is.na(fr$lambda_U)) NA else as.numeric(fr$lambda_U),
    log_likelihood = if (is.na(fr$ll)) NA else as.numeric(fr$ll)
  )
}
jc_dt <- rbindlist(jc_results)
LOG("  Joe-Clayton (BB7) parametric TDC pairwise:")
print(jc_dt)
fwrite(jc_dt, file.path(OUT_DIR, "robust_jc_BB7_pairwise_tdc.csv"))

# ============================================================================
# Robustness 2: DCC-GARCH dynamic correlation (subset 3-source: AR / KR10y / TSMOM)
# ============================================================================
LOG("Robustness 2: DCC-GARCH dynamic correlation")
# 3-source AR / KR10y / TSMOM (post-2015 since TSMOM)
ret3 <- ret[has_tsmom == TRUE & !is.na(r_AR) & !is.na(r_KR10y) & !is.na(r_TSMOM)]
LOG(sprintf("  ret3 (TSMOM joint): n=%d", nrow(ret3)))

R3 <- as.matrix(ret3[, .(r_AR, r_KR10y, r_TSMOM)])

# Univariate GARCH spec for each
uspec <- ugarchspec(
  mean.model=list(armaOrder=c(0,0), include.mean=TRUE),
  variance.model=list(model="sGARCH", garchOrder=c(1,1)),
  distribution.model="std"
)
uspec_multi <- multispec(replicate(3, uspec))

dcc_spec <- dccspec(uspec=uspec_multi, dccOrder=c(1,1), distribution="mvt")

# Fit
dcc_fit <- tryCatch(
  dccfit(dcc_spec, data=R3, fit.control=list(eval.se=FALSE), solver="nlminb"),
  error=function(e) {LOG(sprintf("  DCC fit error: %s", conditionMessage(e))); NULL}
)

if (!is.null(dcc_fit)) {
  # Extract dynamic correlation
  rcor <- rcor(dcc_fit, type="R")  # 3x3xN array
  T_obs <- dim(rcor)[3]
  # Average correlation
  cor_AR_KR <- numeric(T_obs)
  cor_AR_TS <- numeric(T_obs)
  cor_KR_TS <- numeric(T_obs)
  for (t in 1:T_obs) {
    cor_AR_KR[t] <- rcor[1,2,t]
    cor_AR_TS[t] <- rcor[1,3,t]
    cor_KR_TS[t] <- rcor[2,3,t]
  }
  dcc_dt <- data.table(
    t_idx = 1:T_obs,
    date = ret3$date,
    cor_AR_KR_dynamic = cor_AR_KR,
    cor_AR_TS_dynamic = cor_AR_TS,
    cor_KR_TS_dynamic = cor_KR_TS
  )
  fwrite(dcc_dt, file.path(OUT_DIR, "robust_dcc_garch_dynamic_correlation.csv"))

  # Summary stats
  dcc_summary <- list(
    AR_KR_mean = mean(cor_AR_KR), AR_KR_min = min(cor_AR_KR), AR_KR_max = max(cor_AR_KR),
    AR_TS_mean = mean(cor_AR_TS), AR_TS_min = min(cor_AR_TS), AR_TS_max = max(cor_AR_TS),
    KR_TS_mean = mean(cor_KR_TS), KR_TS_min = min(cor_KR_TS), KR_TS_max = max(cor_KR_TS),
    static_AR_KR = cor(R3[,"r_AR"], R3[,"r_KR10y"]),
    static_AR_TS = cor(R3[,"r_AR"], R3[,"r_TSMOM"]),
    static_KR_TS = cor(R3[,"r_KR10y"], R3[,"r_TSMOM"])
  )
  LOG(sprintf("  DCC AR-KR: mean=%.3f range=[%.3f, %.3f] static=%.3f",
              dcc_summary$AR_KR_mean, dcc_summary$AR_KR_min, dcc_summary$AR_KR_max,
              dcc_summary$static_AR_KR))
  LOG(sprintf("  DCC AR-TS: mean=%.3f range=[%.3f, %.3f] static=%.3f",
              dcc_summary$AR_TS_mean, dcc_summary$AR_TS_min, dcc_summary$AR_TS_max,
              dcc_summary$static_AR_TS))
  LOG(sprintf("  DCC KR-TS: mean=%.3f range=[%.3f, %.3f] static=%.3f",
              dcc_summary$KR_TS_mean, dcc_summary$KR_TS_min, dcc_summary$KR_TS_max,
              dcc_summary$static_KR_TS))

  # Crisis subset analysis (BM_Ret bottom 10% months — defined within ret3 sample)
  hybrid_q10 <- quantile(ret3$r_Hybrid, 0.10, na.rm=TRUE)
  crisis_mask <- ret3$r_Hybrid <= hybrid_q10
  if (sum(crisis_mask) >= 5) {
    cor_AR_KR_crisis <- cor_AR_KR[crisis_mask]
    cor_AR_TS_crisis <- cor_AR_TS[crisis_mask]
    cor_KR_TS_crisis <- cor_KR_TS[crisis_mask]
    LOG(sprintf("  CRISIS DCC (n=%d): AR-KR=%.3f AR-TS=%.3f KR-TS=%.3f",
                sum(crisis_mask),
                mean(cor_AR_KR_crisis), mean(cor_AR_TS_crisis), mean(cor_KR_TS_crisis)))
    dcc_summary$crisis_n <- sum(crisis_mask)
    dcc_summary$crisis_AR_KR_mean <- mean(cor_AR_KR_crisis)
    dcc_summary$crisis_AR_TS_mean <- mean(cor_AR_TS_crisis)
    dcc_summary$crisis_KR_TS_mean <- mean(cor_KR_TS_crisis)
  }

  # Save summary
  dcc_summary_dt <- data.table(metric=names(dcc_summary), value=as.numeric(unlist(dcc_summary)))
  fwrite(dcc_summary_dt, file.path(OUT_DIR, "robust_dcc_garch_summary.csv"))
} else {
  LOG("  DCC fit unsuccessful — fallback static correlation only")
  dcc_summary_dt <- data.table(metric="status", value=NA, note="DCC fit failed")
}

# ============================================================================
# Robustness 3: Bootstrap CI for crisis PASS rate (사이클 2 C4 inheritance)
# ============================================================================
LOG("Robustness 3: Bootstrap CI for crisis PASS rate")

# 사이클 2 axis 3 stress 결과: VRP 4/6 PASS, Defensive 2/6, Commodity 2/5, Currency 1/6
# Cycle 3 보강: bootstrap CI under alternative crisis sample definition
# 본 분석: Hybrid bottom 10% months → candidate beat Hybrid count + boostrap

ret_full <- ret[!is.na(r_Hybrid) & !is.na(r_defensive) & !is.na(r_vrp) & !is.na(r_currency)]
ret_post2010 <- ret[!is.na(r_Hybrid) & !is.na(r_commodity) & !is.na(r_defensive) & !is.na(r_vrp)]

bootstrap_crisis_pass <- function(rh, rc, n_boot=1000, q=0.10) {
  set.seed(20260508)
  pass_rates <- numeric(n_boot)
  n <- length(rh)
  for (b in 1:n_boot) {
    idx <- sample(1:n, n, replace=TRUE)
    rh_b <- rh[idx]; rc_b <- rc[idx]
    crisis_mask <- rh_b <= quantile(rh_b, q)
    pass <- sum(rc_b[crisis_mask] > rh_b[crisis_mask])
    pass_rates[b] <- pass / max(sum(crisis_mask), 1)
  }
  list(
    mean = mean(pass_rates),
    median = median(pass_rates),
    ci_lo = quantile(pass_rates, 0.025),
    ci_hi = quantile(pass_rates, 0.975),
    sd = sd(pass_rates)
  )
}

cands_full <- list(defensive="r_defensive", vrp="r_vrp", currency="r_currency")
cands_post2010 <- list(commodity="r_commodity", defensive="r_defensive", vrp="r_vrp")

boot_results <- list()
for (cn in names(cands_full)) {
  ccol <- cands_full[[cn]]
  br <- bootstrap_crisis_pass(ret_full$r_Hybrid, ret_full[[ccol]], n_boot=1000, q=0.10)
  boot_results[[paste0("full_", cn)]] <- data.table(
    sample="256m_full", candidate=cn,
    crisis_pass_mean=br$mean, crisis_pass_median=br$median,
    ci_2_5pct=br$ci_lo, ci_97_5pct=br$ci_hi, ci_width=br$ci_hi-br$ci_lo,
    sd=br$sd
  )
}
for (cn in names(cands_post2010)) {
  ccol <- cands_post2010[[cn]]
  br <- bootstrap_crisis_pass(ret_post2010$r_Hybrid, ret_post2010[[ccol]], n_boot=1000, q=0.10)
  boot_results[[paste0("post2010_", cn)]] <- data.table(
    sample="192m_post2010", candidate=cn,
    crisis_pass_mean=br$mean, crisis_pass_median=br$median,
    ci_2_5pct=br$ci_lo, ci_97_5pct=br$ci_hi, ci_width=br$ci_hi-br$ci_lo,
    sd=br$sd
  )
}
boot_dt <- rbindlist(boot_results)
LOG("  Bootstrap crisis PASS rate (1000 trials, q10):")
print(boot_dt)
fwrite(boot_dt, file.path(OUT_DIR, "robust_bootstrap_crisis_pass_ci.csv"))

# ============================================================================
# Save robustness summary
# ============================================================================
LOG("Saving robustness summary")
robustness <- list(
  robustness_1_jc_BB7_TDC = jc_dt,
  robustness_2_dcc_garch_summary = if (exists("dcc_summary")) dcc_summary else NA,
  robustness_3_bootstrap_crisis_pass = boot_dt
)
write_json(robustness, file.path(OUT_DIR, "robustness_results.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null", null="null")

LOG("Robustness analysis complete.")
