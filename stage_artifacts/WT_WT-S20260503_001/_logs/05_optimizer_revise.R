#!/usr/bin/env Rscript
# WT-S20260503_001 — Optimizer Revision after Codex REVISE stance
# Round 1 -> Round 2 fixes:
#   C2 ACCEPT (CRITICAL): Apply PIT 30d liquidity filter (LIQ_THRESHOLD=2e8) inside optimizer scope
#   C3 ACCEPT (HIGH):     Carry-forward 2026-04 HighRisk to 2026-05 (PIT-respect, not Normal default)
#   C6 PARTIAL (MED):     Compute explicit cost projection per strategy
#
# Rebuttal/Partial concerns documented in optimizer_challenge_note.md:
#   C1 (HIGH) HANDOFF_SCHEMA — REBUTTAL (canonical path is plan §4 standard)
#   C4 (HIGH) METHOD_SELECTION — REBUTTAL (sizing_only WT, judge phase decides primary)
#   C5 (MED)  RF_A1_UNADDRESSED — REBUTTAL (sizing_only mandate forbids alpha modification)
#   C7 (MED)  CRISIS_FALLBACK — PARTIAL (LRO frozen IS endpoint cap=0.15, STR_1715 0.10 layer-2 retained)
#   C8 (HIGH) AX008_TRIANGULATION — PARTIAL (recommendation_only ABORTED — admission gate 자체 없음)
#
# Effect on weights: liquidity filter may change selected tickers in some sig_dates.
# Effect on 2026-05: HighRisk → cap=0.15 + LRO_cash=15%

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

WT_ID <- "WT-S20260503_001"
WT_MAILBOX <- file.path("qepm/mailbox/worktask", WT_ID)
STAGE_DIR  <- file.path("stage_artifacts", paste0("WT_", WT_ID))
WV_DIR     <- file.path(STAGE_DIR, "weights_variants")
LOG_DIR    <- file.path(STAGE_DIR, "_logs")

cat("=== WT-S20260503_001 Optimizer Round 2 (Codex REVISE fixes) ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Helpers
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ===== Load inputs =====
ALPHA_PARQ <- "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"
alpha_scores <- as.data.table(read_parquet(ALPHA_PARQ))
setkey(alpha_scores, Date, Ticker)

ps <- fread(file.path(STAGE_DIR, "lro_policy_state.csv"))
ps[, sig_date := as.Date(sig_date)]
ps[, YM := format(sig_date, "%Y-%m")]

M4_PARQ <- "qepm/stage_artifacts/WT_WT-D20260430_001/alpha_scores.parquet"
m4 <- as.data.table(read_parquet(M4_PARQ))
m4[, YM := format(Date, "%Y-%m")]
m4_sched <- m4[, .(YM, weight_str1715, weight_cash)]
setkey(m4_sched, YM)

# ===== C2 ACCEPT: PIT liquidity filter inside optimizer scope =====
cat("[1] Load RAWDATA for PIT 30d liquidity filter\n")
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                  col_select = c("Date", "Ticker", "Close", "Vol")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 15L
LAMBDA         <- 1.5
TOPHI          <- 3.0
UB_DEFAULT     <- 0.20

# ===== Algorithm helpers =====
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) return(rep(target_sum / length(w), length(w)))
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

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

# sig_dates from alpha_scores
sig_dates <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
cat(sprintf("  alpha_scores sig_dates: %d\n", length(sig_dates)))

# ===== C2: PIT liquidity filter aggregator (memoize 30d AvgTradingAmt per sig_date) =====
cat("\n[2] Compute PIT 30d liquidity per sig_date (PIT-strict t-30..t-1)\n")
liq_by_sigdate <- list()
liq_changes_log <- list()
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  liq_window_start <- d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm = TRUE)), by = Ticker]
  liquid_tickers <- liq_data[!is.na(AvgTradingAmt) & AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  liq_by_sigdate[[as.character(d)]] <- liquid_tickers
}
cat(sprintf("  Liquidity computed for %d sig_dates\n", length(liq_by_sigdate)))
cat(sprintf("  Sample: %s liquid count = %d, %s liquid count = %d\n",
            as.character(sig_dates[1]),
            length(liq_by_sigdate[[as.character(sig_dates[1])]]),
            as.character(sig_dates[length(sig_dates)]),
            length(liq_by_sigdate[[as.character(sig_dates[length(sig_dates)])]])))

# ===== C3 ACCEPT: 2026-05 LRI carry-forward from 2026-04 (HighRisk persistent) =====
cat("\n[3] LRI state mapping with carry-forward (C3 fix)\n")
ps_state_by_ym <- setNames(ps$state, ps$YM)
ps_lri_by_ym <- setNames(ps$LRI, ps$YM)

# t-1 carry-forward for missing YMs (PIT-respect, t-1 is observable)
# Sorted YMs in ps; for any sig_date YM not in ps, use the last-observed state from ps
ps_yms_sorted <- sort(ps$YM)
last_observed_state <- function(ym) {
  # Find largest ps YM <= ym
  candidates <- ps_yms_sorted[ps_yms_sorted <= ym]
  if (length(candidates) == 0) return("Normal")  # pre-burnin (2004-01)
  last_ym <- max(candidates)
  ps_state_by_ym[[last_ym]]
}

get_state_carryforward <- function(ym) {
  s <- ps_state_by_ym[ym]
  if (is.null(s) || length(s) == 0 || is.na(s) || !is.character(s) || s == "") {
    s_cf <- last_observed_state(ym)
    return(list(state = s_cf, source = "carry_forward"))
  }
  return(list(state = unname(s), source = "direct"))
}

# Build state map for all sig_dates with explicit logging of carry-forward
state_map <- data.table(
  Date = sig_dates,
  YM = format(sig_dates, "%Y-%m")
)
state_map[, c("state", "state_source") := {
  res <- lapply(YM, get_state_carryforward)
  list(sapply(res, `[[`, "state"), sapply(res, `[[`, "source"))
}]
cat(sprintf("  Direct: %d, carry_forward: %d\n",
            sum(state_map$state_source == "direct"),
            sum(state_map$state_source == "carry_forward")))
cat("  Carry-forward instances:\n")
print(state_map[state_source == "carry_forward"])

# ===== State -> action mapping =====
lri_state_cap_for_lro <- function(state) {
  if (is.na(state) || !is.character(state)) return(0.20)
  if (state %in% c("HighRisk", "Extreme")) return(0.15) else return(0.20)
}
lri_state_cash_for_lro <- function(state) {
  if (is.na(state) || !is.character(state)) return(0.0)
  switch(state,
    "Normal"  = 0.00, "Crowded" = 0.05,
    "HighRisk" = 0.15, "Extreme" = 0.25, 0.00)
}

# Build cap_seq + cash maps using carry-forward state
sig_yms <- format(sig_dates, "%Y-%m")
cap_020 <- setNames(rep(UB_DEFAULT, length(sig_dates)), sig_yms)
cap_lro <- sapply(seq_along(sig_dates), function(i) {
  lri_state_cap_for_lro(state_map$state[i])
})
names(cap_lro) <- sig_yms

cat(sprintf("  cap_lro: 0.15 in %d months (HighRisk/Extreme), 0.20 in %d months\n",
            sum(cap_lro == 0.15), sum(cap_lro == 0.20)))

# ===== C2: Reconstruct base weights with PIT liquidity filter =====
cat("\n[4] Reconstruct base weights with PIT 30d liquidity filter\n")

build_base_weights_liq <- function(cap_seq) {
  out_list <- vector("list", length(sig_dates))
  liq_changes <- list()
  w_prev_named <- NULL
  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    YM_i <- sig_yms[i]
    panel <- alpha_scores[Date == d & !is.na(score_eff)]
    if (nrow(panel) == 0L) next
    setorder(panel, -score_eff)
    N_eligible <- nrow(panel)
    N_target_initial <- min(MAX_NAMES, N_eligible)
    if (N_target_initial < MIN_NAMES && N_eligible >= MIN_NAMES) N_target_initial <- MIN_NAMES
    if (N_target_initial < 5L) next

    picks_initial <- panel[seq_len(N_target_initial)]
    tickers_initial <- picks_initial$Ticker

    # Apply PIT liquidity filter (run_all.R fallback: if too few liquid, use unfiltered top20)
    liquid_tk <- liq_by_sigdate[[as.character(d)]]
    if (is.null(liquid_tk)) liquid_tk <- character(0)
    tickers_liq <- intersect(tickers_initial, liquid_tk)
    if (length(tickers_liq) < 5L) {
      tickers_use <- tickers_initial  # fallback (matches run_all.R semantics)
      liq_changes[[as.character(d)]] <- list(
        action = "fallback_no_filter", n_liquid = length(tickers_liq), n_used = length(tickers_use))
    } else if (length(tickers_liq) < length(tickers_initial)) {
      # Replace illiquid with next-rank liquid candidates from full panel
      illiquid <- setdiff(tickers_initial, liquid_tk)
      candidates <- setdiff(panel$Ticker, c(tickers_liq, illiquid))
      candidates_liquid <- intersect(candidates, liquid_tk)
      n_replace <- min(length(illiquid), length(candidates_liquid))
      if (n_replace > 0) {
        replace_tk <- candidates_liquid[seq_len(n_replace)]
        tickers_use <- c(tickers_liq, replace_tk)
        liq_changes[[as.character(d)]] <- list(
          action = "replaced_with_liquid",
          n_replaced = n_replace,
          illiquid_dropped = setdiff(illiquid, character(0)),
          replaced_with = replace_tk
        )
      } else {
        tickers_use <- tickers_liq
        liq_changes[[as.character(d)]] <- list(
          action = "shrink_to_liquid_only",
          n_used = length(tickers_use)
        )
      }
    } else {
      tickers_use <- tickers_initial
    }

    # Build alpha_t for tickers_use (preserve panel rank order)
    alpha_t <- panel[Ticker %in% tickers_use, score_eff]
    names(alpha_t) <- panel[Ticker %in% tickers_use, Ticker]
    # Preserve order by rank (already setorder by -score_eff)
    alpha_t <- alpha_t[tickers_use[tickers_use %in% names(alpha_t)]]
    if (length(alpha_t) < 5L) next

    cap_t <- cap_seq[YM_i] %||% UB_DEFAULT
    w_t <- tryCatch(
      linear_tilt_to_penalty_qd(alpha_t, lambda = LAMBDA, w_prev = w_prev_named,
                                phi = TOPHI, lb = 0, ub = cap_t),
      error = function(e) linear_tilt_qd(alpha_t, lambda = LAMBDA, lb = 0, ub = cap_t)
    )
    names(w_t) <- names(alpha_t)
    w_t <- normalize_long_only(w_t, lb = 0, ub = cap_t, target_sum = 1)

    out_list[[i]] <- data.table(
      Date = d, YM = YM_i, Ticker = names(w_t), weight = as.numeric(w_t)
    )
    w_prev_named <- setNames(as.numeric(w_t), names(w_t))
  }
  list(weights = rbindlist(out_list, use.names = TRUE, fill = TRUE),
       liq_changes = liq_changes)
}

cat("  [a] base_cap020_liq (cap=0.20 universal + PIT liquidity)\n")
res_020 <- build_base_weights_liq(cap_020)
base_cap020 <- res_020$weights
liq_changes_020 <- res_020$liq_changes
cat(sprintf("      rows=%d, dates=%d, liq_changes_dates=%d\n",
            nrow(base_cap020), length(unique(base_cap020$Date)),
            length(liq_changes_020)))

cat("  [b] base_caplro_liq (cap state-conditional + PIT liquidity)\n")
res_lro <- build_base_weights_liq(cap_lro)
base_caplro <- res_lro$weights
liq_changes_lro <- res_lro$liq_changes
cat(sprintf("      rows=%d, dates=%d, liq_changes_dates=%d\n",
            nrow(base_caplro), length(unique(base_caplro$Date)),
            length(liq_changes_lro)))

# Save liquidity changes log
liq_log_obj <- list(
  liq_threshold_won_20d_avg_30d_window = LIQ_THRESHOLD,
  total_sig_dates = length(sig_dates),
  cap020_changes_count = length(liq_changes_020),
  caplro_changes_count = length(liq_changes_lro),
  changes_summary = list(
    fallback_count_020 = sum(sapply(liq_changes_020, function(x) x$action == "fallback_no_filter")),
    replaced_count_020 = sum(sapply(liq_changes_020, function(x) x$action == "replaced_with_liquid")),
    shrink_count_020 = sum(sapply(liq_changes_020, function(x) x$action == "shrink_to_liquid_only")),
    fallback_count_lro = sum(sapply(liq_changes_lro, function(x) x$action == "fallback_no_filter")),
    replaced_count_lro = sum(sapply(liq_changes_lro, function(x) x$action == "replaced_with_liquid")),
    shrink_count_lro = sum(sapply(liq_changes_lro, function(x) x$action == "shrink_to_liquid_only"))
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(liq_log_obj, file.path(STAGE_DIR, "liquidity_filter_audit.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ===== Build 7 strategies =====
cat("\n[5] Build 7-strategy weights via cash overlay (PIT-cleaned base)\n")

apply_cash_overlay <- function(base_dt, cash_by_ym) {
  out_list <- list()
  for (d in unique(base_dt$Date)) {
    sub <- base_dt[Date == d]
    ym_i <- sub$YM[1]
    cash_raw <- cash_by_ym[ym_i]
    cash_i <- if (is.null(cash_raw) || length(cash_raw) == 0 || is.na(cash_raw)) 0 else as.numeric(cash_raw)
    if (cash_i < 0) cash_i <- 0
    if (cash_i > 1) cash_i <- 1
    sub[, weight := weight * (1 - cash_i)]
    if (cash_i > 0) {
      sub <- rbind(sub, data.table(
        Date = d, YM = ym_i, Ticker = "__CASH__", weight = cash_i
      ))
    }
    out_list[[as.character(d)]] <- sub
  }
  rbindlist(out_list, use.names = TRUE)
}

m4_cash_by_ym <- setNames(m4_sched$weight_cash, m4_sched$YM)
lro_cash_by_ym <- sapply(seq_along(sig_dates), function(i) {
  lri_state_cash_for_lro(state_map$state[i])
})
names(lro_cash_by_ym) <- sig_yms
combined_cash_by_ym <- sapply(names(lro_cash_by_ym), function(ym) {
  m4_c <- m4_cash_by_ym[ym]
  lro_c <- lro_cash_by_ym[ym]
  m4_v <- if (is.null(m4_c) || length(m4_c) == 0 || is.na(m4_c)) 0 else as.numeric(m4_c)
  lro_v <- if (is.null(lro_c) || length(lro_c) == 0 || is.na(lro_c)) 0 else as.numeric(lro_c)
  max(m4_v, lro_v)
})
names(combined_cash_by_ym) <- names(lro_cash_by_ym)

S1          <- apply_cash_overlay(base_cap020,  setNames(rep(0, length(sig_dates)), sig_yms))
M4_strat    <- apply_cash_overlay(base_cap020,  m4_cash_by_ym)
LRO_mon     <- copy(S1)
LRO_cap     <- apply_cash_overlay(base_caplro,  setNames(rep(0, length(sig_dates)), sig_yms))
LRO_cash    <- apply_cash_overlay(base_cap020,  lro_cash_by_ym)
M4_LRO_cap  <- apply_cash_overlay(base_caplro,  m4_cash_by_ym)
M4_LRO_cash <- apply_cash_overlay(base_caplro,  combined_cash_by_ym)

# ===== Audit =====
cat("\n[6] Hard constraint audit per strategy\n")
audit_strategy <- function(name, dt) {
  by_date <- dt[, .(
    sum_w = sum(weight),
    n_names = sum(weight > 1e-9 & Ticker != "__CASH__"),
    n_total = .N,
    max_w = max(weight[Ticker != "__CASH__"]),
    min_w = min(weight),
    has_cash = "__CASH__" %in% Ticker,
    cash_w = ifelse("__CASH__" %in% Ticker, weight[Ticker == "__CASH__"], 0)
  ), by = Date]
  cat(sprintf("  %s: dates=%d | sum=[%.4f,%.4f] | n_names=[%d,%d] | max_w=[%.4f,%.4f]\n",
              name, nrow(by_date),
              min(by_date$sum_w), max(by_date$sum_w),
              min(by_date$n_names), max(by_date$n_names),
              min(by_date$max_w), max(by_date$max_w)))
  return(by_date)
}
a_S1  <- audit_strategy("S1         ", S1)
a_M4  <- audit_strategy("M4         ", M4_strat)
a_mon <- audit_strategy("LRO_mon    ", LRO_mon)
a_cap <- audit_strategy("LRO_cap    ", LRO_cap)
a_csh <- audit_strategy("LRO_cash   ", LRO_cash)
a_mcp <- audit_strategy("M4+LRO_cap ", M4_LRO_cap)
a_mcs <- audit_strategy("M4+LRO_cash", M4_LRO_cash)

# ===== Write variants + canonical =====
cat("\n[7] Write weights variants + canonical\n")
write_variant <- function(name, dt) {
  out <- dt[, .(Date, Ticker, weight)]
  setorder(out, Date, -weight)
  fp <- file.path(WV_DIR, paste0(name, ".csv"))
  fwrite(out, fp)
  cat(sprintf("  %s -> rows=%d\n", name, nrow(out)))
  invisible(out)
}
write_variant("S1",          S1)
write_variant("M4",          M4_strat)
write_variant("LRO_mon",     LRO_mon)
write_variant("LRO_cap",     LRO_cap)
write_variant("LRO_cash",    LRO_cash)
write_variant("M4+LRO_cap",  M4_LRO_cap)
write_variant("M4+LRO_cash", M4_LRO_cash)

canonical <- M4_LRO_cap[, .(Date, Ticker, weight)]
setorder(canonical, Date, -weight)
fwrite(canonical, file.path(STAGE_DIR, "weights.csv"))
cat(sprintf("  canonical (M4+LRO_cap) -> rows=%d\n", nrow(canonical)))

# ===== Schedule density =====
cat("\n[8] Schedule density audit\n")
alpha_sig_dates_count <- length(unique(alpha_scores[!is.na(score_eff), Date]))
sched_density <- list()
for (n in c("S1", "M4", "LRO_mon", "LRO_cap", "LRO_cash", "M4+LRO_cap", "M4+LRO_cash")) {
  fp <- file.path(WV_DIR, paste0(n, ".csv"))
  d <- fread(fp)
  ud <- length(unique(d$Date))
  ratio <- ud / alpha_sig_dates_count
  sched_density[[n]] <- list(unique_dates = ud, ratio = round(ratio, 4))
  cat(sprintf("  %s: unique_dates=%d ratio=%.4f %s\n",
              n, ud, ratio, ifelse(ratio >= 0.95, "PASS", "WARN")))
}

# ===== C6: Cost projection per strategy =====
cat("\n[9] C6 PARTIAL — Cost projection per strategy (15bps × 2 × turnover annual)\n")

calc_turnover_cost <- function(dt) {
  setorder(dt, Date)
  ds <- sort(unique(dt$Date))
  to_vec <- numeric(length(ds)-1)
  for (i in 2:length(ds)) {
    w_now <- dt[Date == ds[i], setNames(weight, Ticker)]
    w_prev <- dt[Date == ds[i-1], setNames(weight, Ticker)]
    all_n <- union(names(w_now), names(w_prev))
    a <- setNames(rep(0, length(all_n)), all_n); b <- a
    a[names(w_now)] <- w_now; b[names(w_prev)] <- w_prev
    to_vec[i-1] <- sum(abs(a-b))/2
  }
  monthly_to <- mean(to_vec)
  annual_to <- monthly_to * 12
  cost_bps <- COMMISSION_BPS * 2 * annual_to  # round-trip × annual turnover
  list(monthly_turnover = round(monthly_to, 4),
       annual_turnover = round(annual_to, 4),
       cost_bps_annual = round(cost_bps, 1))
}

cost_proj <- list()
for (n in c("S1", "M4", "LRO_mon", "LRO_cap", "LRO_cash", "M4+LRO_cap", "M4+LRO_cash")) {
  dt <- switch(n,
    "S1" = S1, "M4" = M4_strat, "LRO_mon" = LRO_mon, "LRO_cap" = LRO_cap,
    "LRO_cash" = LRO_cash, "M4+LRO_cap" = M4_LRO_cap, "M4+LRO_cash" = M4_LRO_cash)
  c_proj <- calc_turnover_cost(dt)
  cost_proj[[n]] <- c_proj
  cat(sprintf("  %-12s monthly=%.4f annual=%.2f cost_bps=%.1f\n",
              n, c_proj$monthly_turnover, c_proj$annual_turnover, c_proj$cost_bps_annual))
}

# ===== MRC for canonical =====
cat("\n[10] Compute monthly portfolio MRC for canonical (using risk_package Σ)\n")
cov_long <- as.data.table(read_parquet(file.path(STAGE_DIR, "covariance.parquet")))
cov_tickers <- sort(unique(c(cov_long$Ticker_i, cov_long$Ticker_j)))
n_cov <- length(cov_tickers)
Sigma <- matrix(0, n_cov, n_cov, dimnames = list(cov_tickers, cov_tickers))
for (k in seq_len(nrow(cov_long))) {
  Sigma[cov_long$Ticker_i[k], cov_long$Ticker_j[k]] <- cov_long$Sigma_ij[k]
}
mrc_list <- list()
for (d in unique(canonical$Date)) {
  sub <- canonical[Date == d & Ticker != "__CASH__"]
  tk <- sub$Ticker; w <- sub$weight
  in_cov <- tk %in% cov_tickers
  if (sum(in_cov) < 5) next
  tk_use <- tk[in_cov]; w_use <- w[in_cov]
  Sigma_sub <- Sigma[tk_use, tk_use]
  Sw <- as.numeric(Sigma_sub %*% w_use)
  rc_i <- w_use * Sw
  port_var <- sum(rc_i)
  port_vol <- sqrt(max(port_var, 0))
  mrc_list[[as.character(d)]] <- data.table(
    Date = as.Date(d), Ticker = tk_use, weight = w_use,
    sigma_w_i = Sw, rc_i = rc_i,
    pct_rc = ifelse(port_var > 0, rc_i / port_var, 0),
    port_vol = port_vol)
}
mrc_dt <- rbindlist(mrc_list, use.names = TRUE)
fwrite(mrc_dt, file.path(STAGE_DIR, "lro_portfolio_mrc.csv"))
cat(sprintf("  rows=%d, dates=%d\n", nrow(mrc_dt), length(unique(mrc_dt$Date))))

# ===== cash_definition_audit (unchanged 5-field) =====
cat("\n[11] cash_definition_audit.json (5-field)\n")
m4_has_col <- "weight_cash" %in% names(m4)
cash_audit <- list(
  task_id = WT_ID,
  rule = "max(M4_cash, LRO_cash) single rule (additive forbidden)",
  source = ifelse(m4_has_col, "column", "holdings_infer"),
  m4_cash_value = list(
    min = min(m4_sched$weight_cash), max = max(m4_sched$weight_cash),
    mean = round(mean(m4_sched$weight_cash), 6),
    n_nonzero_months = sum(m4_sched$weight_cash > 0)),
  lro_cash_value = list(
    min = min(unname(lro_cash_by_ym)), max = max(unname(lro_cash_by_ym)),
    distinct = sort(unique(round(unname(lro_cash_by_ym), 4))),
    n_nonzero_months = sum(unname(lro_cash_by_ym) > 0)),
  applied_cash_value = list(
    min = min(unname(combined_cash_by_ym)), max = max(unname(combined_cash_by_ym)),
    mean = round(mean(unname(combined_cash_by_ym)), 6),
    n_nonzero_months = sum(unname(combined_cash_by_ym) > 0)),
  cash_inferred_flag = !m4_has_col,
  per_strategy_cash_avg = list(
    S1 = 0,
    M4 = round(mean(m4_sched$weight_cash), 6),
    LRO_mon = 0,
    LRO_cap = 0,
    LRO_cash = round(mean(unname(lro_cash_by_ym)), 6),
    `M4+LRO_cap` = round(mean(m4_sched$weight_cash), 6),
    `M4+LRO_cash` = round(mean(unname(combined_cash_by_ym)), 6)),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(cash_audit, file.path(STAGE_DIR, "cash_definition_audit.json"),
           auto_unbox = TRUE, pretty = TRUE)

# Save schedule density
schedule_density_obj <- list(
  reference_alpha_sig_dates = alpha_sig_dates_count,
  per_strategy = sched_density)
write_json(schedule_density_obj,
           file.path(STAGE_DIR, "schedule_density_per_strategy.json"),
           auto_unbox = TRUE, pretty = TRUE)

# Save cost projection
cost_proj_obj <- list(
  commission_bps_one_way = COMMISSION_BPS,
  formula = "annual_cost_bps = 15 * 2 * annual_turnover",
  per_strategy = cost_proj,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write_json(cost_proj_obj, file.path(STAGE_DIR, "cost_projection.json"),
           auto_unbox = TRUE, pretty = TRUE)

# State map for transparency
fwrite(state_map, file.path(STAGE_DIR, "state_map_with_carryforward.csv"))

# ===== Save workspace =====
saveRDS(list(
  S1 = S1, M4 = M4_strat, LRO_mon = LRO_mon, LRO_cap = LRO_cap,
  LRO_cash = LRO_cash, M4_LRO_cap = M4_LRO_cap, M4_LRO_cash = M4_LRO_cash,
  cap_lro = cap_lro, lro_cash_by_ym = lro_cash_by_ym,
  m4_cash_by_ym = m4_cash_by_ym, combined_cash_by_ym = combined_cash_by_ym,
  state_map = state_map,
  liq_changes_020 = liq_changes_020,
  liq_changes_lro = liq_changes_lro,
  cost_proj = cost_proj,
  audit = list(S1=a_S1, M4=a_M4, LRO_mon=a_mon, LRO_cap=a_cap,
               LRO_cash=a_csh, M4_LRO_cap=a_mcp, M4_LRO_cash=a_mcs)
), file.path(LOG_DIR, "optimizer_workspace_round2.rds"))

cat("\n=== Round 2 DONE ===\n")
cat("Finished:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
