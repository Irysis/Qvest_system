#==============================================================================
# WT-D20260512_003 Optimizer Step 8 — Re-optimization with TO ≤ 6.0 hard filter
#
# Codex REJECT C1+C2+C5 disposition:
#   - TO hard cap 6.0 (Hurdle Rule v2.2 hard fail)
#   - MDD < -45% hard fail
#   - Selection objective: hard filter cascade
#
# Re-design:
#   - Add buffer rule keep_n=15, entry_n=20 (top 20 enter / bottom 15 keep)
#   - Add stronger TOphi (phi=5, 10) for linear_tilt
#   - Add EW with buffer keep_n
#
# If no method passes both TO ≤ 6.0 AND MDD < -45% → INFEASIBILITY_REPORT
# If some method passes → emit that method
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step8] Re-optimize with TO ≤ 6.0 + MDD < -45% hard filter\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
stage <- file.path("stage_artifacts", "WT_D20260512_003")
mailbox <- file.path("qepm/mailbox/worktask", WT)

ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
setkey(asc, Date, Ticker)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

MAX_NAMES <- 20L; MIN_NAMES <- 5L
UB <- 0.20; LB <- 0.0
COMMISSION_BPS <- 15
LIQ_THRESHOLD <- 2e8   # Codex C9 disposition: use base mandate 2e8 KRW
TO_HARD_CAP <- 6.0   # CLAUDE.md Hurdle Rule v2.2
MDD_HARD_GATE <- -0.45  # CLAUDE.md Hurdle Rule v2.2

sig_dates <- sort(unique(asc$Date))

# ─── Helpers ────────────────────────────────────────────────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0; w[w < lb] <- lb
  if (sum(w) == 0) return(rep(target_sum/length(w), length(w)))
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

linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty <- function(alpha_t, lambda = 1.5, w_prev = NULL, phi = 3.0,
                                    lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# Buffer rule: keep_n holdings, only replace ranks > entry_n
apply_buffer_rule <- function(panel_t, w_prev = NULL, keep_n = 30L, entry_n = 20L) {
  # panel_t: data.table with Ticker + z_blend_composite, sorted desc by score
  setorder(panel_t, -z_blend_composite)
  candidates <- panel_t$Ticker[1:min(keep_n, nrow(panel_t))]

  if (is.null(w_prev) || length(w_prev) == 0L) {
    # First period: top 20
    final_tk <- panel_t$Ticker[1:min(entry_n, nrow(panel_t))]
  } else {
    held_tk <- names(w_prev)[w_prev > 1e-6]
    # Keep held if rank <= keep_n
    held_in_keep <- intersect(held_tk, candidates)
    n_held_keep <- length(held_in_keep)
    # Fill remainder with top-entry_n new names
    new_pool <- setdiff(panel_t$Ticker[1:min(entry_n, nrow(panel_t))], held_in_keep)
    need_new <- max(0, entry_n - n_held_keep)
    final_tk <- c(held_in_keep, head(new_pool, need_new))
    if (length(final_tk) > entry_n) final_tk <- final_tk[1:entry_n]
    if (length(final_tk) < MIN_NAMES) {
      # Fallback top entry_n
      final_tk <- panel_t$Ticker[1:min(entry_n, nrow(panel_t))]
    }
  }
  panel_t[Ticker %in% final_tk]
}

# ─── Walk-forward with buffer support ──────────────────────────
run_walk_forward_buffered <- function(weight_fn, weight_fn_name,
                                       use_buffer = FALSE, keep_n = 30L) {
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

    # Liquidity filter (t-30..t-1 PIT)
    liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                     .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
    liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
    panel_t <- panel_t[Ticker %in% liquid_tk]
    if (nrow(panel_t) < MIN_NAMES) {
      # Lower threshold fallback
      panel_t <- asc[Date == sig_label]
    }

    # Apply buffer or simple top20
    if (use_buffer) {
      picks <- apply_buffer_rule(panel_t, w_prev, keep_n = keep_n, entry_n = MAX_NAMES)
    } else {
      setorder(panel_t, -z_blend_composite)
      picks <- panel_t[1:min(MAX_NAMES, nrow(panel_t))]
    }
    if (nrow(picks) < 5L) next

    alpha_t_liq <- picks$z_blend_composite
    names(alpha_t_liq) <- picks$Ticker

    ub_use <- if (regime_i == "CRISIS") min(UB, 0.10) else UB
    w_risk <- tryCatch(
      weight_fn(alpha_t_liq, w_prev = w_prev, ub = ub_use),
      error = function(e) {
        N <- length(alpha_t_liq)
        normalize_long_only(rep(1/N, N), lb=LB, ub=ub_use)
      }
    )
    if (is.null(w_risk) || any(is.na(w_risk)) || abs(sum(w_risk)-1) > 0.01) {
      N <- length(alpha_t_liq)
      w_risk <- normalize_long_only(rep(1/N, N), lb=LB, ub=ub_use)
      names(w_risk) <- names(alpha_t_liq)
    }
    if (is.null(names(w_risk))) names(w_risk) <- names(alpha_t_liq)

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

# ─── New method variants with strong TO suppression ────────────
wf_iter31_phi3 <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  linear_tilt_to_penalty(alpha_t_liq, lambda = 1.5, w_prev = w_prev, phi = 3, lb = 0, ub = ub)
}
wf_iter31_phi5 <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  linear_tilt_to_penalty(alpha_t_liq, lambda = 1.5, w_prev = w_prev, phi = 5, lb = 0, ub = ub)
}
wf_iter31_phi10 <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  linear_tilt_to_penalty(alpha_t_liq, lambda = 1.5, w_prev = w_prev, phi = 10, lb = 0, ub = ub)
}
wf_ew <- function(alpha_t_liq, w_prev = NULL, ub = 0.20) {
  N <- length(alpha_t_liq)
  w <- rep(1/N, N); names(w) <- names(alpha_t_liq)
  normalize_long_only(w, lb = LB, ub = ub, target_sum = 1)
}

# Methods to try
methods <- list(
  list(name = "Iter31_phi3_buffer30", fn = wf_iter31_phi3, buffer = TRUE, keep_n = 30L),
  list(name = "Iter31_phi3_buffer40", fn = wf_iter31_phi3, buffer = TRUE, keep_n = 40L),
  list(name = "Iter31_phi5_buffer30", fn = wf_iter31_phi5, buffer = TRUE, keep_n = 30L),
  list(name = "Iter31_phi10_buffer40", fn = wf_iter31_phi10, buffer = TRUE, keep_n = 40L),
  list(name = "EW_buffer30", fn = wf_ew, buffer = TRUE, keep_n = 30L),
  list(name = "EW_buffer40", fn = wf_ew, buffer = TRUE, keep_n = 40L)
)

cat(sprintf("\n[Buffered method shopping] %d variants (LIQ_THRESHOLD=%.0e KRW)\n",
            length(methods), LIQ_THRESHOLD))

t0 <- Sys.time()
results_buf <- list()
for (m in methods) {
  cat(sprintf("  Running %s ... ", m$name))
  t1 <- Sys.time()
  out <- run_walk_forward_buffered(m$fn, m$name, use_buffer = m$buffer, keep_n = m$keep_n)
  elapsed <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  cat(sprintf("%d periods | %.1fs\n", nrow(out$monthly), elapsed))
  results_buf[[m$name]] <- out
}
total_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\nTotal time: %.1f sec\n", total_secs))

# ─── Aggregate ────────────────────────────────────────────────
agg_buf <- list()
for (m_name in names(results_buf)) {
  res <- results_buf[[m_name]]
  monthly <- res$monthly[!is.na(port_ret_net)]
  if (nrow(monthly) == 0L) next
  setorder(monthly, sig_date)
  rets <- monthly$port_ret_net
  n <- length(rets)
  ann_mu <- mean(rets) * 12; ann_sd <- sd(rets) * sqrt(12)
  sr <- if (ann_sd > 0) ann_mu/ann_sd else NA_real_
  cagr <- prod(1 + rets, na.rm=TRUE)^(12/n) - 1
  eq <- cumprod(1+rets); peak <- cummax(eq); mdd <- min(eq/peak - 1, na.rm=TRUE)
  neg <- rets[rets<0]
  ds_vol <- if (length(neg)>1) sd(neg)*sqrt(12) else NA_real_
  sortino <- if (!is.na(ds_vol) && ds_vol > 0) ann_mu/ds_vol else NA_real_
  calmar <- if (mdd < 0) ann_mu/abs(mdd) else NA_real_
  to_ann <- mean(monthly$turnover[-1], na.rm=TRUE) * 12

  rsr <- monthly[, .(sr = if(sd(port_ret_net)>0)
                       (mean(port_ret_net)*12)/(sd(port_ret_net)*sqrt(12)) else NA_real_),
                 by = regime]
  agg_buf[[m_name]] <- list(
    method = m_name,
    SR = sr, CAGR = cagr, MDD = mdd, Sortino = sortino, Calmar = calmar,
    BULL = rsr[regime=="BULL", sr][1],
    NORMAL = rsr[regime=="NORMAL", sr][1],
    CAUTION = rsr[regime=="CAUTION", sr][1],
    CRISIS = rsr[regime=="CRISIS", sr][1],
    TO = to_ann,
    TO_pass = (to_ann <= TO_HARD_CAP),
    MDD_pass = (mdd > MDD_HARD_GATE),
    HARD_PASS = (to_ann <= TO_HARD_CAP) & (mdd > MDD_HARD_GATE)
  )
}

agg_dt <- rbindlist(lapply(agg_buf, function(x) {
  do.call(data.table, lapply(x, function(v)
    if (is.null(v) || length(v) == 0) NA else v[[1]]))
}), fill = TRUE)

setorder(agg_dt, TO)
cat("\n[Buffered method results — sorted by TO]\n")
print(agg_dt[, .(method,
                 SR=round(SR,3), CAGR=round(CAGR*100,2), MDD=round(MDD*100,2),
                 Sortino=round(Sortino,2), Calmar=round(Calmar,2),
                 BULL=round(BULL,2), NORM=round(NORMAL,2),
                 CAU=round(CAUTION,2), CRI=round(CRISIS,2),
                 TO=round(TO,2),
                 TO_pass, MDD_pass, HARD_PASS)])

# Selection
passes <- agg_dt[TO <= TO_HARD_CAP & MDD > MDD_HARD_GATE]
if (nrow(passes) == 0L) {
  cat("\n[INFEASIBILITY] No method passes both TO ≤ 6.0 AND MDD > -45%\n")
  cat("Closest TO method:\n")
  print(agg_dt[order(TO)][1])
  cat("Closest MDD method:\n")
  print(agg_dt[order(-MDD)][1])
} else {
  setorder(passes, -SR)
  cat(sprintf("\n[Methods passing hard filter]: %d\n", nrow(passes)))
  print(passes)
  cat(sprintf("\n[Best method] %s\n", passes$method[1]))
}

# Save raw + agg
saveRDS(results_buf, file.path(stage, "opt_method_shopping_buffered.rds"))
fwrite(agg_dt, file.path(stage, "opt_method_comparison_buffered.csv"))

cat("[OPT-Step8] DONE\n")
