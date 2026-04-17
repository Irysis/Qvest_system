#==============================================================================
# IC-Weight Helper — DIRECT IC from sleeve factor scores (EVO_1340)
#
# Instead of mapping to Factor DB proxy names (which may mismatch),
# compute rolling IC directly from each sleeve's own factor z-scores
# against 1-month forward returns.
#
# PIT: IC[t] = corr(score[t], ret[t→t+1]). Usable after t+1 return realized.
#      → expanding window IC uses only months where both score AND return known.
#==============================================================================

cat("[ic_weight_helper_direct] Loading...\n")

# ---- IC history storage (built incrementally) ----
.IC_HISTORY_DEF <- list()   # defense sleeve: idiovol, beta
.IC_HISTORY_TP  <- list()   # TP gap sleeve: tp_gap, tp_mom

#' Record factor scores for a sleeve at sig_date (call during scoring loop)
#' @param sleeve_name "defense" or "tp"
#' @param sig_date Date
#' @param scores Named list: component_name -> named numeric (Ticker -> z_score)
record_sleeve_scores <- function(sleeve_name, sig_date, scores) {
  entry <- list(sig_date = as.Date(sig_date), scores = scores)
  if (sleeve_name == "defense") {
    .IC_HISTORY_DEF[[length(.IC_HISTORY_DEF) + 1L]] <<- entry
  } else if (sleeve_name == "tp") {
    .IC_HISTORY_TP[[length(.IC_HISTORY_TP) + 1L]] <<- entry
  }
}

#' Compute expanding-window IC from recorded sleeve scores + forward returns.
#' PIT: Only uses IC[t] where t+1 return is fully realized AND t < sig_date.
#' @param sleeve_name "defense" or "tp"
#' @param sig_date Current signal date
#' @param fwd_ret_dt data.table(Ticker, Date, Fwd_Ret_1M) — precomputed
#' @param min_months Minimum IC history for valid ICIR
#' @return Named numeric: component -> ICIR
compute_direct_ic <- function(sleeve_name, sig_date, fwd_ret_dt, min_months = 24L) {
  history <- if (sleeve_name == "defense") .IC_HISTORY_DEF else .IC_HISTORY_TP
  if (length(history) < min_months) return(NULL)

  sig_d <- as.Date(sig_date)

  # Collect all component names
  all_comps <- unique(unlist(lapply(history, function(h) names(h$scores))))

  # For each month in history, compute cross-sectional IC per component
  ic_table <- list()
  for (h in history) {
    h_date <- h$sig_date
    # PIT: only use IC[t] if t+1 return is fully known (h_date < sig_date)
    if (h_date >= sig_d) next

    for (comp in all_comps) {
      if (is.null(h$scores[[comp]])) next
      score_vec <- h$scores[[comp]]
      tickers <- names(score_vec)
      if (length(tickers) < 15) next

      # Get 1-month forward return for these tickers at h_date
      fwd <- fwd_ret_dt[Date == h_date & Ticker %in% tickers]
      if (nrow(fwd) < 15) next

      # Align
      common <- intersect(tickers, fwd$Ticker)
      if (length(common) < 15) next

      sc <- score_vec[common]
      rt <- fwd[match(common, Ticker), Fwd_Ret_1M]
      valid <- !is.na(sc) & !is.na(rt)
      if (sum(valid) < 15) next

      ic_val <- cor(sc[valid], rt[valid], method = "spearman")
      ic_table[[length(ic_table) + 1L]] <- data.table(
        Date = h_date, Component = comp, IC = ic_val
      )
    }
  }

  if (length(ic_table) == 0) return(NULL)
  ic_dt <- rbindlist(ic_table)

  # Compute ICIR per component (expanding window)
  result <- ic_dt[, {
    n <- .N
    if (n < min_months) {
      list(Mean_IC = NA_real_, ICIR = NA_real_, N = n)
    } else {
      m <- mean(IC, na.rm = TRUE)
      s <- sd(IC, na.rm = TRUE)
      list(Mean_IC = m, ICIR = if (s > 1e-8) m / s else NA_real_, N = n)
    }
  }, by = Component]

  result[!is.na(ICIR)]
}

#' Convert ICIR table to weights (ICIR-proportional, exclude negative)
icir_to_weights <- function(icir_dt, fallback_weights) {
  if (is.null(icir_dt) || nrow(icir_dt) == 0) return(fallback_weights)

  w_raw <- setNames(rep(0, length(fallback_weights)), names(fallback_weights))
  for (i in seq_len(nrow(icir_dt))) {
    comp <- icir_dt$Component[i]
    if (comp %in% names(w_raw) && icir_dt$ICIR[i] > 0) {
      w_raw[comp] <- icir_dt$ICIR[i]
    }
  }

  if (sum(w_raw) < 1e-8) return(fallback_weights)
  w_raw / sum(w_raw)
}

#' Get defense sleeve IC-weights (direct IC, no Factor DB proxy)
get_defense_ic_weights <- function(sig_date, regime_label, fwd_ret_dt) {
  fb <- switch(regime_label,
    "NEUTRAL"         = c(idiovol = 0.5, beta = 0.5),
    "RISK_ON_CAUTION" = c(idiovol = 0.2, beta = 0.8),
                        c(idiovol = 0.4, beta = 0.6)
  )
  icir_dt <- compute_direct_ic("defense", sig_date, fwd_ret_dt, min_months = 24L)
  icir_to_weights(icir_dt, fb)
}

#' Get TP Gap sleeve IC-weights (direct IC, no Factor DB proxy)
get_tp_ic_weights <- function(sig_date, fwd_ret_dt) {
  fb <- c(tp_gap = 0.6, tp_mom = 0.4)
  icir_dt <- compute_direct_ic("tp", sig_date, fwd_ret_dt, min_months = 24L)
  icir_to_weights(icir_dt, fb)
}

cat("[ic_weight_helper_direct] Ready. Direct IC from sleeve factor scores.\n")
cat("  Functions: record_sleeve_scores(), get_defense_ic_weights(), get_tp_ic_weights()\n")
