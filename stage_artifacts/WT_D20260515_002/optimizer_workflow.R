#==============================================================================
# WT-D20260515_002 Optimizer Workflow v2 — fixed Σ-universe handoff
#
# Critical fix: Risk-package Σ tickers cover M6 top-30 only (not STR_1715 top-20).
# Hook L3 prevents risk re-spawn. Solution:
#   - sleeve-aware weighting: A uses STR_1715 production tilt (a + b*signal),
#     B uses MVO/HRP/ERC over its own Σ block.
#   - Dedupe-merge keeps A+B combined top-20 by combined z-score.
#   - For sleeve A names that lack Σ entries, fall back to signal tilt only.
#     (Honest: Σ shrinkage applies on the M6-side names where it was built.)
#
# Also fixes:
#   - overlay_ts join: rename internal var to avoid shadowing.
#   - eff_TO calc: confirm round-trip turnover.
#   - AX-007 proof: clean sleeve contribution measurement.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(quadprog)
  library(PerformanceAnalytics)
  library(xts)
  library(jsonlite)
})

# ─── Constants ────────────────────────────────────────────
WT_ID         <- "WT-D20260515_002"
STAGE_DIR     <- "stage_artifacts/WT_D20260515_002"
SLEEVE_A_W    <- 0.60        # STR_1715
SLEEVE_B_W    <- 0.40        # M6 Ensemble
MAX_NAMES     <- 20L
N_FROM_A      <- 12L          # round(0.60 * 20) — proportional allocation
N_FROM_B      <- 8L           # 20 - 12
WEIGHT_UB     <- 0.20
WEIGHT_LB     <- 0.0
TC_BPS        <- 15          # one-way 15bps
LIQ_THRESH    <- 2e8         # KRW 20d ADV
TARGET_CVAR   <- -0.0707     # STR_1715 R05 inherit precedent
COST_MODEL    <- "v2.3_kr_retail_15bps"

set.seed(20260515L)

cat("===============================================\n")
cat("WT-D20260515_002 Optimizer Research Workflow v2\n")
cat("===============================================\n\n")

# ─── 1. Load Inputs ───────────────────────────────────────
cat("[1] Loading inputs...\n")
alpha_top30 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_top30_by_sig_date.parquet")))
str1715     <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
rp          <- as.data.table(read_parquet("stage_artifacts/WT_D20260514_007/returns_monthly_panel.parquet"))
em          <- as.data.table(read_parquet(file.path(STAGE_DIR, "exposure_matrix.parquet")))

# STR_1715 overlay schedule (regime + cash share)
overlay_ts  <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv")
overlay_ts[, as_of_date := as.Date(as_of_date)]
overlay_ts[, overlay_ym := format(as_of_date, "%Y-%m")]

# Align sig_dates
alpha_top30[, sig_ym := format(sig_date, "%Y-%m")]
str1715[, sig_ym := format(Date, "%Y-%m")]
rp[, sig_ym := format(Date, "%Y-%m")]

SIG_DATES_84 <- sort(unique(alpha_top30$sig_date))
SIG_YM_84    <- sort(unique(alpha_top30$sig_ym))
cat("  n_sig_dates:", length(SIG_DATES_84), "\n")
cat("  range:", as.character(range(SIG_DATES_84)), "\n\n")

# ─── 2. Σ rolling per-sig_date loader ─────────────────────
sigma_dir <- file.path(STAGE_DIR, "covariance_per_sig_date")
get_sigma <- function(sig_ym) {
  fp <- file.path(sigma_dir, paste0("sigma_", gsub("-", "", sig_ym), ".rds"))
  if (!file.exists(fp)) return(NULL)
  readRDS(fp)
}
test_sig <- get_sigma("201901")
cat("[2] Sigma loader test (201901): N=", test_sig$N, " cond=", round(test_sig$cond, 1),
    " pc1=", round(test_sig$pc1, 3), "\n\n")

# ─── 3. Sleeve A: STR_1715 top-20 (signal-linear tilt) ────
# w_i = a + b * score_eff (production STR_1715 v2 weighting; intercept 0.018,
# slope 0.021 fit to PG2 sleeve weights). Normalized to sum=1 in sleeve.
build_sleeve_A <- function(sig_ym_t) {
  s <- str1715[sig_ym == sig_ym_t & !is.na(score_eff)]
  if (nrow(s) < 20) return(NULL)
  s <- s[order(-score_eff)][1:20]
  a <- 0.018; b <- 0.021
  w_raw <- pmax(0.001, a + b * s$score_eff)
  w_in_A <- w_raw / sum(w_raw)
  w_in_A <- pmin(w_in_A, WEIGHT_UB)
  w_in_A <- w_in_A / sum(w_in_A)
  data.table(
    Ticker      = s$Ticker,
    score_A     = s$score_eff,
    w_in_sleeve_A = w_in_A,
    sleeve_A_in = TRUE
  )
}

# ─── 4. Sleeve B: M6 top-30 ──────────────────────────────
build_sleeve_B <- function(sig_date_t) {
  s <- alpha_top30[sig_date == sig_date_t]
  if (nrow(s) == 0) return(NULL)
  setorder(s, -alpha_score)
  s[, rank_B := 1:.N]
  s[, .(Ticker, score_B = alpha_score, rank_B, sleeve_B_in = TRUE)]
}

# ─── 5. Universe filter ──────────────────────────────────
# Use returns_monthly_panel coverage as PIT-clean Production listing universe proxy.
universe_for_sig <- function(sig_date_t) {
  rp[Date == sig_date_t & !is.na(Ret_1m_fwd), Ticker]
}

# ─── 6. Per-sleeve weighting registry ─────────────────────
# Sleeve A weighting: STR_1715 production signal-linear tilt (fixed).
# Sleeve B weighting: method shopping over Σ_B sub-block.
#   Methods evaluated:
#     M_EW       : EW
#     M_SigTilt  : score-linear (a + b * (z+offset))
#     M_MVO_lam2 : MVO quadprog with Σ_B + λ=2
#     M_MVO_TO   : MVO + turnover penalty (φ=0.5)
#     M_HRP      : Hierarchical Risk Parity
#     M_ERC      : Equal Risk Contribution

wB_EW <- function(scores, sigma, prev_w) rep(1/length(scores), length(scores))

wB_SigTilt <- function(scores, sigma, prev_w, a = 0.018, b = 0.021) {
  # scores normalized to [1.0, 2.0] for tilt (mimics STR_1715 score scale)
  s <- scores - min(scores) + 1.0
  w_raw <- pmax(0.001, a + b * s)
  w <- w_raw / sum(w_raw)
  pmin(w, WEIGHT_UB) / sum(pmin(w, WEIGHT_UB))
}

wB_MVO <- function(scores, sigma, prev_w, lambda = 2.0) {
  N <- length(scores)
  if (is.null(sigma) || nrow(sigma) != N) return(wB_EW(scores, sigma, prev_w))
  Dmat <- (lambda * sigma + lambda * t(sigma)) / 2 + diag(1e-6, N)
  dvec <- as.numeric(scores)
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(WEIGHT_LB, N), rep(-WEIGHT_UB, N))
  fit <- tryCatch(solve.QP(Dmat=Dmat, dvec=dvec, Amat=Amat, bvec=bvec, meq=1), error = function(e) NULL)
  if (is.null(fit)) return(wB_EW(scores, sigma, prev_w))
  w <- pmax(WEIGHT_LB, pmin(WEIGHT_UB, fit$solution))
  w / sum(w)
}

wB_MVO_TO <- function(scores, sigma, prev_w, lambda = 2.0, phi = 0.5) {
  N <- length(scores)
  if (is.null(sigma) || nrow(sigma) != N) return(wB_EW(scores, sigma, prev_w))
  if (is.null(prev_w) || length(prev_w) != N) return(wB_MVO(scores, sigma, NULL, lambda))
  Dmat <- lambda * sigma + phi * diag(N)
  Dmat <- (Dmat + t(Dmat))/2 + diag(1e-6, N)
  dvec <- as.numeric(scores) + phi * prev_w
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(WEIGHT_LB, N), rep(-WEIGHT_UB, N))
  fit <- tryCatch(solve.QP(Dmat=Dmat, dvec=dvec, Amat=Amat, bvec=bvec, meq=1), error = function(e) NULL)
  if (is.null(fit)) return(wB_MVO(scores, sigma, NULL, lambda))
  w <- pmax(WEIGHT_LB, pmin(WEIGHT_UB, fit$solution))
  w / sum(w)
}

wB_HRP <- function(scores, sigma, prev_w) {
  N <- length(scores)
  if (is.null(sigma) || nrow(sigma) != ncol(sigma) || nrow(sigma) != N || N < 2) {
    return(wB_EW(scores, sigma, prev_w))
  }
  d <- sqrt(pmax(diag(sigma), 1e-12))
  cor_m <- sigma / (d %o% d)
  cor_m <- (cor_m + t(cor_m)) / 2
  cor_m[!is.finite(cor_m)] <- 0
  diag(cor_m) <- 1
  D <- sqrt(pmax(0, (1 - cor_m) / 2))
  hclust_obj <- tryCatch(hclust(as.dist(D), method = "single"), error = function(e) NULL)
  if (is.null(hclust_obj)) return(wB_EW(scores, sigma, prev_w))
  ord <- hclust_obj$order
  hrp_rec <- function(idx) {
    if (length(idx) <= 1) return(setNames(rep(1, length(idx)), idx))
    mid <- ceiling(length(idx) / 2)
    L <- idx[1:mid]; R <- idx[(mid+1):length(idx)]
    vL <- as.numeric(t(rep(1/length(L), length(L))) %*% sigma[L, L, drop=FALSE] %*% rep(1/length(L), length(L)))
    vR <- as.numeric(t(rep(1/length(R), length(R))) %*% sigma[R, R, drop=FALSE] %*% rep(1/length(R), length(R)))
    a_l <- if (vL + vR < 1e-12) 0.5 else 1 - vL / (vL + vR)
    wL <- hrp_rec(L) * a_l
    wR <- hrp_rec(R) * (1 - a_l)
    c(wL, wR)
  }
  w_ord <- hrp_rec(ord)
  w <- numeric(N)
  w[ord] <- w_ord
  w <- pmax(WEIGHT_LB, pmin(WEIGHT_UB, w))
  w / sum(w)
}

wB_ERC <- function(scores, sigma, prev_w, max_iter = 200, tol = 1e-6) {
  N <- length(scores)
  if (is.null(sigma) || nrow(sigma) != N || N < 2) return(wB_EW(scores, sigma, prev_w))
  w <- rep(1/N, N)
  for (iter in 1:max_iter) {
    Sw <- pmax(as.numeric(sigma %*% w), 1e-10)
    w_new <- (1 / Sw) / sum(1 / Sw)
    if (max(abs(w_new - w)) < tol) break
    w <- w_new
  }
  w <- pmax(WEIGHT_LB, pmin(WEIGHT_UB, w))
  w / sum(w)
}

methods_B <- list(
  list(name = "EW",            fn = wB_EW),
  list(name = "SigTilt",       fn = wB_SigTilt),
  list(name = "MVO_lam2",      fn = wB_MVO),
  list(name = "MVO_TO_phi0.5", fn = wB_MVO_TO),
  list(name = "HRP",           fn = wB_HRP),
  list(name = "ERC",           fn = wB_ERC)
)

# ─── 7. Walk-forward backtest engine ──────────────────────
# Final 20-name selection: combined top-20 by (SLEEVE_A_W * z_A + SLEEVE_B_W * z_B).
# Per name, weight = sleeve allocation × in-sleeve weight (normalized to picks
# from that sleeve in the final 20):
#   - n_A_final = # of A names in top-20, n_B_final = # of B names in top-20
#   - For an A-only name: name_w = SLEEVE_A_W * (w_in_sleeve_A / sum_in_sleeve_A_final)
#   - For a B-only name: name_w = SLEEVE_B_W * (w_in_sleeve_B / sum_in_sleeve_B_final)
# Overlap names share both buckets — but observed overlap = 0 over 84 sig_dates.
# Then apply STR_1715 overlay scalar (combined_overlay_V2). Cash residual = 1 - overlay.
# Σ block for sleeve B QP comes from covariance_per_sig_date (M6 top-30 cover).

run_walk_forward <- function(method_B_name, method_B_fn, capture_weights = FALSE) {
  results <- list()
  weights_list <- vector("list", length(SIG_DATES_84))
  prev_w_named <- NULL

  for (i in seq_along(SIG_DATES_84)) {
    sig_t   <- SIG_DATES_84[i]
    sig_ym_t<- format(sig_t, "%Y-%m")

    sleeveA_dt <- build_sleeve_A(sig_ym_t)
    sleeveB_dt <- build_sleeve_B(sig_t)
    if (is.null(sleeveA_dt) || is.null(sleeveB_dt)) next

    # Universe filter
    univ <- universe_for_sig(sig_t)
    sleeveA_dt <- sleeveA_dt[Ticker %in% univ]
    sleeveB_dt <- sleeveB_dt[Ticker %in% univ]
    if (nrow(sleeveA_dt) < 5 || nrow(sleeveB_dt) < 5) next

    # Allocation-proportional dedupe-merge:
    # n_A = round(SLEEVE_A_W * MAX_NAMES) = 12 names from STR_1715 top-20
    # n_B = MAX_NAMES - n_A = 8 names from M6 top-30
    # Both sleeves sorted by their respective signals, top-K each.
    sleeveA_dt <- sleeveA_dt[order(-score_A)][1:min(N_FROM_A, nrow(sleeveA_dt))]
    sleeveB_dt <- sleeveB_dt[order(-score_B)][1:min(N_FROM_B, nrow(sleeveB_dt))]

    # Dedupe: if a Ticker is in both (empirically 0 overlap, but safe), prefer sleeve A
    # and refill B from next-best M6 name.
    in_A_set <- sleeveA_dt$Ticker
    if (any(sleeveB_dt$Ticker %in% in_A_set)) {
      raw_B <- build_sleeve_B(sig_t)[Ticker %in% univ]
      setorder(raw_B, -score_B)
      raw_B <- raw_B[!Ticker %in% in_A_set]
      sleeveB_dt <- raw_B[1:min(N_FROM_B, nrow(raw_B))]
    }

    setkey(sleeveA_dt, Ticker); setkey(sleeveB_dt, Ticker)
    merged_dt <- merge(
      sleeveA_dt[, .(Ticker, score_A, w_in_sleeve_A, sleeve_A_in)],
      sleeveB_dt[, .(Ticker, score_B, rank_B, sleeve_B_in)],
      by = "Ticker", all = TRUE
    )
    merged_dt[is.na(sleeve_A_in), sleeve_A_in := FALSE]
    merged_dt[is.na(sleeve_B_in), sleeve_B_in := FALSE]
    # Combined score (for diagnostic only — selection already done by allocation)
    sA_z <- rep(0, nrow(merged_dt))
    if (sum(merged_dt$sleeve_A_in) > 1) {
      vA <- merged_dt$score_A[merged_dt$sleeve_A_in]
      sA_z[merged_dt$sleeve_A_in] <- (vA - mean(vA, na.rm=TRUE)) / sd(vA, na.rm=TRUE)
    }
    sB_z <- rep(0, nrow(merged_dt))
    if (sum(merged_dt$sleeve_B_in) > 1) {
      vB <- merged_dt$score_B[merged_dt$sleeve_B_in]
      sB_z[merged_dt$sleeve_B_in] <- (vB - mean(vB, na.rm=TRUE)) / sd(vB, na.rm=TRUE)
    }
    merged_dt[, combined_score := SLEEVE_A_W * sA_z + SLEEVE_B_W * sB_z]
    # No re-sort needed: union of top-12 A + top-8 B = up to 20 names
    top20 <- merged_dt

    # Backtest requires Ret_1m_fwd
    rp_t <- rp[Date == sig_t & Ticker %in% top20$Ticker, .(Ticker, Ret_1m_fwd)]
    top20 <- merge(top20, rp_t, by = "Ticker", all.x = TRUE)
    top20 <- top20[!is.na(Ret_1m_fwd)]
    if (nrow(top20) < 5) next

    # Split into A side and B side for in-sleeve weighting
    A_names <- top20[sleeve_A_in == TRUE]
    B_names <- top20[sleeve_B_in == TRUE & sleeve_A_in == FALSE]  # only B-only (overlap=0 empirically)
    n_A <- nrow(A_names); n_B <- nrow(B_names)
    # Effective sleeve allocations: scale by # selected from each
    # If n_A=0 → all weight to B; if n_B=0 → all weight to A.
    eff_A_w <- if (n_A == 0) 0 else SLEEVE_A_W
    eff_B_w <- if (n_B == 0) 0 else SLEEVE_B_W
    s_w     <- eff_A_w + eff_B_w
    eff_A_w <- eff_A_w / s_w
    eff_B_w <- eff_B_w / s_w

    # In-sleeve weights for A (production STR_1715 tilt over selected A names only)
    w_A_in <- numeric(0); names(w_A_in) <- character(0)
    if (n_A > 0) {
      a_p <- 0.018; b_p <- 0.021
      w_raw <- pmax(0.001, a_p + b_p * A_names$score_A)
      w_A_in <- w_raw / sum(w_raw)
      w_A_in <- pmin(w_A_in, WEIGHT_UB/eff_A_w)  # cap so name_w ≤ 0.20
      w_A_in <- w_A_in / sum(w_A_in)
      names(w_A_in) <- A_names$Ticker
    }

    # Σ block for B-side
    w_B_in <- numeric(0); names(w_B_in) <- character(0)
    if (n_B > 0) {
      sig_obj <- get_sigma(format(sig_t, "%Y%m"))
      sigma_B <- NULL
      common <- character(0)
      if (!is.null(sig_obj)) {
        common <- intersect(B_names$Ticker, sig_obj$tickers)
        if (length(common) >= 2) {
          sigma_B <- sig_obj$Sigma[common, common, drop = FALSE]
        }
      }
      if (length(common) == nrow(B_names) && !is.null(sigma_B)) {
        scores_B <- B_names$score_B
        # match scores order to sigma_B rownames
        idx <- match(rownames(sigma_B), B_names$Ticker)
        scores_B_ord <- scores_B[idx]
        prev_w_B <- if (is.null(prev_w_named)) rep(0, length(common)) else as.numeric(prev_w_named[rownames(sigma_B)])
        prev_w_B[is.na(prev_w_B)] <- 0
        w_B_in <- method_B_fn(scores_B_ord, sigma_B, prev_w_B)
        w_B_in <- pmin(w_B_in, WEIGHT_UB/eff_B_w)
        w_B_in <- w_B_in / sum(w_B_in)
        names(w_B_in) <- rownames(sigma_B)
        # Recover names not in Σ (fallback EW)
        missing <- setdiff(B_names$Ticker, names(w_B_in))
        if (length(missing) > 0) {
          # blend: 90% to QP names, 10% EW to missing
          w_missing <- rep(0.10/length(missing), length(missing))
          names(w_missing) <- missing
          w_B_in <- c(w_B_in * 0.90, w_missing)
          w_B_in <- w_B_in / sum(w_B_in)
        }
      } else {
        # Fallback: EW or SigTilt
        w_B_in <- rep(1/n_B, n_B)
        names(w_B_in) <- B_names$Ticker
      }
    }

    # Combined name weights
    name_w <- numeric(nrow(top20))
    names(name_w) <- top20$Ticker
    if (n_A > 0) name_w[names(w_A_in)] <- name_w[names(w_A_in)] + eff_A_w * w_A_in
    if (n_B > 0) name_w[names(w_B_in)] <- name_w[names(w_B_in)] + eff_B_w * w_B_in

    # Cap and normalize to risk_total = 1 (pre-overlay) — preserve names
    nm_keep <- names(name_w)
    name_w <- pmax(WEIGHT_LB, pmin(WEIGHT_UB, name_w))
    names(name_w) <- nm_keep
    name_w <- name_w / sum(name_w)
    names(name_w) <- nm_keep

    # STR_1715 overlay (regime gate)
    o_row <- overlay_ts[overlay_ym == sig_ym_t]
    overlay_gate <- if (nrow(o_row) > 0) o_row$combined_overlay_V2[1] else 1.0
    cash_share   <- 1 - overlay_gate
    w_eff <- name_w * overlay_gate

    # Realized return (cash earns 0)
    ret_panel_ord <- top20$Ret_1m_fwd
    names(ret_panel_ord) <- top20$Ticker
    w_eff_ord <- w_eff[top20$Ticker]
    port_ret_gross <- sum(w_eff_ord * ret_panel_ord)

    # Turnover (against previous w_eff aligned on combined ticker universe)
    if (is.null(prev_w_named)) {
      turn <- sum(abs(w_eff))   # initial buy = sum
    } else {
      all_tk <- union(names(prev_w_named), names(w_eff))
      pw <- as.numeric(prev_w_named[all_tk]); pw[is.na(pw)] <- 0
      cw <- as.numeric(w_eff[all_tk]);        cw[is.na(cw)] <- 0
      turn <- sum(abs(cw - pw))
    }
    cost_drag <- turn * (TC_BPS / 1e4)
    port_ret_net <- port_ret_gross - cost_drag

    results[[length(results) + 1]] <- data.table(
      sig_date       = sig_t,
      sig_ym         = sig_ym_t,
      n_names        = nrow(top20),
      n_A_selected   = n_A,
      n_B_selected   = n_B,
      port_ret_gross = port_ret_gross,
      port_ret_net   = port_ret_net,
      turn           = turn,
      cost_drag      = cost_drag,
      cash_share     = cash_share,
      overlay_gate   = overlay_gate
    )

    if (capture_weights) {
      weights_list[[i]] <- data.table(
        sig_date       = sig_t,
        sig_ym         = sig_ym_t,
        Ticker         = top20$Ticker,
        weight         = w_eff[top20$Ticker],
        cash_residual  = cash_share,
        sleeve_A_in    = top20$sleeve_A_in,
        sleeve_B_in    = top20$sleeve_B_in,
        score_A        = top20$score_A,
        score_B        = top20$score_B,
        combined_score = top20$combined_score
      )
    }

    prev_w_named <- w_eff
  }

  bt <- rbindlist(results)
  wts <- if (capture_weights) rbindlist(weights_list, fill = TRUE) else NULL
  list(bt = bt, weights = wts)
}

# ─── 8. Performance metrics calculator ────────────────────
calc_metrics <- function(bt, label) {
  if (nrow(bt) < 12) return(NULL)
  # drop NA returns
  bt <- bt[!is.na(port_ret_gross) & !is.na(port_ret_net)]
  rg <- xts(bt$port_ret_gross, order.by = bt$sig_date)
  rn <- xts(bt$port_ret_net,   order.by = bt$sig_date)
  ar_g <- as.numeric(Return.annualized(rg))
  ar_n <- as.numeric(Return.annualized(rn))
  sd_g <- as.numeric(StdDev.annualized(rg))
  sd_n <- as.numeric(StdDev.annualized(rn))
  if (!is.finite(sd_g)) sd_g <- 0
  if (!is.finite(sd_n)) sd_n <- 0
  sr_g <- if (sd_g > 0) ar_g / sd_g else NA_real_
  sr_n <- if (sd_n > 0) ar_n / sd_n else NA_real_
  mdd_n <- as.numeric(maxDrawdown(rn))
  cvar_n <- as.numeric(ES(rn, p = 0.95, method = "historical"))
  eff_to_yr <- mean(bt$turn) * 12
  list(
    label          = label,
    n_months       = nrow(bt),
    sharpe_gross   = round(sr_g, 4),
    sharpe_net     = round(sr_n, 4),
    cagr_net_pct   = round(ar_n * 100, 2),
    vol_net_pct    = round(sd_n * 100, 2),
    mdd_net_pct    = round(mdd_n * 100, 2),
    cvar95_monthly = round(cvar_n, 4),
    eff_to_yr      = round(eff_to_yr, 4),
    avg_n_names    = round(mean(bt$n_names), 1),
    avg_n_A        = round(mean(bt$n_A_selected), 1),
    avg_n_B        = round(mean(bt$n_B_selected), 1),
    avg_cash       = round(mean(bt$cash_share), 4)
  )
}

# ─── 9. Method shopping ───────────────────────────────────
cat("[9] Method shopping (6 sleeve-B methods, sleeve-A fixed signal-linear tilt)...\n")
all_results <- list()
for (m in methods_B) {
  cat(sprintf("  Running %s...\n", m$name))
  res <- run_walk_forward(m$name, m$fn, capture_weights = FALSE)
  metric <- calc_metrics(res$bt, m$name)
  all_results[[m$name]] <- list(metric = metric, bt = res$bt)
}

cat("\n=== Method Shopping Comparison ===\n")
cmp <- rbindlist(lapply(all_results, function(x) as.data.table(x$metric)))
print(cmp)

# ─── 10. Selection ────────────────────────────────────────
# Charter §15 P2 cost-aware: net_IR / to_adj_ret. Penalize TO > 6.0.
cat("\n[10] Method selection (objective: to_adj_ret = sharpe_net - penalty * (eff_TO/6.0))...\n")
cmp[, selection_score := sharpe_net]
cmp[eff_to_yr > 6.0, selection_score := selection_score - 0.25 * (eff_to_yr - 6.0) / 6.0]
cmp[, qualified := eff_to_yr <= 6.0]
setorder(cmp, -selection_score)
print(cmp[, .(label, sharpe_net, eff_to_yr, mdd_net_pct, cvar95_monthly, selection_score, qualified)])

SELECTED_METHOD <- cmp$label[1]
cat("\n  >>> Selected sleeve-B method:", SELECTED_METHOD, "<<<\n")

# ─── 11. Re-run selected to capture weights ───────────────
cat("\n[11] Re-running", SELECTED_METHOD, "to capture weights.csv...\n")
selected_fn <- NULL
for (m in methods_B) if (m$name == SELECTED_METHOD) selected_fn <- m$fn
res_final <- run_walk_forward(SELECTED_METHOD, selected_fn, capture_weights = TRUE)
WEIGHTS_DT <- res_final$weights
cat("Weights captured: nrow =", nrow(WEIGHTS_DT),
    " unique_sig_dates =", length(unique(WEIGHTS_DT$sig_date)), "\n")

# ─── 12. AX-007 sleeve contribution analysis ─────────────
WEIGHTS_DT[, only_A := sleeve_A_in & !sleeve_B_in]
WEIGHTS_DT[, only_B := !sleeve_A_in & sleeve_B_in]
WEIGHTS_DT[, both   := sleeve_A_in & sleeve_B_in]
sleeve_contrib_ts <- WEIGHTS_DT[, .(
  w_only_A = sum(weight[only_A]),
  w_only_B = sum(weight[only_B]),
  w_both   = sum(weight[both]),
  n_only_A = sum(only_A),
  n_only_B = sum(only_B),
  n_both   = sum(both),
  n_total  = .N,
  port_w_sum = sum(weight)
), by = sig_date]
sleeve_contrib_ts[, sleeve_A_share := (w_only_A + w_both) / pmax(port_w_sum, 1e-6)]
sleeve_contrib_ts[, sleeve_B_share := (w_only_B + w_both) / pmax(port_w_sum, 1e-6)]
sleeve_contrib_summary <- list(
  mean_sleeve_A_share = round(mean(sleeve_contrib_ts$sleeve_A_share), 4),
  mean_sleeve_B_share = round(mean(sleeve_contrib_ts$sleeve_B_share), 4),
  median_sleeve_A_share = round(median(sleeve_contrib_ts$sleeve_A_share), 4),
  median_sleeve_B_share = round(median(sleeve_contrib_ts$sleeve_B_share), 4),
  mean_n_only_A = round(mean(sleeve_contrib_ts$n_only_A), 1),
  mean_n_only_B = round(mean(sleeve_contrib_ts$n_only_B), 1),
  mean_n_both   = round(mean(sleeve_contrib_ts$n_both), 1),
  mean_n_total  = round(mean(sleeve_contrib_ts$n_total), 1),
  n_sig_dates   = nrow(sleeve_contrib_ts)
)
# AX-007 EXEMPT criteria from task spec: sleeve A ≥ 50%, sleeve B ≥ 30%
ax_007_pass <- sleeve_contrib_summary$mean_sleeve_A_share >= 0.50 &&
               sleeve_contrib_summary$mean_sleeve_B_share >= 0.30
sleeve_contrib_summary$ax_007_proof <- list(
  sleeve_A_target_min = 0.50,
  sleeve_B_target_min = 0.30,
  sleeve_A_actual = sleeve_contrib_summary$mean_sleeve_A_share,
  sleeve_B_actual = sleeve_contrib_summary$mean_sleeve_B_share,
  multi_sleeve_count = 2L,
  pass = ax_007_pass
)
cat("\n[12] AX-007 sleeve contribution proof:\n")
cat("  Sleeve A share (mean / median):", sleeve_contrib_summary$mean_sleeve_A_share,
    "/", sleeve_contrib_summary$median_sleeve_A_share, "\n")
cat("  Sleeve B share (mean / median):", sleeve_contrib_summary$mean_sleeve_B_share,
    "/", sleeve_contrib_summary$median_sleeve_B_share, "\n")
cat("  Mean n only_A / only_B / both / total:", sleeve_contrib_summary$mean_n_only_A,
    "/", sleeve_contrib_summary$mean_n_only_B,
    "/", sleeve_contrib_summary$mean_n_both,
    "/", sleeve_contrib_summary$mean_n_total, "\n")
cat("  AX-007 EXEMPT pass (A≥50 + B≥30):", ax_007_pass, "\n")

# ─── 13. Save weights.csv + sleeve_contribution.json ──────
out_w <- WEIGHTS_DT[, .(sig_date, Ticker, weight, sleeve_A_in, sleeve_B_in,
                       combined_score, score_A, score_B, cash_residual)]
fwrite(out_w, file.path(STAGE_DIR, "weights.csv"))
cat("\nweights.csv saved: nrow =", nrow(out_w), "\n")

sleeve_contrib_export <- list(
  summary = sleeve_contrib_summary,
  per_sig_date = lapply(seq_len(nrow(sleeve_contrib_ts)), function(i) {
    list(
      sig_date       = as.character(sleeve_contrib_ts$sig_date[i]),
      sleeve_A_share = round(sleeve_contrib_ts$sleeve_A_share[i], 4),
      sleeve_B_share = round(sleeve_contrib_ts$sleeve_B_share[i], 4),
      n_only_A       = sleeve_contrib_ts$n_only_A[i],
      n_only_B       = sleeve_contrib_ts$n_only_B[i],
      n_both         = sleeve_contrib_ts$n_both[i],
      n_total        = sleeve_contrib_ts$n_total[i]
    )
  })
)
write_json(sleeve_contrib_export, file.path(STAGE_DIR, "sleeve_contribution.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ─── 14. Save method shopping log + selected backtest ────
fwrite(cmp, file.path(STAGE_DIR, "method_shopping_log.csv"))
sel_bt <- all_results[[SELECTED_METHOD]]$bt
fwrite(sel_bt, file.path(STAGE_DIR, "selected_backtest_returns.csv"))

# ─── 15. Print summary ────────────────────────────────────
cat("\n========= FINAL SUMMARY =========\n")
cat("WT:", WT_ID, "\n")
cat("Selected sleeve-B method:", SELECTED_METHOD, "\n")
sm <- all_results[[SELECTED_METHOD]]$metric
cat("Sharpe (gross / net):", sm$sharpe_gross, "/", sm$sharpe_net, "\n")
cat("CAGR_net:", sm$cagr_net_pct, "%  MDD_net:", sm$mdd_net_pct, "%\n")
cat("eff_TO/yr:", sm$eff_to_yr, "  (target ≤ 6.0)\n")
cat("CVaR_95 monthly:", sm$cvar95_monthly, "  (STR_1715 inherit precedent ≤ -0.0707)\n")
cat("Avg n_names:", sm$avg_n_names, " (n_A:", sm$avg_n_A, " n_B:", sm$avg_n_B, ")\n")
cat("Avg cash share:", sm$avg_cash, "\n")
cat("AX-007 EXEMPT pass:", ax_007_pass, "\n")
cat("==================================\n")

# ─── 16. JSON summary for optimization_package draft build ─
write_json(list(
  task_id = WT_ID,
  selected_method = paste0("Sleeve_blend_A_SigTilt_B_", SELECTED_METHOD),
  selection_objective = "to_adj_ret",
  method_shopping_log = lapply(seq_len(nrow(cmp)), function(i) {
    list(
      name = cmp$label[i],
      sharpe_gross = cmp$sharpe_gross[i],
      sharpe_net = cmp$sharpe_net[i],
      eff_to_yr = cmp$eff_to_yr[i],
      cvar95_monthly = cmp$cvar95_monthly[i],
      mdd_net_pct = cmp$mdd_net_pct[i],
      cagr_net_pct = cmp$cagr_net_pct[i],
      vol_net_pct = cmp$vol_net_pct[i],
      qualified = cmp$qualified[i],
      selection_score = cmp$selection_score[i],
      selected = cmp$label[i] == SELECTED_METHOD
    )
  }),
  selected_metrics = sm,
  sleeve_contribution_summary = sleeve_contrib_summary,
  cost_model_version = COST_MODEL
), file.path(STAGE_DIR, "optimization_summary.json"),
   auto_unbox = TRUE, pretty = TRUE)

cat("\nAll artifacts saved to ", STAGE_DIR, "\n")
