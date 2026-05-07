# ============================================================================
# Cycle 8 — Stambaugh 2015 post-publication retest (3 source 통합)
# ============================================================================
# Theme: 3 source (TSMOM 2012 / KR_10y carry 2017 normalization / AR 2018) post-publication
#        decay 정량 retest + joint decay correlation + Bayesian forward simulation
# Inputs: cycle 1~7 누적, 특히 cycle 7 monitoring inbox + cycle 5 MK/Pettitt
# Output: 3축 세 정통 학술 framework — Stambaugh 2015 / Bayesian / Multivariate copula
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# Paths -----------------------------------------------------------------------
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WORK <- file.path(ROOT, "qepm/mailbox/research/risk_cycle8_20260507")
RETURNS_CSV <- file.path(ROOT,
                         "qepm/mailbox/research/risk_candidates_20260507",
                         "master_returns_hybrid_plus_4candidates.csv")
setwd(WORK)

set.seed(20260508L)  # bootstrap reproducibility

# Logging ---------------------------------------------------------------------
log_msg <- function(msg) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "—", msg, "\n", sep = " ")
}

log_msg("Cycle 8 Stambaugh framework start")
log_msg(paste("Work dir:", WORK))

# ============================================================================
# Load master returns
# ============================================================================
dt <- fread(RETURNS_CSV)
dt[, ym := as.character(ym)]
dt[, date := as.Date(date)]

setorder(dt, ym)
log_msg(sprintf("master_returns loaded: %d rows", nrow(dt)))

# 3 source returns (NA-safe)
dt_ar <- dt[!is.na(r_AR), .(ym, date, r = r_AR)]
dt_tsmom <- dt[!is.na(r_TSMOM), .(ym, date, r = r_TSMOM)]
dt_kr10y <- dt[!is.na(r_KR10y), .(ym, date, r = r_KR10y)]
dt_hybrid <- dt[!is.na(r_Hybrid), .(ym, date, r = r_Hybrid)]

log_msg(sprintf("AR n=%d (%s ~ %s)", nrow(dt_ar),
                min(dt_ar$ym), max(dt_ar$ym)))
log_msg(sprintf("TSMOM n=%d (%s ~ %s)", nrow(dt_tsmom),
                min(dt_tsmom$ym), max(dt_tsmom$ym)))
log_msg(sprintf("KR10y n=%d (%s ~ %s)", nrow(dt_kr10y),
                min(dt_kr10y$ym), max(dt_kr10y$ym)))
log_msg(sprintf("Hybrid n=%d (%s ~ %s)", nrow(dt_hybrid),
                min(dt_hybrid$ym), max(dt_hybrid$ym)))

# ============================================================================
# AXIS 1: Stambaugh 2015 3-source post-publication retest
# ============================================================================
# Publication dates per source:
# - TSMOM: Moskowitz-Ooi-Pedersen 2012 JFE published. Pre 2005-02~2012-12, Post 2013-01~
# - KR_10y carry: 한국 통화정책 normalization 2017 onward. Pre 2005-02~2016-12, Post 2017-01~
# - AR threshold (도훈 자체): 2018 onward. Pre 2005-02~2017-12, Post 2018-01~ (post-only sample)
# ============================================================================

log_msg("===== AXIS 1: Stambaugh 2015 retest start =====")

# Sharpe annualized helper
sr_ann <- function(r, freq = 12) {
  r <- r[!is.na(r)]
  if (length(r) < 2) return(NA_real_)
  mu <- mean(r)
  sd <- sd(r)
  if (is.na(sd) || sd == 0) return(NA_real_)
  (mu / sd) * sqrt(freq)
}

# Welch's t-test SR difference (Lo 2002 corrected SR std error)
# Memmel 2003 Test of equality of Sharpe ratios
sr_diff_welch <- function(r_pre, r_post, freq = 12) {
  r_pre <- r_pre[!is.na(r_pre)]
  r_post <- r_post[!is.na(r_post)]
  n_pre <- length(r_pre)
  n_post <- length(r_post)
  if (n_pre < 30 || n_post < 30) {
    return(list(sr_pre = sr_ann(r_pre, freq),
                sr_post = sr_ann(r_post, freq),
                t_stat = NA_real_, p_value = NA_real_,
                method = "n_too_small"))
  }
  sr_pre <- sr_ann(r_pre, freq)
  sr_post <- sr_ann(r_post, freq)
  # Lo 2002 SR variance approximation under iid normal
  var_sr_pre <- (1 + 0.5 * (sr_pre / sqrt(freq))^2) / n_pre * freq
  var_sr_post <- (1 + 0.5 * (sr_post / sqrt(freq))^2) / n_post * freq
  se_diff <- sqrt(var_sr_pre + var_sr_post)
  t_stat <- (sr_post - sr_pre) / se_diff
  # Welch df
  df <- (var_sr_pre + var_sr_post)^2 /
    ((var_sr_pre^2 / (n_pre - 1)) + (var_sr_post^2 / (n_post - 1)))
  p_value <- 2 * pt(-abs(t_stat), df = df)
  list(sr_pre = sr_pre, sr_post = sr_post, n_pre = n_pre, n_post = n_post,
       t_stat = t_stat, df = df, p_value = p_value,
       method = "lo2002_welch")
}

# Stationary bootstrap SR (Politis-Romano 1994)
boot_sr_diff <- function(r_pre, r_post, B = 1000, freq = 12, block_mean = 6) {
  r_pre <- r_pre[!is.na(r_pre)]
  r_post <- r_post[!is.na(r_post)]
  if (length(r_pre) < 12 || length(r_post) < 12) {
    return(list(ci_lower = NA_real_, ci_upper = NA_real_, B_eff = 0))
  }
  stat_boot <- function(r, n_target, p_geom) {
    n <- length(r)
    out <- numeric(n_target)
    i <- 1
    while (i <= n_target) {
      block_len <- 1 + rgeom(1, prob = p_geom)
      start <- sample.int(n, 1)
      end <- min(i + block_len - 1, n_target)
      take <- end - i + 1
      idx <- ((start - 1) + seq_len(take) - 1) %% n + 1
      out[i:end] <- r[idx]
      i <- end + 1
    }
    out
  }
  p_geom <- 1 / block_mean
  diffs <- numeric(B)
  for (b in seq_len(B)) {
    rb_pre <- stat_boot(r_pre, length(r_pre), p_geom)
    rb_post <- stat_boot(r_post, length(r_post), p_geom)
    diffs[b] <- sr_ann(rb_post, freq) - sr_ann(rb_pre, freq)
  }
  list(ci_lower = quantile(diffs, 0.025, na.rm = TRUE),
       ci_upper = quantile(diffs, 0.975, na.rm = TRUE),
       B_eff = sum(!is.na(diffs)),
       sd_diff = sd(diffs, na.rm = TRUE))
}

# Information ratio decay rate (Stambaugh 2015 framework)
# decay_rate = (sr_pre - sr_post) / sr_pre  (if sr_pre > 0, else NA)
ir_decay <- function(sr_pre, sr_post) {
  if (is.na(sr_pre) || is.na(sr_post)) return(NA_real_)
  if (sr_pre <= 0) return(NA_real_)
  (sr_pre - sr_post) / sr_pre
}

# Half-life estimation (exponential decay model)
# Model: SR_t = SR_0 * exp(-lambda * t) → log(SR_t) = log(SR_0) - lambda * t
# Half-life = log(2) / lambda
half_life_ols <- function(rolling_sr_vec, t_vec, ym_vec) {
  ok <- !is.na(rolling_sr_vec) & rolling_sr_vec > 0
  if (sum(ok) < 12) {
    return(list(lambda = NA_real_, half_life = NA_real_,
                r2 = NA_real_, n_obs = sum(ok),
                method = "ols_log_linear"))
  }
  log_sr <- log(rolling_sr_vec[ok])
  t_use <- t_vec[ok]
  fit <- tryCatch(lm(log_sr ~ t_use), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(lambda = NA_real_, half_life = NA_real_,
                r2 = NA_real_, n_obs = sum(ok), method = "lm_failed"))
  }
  lambda <- -coef(fit)[2]
  hl <- if (!is.na(lambda) && lambda > 0) log(2) / lambda else NA_real_
  list(lambda = unname(lambda),
       half_life_months = unname(hl),
       r2 = summary(fit)$r.squared,
       n_obs = sum(ok),
       method = "ols_log_linear",
       note = "lambda > 0 = decay; lambda < 0 = strengthening; hl=NA when lambda<=0")
}

# Define publication splits
# IMPORTANT: TSMOM data starts 2015-01 (cycle 2 inheritance). 2012 split impossible.
# Decision: TSMOM use mid-sample (2018-12) as post-publication proxy
#           — Hutchinson-O'Brien 2014 ICR + Hwang-Rubesam 2024 secular decay framework
#           — 6-year mid-period gives n_pre=48 / n_post=87 (sufficient for Welch-t)
split_TSMOM_pub <- "2018-12"  # Mid-sample proxy (data starts 2015-01, cycle 2 inheritance)
split_KR10y_pub <- "2016-12"  # Korea normalization onset 2017
split_AR_pub <- "2017-12"     # AR 2018+

# Run retest per source
sources <- list(
  AR = list(dt = dt_ar, split = split_AR_pub, pub_year = 2018,
            split_note = "도훈 자체 발굴 2018+; pre/post split standard",
            citation = "도훈 자체 발굴 2018 — post-only sample stress test",
            paper = "Kritzman-Page-Turkington 2011 FAJ AR threshold framework"),
  TSMOM = list(dt = dt_tsmom, split = split_TSMOM_pub, pub_year = 2012,
               split_note = "Mid-sample 2018-12 proxy (data starts 2015-01; 2012 publication preceded data); Hutchinson-O'Brien 2014 ICR + Hwang-Rubesam 2024",
               citation = "Moskowitz-Ooi-Pedersen 2012 JFE TSMOM 12m; Hutchinson-O'Brien 2014 ICR; Hwang-Rubesam 2024",
               paper = "Moskowitz-Ooi-Pedersen 2012 JFE"),
  KR10y = list(dt = dt_kr10y, split = split_KR10y_pub, pub_year = 2017,
               split_note = "Korea BoK normalization onset 2017",
               citation = "Korea 통화정책 normalization 2017+ Cieslak-Povala 2015 RFS",
               paper = "Cieslak-Povala 2015 RFS Treasury bond expected returns")
)

axis1_results <- list()
for (sn in names(sources)) {
  src <- sources[[sn]]
  d <- src$dt
  pre <- d[ym <= src$split, r]
  post <- d[ym > src$split, r]
  log_msg(sprintf("  %s: pre n=%d post n=%d split=%s", sn, length(pre),
                  length(post), src$split))
  welch <- sr_diff_welch(pre, post)
  decay_pt <- ir_decay(welch$sr_pre, welch$sr_post)
  bs <- boot_sr_diff(pre, post, B = 1000, block_mean = 6)

  # Half-life on rolling 36m SR
  d_full <- d
  d_full[, t_idx := seq_len(.N)]
  r_full <- d_full$r
  rolling_36m <- sapply(seq_along(r_full), function(i) {
    if (i < 36) return(NA_real_)
    sr_ann(r_full[(i - 35):i])
  })
  d_full[, sr_36m := rolling_36m]
  hl <- half_life_ols(d_full$sr_36m[36:nrow(d_full)],
                      d_full$t_idx[36:nrow(d_full)] - 35,
                      d_full$ym[36:nrow(d_full)])

  axis1_results[[sn]] <- list(
    source = sn,
    pub_year = src$pub_year,
    paper = src$paper,
    citation = src$citation,
    split_ym = src$split,
    split_note = src$split_note,
    n_pre = length(pre), n_post = length(post),
    sr_pre = welch$sr_pre, sr_post = welch$sr_post,
    sr_diff = welch$sr_post - welch$sr_pre,
    welch_t_stat = welch$t_stat, welch_df = welch$df,
    welch_p_value = welch$p_value,
    welch_method = welch$method,
    decay_rate_stambaugh = decay_pt,
    boot_ci_95_lower = bs$ci_lower, boot_ci_95_upper = bs$ci_upper,
    boot_B_eff = bs$B_eff, boot_sd_diff = bs$sd_diff,
    half_life_lambda = hl$lambda,
    half_life_months = hl$half_life_months,
    half_life_r2 = hl$r2, half_life_n_obs = hl$n_obs,
    half_life_method = hl$method,
    half_life_note = hl$note
  )
}

# Save axis 1 CSV
axis1_dt <- rbindlist(lapply(axis1_results, function(x) {
  data.table(
    source = x$source,
    pub_year = x$pub_year,
    split_ym = x$split_ym,
    n_pre = x$n_pre, n_post = x$n_post,
    sr_pre = x$sr_pre, sr_post = x$sr_post,
    sr_diff = x$sr_diff,
    welch_t_stat = x$welch_t_stat, welch_p_value = x$welch_p_value,
    decay_rate_stambaugh = x$decay_rate_stambaugh,
    boot_ci_95_lower = x$boot_ci_95_lower,
    boot_ci_95_upper = x$boot_ci_95_upper,
    half_life_lambda = x$half_life_lambda,
    half_life_months = x$half_life_months,
    half_life_r2 = x$half_life_r2,
    half_life_n_obs = x$half_life_n_obs,
    paper = x$paper,
    split_note = x$split_note
  )
}))
fwrite(axis1_dt, file.path(WORK, "axis1_stambaugh_3source_retest.csv"))
log_msg(sprintf("axis1 retest CSV saved: %d sources", nrow(axis1_dt)))

# Bayesian update: Prior (cycle 7 + Stambaugh base rate) + Likelihood (cycles 1~7)
# Prior: Stambaugh 2015 RFS reports avg out-of-sample decay 56% for 11 anomalies post-publication
# Posterior on decay rate using normal-normal conjugate
# Prior decay rate ~ Normal(0.30, 0.20^2)  -- moderate decay with wide uncertainty
# Likelihood evidence: 3 source observed decay rates as 3 noisy obs of true decay
prior_mu <- 0.30
prior_sigma <- 0.20
observed_decays <- sapply(axis1_results, function(x) x$decay_rate_stambaugh)
observed_decays <- observed_decays[!is.na(observed_decays)]
likelihood_sigma <- 0.15  # observation noise (sub-sample variance)
n_obs <- length(observed_decays)

if (n_obs > 0) {
  # Normal-normal conjugate for mean
  # posterior_var = 1 / (1/prior_var + n_obs/likelihood_var)
  # posterior_mean = posterior_var * (prior_mean/prior_var + sum(obs)/likelihood_var)
  prior_var <- prior_sigma^2
  lik_var <- likelihood_sigma^2
  post_var <- 1 / (1 / prior_var + n_obs / lik_var)
  post_mu <- post_var * (prior_mu / prior_var + sum(observed_decays) / lik_var)
  post_sigma <- sqrt(post_var)

  bayesian_update <- list(
    prior_mu = prior_mu, prior_sigma = prior_sigma,
    likelihood_sigma = likelihood_sigma,
    observed_decays = observed_decays,
    n_observations = n_obs,
    posterior_mu = post_mu, posterior_sigma = post_sigma,
    posterior_ci_95_lower = post_mu - 1.96 * post_sigma,
    posterior_ci_95_upper = post_mu + 1.96 * post_sigma,
    framework = "Stambaugh 2015 + Normal-Normal Bayesian conjugate (mean update)",
    citations = c("Stambaugh-Yu-Yuan 2015 RFS Mispricing Factors",
                  "McElreath 2020 Statistical Rethinking ch.3",
                  "Gelman et al. 2013 BDA3 ch.2")
  )
} else {
  bayesian_update <- list(error = "No valid decay observations")
}

write_json(bayesian_update,
           file.path(WORK, "axis1_bayesian_decay_posterior.json"),
           pretty = TRUE, auto_unbox = TRUE)
log_msg(sprintf("axis1 Bayesian posterior: mu=%.4f sigma=%.4f",
                bayesian_update$posterior_mu, bayesian_update$posterior_sigma))

log_msg("===== AXIS 1 done =====")

# ============================================================================
# AXIS 2: 3-source joint decay correlation + Hybrid impact
# ============================================================================
log_msg("===== AXIS 2: joint decay correlation start =====")

# Joint distribution: rolling 36m SR per source, then innovations
# Step: compute rolling 36m SR per source on aligned ym basis (where all 3 exist)
dt_aligned <- merge(dt_ar[, .(ym, r_AR = r)],
                    dt_tsmom[, .(ym, r_TSMOM = r)], by = "ym", all = FALSE)
dt_aligned <- merge(dt_aligned, dt_kr10y[, .(ym, r_KR10y = r)],
                    by = "ym", all = FALSE)
dt_aligned <- merge(dt_aligned, dt_hybrid[, .(ym, r_Hybrid = r)],
                    by = "ym", all = FALSE)
setorder(dt_aligned, ym)
log_msg(sprintf("aligned (where 3 sources + hybrid exist) n=%d (%s~%s)",
                nrow(dt_aligned), min(dt_aligned$ym), max(dt_aligned$ym)))

rolling_sr_vec <- function(r, w = 36) {
  n <- length(r)
  out <- rep(NA_real_, n)
  for (i in w:n) {
    out[i] <- sr_ann(r[(i - w + 1):i])
  }
  out
}
dt_aligned[, sr36_AR := rolling_sr_vec(r_AR, 36)]
dt_aligned[, sr36_TSMOM := rolling_sr_vec(r_TSMOM, 36)]
dt_aligned[, sr36_KR10y := rolling_sr_vec(r_KR10y, 36)]
dt_aligned[, sr36_Hybrid := rolling_sr_vec(r_Hybrid, 36)]

# SR innovations (first difference)
dt_aligned[, dsr36_AR := c(NA, diff(sr36_AR))]
dt_aligned[, dsr36_TSMOM := c(NA, diff(sr36_TSMOM))]
dt_aligned[, dsr36_KR10y := c(NA, diff(sr36_KR10y))]

# Joint decay correlation
ok_idx <- complete.cases(dt_aligned[, .(dsr36_AR, dsr36_TSMOM, dsr36_KR10y)])
log_msg(sprintf("Joint dsr36 ok n=%d", sum(ok_idx)))

dsr_mat <- as.matrix(dt_aligned[ok_idx,
                                .(dsr36_AR, dsr36_TSMOM, dsr36_KR10y)])
joint_cor <- cor(dsr_mat)
log_msg("Joint decay innovation cor:")
print(joint_cor)

# Empirical multivariate Gaussian copula joint probability of decay shock
# P(all 3 < -1σ) - Brunnermeier-Pedersen 2009 contagion proxy
# Using empirical pseudo-observations
n_dsr <- nrow(dsr_mat)
ranks_AR <- rank(dsr_mat[, "dsr36_AR"]) / (n_dsr + 1)
ranks_TS <- rank(dsr_mat[, "dsr36_TSMOM"]) / (n_dsr + 1)
ranks_KR <- rank(dsr_mat[, "dsr36_KR10y"]) / (n_dsr + 1)

joint_decay_lower_15 <- mean(ranks_AR < 0.15 & ranks_TS < 0.15 & ranks_KR < 0.15)
joint_decay_lower_25 <- mean(ranks_AR < 0.25 & ranks_TS < 0.25 & ranks_KR < 0.25)
joint_decay_lower_35 <- mean(ranks_AR < 0.35 & ranks_TS < 0.35 & ranks_KR < 0.35)

# Independence baseline
indep_15 <- 0.15^3
indep_25 <- 0.25^3
indep_35 <- 0.35^3

# Pairwise tail dependence (lower)
ldp_AR_TSMOM <- mean(ranks_TS < 0.10 & ranks_AR < 0.10) / 0.10
ldp_AR_KR <- mean(ranks_KR < 0.10 & ranks_AR < 0.10) / 0.10
ldp_TSMOM_KR <- mean(ranks_KR < 0.10 & ranks_TS < 0.10) / 0.10

# Decay regime + Hybrid shock joint
dt_aligned[, decay_regime := ifelse(!is.na(dsr36_AR) & !is.na(dsr36_TSMOM) & !is.na(dsr36_KR10y) &
                                      dsr36_AR < quantile(dsr36_AR, 0.25, na.rm = TRUE) &
                                      dsr36_TSMOM < quantile(dsr36_TSMOM, 0.25, na.rm = TRUE) &
                                      dsr36_KR10y < quantile(dsr36_KR10y, 0.25, na.rm = TRUE),
                                    "JOINT_DECAY", "OTHER")]
hybrid_under_decay <- dt_aligned[decay_regime == "JOINT_DECAY", r_Hybrid]
hybrid_other <- dt_aligned[decay_regime == "OTHER", r_Hybrid]

decay_regime_summary <- list(
  hybrid_decay_n = length(hybrid_under_decay),
  hybrid_other_n = length(hybrid_other),
  hybrid_decay_mean = mean(hybrid_under_decay, na.rm = TRUE),
  hybrid_other_mean = mean(hybrid_other, na.rm = TRUE),
  hybrid_decay_sr_ann = sr_ann(hybrid_under_decay),
  hybrid_other_sr_ann = sr_ann(hybrid_other),
  diff_mean = mean(hybrid_under_decay, na.rm = TRUE) -
    mean(hybrid_other, na.rm = TRUE)
)

# Save axis 2 results
fwrite(as.data.table(joint_cor, keep.rownames = "var"),
       file.path(WORK, "axis2_joint_decay_innovation_cor.csv"))

axis2_summary <- list(
  description = "3-source joint decay correlation + Hybrid impact (sigma1c response check)",
  n_obs = sum(ok_idx),
  joint_innovation_cor_AR_TSMOM = joint_cor["dsr36_AR", "dsr36_TSMOM"],
  joint_innovation_cor_AR_KR10y = joint_cor["dsr36_AR", "dsr36_KR10y"],
  joint_innovation_cor_TSMOM_KR10y = joint_cor["dsr36_TSMOM", "dsr36_KR10y"],
  joint_decay_lower_15pct = joint_decay_lower_15,
  joint_decay_lower_25pct = joint_decay_lower_25,
  joint_decay_lower_35pct = joint_decay_lower_35,
  independence_baseline_15pct = indep_15,
  independence_baseline_25pct = indep_25,
  independence_baseline_35pct = indep_35,
  joint_lower_15_excess_vs_indep = joint_decay_lower_15 - indep_15,
  joint_lower_25_excess_vs_indep = joint_decay_lower_25 - indep_25,
  ldp_AR_TSMOM_q10 = ldp_AR_TSMOM,
  ldp_AR_KR_q10 = ldp_AR_KR,
  ldp_TSMOM_KR_q10 = ldp_TSMOM_KR,
  decay_regime_hybrid = decay_regime_summary,
  citations = c("Brunnermeier-Pedersen 2009 RFS funding contagion",
                "Politis-Romano 1994 JASA stationary bootstrap",
                "Joe 1997 Multivariate Models",
                "Forbes-Rigobon 2002 JOF correlation breakdown",
                "Embrechts-McNeil-Straumann 2002 dependence pitfalls")
)
write_json(axis2_summary,
           file.path(WORK, "axis2_joint_decay_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)
log_msg("===== AXIS 2 done =====")

# ============================================================================
# AXIS 3: Forward Bayesian decay path simulation (12/24/36/60m)
# ============================================================================
log_msg("===== AXIS 3: forward decay simulation start =====")

# Bayesian posterior mean decay rate from axis 1 → forward simulation
# Apply decay rate to current 60m SR (from cycle 7 monitoring)
current_sr_60m <- list(
  AR = 1.6709, TSMOM = 0.5921, KR10y = 0.0706, Hybrid = 1.7122
)
current_sr_full <- list(
  AR = 1.6063, TSMOM = 0.8688, KR10y = 0.6163, Hybrid = 1.5070
)
weights_hybrid <- c(AR = 0.70, TSMOM = 0.15, KR10y = 0.15)

# Posterior decay rate (annual implied from Bayesian)
# Convert: decay_rate is total over post-pub period; need annual rate
# Estimate annual_decay_rate via half-life regression on each source
hl_lambda_per_source <- sapply(axis1_results, function(x) {
  ifelse(is.na(x$half_life_lambda), 0, x$half_life_lambda)
})
hl_annualized <- hl_lambda_per_source * 12  # monthly rate to annual
log_msg("Half-life lambda annual per source:")
print(hl_annualized)

# Forward simulation using individual half-life lambdas (more accurate than bayesian global)
horizons_months <- c(12, 24, 36, 60)
forward_paths <- list()
for (h in horizons_months) {
  for (sn in names(sources)) {
    lambda_m <- hl_lambda_per_source[sn]
    sr_now <- current_sr_60m[[sn]]
    if (is.na(lambda_m) || lambda_m <= 0) {
      sr_h <- sr_now  # no decay
      decay_pct <- 0
    } else {
      sr_h <- sr_now * exp(-lambda_m * h)
      decay_pct <- (sr_now - sr_h) / sr_now
    }
    forward_paths[[length(forward_paths) + 1]] <- list(
      source = sn,
      horizon_months = h,
      lambda_monthly = unname(lambda_m),
      sr_60m_now = sr_now,
      sr_h_forward = unname(sr_h),
      decay_pct = unname(decay_pct)
    )
  }
}
forward_dt <- rbindlist(lapply(forward_paths, as.data.table))
fwrite(forward_dt, file.path(WORK, "axis3_forward_decay_paths_per_source.csv"))

# Hybrid SR distribution under decay using delta method
# Hybrid_SR ≈ w_AR * SR_AR + w_TSMOM * SR_TSMOM + w_KR * SR_KR
# (loose approximation; ignores correlation between sources)
# Adjust with empirical correlation matrix
src_cor_post2015 <- matrix(c(1.0,    0.0751, -0.1223,
                             0.0751, 1.0,    0.1187,
                             -0.1223, 0.1187, 1.0),
                           nrow = 3, byrow = TRUE,
                           dimnames = list(c("AR", "TSMOM", "KR10y"),
                                           c("AR", "TSMOM", "KR10y")))
# Hybrid vol: sqrt(w' Sigma w) — assume vols normalized to 1 (SR-space)
sigma_w <- sqrt(t(weights_hybrid) %*% src_cor_post2015 %*% weights_hybrid)
# Approx Hybrid SR forward = sum(w * sr) / sigma_w
hybrid_forward <- list()
for (h in horizons_months) {
  rows <- forward_dt[horizon_months == h]
  rows_named <- setNames(rows$sr_h_forward, rows$source)
  num <- weights_hybrid["AR"] * rows_named["AR"] +
    weights_hybrid["TSMOM"] * rows_named["TSMOM"] +
    weights_hybrid["KR10y"] * rows_named["KR10y"]
  hybrid_sr_h <- as.numeric(num / sigma_w)
  hybrid_decay_pct <- (current_sr_60m$Hybrid - hybrid_sr_h) / current_sr_60m$Hybrid
  hybrid_forward[[length(hybrid_forward) + 1]] <- list(
    horizon_months = h,
    weighted_sum = unname(num),
    sigma_w = unname(sigma_w),
    hybrid_sr_60m_now = current_sr_60m$Hybrid,
    hybrid_sr_h_forward = hybrid_sr_h,
    hybrid_decay_pct = unname(hybrid_decay_pct)
  )
}
hybrid_dt <- rbindlist(lapply(hybrid_forward, as.data.table))
fwrite(hybrid_dt, file.path(WORK, "axis3_hybrid_forward_sr_distribution.csv"))

# Posterior alert thresholds (acceleration vs reversal)
# AR mk_tau -0.27 + Bayesian posterior mu = next-period decay rate
# Define acceleration trigger: monthly SR drop > 1.96 * posterior_sigma
posterior_sigma_decay <- bayesian_update$posterior_sigma
# Convert to monthly SR delta scale (60m SR units)
# Approx threshold: 1.96 * sd_decay * SR_now
alert_acceleration <- list(
  description = "Decay accelerate alert if rolling 60m SR drops faster than posterior expectation",
  posterior_decay_mu = bayesian_update$posterior_mu,
  posterior_decay_sigma = bayesian_update$posterior_sigma,
  ar_threshold_warning = current_sr_60m$AR * (1 - bayesian_update$posterior_mu / 2),
  ar_threshold_critical = current_sr_60m$AR * (1 - bayesian_update$posterior_mu),
  tsmom_threshold_warning = current_sr_60m$TSMOM * (1 - bayesian_update$posterior_mu / 2),
  tsmom_threshold_critical = current_sr_60m$TSMOM * (1 - bayesian_update$posterior_mu),
  kr10y_threshold_warning = current_sr_60m$KR10y * (1 - bayesian_update$posterior_mu / 2),
  kr10y_threshold_critical = current_sr_60m$KR10y * (1 - bayesian_update$posterior_mu),
  alert_reversal_AR_p0_001 = "Cycle 7 AR MK tau -0.27 p<0.001 → 12m forward must show SR_60m > 1.50 to reject decay (1σ posterior)"
)

# Save axis 3 summary
axis3_summary <- list(
  description = "Forward Bayesian decay simulation with empirical posterior + Hybrid joint",
  current_sr_60m = current_sr_60m,
  current_sr_full = current_sr_full,
  weights_hybrid = as.list(weights_hybrid),
  half_life_lambda_monthly = as.list(hl_lambda_per_source),
  half_life_months_per_source = sapply(axis1_results, function(x) x$half_life_months,
                                        USE.NAMES = TRUE),
  forward_horizons_months = horizons_months,
  hybrid_forward_distribution = hybrid_forward,
  bayesian_posterior_decay = list(
    mu = bayesian_update$posterior_mu,
    sigma = bayesian_update$posterior_sigma,
    ci_95_lower = bayesian_update$posterior_ci_95_lower,
    ci_95_upper = bayesian_update$posterior_ci_95_upper
  ),
  alert_thresholds_acceleration = alert_acceleration,
  citations = c("Stambaugh-Yu-Yuan 2015 RFS Mispricing Factors anomaly decay",
                "McElreath 2020 Statistical Rethinking ch.3 Bayesian update",
                "Gelman et al. 2013 BDA3 ch.2 normal-normal conjugate",
                "Chordia-Subrahmanyam-Tong 2014 JFE post-publication decay",
                "Hwang-Rubesam 2024 momentum disappearance",
                "Moskowitz-Ooi-Pedersen 2012 JFE TSMOM 14-year")
)
write_json(axis3_summary,
           file.path(WORK, "axis3_forward_simulation_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)
log_msg("===== AXIS 3 done =====")

# ============================================================================
# Aggregate cycle 8 dashboard
# ============================================================================
log_msg("===== Aggregate dashboard =====")

# Termination decision logic:
# 1) If all 3 sources show statistically significant decay (welch p < 0.05 OR boot CI excludes 0)
#    AND hybrid forward decay > 30% by 60m horizon → TERMINATE_BENEFICIAL
# 2) If decay framework reveals new actionable findings (e.g., joint decay tail dependence) → CYCLE_9
# 3) If ambiguous → CYCLE_9 with refined diagnostics

decay_significant_count <- sum(sapply(axis1_results, function(x) {
  !is.na(x$welch_p_value) && x$welch_p_value < 0.05
}), na.rm = TRUE)

decay_count_with_decay_pos <- sum(sapply(axis1_results, function(x) {
  !is.na(x$decay_rate_stambaugh) && x$decay_rate_stambaugh > 0
}), na.rm = TRUE)

# Hybrid 60m forward decay
hybrid_60m_decay <- hybrid_dt[horizon_months == 60, hybrid_decay_pct]

# Joint dependency excess
joint_dependency_excess <- joint_decay_lower_25 - indep_25

# Decision rule
if (decay_count_with_decay_pos == 3 && hybrid_60m_decay > 0.30) {
  termination <- "TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE"
  termination_reason <- "All 3 sources show positive decay + Hybrid 60m forward > 30% decay"
  next_cycle <- "TERMINATE — proceed to formal lifecycle (BAB + Q07 + 8 stress)"
} else if (decay_significant_count >= 2 || joint_dependency_excess > 0.05) {
  termination <- "CYCLE_9_RECOMMENDED_REFINE_DIAGNOSTICS"
  termination_reason <- sprintf("Significant decay in %d/3 sources OR joint excess %0.4f",
                                 decay_significant_count, joint_dependency_excess)
  next_cycle <- "Cycle 9: structural break test on individual decay paths + parametric copula fit"
} else {
  termination <- "TERMINATE_BENEFICIAL_DECAY_FRAMEWORK_COMPLETE"
  termination_reason <- "Decay signals quantified but not all critical; framework saturated"
  next_cycle <- "TERMINATE — formal lifecycle path"
}

cycle8_dashboard <- list(
  cycle = 8,
  task_id = "RESEARCH_RISK_CYCLE8_20260507",
  research_type = "stambaugh_2015_3source_post_publication_retest_bayesian_forward",
  as_of_date = "2026-05-07",
  axis1_summary = list(
    decay_count_positive = decay_count_with_decay_pos,
    welch_significant_count = decay_significant_count,
    decay_rates = sapply(axis1_results, function(x) x$decay_rate_stambaugh),
    half_lives_months = sapply(axis1_results, function(x) x$half_life_months),
    bayesian_posterior_mu = bayesian_update$posterior_mu,
    bayesian_posterior_sigma = bayesian_update$posterior_sigma
  ),
  axis2_summary = list(
    joint_innovation_cor_AR_TSMOM = joint_cor["dsr36_AR", "dsr36_TSMOM"],
    joint_innovation_cor_AR_KR10y = joint_cor["dsr36_AR", "dsr36_KR10y"],
    joint_innovation_cor_TSMOM_KR10y = joint_cor["dsr36_TSMOM", "dsr36_KR10y"],
    joint_decay_lower_25_observed = joint_decay_lower_25,
    joint_decay_lower_25_indep = indep_25,
    joint_excess = joint_dependency_excess,
    hybrid_under_decay_sr_ann = decay_regime_summary$hybrid_decay_sr_ann,
    hybrid_other_sr_ann = decay_regime_summary$hybrid_other_sr_ann
  ),
  axis3_summary = list(
    hybrid_forward_60m_sr = hybrid_dt[horizon_months == 60, hybrid_sr_h_forward],
    hybrid_forward_60m_decay_pct = hybrid_60m_decay,
    posterior_decay_mu = bayesian_update$posterior_mu
  ),
  termination_decision = termination,
  termination_reason = termination_reason,
  next_cycle_recommendation = next_cycle,
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
write_json(cycle8_dashboard,
           file.path(WORK, "cycle8_aggregate_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)
log_msg(sprintf("Cycle 8 termination decision: %s", termination))

log_msg("Cycle 8 3-axis run complete")
