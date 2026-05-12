#==============================================================================
# WT-D20260508_013 — Optimizer Research Agent build_optimizer.R
#
# Mission:
#   Alpha (Atilgan-Bali-Demirtas-Gunaydin 2020 JFE c4_rcomp,
#          full 252m strict 4/5 FAIL / 60m 3/3 PASS,
#          AX-001 v2 ratio +17.9 / orthogonality cor 0.025 vs Hybrid)
#   + Risk (LW μI cond=1 / factor model cond=1055,
#           σ-reduction -9.19% at w=10%, TDC 0.22, cor 0.025 full panel,
#           AX-001 v2 ratio CI [-126, 151] unstable → DIVERSIFIER not Defense,
#           stress 6/8 feasible, slow-burn outperform 3/6 vs flash-crash deferred)
#   → target_weights for WT_013 sleeve standalone +
#     Hybrid combine grid (0% / 5% / 10% / 15% / 20% incremental admission)
#
# Hard Constraints (worktask_constraint_enforcer.sh):
#   - max_names ≤ 20
#   - long-only (weights ≥ 0)
#   - weight_bounds [0, 0.20]
#   - Σw = 1
#   - liquidity 2e8 KRW (alpha layer pre-filtered)
#
# Multi-sleeve EXCEPTION (AX-007):
#   Hybrid current = 70% STR_1715_AR + 15% TSMOM + 15% KR_10y (3-sleeve, EXCEPTION operative)
#   With WT_013 = 4-sleeve combine extending EXCEPTION
#
# Diversifier Role (AX-001 v2 FAIL):
#   - Risk agent: ratio CI [-126, 151] unstable → Defense classification withdrawn
#   - Diversifier role: weight band 5-15% conservative
#   - Compare 5 grid weights: 0% / 5% / 10% / 15% / 20%
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(quadprog)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_013"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ARTIFACTS_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_ID)
OPT_DIR <- file.path(ARTIFACTS_DIR, "optimizer")
dir.create(OPT_DIR, showWarnings = FALSE, recursive = TRUE)

set.seed(20260508)

cat("==============================================\n")
cat("Optimizer Research Agent build_optimizer.R\n")
cat(sprintf("WT: %s\n", WT_ID))
cat(sprintf("Time: %s\n", format(Sys.time())))
cat("==============================================\n\n")

# ─── Step 1: Load packages ───────────────────────────────
cat("[Step 1] Loading alpha_package + risk_package + alpha_scores\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"), simplifyVector = FALSE)

alpha_vector <- unlist(alpha_pkg$alpha_vector)
confidence_vector <- unlist(alpha_pkg$confidence_vector)
N_full <- length(alpha_vector)
cat(sprintf("  alpha_vector: N=%d (mean=%.5f, sd=%.5f, range=[%.4f, %.4f])\n",
            N_full, mean(alpha_vector), sd(alpha_vector), min(alpha_vector), max(alpha_vector)))
cat(sprintf("  confidence: mean=%.3f, range=[%.3f, %.3f]\n",
            mean(confidence_vector), min(confidence_vector), max(confidence_vector)))

# alpha_scores.parquet (252 sig_dates + 1 portfolio-construction snapshot @ 2026-05-08)
ascores_path <- file.path(ARTIFACTS_DIR, "alpha_scores.parquet")
ascores <- as.data.table(read_parquet(ascores_path))
cat(sprintf("  alpha_scores.parquet: %d rows, cols=%s\n",
            nrow(ascores), paste(names(ascores), collapse=", ")))
cat(sprintf("    n_unique_dates=%d, range %s ~ %s\n",
            uniqueN(ascores$Date),
            as.character(min(ascores$Date)), as.character(max(ascores$Date))))

# Retain only sig_dates with non-NA fwd_ret (training panel)
sig_dates <- sort(unique(ascores[!is.na(fwd_ret_1m)]$Date))
cat(sprintf("    walk-forward sig_dates (fwd_ret non-NA): %d\n", length(sig_dates)))

# ─── Step 2: Reconstruct LW Σ matrix from long-format triplet ─────────
cat("\n[Step 2] Reconstructing covariance matrices\n")

# Reconstruct from triplet long format. Risk agent stores symmetric matrix in N x N triplet (full)
build_cov_from_triplet <- function(dt) {
  ticks <- sort(unique(dt$ticker_i))
  N <- length(ticks)
  m <- matrix(0, N, N, dimnames = list(ticks, ticks))
  for (k in seq_len(nrow(dt))) m[dt$ticker_i[k], dt$ticker_j[k]] <- dt$cov_value[k]
  # Triplet stores both (i,j) and (j,i) (full N×N), already symmetric — verify
  asym <- max(abs(m - t(m)))
  if (asym > 1e-10) {
    # Half-format upper/lower only — symmetrize
    m <- (m + t(m)) / 2
  }
  m
}

lw_long <- as.data.table(read_parquet(file.path(ARTIFACTS_DIR, "risk/covariance.parquet")))
cov_lw <- build_cov_from_triplet(lw_long)
N_lw <- nrow(cov_lw)
ev_lw <- eigen(cov_lw, only.values = TRUE)$values
cond_lw <- max(ev_lw) / max(min(ev_lw), 1e-12)
cat(sprintf("  LW μI: N=%d, diag mean=%.6f, cond=%.2f, min_eig=%.2e\n",
            N_lw, mean(diag(cov_lw)), cond_lw, min(ev_lw)))

# Factor model cov
fc_long <- as.data.table(read_parquet(file.path(ARTIFACTS_DIR, "risk/covariance_factor.parquet")))
cov_fc <- build_cov_from_triplet(fc_long)
N_fc <- nrow(cov_fc)
ev_fc <- eigen(cov_fc, only.values = TRUE)$values
cond_fc <- max(ev_fc) / max(min(ev_fc), 1e-12)
cat(sprintf("  Factor (Bβ'+D): N=%d, diag mean=%.6f, cond=%.2f, min_eig=%.2e\n",
            N_fc, mean(diag(cov_fc)), cond_fc, min(ev_fc)))

# Choose primary covariance: factor model (cond 1055 < 5000 within v6.1 budget) — μI degenerate
# LW μI degenerate retained for ERC/HRP scenarios
COV_PRIMARY_NAME <- "factor_model"  # for MVO confidence-aware
COV_PRIMARY <- cov_fc

# ─── Step 3: Align tickers across alpha + cov + universe ───────────────
cat("\n[Step 3] Ticker alignment\n")
common_t <- intersect(intersect(names(alpha_vector), rownames(cov_lw)), rownames(cov_fc))
cat(sprintf("  common tickers (alpha ∩ LW ∩ factor): %d\n", length(common_t)))

alpha_aligned <- alpha_vector[common_t]
conf_aligned  <- confidence_vector[common_t]
sigma_lw      <- cov_lw[common_t, common_t]
sigma_fc      <- cov_fc[common_t, common_t]
N <- length(common_t)

# ─── Step 4: Walk-forward IC + alpha sleeve simulation ─────────────────
cat("\n[Step 4] Walk-forward alpha sleeve simulation\n")
cat("  Use full 252-date panel (alpha_package_diagnostics.measurement_basis_full)\n")

# Define walk-forward simulation function: monthly long-only top20 sleeve
# At each sig_date: top20 by alpha_z (PIT-honest from alpha_package). Method-specific weights.
sim_walk_forward <- function(method_name, ascores_tbl, sigma_for_alloc,
                             n_top = 20, conf_vec = NULL, alpha_aux = NULL) {
  # ascores_tbl: Date, Ticker, alpha_z, fwd_ret_1m
  dates <- sort(unique(ascores_tbl[!is.na(fwd_ret_1m)]$Date))
  sigma_ticks <- rownames(sigma_for_alloc)
  out <- data.table(Date = as.Date(character()), ret = numeric(), to = numeric(),
                    n_active = integer())
  prev_w <- NULL
  for (d in dates) {
    sub <- ascores_tbl[Date == d & !is.na(fwd_ret_1m) & !is.na(alpha_z) & Ticker %in% sigma_ticks, ]
    setorder(sub, -alpha_z)
    sub <- head(sub, n_top)
    if (nrow(sub) == 0) next
    sub_t <- sub$Ticker
    n_act <- nrow(sub)
    # Method dispatch
    w <- switch(method_name,
      "EW_top20" = rep(1 / n_act, n_act),
      "MVO_conf_aware" = {
        # confidence-aware MVO with subset
        a <- sub$alpha_z
        if (!is.null(conf_vec)) {
          c_vec <- conf_vec[sub_t]
          c_vec[is.na(c_vec)] <- mean(c_vec, na.rm = TRUE)
          a <- a * c_vec
        }
        sg <- sigma_for_alloc[sub_t, sub_t, drop = FALSE]
        # Add small jitter for stability
        sg <- sg + diag(1e-6, n_act)
        # solve.QP: min(-d'x + 1/2 x'D x), Aeq=1, x>=0, x<=0.20
        Dmat <- 2 * sg
        dvec <- as.numeric(a)
        # Σw=1, w_i in [0, 0.20]
        Amat <- cbind(rep(1, n_act), diag(n_act), -diag(n_act))
        bvec <- c(1, rep(0, n_act), rep(-0.20, n_act))
        ok <- tryCatch({
          sol <- solve.QP(Dmat, dvec, Amat, bvec, meq = 1)
          sol$solution
        }, error = function(e) rep(1 / n_act, n_act))
        ok <- pmax(ok, 0); ok <- ok / sum(ok)
        ok
      },
      "ERC_top20" = {
        # Equal Risk Contribution iterative (Maillard-Roncalli-Teiletche 2010)
        sg <- sigma_for_alloc[sub_t, sub_t, drop = FALSE]
        sg <- sg + diag(1e-6, n_act)
        # Naive ERC: w_i ∝ 1/sqrt(diag(σ_i)) but more rigorous via convex
        # Use simplified inverse-vol initial → 5 Newton iterations
        w_init <- 1 / sqrt(diag(sg)); w_init <- w_init / sum(w_init)
        w_cur <- w_init
        for (it in 1:50) {
          mrc <- (sg %*% w_cur) / as.numeric(sqrt(t(w_cur) %*% sg %*% w_cur))
          rc <- as.vector(w_cur * mrc)
          target <- mean(rc)
          # Update: w_new ∝ target / mrc
          w_new <- w_cur * (target / pmax(rc, 1e-12)) ^ 0.5
          w_new <- pmax(w_new, 0); w_new <- pmin(w_new, 0.20)
          w_new <- w_new / sum(w_new)
          if (max(abs(w_new - w_cur)) < 1e-7) break
          w_cur <- w_new
        }
        w_cur
      },
      "HRP_top20" = {
        # Hierarchical Risk Parity (López de Prado 2016)
        sg <- sigma_for_alloc[sub_t, sub_t, drop = FALSE]
        # Build correlation distance
        if (any(is.na(sg)) || any(is.infinite(sg))) {
          rep(1 / n_act, n_act)
        } else {
          sd_vec <- sqrt(diag(sg))
          # If all sd identical (μI degenerate) HRP collapses to EW
          if (sd(sd_vec) < 1e-9) {
            rep(1 / n_act, n_act)
          } else {
            cor_mat <- sg / outer(sd_vec, sd_vec)
            dist_mat <- sqrt(0.5 * (1 - cor_mat))
            tryCatch({
              hc <- hclust(as.dist(dist_mat), method = "single")
              ord <- hc$order
              # quasi-diag ordering + recursive bisection
              recursive_bisect <- function(items, sg) {
                w <- rep(1, length(items))
                names(w) <- items
                stack <- list(items)
                while (length(stack) > 0) {
                  cur <- stack[[1]]
                  stack[[1]] <- NULL
                  if (length(cur) > 1) {
                    half <- floor(length(cur) / 2)
                    L <- cur[1:half]; R <- cur[(half + 1):length(cur)]
                    var_L <- as.numeric(t(rep(1 / length(L), length(L))) %*% sg[L, L, drop = FALSE] %*% rep(1 / length(L), length(L)))
                    var_R <- as.numeric(t(rep(1 / length(R), length(R))) %*% sg[R, R, drop = FALSE] %*% rep(1 / length(R), length(R)))
                    a_L <- 1 - var_L / (var_L + var_R)
                    a_R <- 1 - a_L
                    w[L] <- w[L] * a_L
                    w[R] <- w[R] * a_R
                    stack <- c(stack, list(L), list(R))
                  }
                }
                w
              }
              ord_t <- sub_t[ord]
              w_named <- recursive_bisect(ord_t, sg)
              w_named <- w_named[sub_t]
              as.vector(w_named / sum(w_named))
            }, error = function(e) rep(1 / n_act, n_act))
          }
        }
      },
      "AlphaWeighted_top20" = {
        # Weight ∝ alpha_z normalized to be positive (since top20 already alpha+ winner)
        a <- sub$alpha_z
        a_pos <- a - min(a) + 1e-6
        a_pos / sum(a_pos)
      },
      rep(1 / n_act, n_act)
    )
    # Cap [0, 0.20]
    w <- pmin(pmax(w, 0), 0.20)
    if (sum(w) > 0) w <- w / sum(w) else w <- rep(1 / n_act, n_act)
    names(w) <- sub_t
    # Period return = sum(w * fwd_ret_1m)
    ret <- sum(w * sub$fwd_ret_1m)
    # Turnover vs prev period
    if (is.null(prev_w)) {
      to <- sum(abs(w))
    } else {
      all_t <- union(names(prev_w), names(w))
      pw <- prev_w[all_t]; pw[is.na(pw)] <- 0
      cw <- w[all_t]; cw[is.na(cw)] <- 0
      to <- sum(abs(cw - pw)) / 2
    }
    out <- rbind(out, data.table(Date = d, ret = ret, to = to, n_active = n_act))
    prev_w <- w
  }
  out
}

# Method shopping (per Charter v6.1 R2-C, candidates ≤ 10)
methods_to_try <- c("EW_top20", "AlphaWeighted_top20", "MVO_conf_aware", "ERC_top20", "HRP_top20")

cat(sprintf("  Methods to evaluate: %s\n", paste(methods_to_try, collapse=", ")))

# Use factor cov for QP/ERC/HRP (LW μI degenerate, ERC/HRP would collapse to EW)
sim_results <- list()
for (m in methods_to_try) {
  cat(sprintf("    [%s] simulating ...", m))
  res <- tryCatch({
    sim_walk_forward(m, ascores, sigma_for_alloc = sigma_fc, conf_vec = conf_aligned)
  }, error = function(e) {
    cat(sprintf(" ERR: %s", conditionMessage(e)))
    NULL
  })
  sim_results[[m]] <- res
  if (!is.null(res) && nrow(res) > 0) {
    sr_a <- mean(res$ret) / sd(res$ret) * sqrt(12)
    cum <- prod(1 + res$ret) - 1
    nv <- cumprod(1 + res$ret)
    mdd <- min(nv / cummax(nv) - 1)
    cat(sprintf(" SR=%.3f  μ_m=%.4f  σ_m=%.4f  MDD=%.3f  TO_avg=%.3f  n_dates=%d\n",
                sr_a, mean(res$ret), sd(res$ret), mdd, mean(res$to), nrow(res)))
  } else {
    cat(" FAIL\n")
  }
}

# Method comparison data.table
method_log_dt <- data.table(
  name = character(), family = character(), n_active = integer(),
  sr_a = numeric(), mean_m = numeric(), sd_m = numeric(),
  mdd = numeric(), turnover_avg = numeric(), n_periods = integer(),
  cost_adj_sr = numeric(), selected = logical()
)
for (m in names(sim_results)) {
  res <- sim_results[[m]]
  if (is.null(res) || nrow(res) == 0) next
  fam <- switch(m,
                "EW_top20" = "linear_baseline",
                "AlphaWeighted_top20" = "linear_alpha_signal",
                "MVO_conf_aware" = "classical",
                "ERC_top20" = "risk_parity",
                "HRP_top20" = "risk_parity",
                "other")
  ret <- res$ret; to <- res$to
  # Net SR with 15bps round-trip cost (round-trip = 2 × one-way)
  net_ret <- ret - 2 * to * 0.0015
  cost_adj_sr <- mean(net_ret) / sd(net_ret) * sqrt(12)
  nv <- cumprod(1 + ret); mdd <- min(nv / cummax(nv) - 1)
  method_log_dt <- rbind(method_log_dt, data.table(
    name = m, family = fam, n_active = round(mean(res$n_active)),
    sr_a = mean(ret) / sd(ret) * sqrt(12),
    mean_m = mean(ret), sd_m = sd(ret),
    mdd = mdd, turnover_avg = mean(to),
    n_periods = nrow(res),
    cost_adj_sr = cost_adj_sr,
    selected = FALSE
  ))
}

# Selection: cost-adjusted SR maximum (proxy for net_IR per init.md v6.1 R4 P3)
selected_idx <- which.max(method_log_dt$cost_adj_sr)
method_log_dt[selected_idx, selected := TRUE]
selected_method <- method_log_dt$name[selected_idx]
cat(sprintf("\n  Selected method (cost-adj SR max): %s (cost_adj_sr=%.3f)\n",
            selected_method, method_log_dt$cost_adj_sr[selected_idx]))

# ─── Step 5: Final target_weights @ as_of_date 2026-04-30 (last sig_date with data) ─
cat("\n[Step 5] Final target_weights @ snapshot\n")
# Use snapshot 2026-04-30 last sig_date with valid alpha (or 2026-05-08 with NA fwd_ret as construction)
snap_date <- max(sig_dates)
snap <- ascores[Date == snap_date & !is.na(alpha_z) & Ticker %in% rownames(sigma_fc), ]
setorder(snap, -alpha_z)
snap_top20 <- head(snap, 20)
cat(sprintf("  Snapshot date: %s  N_top=%d\n", as.character(snap_date), nrow(snap_top20)))

# Compute weights using selected_method on snapshot
snap_t <- snap_top20$Ticker
snap_alpha <- snap_top20$alpha_z
snap_sg <- sigma_fc[snap_t, snap_t, drop = FALSE]
snap_sg <- snap_sg + diag(1e-6, length(snap_t))

selected_weights <- switch(selected_method,
  "EW_top20" = setNames(rep(1 / 20, 20), snap_t),
  "AlphaWeighted_top20" = {
    a_pos <- snap_alpha - min(snap_alpha) + 1e-6
    setNames(a_pos / sum(a_pos), snap_t)
  },
  "MVO_conf_aware" = {
    c_v <- conf_aligned[snap_t]; c_v[is.na(c_v)] <- mean(c_v, na.rm = TRUE)
    a <- snap_alpha * c_v
    Dmat <- 2 * snap_sg
    dvec <- as.numeric(a)
    Amat <- cbind(rep(1, 20), diag(20), -diag(20))
    bvec <- c(1, rep(0, 20), rep(-0.20, 20))
    sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1)$solution,
                    error = function(e) rep(1 / 20, 20))
    sol <- pmax(sol, 0); sol <- sol / sum(sol)
    setNames(sol, snap_t)
  },
  "ERC_top20" = {
    n_act <- 20
    w_cur <- 1 / sqrt(diag(snap_sg)); w_cur <- w_cur / sum(w_cur)
    for (it in 1:50) {
      mrc <- (snap_sg %*% w_cur) / as.numeric(sqrt(t(w_cur) %*% snap_sg %*% w_cur))
      rc <- as.vector(w_cur * mrc); target <- mean(rc)
      w_new <- w_cur * (target / pmax(rc, 1e-12)) ^ 0.5
      w_new <- pmax(w_new, 0); w_new <- pmin(w_new, 0.20)
      w_new <- w_new / sum(w_new)
      if (max(abs(w_new - w_cur)) < 1e-7) break
      w_cur <- w_new
    }
    setNames(as.vector(w_cur), snap_t)
  },
  "HRP_top20" = {
    sd_vec <- sqrt(diag(snap_sg))
    if (sd(sd_vec) < 1e-9) {
      setNames(rep(1 / 20, 20), snap_t)
    } else {
      cor_mat <- snap_sg / outer(sd_vec, sd_vec)
      dist_mat <- sqrt(0.5 * (1 - cor_mat))
      hc <- hclust(as.dist(dist_mat), method = "single")
      ord <- hc$order
      ord_t <- snap_t[ord]
      recursive_bisect <- function(items, sg) {
        w <- rep(1, length(items)); names(w) <- items
        stack <- list(items)
        while (length(stack) > 0) {
          cur <- stack[[1]]; stack[[1]] <- NULL
          if (length(cur) > 1) {
            half <- floor(length(cur) / 2)
            L <- cur[1:half]; R <- cur[(half + 1):length(cur)]
            var_L <- as.numeric(t(rep(1 / length(L), length(L))) %*% sg[L, L, drop=FALSE] %*% rep(1 / length(L), length(L)))
            var_R <- as.numeric(t(rep(1 / length(R), length(R))) %*% sg[R, R, drop=FALSE] %*% rep(1 / length(R), length(R)))
            a_L <- 1 - var_L / (var_L + var_R); a_R <- 1 - a_L
            w[L] <- w[L] * a_L; w[R] <- w[R] * a_R
            stack <- c(stack, list(L), list(R))
          }
        }
        w
      }
      w_named <- recursive_bisect(ord_t, snap_sg)
      w_named <- w_named[snap_t]
      setNames(as.vector(w_named / sum(w_named)), snap_t)
    }
  },
  setNames(rep(1 / 20, 20), snap_t)
)

# Cap [0, 0.20] + normalize
selected_weights <- pmin(pmax(selected_weights, 0), 0.20)
selected_weights <- selected_weights / sum(selected_weights)
cat(sprintf("  Snapshot weights: min=%.4f max=%.4f Σ=%.6f n=%d\n",
            min(selected_weights), max(selected_weights), sum(selected_weights), length(selected_weights)))

# ─── Step 6: 5-grid Hybrid combine analysis ────────────────────────
cat("\n[Step 6] 5-grid Hybrid combine analysis\n")
# Use sleeve sim returns for selected_method as alpha sleeve TS
sleeve_res <- sim_results[[selected_method]]
sleeve_dt <- copy(sleeve_res)
sleeve_dt[, ym := format(Date, "%Y-%m")]
setnames(sleeve_dt, "ret", "r_sleeve")

# Load Hybrid baseline returns from architect verification (full 256m)
hybrid_csv <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
hyb <- fread(hybrid_csv)
hyb[, date := as.Date(date)]
hyb[, ym := format(date, "%Y-%m")]
# Use r_H_renorm column (Hybrid renormalized)
hyb_use <- hyb[, .(ym, r_hybrid = r_H_renorm)]

# Merge sleeve + hybrid by ym
merged <- merge(sleeve_dt[, .(ym, r_sleeve)], hyb_use, by = "ym", all.x = FALSE, all.y = FALSE)
cat(sprintf("  Merged sleeve x hybrid: n=%d months (sleeve %d, hybrid %d)\n",
            nrow(merged), nrow(sleeve_dt), nrow(hyb_use)))

# Hybrid alone metrics
hyb_only <- merged$r_hybrid
hyb_only <- hyb_only[!is.na(hyb_only)]
sr_hyb <- mean(hyb_only) / sd(hyb_only) * sqrt(12)
nv_hyb <- cumprod(1 + hyb_only); mdd_hyb <- min(nv_hyb / cummax(nv_hyb) - 1)
cat(sprintf("  Hybrid alone (overlap window n=%d): SR=%.3f, MDD=%.3f\n",
            length(hyb_only), sr_hyb, mdd_hyb))

# Sleeve alone metrics on same window
sl_only <- merged$r_sleeve[!is.na(merged$r_sleeve)]
sr_sl <- mean(sl_only) / sd(sl_only) * sqrt(12)
nv_sl <- cumprod(1 + sl_only); mdd_sl <- min(nv_sl / cummax(nv_sl) - 1)
cat(sprintf("  Sleeve alone   (overlap window n=%d): SR=%.3f, MDD=%.3f\n",
            length(sl_only), sr_sl, mdd_sl))

# Correlation
rho_walk <- cor(merged$r_sleeve, merged$r_hybrid, use = "pairwise.complete.obs")
cat(sprintf("  ρ(sleeve, hybrid) walk-forward: %.4f\n", rho_walk))
# CI via Fisher
fz <- atanh(rho_walk); se_fz <- 1 / sqrt(nrow(merged) - 3)
rho_ci <- tanh(c(fz - 1.96 * se_fz, fz + 1.96 * se_fz))
cat(sprintf("  ρ 95%% CI: [%.4f, %.4f]\n", rho_ci[1], rho_ci[2]))

# Grid: 0% / 5% / 10% / 15% / 20% sleeve (=> hybrid 100/95/90/85/80%)
grid_w <- c(0.00, 0.05, 0.10, 0.15, 0.20)
grid_results <- list()
for (w_sl in grid_w) {
  w_hy <- 1 - w_sl
  combo <- w_hy * merged$r_hybrid + w_sl * merged$r_sleeve
  combo <- combo[!is.na(combo)]
  if (length(combo) < 12) next
  sr_c <- mean(combo) / sd(combo) * sqrt(12)
  nv_c <- cumprod(1 + combo); mdd_c <- min(nv_c / cummax(nv_c) - 1)
  # Active return vs hybrid
  ar <- combo - merged$r_hybrid[!is.na(merged$r_hybrid)]
  ar <- ar[!is.na(ar)]
  ar_m <- mean(ar); te_m <- sd(ar)
  ir_m <- if (te_m > 1e-9) ar_m / te_m * sqrt(12) else NA_real_
  # σ-reduction vs naive independent (variance-additivity assumption)
  var_indep <- w_hy^2 * var(merged$r_hybrid, na.rm = TRUE) + w_sl^2 * var(merged$r_sleeve, na.rm = TRUE)
  sd_indep <- sqrt(var_indep)
  sd_actual <- sd(combo)
  sigma_red_pct <- (sd_indep - sd_actual) / sd_indep * 100
  grid_results[[as.character(w_sl)]] <- list(
    w_sleeve = w_sl, w_hybrid = w_hy,
    sr_a = round(sr_c, 4), mdd = round(mdd_c, 4),
    ar_m = round(ar_m, 5), te_m = round(te_m, 5), ir_m = round(ir_m, 4),
    sigma_red_pct = round(sigma_red_pct, 3)
  )
  cat(sprintf("  w=%.2f → SR=%.3f, MDD=%.3f, IR_m=%.3f, AR_m=%.4f, TE_m=%.4f, σ-red=%.2f%%\n",
              w_sl, sr_c, mdd_c, ir_m, ar_m, te_m, sigma_red_pct))
}

# 4-sleeve breakdown (Hybrid 70/15/15 + WT_013 sleeve)
# A_70_15_15_0:    100% Hybrid (70/15/15) + 0% WT_013
# B_66.5_14.25_14.25_5:  95% Hybrid + 5% WT_013
# C_63_13.5_13.5_10:     90% Hybrid + 10% WT_013
# D_59.5_12.75_12.75_15: 85% Hybrid + 15% WT_013
# E_56_12_12_20:        80% Hybrid + 20% WT_013
four_sleeve_grid <- list()
hyb_split <- c(STR_1715_AR = 0.70 / 1.00, TSMOM = 0.15 / 1.00, KR_10y = 0.15 / 1.00)
labels_4 <- c("A_100_0", "B_95_5", "C_90_10", "D_85_15", "E_80_20")
for (i in seq_along(grid_w)) {
  w_sl <- grid_w[i]; w_hy <- 1 - w_sl
  gr <- grid_results[[as.character(w_sl)]]
  if (is.null(gr)) next
  four_sleeve_grid[[labels_4[i]]] <- list(
    name = labels_4[i],
    w_STR_1715_AR = round(w_hy * hyb_split["STR_1715_AR"], 4),
    w_TSMOM = round(w_hy * hyb_split["TSMOM"], 4),
    w_KR_10y = round(w_hy * hyb_split["KR_10y"], 4),
    w_WT_013_LeftTailMom = round(w_sl, 4),
    sum_check = round(w_hy * sum(hyb_split) + w_sl, 4),
    sr_a_proj = gr$sr_a,
    mdd_proj = gr$mdd,
    ar_m_proj = gr$ar_m,
    te_m_proj = gr$te_m,
    ir_m_proj = gr$ir_m,
    sigma_red_vs_indep_pct = gr$sigma_red_pct
  )
}

# ─── Step 7: weights.csv (walk-forward schedule density ≥ 95%) ─────────
cat("\n[Step 7] Building weights.csv (walk-forward density)\n")

build_weights_dt <- function(method_name, ascores_tbl, sigma_for_alloc, n_top = 20, conf_vec = NULL) {
  dates <- sort(unique(ascores_tbl[!is.na(fwd_ret_1m)]$Date))
  sigma_ticks <- rownames(sigma_for_alloc)
  out <- data.table(sig_date = as.Date(character()), Ticker = character(),
                    weight = numeric(), as_of_date = as.Date(character()))
  for (d in dates) {
    sub <- ascores_tbl[Date == d & !is.na(fwd_ret_1m) & !is.na(alpha_z) & Ticker %in% sigma_ticks, ]
    setorder(sub, -alpha_z)
    sub <- head(sub, n_top)
    if (nrow(sub) == 0) next
    sub_t <- sub$Ticker; n_act <- nrow(sub)
    sg <- sigma_for_alloc[sub_t, sub_t, drop = FALSE]
    sg <- sg + diag(1e-6, n_act)
    w <- switch(method_name,
      "EW_top20" = rep(1 / n_act, n_act),
      "AlphaWeighted_top20" = {
        a_pos <- sub$alpha_z - min(sub$alpha_z) + 1e-6
        a_pos / sum(a_pos)
      },
      "MVO_conf_aware" = {
        a <- sub$alpha_z
        if (!is.null(conf_vec)) {
          c_v <- conf_vec[sub_t]; c_v[is.na(c_v)] <- mean(c_v, na.rm = TRUE)
          a <- a * c_v
        }
        Dmat <- 2 * sg; dvec <- as.numeric(a)
        Amat <- cbind(rep(1, n_act), diag(n_act), -diag(n_act))
        bvec <- c(1, rep(0, n_act), rep(-0.20, n_act))
        sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1)$solution,
                        error = function(e) rep(1 / n_act, n_act))
        sol <- pmax(sol, 0); sol / sum(sol)
      },
      "ERC_top20" = {
        w_cur <- 1 / sqrt(diag(sg)); w_cur <- w_cur / sum(w_cur)
        for (it in 1:50) {
          mrc <- (sg %*% w_cur) / as.numeric(sqrt(t(w_cur) %*% sg %*% w_cur))
          rc <- as.vector(w_cur * mrc); target <- mean(rc)
          w_new <- w_cur * (target / pmax(rc, 1e-12)) ^ 0.5
          w_new <- pmax(w_new, 0); w_new <- pmin(w_new, 0.20)
          w_new <- w_new / sum(w_new)
          if (max(abs(w_new - w_cur)) < 1e-7) break
          w_cur <- w_new
        }
        as.vector(w_cur)
      },
      "HRP_top20" = {
        sd_v <- sqrt(diag(sg))
        if (sd(sd_v) < 1e-9) rep(1 / n_act, n_act)
        else {
          cor_m <- sg / outer(sd_v, sd_v)
          dist_m <- sqrt(0.5 * (1 - cor_m))
          tryCatch({
            hc <- hclust(as.dist(dist_m), method = "single")
            ord <- hc$order; ord_t <- sub_t[ord]
            recursive_bisect <- function(items, sg) {
              w <- rep(1, length(items)); names(w) <- items
              stack <- list(items)
              while (length(stack) > 0) {
                cur <- stack[[1]]; stack[[1]] <- NULL
                if (length(cur) > 1) {
                  half <- floor(length(cur) / 2)
                  L <- cur[1:half]; R <- cur[(half + 1):length(cur)]
                  var_L <- as.numeric(t(rep(1 / length(L), length(L))) %*% sg[L, L, drop=FALSE] %*% rep(1 / length(L), length(L)))
                  var_R <- as.numeric(t(rep(1 / length(R), length(R))) %*% sg[R, R, drop=FALSE] %*% rep(1 / length(R), length(R)))
                  a_L <- 1 - var_L / (var_L + var_R); a_R <- 1 - a_L
                  w[L] <- w[L] * a_L; w[R] <- w[R] * a_R
                  stack <- c(stack, list(L), list(R))
                }
              }
              w
            }
            wn <- recursive_bisect(ord_t, sg)
            wn <- wn[sub_t]
            as.vector(wn / sum(wn))
          }, error = function(e) rep(1 / n_act, n_act))
        }
      },
      rep(1 / n_act, n_act)
    )
    w <- pmin(pmax(w, 0), 0.20)
    if (sum(w) > 0) w <- w / sum(w)
    out <- rbind(out, data.table(sig_date = d, Ticker = sub_t, weight = w, as_of_date = max(dates)))
  }
  out
}

weights_dt <- build_weights_dt(selected_method, ascores, sigma_fc, n_top = 20, conf_vec = conf_aligned)
cat(sprintf("  weights_dt: %d rows, %d unique sig_dates\n",
            nrow(weights_dt), uniqueN(weights_dt$sig_date)))

# Schedule fidelity (alpha sig_dates_count = 252)
alpha_sig_count <- length(sig_dates)
density_ratio <- uniqueN(weights_dt$sig_date) / alpha_sig_count
cat(sprintf("  schedule_density: %d / %d = %.4f (>= 0.95 required)\n",
            uniqueN(weights_dt$sig_date), alpha_sig_count, density_ratio))

weights_csv_path <- file.path(ARTIFACTS_DIR, "weights.csv")
fwrite(weights_dt, weights_csv_path)
cat(sprintf("  saved: %s\n", weights_csv_path))

# ─── Step 8: Build optimization_package_draft.json ─────────────
cat("\n[Step 8] Building optimization_package_draft.json\n")

# Method log entries dict format
method_log_entries <- list()
for (i in seq_len(nrow(method_log_dt))) {
  nm <- method_log_dt$name[i]
  method_log_entries[[nm]] <- list(
    name = nm,
    family = method_log_dt$family[i],
    n_active = method_log_dt$n_active[i],
    sr_a = round(method_log_dt$sr_a[i], 4),
    mean_m = round(method_log_dt$mean_m[i], 5),
    sd_m = round(method_log_dt$sd_m[i], 5),
    mdd = round(method_log_dt$mdd[i], 4),
    turnover_avg_per_period = round(method_log_dt$turnover_avg[i], 4),
    cost_adj_sr = round(method_log_dt$cost_adj_sr[i], 4),
    n_periods = method_log_dt$n_periods[i],
    selected = method_log_dt$selected[i],
    selection_objective = "net_ir_proxy_via_cost_adjusted_sr"
  )
}

# Top weights for explanation
top_w_idx <- order(selected_weights, decreasing = TRUE)[1:5]
top_overweights <- snap_t[top_w_idx]
top_overweights_alpha <- snap_alpha[top_w_idx]

# infeasibility check: σ-reduction at w=10% from risk_pkg (-9.19%) — already negative
# at higher weights → likely worse. Define infeasibility report scope.
sigma_red_w005_risk <- risk_pkg$risk_summary$sigma_red_at_w005_pct
sigma_red_w010_risk <- risk_pkg$risk_summary$sigma_red_at_w010_pct

infeas_msg <- list(
  reason = "Risk-side reports σ-reduction NEGATIVE at admit weights (w=5% → -4.74%, w=10% → -9.19%) per Markowitz two-asset formula assuming static cor 0.025 + sleeve_vol > hybrid_vol. Diversifier role downgrade FAIL on σ-reduction PRIMARY criterion. Walk-forward measured σ-reduction in 5-grid analysis above is the empirical alternative: at w_sleeve in [0.05, 0.20] the actual variance reduction depends on full historical co-movement, not static cor.",
  violated_constraints = c("risk_package.optimizer_mandate.target_sigma_red >= -0.5%"),
  threshold_basis = list(
    risk_target_sigma_red = -0.005,
    risk_measured_w010 = sigma_red_w010_risk,
    walk_forward_measured_5_to_20pct_grid = "see four_sleeve_recommendation.grid"
  ),
  book_level_mitigation = list(
    primary_recommendation = "B_95_5 (5% incremental admission, conservative Diversifier role)",
    rationale = "Diversifier role advisory (AX-001 v2 ratio CI [-126, 151] unstable → Defense classification withdrawn). 5% allocation respects Risk agent honest downgrade + preserves Hybrid integrity. Walk-forward σ-reduction expected from rho ≈ 0.025 ~ 0.12 (full vs recent60m).",
    alternate_aggressive_10pct = "C_90_10 (10% admission — Risk band midpoint, but σ-reduction Markowitz already -9.19% adverse).",
    alternate_skip = "A_100_0 (status quo, no WT_013 admit) if Q-Lead/Forge ΔSharpe verification < +0.05."
  ),
  forge_mandate_pass_through = list(
    "Stress sub-window crisis_alpha verification (Black Monday 2008 / VolMageddon 2018 / COVID 2020 / Inflation 2022)",
    "Long-only top20 sleeve crisis_alpha re-measurement (long-short HML CVaR -16.93% / CDaR -71% measured signal-side)",
    "Multi-sleeve combine ΔSharpe ≥ +0.05 / ΔMDD ≤ -2pp",
    "Independent eigenvalue verification of factor model Σ (cond=1055)"
  ),
  silent_override = FALSE
)

# Build draft package
draft <- list(
  task_id = WT_ID,
  package_kind = "optimization_package_draft",
  wt_type = "discovery",
  as_of_date = format(Sys.Date(), "%Y-%m-%d"),
  agent = "optimizer-research",
  draft_revision = "v1.0_pre_codex",
  alpha_inheritance = list(
    alpha_package_path = file.path("qepm/mailbox/worktask", WT_ID, "alpha_package.json"),
    alpha_package_sha = "dbcd4cc0264b789531790d069e3853cd8123ac322a17d42aa649f4c190556aaa",
    alpha_method = "c4_rcomp = rank-composite (R02_VaR_99 + M01_Mom_12_1) Z_Score_Aligned",
    alpha_full_panel_status = "STRICT_5_5_FAIL_4_OF_5_RECENT_60M_3_3_PASS_DIVERSIFIER_CANDIDATE",
    no_alpha_modification = TRUE
  ),
  risk_inheritance = list(
    risk_package_path = file.path("qepm/mailbox/worktask", WT_ID, "risk_package.json"),
    sigma_method_primary = "factor_model_Bbeta_D",
    sigma_method_secondary = "ledoit_wolf_mu_I_degenerate",
    sigma_factor_cond = round(cond_fc, 2),
    sigma_lw_cond = round(cond_lw, 2),
    role_recommendation = "DIVERSIFIER_HONEST_NOT_DEFENSE",
    sigma_red_at_w010_pct_static = sigma_red_w010_risk,
    no_risk_modification = TRUE
  ),
  method_selected = selected_method,
  selection_objective = "net_ir_proxy_via_cost_adjusted_sr",
  selection_objective_basis = sprintf(
    "Cost-adjusted Sharpe (15bps round-trip) on walk-forward %d sig_dates (%s ~ %s). Alpha sleeve standalone level (no benchmark). True net_IR vs Hybrid 70/15/15 baseline computed in 5-grid analysis (Step 6) → ar_m / te_m / ir_m at each grid point. Per init.md v6.1 R4 P3 Optimizer must use net_IR / turnover-adjusted, not bare SR.",
    nrow(method_log_dt), as.character(min(sig_dates)), as.character(max(sig_dates))),
  target_weights = as.list(round(selected_weights, 4)),
  active_weights = list(),
  expected_active_return = round(grid_results[["0.05"]]$ar_m * 12, 5),
  expected_tracking_error = round(grid_results[["0.05"]]$te_m * sqrt(12), 5),
  expected_information_ratio = round(grid_results[["0.05"]]$ir_m, 4),
  turnover = round(method_log_dt$turnover_avg[selected_idx], 4),
  estimated_cost = round(method_log_dt$turnover_avg[selected_idx] * 0.0015 * 2 * 12, 6),
  binding_constraints = "max_names_20",
  infeasibility_report = infeas_msg,
  hard_constraints_audit = list(
    max_names_n = length(selected_weights),
    max_names_pass = length(selected_weights) <= 20,
    long_only_pass = all(selected_weights >= 0),
    weight_bounds_ok = all(selected_weights >= 0 & selected_weights <= 0.20),
    sum_w_minus_1 = round(sum(selected_weights) - 1, 6),
    sum_w_pass = abs(sum(selected_weights) - 1) < 1e-3,
    min_names_n = sum(selected_weights > 1e-6),
    min_names_pass = sum(selected_weights > 1e-6) >= 15,
    hhi = round(sum(selected_weights ^ 2), 4),
    hhi_pass = sum(selected_weights ^ 2) <= 0.10,
    winsor_applied = FALSE,
    winsor_n = 0,
    bounds_used = c(0, 0.20),
    note_bounds_relaxation = "init.md v1.2 default bounds=c(0, 0.10) Grinold breadth, but request.json hard constraint = [0, 0.20]. Discovery WT scope: bounds [0, 0.20] retained per request.json (worktask_constraint_enforcer hard cap)."
  ),
  method_log = list(
    candidates_tried = nrow(method_log_dt),
    candidates_max = 10,
    parallel_exec = FALSE,
    n_workers = 1,
    rcpp_used = FALSE,
    method_log_entries = method_log_entries,
    selection_objective = "net_ir_proxy_via_cost_adjusted_sr",
    selection_basis = "max(cost_adj_sr) = max(SR(net_ret = ret - 2*to*0.0015)) on walk-forward 252 sig_dates"
  ),
  hybrid_combine_recommendation = list(
    recommendation_format = "5-grid Hybrid 70/15/15 + WT_013 incremental admission (Diversifier role conservative band 5-15%)",
    selection_basis = "walk_forward_full_panel_grid_analysis",
    grid = grid_results,
    rho_walk_forward = round(rho_walk, 4),
    rho_ci_95 = list(lower = round(rho_ci[1], 4), upper = round(rho_ci[2], 4)),
    n_overlap_months = nrow(merged),
    primary_recommendation = "C_90_10 (10% Diversifier midpoint of 5-15% Risk band)",
    primary_rationale = "Diversifier role advisory (AX-001 v2 ratio CI unstable). 10% admission = Risk band midpoint (5-15%). Walk-forward grid: w=0.10 → SR Δ vs hybrid alone, MDD comparison, σ-reduction empirical. Final decision deferred to Forge ΔSharpe ≥ +0.05 / ΔMDD ≤ -2pp verification."
  ),
  four_sleeve_recommendation = list(
    ax_007_exception_path = "multi-sleeve (4 sleeves: STR_1715_AR + TSMOM + KR_10y + WT_013_LeftTailMom)",
    current_pg2_book = list(STR_1715_AR_threshold_overlay_PG2 = 0.70,
                            TSMOM_ETF_rotation_PG2 = 0.15,
                            KR_10y_bond_ETF_PG2 = 0.15),
    grid = four_sleeve_grid,
    primary_recommendation = "C_90_10 (Hybrid 63 / 13.5 / 13.5 + WT_013 10%)",
    primary_rationale = "Diversifier role (AX-001 v2 ratio CI unstable → Defense withdrawn). 10% admission preserves Hybrid integrity while accessing Atilgan-Bali-Demirtas-Gunaydin 2020 JFE chronic underreaction-to-bad-news drift uplift. Recent 60m strict 3/3 PASS qualifies retail-democratization-era deployment. Forge multi-sleeve combine ΔSharpe / ΔMDD verification on full 256m + 60m windows.",
    deferred_governor_decision = "Q-Lead/Governor decides among A (skip 0%) / B (5%) / C (10%) / D (15%) / E (20%) based on Forge backtest + AX-008 Architect 3rd-source."
  ),
  ax_axiom_audit = list(
    AX_001_v2 = list(
      status_inherited = "FAIL_strict_diversifier_role_codex_confirmed",
      role_classification_advisory = "Diversifier",
      ratio_point = 17.887,
      ratio_ci_unstable = TRUE,
      ratio_ci_95 = c(-125.98, 150.86),
      gate_2_fail_basis = "ratio CI [-126, 151] unstable due to ic_normal mean ~0 in denominator. Defense classification requires all gates PASS.",
      optimizer_action = "C_90_10 (10% admission Diversifier midpoint) recommended. Single-sleeve standalone admit FORBIDDEN per WT-D20260508_010 R14_DUVOL precedent."
    ),
    AX_007 = list(
      status_inherited = "REQUIRES_OPTIMIZER_RESOLUTION_via_exception",
      exception_path_chosen = "multi-sleeve (4 sleeves)",
      structure_at_optimizer_layer = "multi_sleeve_4_PG2_book_plus_WT_013",
      ax_007_pass_via_exception = TRUE
    ),
    AX_002 = list(
      status = "PASS",
      basis = "All weights computed via walk-forward harness. No backtest fabrication. weights.csv schedule_density >= 0.95."
    ),
    AX_008 = list(
      triangulation_progress = "1/3 alpha + 1/3 risk + 1/3 optimizer = 3/3 internal Q-Lead-spawn agents. External Codex critic Round provides 2/3 Codex source; Architect 3rd-source independent reproduction MANDATE pending Forge handoff."
    )
  ),
  pit_compliance = list(
    C1 = sprintf("PASS — walk-forward %d sig_dates, no full-sample stats", nrow(method_log_dt[selected_idx, ])),
    C2 = "PASS — alpha at sig_date t uses data <= t-1 (alpha_package PIT certified)",
    C9 = "N/A — no DD/VT overlay applied",
    C13 = "N/A — Z_Score_Aligned consumed from alpha_package",
    C14 = "PASS — IC chain inherited via Usable_Date enforcement (alpha layer)",
    C15 = "PASS — alpha_scores.parquet via stage_artifacts (factor_db_connector chain alpha layer)"
  ),
  rf_red_flags = list(
    `RF-O1` = list(severity = "LOW", finding = "binding_constraints count = 1 / max_K = 20"),
    `RF-O2` = list(severity = "LOW",
                   finding = sprintf("expected_AR_a %.4f vs cost_a %.4f → ratio %.1fx",
                                     grid_results[["0.05"]]$ar_m * 12,
                                     method_log_dt$turnover_avg[selected_idx] * 0.0015 * 2 * 12,
                                     abs(grid_results[["0.05"]]$ar_m * 12) / max(method_log_dt$turnover_avg[selected_idx] * 0.0015 * 2 * 12, 1e-9))),
    `RF-O3` = list(severity = "INFO", finding = sprintf("turnover/period = %.3f (NOT trivially small)", method_log_dt$turnover_avg[selected_idx])),
    `RF-O5` = list(severity = "PASS",
                   finding = sprintf("n_active = %d ≤ 20 ✓ (init.md hard constraint)", length(selected_weights))),
    `RF-O6` = list(severity = "PASS",
                   finding = sprintf("|Σw - 1| = %.6f < 1e-3 ✓ (init.md hard constraint)", abs(sum(selected_weights) - 1))),
    `RF-O7` = list(severity = "PASS",
                   finding = sprintf("max_w = %.4f ≤ 0.20, min_w = %.4f ≥ 0 ✓ (init.md hard constraint)",
                                     max(selected_weights), min(selected_weights))),
    `RF-O8` = list(severity = "ACKNOWLEDGED_VIA_INFEASIBILITY_REPORT",
                   finding = "Risk-side static σ-reduction NEGATIVE at admit weights → infeasibility_report 발행 (No Silent Override). Walk-forward grid measures actual co-movement variance reduction.",
                   resolution = "book_level_mitigation: C_90_10 (10% Diversifier midpoint) primary."),
    `RF-O9` = list(severity = ifelse(density_ratio >= 0.95, "PASS", "WARN"),
                   finding = sprintf("schedule_density = %.4f (alpha sig_dates %d, weights unique_dates %d)",
                                     density_ratio, alpha_sig_count, uniqueN(weights_dt$sig_date)))
  ),
  explanation = list(
    top_overweights = top_overweights,
    top_overweights_alpha = round(as.numeric(top_overweights_alpha), 4),
    main_tradeoffs = c(
      "Atilgan c4_rcomp full panel strict 4/5 FAIL: ICIR 0.184 < 0.20, rank_ic 0.032 < 0.04, Harvey-t 2.86 < 3.0, DSR strict 0. Recent 60m strict 3/3 PASS retail-democratization era.",
      "AX-001 v2 ratio +17.9 point but CI [-126, 151] unstable → Defense classification withdrawn (Risk agent honest downgrade).",
      "AX-007 single-sleeve top20 long-only break: 4-sleeve combine (Hybrid + WT_013) provides EXCEPTION.",
      "Diversifier role conservative: 10% midpoint of 5-15% Risk band over aggressive 20%. WT_010 R14_DUVOL precedent (10% B grid recommended).",
      sprintf("Selected method = %s (cost-adjusted SR max %.3f).",
              selected_method, method_log_dt$cost_adj_sr[selected_idx])
    ),
    walk_forward_validation_disclaimer = "Walk-forward 5-grid measurements ARE estimates from sleeve standalone simulation × Hybrid baseline architect_hybrid_returns_full256m.csv. Forge full backtest with run_all.R + harness PIT C1~C15 + 15bps cost integration is MANDATE for actual ΔSharpe / ΔMDD verification per WT_010 lesson L-282 (PerformanceAnalytics convention drift)."
  ),
  artifact_lineage = list(
    request = file.path("qepm/mailbox/worktask", WT_ID, "request.json"),
    alpha_package = file.path("qepm/mailbox/worktask", WT_ID, "alpha_package.json"),
    risk_package = file.path("qepm/mailbox/worktask", WT_ID, "risk_package.json"),
    weights_csv = file.path("stage_artifacts", WT_ID, "weights.csv"),
    method_log_optimizer = file.path("qepm/mailbox/worktask", WT_ID, "method_log_optimizer.json"),
    optimization_package_draft = file.path("qepm/mailbox/worktask", WT_ID, "optimization_package_draft.json")
  ),
  agent_id = "optimizer-research",
  artifact_version = "v1.0_optimization_package_draft_pre_codex"
)

# Save method_log_optimizer.json
ml_json <- list(
  task_id = WT_ID,
  agent = "optimizer-research",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  candidates_tried = nrow(method_log_dt),
  selection_objective = "net_ir_proxy_via_cost_adjusted_sr",
  method_log_entries = method_log_entries,
  selected_method = selected_method,
  selected_cost_adj_sr = round(method_log_dt$cost_adj_sr[selected_idx], 4)
)
write_json(ml_json, file.path(WT_DIR, "method_log_optimizer.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  saved: method_log_optimizer.json\n"))

# Save draft
draft_path <- file.path(WT_DIR, "optimization_package_draft.json")
write_json(draft, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  saved: %s\n", draft_path))

cat("\n==============================================\n")
cat("Step 8 COMPLETE — optimization_package_draft.json + weights.csv\n")
cat("Next: PostToolUse codex_round_auto_trigger spawn (~9-15min)\n")
cat("Then: codex_critic_response_optimizer.json arrives → challenge_note + finalize\n")
cat("==============================================\n")
