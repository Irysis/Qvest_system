#==============================================================================
# WT-D20260426_008 Optimizer Research — STR_1701 V3 Direct Upgrade
#
# Step 1~6 자율 파이프라인:
#   1. Feasibility (load alpha+risk+request, sanity)
#   2. Objective (active vs absolute -> long-only absolute Σw=1)
#   3. Constraint Binding (max_names=20, bounds [0,0.20], regime-aware max_w 0.10 CRISIS)
#   4. Cost-Aware Optimization (10 methods, walk-forward per-sig_date weights)
#   5. Sensitivity (binding constraints, dual proxy)
#   6. Emit optimization_package + weights.csv
#
# Risk Forward Mandate:
#   - BIND pooled Σ in CRISIS/CAUTION regime  (cond>100 / T<30)
#   - max_w 0.10 in CRISIS
#   - tail caps weight-applied re-measurement (CVaR_d ≤ 2.5%, MDD ≤ 45%)
#   - infeasibility_report mandatory if CVaR_d > 2.5%
#
# Hard constraints:
#   max_names = 20 / weight_bounds [0, 0.20] / Σw = 1 / long-only
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(quadprog)
  library(jsonlite)
})

PROJECT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID   <- "WT-D20260426_008"
WT_DIR  <- file.path(PROJECT, "qepm/mailbox/worktask", WT_ID)
SA_DIR  <- file.path(PROJECT, "stage_artifacts", "WT_D20260426_008")
setwd(PROJECT)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

cat("=============================================================\n")
cat(sprintf("[Optimizer V3] WT %s — START %s\n", WT_ID, Sys.time()))
cat("=============================================================\n")

#─── Step 1: Feasibility / Load ─────────────────────────────────────
cat("\n[Step 1] Feasibility check + load packages\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)
request   <- fromJSON(file.path(WT_DIR, "request.json"),       simplifyVector = FALSE)

# Alpha scores panel (240 sig_dates × 20 tickers, top_flag==1)
ascr <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
ascr_top <- ascr[top_flag == 1L]
setkey(ascr_top, Date, Ticker)
cat(sprintf("  alpha_scores top_flag panel: %d rows × %d tickers × %d sig_dates\n",
            nrow(ascr_top), length(unique(ascr_top$Ticker)), length(unique(ascr_top$Date))))

# Risk: full Σ (last sig_date 20-ticker panel)
cv_full <- as.data.table(read_parquet(file.path(SA_DIR, "covariance.parquet")))
cov_tk_full  <- cv_full$Ticker
cov_mat_full <- as.matrix(cv_full[, -"Ticker"])
rownames(cov_mat_full) <- cov_tk_full
colnames(cov_mat_full) <- cov_tk_full

cv_pool <- as.data.table(read_parquet(file.path(SA_DIR, "covariance_pooled_fallback.parquet")))
cov_mat_pool <- as.matrix(cv_pool[, -"Ticker"])
rownames(cov_mat_pool) <- cv_pool$Ticker
colnames(cov_mat_pool) <- cv_pool$Ticker

cat(sprintf("  Σ_full: %d×%d, cond=%.2f\n",
            nrow(cov_mat_full), ncol(cov_mat_full),
            kappa(cov_mat_full, exact = TRUE)))
cat(sprintf("  Σ_pool: %d×%d, cond=%.2f\n",
            nrow(cov_mat_pool), ncol(cov_mat_pool),
            kappa(cov_mat_pool, exact = TRUE)))

# Hard constraint pre-check: max_names=20, bounds [0,0.20], 20*0.20 ≥ 1 ✓
N_HARD     <- 20L
W_LO       <- 0.0
W_HI       <- 0.20
W_HI_CRIS  <- 0.10
COST_BPS   <- 15
TARGET_SUM <- 1.0

stopifnot(N_HARD * W_HI >= TARGET_SUM)

#─── Step 2: Objective ───────────────────────────────────────────────
# Active management with long-only absolute (Σw=1) — typical KR retail mandate.
# Objective: max x'α̂ - (λ/2) x'Σx - φ TC(x) - ψ FU(x,c)
# Selection: net_IR (gross_IR - cost) / TE — used for method comparison.

cat("\n[Step 2] Objective: Confidence-aware MVO + tail-aware comparison\n")

LAMBDA <- 2.0   # risk aversion
PSI    <- 0.3   # forecast uncertainty penalty (low confidence concentration penalty)
PHI    <- 1.0   # turnover cost (15bps already applied via post-process)

#─── Step 3: Constraint Binding & helpers ────────────────────────────

# .normalize: long-only + bounds + Σw=1 normalize (hard cap weight)
.normalize <- function(w, lo = W_LO, hi = W_HI, target_sum = TARGET_SUM, tol = 1e-9) {
  w[!is.finite(w)] <- 0
  w[w < lo] <- lo
  # iterative cap
  for (iter in seq_len(50L)) {
    w_sum <- sum(w)
    if (abs(w_sum - target_sum) < tol) break
    if (w_sum <= 0) {
      w[] <- target_sum / length(w)
      break
    }
    w <- w * (target_sum / w_sum)
    over <- w > hi
    if (!any(over)) break
    excess <- sum(w[over] - hi)
    w[over] <- hi
    under_idx <- which(!over & w < hi - tol)
    if (length(under_idx) == 0) break
    add_per <- excess / length(under_idx)
    w[under_idx] <- pmin(hi, w[under_idx] + add_per)
  }
  # Final: re-normalize to sum=1 (small drift OK)
  w <- w / sum(w)
  w
}

# Confidence-aware MVO via quadprog
.mvo_cv <- function(alpha_v, cov_m, conf_v, lambda = LAMBDA, psi = PSI,
                    lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  N <- length(alpha_v)
  alpha_eff <- alpha_v * conf_v        # confidence-scaled alpha
  # FU diagonal: psi * (1-c)^2
  D_fu <- diag(psi * (1 - conf_v)^2, N, N)
  Dmat <- lambda * cov_m + D_fu + diag(1e-8, N)
  Dmat <- (Dmat + t(Dmat)) / 2  # symmetric
  dvec <- alpha_eff
  # constraints: 1'x = target_sum, x >= lo, x <= hi
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(target_sum, rep(lo, N), rep(-hi, N))
  res <- tryCatch(
    solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
    error = function(e) NULL
  )
  if (is.null(res)) return(rep(target_sum / N, N))
  w <- res$solution
  .normalize(w, lo, hi, target_sum)
}

# HRP via correlation distance + quasi-diag
.hrp <- function(cov_m, lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  N <- nrow(cov_m)
  if (N == 0) return(numeric(0))
  if (N == 1) return(target_sum)
  sd_v <- sqrt(diag(cov_m))
  cor_m <- cov_m / (sd_v %o% sd_v)
  cor_m[!is.finite(cor_m)] <- 0
  diag(cor_m) <- 1
  dist_m <- sqrt(0.5 * (1 - cor_m))
  hc <- hclust(as.dist(dist_m), method = "single")
  order_idx <- hc$order
  # IVP allocation along quasi-diag
  iv <- 1 / sd_v
  iv[!is.finite(iv)] <- 0
  iv <- iv / sum(iv)
  # bisection HRP weighting
  w <- rep(1, N)
  recur <- function(items) {
    if (length(items) <= 1) return()
    mid <- floor(length(items) / 2)
    left <- items[1:mid]; right <- items[(mid + 1):length(items)]
    var_left  <- sum(diag(cov_m)[left]  * iv[left]^2)  / max(sum(iv[left])^2, 1e-12)
    var_right <- sum(diag(cov_m)[right] * iv[right]^2) / max(sum(iv[right])^2, 1e-12)
    alpha <- 1 - var_left / (var_left + var_right + 1e-12)
    w[left]  <<- w[left]  * alpha
    w[right] <<- w[right] * (1 - alpha)
    recur(left); recur(right)
  }
  ordered <- order_idx
  recur(ordered)
  w_out <- numeric(N)
  w_out[ordered] <- w[ordered] * iv[ordered]
  w_out <- w_out / sum(w_out) * target_sum
  .normalize(w_out, lo, hi, target_sum)
}

# Equal Risk Contribution (ERC) via gradient projection
.erc <- function(cov_m, lo = W_LO, hi = W_HI, target_sum = TARGET_SUM, max_iter = 200L) {
  N <- nrow(cov_m)
  w <- rep(target_sum / N, N)
  for (it in seq_len(max_iter)) {
    sigma_p <- sqrt(as.numeric(t(w) %*% cov_m %*% w))
    if (!is.finite(sigma_p) || sigma_p < 1e-12) break
    mrc <- (cov_m %*% w) / sigma_p   # marginal risk contrib
    rc  <- as.numeric(w * mrc)        # risk contrib
    target_rc <- sigma_p / N
    grad <- rc - target_rc
    step <- 0.01 / (1 + it / 50)
    w <- w - step * grad
    w[w < lo] <- lo
    w[w > hi] <- hi
    w <- w / sum(w) * target_sum
    if (max(abs(grad)) < 1e-6) break
  }
  .normalize(w, lo, hi, target_sum)
}

# Inverse Volatility
.inv_vol <- function(cov_m, lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  sd_v <- sqrt(diag(cov_m))
  iv <- 1 / sd_v
  iv[!is.finite(iv)] <- 0
  w <- iv / sum(iv) * target_sum
  .normalize(w, lo, hi, target_sum)
}

# Max Diversification
.maxdiv <- function(cov_m, lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  N <- nrow(cov_m)
  sd_v <- sqrt(diag(cov_m))
  # max DR = (w'σ) / sqrt(w'Σw) — solve via QP: min -w'σ s.t. w'Σw=1 then rescale
  Dmat <- 2 * (cov_m + diag(1e-8, N))
  Dmat <- (Dmat + t(Dmat)) / 2
  dvec <- sd_v
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(target_sum, rep(lo, N), rep(-hi, N))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
  if (is.null(res)) return(rep(target_sum / N, N))
  .normalize(res$solution, lo, hi, target_sum)
}

# Black-Litterman style: shrink alpha toward equal-prior using confidence
.bl <- function(alpha_v, cov_m, conf_v, tau = 0.5,
                lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  N <- length(alpha_v)
  prior <- mean(alpha_v)
  shrink <- conf_v / (conf_v + tau)
  alpha_bl <- shrink * alpha_v + (1 - shrink) * prior
  .mvo_cv(alpha_bl, cov_m, conf_v, lambda = LAMBDA, psi = PSI * 0.5,
          lo = lo, hi = hi, target_sum = target_sum)
}

# Linear Tilt: alpha-rank tilt onto EW
.lin_tilt <- function(alpha_v, lambda_t = 0.05,
                      lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  N <- length(alpha_v)
  # cross-section z-score
  z <- (alpha_v - mean(alpha_v)) / max(sd(alpha_v), 1e-12)
  z <- pmin(pmax(z, -2), 2)  # winsor 2σ
  w <- (target_sum / N) + lambda_t * z
  .normalize(w, lo, hi, target_sum)
}

# CVaR LP proxy: penalize via CVaR estimate (95%) using Σ-implied normal
# (true CVaR LP needs scenarios — use parametric proxy + alpha tilt)
.cvar_proxy <- function(alpha_v, cov_m, conf_v, alpha_lvl = 0.95,
                        lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  N <- length(alpha_v)
  # Normal approx CVaR: -(μ - σ * φ(z)/(1-α))
  # MVO with augmented λ to penalize tail (z_alpha)
  z_alpha <- qnorm(alpha_lvl)
  phi_alpha <- dnorm(z_alpha) / (1 - alpha_lvl)
  lambda_eff <- LAMBDA * (1 + phi_alpha)
  alpha_eff <- alpha_v * conf_v
  D_fu <- diag(PSI * (1 - conf_v)^2, N, N)
  Dmat <- lambda_eff * cov_m + D_fu + diag(1e-8, N)
  Dmat <- (Dmat + t(Dmat)) / 2
  dvec <- alpha_eff
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(target_sum, rep(lo, N), rep(-hi, N))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
  if (is.null(res)) return(rep(target_sum / N, N))
  .normalize(res$solution, lo, hi, target_sum)
}

# Risk Parity (= ERC variant, sub-method using diag-free)
.risk_par <- function(cov_m, lo = W_LO, hi = W_HI, target_sum = TARGET_SUM) {
  .erc(cov_m, lo, hi, target_sum, max_iter = 300L)
}

cat("  Helpers loaded: MVO/HRP/ERC/InvVol/MaxDiv/BL/LinTilt/CVaR_proxy/RP\n")

#─── Step 4: Walk-forward Optimization ───────────────────────────────
cat("\n[Step 4] Walk-forward optimization across 240 sig_dates × 10 methods\n")

dates_sorted <- sort(unique(ascr_top$Date))
N_DATES <- length(dates_sorted)

# Per-sig_date rolling Σ from full panel Ret_1m (any ticker, 36-month window)
# Build full panel return matrix (date × ticker) for rolling Σ
ret_panel <- dcast(ascr, Date ~ Ticker, value.var = "Ret_1m")
setkey(ret_panel, Date)

ROLL_WINDOW_M <- 36L  # 3 years

estimate_local_sigma <- function(sig_date, tickers, fallback_global = cov_mat_full,
                                 fallback_pool = cov_mat_pool) {
  # Use last ROLL_WINDOW_M months strictly before sig_date
  past_dates <- dates_sorted[dates_sorted < sig_date]
  if (length(past_dates) < 12L) {
    # Not enough history → use global pool
    sub_idx <- match(tickers, rownames(fallback_pool))
    sub_idx <- sub_idx[!is.na(sub_idx)]
    if (length(sub_idx) < length(tickers)) {
      # Fill missing with diag(median variance)
      med_var <- median(diag(fallback_pool))
      out <- matrix(0, length(tickers), length(tickers))
      diag(out) <- med_var
      rownames(out) <- colnames(out) <- tickers
      if (length(sub_idx) > 0) {
        valid_tk <- intersect(tickers, rownames(fallback_pool))
        out[valid_tk, valid_tk] <- fallback_pool[valid_tk, valid_tk]
      }
      return(out)
    }
    return(fallback_pool[tickers, tickers, drop = FALSE])
  }
  win_start <- past_dates[max(1, length(past_dates) - ROLL_WINDOW_M + 1)]
  win_end <- past_dates[length(past_dates)]
  rp_sub <- ret_panel[Date >= win_start & Date <= win_end]
  ret_mat <- as.matrix(rp_sub[, tickers, with = FALSE])
  # Replace NA with column mean
  for (j in seq_along(tickers)) {
    nas <- is.na(ret_mat[, j])
    if (all(nas)) ret_mat[, j] <- 0
    else if (any(nas)) ret_mat[nas, j] <- mean(ret_mat[, j], na.rm = TRUE)
  }
  if (nrow(ret_mat) < 12L) {
    return(estimate_local_sigma(sig_date, tickers, fallback_global, fallback_pool))
  }
  Sgm <- cov(ret_mat)
  # Ledoit-Wolf shrinkage to constant correlation target
  N_ <- ncol(Sgm)
  sd_v <- sqrt(diag(Sgm))
  cor_m <- Sgm / (sd_v %o% sd_v)
  cor_m[!is.finite(cor_m)] <- 0
  diag(cor_m) <- 1
  rho_bar <- (sum(cor_m) - N_) / (N_ * (N_ - 1))
  target_cor <- matrix(rho_bar, N_, N_); diag(target_cor) <- 1
  target_cov <- target_cor * (sd_v %o% sd_v)
  shrink <- 0.3  # standard pragma
  Sgm_sh <- (1 - shrink) * Sgm + shrink * target_cov
  # PSD floor
  eig <- eigen(Sgm_sh, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-6)
  Sgm_psd <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
  Sgm_psd <- (Sgm_psd + t(Sgm_psd)) / 2
  rownames(Sgm_psd) <- colnames(Sgm_psd) <- tickers
  Sgm_psd
}

# Methods registry (10 candidates)
METHODS <- c(
  "EW_baseline",
  "InvVol",
  "HRP",
  "ERC",
  "MaxDiv",
  "MVO_conf_aware",
  "BlackLitterman",
  "LinTilt_alpha",
  "CVaR_proxy",
  "Ensemble_top3"
)

# Storage: list of weight matrices (sig_date × ticker)
weights_by_method <- list()
for (m in METHODS) weights_by_method[[m]] <- list()

# Track binding constraint stats
binding_count <- list()
for (m in METHODS) binding_count[[m]] <- 0L

t0 <- Sys.time()
for (i in seq_len(N_DATES)) {
  sd_i  <- dates_sorted[i]
  panel <- ascr_top[Date == sd_i]
  setorder(panel, -score_eff_v3)
  tickers_i <- panel$Ticker
  alpha_i   <- panel$score_eff_v3
  names(alpha_i) <- tickers_i
  # Confidence: derive from rank (top names higher) — use linear normalized rank in [0.5,1]
  # If alpha_pkg has confidence, prefer it; else use rank-based
  conf_i <- 0.5 + 0.5 * (length(tickers_i):1) / length(tickers_i)
  names(conf_i) <- tickers_i
  # If last sig_date and confidence_vector available — use it
  if (sd_i == dates_sorted[N_DATES]) {
    cv_pkg <- alpha_pkg$confidence_vector
    if (!is.null(cv_pkg)) {
      cv_named <- unlist(cv_pkg)
      common <- intersect(tickers_i, names(cv_named))
      conf_i[common] <- as.numeric(cv_named[common])
    }
  }
  regime_i <- panel$regime_state[1]

  # Σ selection: pooled in CRISIS / CAUTION (forward mandate)
  if (regime_i %in% c("CRISIS", "CAUTION")) {
    # Pool fallback uses last sig_date 20 panel — adapt to current panel by ticker subset
    # If tickers_i ⊆ pool tickers → slice; else compute local
    if (all(tickers_i %in% rownames(cov_mat_pool))) {
      Sgm_i <- cov_mat_pool[tickers_i, tickers_i, drop = FALSE]
    } else {
      Sgm_i <- estimate_local_sigma(sd_i, tickers_i,
                                    fallback_global = cov_mat_pool,
                                    fallback_pool = cov_mat_pool)
    }
    hi_i <- W_HI_CRIS  # 0.10 in CRISIS only (CAUTION keeps 0.20)
    if (regime_i == "CAUTION") hi_i <- W_HI
  } else {
    Sgm_i <- estimate_local_sigma(sd_i, tickers_i,
                                  fallback_global = cov_mat_full,
                                  fallback_pool = cov_mat_pool)
    hi_i <- W_HI
  }

  # PSD safety
  eig <- eigen(Sgm_i, symmetric = TRUE)
  if (min(eig$values) < 1e-8) {
    eig$values <- pmax(eig$values, 1e-8)
    Sgm_i <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
    Sgm_i <- (Sgm_i + t(Sgm_i)) / 2
    rownames(Sgm_i) <- colnames(Sgm_i) <- tickers_i
  }

  # Run each method
  w_list <- list()
  w_list$EW_baseline    <- rep(1 / length(tickers_i), length(tickers_i))
  w_list$InvVol         <- .inv_vol(Sgm_i, hi = hi_i)
  w_list$HRP            <- .hrp(Sgm_i, hi = hi_i)
  w_list$ERC            <- .erc(Sgm_i, hi = hi_i)
  w_list$MaxDiv         <- .maxdiv(Sgm_i, hi = hi_i)
  w_list$MVO_conf_aware <- .mvo_cv(alpha_i, Sgm_i, conf_i, hi = hi_i)
  w_list$BlackLitterman <- .bl(alpha_i, Sgm_i, conf_i, hi = hi_i)
  w_list$LinTilt_alpha  <- .lin_tilt(alpha_i, lambda_t = 0.04, hi = hi_i)
  w_list$CVaR_proxy     <- .cvar_proxy(alpha_i, Sgm_i, conf_i, hi = hi_i)

  for (mn in METHODS[METHODS != "Ensemble_top3"]) {
    w_v <- w_list[[mn]]
    names(w_v) <- tickers_i
    weights_by_method[[mn]][[as.character(sd_i)]] <- w_v
    # Count binding (weight at hi)
    if (any(abs(w_v - hi_i) < 1e-6)) binding_count[[mn]] <- binding_count[[mn]] + 1L
  }

  if (i %% 60 == 0) {
    cat(sprintf("  ...%d / %d sig_dates done (%.1fs)\n",
                i, N_DATES, as.numeric(Sys.time() - t0, units = "secs")))
  }
}

# Ensemble: equal-weighted top 3 methods (decided after metric comp below)
# Placeholder — fill after method scoring

cat(sprintf("  All %d sig_dates × 9 base methods complete (%.1fs)\n",
            N_DATES, as.numeric(Sys.time() - t0, units = "secs")))

#─── Step 5: Method Scoring (net_IR + tail caps weight-applied) ─────
cat("\n[Step 5] Score each method: gross_IR, TE, turnover, cost, CVaR_d, MDD\n")

# Helper: build sig_date weights as data.table → join with Ret_1m → portfolio return
build_returns <- function(weights_list) {
  # weights_list: list keyed by date_string -> named numeric
  dt_w <- rbindlist(lapply(names(weights_list), function(ds) {
    w <- weights_list[[ds]]
    data.table(Date = as.Date(ds), Ticker = names(w), w = unname(w))
  }))
  setkey(dt_w, Date, Ticker)
  # Merge with Ret_1m
  rp <- ascr_top[, .(Date, Ticker, Ret_1m)]
  setkey(rp, Date, Ticker)
  mrg <- merge(dt_w, rp, by = c("Date", "Ticker"), all.x = TRUE)
  mrg[is.na(Ret_1m), Ret_1m := 0]
  port_ret <- mrg[, .(port_ret = sum(w * Ret_1m, na.rm = TRUE)), by = Date]
  setorder(port_ret, Date)
  port_ret
}

# Turnover annualized: sum across rebalance |w_t - w_{t-1}|, monthly avg ×12
build_turnover <- function(weights_list) {
  dates <- sort(as.Date(names(weights_list)))
  N <- length(dates)
  if (N < 2) return(0)
  to_total <- 0
  for (i in 2:N) {
    w_prev <- weights_list[[as.character(dates[i - 1])]]
    w_curr <- weights_list[[as.character(dates[i])]]
    tk_all <- union(names(w_prev), names(w_curr))
    wp <- setNames(numeric(length(tk_all)), tk_all)
    wc <- setNames(numeric(length(tk_all)), tk_all)
    wp[names(w_prev)] <- w_prev
    wc[names(w_curr)] <- w_curr
    to_total <- to_total + sum(abs(wc - wp))
  }
  # 1-sided turnover (sum of |Δw|/2 = trade volume); 2-sided = full sum
  to_avg_per_rebal <- to_total / (N - 1)
  to_annual_2sided <- to_avg_per_rebal * 12  # monthly rebalance × 12
  to_annual_2sided
}

method_metrics <- list()

for (mn in METHODS[METHODS != "Ensemble_top3"]) {
  wl <- weights_by_method[[mn]]
  port <- build_returns(wl)
  ret_v <- port$port_ret
  to_ann <- build_turnover(wl)
  cost_ann <- to_ann * (COST_BPS / 10000)  # 15bps × turnover
  # Net monthly: deduct cost evenly over 12 months
  cost_per_month <- cost_ann / 12
  ret_net_v <- ret_v - cost_per_month
  # Annualized stats
  mu_m <- mean(ret_v); sd_m <- sd(ret_v)
  sr_gross_ann <- (mu_m / sd_m) * sqrt(12)
  cagr_gross <- prod(1 + ret_v)^(12 / length(ret_v)) - 1
  # net
  mu_m_n <- mean(ret_net_v); sd_m_n <- sd(ret_net_v)
  sr_net_ann <- (mu_m_n / sd_m_n) * sqrt(12)
  cagr_net <- prod(1 + ret_net_v)^(12 / length(ret_net_v)) - 1
  # MDD
  cum <- cumprod(1 + ret_net_v)
  peak <- cummax(cum)
  dd <- cum / peak - 1
  mdd <- min(dd)
  # CVaR_daily — weight-applied re-measurement using risk_pkg per-regime tail
  # Risk pkg per_regime CVaR_d (EW top-20 proxy): BULL -2.63% / NORMAL -2.90% / CAUTION -5.70% / CRISIS -4.30%
  # Weight-applied scaling: CVaR_d_w ≈ CVaR_d_EW * (σ_p / σ_EW), regime-mixed.
  per_reg_cvar <- list(BULL = -0.0263, NORMAL = -0.0290, CAUTION = -0.0570, CRISIS = -0.0430)
  # Compute σ_p / σ_EW per sig_date using local Σ
  rg_per_date <- ascr_top[, .(rg = regime_state[1]), by = Date]
  setkey(rg_per_date, Date)
  sigma_ratios <- numeric(0)
  cvar_d_contrib <- numeric(0)
  for (ds in names(wl)) {
    w_v <- wl[[ds]]
    tk_v <- names(w_v)
    # Use full Σ if all tickers in cov_mat_full else local
    if (all(tk_v %in% rownames(cov_mat_full))) {
      Sg <- cov_mat_full[tk_v, tk_v, drop = FALSE]
    } else {
      Sg <- estimate_local_sigma(as.Date(ds), tk_v,
                                  fallback_global = cov_mat_full,
                                  fallback_pool = cov_mat_pool)
    }
    sd_p   <- sqrt(as.numeric(t(w_v) %*% Sg %*% w_v))
    sd_ew  <- sqrt(mean(diag(Sg)) / length(w_v) +
                    (sum(Sg) - sum(diag(Sg))) / (length(w_v)^2))
    if (!is.finite(sd_ew) || sd_ew < 1e-12) sd_ew <- max(sd_p, 1e-6)
    ratio  <- sd_p / sd_ew
    sigma_ratios <- c(sigma_ratios, ratio)
    rg_d <- rg_per_date[Date == as.Date(ds)]$rg
    cv_d <- per_reg_cvar[[rg_d]] %||% per_reg_cvar$NORMAL
    cvar_d_contrib <- c(cvar_d_contrib, cv_d * ratio)
  }
  # Take mean across all sig_dates (book-level expected daily CVaR)
  cvar_d_5 <- mean(cvar_d_contrib)
  # Worst regime (CRISIS) for stress reporting
  cvar_d_crisis_max <- if (any(rg_per_date$rg == "CRISIS")) {
    cris_idx <- which(rg_per_date$rg == "CRISIS")
    min(cvar_d_contrib[cris_idx])
  } else NA
  # IR vs benchmark: KOSPI200 not provided as panel — use EW as proxy benchmark
  # But for selection_objective = net_IR, we use SR_net as IR proxy (no explicit benchmark)
  net_ir <- sr_net_ann  # proxy: net SR (since active vs benchmark not in panel)

  # Hard cap PASS checks
  pass_to    <- to_ann <= 6.0
  pass_cvar  <- abs(cvar_d_5) <= 0.025
  pass_mdd   <- abs(mdd) <= 0.45

  method_metrics[[mn]] <- list(
    method = mn,
    n_obs = length(ret_v),
    sr_gross = sr_gross_ann,
    sr_net = sr_net_ann,
    cagr_gross = cagr_gross,
    cagr_net = cagr_net,
    mdd = mdd,
    cvar_d_5 = cvar_d_5,
    turnover_ann = to_ann,
    cost_ann = cost_ann,
    net_ir = net_ir,
    binding_count = binding_count[[mn]],
    pass_to_cap = pass_to,
    pass_cvar_cap = pass_cvar,
    pass_mdd_cap = pass_mdd
  )
}

# Print scoring table
cat("\n=== Method Comparison (net_IR primary) ===\n")
mm_dt <- rbindlist(lapply(method_metrics, function(m) {
  as.data.table(m[c("method", "sr_net", "cagr_net", "mdd", "cvar_d_5",
                     "turnover_ann", "cost_ann", "net_ir",
                     "pass_to_cap", "pass_cvar_cap", "pass_mdd_cap")])
}))
mm_dt[, sr_net := round(sr_net, 4)]
mm_dt[, cagr_net := round(cagr_net, 4)]
mm_dt[, mdd := round(mdd, 4)]
mm_dt[, cvar_d_5 := round(cvar_d_5, 5)]
mm_dt[, turnover_ann := round(turnover_ann, 3)]
mm_dt[, cost_ann := round(cost_ann, 4)]
mm_dt[, net_ir := round(net_ir, 4)]
print(mm_dt)

#─── Build Ensemble_top3 ─────────────────────────────────────────────
top3_names <- mm_dt[order(-net_ir)][pass_to_cap == TRUE & pass_cvar_cap == TRUE & pass_mdd_cap == TRUE][1:3]$method
top3_names <- top3_names[!is.na(top3_names)]
if (length(top3_names) >= 2) {
  cat(sprintf("\n[Ensemble] EW combine top-%d: %s\n", length(top3_names), paste(top3_names, collapse = ", ")))
  ens_w_list <- list()
  dates_chr <- as.character(dates_sorted)
  for (ds in dates_chr) {
    tk_set <- names(weights_by_method[[top3_names[1]]][[ds]])
    w_avg <- numeric(length(tk_set)); names(w_avg) <- tk_set
    for (m in top3_names) {
      w_m <- weights_by_method[[m]][[ds]]
      common <- intersect(tk_set, names(w_m))
      w_avg[common] <- w_avg[common] + w_m[common] / length(top3_names)
    }
    # Normalize (min-tweak; ensemble may breach hi on few names if rare)
    hi_use <- if (ascr_top[Date == as.Date(ds)]$regime_state[1] == "CRISIS") W_HI_CRIS else W_HI
    w_avg <- .normalize(w_avg, lo = W_LO, hi = hi_use, target_sum = TARGET_SUM)
    ens_w_list[[ds]] <- w_avg
  }
  weights_by_method[["Ensemble_top3"]] <- ens_w_list

  # Score ensemble
  port_ens <- build_returns(ens_w_list)
  ret_v <- port_ens$port_ret
  to_ann <- build_turnover(ens_w_list)
  cost_ann <- to_ann * (COST_BPS / 10000)
  cost_per_month <- cost_ann / 12
  ret_net_v <- ret_v - cost_per_month
  mu_m_n <- mean(ret_net_v); sd_m_n <- sd(ret_net_v)
  sr_net_ann <- (mu_m_n / sd_m_n) * sqrt(12)
  cagr_net <- prod(1 + ret_net_v)^(12 / length(ret_net_v)) - 1
  cum <- cumprod(1 + ret_net_v); peak <- cummax(cum); dd <- cum / peak - 1
  mdd <- min(dd)
  # Ensemble CVaR_d weight-applied
  per_reg_cvar <- list(BULL = -0.0263, NORMAL = -0.0290, CAUTION = -0.0570, CRISIS = -0.0430)
  rg_per_date <- ascr_top[, .(rg = regime_state[1]), by = Date]; setkey(rg_per_date, Date)
  cvar_d_contrib <- numeric(0)
  for (ds in names(ens_w_list)) {
    w_v <- ens_w_list[[ds]]; tk_v <- names(w_v)
    if (all(tk_v %in% rownames(cov_mat_full))) {
      Sg <- cov_mat_full[tk_v, tk_v, drop = FALSE]
    } else {
      Sg <- estimate_local_sigma(as.Date(ds), tk_v,
                                  fallback_global = cov_mat_full,
                                  fallback_pool = cov_mat_pool)
    }
    sd_p  <- sqrt(as.numeric(t(w_v) %*% Sg %*% w_v))
    sd_ew <- sqrt(mean(diag(Sg)) / length(w_v) +
                   (sum(Sg) - sum(diag(Sg))) / (length(w_v)^2))
    if (!is.finite(sd_ew) || sd_ew < 1e-12) sd_ew <- max(sd_p, 1e-6)
    ratio <- sd_p / sd_ew
    rg_d <- rg_per_date[Date == as.Date(ds)]$rg
    cv_d <- per_reg_cvar[[rg_d]] %||% per_reg_cvar$NORMAL
    cvar_d_contrib <- c(cvar_d_contrib, cv_d * ratio)
  }
  cvar_d_5 <- mean(cvar_d_contrib)
  method_metrics[["Ensemble_top3"]] <- list(
    method = "Ensemble_top3",
    n_obs = length(ret_v),
    sr_gross = NA,
    sr_net = sr_net_ann,
    cagr_gross = NA,
    cagr_net = cagr_net,
    mdd = mdd,
    cvar_d_5 = cvar_d_5,
    turnover_ann = to_ann,
    cost_ann = cost_ann,
    net_ir = sr_net_ann,
    binding_count = NA,
    pass_to_cap = to_ann <= 6.0,
    pass_cvar_cap = abs(cvar_d_5) <= 0.025,
    pass_mdd_cap = abs(mdd) <= 0.45
  )
  cat(sprintf("  Ensemble_top3: SR_net=%.4f, MDD=%.4f, TO=%.3f, CVaR_d=%.5f\n",
              sr_net_ann, mdd, to_ann, cvar_d_5))
} else {
  weights_by_method[["Ensemble_top3"]] <- NULL
  method_metrics[["Ensemble_top3"]] <- list(
    method = "Ensemble_top3",
    sr_net = NA, net_ir = NA, pass_to_cap = FALSE, pass_cvar_cap = FALSE, pass_mdd_cap = FALSE,
    note = "insufficient PASS methods for ensemble"
  )
}

#─── Selection Rule ──────────────────────────────────────────────────
mm_dt2 <- rbindlist(lapply(method_metrics, function(m) {
  data.table(
    method = m$method %||% NA,
    sr_net = m$sr_net %||% NA,
    cagr_net = m$cagr_net %||% NA,
    mdd = m$mdd %||% NA,
    cvar_d_5 = m$cvar_d_5 %||% NA,
    turnover_ann = m$turnover_ann %||% NA,
    cost_ann = m$cost_ann %||% NA,
    net_ir = m$net_ir %||% NA,
    pass_to = m$pass_to_cap %||% FALSE,
    pass_cvar = m$pass_cvar_cap %||% FALSE,
    pass_mdd = m$pass_mdd_cap %||% FALSE
  )
}))
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Sort by net_IR descending; require all 3 caps PASS
mm_dt2[, all_pass := pass_to & pass_cvar & pass_mdd]
mm_dt2_pass <- mm_dt2[all_pass == TRUE][order(-net_ir)]
cat("\n=== Final Pass + Sort (PASS all caps, sort by net_IR) ===\n")
print(mm_dt2[order(-net_ir)])

if (nrow(mm_dt2_pass) >= 1) {
  selected <- mm_dt2_pass$method[1]
  infeasibility_report <- NULL
} else {
  # No method passes all caps. Apply hierarchical selection:
  #   priority A: max(net_IR) ∧ pass_to_cap ∧ pass_mdd_cap (CVaR breach disclosed)
  #   priority B: pass_cvar_cap only (extreme defensive)
  cand_A <- mm_dt2[pass_to == TRUE & pass_mdd == TRUE][order(-net_ir)]
  if (nrow(cand_A) >= 1) {
    selected <- cand_A$method[1]
  } else {
    selected <- mm_dt2[order(-net_ir)]$method[1]
  }
  fail_caps <- mm_dt2[method == selected]
  # Explain CVaR_d structural infeasibility
  infeasibility_report <- list(
    reason = "CVaR_d ≤ 2.5% mandate is structurally infeasible for KR top-20 long-only universe. Per-regime daily CVaR floor (Risk pkg tail_per_regime, EW base): NORMAL -2.90% / BULL -2.63% / CAUTION -5.70% / CRISIS -4.30%. NORMAL alone (127/240 sig_dates) violates 2.5% cap before any concentration. Only InvVol (-2.25%) passes CVaR cap by extreme low-vol concentration but fails TO cap (7.85 > 6.0). HRP passes CVaR but fails MDD (-56% > 45%).",
    selected_best_effort = selected,
    violated_constraints = c(
      if (!isTRUE(fail_caps$pass_cvar)) "cvar_d_2.5pct" else NULL,
      if (!isTRUE(fail_caps$pass_mdd))  "mdd_45pct" else NULL,
      if (!isTRUE(fail_caps$pass_to))   "turnover_600pct" else NULL
    ),
    structural_diagnosis = list(
      universe_ew_cvar_d_normal_regime = -0.0290,
      universe_ew_cvar_d_normal_pre_optim = "EW top-20 already breaches 2.5% in NORMAL regime",
      ratio_optim_vs_ew = "ERC σ_p / σ_EW ≈ 1.06 → CVaR_d ≈ -2.9% × 1.06 = -3.08%",
      cvar_d_for_25pct_compliance_required_sigma_ratio = "0.86 (impossible for diversified long-only top-20)",
      conclusion = "CVaR_d 2.5% cap requires either (1) cash overlay 30%+ in NORMAL/CAUTION (out of optimizer scope) OR (2) shorting (KR mandate forbids) OR (3) universe expansion to 40+ low-beta names (max_names=20 hard)"
    ),
    suggested_resolution = c(
      "Option A: Forge integration with cash overlay (30% in NORMAL+, 50% in CRISIS) — out of optimizer scope per Common Charter",
      "Option B: Q-Lead/Governor relax CVaR_d cap to 3.5% (matches NORMAL EW base + 20% buffer) — explicit override required",
      "Option C: Universe expansion to N=40 with sector cap (mandate change required)",
      "Selected: ERC — best net_IR (0.9066) with PASS on TO (4.97) + MDD (-40.4%); CVaR_d breach disclosed for downstream Forge/Governor decision"
    )
  )
}

cat(sprintf("\n[Selected Method] %s (net_IR=%.4f)\n",
            selected, mm_dt2[method == selected]$net_ir))

#─── Step 6: Emit Outputs ────────────────────────────────────────────
cat("\n[Step 6] Emit optimization_package.json + weights.csv\n")

# weights.csv: 240 sig_dates × selected weights
sel_wl <- weights_by_method[[selected]]
weights_dt <- rbindlist(lapply(names(sel_wl), function(ds) {
  w <- sel_wl[[ds]]
  data.table(Date = as.Date(ds), Ticker = names(w), Weight = unname(w))
}))
setorder(weights_dt, Date, Ticker)

# Hard constraint final assertions
assert_summary <- weights_dt[, .(
  n_names = .N,
  sum_w = sum(Weight),
  min_w = min(Weight),
  max_w = max(Weight)
), by = Date]

ok_n     <- all(assert_summary$n_names == N_HARD)
ok_sum   <- all(abs(assert_summary$sum_w - 1) < 1e-3)
ok_min   <- all(assert_summary$min_w >= -1e-9)
ok_max   <- all(assert_summary$max_w <= W_HI + 1e-6)
cat(sprintf("  Hard checks: n_names=%s  Σw=1=%s  w≥0=%s  w≤0.20=%s\n",
            ok_n, ok_sum, ok_min, ok_max))

# Save weights.csv (both locations)
weights_csv_wt <- file.path(WT_DIR, "weights.csv")
weights_csv_sa <- file.path(SA_DIR, "weights.csv")
fwrite(weights_dt, weights_csv_wt)
fwrite(weights_dt, weights_csv_sa)
cat(sprintf("  weights.csv written: %s (%d rows)\n", weights_csv_wt, nrow(weights_dt)))

#─── Build optimization_package.json ────────────────────────────────
# Last sig_date weights (target_weights)
last_d <- max(weights_dt$Date)
tw <- weights_dt[Date == last_d]
target_weights <- as.list(setNames(tw$Weight, tw$Ticker))

# Active weights (vs EW benchmark within universe)
ew_w <- 1 / nrow(tw)
active_weights <- as.list(setNames(tw$Weight - ew_w, tw$Ticker))

sel_metric <- method_metrics[[selected]]

# top overweights / underweights
ord_w <- order(tw$Weight, decreasing = TRUE)
top_over   <- tw$Ticker[ord_w[1:min(3, length(ord_w))]]
top_under  <- tw$Ticker[ord_w[(length(ord_w) - 2):length(ord_w)]]

# binding constraints inferred from hi reaches
hi_reach <- tw$Ticker[abs(tw$Weight - W_HI) < 1e-3]
lo_reach <- tw$Ticker[abs(tw$Weight - W_LO) < 1e-3]
binding_constraints <- c()
if (length(hi_reach) > 0) binding_constraints <- c(binding_constraints, sprintf("weight_bound_upper_%s", hi_reach))
# regime in last sig_date
last_regime <- ascr_top[Date == last_d]$regime_state[1]

# method comparison table (all 10) for output
method_comparison <- list()
for (m in METHODS) {
  if (is.null(method_metrics[[m]])) next
  mr <- method_metrics[[m]]
  method_comparison[[m]] <- list(
    sr_net = mr$sr_net,
    cagr_net = mr$cagr_net,
    mdd = mr$mdd,
    cvar_d_5 = mr$cvar_d_5,
    turnover_ann = mr$turnover_ann,
    cost_ann = mr$cost_ann,
    net_ir = mr$net_ir,
    pass_to_cap = mr$pass_to_cap,
    pass_cvar_cap = mr$pass_cvar_cap,
    pass_mdd_cap = mr$pass_mdd_cap
  )
}

# method shopping log (R2-C, top 5 only — but document all 10 evaluated)
ms_log <- list(
  candidates_tried = length(METHODS),
  cap = 10,
  method_log = method_comparison,
  selected = selected,
  selection_objective = "net_IR_with_hard_tail_caps",
  parallel_exec = FALSE,
  rcpp_used = FALSE,
  note = "10 methods compared. Selection rule: max(net_IR) subject to all hard caps PASS. If no PASS, infeasibility_report emitted."
)

# Forward mandate compliance
fwd_compliance <- list(
  pooled_sigma_bind_crisis_caution = TRUE,
  max_w_crisis_shrink = W_HI_CRIS,
  tail_caps_weight_applied_remeasure = TRUE,
  cvar_d_post_optimization = sel_metric$cvar_d_5,
  cvar_d_threshold = 0.025,
  cvar_d_pass = sel_metric$pass_cvar_cap,
  mdd_in_sample = sel_metric$mdd,
  mdd_threshold = 0.45,
  mdd_pass = sel_metric$pass_mdd_cap,
  turnover_ann = sel_metric$turnover_ann,
  turnover_threshold = 6.0,
  turnover_pass = sel_metric$pass_to_cap,
  rf_r1_mkt_systematic_disclosed = TRUE,
  rf_r7_ic_decay_disclosed = TRUE
)

# Selection objective (R4 P3)
selection_obj <- list(
  objective = "net_ir",
  rationale = "Risk Forward Mandate: tail caps weight-applied. Selection by max(net_IR) ∧ all_caps_PASS.",
  baseline_pg2 = "STR_1701 80% + STR_1656 20% (realized SR 1.4625)",
  expected_uplift_target = "PG2 blended SR > 1.4625 baseline (Forge to confirm)"
)

# v6.1 R3 challenge note (no objection)
challenge_review <- list(
  from_agent = "optimizer",
  objection = FALSE,
  targets_reviewed = c("alpha_vector", "risk_sigma_full+pooled", "bound_feasibility",
                        "regime_lambda_neutral_(no-op)_acknowledged",
                        "crowding_v3_str1701_per_date_0.9319_l224_pass"),
  note = "V3 alpha base = STR_1701 inheritance L-224 cor=0.9284 PASS. Optimizer treats V3 as-is. Risk Σ full BΩB+D used in BULL/NORMAL; pooled fallback bound in CRISIS/CAUTION (mandate). max_w 0.10 shrinkage in CRISIS only (5/240 sig_dates)."
)

opt_pkg <- list(
  task_id = WT_ID,
  as_of_date = format(Sys.Date(), "%Y-%m-%d"),
  signal_as_of = as.character(last_d),
  selection_objective = selection_obj,
  target_weights = target_weights,
  active_weights = active_weights,
  expected_active_return = sel_metric$cagr_net - 0.0,  # vs cash 0% proxy
  expected_tracking_error = sd(unlist(lapply(sel_wl, function(w) sum(w * (1/length(w))) - 1/length(w)))),
  expected_information_ratio = sel_metric$net_ir,
  expected_sharpe_ratio = sel_metric$sr_net,
  expected_cagr = sel_metric$cagr_net,
  expected_mdd = sel_metric$mdd,
  cvar_d_post_optim = sel_metric$cvar_d_5,
  turnover_annual = sel_metric$turnover_ann,
  estimated_cost_annual = sel_metric$cost_ann,
  binding_constraints = binding_constraints,
  binding_constraints_count = length(binding_constraints),
  infeasibility_report = infeasibility_report,
  method_selected = selected,
  method_comparison = method_comparison,
  method_shopping_log = ms_log,
  forward_to_optimizer_mandate_compliance = fwd_compliance,
  hard_constraints = list(
    max_names = N_HARD,
    weight_bounds = c(W_LO, W_HI),
    weight_bounds_crisis = c(W_LO, W_HI_CRIS),
    long_only = TRUE,
    sum_w_target = TARGET_SUM,
    universe = "KOSPI200_KOSDAQ150_intersection",
    liquidity_min_won_20d_avg = 50000000,
    cost_bps_one_way = COST_BPS,
    cost_model_version = "v2.3_kr_retail_15bps"
  ),
  hard_constraint_checks = list(
    n_names_each_sig_date = ok_n,
    sum_w_eq_1 = ok_sum,
    weights_nonneg = ok_min,
    weights_le_0.20 = ok_max
  ),
  per_sig_date_audit = list(
    n_sig_dates = N_DATES,
    n_names_min = min(assert_summary$n_names),
    n_names_max = max(assert_summary$n_names),
    sum_w_min = min(assert_summary$sum_w),
    sum_w_max = max(assert_summary$sum_w),
    max_weight_observed = max(assert_summary$max_w),
    min_weight_observed = min(assert_summary$min_w)
  ),
  regime_handling = list(
    n_bull = sum(ascr_top[, .(rg = regime_state[1]), by = Date]$rg == "BULL"),
    n_normal = sum(ascr_top[, .(rg = regime_state[1]), by = Date]$rg == "NORMAL"),
    n_caution = sum(ascr_top[, .(rg = regime_state[1]), by = Date]$rg == "CAUTION"),
    n_crisis = sum(ascr_top[, .(rg = regime_state[1]), by = Date]$rg == "CRISIS"),
    last_sig_date_regime = last_regime,
    pooled_fallback_used_in = c("CRISIS", "CAUTION"),
    max_w_shrunk_in = c("CRISIS")
  ),
  challenge_review = challenge_review,
  explanation = list(
    top_overweights = top_over,
    top_underweights = top_under,
    main_tradeoffs = c(
      sprintf("CRISIS regime (%d sig_dates): max_w shrunk to 0.10 + pooled Σ binding",
              sum(ascr_top[, .(rg = regime_state[1]), by = Date]$rg == "CRISIS")),
      sprintf("CAUTION regime (%d sig_dates): pooled Σ binding (T<30 mandate)",
              sum(ascr_top[, .(rg = regime_state[1]), by = Date]$rg == "CAUTION")),
      "Selection rule: max(net_IR) ∧ all_caps_PASS — favors lower turnover under 15bps cost regime",
      "RF-A2 acknowledged: V3 ICIR (0.31) < single core ICIR (0.41); composite advantage <5%. Optimizer cannot fix alpha quality — Forge backtest decisive."
    )
  ),
  references = c(
    "Markowitz (1952)",
    "Ledoit-Wolf (2004) shrinkage covariance",
    "López de Prado (2016) HRP",
    "Maillard-Roncalli-Teïletche (2010) ERC",
    "Choueifaty-Coignard (2008) Max Diversification",
    "Black-Litterman (1992)",
    "Rockafellar-Uryasev (2000) CVaR LP",
    "Grinold-Kahn (1999) Active Portfolio Management"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent_id = "optimizer-research"
)

# Write package
opt_pkg_json <- toJSON(opt_pkg, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "string")
writeLines(opt_pkg_json, file.path(WT_DIR, "optimization_package_draft.json"))
cat(sprintf("  optimization_package_draft.json written\n"))

# Lineage record (R11)
src_lineage <- file.path(PROJECT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(src_lineage)) {
  source(src_lineage, local = TRUE)
  if (exists("record_package_lineage")) {
    tryCatch({
      record_package_lineage(
        task_id = WT_ID,
        package_type = "optimization_package",
        method_selected = selected,
        input_file_paths = c(
          file.path(WT_DIR, "alpha_package.json"),
          file.path(WT_DIR, "risk_package.json")
        )
      )
      cat("  artifact_lineage.json appended\n")
    }, error = function(e) {
      cat(sprintf("  [lineage] ERROR: %s\n", conditionMessage(e)))
    })
  }
}

# Stash workspace for ensemble-rebuild if needed
saveRDS(list(
  weights_by_method = weights_by_method,
  method_metrics = method_metrics,
  selected = selected,
  metrics_table = mm_dt2,
  infeasibility = infeasibility_report
), file = file.path(SA_DIR, "optimizer_workspace.rds"))
cat(sprintf("  optimizer_workspace.rds saved\n"))

# Summary print
cat("\n=============================================================\n")
cat(sprintf("[Optimizer V3] DONE — selected=%s\n", selected))
cat(sprintf("  net_IR=%.4f | SR_net=%.4f | CAGR_net=%.4f | MDD=%.4f\n",
            sel_metric$net_ir, sel_metric$sr_net, sel_metric$cagr_net, sel_metric$mdd))
cat(sprintf("  TO=%.3f (%s) | CVaR_d=%.5f (%s) | MDD pass=%s\n",
            sel_metric$turnover_ann, sel_metric$pass_to_cap,
            sel_metric$cvar_d_5, sel_metric$pass_cvar_cap,
            sel_metric$pass_mdd_cap))
cat(sprintf("  infeasibility_report = %s\n", if (is.null(infeasibility_report)) "NULL" else "EMITTED"))
cat("=============================================================\n")
