#==============================================================================
# Sensitivity + Bootstrap CI for top candidates — WT-D20260511_002
#
# Top candidates (256m):
#   01_static_baseline (SR 1.8603, MDD -15.23%, TO 0%) — BENCHMARK
#   02_static_ew4 (SR 1.9333, MDD -6.70%, TO 0%) — different alpha thesis (downweights 1715)
#   09_regime_crisis_aggr (SR 1.9090, MDD -14.51%, TO 18.8%) — CRISIS regime mild outperform
#   07_regime_crisis_mild (SR 1.8924, MDD -14.91%, TO 9.4%)
#   18_regime_tsmom_down (SR 1.8895, MDD -14.63%, TO 18.8%)
#==============================================================================

suppressMessages({ library(arrow); library(data.table) })
set.seed(20260511)

r <- readRDS("stage_artifacts/WT_D20260511_002/dynamic_comparison_v3_256m.rds")
results <- r$results
returns_full <- r$returns_full

composite_ret_renorm <- function(W, dt) {
  assets <- c("str1715", "kr10y", "tsmom", "cash")
  if (is.vector(W)) W <- matrix(W, nrow=nrow(dt), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))
  rr <- numeric(nrow(dt))
  for (t in 1:nrow(dt)) {
    w <- W[t, ]
    if (is.na(dt$tsmom[t])) {
      wr <- w[c("str1715", "kr10y", "cash")]
      if (sum(wr) > 0) wr <- wr / sum(wr)
      rr[t] <- wr["str1715"] * dt$str1715[t] +
              wr["kr10y"]   * (if(!is.na(dt$kr10y[t])) dt$kr10y[t] else 0) +
              wr["cash"]    * 0
    } else {
      rr[t] <- w["str1715"] * dt$str1715[t] +
              w["kr10y"]   * (if(!is.na(dt$kr10y[t])) dt$kr10y[t] else 0) +
              w["tsmom"]   * dt$tsmom[t]
    }
  }
  rr
}
net_ret <- function(r, W, tc=15) {
  if (is.vector(W)) return(r)
  cost <- c(0, rowSums(abs(diff(W)))/2 * tc * 2 / 1e4)
  r - cost
}
sr_fn <- function(r, freq=12) {
  r <- r[!is.na(r)]
  if (length(r) < 12) return(NA)
  mean(r)/sd(r) * sqrt(freq)
}
mdd_fn <- function(r) {
  r <- r[!is.na(r)]
  nav <- cumprod(1+r); peak <- cummax(nav); min(nav/peak - 1)
}

# Bootstrap SR CI (block bootstrap, block=6m for monthly serial dependence)
bootstrap_sr_ci <- function(r, B=1000, block=6, freq=12, conf=0.95) {
  r <- r[!is.na(r)]
  n <- length(r)
  blocks <- ceiling(n / block)
  sr_b <- numeric(B)
  for (b in 1:B) {
    idx_start <- sample(1:(n-block+1), blocks, replace=TRUE)
    idx <- as.integer(unlist(lapply(idx_start, function(s) s:(s+block-1))))
    idx <- idx[idx <= n][1:n]
    r_b <- r[idx]
    sr_b[b] <- mean(r_b)/sd(r_b) * sqrt(freq)
  }
  lo <- quantile(sr_b, (1-conf)/2)
  hi <- quantile(sr_b, 1-(1-conf)/2)
  list(sr_lo=lo, sr_hi=hi, sr_se=sd(sr_b), B=B, block=block)
}

# Bootstrap MDD CI
bootstrap_mdd_ci <- function(r, B=1000, block=6, conf=0.95) {
  r <- r[!is.na(r)]
  n <- length(r)
  blocks <- ceiling(n / block)
  mdd_b <- numeric(B)
  for (b in 1:B) {
    idx_start <- sample(1:(n-block+1), blocks, replace=TRUE)
    idx <- as.integer(unlist(lapply(idx_start, function(s) s:(s+block-1))))
    idx <- idx[idx <= n][1:n]
    mdd_b[b] <- mdd_fn(r[idx])
  }
  lo <- quantile(mdd_b, (1-conf)/2)
  hi <- quantile(mdd_b, 1-(1-conf)/2)
  list(mdd_lo=lo, mdd_hi=hi, B=B, block=block)
}

# CVaR (95%) monthly
cvar_95 <- function(r, alpha=0.95) {
  r <- r[!is.na(r)]
  q <- quantile(r, 1-alpha)
  -mean(r[r <= q])
}

# Run on top 5 candidates
candidates <- c("01_static_baseline", "02_static_ew4", "09_regime_crisis_aggr",
                "07_regime_crisis_mild", "18_regime_crisis_tsmom_down")
sens_table <- data.frame()
cat("Bootstrap analysis (B=1000, block=6m)...\n")
for (nm in candidates) {
  res <- NULL
  for (r_ in results) if (r_$name == nm) { res <- r_; break }
  if (is.null(res)) next
  rg <- composite_ret_renorm(res$W, returns_full)
  rn <- net_ret(rg, res$W)
  sr_ci <- bootstrap_sr_ci(rn)
  mdd_ci <- bootstrap_mdd_ci(rn)
  cvar95 <- cvar_95(rn)
  sens_table <- rbind(sens_table, data.frame(
    method = nm,
    SR_net = round(sr_fn(rn), 4),
    SR_lo95 = round(sr_ci$sr_lo, 4),
    SR_hi95 = round(sr_ci$sr_hi, 4),
    SR_se = round(sr_ci$sr_se, 4),
    MDD_net = round(mdd_fn(rn), 4),
    MDD_lo95 = round(mdd_ci$mdd_lo, 4),
    MDD_hi95 = round(mdd_ci$mdd_hi, 4),
    CVaR_95_monthly = round(cvar95, 4)
  ))
  cat(sprintf("  %s: SR=%.4f [%.4f, %.4f], MDD=%.4f [%.4f, %.4f], CVaR_95=%.4f\n",
              nm, sr_fn(rn), sr_ci$sr_lo, sr_ci$sr_hi, mdd_fn(rn), mdd_ci$mdd_lo, mdd_ci$mdd_hi, cvar95))
}
print(sens_table)

# Crisis sub-period analysis (2008, 2011, 2020, 2022)
crisis_periods <- list(
  gfc_2008 = list(start="2008-01", end="2009-06"),
  eu_2011 = list(start="2011-07", end="2012-06"),
  covid_2020 = list(start="2020-02", end="2020-12"),
  inflation_2022 = list(start="2022-01", end="2022-12")
)
crisis_table <- data.frame()
for (nm in candidates) {
  res <- NULL
  for (r_ in results) if (r_$name == nm) { res <- r_; break }
  if (is.null(res)) next
  rg <- composite_ret_renorm(res$W, returns_full)
  rn <- net_ret(rg, res$W)
  for (cp in names(crisis_periods)) {
    p <- crisis_periods[[cp]]
    idx <- which(format(returns_full$date, "%Y-%m") >= p$start & format(returns_full$date, "%Y-%m") <= p$end)
    if (length(idx) > 0) {
      r_p <- rn[idx]
      r_p <- r_p[!is.na(r_p)]
      if (length(r_p) > 1) {
        cum_ret <- prod(1+r_p) - 1
        worst_m <- min(r_p)
        nav <- cumprod(1+r_p); peak <- cummax(nav); mdd_p <- min(nav/peak - 1)
        crisis_table <- rbind(crisis_table, data.frame(
          method=nm, period=cp, n_months=length(r_p),
          cum_return=round(cum_ret,4), worst_month=round(worst_m,4), mdd_period=round(mdd_p,4)
        ))
      }
    }
  }
}
cat("\n=== Crisis sub-period performance ===\n")
print(crisis_table)

# Save
write.csv(sens_table, "stage_artifacts/WT_D20260511_002/sensitivity_bootstrap.csv", row.names=FALSE)
write.csv(crisis_table, "stage_artifacts/WT_D20260511_002/crisis_subperiods.csv", row.names=FALSE)
saveRDS(list(sens=sens_table, crisis=crisis_table),
        "stage_artifacts/WT_D20260511_002/sensitivity_full.rds")
cat("\nSaved sensitivity + crisis subperiods.\n")
