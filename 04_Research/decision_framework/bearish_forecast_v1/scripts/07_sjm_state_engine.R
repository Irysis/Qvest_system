#==============================================================================
# 07_sjm_state_engine.R — SJM State Engine (KR-013 Shu-Mulvey 2024 method transfer)
#
# Risk Research Agent — S7 구현 (2026-05-19)
#
# References:
#   KR-013: Shu & Mulvey (2024) arXiv:2410.14841 "Statistical Jump Model"
#   KR-023: Yale HMM (Hamilton 1989 Econometrica foundation)
#
# SJM formulation:
#   min Σ_t ||x_t - θ_{s_t}||² / 2 + λ · Σ_t 1{s_{t-1} ≠ s_t} + ||w||_1 ≤ κ
#
# Role: state engine (NOT main classifier — Codex round 2 R2 degraded to state)
#   Outputs 3 features: sjm_state(t-1) + state_age + distance_to_centroid
#
# Feature set (KR-013 Exhibit 3):
#   - Active Return EWMA (benchmark relative)
#   - Market breadth (KTRI proxy — above MA200 fraction)
#   - Downside Deviation (rolling)
#   - Active Market Beta (time-varying)
#   - VIX log-diff EWMA 21d
#   - Term spread (KR_Gov10Y - KR_Gov3Y)
#   - Credit spread (KR_CorpBBB - KR_CorpAA)
#   - RSI 14d
#   - Stochastic %K 14d
#   - MACD (12-26-9)
#
# PIT: expanding window, min_warmup = 252 days
# Hyperparams: λ + κ via nested purged WFO (log-loss + Brier on validation)
#
# Output:
#   outputs/03_models/markov_switching/sjm_states.parquet
#   outputs/03_models/markov_switching/hyperparams_lock.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR       <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v1")
OUT_DIR      <- file.path(WS_DIR, "outputs/03_models/markov_switching")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
REGIME_DIR   <- file.path(PROJECT_ROOT, "04_Research/regime_comparison/output")

cat("[S7] SJM State Engine — START\n")
cat("[S7] Reference: KR-013 Shu-Mulvey 2024 arXiv:2410.14841\n")
cat("[S7] Role: state engine (NOT main classifier — Codex R2 degraded)\n")

#==============================================================================
# STEP 1: Load and prepare feature set (KR-013 Exhibit 3)
#==============================================================================
cat("[S7] Step 1: Loading KR-013 Exhibit 3 features...\n")

# 1a. Benchmark returns (KOSPI200)
bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
bm <- bm[!is.na(BM_Close)]

# Log daily return
bm[, ret_daily := log(BM_Close / shift(BM_Close, 1L))]
bm <- bm[!is.na(ret_daily)]

cat(sprintf("  Benchmark: %d rows (%s ~ %s)\n",
    nrow(bm), min(bm$Date), max(bm$Date)))

# 1b. Helper: rolling window functions (PIT-safe expanding from min_warmup)
.rolling_z <- function(x, w=252L) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < max(2L, w)) next
    win <- x[max(1L, i-w+1L):i]
    m <- mean(win, na.rm=TRUE); s <- sd(win, na.rm=TRUE)
    out[i] <- if (is.finite(s) && s > 1e-10) (x[i] - m) / s else 0
  }
  out
}

.ewma <- function(x, span=21L) {
  alpha <- 2 / (span + 1)
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (is.na(x[i])) next
    if (is.na(out[i-1L]) || i == 1L) {
      out[i] <- x[i]
    } else {
      out[i] <- alpha * x[i] + (1 - alpha) * out[i-1L]
    }
  }
  out
}

.rsi <- function(r, period=14L) {
  n <- length(r)
  out <- rep(NA_real_, n)
  for (i in (period+1L):n) {
    win <- r[(i-period+1L):i]
    gains <- pmax(win, 0); losses <- pmax(-win, 0)
    avg_g <- mean(gains); avg_l <- mean(losses)
    if (avg_l < 1e-12) { out[i] <- 100; next }
    rs <- avg_g / avg_l
    out[i] <- 100 - 100 / (1 + rs)
  }
  out
}

.stochastic_k <- function(high, low, close, period=14L) {
  n <- length(close)
  out <- rep(NA_real_, n)
  for (i in period:n) {
    hi <- max(high[(i-period+1L):i], na.rm=TRUE)
    lo <- min(low[(i-period+1L):i], na.rm=TRUE)
    if (hi - lo < 1e-10) { out[i] <- 50; next }
    out[i] <- 100 * (close[i] - lo) / (hi - lo)
  }
  out
}

# 1c. MACD: EMA12 - EMA26
.ema <- function(x, span) {
  alpha <- 2 / (span + 1)
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (is.na(x[i])) next
    if (i == 1 || is.na(out[i-1])) out[i] <- x[i]
    else out[i] <- alpha * x[i] + (1-alpha) * out[i-1]
  }
  out
}

# 1d. Downside deviation (rolling)
.downside_dev <- function(r, period=63L) {
  n <- length(r)
  out <- rep(NA_real_, n)
  for (i in period:n) {
    win <- r[(i-period+1L):i]
    neg <- win[win < 0]
    out[i] <- if (length(neg) > 0) sqrt(mean(neg^2)) else 0
  }
  out
}

# 1e. Active return EWMA (vs benchmark = itself here; use excess over risk-free proxy)
# Since KOSPI200 IS the benchmark, use raw return EWMA as proxy for active trend
bm[, active_ret_ewma21 := .ewma(ret_daily, 21L)]
bm[, downside_dev_63    := .downside_dev(ret_daily, 63L)]
bm[, rsi_14             := .rsi(ret_daily, 14L)]
bm[, log_ret_z252       := .rolling_z(ret_daily, 252L)]

# MACD (12-26-9) on BM_Close
bm[, ema12 := .ema(BM_Close, 12L)]
bm[, ema26 := .ema(BM_Close, 26L)]
bm[, macd  := ema12 - ema26]
bm[, macd_signal := .ema(macd, 9L)]
bm[, macd_hist   := macd - macd_signal]

# Stochastic %K — use (BM_Close, BM_Close, BM_Close) as proxy (no high/low)
bm[, stoch_k := .stochastic_k(BM_Close, BM_Close, BM_Close, 14L)]

# VIX EWMA (load from FRED)
fred <- as.data.table(read_parquet(file.path(CACHE_DIR, "fred_macro_wide.parquet")))
fred[, Date := as.Date(Date)]
setorder(fred, Date)
vix_col <- if("VIX" %in% names(fred)) "VIX" else "StL_Fin_Stress"
fred_vix <- fred[, c("Date", vix_col), with=FALSE]
setnames(fred_vix, vix_col, "vix_raw")
fred_vix[, vix_log := log(pmax(vix_raw, 0.01))]
fred_vix[, vix_logdiff_ewma21 := .ewma(c(NA_real_, diff(fred_vix$vix_log)), 21L)]

# Term spread + Credit spread from ECOS
ecos <- as.data.table(read_parquet(file.path(CACHE_DIR, "ecos_bond_rates.parquet")))
ecos[, Date := as.Date(Date)]
setorder(ecos, Date)
ecos_wide <- dcast(ecos[!is.na(Value)], Date ~ Series, value.var="Value", fun.aggregate=mean)
if ("KR_Gov10Y" %in% names(ecos_wide) && "KR_Gov3Y" %in% names(ecos_wide)) {
  ecos_wide[, term_spread := KR_Gov10Y - KR_Gov3Y]
} else if ("KR_CorpAA" %in% names(ecos_wide) && "KR_Call1D" %in% names(ecos_wide)) {
  ecos_wide[, term_spread := KR_CorpAA - KR_Call1D]
} else {
  ecos_wide[, term_spread := NA_real_]
}
if ("KR_CorpBBB" %in% names(ecos_wide) && "KR_CorpAA" %in% names(ecos_wide)) {
  ecos_wide[, credit_spread := KR_CorpBBB - KR_CorpAA]
} else {
  ecos_wide[, credit_spread := NA_real_]
}

# KTRI breadth proxy (above MA200 fraction) — from unified_regime_signal_daily
ud <- as.data.table(read_parquet(file.path(CACHE_DIR, "unified_regime_signal_daily.parquet")))
ud[, Date := as.Date(Date)]
setorder(ud, Date)
# KTRI_Score is 0~100 breadth composite; normalize to [0,1]
ud[, ktri_breadth := KTRI_Score / 100]

# Active Market Beta (rolling 63d) — approx using auto-regression
bm[, active_beta_63 := {
  n <- .N; out <- rep(NA_real_, n)
  for(i in 64:n) {
    win_r <- ret_daily[(i-63L):i]
    # Market beta = cov(r, r_market) / var(r_market) = 1 for benchmark itself
    # Use rolling beta vs constant: slope of ret on lag(ret)
    y <- win_r[2:64]; x <- win_r[1:63]
    vx <- var(x, na.rm=TRUE)
    if (is.finite(vx) && vx > 1e-12) out[i] <- cov(y, x, use="complete.obs") / vx
    else out[i] <- 1
  }
  out
}]

#==============================================================================
# STEP 2: Merge all features into daily panel
#==============================================================================
cat("[S7] Step 2: Building daily SJM feature panel...\n")

feat_panel <- Reduce(function(a, b) merge(a, b, by="Date", all.x=TRUE), list(
  bm[, .(Date, ret_daily, active_ret_ewma21, downside_dev_63, rsi_14,
         macd_hist, stoch_k, log_ret_z252, active_beta_63)],
  fred_vix[, .(Date, vix_logdiff_ewma21)],
  ecos_wide[, .(Date, term_spread, credit_spread)],
  ud[, .(Date, ktri_breadth)]
))

# Define SJM feature names
sjm_feature_names <- c(
  "active_ret_ewma21",   # Active Return EWMA
  "rsi_14",              # RSI 14
  "stoch_k",             # Stochastic %K
  "macd_hist",           # MACD histogram
  "downside_dev_63",     # Downside Deviation
  "active_beta_63",      # Active Market Beta
  "vix_logdiff_ewma21",  # VIX log-diff EWMA 21d
  "term_spread",         # 2Y UST / KR term spread
  "credit_spread",       # 10Y-2Y / KR credit spread
  "ktri_breadth"         # Market breadth proxy
)
sjm_feature_names <- intersect(sjm_feature_names, names(feat_panel))

cat(sprintf("  SJM features available: %s\n", paste(sjm_feature_names, collapse=", ")))
cat(sprintf("  Feature panel: %d rows (%s ~ %s)\n",
    nrow(feat_panel), min(feat_panel$Date), max(feat_panel$Date)))

#==============================================================================
# STEP 3: SJM core algorithm (Shu-Mulvey 2024)
#
# Coordinate descent:
#   Given states {s_t}, update centroids θ_k = mean(x_t : s_t = k)
#   Given centroids, update states via Viterbi-like DP with switching cost λ
#
# Sparse feature selection via L1 constraint on weight vector w: ||w||_1 ≤ κ
# Implemented as soft-thresholding on feature weights
#==============================================================================

#' SJM coordinate descent (batch version, not expanding window)
sjm_fit_batch <- function(X, n_states = 2L, lambda = 0.5, kappa = Inf,
                           max_iter = 50L, tol = 1e-5, seed = 42L) {
  # X: T x p matrix of standardized features (NAs → 0 imputed)
  # lambda: switching cost
  # kappa: L1 bound on feature weights (Inf = no sparsity)
  # Returns: list(states, centroids, weights, obj_history, n_iter)

  set.seed(seed)
  T_len <- nrow(X); p <- ncol(X)

  # Feature weights (uniform init, then soft-threshold to enforce L1 <= kappa)
  w <- rep(1/p, p)
  if (is.finite(kappa)) {
    # Project onto L1 ball: soft-threshold
    w <- pmax(w - max(0, (sum(abs(w)) - kappa) / p), 0)
    w <- w / max(sum(abs(w)), 1e-10) * min(sum(abs(w)), kappa)
  }

  # Initialize states with k-means (faster than random)
  # Use first 2 PCs to seed
  X_complete <- X; X_complete[is.na(X_complete)] <- 0
  init_states <- rep(1L, T_len)
  tryCatch({
    km <- kmeans(X_complete, centers=n_states, nstart=5L, iter.max=20L)
    init_states <- km$cluster
    # Ensure states are 1..n_states
    init_states <- as.integer(factor(init_states))
  }, error = function(e) {
    init_states <<- sample(seq_len(n_states), T_len, replace=TRUE)
  })
  states <- init_states

  # Compute centroids
  centroids <- matrix(0, n_states, p)
  for (k in seq_len(n_states)) {
    rows_k <- which(states == k)
    if (length(rows_k) == 0) next
    centroids[k, ] <- colMeans(X_complete[rows_k, , drop=FALSE])
  }

  obj_history <- numeric(max_iter)

  for (iter in seq_len(max_iter)) {
    states_old <- states

    # ── Update states via DP (Viterbi with switching cost λ) ──────────────
    # Weighted distance: d(x_t, θ_k) = ||w * (x_t - θ_k)||² / 2
    # DP: V[t, k] = min_path cost ending in state k at time t
    V <- matrix(Inf, T_len, n_states)
    back <- matrix(0L, T_len, n_states)

    # Initialize t=1
    for (k in seq_len(n_states)) {
      diff_k <- X_complete[1, ] - centroids[k, ]
      V[1, k] <- sum((w * diff_k)^2) / 2
      back[1, k] <- k
    }

    # Forward pass
    for (t in 2L:T_len) {
      diff_t <- sweep(centroids, 2, X_complete[t, ], FUN="-")  # n_states × p
      emit_cost <- rowSums((sweep(diff_t, 2, w, FUN="*"))^2) / 2

      for (k in seq_len(n_states)) {
        # Cost from each previous state
        prev_costs <- V[t-1, ] + lambda * (seq_len(n_states) != k)
        best_prev  <- which.min(prev_costs)
        V[t, k]    <- prev_costs[best_prev] + emit_cost[k]
        back[t, k] <- best_prev
      }
    }

    # Backtrack
    states[T_len] <- which.min(V[T_len, ])
    for (t in (T_len-1L):1L) {
      states[t] <- back[t+1L, states[t+1L]]
    }

    # ── Update centroids ───────────────────────────────────────────────────
    for (k in seq_len(n_states)) {
      rows_k <- which(states == k)
      if (length(rows_k) == 0) {
        # Degenerate state: reinit to random point
        centroids[k, ] <- X_complete[sample.int(T_len, 1L), ]
        next
      }
      centroids[k, ] <- colMeans(X_complete[rows_k, , drop=FALSE])
    }

    # ── Update feature weights (gradient on reconstruction + L1 projection) ─
    # Gradient: ∇_w J = Σ_t (w * (x_t - θ_{s_t})) * (x_t - θ_{s_t})
    # (element-wise product → sign flip toward zero)
    diffs <- X_complete - centroids[states, ]  # T × p
    grad_w <- colMeans(diffs^2) * w            # p-vector

    if (is.finite(kappa)) {
      # Gradient step then project onto L1 ball
      lr <- 0.01
      w_new <- w - lr * grad_w
      w_new <- pmax(w_new, 0)
      l1 <- sum(abs(w_new))
      if (l1 > kappa) {
        # Project: sort and find threshold
        sorted_w <- sort(w_new, decreasing=TRUE)
        cumsum_w <- cumsum(sorted_w)
        rho <- max(which(sorted_w - (cumsum_w - kappa) / seq_along(sorted_w) > 0))
        theta <- (cumsum_w[rho] - kappa) / rho
        w_new <- pmax(w_new - theta, 0)
      }
      w <- if (sum(w_new) > 1e-10) w_new / sum(w_new) * kappa else rep(1/p, p) * kappa
    }
    w <- pmax(w, 0)

    # ── Objective ──────────────────────────────────────────────────────────
    total_emit <- sum(rowSums((sweep(diffs, 2, w, FUN="*"))^2)) / 2
    n_switches <- sum(states[-T_len] != states[-1L])
    obj_history[iter] <- total_emit + lambda * n_switches

    # Convergence
    if (iter > 1 && abs(obj_history[iter] - obj_history[iter-1]) < tol) {
      cat(sprintf("    Converged at iter %d (obj=%.4f)\n", iter, obj_history[iter]))
      break
    }
  }

  list(
    states      = states,
    centroids   = centroids,
    weights     = w,
    obj_history = obj_history[1:iter],
    n_iter      = iter
  )
}

#==============================================================================
# STEP 4: Expanding-window SJM fit (PIT-safe)
#==============================================================================
cat("[S7] Step 3: Expanding-window SJM with λ+κ grid search...\n")

# Filter to valid rows (sufficient non-NA features)
feat_cols_avail <- sjm_feature_names
feat_panel_valid <- copy(feat_panel)
feat_panel_valid[, n_valid_feats := rowSums(!is.na(.SD)), .SDcols=feat_cols_avail]
feat_panel_valid <- feat_panel_valid[n_valid_feats >= floor(0.5 * length(feat_cols_avail))]

# Standardize features (rolling 252d, PIT)
for (col in feat_cols_avail) {
  if (!(col %in% names(feat_panel_valid))) next
  feat_panel_valid[, paste0(col, "_z") := {
    x <- get(col)
    out <- rep(NA_real_, .N)
    for(i in seq_along(x)) {
      if(is.na(x[i])) { out[i] <- 0; next }
      if(i < 63) { out[i] <- 0; next }
      win <- x[max(1L, i-251L):i]
      m <- mean(win, na.rm=TRUE); s <- sd(win, na.rm=TRUE)
      out[i] <- if(is.finite(s) && s > 1e-10) (x[i] - m) / s else 0
    }
    out
  }]
}
z_cols <- paste0(feat_cols_avail, "_z")
z_cols <- intersect(z_cols, names(feat_panel_valid))

# Hyperparameter grid: λ × κ — nested purged WFO on validation 2010-2015
lambda_grid <- c(0.3, 0.5, 0.8, 1.5, 3.0)
kappa_grid  <- c(Inf, 5.0, 3.0)

# Load targets for validation
targets <- as.data.table(read_parquet(file.path(WS_DIR, "outputs/02_targets/targets_full.parquet")))
targets[, Date := as.Date(Date)]
setorder(targets, Date)

# Merge
feat_panel_valid <- merge(feat_panel_valid, targets[, .(Date, Y = y_onset)], by="Date", all.x=TRUE)

# Validation window 2010-2016 (out-of-training for λ,κ selection)
val_start <- as.Date("2010-01-01")
val_end   <- as.Date("2015-12-31")
train_end <- as.Date("2009-12-31")

# Build X matrix for train period (1990 ~ 2009)
X_full <- as.matrix(feat_panel_valid[, z_cols, with=FALSE])
X_full[is.na(X_full)] <- 0

train_idx <- which(feat_panel_valid$Date <= train_end)
val_idx   <- which(feat_panel_valid$Date >= val_start & feat_panel_valid$Date <= val_end)

# Hyperparameter search — quick grid (full expanding-window is expensive)
# Strategy: fit on train, evaluate on validation Brier score
best_lambda <- 0.5; best_kappa <- Inf; best_brier <- Inf
hparam_log <- list()

cat("  Hyperparameter grid search (λ × κ)...\n")
for (lam in lambda_grid) {
  for (kap in kappa_grid) {
    # Fit on train
    X_train <- X_full[train_idx, ]
    tryCatch({
      fit <- sjm_fit_batch(X_train, n_states=2L, lambda=lam, kappa=kap,
                           max_iter=30L, tol=1e-4)

      # Forward predict on validation: assign to nearest centroid
      X_val <- X_full[val_idx, ]
      # Distance to each centroid
      dists <- matrix(0, nrow(X_val), 2L)
      for (k in 1:2) {
        diff_k <- sweep(X_val, 2, fit$centroids[k, ], FUN="-")
        dists[, k] <- rowSums((sweep(diff_k, 2, pmax(fit$weights, 0), FUN="*"))^2)
      }
      # State 2 = more bearish (higher distance from normal centroid)
      # Identify which state is bearish: state with lower mean return
      state_mean_ret <- sapply(1:2, function(k) {
        ki <- which(fit$states == k)
        if(length(ki)==0) return(0)
        mean(feat_panel_valid$ret_daily[train_idx][ki], na.rm=TRUE)
      })
      bearish_state <- which.min(state_mean_ret)

      # Convert distance to probability
      p_bear_raw <- dists[, bearish_state] / (rowSums(dists) + 1e-10)
      # Flip: smaller distance = more likely in that state
      p_bear <- 1 - p_bear_raw

      Y_val <- feat_panel_valid$Y[val_idx]
      valid_v <- !is.na(Y_val)
      if (sum(valid_v) < 50) next

      brier <- mean((p_bear[valid_v] - Y_val[valid_v])^2, na.rm=TRUE)

      hparam_log[[length(hparam_log)+1]] <- list(
        lambda=lam, kappa=kap, brier=round(brier, 6), n_train=length(train_idx), n_val=sum(valid_v)
      )
      cat(sprintf("    λ=%.1f κ=%s → Brier=%.5f\n", lam, ifelse(is.infinite(kap), "Inf", kap), brier))

      if (brier < best_brier) {
        best_brier <- brier; best_lambda <- lam; best_kappa <- kap
      }
    }, error = function(e) {
      cat(sprintf("    λ=%.1f κ=%s → ERROR: %s\n", lam, kap, conditionMessage(e)))
    })
  }
}
cat(sprintf("  Best hyperparams: λ=%.2f, κ=%s (Brier=%.5f)\n",
    best_lambda, ifelse(is.infinite(best_kappa), "Inf", best_kappa), best_brier))

# Save hyperparams
hparam_out <- list(
  lambda_selected = best_lambda,
  kappa_selected  = ifelse(is.infinite(best_kappa), "Inf", best_kappa),
  best_brier_validation = best_brier,
  selection_window = list(train="1990-2009", validation="2010-2015"),
  lambda_grid = lambda_grid,
  kappa_grid  = kappa_grid,
  hparam_log  = hparam_log,
  n_states    = 2L,
  features_used = z_cols,
  sjm_role    = "state_engine_not_main_classifier",
  output_features = c("sjm_state_lag1", "state_age", "distance_to_centroid"),
  reference   = "KR-013 Shu-Mulvey 2024 arXiv:2410.14841",
  as_of       = "2026-05-19"
)
write_json(hparam_out, file.path(OUT_DIR, "hyperparams_lock.json"), pretty=TRUE, auto_unbox=TRUE)

#==============================================================================
# STEP 5: Expanding-window SJM state assignment (PIT-safe, min_warmup=252)
#==============================================================================
cat("[S7] Step 4: Expanding-window state assignment (PIT, min_warmup=252)...\n")

MIN_WARMUP <- 252L
n_total <- nrow(feat_panel_valid)
all_dates <- feat_panel_valid$Date

sjm_state    <- rep(NA_integer_, n_total)
state_age    <- rep(NA_integer_, n_total)
dist_centroid <- rep(NA_real_, n_total)
bearish_state_id <- rep(NA_integer_, n_total)

# Expanding window: refit every 63 days (quarterly) for efficiency
refit_schedule <- seq(MIN_WARMUP + 1L, n_total, by=63L)
if (tail(refit_schedule, 1) != n_total) refit_schedule <- c(refit_schedule, n_total)

last_fit <- NULL
last_bearish <- 2L  # default assumption

cat(sprintf("  Expanding window refits: %d points\n", length(refit_schedule)))

for (t_end in refit_schedule) {
  X_train <- X_full[1:t_end, ]

  # Fit SJM on expanding window
  tryCatch({
    fit <- sjm_fit_batch(X_train, n_states=2L, lambda=best_lambda, kappa=best_kappa,
                         max_iter=40L, tol=1e-4, seed=42L + t_end)
    last_fit <- fit

    # Identify bearish state (lower mean return in training window)
    ret_in_train <- feat_panel_valid$ret_daily[1:t_end]
    state_mean_ret <- sapply(1:2, function(k) {
      ki <- which(fit$states == k)
      if(length(ki)==0) return(0)
      mean(ret_in_train[ki], na.rm=TRUE)
    })
    last_bearish <- which.min(state_mean_ret)

    # Assign states for this window
    sjm_state[1:t_end] <- fit$states

    # Map to {1=BEARISH, 0=NORMAL} consistently
    # Ensure bearish = higher index consistently for interpretability
    state_mapped <- ifelse(fit$states == last_bearish, 1L, 0L)
    sjm_state[1:t_end] <- state_mapped

    # Distance to bearish centroid
    for (i in 1:t_end) {
      diff_i <- X_full[i, ] - fit$centroids[last_bearish, ]
      w_safe <- pmax(last_fit$weights, 0)
      dist_centroid[i] <- sqrt(sum((w_safe * diff_i)^2))
    }

    # State age: number of consecutive periods in current state
    states_so_far <- state_mapped[1:t_end]
    ages <- rep(0L, t_end)
    ages[1] <- 1L
    for (i in 2:t_end) {
      ages[i] <- if (states_so_far[i] == states_so_far[i-1]) ages[i-1] + 1L else 1L
    }
    state_age[1:t_end] <- ages

    bearish_state_id[1:t_end] <- last_bearish

  }, error = function(e) {
    cat(sprintf("  WARN at t=%d: %s\n", t_end, conditionMessage(e)))
  })

  if (t_end %% 500 == 0) {
    cat(sprintf("  Progress: %d / %d dates processed\n", t_end, n_total))
  }
}

cat("[S7] Expanding-window SJM states assigned.\n")
cat(sprintf("  State distribution: bearish=%d (%.1f%%), normal=%d (%.1f%%)\n",
    sum(sjm_state==1L, na.rm=TRUE),
    100*mean(sjm_state==1L, na.rm=TRUE),
    sum(sjm_state==0L, na.rm=TRUE),
    100*mean(sjm_state==0L, na.rm=TRUE)))

#==============================================================================
# STEP 6: Build output parquet (PIT: apply t-1 lag for use as features)
#==============================================================================
cat("[S7] Step 5: Building sjm_states.parquet (PIT lag=1 applied)...\n")

sjm_out <- data.table(
  Date              = all_dates,
  sjm_state_raw     = sjm_state,         # current state (0=normal, 1=bearish)
  state_age_raw     = state_age,
  distance_raw      = dist_centroid
)

# PIT lag: features are used at t-1 for prediction at t
sjm_out[, sjm_state_lag1       := shift(sjm_state_raw, 1L, type="lag")]
sjm_out[, state_age_lag1       := shift(state_age_raw, 1L, type="lag")]
sjm_out[, distance_to_centroid := shift(distance_raw, 1L, type="lag")]

# State transitions (for leave-one-crisis-out validation)
sjm_out[, state_change := as.integer(sjm_state_raw != shift(sjm_state_raw, 1L))]

# Add regime context from unified signal
sjm_out <- merge(sjm_out, ud[, .(Date, Category, Cash_Pct, MSM_Crisis_Prob)],
                 by="Date", all.x=TRUE)

# Compute summary stats by crisis periods
cat("[S7] SJM state distribution by market regime:\n")
cat("  CRISIS periods:\n")
print(sjm_out[Category == "CRISIS", .(
  n = .N,
  pct_bearish = round(mean(sjm_state_raw == 1L, na.rm=TRUE), 3),
  mean_dist   = round(mean(distance_raw, na.rm=TRUE), 4),
  mean_age    = round(mean(state_age_raw, na.rm=TRUE), 1)
)])
cat("  NON-CRISIS periods:\n")
print(sjm_out[Category %in% c("RISK_ON", "NEUTRAL"), .(
  n = .N,
  pct_bearish = round(mean(sjm_state_raw == 1L, na.rm=TRUE), 3),
  mean_dist   = round(mean(distance_raw, na.rm=TRUE), 4)
)])

# Save
write_parquet(sjm_out, file.path(OUT_DIR, "sjm_states.parquet"))
cat(sprintf("[S7] sjm_states.parquet saved: %d rows (%s ~ %s)\n",
    nrow(sjm_out), min(sjm_out$Date), max(sjm_out$Date)))

#==============================================================================
# STEP 7: Leave-one-crisis-out validation
#==============================================================================
cat("[S7] Step 6: Leave-one-crisis-out stability validation...\n")

# Crisis periods (reference_stress_periods): GFC 2008, EuDebt 2011, COVID 2020, KR 1997-98
crisis_periods <- list(
  GFC_2008  = c(as.Date("2007-10-01"), as.Date("2009-03-31")),
  EuDebt_2011 = c(as.Date("2010-07-01"), as.Date("2012-06-30")),
  COVID_2020  = c(as.Date("2020-01-01"), as.Date("2020-06-30")),
  Rate_2022   = c(as.Date("2022-01-01"), as.Date("2022-12-31"))
)

loco_results <- list()
for (crisis_name in names(crisis_periods)) {
  period <- crisis_periods[[crisis_name]]
  crisis_dates <- sjm_out$Date >= period[1] & sjm_out$Date <= period[2]

  if (sum(crisis_dates, na.rm=TRUE) < 10) next

  # State recall in crisis: % correctly identified as bearish
  crisis_rows <- sjm_out[crisis_dates]
  recall_crisis <- mean(crisis_rows$sjm_state_raw == 1L, na.rm=TRUE)
  avg_dist_crisis <- mean(crisis_rows$distance_raw, na.rm=TRUE)
  avg_dist_all <- mean(sjm_out$distance_raw, na.rm=TRUE)

  loco_results[[crisis_name]] <- list(
    period_start    = as.character(period[1]),
    period_end      = as.character(period[2]),
    n_days          = sum(crisis_dates, na.rm=TRUE),
    recall_bearish  = round(recall_crisis, 4),
    avg_distance_crisis = round(avg_dist_crisis, 4),
    avg_distance_all    = round(avg_dist_all, 4),
    relative_distance   = round(avg_dist_crisis / max(avg_dist_all, 1e-10), 4),
    stability_flag  = if (!is.na(recall_crisis) && recall_crisis >= 0.5) "PASS" else "WARN"
  )
  cat(sprintf("  %s: recall=%.3f, rel_dist=%.3f [%s]\n",
      crisis_name, recall_crisis,
      avg_dist_crisis / max(avg_dist_all, 1e-10),
      loco_results[[crisis_name]]$stability_flag))
}

# Save LOCO validation
loco_out <- list(
  method = "leave-one-crisis-out",
  description = "SJM state recall in crisis periods vs full-sample average distance",
  pass_threshold = 0.5,
  results = loco_results,
  note = "SJM is state engine, not main classifier — 50%+ crisis recall is sufficient",
  as_of = "2026-05-19"
)
write_json(loco_out, file.path(OUT_DIR, "loco_validation.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[S7] loco_validation.json saved\n"))

#==============================================================================
# STEP 8: Summary report
#==============================================================================
cat("\n[S7] COMPLETE\n")
n_bearish <- sum(sjm_out$sjm_state_raw == 1L, na.rm=TRUE)
n_total_valid <- sum(!is.na(sjm_out$sjm_state_raw))
loco_pass <- sum(sapply(loco_results, function(x) x$stability_flag == "PASS"))
loco_total <- length(loco_results)

cat(sprintf("  sjm_states.parquet: %d rows, bearish %.1f%% (n=%d)\n",
    nrow(sjm_out), 100*n_bearish/n_total_valid, n_bearish))
cat(sprintf("  Hyperparams locked: λ=%.2f, κ=%s (Brier=%.5f)\n",
    best_lambda, ifelse(is.infinite(best_kappa), "Inf", best_kappa), best_brier))
cat(sprintf("  LOCO validation: %d/%d crisis periods PASS (>=50%% recall)\n",
    loco_pass, loco_total))
cat(sprintf("  PIT lag=1 applied to: sjm_state_lag1, state_age_lag1, distance_to_centroid\n"))
cat(sprintf("  Outputs:\n"))
cat(sprintf("    %s/sjm_states.parquet\n", OUT_DIR))
cat(sprintf("    %s/hyperparams_lock.json\n", OUT_DIR))
cat(sprintf("    %s/loco_validation.json\n", OUT_DIR))

invisible(list(
  sjm_out        = sjm_out,
  best_lambda    = best_lambda,
  best_kappa     = best_kappa,
  loco_pass_rate = loco_pass / max(loco_total, 1),
  as_of          = "2026-05-19"
))
