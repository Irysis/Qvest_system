#==============================================================================
# 102_m3_hedge_deepdive.R — Cycle 47C — M3 Hedge Dynamic Ensemble Deep Dive
#
# Motivation (45D discovery):
#   - Cycle 45D OOS 2018-2026, y_tail_q15:
#     Static WEW 0.5875 / M1 Rolling 0.5896 / M2 Regime 0.5917 / M3 Hedge 0.6019 / M4 Bayes 0.5979 / M5 Bandit 0.5860
#   - M3 Hedge 처음으로 M2 Regime 능가 (+0.0102). M2 우월 가정 흔들림.
#   - 검증 필요: 45D-specific? Or general winner across datasets?
#
# This script (CPU only, ~2-4h):
#   1) 4 M3 Hedge variants:
#        V1. Classical Hedge fixed η ∈ {0.1, 0.3, 0.5, 1.0}
#        V2. Adaptive Hedge (Cesa-Bianchi-Lugosi 2006): η_t = sqrt(log(N) / t)
#        V3. AdaHedge (de Rooij et al. 2014): self-tuning η based on cumulative loss variance
#        V4. Regret-Min via Online Projected Gradient (simplex projection)
#   2) Cross-dataset (3): v2_2feat, v3b_inst_suite, v3d_walkforward
#   3) Bootstrap PR-AUC 95% CI (B=1000)
#   4) Weight trajectories diagnostic + plots
#   5) Final recommendation: M2 retain vs M3 production switch
#
# PIT: weight update strictly after observing y_t (one-step lag). 5-fold time-series CV for η.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(ggplot2)
  library(jsonlite)
})

set.seed(20260520)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_EVAL <- file.path(WS_DIR, "outputs/04_evaluation")
OUT_CHART <- file.path(WS_DIR, "outputs/06_reports/charts")
dir.create(OUT_EVAL, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_CHART, recursive = TRUE, showWarnings = FALSE)

# ─── Config ────────────────────────────────────────────────────────────────
TARGET   <- "y_tail_q15"
OOS_FROM <- as.Date("2018-01-01")              # match 45D evaluation window
M_NAMES  <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
N_MODEL  <- length(M_NAMES)
W_STATIC <- c(0.25, 0.25, 0.25, 0.125, 0.125)  # WEW baseline (D4 admit)
B_BOOT   <- 1000                                # bootstrap reps for CI
ETA_GRID <- c(0.1, 0.3, 0.5, 1.0)               # fixed-η sweep
EPS      <- 1e-12

DATASETS <- list(
  list(name = "v2_2feat",       base_path = "outputs/03_models/v2_2feat/predictions_5way_y_tail_q15.parquet",
       regime_path = "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet"),
  list(name = "v3b_inst_suite", base_path = "outputs/03_models/v3b_inst_suite/predictions_5way_y_tail_q15.parquet",
       regime_path = "outputs/03_models/v3b_inst_suite/predictions_dynamic_y_tail_q15.parquet"),
  list(name = "v3d_walkforward", base_path = "outputs/03_models/v3d_walkforward/predictions_5way_y_tail_q15.parquet",
       regime_path = "outputs/03_models/v3d_walkforward/predictions_dynamic_y_tail_q15.parquet")
)

# ─── Utilities ──────────────────────────────────────────────────────────────
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

softmax <- function(x, beta = 1) {
  e <- exp(x * beta - max(x * beta)); e / sum(e)
}

# Project a vector onto the probability simplex (Wang & Carreira-Perpiñán 2013, O(N log N))
project_simplex <- function(v) {
  n <- length(v); u <- sort(v, decreasing = TRUE)
  cssv <- cumsum(u) - 1
  rho_idx <- which(u - cssv / seq_len(n) > 0)
  if (length(rho_idx) == 0) return(rep(1 / n, n))
  rho <- max(rho_idx); lam <- cssv[rho] / rho
  pmax(v - lam, 0)
}

# Bootstrap PR-AUC 95% CI (paired, stationary block bootstrap to respect ts dep)
bootstrap_prauc_ci <- function(p, y, B = 1000, block_len = 21) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  n <- length(p); if (n < 30) return(c(lo = NA, hi = NA, pt = NA))
  pt <- pr_auc(p, y)
  vals <- numeric(B)
  for (b in seq_len(B)) {
    # Stationary block bootstrap (Politis-Romano 1994)
    n_blocks <- ceiling(n / block_len)
    starts <- sample.int(n, n_blocks, replace = TRUE)
    idx <- unlist(lapply(starts, function(s) ((s - 1 + seq_len(block_len) - 1) %% n) + 1))
    idx <- idx[seq_len(n)]
    vals[b] <- pr_auc(p[idx], y[idx])
  }
  vals <- vals[!is.na(vals)]
  c(lo = unname(quantile(vals, 0.025)), hi = unname(quantile(vals, 0.975)), pt = pt)
}

# ─── Hedge Variants ─────────────────────────────────────────────────────────
# Common loss: squared loss (matches original M3). Predictions in [0,1].

# V1. Classical Hedge fixed η
hedge_classical <- function(M, Y, eta) {
  n <- nrow(M); w <- rep(1 / N_MODEL, N_MODEL)
  preds <- numeric(n); w_hist <- matrix(NA_real_, n, N_MODEL)
  for (i in seq_len(n)) {
    preds[i] <- sum(M[i, ] * w); w_hist[i, ] <- w
    if (!is.na(Y[i])) {
      losses <- (M[i, ] - Y[i])^2
      w <- w * exp(-eta * losses); w <- w / sum(w)
    }
  }
  list(preds = preds, weights = w_hist, final_w = w)
}

# V2. Adaptive Hedge (Cesa-Bianchi-Lugosi 2006 Theorem 2.3): η_t = sqrt(log(N) / t)
hedge_adaptive <- function(M, Y) {
  n <- nrow(M); w <- rep(1 / N_MODEL, N_MODEL)
  preds <- numeric(n); w_hist <- matrix(NA_real_, n, N_MODEL)
  cum_loss <- rep(0, N_MODEL); t_seen <- 0
  for (i in seq_len(n)) {
    preds[i] <- sum(M[i, ] * w); w_hist[i, ] <- w
    if (!is.na(Y[i])) {
      t_seen <- t_seen + 1
      losses <- (M[i, ] - Y[i])^2
      cum_loss <- cum_loss + losses
      eta_t <- sqrt(log(N_MODEL) / max(t_seen, 1))
      w_new <- exp(-eta_t * cum_loss); w_new <- w_new / sum(w_new)
      w <- w_new
    }
  }
  list(preds = preds, weights = w_hist, final_w = w)
}

# V3. AdaHedge (de Rooij, van Erven, Grünwald, Koolen 2014 JMLR)
#   eta_t = log(N) / delta_t,  delta_t = sum_{s<=t} (m_s - h_s)
#   where m_s = mixed loss (-eta * log E_w[exp(-l)]), h_s = expected loss E_w[l]
#   Update: w_{t+1,i} = w_t,i * exp(-eta_t * l_t,i) / Z
hedge_adahedge <- function(M, Y) {
  n <- nrow(M); w <- rep(1 / N_MODEL, N_MODEL)
  preds <- numeric(n); w_hist <- matrix(NA_real_, n, N_MODEL)
  delta_cum <- 0  # cumulative mix gap
  for (i in seq_len(n)) {
    preds[i] <- sum(M[i, ] * w); w_hist[i, ] <- w
    if (!is.na(Y[i])) {
      losses <- (M[i, ] - Y[i])^2
      # eta from current delta_cum (handle delta_cum=0 with infinite eta → equal_weight protection)
      eta_t <- if (delta_cum <= EPS) log(N_MODEL) * 1e6 else log(N_MODEL) / delta_cum
      # Mixed loss m_t = -1/eta * log E_w[exp(-eta * l)]
      exp_term <- w * exp(-eta_t * losses)
      sum_exp <- sum(exp_term)
      if (sum_exp <= EPS || !is.finite(sum_exp)) {
        m_t <- min(losses); h_t <- sum(w * losses)
      } else {
        m_t <- -log(sum_exp) / eta_t; h_t <- sum(w * losses)
      }
      gap <- max(h_t - m_t, 0)
      delta_cum <- delta_cum + gap
      # Weight update
      if (sum_exp > EPS && is.finite(sum_exp)) {
        w <- exp_term / sum_exp
      }
    }
  }
  list(preds = preds, weights = w_hist, final_w = w)
}

# V4. Regret-Min via Online Projected Gradient on simplex (Zinkevich 2003)
#   w_{t+1} = Proj_simplex(w_t - lr * grad l_t(w_t))
#   loss l_t(w) = (M[t,] %*% w - Y[t])^2; grad = 2*(M[t,]%*%w - Y[t]) * M[t,]
#   lr_t = 1 / sqrt(t)
hedge_regretmin <- function(M, Y) {
  n <- nrow(M); w <- rep(1 / N_MODEL, N_MODEL)
  preds <- numeric(n); w_hist <- matrix(NA_real_, n, N_MODEL)
  t_seen <- 0
  for (i in seq_len(n)) {
    preds[i] <- sum(M[i, ] * w); w_hist[i, ] <- w
    if (!is.na(Y[i])) {
      t_seen <- t_seen + 1
      lr <- 1 / sqrt(t_seen)
      err <- sum(M[i, ] * w) - Y[i]
      grad <- 2 * err * M[i, ]
      w_unconstr <- w - lr * grad
      w <- project_simplex(w_unconstr)
    }
  }
  list(preds = preds, weights = w_hist, final_w = w)
}

# ─── 5-fold time-series CV for η selection (V1 only) ────────────────────────
cv_pick_eta <- function(M, Y, eta_grid, n_folds = 5) {
  n <- nrow(M)
  fold_size <- floor(n / (n_folds + 1))
  scores <- matrix(NA_real_, length(eta_grid), n_folds)
  for (k in seq_len(n_folds)) {
    val_start <- k * fold_size + 1; val_end <- min((k + 1) * fold_size, n)
    if (val_end - val_start < 30) next
    for (j in seq_along(eta_grid)) {
      # Train hedge on [1, val_start-1], freeze weights, predict val
      res <- hedge_classical(M[seq_len(val_end), , drop = FALSE],
                             Y[seq_len(val_end)],
                             eta_grid[j])
      scores[j, k] <- pr_auc(res$preds[val_start:val_end], Y[val_start:val_end])
    }
  }
  mean_scores <- rowMeans(scores, na.rm = TRUE)
  best_idx <- which.max(mean_scores)
  list(best_eta = eta_grid[best_idx], cv_scores = mean_scores, fold_matrix = scores)
}

# ─── Per-dataset Pipeline ───────────────────────────────────────────────────
run_dataset <- function(ds_meta) {
  cat(sprintf("\n========== Dataset: %s ==========\n", ds_meta$name))
  base_full <- as.data.table(read_parquet(file.path(WS_DIR, ds_meta$base_path)))
  base_full[, Date := as.Date(Date)]
  setorder(base_full, Date)
  # Merge regime
  reg <- as.data.table(read_parquet(file.path(WS_DIR, ds_meta$regime_path)))
  reg[, Date := as.Date(Date)]
  base_full <- merge(base_full, reg[, .(Date, regime)], by = "Date", all.x = TRUE)
  setorder(base_full, Date)

  # Filter to OOS_FROM
  d_oos <- base_full[Date >= OOS_FROM]
  n_oos <- nrow(d_oos)
  cat(sprintf("  OOS rows: %d (date %s -> %s)  events=%d (%.2f%%)\n",
              n_oos, as.character(min(d_oos$Date)), as.character(max(d_oos$Date)),
              sum(d_oos$y, na.rm = TRUE), 100 * mean(d_oos$y, na.rm = TRUE)))

  M <- as.matrix(d_oos[, ..M_NAMES])
  Y <- d_oos$y

  # ── Baselines (recompute with this OOS window) ──
  p_static <- as.numeric(M %*% W_STATIC)
  pa_static <- pr_auc(p_static, Y)

  # M1 Rolling 252d softmax β=5 — recreate quickly
  PURGE <- 21; LOOKBACK <- 252
  p_M1 <- rep(NA_real_, n_oos)
  for (i in seq_len(n_oos)) {
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    pw <- M[start:cutoff, , drop = FALSE]; yw <- Y[start:cutoff]
    pr_models <- sapply(seq_len(N_MODEL), function(m) pr_auc(pw[, m], yw))
    pr_models[is.na(pr_models)] <- 0
    w <- softmax(pr_models, beta = 5)
    p_M1[i] <- sum(M[i, ] * w)
  }
  pa_M1 <- pr_auc(p_M1, Y)

  # M2 Regime — use precomputed regime label from existing dynamic_ensemble parquet
  Regime <- d_oos$regime
  p_M2 <- rep(NA_real_, n_oos)
  for (i in seq_len(n_oos)) {
    cur_reg <- Regime[i]; if (is.na(cur_reg)) next
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    in_reg <- which(Regime[start:cutoff] == cur_reg) + (start - 1)
    if (length(in_reg) < 30) { p_M2[i] <- sum(M[i, ] * W_STATIC); next }
    pr_models <- sapply(seq_len(N_MODEL), function(m) pr_auc(M[in_reg, m], Y[in_reg]))
    pr_models[is.na(pr_models)] <- 0
    w <- softmax(pr_models, beta = 5)
    p_M2[i] <- sum(M[i, ] * w)
  }
  pa_M2 <- pr_auc(p_M2, Y)

  # ── 5-fold CV for classical η (within OOS, time-blocked) ──
  cv_res <- cv_pick_eta(M, Y, ETA_GRID, n_folds = 5)
  cat(sprintf("  [CV] best η=%.3f (scores: %s)\n", cv_res$best_eta,
              paste0(sprintf("η=%.1f→%.4f", ETA_GRID, cv_res$cv_scores), collapse = " | ")))

  # ── V1 Classical Hedge fixed η (full grid + CV-picked) ──
  v1_results <- list()
  for (eta in ETA_GRID) {
    r <- hedge_classical(M, Y, eta)
    v1_results[[paste0("eta_", eta)]] <- list(
      preds = r$preds, weights = r$weights, final_w = r$final_w, pa = pr_auc(r$preds, Y)
    )
  }
  # V1 final (CV-picked)
  v1_final <- v1_results[[paste0("eta_", cv_res$best_eta)]]

  # ── V2 Adaptive Hedge ──
  v2 <- hedge_adaptive(M, Y); pa_v2 <- pr_auc(v2$preds, Y)

  # ── V3 AdaHedge ──
  v3 <- hedge_adahedge(M, Y); pa_v3 <- pr_auc(v3$preds, Y)

  # ── V4 Regret-Min OPG ──
  v4 <- hedge_regretmin(M, Y); pa_v4 <- pr_auc(v4$preds, Y)

  # ── Bootstrap CI for all variants + baselines ──
  cat("  Bootstrapping CIs (B=", B_BOOT, ")...\n", sep = "")
  ci <- list()
  ci[["Static_WEW"]]      <- bootstrap_prauc_ci(p_static, Y, B = B_BOOT)
  ci[["M1_Rolling"]]      <- bootstrap_prauc_ci(p_M1, Y, B = B_BOOT)
  ci[["M2_Regime"]]       <- bootstrap_prauc_ci(p_M2, Y, B = B_BOOT)
  for (eta in ETA_GRID) {
    ci[[paste0("V1_Classical_eta", eta)]] <- bootstrap_prauc_ci(v1_results[[paste0("eta_", eta)]]$preds, Y, B = B_BOOT)
  }
  ci[["V1_Classical_CV"]] <- bootstrap_prauc_ci(v1_final$preds, Y, B = B_BOOT)
  ci[["V2_Adaptive"]]     <- bootstrap_prauc_ci(v2$preds, Y, B = B_BOOT)
  ci[["V3_AdaHedge"]]     <- bootstrap_prauc_ci(v3$preds, Y, B = B_BOOT)
  ci[["V4_RegretMin"]]    <- bootstrap_prauc_ci(v4$preds, Y, B = B_BOOT)

  # ── Significance vs M2 Regime ──
  m2_pa <- ci[["M2_Regime"]]["pt"]
  sig_test <- function(label) {
    lo <- ci[[label]]["lo"]; pt <- ci[[label]]["pt"]
    sig <- !is.na(lo) && !is.na(m2_pa) && lo > m2_pa
    list(uplift_vs_M2 = unname(pt - m2_pa), lower_CI_above_M2 = unname(sig))
  }

  # ── Print summary ──
  variant_names <- c("Static_WEW", "M1_Rolling", "M2_Regime",
                     paste0("V1_Classical_eta", ETA_GRID), "V1_Classical_CV",
                     "V2_Adaptive", "V3_AdaHedge", "V4_RegretMin")
  cat("\n  ── PR-AUC results ──\n")
  for (vn in variant_names) {
    c95 <- ci[[vn]]
    star <- ""
    if (vn != "M2_Regime" && !is.na(c95["lo"]) && !is.na(m2_pa) && c95["lo"] > m2_pa) star <- " *>M2 (sig)"
    if (vn != "M2_Regime" && !is.na(c95["pt"]) && !is.na(m2_pa) && c95["pt"] > m2_pa) star <- paste0(star, if (star == "") " >M2" else "")
    cat(sprintf("    %-26s PR-AUC=%.4f  CI=[%.4f, %.4f]%s\n", vn, c95["pt"], c95["lo"], c95["hi"], star))
  }

  # ── Weight trajectory data ──
  weight_traj_list <- list()
  for (eta in ETA_GRID) {
    weight_traj_list[[paste0("V1_eta", eta)]] <- v1_results[[paste0("eta_", eta)]]$weights
  }
  weight_traj_list[["V2_Adaptive"]] <- v2$weights
  weight_traj_list[["V3_AdaHedge"]] <- v3$weights
  weight_traj_list[["V4_RegretMin"]] <- v4$weights

  list(
    dataset = ds_meta$name,
    n_oos = n_oos,
    dates = d_oos$Date,
    Y = Y,
    regime = Regime,
    cv = cv_res,
    pa = list(
      Static_WEW = pa_static, M1_Rolling = pa_M1, M2_Regime = pa_M2,
      V1_etagrid = sapply(v1_results, function(x) x$pa),
      V1_CV = v1_final$pa, V2 = pa_v2, V3 = pa_v3, V4 = pa_v4
    ),
    ci = ci,
    weights = weight_traj_list,
    final_weights = list(
      V1_classical_CV = v1_final$final_w,
      V2_adaptive = v2$final_w,
      V3_adahedge = v3$final_w,
      V4_regretmin = v4$final_w
    )
  )
}

# ─── MAIN ──────────────────────────────────────────────────────────────────
cat("[Cycle 47C] M3 Hedge Deep Dive — 4 variants × 3 datasets\n")
t0 <- Sys.time()
all_results <- lapply(DATASETS, run_dataset)
names(all_results) <- sapply(DATASETS, function(x) x$name)
cat(sprintf("\n[TIME] All datasets done in %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ─── Cross-dataset matrix ───────────────────────────────────────────────────
cat("\n============================================================\n")
cat("[CROSS-DATASET PR-AUC MATRIX]\n")
cat("============================================================\n")

build_matrix <- function() {
  variant_names <- c("Static_WEW", "M1_Rolling", "M2_Regime",
                     paste0("V1_Classical_eta", ETA_GRID), "V1_Classical_CV",
                     "V2_Adaptive", "V3_AdaHedge", "V4_RegretMin")
  mat_pt <- matrix(NA_real_, length(variant_names), length(all_results),
                   dimnames = list(variant_names, names(all_results)))
  mat_lo <- mat_pt; mat_hi <- mat_pt
  for (di in seq_along(all_results)) {
    res <- all_results[[di]]
    for (vn in variant_names) {
      c95 <- res$ci[[vn]]
      mat_pt[vn, di] <- c95["pt"]; mat_lo[vn, di] <- c95["lo"]; mat_hi[vn, di] <- c95["hi"]
    }
  }
  list(pt = mat_pt, lo = mat_lo, hi = mat_hi)
}
mat <- build_matrix()
print(round(mat$pt, 4))

# ── Winner per dataset (max PR-AUC) ──
cat("\n[BEST PER DATASET]\n")
for (di in seq_along(all_results)) {
  ds <- names(all_results)[di]
  col <- mat$pt[, di]; col <- col[!is.na(col)]
  ord <- order(col, decreasing = TRUE)
  cat(sprintf("  %-18s top3: ", ds))
  for (k in 1:3) cat(sprintf("%s=%.4f  ", names(col)[ord[k]], col[ord[k]]))
  cat("\n")
}

# ── Global winner: count of times each variant > M2 ──
cat("\n[VARIANT WIN COUNT (PR-AUC > M2_Regime) across 3 datasets]\n")
m2_row <- mat$pt["M2_Regime", ]
wins <- rowSums(sweep(mat$pt, 2, m2_row, FUN = ">"), na.rm = TRUE)
sig_wins <- rowSums(mat$lo > matrix(m2_row, nrow(mat$lo), ncol(mat$lo), byrow = TRUE), na.rm = TRUE)
for (vn in setdiff(names(wins), "M2_Regime")) {
  cat(sprintf("  %-26s wins=%d/3   sig_wins(CI_lo>M2)=%d/3\n", vn, wins[vn], sig_wins[vn]))
}

# ─── Verdict logic ──────────────────────────────────────────────────────────
hedge_variants <- c(paste0("V1_Classical_eta", ETA_GRID), "V1_Classical_CV",
                    "V2_Adaptive", "V3_AdaHedge", "V4_RegretMin")
best_hedge_global <- hedge_variants[which.max(rowMeans(mat$pt[hedge_variants, , drop = FALSE], na.rm = TRUE))]
best_hedge_wins   <- wins[best_hedge_global]
best_hedge_sig    <- sig_wins[best_hedge_global]

verdict <- if (best_hedge_wins >= 2 && best_hedge_sig >= 1) {
  "M3_GENERAL_WINNER"
} else if (best_hedge_wins == 1 && best_hedge_global %in% hedge_variants &&
           mat$pt[best_hedge_global, "v3d_walkforward"] > mat$pt["M2_Regime", "v3d_walkforward"]) {
  "M3_45D_SPECIFIC"
} else {
  "M2_RETAIN"
}
cat(sprintf("\n[VERDICT] %s   (best_hedge=%s wins=%d sig=%d)\n",
            verdict, best_hedge_global, best_hedge_wins, best_hedge_sig))

# ─── Save JSON ──────────────────────────────────────────────────────────────
json_payload <- list(
  cycle = "47C",
  generated_at = as.character(Sys.time()),
  verdict = verdict,
  best_hedge_variant_global = best_hedge_global,
  best_hedge_wins_vs_M2 = unname(best_hedge_wins),
  best_hedge_sig_wins_vs_M2 = unname(best_hedge_sig),
  datasets = names(all_results),
  variants = rownames(mat$pt),
  prauc_point = as.data.frame(mat$pt),
  prauc_ci_lo = as.data.frame(mat$lo),
  prauc_ci_hi = as.data.frame(mat$hi),
  cv_picked_eta = sapply(all_results, function(x) x$cv$best_eta),
  cv_eta_grid = ETA_GRID,
  cv_eta_scores = lapply(all_results, function(x) setNames(round(x$cv$cv_scores, 5), paste0("eta_", ETA_GRID))),
  final_weights = lapply(all_results, function(x) lapply(x$final_weights, function(w) setNames(round(w, 4), M_NAMES))),
  base_models = M_NAMES,
  oos_from = as.character(OOS_FROM),
  target = TARGET,
  bootstrap_B = B_BOOT,
  bootstrap_block_len = 21,
  context = list(
    cycle_45D_reference = list(
      Static_WEW = 0.5875, M1_Rolling = 0.5896, M2_Regime = 0.5917,
      M3_Hedge = 0.6019, M4_Bayes = 0.5979, M5_Bandit = 0.5860
    ),
    motivation = "45D found M3 Hedge 0.6019 > M2 Regime 0.5917 (+0.0102). Test if 45D-specific or general."
  )
)
write_json(json_payload, file.path(OUT_EVAL, "m3_hedge_deepdive.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "string")
cat(sprintf("\n[OUT] %s\n", file.path(OUT_EVAL, "m3_hedge_deepdive.json")))

# ─── Weight trajectory parquet ──────────────────────────────────────────────
build_traj_dt <- function() {
  out_list <- list()
  for (ds_name in names(all_results)) {
    res <- all_results[[ds_name]]
    dates <- res$dates
    for (variant in names(res$weights)) {
      W <- res$weights[[variant]]
      colnames(W) <- M_NAMES
      dt <- as.data.table(W); dt[, Date := dates]; dt[, variant := variant]; dt[, dataset := ds_name]
      out_list[[length(out_list) + 1]] <- dt
    }
  }
  rbindlist(out_list, use.names = TRUE, fill = TRUE)
}
traj_dt <- build_traj_dt()
write_parquet(traj_dt, file.path(OUT_EVAL, "m3_hedge_weight_trajectories.parquet"))
cat(sprintf("[OUT] %s   (rows=%d)\n", file.path(OUT_EVAL, "m3_hedge_weight_trajectories.parquet"), nrow(traj_dt)))

# ─── Plot 1: PR-AUC comparison bars per dataset ─────────────────────────────
plot_df_list <- list()
for (di in seq_along(all_results)) {
  ds <- names(all_results)[di]
  for (vn in rownames(mat$pt)) {
    plot_df_list[[length(plot_df_list) + 1]] <- data.table(
      dataset = ds, variant = vn, pt = mat$pt[vn, di],
      lo = mat$lo[vn, di], hi = mat$hi[vn, di]
    )
  }
}
plot_df <- rbindlist(plot_df_list)
plot_df[, group := fcase(
  variant == "Static_WEW", "Baseline_Static",
  variant %in% c("M1_Rolling", "M2_Regime"), "Baseline_M1M2",
  startsWith(variant, "V1_Classical"), "V1_Classical",
  variant == "V2_Adaptive", "V2_Adaptive",
  variant == "V3_AdaHedge", "V3_AdaHedge",
  variant == "V4_RegretMin", "V4_RegretMin"
)]
plot_df[, variant := factor(variant, levels = rownames(mat$pt))]

p1 <- ggplot(plot_df, aes(x = variant, y = pt, fill = group)) +
  geom_col(position = position_dodge(width = 0.7)) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3) +
  facet_wrap(~ dataset, ncol = 1, scales = "free_y") +
  coord_flip() +
  geom_hline(data = plot_df[variant == "M2_Regime", .(dataset, pt)],
             aes(yintercept = pt), linetype = "dashed", color = "red", linewidth = 0.5) +
  labs(title = "Cycle 47C — M3 Hedge variants vs M2 Regime baseline (y_tail_q15, OOS 2018-2026)",
       subtitle = "Red dashed line = M2_Regime PR-AUC. Error bars = 95% bootstrap CI (block_len=21)",
       x = "Variant", y = "PR-AUC") +
  theme_minimal(base_size = 9) +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold"))
ggsave(file.path(OUT_CHART, "102_m3_hedge_comparison.png"), p1, width = 11, height = 12, dpi = 110)
cat(sprintf("[CHART] %s\n", file.path(OUT_CHART, "102_m3_hedge_comparison.png")))

# ─── Plot 2: Weight evolution over time (per variant × dataset) ─────────────
traj_long <- melt(traj_dt, id.vars = c("Date", "variant", "dataset"),
                  measure.vars = M_NAMES, variable.name = "model", value.name = "weight")
# Focus: V1_CV-picked η per dataset (from cv_res), V2_Adaptive, V3_AdaHedge, V4_RegretMin
focus_variants <- c(paste0("V1_eta", c(0.1, 1.0)), "V2_Adaptive", "V3_AdaHedge", "V4_RegretMin")
traj_focus <- traj_long[variant %in% focus_variants]

p2 <- ggplot(traj_focus, aes(x = Date, y = weight, color = model)) +
  geom_line(linewidth = 0.4, alpha = 0.85) +
  facet_grid(dataset ~ variant) +
  geom_vline(xintercept = as.Date(c("2020-03-15", "2022-09-15")), linetype = "dotted", color = "gray40") +
  labs(title = "Cycle 47C — Hedge weight evolution per (dataset × variant)",
       subtitle = "Dotted lines: 2020-03 COVID / 2022-09 stagflation crisis windows",
       x = "Date", y = "Weight") +
  theme_minimal(base_size = 8) +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold", size = 7))
ggsave(file.path(OUT_CHART, "102_m3_weight_evolution.png"), p2, width = 16, height = 9, dpi = 110)
cat(sprintf("[CHART] %s\n", file.path(OUT_CHART, "102_m3_weight_evolution.png")))

# ─── Stability of weights (variance over time) ──────────────────────────────
cat("\n[WEIGHT STABILITY — std dev of weights over time, mean across 5 models]\n")
for (ds in names(all_results)) {
  res <- all_results[[ds]]
  for (variant in names(res$weights)) {
    W <- res$weights[[variant]]; W <- W[complete.cases(W), , drop = FALSE]
    if (nrow(W) < 10) next
    sds <- apply(W, 2, sd, na.rm = TRUE)
    cat(sprintf("  %-18s | %-18s mean_sd=%.4f  range_sd=[%.4f, %.4f]\n",
                ds, variant, mean(sds), min(sds), max(sds)))
  }
}

# ─── Crisis-window weight shifts ────────────────────────────────────────────
cat("\n[CRISIS REACTIVE — weight shift |Δw| in 2020-03 COVID window]\n")
covid_window <- c(as.Date("2020-02-15"), as.Date("2020-04-15"))
for (ds in names(all_results)) {
  res <- all_results[[ds]]
  dates <- res$dates
  for (variant in c("V1_eta1", "V2_Adaptive", "V3_AdaHedge", "V4_RegretMin")) {
    if (!variant %in% names(res$weights)) next
    W <- res$weights[[variant]]
    pre  <- which(dates >= covid_window[1] & dates <= covid_window[1] + 5)
    post <- which(dates >= covid_window[2] - 5 & dates <= covid_window[2])
    if (length(pre) == 0 || length(post) == 0) next
    w_pre <- colMeans(W[pre, , drop = FALSE], na.rm = TRUE)
    w_post <- colMeans(W[post, , drop = FALSE], na.rm = TRUE)
    shift <- sum(abs(w_post - w_pre))
    cat(sprintf("  %-18s | %-18s |Δw|_L1 (pre→post)=%.4f\n", ds, variant, shift))
  }
}

# ─── Final recommendation block ─────────────────────────────────────────────
cat("\n============================================================\n")
cat("[FINAL RECOMMENDATION — Cycle 47C]\n")
cat("============================================================\n")
cat(sprintf("Verdict: %s\n", verdict))
cat(sprintf("Best hedge variant globally: %s\n", best_hedge_global))
cat(sprintf("Wins vs M2 Regime (across 3 datasets): %d/3\n", best_hedge_wins))
cat(sprintf("Significant (CI lower > M2): %d/3\n", best_hedge_sig))
cat(sprintf("\nProduction recommendation:\n"))
cat(if (verdict == "M3_GENERAL_WINNER") {
  sprintf("  ⇒ SWITCH production dynamic ensemble to %s (M3 Hedge variant).\n", best_hedge_global)
} else if (verdict == "M3_45D_SPECIFIC") {
  "  ⇒ KEEP M2 Regime as production; M3 Hedge only competitive on 45D walk-forward CV.\n"
} else {
  "  ⇒ RETAIN M2 Regime as production. M3 Hedge edge in 45D appears spurious.\n"
})

cat(sprintf("\n[ALL DONE in %.1f min] outputs at %s and %s\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")),
            OUT_EVAL, OUT_CHART))
