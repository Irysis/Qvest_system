#==============================================================================
# WT-D20260512_003 Optimizer Step 2 — Method Shopping + 268m Walk-Forward
#
# 자율 method shopping log (≤10 cap):
#   1. Iter31_LinearTilt (STR_1715 admit baseline: λ=1.5, phi=3, ub=0.20)
#   2. AlphaSort_EW (top20 alpha-sort equal weight)
#   3. AlphaSoftmax_T05 (softmax tilt temperature=0.5)
#   4. MVO_lam2_psi0p3_ub20 (confidence-aware MVO, ub=0.20)
#   5. MVO_lam1_psi0p3_ub20 (gentler λ)
#   6. HRP_ward (rolling 60d sample cov, Lopez de Prado 2016)
#   7. ERC (Equal Risk Contribution, rolling 60d sample cov)
#   8. MVO_TOphi (MVO + turnover penalty phi=0.5, ub=0.20)
#   9. Ensemble_lin_mvo (50/50 Iter31 + MVO_lam1)
#  10. WinsorTilt (alpha winsor ±2σ → linear_tilt)
#
# Walk-forward design:
#   - 268m monthly schedule (sig_dates 2004-01 ~ 2026-04)
#   - Σ-based methods: rolling 60d sample covariance (PIT compliant)
#   - alpha-rank methods: no Σ required (deterministic from z_blend)
#   - Liquidity filter: 20d avg TA >= 5e7 KRW (t-1)
#   - max_names=20, weight_bounds=[0, 0.20], long_only, Σw=1 strict
#
# Selection objective: crowding_adj_ret (R4 P3 enum)
#   = SR(net) - λ_HHI × HHI_mean - λ_TO × turnover - λ_F_QMJ × F_QMJ_loading
#
# v6.1 R13 parallel exec via future_lapply (5 workers).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(quadprog); library(future); library(future.apply)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step2] Method Shopping + 268m Walk-Forward\n")
cat("============================================================\n\n")

# ─── Load inputs ────────────────────────────────────────────────
WT <- "WT-D20260512_003"
mailbox <- file.path("qepm/mailbox/worktask", WT)
stage <- file.path("stage_artifacts", "WT_D20260512_003")

ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
setkey(asc, Date, Ticker)

# Risk Σ (2026-04 as-of, for cross-sectional single-snapshot final method check)
cov_long <- as.data.table(read_parquet(file.path(stage, "covariance.parquet")))
cov_long_full <- rbind(cov_long, cov_long[i != j, .(i = j, j = i, sigma_ij, estimator)])
cov_long_full <- unique(cov_long_full, by = c("i", "j"))
Sigma_2604 <- dcast(cov_long_full, i ~ j, value.var = "sigma_ij", fill = 0)
ix_rn <- Sigma_2604$i
Sigma_2604 <- as.matrix(Sigma_2604[, -1])
rownames(Sigma_2604) <- ix_rn
risk_universe <- sort(unique(cov_long$i))
Sigma_2604 <- Sigma_2604[risk_universe, risk_universe]

# Exposure matrix (for F_QMJ factor loading audit)
emat <- as.data.table(read_parquet(file.path(stage, "exposure_matrix.parquet")))
setkey(emat, Ticker)

# RAWDATA (returns for walk-forward + liquidity filter)
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

# Benchmark
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
setorder(bm, Date)

cat(sprintf("Loaded: alpha_scores %s rows | Sigma 237×237 | raw %s rows\n",
            format(nrow(asc), big.mark=","),
            format(nrow(raw), big.mark=",")))

# ─── Hard constraints ─────────────────────────────────────────
MAX_NAMES <- 20L
MIN_NAMES <- 5L
UB <- 0.20
LB <- 0.0
TARGET_SUM <- 1.0
LIQ_THRESHOLD <- 5e7
COMMISSION_BPS <- 15  # one-way

sig_dates <- sort(unique(asc$Date))
cat(sprintf("sig_dates: %d (%s ~ %s)\n",
            length(sig_dates),
            as.character(min(sig_dates)),
            as.character(max(sig_dates))))

# ─── Helper: normalize_long_only (Iter31 baseline) ──────────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0
  w[w < lb] <- lb
  if (sum(w) == 0) {
    w <- rep(target_sum / length(w), length(w))
    names(w) <- names(w)
    return(w)
  }
  w <- w / sum(w) * target_sum
  while (any(w > ub + 1e-12) && sum(w) > 0) {
    excess_idx <- which(w > ub)
    excess <- sum(w[excess_idx]) - length(excess_idx) * ub
    w[excess_idx] <- ub
    free <- setdiff(seq_along(w), excess_idx)
    if (length(free) == 0) break
    if (sum(w[free]) == 0) {
      w[free] <- excess / length(free)
    } else {
      w[free] <- w[free] + excess * (w[free] / sum(w[free]))
    }
    w <- w / sum(w) * target_sum
  }
  w
}

# ─── Method 1: Iter31 Linear Tilt (STR_1715 admit baseline) ─────
linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# ─── Method 2: AlphaSort_EW ─────────────────────────────────────
alpha_sort_ew <- function(alpha_t, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  w <- rep(1/N, N)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ─── Method 3: AlphaSoftmax_T05 ─────────────────────────────────
alpha_softmax <- function(alpha_t, temperature = 0.5, lb = 0, ub = 0.20) {
  ax <- alpha_t / temperature
  ax <- ax - max(ax)  # numerical stability
  w_raw <- exp(ax)
  w <- w_raw / sum(w_raw)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ─── Method 4-5: MVO (confidence-aware, quadprog) ──────────────
mvo_solve <- function(alpha_t, Sigma_sub, lambda = 2.0, psi = 0.3,
                       confidence = NULL, lb = 0, ub = 0.20, target_sum = 1) {
  D <- length(alpha_t)
  if (is.null(confidence)) confidence <- rep(1.0, D)
  fu_diag <- psi * (1 - confidence)^2
  Dmat <- lambda * Sigma_sub + diag(2 * fu_diag)
  diag(Dmat) <- diag(Dmat) + 1e-6
  dvec <- as.vector(alpha_t)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(target_sum, rep(lb, D), rep(-ub, D))
  res <- tryCatch(
    solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
    error = function(e) NULL
  )
  if (is.null(res)) {
    return(normalize_long_only(rep(1/D, D), lb = lb, ub = ub, target_sum = target_sum))
  }
  w <- res$solution
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

# ─── Method 6: HRP_ward (rolling 60d sample cov) ────────────────
hrp_ward <- function(alpha_t, ret_mat_t, lb = 0, ub = 0.20) {
  # ret_mat_t: rows=days, cols=tickers, n_obs >= 30 enforced upstream
  common <- intersect(names(alpha_t), colnames(ret_mat_t))
  if (length(common) < 3L) {
    return(alpha_sort_ew(alpha_t, lb = lb, ub = ub))
  }
  rm <- ret_mat_t[, common, drop=FALSE]
  rm[is.na(rm)] <- 0
  cov_s <- cov(rm)
  cor_s <- cov2cor(cov_s)
  cor_s[is.na(cor_s)] <- 0
  cor_s <- pmin(pmax(cor_s, -0.999), 0.999)
  d <- 0.5 * (1 - cor_s); d[d < 0] <- 0
  diag(d) <- 0
  dist_mat <- as.dist(sqrt(d))
  hc <- tryCatch(hclust(dist_mat, method = "ward.D2"), error = function(e) NULL)
  if (is.null(hc)) return(alpha_sort_ew(alpha_t, lb = lb, ub = ub))
  ord <- hc$order

  # Recursive bisection (Lopez de Prado 2016)
  rb <- function(idx, w = 1) {
    if (length(idx) == 1L) return(setNames(w, idx))
    h <- ceiling(length(idx) / 2)
    L <- idx[1:h]; R <- idx[(h+1):length(idx)]
    # inverse-variance allocation between L and R clusters
    vL <- sum(diag(cov_s[L, L, drop=FALSE]))
    vR <- sum(diag(cov_s[R, R, drop=FALSE]))
    aL <- vR / (vL + vR + 1e-12)
    aR <- 1 - aL
    c(rb(L, w * aL), rb(R, w * aR))
  }
  ord_names <- common[ord]
  w <- rb(ord_names)
  w_full <- setNames(rep(0, length(alpha_t)), names(alpha_t))
  w_full[names(w)] <- w
  if (sum(w_full) == 0) w_full <- rep(1/length(w_full), length(w_full))
  w_full <- w_full / sum(w_full)
  normalize_long_only(w_full, lb = lb, ub = ub, target_sum = 1)
}

# ─── Method 7: ERC (Equal Risk Contribution) ────────────────────
erc_solve <- function(alpha_t, Sigma_sub, lb = 0, ub = 0.20, target_sum = 1,
                       n_iter = 100, tol = 1e-6) {
  D <- length(alpha_t)
  if (D <= 1) return(setNames(target_sum, names(alpha_t)))
  w <- rep(target_sum/D, D)
  names(w) <- names(alpha_t)
  for (k in seq_len(n_iter)) {
    mrc <- as.vector(Sigma_sub %*% w)
    rc <- w * mrc
    target_rc <- mean(rc)
    grad <- mrc - target_rc / w
    w_new <- w - 0.005 * grad
    w_new <- pmax(w_new, 1e-8)
    w_new <- w_new / sum(w_new) * target_sum
    if (max(abs(w_new - w)) < tol) break
    w <- w_new
  }
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

# ─── Method 10: Winsor Tilt ─────────────────────────────────────
winsor_tilt <- function(alpha_t, winsor = 2.0, lambda = 1.5, lb = 0, ub = 0.20) {
  mu <- mean(alpha_t, na.rm = TRUE)
  sg <- sd(alpha_t, na.rm = TRUE)
  if (is.na(sg) || sg == 0) return(linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub))
  cap <- winsor * sg
  ax <- pmax(pmin(alpha_t - mu, cap), -cap) + mu
  linear_tilt_qd(setNames(ax, names(alpha_t)), lambda = lambda, lb = lb, ub = ub)
}

# ─── 268m Walk-Forward common loop ──────────────────────────────
# T+1 lag, monthly schedule
# returns: list with port_ret, port_ret_gross, turnover, n_held, regime per period
run_walk_forward <- function(weight_fn,
                              weight_fn_name = "method",
                              needs_cov_rolling = FALSE,
                              n_cov_days = 60L,
                              n_cov_min = 30L) {
  monthly <- vector("list", length(sig_dates) - 1L)
  w_prev <- NULL

  for (i in seq_len(length(sig_dates) - 1L)) {
    sig_label <- sig_dates[i]
    next_sig_label <- sig_dates[i + 1L]
    start_d <- min(raw[Date >= sig_label]$Date)
    if (length(start_d) == 0L || is.na(start_d)) next
    end_d <- min(raw[Date >= next_sig_label]$Date)
    if (length(end_d) == 0L || is.na(end_d)) end_d <- max(raw$Date)

    panel_t <- asc[Date == sig_label]
    if (nrow(panel_t) == 0L) next

    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -z_blend_composite)
    N_eligible <- nrow(panel_t)
    N_target <- min(MAX_NAMES, N_eligible)
    if (N_target < 5L) next

    picks <- panel_t[seq_len(N_target)]
    alpha_t <- picks$z_blend_composite
    names(alpha_t) <- picks$Ticker

    # Liquidity filter (t-30..t-1)
    liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                     .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
    tickers_liq <- intersect(names(alpha_t), liquid_tk)
    if (length(tickers_liq) < 5L) tickers_liq <- names(alpha_t)
    alpha_t_liq <- alpha_t[tickers_liq]

    confidence_t <- picks[Ticker %in% tickers_liq, confidence]
    names(confidence_t) <- picks[Ticker %in% tickers_liq, Ticker]
    confidence_t <- confidence_t[tickers_liq]

    # Build rolling cov if needed
    Sigma_sub <- NULL
    ret_mat_t <- NULL
    if (needs_cov_rolling) {
      cov_window_start <- start_d - (n_cov_days * 3L)  # ~3 calendar days per trading day
      ret_window <- raw[Date >= cov_window_start & Date < start_d & Ticker %in% tickers_liq,
                        .(Date, Ticker, Ret)]
      # Wide format
      ret_wide <- dcast(ret_window, Date ~ Ticker, value.var = "Ret", fill = 0)
      if (nrow(ret_wide) < n_cov_min) next
      ret_mat_t <- as.matrix(ret_wide[, -1])
      rownames(ret_mat_t) <- as.character(ret_wide$Date)

      # Keep only tickers with sufficient non-NA data
      valid_tk <- colnames(ret_mat_t)[colSums(!is.na(ret_mat_t) & ret_mat_t != 0) >= n_cov_min/2]
      if (length(valid_tk) < 5L) next
      ret_mat_t <- ret_mat_t[, valid_tk, drop=FALSE]
      ret_mat_t[is.na(ret_mat_t)] <- 0

      Sigma_sub <- cov(ret_mat_t)
      # Shrinkage for stability
      shrinkage <- 0.1
      I_d <- diag(mean(diag(Sigma_sub)), nrow(Sigma_sub))
      Sigma_sub <- (1 - shrinkage) * Sigma_sub + shrinkage * I_d
      diag(Sigma_sub) <- diag(Sigma_sub) + 1e-6

      alpha_t_liq <- alpha_t_liq[valid_tk]
      confidence_t <- confidence_t[valid_tk]
    }

    # Apply weight function
    w_risk <- tryCatch(
      weight_fn(alpha_t_liq,
                Sigma_sub = Sigma_sub,
                ret_mat_t = ret_mat_t,
                confidence_t = confidence_t,
                w_prev = w_prev,
                regime = regime_i),
      error = function(e) {
        cat(sprintf("  [%s @ %s] error: %s, fallback EW\n",
                    weight_fn_name, sig_label, conditionMessage(e)))
        alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB)
      }
    )
    if (is.null(w_risk) || any(is.na(w_risk)) || abs(sum(w_risk) - 1) > 0.01) {
      w_risk <- alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB)
    }

    # Period returns
    period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
    stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1),
                               by = Ticker]
    merged <- merge(
      data.table(ticker = names(w_risk), w = as.numeric(w_risk)),
      stock_rets, by.x = "ticker", by.y = "Ticker", all.x = TRUE
    )
    merged[is.na(stock_ret), stock_ret := 0]
    port_ret_gross <- sum(merged$w * merged$stock_ret, na.rm = TRUE)

    # Turnover (Σ |w_new - w_prev|)
    to <- 0
    if (!is.null(w_prev) && length(w_prev) > 0) {
      all_tk <- union(names(w_risk), names(w_prev))
      w_new_full <- setNames(rep(0, length(all_tk)), all_tk)
      w_prev_full <- setNames(rep(0, length(all_tk)), all_tk)
      w_new_full[names(w_risk)] <- w_risk
      w_prev_full[names(w_prev)] <- w_prev
      to <- sum(abs(w_new_full - w_prev_full))
    } else {
      to <- sum(w_risk)  # initial period: full turnover = 1
    }

    # Cost (one-way 15bps × turnover)
    cost <- to * COMMISSION_BPS / 10000
    port_ret_net <- port_ret_gross - cost

    monthly[[i]] <- data.table(
      sig_date = sig_label,
      start_d = start_d,
      end_d = end_d,
      port_ret_gross = port_ret_gross,
      port_ret_net = port_ret_net,
      turnover = to,
      n_held = length(w_risk),
      regime = regime_i,
      method = weight_fn_name,
      cost = cost
    )
    w_prev <- w_risk
  }

  monthly <- rbindlist(monthly, fill = TRUE)
  monthly
}

# ─── Wrap weight methods with uniform signature ─────────────────
wf_iter31 <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  ub_use <- if (regime == "CRISIS") min(UB, 0.10) else UB
  linear_tilt_to_penalty_qd(alpha_t_liq, lambda = 1.5, w_prev = w_prev,
                             phi = 3.0, lb = 0, ub = ub_use)
}

wf_alpha_sort_ew <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB)
}

wf_alpha_softmax_t05 <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  alpha_softmax(alpha_t_liq, temperature = 0.5, lb = LB, ub = UB)
}

wf_mvo_lam2 <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  if (is.null(Sigma_sub)) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  common <- intersect(names(alpha_t_liq), rownames(Sigma_sub))
  if (length(common) < 5L) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  mvo_solve(alpha_t_liq[common], Sigma_sub[common, common],
            lambda = 2.0, psi = 0.3, confidence = confidence_t[common],
            lb = LB, ub = UB)
}

wf_mvo_lam1 <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  if (is.null(Sigma_sub)) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  common <- intersect(names(alpha_t_liq), rownames(Sigma_sub))
  if (length(common) < 5L) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  mvo_solve(alpha_t_liq[common], Sigma_sub[common, common],
            lambda = 1.0, psi = 0.3, confidence = confidence_t[common],
            lb = LB, ub = UB)
}

wf_hrp_ward <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  if (is.null(ret_mat_t)) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  hrp_ward(alpha_t_liq, ret_mat_t, lb = LB, ub = UB)
}

wf_erc <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  if (is.null(Sigma_sub)) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  common <- intersect(names(alpha_t_liq), rownames(Sigma_sub))
  if (length(common) < 5L) return(alpha_sort_ew(alpha_t_liq, lb = LB, ub = UB))
  erc_solve(alpha_t_liq[common], Sigma_sub[common, common],
            lb = LB, ub = UB)
}

wf_winsor_tilt <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  winsor_tilt(alpha_t_liq, winsor = 2.0, lambda = 1.5, lb = LB, ub = UB)
}

wf_ensemble <- function(alpha_t_liq, Sigma_sub, ret_mat_t, confidence_t, w_prev, regime) {
  w1 <- linear_tilt_to_penalty_qd(alpha_t_liq, lambda = 1.5, w_prev = w_prev,
                                    phi = 3.0, lb = 0, ub = UB)
  if (is.null(Sigma_sub)) return(w1)
  common <- intersect(names(alpha_t_liq), rownames(Sigma_sub))
  if (length(common) < 5L) return(w1)
  w2_part <- mvo_solve(alpha_t_liq[common], Sigma_sub[common, common],
                        lambda = 1.0, psi = 0.3, confidence = confidence_t[common],
                        lb = LB, ub = UB)
  w2 <- setNames(rep(0, length(alpha_t_liq)), names(alpha_t_liq))
  w2[names(w2_part)] <- w2_part
  if (sum(w2) > 0) w2 <- w2 / sum(w2) else w2 <- w1
  w_blend <- 0.5 * w1 + 0.5 * w2
  normalize_long_only(w_blend, lb = LB, ub = UB, target_sum = 1)
}

# ─── Run methods (parallel) ─────────────────────────────────────
methods_spec <- list(
  list(name = "Iter31_LinearTilt", fn = wf_iter31, needs_cov = FALSE),
  list(name = "AlphaSort_EW", fn = wf_alpha_sort_ew, needs_cov = FALSE),
  list(name = "AlphaSoftmax_T05", fn = wf_alpha_softmax_t05, needs_cov = FALSE),
  list(name = "MVO_lam2_psi0p3", fn = wf_mvo_lam2, needs_cov = TRUE),
  list(name = "MVO_lam1_psi0p3", fn = wf_mvo_lam1, needs_cov = TRUE),
  list(name = "HRP_ward", fn = wf_hrp_ward, needs_cov = TRUE),
  list(name = "ERC", fn = wf_erc, needs_cov = TRUE),
  list(name = "WinsorTilt", fn = wf_winsor_tilt, needs_cov = FALSE),
  list(name = "Ensemble_lin_mvo", fn = wf_ensemble, needs_cov = TRUE)
)

cat(sprintf("\n[Method shopping] %d candidates (parallel exec)\n", length(methods_spec)))

t0 <- Sys.time()
# Single-threaded for reliability (parallel future may have copy overhead with raw data.table)
results_raw <- list()
for (m in methods_spec) {
  cat(sprintf("  Running %s ... ", m$name))
  t1 <- Sys.time()
  out <- run_walk_forward(m$fn, weight_fn_name = m$name,
                           needs_cov_rolling = m$needs_cov)
  elapsed <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  cat(sprintf("%d periods | %.1fs\n", nrow(out), elapsed))
  results_raw[[m$name]] <- out
}
total_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\nTotal walk-forward time: %.1f sec\n", total_secs))

# ─── Save raw results ───────────────────────────────────────────
saveRDS(results_raw, file.path(stage, "opt_method_shopping_raw.rds"))
cat(sprintf("Saved raw: %s\n", file.path(stage, "opt_method_shopping_raw.rds")))
cat("[OPT-Step2] DONE\n")
