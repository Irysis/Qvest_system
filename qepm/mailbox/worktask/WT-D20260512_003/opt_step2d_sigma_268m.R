#==============================================================================
# WT-D20260512_003 Optimizer Step 2d — Σ-based 268m walk-forward
#
# 3 Σ-based methods × 268m schedule with rolling 60d sample covariance.
#   1. MVO_lam1_rolling_2604 (confidence-aware MVO, rolling sample Σ)
#   2. HRP_ward_rolling (rolling 60d cor → ward.D2 → recursive bisection)
#   3. ERC_rolling (rolling 60d sample Σ → equal risk contribution)
#
# PIT 정합: t-day rolling 60d returns (t-1 cutoff, no future) → cov → weights → t-month return.
# Estimated time: 85s × 3 = ~260s (rolling cov per sig_date).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(quadprog)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step2d] Σ-based 268m Walk-Forward (rolling sample cov)\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
mailbox <- file.path("qepm/mailbox/worktask", WT)
stage <- file.path("stage_artifacts", "WT_D20260512_003")

ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
setkey(asc, Date, Ticker)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

MAX_NAMES <- 20L; MIN_NAMES <- 5L
UB <- 0.20; LB <- 0.0; TARGET_SUM <- 1.0
LIQ_THRESHOLD <- 5e7
COMMISSION_BPS <- 15

sig_dates <- sort(unique(asc$Date))
cat(sprintf("sig_dates: %d (%s ~ %s)\n",
            length(sig_dates),
            as.character(min(sig_dates)),
            as.character(max(sig_dates))))

# ─── Helpers (re-used from step2b) ─────────────────────────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0
  w[w < lb] <- lb
  if (sum(w) == 0) {
    w <- rep(target_sum / length(w), length(w))
    return(w)
  }
  w <- w / sum(w) * target_sum
  iter <- 0
  while (any(w > ub + 1e-12) && sum(w) > 0 && iter < 100) {
    excess_idx <- which(w > ub)
    excess <- sum(w[excess_idx]) - length(excess_idx) * ub
    w[excess_idx] <- ub
    free <- setdiff(seq_along(w), excess_idx)
    if (length(free) == 0) break
    if (sum(w[free]) == 0) w[free] <- excess / length(free)
    else w[free] <- w[free] + excess * (w[free] / sum(w[free]))
    w <- w / sum(w) * target_sum
    iter <- iter + 1
  }
  w
}

mvo_solve <- function(alpha_t, Sigma_sub, lambda = 1.0, psi = 0.3,
                       confidence = NULL, lb = 0, ub = 0.20, target_sum = 1) {
  D <- length(alpha_t)
  if (is.null(confidence)) confidence <- rep(1.0, D)
  fu_diag <- psi * (1 - confidence)^2
  Dmat <- lambda * Sigma_sub + diag(2 * fu_diag)
  diag(Dmat) <- diag(Dmat) + 1e-6
  dvec <- as.vector(alpha_t)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(target_sum, rep(lb, D), rep(-ub, D))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                  error = function(e) NULL)
  if (is.null(res)) return(normalize_long_only(rep(1/D, D), lb=lb, ub=ub, target_sum=target_sum))
  w <- res$solution
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

erc_solve <- function(Sigma_sub, lb = 0, ub = 0.20, target_sum = 1,
                       n_iter = 200, tol = 1e-7) {
  D <- nrow(Sigma_sub)
  w <- rep(target_sum/D, D)
  names(w) <- rownames(Sigma_sub)
  for (k in seq_len(n_iter)) {
    mrc <- as.vector(Sigma_sub %*% w)
    target_rc <- mean(w * mrc)
    grad <- mrc - target_rc / pmax(w, 1e-8)
    w_new <- pmax(w - 0.003 * grad, 1e-8)
    w_new <- w_new / sum(w_new) * target_sum
    if (max(abs(w_new - w)) < tol) break
    w <- w_new
  }
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

hrp_ward <- function(Sigma_sub, lb = 0, ub = 0.20) {
  cor_s <- tryCatch(cov2cor(Sigma_sub), error = function(e) NULL)
  if (is.null(cor_s)) {
    return(normalize_long_only(rep(1/nrow(Sigma_sub), nrow(Sigma_sub)),
                                lb=lb, ub=ub, target_sum=1))
  }
  cor_s <- pmin(pmax(cor_s, -0.999), 0.999)
  d <- 0.5 * (1 - cor_s); d[d < 0] <- 0; diag(d) <- 0
  dist_mat <- as.dist(sqrt(d))
  hc <- tryCatch(hclust(dist_mat, method = "ward.D2"), error = function(e) NULL)
  if (is.null(hc)) {
    return(normalize_long_only(rep(1/nrow(Sigma_sub), nrow(Sigma_sub)),
                                lb=lb, ub=ub, target_sum=1))
  }
  ord <- hc$order
  common <- rownames(Sigma_sub)[ord]
  rb <- function(idx, w_alloc = 1) {
    if (length(idx) == 1L) return(setNames(w_alloc, idx))
    h <- ceiling(length(idx) / 2)
    L <- idx[1:h]; R <- idx[(h+1):length(idx)]
    vL <- sum(diag(Sigma_sub[L, L, drop=FALSE]))
    vR <- sum(diag(Sigma_sub[R, R, drop=FALSE]))
    aL <- vR / (vL + vR + 1e-12)
    aR <- 1 - aL
    c(rb(L, w_alloc * aL), rb(R, w_alloc * aR))
  }
  w <- rb(common)
  w_full <- setNames(rep(0, nrow(Sigma_sub)), rownames(Sigma_sub))
  w_full[names(w)] <- w
  if (sum(w_full) > 0) w_full <- w_full / sum(w_full)
  normalize_long_only(w_full, lb = lb, ub = ub, target_sum = 1)
}

# ─── Walk-forward with rolling cov ──────────────────────────────
run_walk_forward_cov <- function(weight_fn, weight_fn_name) {
  monthly <- vector("list", length(sig_dates) - 1L)
  weight_records <- vector("list", length(sig_dates) - 1L)
  w_prev <- NULL

  for (i in seq_len(length(sig_dates) - 1L)) {
    sig_label <- sig_dates[i]
    next_sig_label <- sig_dates[i + 1L]
    start_d <- raw[Date >= sig_label, Date[1L]]
    if (is.na(start_d)) next
    end_d <- raw[Date >= next_sig_label, Date[1L]]
    if (is.na(end_d)) end_d <- max(raw$Date)

    panel_t <- asc[Date == sig_label]
    if (nrow(panel_t) == 0L) next

    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -z_blend_composite)
    N_target <- min(MAX_NAMES, nrow(panel_t))
    if (N_target < 5L) next
    picks <- panel_t[seq_len(N_target)]
    alpha_t <- picks$z_blend_composite
    names(alpha_t) <- picks$Ticker
    conf_t <- setNames(picks$confidence, picks$Ticker)

    liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                     .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
    tickers_liq <- intersect(names(alpha_t), liquid_tk)
    if (length(tickers_liq) < 5L) tickers_liq <- names(alpha_t)
    alpha_t_liq <- alpha_t[tickers_liq]
    conf_t_liq <- conf_t[tickers_liq]

    # Rolling 60d cov build
    ret_window <- raw[Date < start_d & Ticker %in% tickers_liq, .(Date, Ticker, Ret)]
    ret_wide <- dcast(ret_window, Date ~ Ticker, value.var = "Ret", fill = 0)
    if (nrow(ret_wide) > 60) ret_wide <- ret_wide[(nrow(ret_wide)-59):nrow(ret_wide)]
    if (nrow(ret_wide) < 30) next
    ret_mat <- as.matrix(ret_wide[, -1])
    valid_cols <- which(colSums(!is.na(ret_mat) & ret_mat != 0) >= 20)
    if (length(valid_cols) < 5L) next
    ret_mat <- ret_mat[, valid_cols, drop=FALSE]
    ret_mat[is.na(ret_mat)] <- 0
    cov_s <- cov(ret_mat)
    # Light shrinkage to identity (10%)
    avg_var <- mean(diag(cov_s))
    cov_s <- 0.9 * cov_s + 0.1 * diag(avg_var, nrow(cov_s))
    diag(cov_s) <- diag(cov_s) + 1e-6

    alpha_t_use <- alpha_t_liq[colnames(ret_mat)]
    conf_t_use <- conf_t_liq[colnames(ret_mat)]
    ub_use <- if (regime_i == "CRISIS") min(UB, 0.10) else UB

    w_risk <- tryCatch(
      weight_fn(alpha_t_use, cov_s, conf_t_use, ub_use),
      error = function(e) {
        cat(sprintf("  [%s @ %s] error: %s, fallback EW\n",
                    weight_fn_name, sig_label, conditionMessage(e)))
        normalize_long_only(rep(1/length(alpha_t_use), length(alpha_t_use)),
                             lb = LB, ub = ub_use)
      }
    )
    if (is.null(w_risk) || any(is.na(w_risk)) || abs(sum(w_risk) - 1) > 0.01) {
      w_risk <- normalize_long_only(rep(1/length(alpha_t_use), length(alpha_t_use)),
                                     lb = LB, ub = ub_use)
      names(w_risk) <- names(alpha_t_use)
    }
    if (is.null(names(w_risk))) names(w_risk) <- names(alpha_t_use)

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

    to <- if (is.null(w_prev)) sum(w_risk) else {
      all_tk <- union(names(w_risk), names(w_prev))
      w_new_f <- setNames(rep(0, length(all_tk)), all_tk)
      w_prev_f <- setNames(rep(0, length(all_tk)), all_tk)
      w_new_f[names(w_risk)] <- w_risk
      w_prev_f[names(w_prev)] <- w_prev
      sum(abs(w_new_f - w_prev_f))
    }
    cost <- to * COMMISSION_BPS / 10000
    port_ret_net <- port_ret_gross - cost

    monthly[[i]] <- data.table(
      sig_date = sig_label, start_d = start_d, end_d = end_d,
      port_ret_gross = port_ret_gross, port_ret_net = port_ret_net,
      turnover = to, n_held = length(w_risk),
      regime = regime_i, method = weight_fn_name, cost = cost
    )
    weight_records[[i]] <- data.table(
      sig_date = sig_label, ticker = names(w_risk),
      weight = as.numeric(w_risk), regime = regime_i, method = weight_fn_name
    )
    w_prev <- w_risk
  }

  list(monthly = rbindlist(monthly, fill = TRUE),
       weights = rbindlist(weight_records, fill = TRUE))
}

# ─── Method wrappers (signature: alpha_t, cov_s, conf_t, ub) ────
fn_mvo_lam1 <- function(alpha_t, cov_s, conf_t, ub) {
  mvo_solve(alpha_t, cov_s, lambda = 1.0, psi = 0.3, confidence = conf_t,
            lb = LB, ub = ub)
}
fn_hrp <- function(alpha_t, cov_s, conf_t, ub) {
  w <- hrp_ward(cov_s, lb = LB, ub = ub)
  setNames(as.numeric(w[names(alpha_t)]), names(alpha_t))
}
fn_erc <- function(alpha_t, cov_s, conf_t, ub) {
  w <- erc_solve(cov_s, lb = LB, ub = ub)
  setNames(as.numeric(w[names(alpha_t)]), names(alpha_t))
}

methods_sigma <- list(
  MVO_lam1_rolling = fn_mvo_lam1,
  HRP_ward_rolling = fn_hrp,
  ERC_rolling = fn_erc
)

cat(sprintf("\n[Σ-based methods] %d candidates × 268m\n", length(methods_sigma)))

t0 <- Sys.time()
results_sigma <- list()
for (m in names(methods_sigma)) {
  cat(sprintf("  Running %s ... ", m))
  t1 <- Sys.time()
  out <- run_walk_forward_cov(methods_sigma[[m]], weight_fn_name = m)
  elapsed <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  cat(sprintf("%d periods | %.1fs\n", nrow(out$monthly), elapsed))
  results_sigma[[m]] <- out
}
total_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\nTotal Σ-based walk-forward: %.1f sec\n", total_secs))

saveRDS(results_sigma, file.path(stage, "opt_method_shopping_sigma.rds"))
cat(sprintf("Saved: %s\n", file.path(stage, "opt_method_shopping_sigma.rds")))
cat("[OPT-Step2d] DONE\n")
