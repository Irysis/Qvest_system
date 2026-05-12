#==============================================================================
# Dynamic Weight Rule Method Comparison v3 — 256m extension
#
# r_H_renorm convention (architect_hybrid_returns_full256m.csv):
#   TSMOM missing → re-normalize weights (50/25/20/5 → 50/20/5 with 50% str1715, 20% kr10y, 5% cash from 75% total = 67/27/7)
# v3 extends to full 256m with same re-normalization for missing TSMOM rows.
# Strict criterion: SR > 1.6744 (r_H_renorm 256m baseline)
#==============================================================================

suppressMessages({ library(arrow); library(jsonlite); library(data.table) })
set.seed(20260511)

returns <- read.csv("stage_artifacts/WT_P20260505_001/merged_returns_3source.csv", stringsAsFactors=FALSE)
returns$date <- as.Date(returns$date)
returns <- as.data.table(returns)
returns[, cash := 0]
# Set TSMOM NA to NA (will be re-normalized in composite)
returns_full <- returns[!is.na(str1715)]
cat("Full window (str1715 available):", as.character(min(returns_full$date)), "~", as.character(max(returns_full$date)), "N=", nrow(returns_full), "\n")
cat("kr10y avail:", sum(!is.na(returns_full$kr10y)), "tsmom avail:", sum(!is.na(returns_full$tsmom)), "\n")

assets <- c("str1715", "kr10y", "tsmom", "cash")
assets3 <- c("str1715", "kr10y", "tsmom")

# Regime detection on full str1715
regime_from_str1715 <- function(r) {
  n <- length(r); rs <- rep(NA, n)
  for (i in 12:n) rs[i] <- sum(r[(i-11):i])
  pct <- rep(NA, n)
  for (i in 12:n) { h <- rs[12:i]; h <- h[!is.na(h)]
    if (length(h)>1) pct[i] <- rank(h)[length(h)]/length(h) }
  reg <- rep(NA_character_, n)
  reg[!is.na(pct) & pct > 0.75] <- "BULL"
  reg[!is.na(pct) & pct > 0.50 & pct <= 0.75] <- "NORMAL"
  reg[!is.na(pct) & pct > 0.25 & pct <= 0.50] <- "CAUTION"
  reg[!is.na(pct) & pct <= 0.25] <- "CRISIS"
  c(NA, reg[-n])  # t-1 lag
}
returns_full[, regime_lag := regime_from_str1715(str1715)]
cat("Regime dist (256m, t-1 lag):\n"); print(table(returns_full$regime_lag, useNA="always"))

# Re-normalized composite return
composite_ret_renorm <- function(W, dt) {
  # W: matrix(N, 4) sleeve weights
  # For rows where tsmom is NA, redistribute tsmom weight to other 3 sleeves proportionally
  if (is.vector(W)) W <- matrix(W, nrow=nrow(dt), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))
  r <- numeric(nrow(dt))
  for (t in 1:nrow(dt)) {
    w <- W[t, ]
    if (is.na(dt$tsmom[t])) {
      # Re-normalize: drop tsmom column, redistribute weight
      w_renorm <- w[c("str1715", "kr10y", "cash")]
      if (sum(w_renorm) > 0) w_renorm <- w_renorm / sum(w_renorm)
      r[t] <- w_renorm["str1715"] * dt$str1715[t] +
              w_renorm["kr10y"]   * (if(!is.na(dt$kr10y[t])) dt$kr10y[t] else 0) +
              w_renorm["cash"]    * 0
    } else {
      r[t] <- w["str1715"] * dt$str1715[t] +
              w["kr10y"]   * (if(!is.na(dt$kr10y[t])) dt$kr10y[t] else 0) +
              w["tsmom"]   * dt$tsmom[t] +
              w["cash"]    * 0
    }
  }
  r
}

# Helpers
perf <- function(r, freq=12) {
  r <- r[!is.na(r)]
  if (length(r) < 12) return(list(SR=NA, CAGR=NA, MDD=NA, Sortino=NA, Calmar=NA, N=length(r), AnnVol=NA))
  n <- length(r); ann_r <- prod(1+r)^(freq/n) - 1; ann_v <- sd(r)*sqrt(freq)
  nav <- cumprod(1+r); peak <- cummax(nav); mdd <- min(nav/peak - 1)
  ds <- r[r<0]; sortino <- if(length(ds)>0) ann_r / (sd(ds)*sqrt(freq)) else NA
  list(SR=ann_r/ann_v, CAGR=ann_r, MDD=mdd, Sortino=sortino, Calmar=ann_r/abs(mdd), N=n, AnnVol=ann_v)
}
to_yr <- function(W) { if (is.vector(W)) return(0); mean(rowSums(abs(diff(W))))/2 * 12 }
net_ret <- function(r, W, tc=15) {
  if (is.vector(W)) return(r)
  cost <- c(0, rowSums(abs(diff(W)))/2 * tc * 2 / 1e4)
  r - cost
}
dm_test <- function(r1, r2, freq=12) {
  ok <- !is.na(r1) & !is.na(r2)
  r1 <- r1[ok]; r2 <- r2[ok]; n <- length(r1)
  if (n < 12) return(list(sr_diff=NA, t_stat=NA, p_value=NA, n=n))
  sr1 <- mean(r1)/sd(r1)*sqrt(freq); sr2 <- mean(r2)/sd(r2)*sqrt(freq)
  rho <- cor(r1, r2)
  var_diff <- (1/(n-1)) * (2 - 2*rho + 0.5*(sr1^2 + sr2^2 - 2*sr1*sr2*rho^2)) * freq
  t_stat <- (sr1 - sr2) / sqrt(var_diff)
  list(sr_diff=sr1-sr2, t_stat=t_stat, p_value=2*(1-pnorm(abs(t_stat))), n=n, rho=rho)
}

# METHODS — adapted for 256m
make_static <- function(returns_full, w) {
  W <- matrix(w, nrow=nrow(returns_full), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))
  W
}

# Run methods adapted to 256m
methods_256m <- list()

methods_256m[["01_static_baseline"]] <- function() {
  list(name="01_static_baseline", W=make_static(returns_full, c(0.50, 0.20, 0.25, 0.05)),
       desc="S4 v2 admit static (50/25/20/5)")
}

methods_256m[["02_static_ew4"]] <- function() {
  list(name="02_static_ew4", W=make_static(returns_full, c(0.25, 0.25, 0.25, 0.25)),
       desc="EW 4-sleeve (25/25/25/25)")
}

methods_256m[["07_regime_crisis_mild"]] <- function() {
  n <- nrow(returns_full); base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  shift <- c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0.00)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- returns_full$regime_lag[t]
    W[t, ] <- if (!is.na(reg) && reg=="CRISIS") (base+shift)[assets] else base[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="07_regime_crisis_mild", W=W, desc="CRISIS shift str1715 -10pp / kr10y +5pp / tsmom +5pp")
}

methods_256m[["09_regime_crisis_aggr"]] <- function() {
  n <- nrow(returns_full); base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  shift <- c(str1715=-0.20, kr10y=+0.10, tsmom=+0.05, cash=+0.05)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- returns_full$regime_lag[t]
    W[t, ] <- if (!is.na(reg) && reg=="CRISIS") (base+shift)[assets] else base[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="09_regime_crisis_aggr", W=W, desc="CRISIS aggressive str1715 -20pp / kr10y +10pp / tsmom +5pp / cash +5pp")
}

# 17_regime_crisis_caution_bull_quartet: 4-state different shifts
methods_256m[["17_regime_4state_full"]] <- function() {
  n <- nrow(returns_full); base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- returns_full$regime_lag[t]
    if (is.na(reg)) {
      w <- base
    } else if (reg == "BULL") {
      # BULL: str1715 risk-on, slight tsmom up
      w <- base + c(str1715=+0.05, kr10y=-0.05, tsmom=0, cash=0)
    } else if (reg == "NORMAL") {
      # NORMAL: same as base
      w <- base
    } else if (reg == "CAUTION") {
      # CAUTION: kr10y up slightly
      w <- base + c(str1715=-0.05, kr10y=+0.05, tsmom=0, cash=0)
    } else if (reg == "CRISIS") {
      # CRISIS: str1715 down, kr10y up, tsmom up
      w <- base + c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0)
    }
    W[t, ] <- w[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="17_regime_4state_full", W=W, desc="4-state full quartet shifts")
}

# Risk Agent finding ⭐: CRISIS-tsmom coupling is SIG → CRISIS regime tsmom DOWN (not up!)
# Re-interpret Risk Agent finding: str1715-tsmom +0.234 in CRISIS means coupling spike → tsmom NOT diversifier in CRISIS → DOWNWEIGHT tsmom in CRISIS
methods_256m[["18_regime_crisis_tsmom_down"]] <- function() {
  n <- nrow(returns_full); base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  shift <- c(str1715=-0.10, kr10y=+0.15, tsmom=-0.10, cash=+0.05)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- returns_full$regime_lag[t]
    W[t, ] <- if (!is.na(reg) && reg=="CRISIS") (base+shift)[assets] else base[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="18_regime_crisis_tsmom_down", W=W, desc="CRISIS: tsmom DOWN (Risk Agent str1715-tsmom +0.234 coupling spike interpretation)")
}

# Vol target rolling 12m + cash 5% (covers full 256m, requires t > 12)
methods_256m[["10_vol_target_inverse"]] <- function() {
  n <- nrow(returns_full); W <- make_static(returns_full, c(0.50, 0.20, 0.25, 0.05))
  for (t in 13:n) {
    vol <- sapply(assets3, function(c) sd(returns_full[[c]][(t-12):(t-1)], na.rm=TRUE))
    if (any(is.na(vol)) || any(vol < 1e-8)) next
    iv <- 1/vol; iv <- iv/sum(iv)
    W[t, "str1715"] <- iv["str1715"]*0.95
    W[t, "kr10y"]   <- iv["kr10y"]*0.95
    W[t, "tsmom"]   <- iv["tsmom"]*0.95
    W[t, "cash"]    <- 0.05
  }
  list(name="10_vol_target_inverse", W=W, desc="Inverse-vol rolling 12m (cash 5%)")
}

# MVO rolling 60m
methods_256m[["03_mvo_rolling"]] <- function() {
  n <- nrow(returns_full); W <- make_static(returns_full, c(0.50, 0.20, 0.25, 0.05))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  for (t in 24:n) {
    start <- max(1, t-60)
    R <- as.matrix(returns_full[start:(t-1), .(str1715, kr10y, tsmom)])
    if (any(rowSums(is.na(R)) > 0)) next
    mu <- colMeans(R); Sig <- cov(R)
    Sig4 <- rbind(cbind(Sig, c(0,0,0)), c(0,0,0,1e-8))
    rownames(Sig4) <- assets; colnames(Sig4) <- assets
    mu4 <- c(mu, 0)
    Dmat <- 2.0 * Sig4; dvec <- mu4
    Amat <- cbind(rep(1,4), diag(4), -diag(4))
    bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
    sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1), error=function(e) NULL)
    if (!is.null(sol)) {
      current_w <- pmax(0, sol$solution); current_w <- current_w/sum(current_w)
    }
    W[t, ] <- current_w
  }
  list(name="03_mvo_rolling", W=W, desc="MVO rolling 60m (when joint avail)")
}

# RUN ALL
cat("\n=== Running 256m methods ===\n")
results256 <- list()
for (nm in names(methods_256m)) {
  res <- tryCatch(methods_256m[[nm]](), error=function(e) list(name=nm, W=NULL, error=conditionMessage(e)))
  cat(sprintf("[%s] %s DONE\n", nm, res$name))
  results256[[nm]] <- res
}

# EVAL on 256m (re-normalized composite)
eval256 <- data.frame()
baseline_r256 <- NULL
for (nm in names(results256)) {
  res <- results256[[nm]]
  if (is.null(res$W)) next
  rg <- composite_ret_renorm(res$W, returns_full)
  rn <- net_ret(rg, res$W)
  if (res$name == "01_static_baseline") baseline_r256 <- rn
  mn <- perf(rn); mg <- perf(rg)
  to <- to_yr(res$W)
  na_w <- sum(rowSums(is.na(res$W)) > 0)
  eval256 <- rbind(eval256, data.frame(
    method = res$name,
    desc = substr(res$desc, 1, 70),
    SR_gross = round(mg$SR, 4),
    SR_net = round(mn$SR, 4),
    CAGR = round(mn$CAGR, 4),
    MDD = round(mn$MDD, 4),
    Sortino = round(mn$Sortino, 4),
    Calmar = round(mn$Calmar, 4),
    AnnVol = round(mn$AnnVol, 4),
    Turnover_yr = round(to, 4),
    N_valid = mn$N,
    N_NA = na_w
  ))
}
eval256 <- eval256[order(-eval256$SR_net), ]
cat("\n=== 256m Method Comparison (re-normalized for missing TSMOM, net 15bps) ===\n")
print(eval256)

# DM test
dm256 <- data.frame()
for (nm in names(results256)) {
  res <- results256[[nm]]
  if (is.null(res$W) || res$name == "01_static_baseline") next
  rg <- composite_ret_renorm(res$W, returns_full)
  rn <- net_ret(rg, res$W)
  dm <- dm_test(rn, baseline_r256)
  dm256 <- rbind(dm256, data.frame(
    method = res$name,
    sr_diff = round(dm$sr_diff, 4),
    t_stat = round(dm$t_stat, 3),
    p_value = round(dm$p_value, 4),
    n = dm$n,
    rho = round(dm$rho, 3)
  ))
}
print(dm256)

write.csv(eval256, "stage_artifacts/WT_D20260511_002/method_comparison_v3_256m.csv", row.names=FALSE)
write.csv(dm256, "stage_artifacts/WT_D20260511_002/dm_test_v3_256m.csv", row.names=FALSE)
saveRDS(list(results=results256, eval=eval256, dm=dm256, returns_full=returns_full),
        "stage_artifacts/WT_D20260511_002/dynamic_comparison_v3_256m.rds")
cat("\nSaved v3 256m artifacts\n")
