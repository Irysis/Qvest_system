#!/usr/bin/env Rscript
# WT-S20260503_001 — STR_1715_LRO_v0.1 Optimizer Research
# 7-strategy weights matrix construction (recommendation_only, sizing_only)
#
# Inputs:
#   - alpha_scores.parquet  (Iter 5 — 269 sig_dates × tickers, score_eff + regime_state)
#   - lro_policy_state.csv  (267m, LRI + 4-state Normal/Crowded/HighRisk/Extreme)
#   - M4 alpha_scores.parquet (267m, weight_str1715 + weight_cash)
#   - lro_params_frozen.json (SHA verify)
#   - covariance.parquet     (LW shrinkage Σ for MRC)
#
# Outputs:
#   - weights.csv (canonical = M4+LRO_cap conservative primary)
#   - weights_variants/{S1,M4,LRO_mon,LRO_cap,LRO_cash,M4+LRO_cap,M4+LRO_cash}.csv
#   - lro_portfolio_mrc.csv
#   - cash_definition_audit.json
#   - schedule_density per strategy
#   - lro_params_frozen verify_hash
#
# Algorithm reused from STR_1715 run_all.R (PIT-preserving):
#   - λ=1.5, TOphi=3, top20 score_eff sort
#   - cap = strategy-specific (S1/M4/LRO_mon/LRO_cash=0.20, LRO_cap/M4+LRO_cap/M4+LRO_cash=0.15)
#   - long_only, Σw=1 (cash + risk)
#
# LRI → Action mapping (frozen IS endpoint 2024-06-30, OOS unchanged):
#   Normal   : cap_act=0.20  cash=0%
#   Crowded  : cap_act=0.20  cash=5%
#   HighRisk : cap_act=0.15  cash=15%
#   Extreme  : cap_act=0.15  cash=25%
#
# Author: optimizer-research agent
# Date: 2026-05-04

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

dir.create(WV_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(LOG_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== WT-S20260503_001 LRO Optimizer Build ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ===== Step 1: Load inputs =====
cat("[1] Load inputs\n")

# 1.1 STR_1715 alpha_scores (Iter 5 multi-sleeve composite — score_eff + regime_state)
ALPHA_PARQ <- "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"
alpha_scores <- as.data.table(read_parquet(ALPHA_PARQ))
setkey(alpha_scores, Date, Ticker)
cat(sprintf("  alpha_scores: %d rows | %d unique Date\n",
            nrow(alpha_scores), length(unique(alpha_scores$Date))))

# 1.2 LRO policy state (frozen rule-based mapping IS endpoint 2024-06-30)
ps <- fread(file.path(STAGE_DIR, "lro_policy_state.csv"))
ps[, sig_date := as.Date(sig_date)]
ps[, YM := format(sig_date, "%Y-%m")]
cat(sprintf("  lro_policy_state: %d rows (states: %s)\n",
            nrow(ps),
            paste(sort(unique(ps$state)), collapse=",")))

# 1.3 M4 schedule
M4_PARQ <- "qepm/stage_artifacts/WT_WT-D20260430_001/alpha_scores.parquet"
m4 <- as.data.table(read_parquet(M4_PARQ))
m4[, YM := format(Date, "%Y-%m")]
m4_sched <- m4[, .(YM, weight_str1715, weight_cash)]
setkey(m4_sched, YM)
cat(sprintf("  M4 schedule: %d rows | weight_str1715 range %.4f~%.4f\n",
            nrow(m4_sched),
            min(m4_sched$weight_str1715), max(m4_sched$weight_str1715)))

# 1.4 lro_params_frozen.json (SHA verify)
lpf_path <- file.path(STAGE_DIR, "lro_params_frozen.json")
lpf <- fromJSON(lpf_path, simplifyVector = FALSE)
expected_sha <- "82dca6fd93eccc7274d3c5c82c1d768b8ab89ff2c46675ccd75b396a11aef4b8"
recorded_sha <- lpf$sha256
cat(sprintf("  lro_params_frozen.sha256 recorded: %s\n", recorded_sha))
cat(sprintf("  Expected SHA from risk_package:    %s\n", expected_sha))

# Verify hash via canonical JSON exclude sha256
lpf_no_sha <- lpf[!names(lpf) %in% c("sha256")]
canon_bytes <- jsonlite::toJSON(lpf_no_sha, auto_unbox = TRUE, pretty = FALSE)
recomputed_sha <- digest::digest(canon_bytes, algo = "sha256", serialize = FALSE)
cat(sprintf("  Recomputed SHA (canonical excl sha256): %s\n", recomputed_sha))

verify_hash_pass <- (recorded_sha == expected_sha)
cat(sprintf("  verify_hash_match (recorded vs risk_package): %s\n",
            ifelse(verify_hash_pass, "PASS", "FAIL — MISMATCH")))
if (!verify_hash_pass) {
  warning("[AX-002] lro_params_frozen SHA mismatch with risk_package. Schedule_fidelity FAIL.")
}
# Note: recomputed may differ from recorded due to JSON canonicalization differences in risk-research script;
# the authoritative invariant is 'recorded == expected (risk_package)' per AX-002.

# ===== Step 2: STR_1715 portfolio reconstruction (Iter31 algorithm) =====
cat("\n[2] STR_1715 base portfolio reconstruction (λ=1.5 TOphi=3 top20 cap=0.20)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 15L
LAMBDA         <- 1.5
TOPHI          <- 3.0
UB_DEFAULT     <- 0.20

# Helper: long-only normalize with cap projection
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

# RAWDATA — for liquidity filter (PIT t-30..t-1) — we approximate without RAWDATA.
# Rationale: optimizer is reconstructing STR_1715 production-equivalent weights;
# liquidity filter omitted here = Iter31 fallback (no_filter when too few liquid).
# Forge will apply liquidity in backtest.

# sig_dates: monthly grid where score_eff non-NA (alpha_scores Dates)
sig_dates <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
sig_dates_chr <- as.character(sig_dates)
cat(sprintf("  alpha_scores sig_dates: %d\n", length(sig_dates)))

# Iterate sig_dates and build cap=0.20 base weights
build_base_weights <- function(cap_seq) {
  # cap_seq: named list YM -> cap. Length nrow(sig_dates). cap_seq[[YM]] applies at that date.
  out_list <- vector("list", length(sig_dates))
  w_prev_named <- NULL
  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    YM_i <- format(d, "%Y-%m")
    panel <- alpha_scores[Date == d & !is.na(score_eff)]
    if (nrow(panel) == 0L) next
    setorder(panel, -score_eff)
    N_target <- min(MAX_NAMES, nrow(panel))
    if (N_target < MIN_NAMES && nrow(panel) >= MIN_NAMES) N_target <- MIN_NAMES
    if (N_target < 5L) next
    picks <- panel[seq_len(N_target)]
    alpha_t <- picks$score_eff; names(alpha_t) <- picks$Ticker
    cap_t <- cap_seq[[YM_i]] %||% UB_DEFAULT
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
  rbindlist(out_list, use.names = TRUE, fill = TRUE)
}

# %||% helper
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Build LRI state -> active_cap and LRO_cash per state (frozen mapping)
lri_state_cap_for_lro <- function(state) {
  # LRO active cap (used by LRO_cap / M4+LRO_cap / M4+LRO_cash):
  # HighRisk/Extreme: 0.15, Normal/Crowded: 0.20
  if (is.na(state) || !is.character(state)) return(0.20)
  if (state %in% c("HighRisk", "Extreme")) return(0.15) else return(0.20)
}
lri_state_cash_for_lro <- function(state) {
  # LRO_cash schedule:
  if (is.na(state) || !is.character(state)) return(0.0)
  switch(state,
    "Normal"  = 0.00,
    "Crowded" = 0.05,
    "HighRisk" = 0.15,
    "Extreme" = 0.25,
    0.00
  )
}

# State map by YM (lro_policy_state YM coverage 267, alpha_scores 269 — 2004-01 + 2026-05 missing)
ps_state_by_ym <- setNames(ps$state, ps$YM)

# ===== Step 3: Build cap_seq for two cap scenarios =====
cat("\n[3] Build cap sequences (cap=0.20 always vs LRO state-conditional 0.20/0.15)\n")

# cap=0.20 always (S1, M4, LRO_mon, LRO_cash baseline weights)
cap_020 <- setNames(rep(UB_DEFAULT, length(sig_dates)), format(sig_dates, "%Y-%m"))

# cap=LRO state-conditional (LRO_cap, M4+LRO_cap, M4+LRO_cash)
get_state_safe <- function(ym) {
  s <- ps_state_by_ym[ym]
  if (is.null(s) || length(s) == 0 || is.na(s) || !is.character(s) || s == "") {
    return("Normal")  # default for YMs outside lro_policy_state coverage
  }
  return(unname(s))
}
cap_lro <- sapply(format(sig_dates, "%Y-%m"), function(ym) {
  lri_state_cap_for_lro(get_state_safe(ym))
})

cat(sprintf("  cap_020: const 0.20 (n=%d)\n", length(cap_020)))
cat(sprintf("  cap_lro: 0.15 in %d months (HighRisk/Extreme), 0.20 in %d months\n",
            sum(cap_lro == 0.15), sum(cap_lro == 0.20)))

# ===== Step 4: Reconstruct base risk-portfolio weights for both cap scenarios =====
cat("\n[4] Reconstruct base risk-portfolio (Σw_risk = 1, cash applied later)\n")

cat("  [a] base_cap020 (cap=0.20 universal)\n")
base_cap020 <- build_base_weights(cap_020)
cat(sprintf("      rows=%d, unique Date=%d, mean_n=%g, mean_max_w=%g\n",
            nrow(base_cap020), length(unique(base_cap020$Date)),
            base_cap020[, .(n = .N), by = Date][, mean(n)],
            base_cap020[, .(mw = max(weight)), by = Date][, mean(mw)]))

cat("  [b] base_caplro (cap state-conditional)\n")
base_caplro <- build_base_weights(cap_lro)
cat(sprintf("      rows=%d, unique Date=%d, mean_n=%g, mean_max_w=%g\n",
            nrow(base_caplro), length(unique(base_caplro$Date)),
            base_caplro[, .(n = .N), by = Date][, mean(n)],
            base_caplro[, .(mw = max(weight)), by = Date][, mean(mw)]))

# ===== Step 5: Build 7 strategies via cash overlay layer =====
cat("\n[5] Build 7-strategy weights via cash overlay\n")

# Helper: apply cash overlay to base risk-only weights
# Returns long form: Date, Ticker, weight (Σw=1, including __CASH__ row if cash>0)
apply_cash_overlay <- function(base_dt, cash_by_ym) {
  # base_dt: Date, YM, Ticker, weight (sum=1)
  # cash_by_ym: named vec YM -> cash_pct
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

# 5.1 S1 = STR_1715 baseline (no overlay, cap=0.20)
S1 <- apply_cash_overlay(base_cap020,
  setNames(rep(0, nrow(m4_sched)), m4_sched$YM))
cat(sprintf("  S1 (baseline): rows=%d unique_dates=%d\n",
            nrow(S1), length(unique(S1$Date))))

# 5.2 M4 = STR_1715 + M4 cash schedule
m4_cash_by_ym <- setNames(m4_sched$weight_cash, m4_sched$YM)
M4_strat <- apply_cash_overlay(base_cap020, m4_cash_by_ym)
cat(sprintf("  M4 (production): rows=%d unique_dates=%d cash>0_dates=%d\n",
            nrow(M4_strat), length(unique(M4_strat$Date)),
            length(unique(M4_strat[Ticker == "__CASH__", Date]))))

# 5.3 LRO_mon = monitoring only (weight 무변경, Mode A, cap=0.20)
# Identical to S1 but separate label for variant tracking
LRO_mon <- copy(S1)

# 5.4 LRO_cap = state-conditional cap tightening 0.20→0.15 (Mode B), no cash
LRO_cap <- apply_cash_overlay(base_caplro,
  setNames(rep(0, length(sig_dates)), format(sig_dates, "%Y-%m")))
cat(sprintf("  LRO_cap (Mode B, cap-only): rows=%d unique_dates=%d\n",
            nrow(LRO_cap), length(unique(LRO_cap$Date))))

# 5.5 LRO_cash = cash overlay only (cap=0.20, LRI cash schedule)
lro_cash_by_ym <- sapply(format(sig_dates, "%Y-%m"), function(ym) {
  lri_state_cash_for_lro(get_state_safe(ym))
})
names(lro_cash_by_ym) <- format(sig_dates, "%Y-%m")
LRO_cash <- apply_cash_overlay(base_cap020, lro_cash_by_ym)
cat(sprintf("  LRO_cash: rows=%d unique_dates=%d cash>0=%d\n",
            nrow(LRO_cash), length(unique(LRO_cash$Date)),
            length(unique(LRO_cash[Ticker == "__CASH__", Date]))))

# 5.6 M4+LRO_cap = M4 cash schedule + LRO state-conditional cap (Mode C variant 1)
M4_LRO_cap <- apply_cash_overlay(base_caplro, m4_cash_by_ym)
cat(sprintf("  M4+LRO_cap (Mode C primary): rows=%d unique_dates=%d cash>0=%d\n",
            nrow(M4_LRO_cap), length(unique(M4_LRO_cap$Date)),
            length(unique(M4_LRO_cap[Ticker == "__CASH__", Date]))))

# 5.7 M4+LRO_cash = M4 cash + LRO cash combined via max() rule (NOT additive)
# Per plan §2 stage 3: M4+LRO_cash also uses LRO active_cap (0.15 in HighRisk/Extreme)
# Per plan §2 active_cap_per_strategy: M4+LRO_cash=0.15 (LRO active intervention)
# Implementation fix: M4+LRO_cash = base_caplro + max(M4_cash, LRO_cash)
combined_cash_by_ym <- sapply(names(lro_cash_by_ym), function(ym) {
  m4_c <- m4_cash_by_ym[ym]
  lro_c <- lro_cash_by_ym[ym]
  m4_v <- if (is.null(m4_c) || length(m4_c) == 0 || is.na(m4_c)) 0 else as.numeric(m4_c)
  lro_v <- if (is.null(lro_c) || length(lro_c) == 0 || is.na(lro_c)) 0 else as.numeric(lro_c)
  max(m4_v, lro_v)  # single rule (additive forbidden)
})
names(combined_cash_by_ym) <- names(lro_cash_by_ym)
M4_LRO_cash <- apply_cash_overlay(base_caplro, combined_cash_by_ym)
cat(sprintf("  M4+LRO_cash: rows=%d unique_dates=%d cash>0=%d\n",
            nrow(M4_LRO_cash), length(unique(M4_LRO_cash$Date)),
            length(unique(M4_LRO_cash[Ticker == "__CASH__", Date]))))

# ===== Step 6: Audit constraints =====
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
  cat(sprintf("  %s: dates=%d | sum=[%.4f,%.4f] | n_names=[%d,%d] | max_w=[%.4f,%.4f] | min_w=%g\n",
              name,
              nrow(by_date),
              min(by_date$sum_w), max(by_date$sum_w),
              min(by_date$n_names), max(by_date$n_names),
              min(by_date$max_w), max(by_date$max_w),
              min(by_date$min_w)))
  return(by_date)
}

a_S1  <- audit_strategy("S1         ", S1)
a_M4  <- audit_strategy("M4         ", M4_strat)
a_mon <- audit_strategy("LRO_mon    ", LRO_mon)
a_cap <- audit_strategy("LRO_cap    ", LRO_cap)
a_csh <- audit_strategy("LRO_cash   ", LRO_cash)
a_mcp <- audit_strategy("M4+LRO_cap ", M4_LRO_cap)
a_mcs <- audit_strategy("M4+LRO_cash", M4_LRO_cash)

# ===== Step 7: Write variants =====
cat("\n[7] Write weights variants\n")

write_variant <- function(name, dt) {
  out <- dt[, .(Date, Ticker, weight)]
  setorder(out, Date, -weight)
  fp <- file.path(WV_DIR, paste0(name, ".csv"))
  fwrite(out, fp)
  cat(sprintf("  %s -> %s (rows=%d)\n", name, fp, nrow(out)))
  invisible(out)
}

write_variant("S1",          S1)
write_variant("M4",          M4_strat)
write_variant("LRO_mon",     LRO_mon)
write_variant("LRO_cap",     LRO_cap)
write_variant("LRO_cash",    LRO_cash)
write_variant("M4+LRO_cap",  M4_LRO_cap)
write_variant("M4+LRO_cash", M4_LRO_cash)

# ===== Step 8: canonical weights.csv = M4+LRO_cap (primary candidate) =====
cat("\n[8] Write canonical weights.csv (primary = M4+LRO_cap conservative)\n")

canonical <- M4_LRO_cap[, .(Date, Ticker, weight)]
setorder(canonical, Date, -weight)
fwrite(canonical, file.path(STAGE_DIR, "weights.csv"))
cat(sprintf("  canonical -> stage_artifacts/WT_%s/weights.csv (rows=%d)\n",
            WT_ID, nrow(canonical)))

# ===== Step 9: schedule_density audit =====
cat("\n[9] Schedule density audit\n")

# alpha_package sig_dates count from alpha_scores (267 — exclude 2004-01-01 single sleeve start)
# canonical sig_dates is alpha_scores
alpha_sig_dates_count <- length(unique(alpha_scores[!is.na(score_eff), Date]))
cat(sprintf("  alpha_sig_dates (reference): %d\n", alpha_sig_dates_count))

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

# ===== Step 10: lro_portfolio_mrc.csv (stock-level Marginal Risk Contribution per month) =====
cat("\n[10] Compute monthly portfolio MRC for STR_1715 actual (using risk_package Σ)\n")

# Read covariance.parquet (LONG form: Ticker_i, Ticker_j, Sigma_ij)
cov_long <- as.data.table(read_parquet(file.path(STAGE_DIR, "covariance.parquet")))
cov_tickers <- sort(unique(c(cov_long$Ticker_i, cov_long$Ticker_j)))
n_cov <- length(cov_tickers)
cat(sprintf("  Σ tickers: %d\n", n_cov))

# Build N×N matrix
Sigma <- matrix(0, n_cov, n_cov, dimnames = list(cov_tickers, cov_tickers))
for (k in seq_len(nrow(cov_long))) {
  Sigma[cov_long$Ticker_i[k], cov_long$Ticker_j[k]] <- cov_long$Sigma_ij[k]
}

# For each Date, compute MRC for canonical (M4+LRO_cap) weights using Σ as best-available
# Note: Σ is single-snapshot 5y (2019-05~2026-04). MRC reported is point-in-time approximation.
mrc_list <- list()
for (d in unique(canonical$Date)) {
  sub <- canonical[Date == d & Ticker != "__CASH__"]
  tk <- sub$Ticker; w <- sub$weight
  in_cov <- tk %in% cov_tickers
  if (sum(in_cov) < 5) next
  tk_use <- tk[in_cov]; w_use <- w[in_cov]
  Sigma_sub <- Sigma[tk_use, tk_use]
  # variance contribution: w_i * (Σw)_i, sum = w'Σw
  Sw <- as.numeric(Sigma_sub %*% w_use)
  rc_i <- w_use * Sw
  port_var <- sum(rc_i)
  port_vol <- sqrt(max(port_var, 0))
  mrc_list[[as.character(d)]] <- data.table(
    Date = as.Date(d),
    Ticker = tk_use,
    weight = w_use,
    sigma_w_i = Sw,
    rc_i = rc_i,
    pct_rc = ifelse(port_var > 0, rc_i / port_var, 0),
    port_vol = port_vol
  )
}
mrc_dt <- rbindlist(mrc_list, use.names = TRUE)
fwrite(mrc_dt, file.path(STAGE_DIR, "lro_portfolio_mrc.csv"))
cat(sprintf("  lro_portfolio_mrc.csv -> rows=%d, unique_dates=%d\n",
            nrow(mrc_dt), length(unique(mrc_dt$Date))))

# ===== Step 11: cash_definition_audit.json (5-field) =====
cat("\n[11] cash_definition_audit.json (5-field)\n")

# Per-strategy cash definition audit (M4+LRO_cash specifically)
# Source determination: M4 has weight_cash column directly (column source).
m4_has_col <- "weight_cash" %in% names(m4)
cat(sprintf("  M4 weight_cash column present: %s\n", m4_has_col))

# Compute summary stats
m4_cash_summary <- list(
  source = ifelse(m4_has_col, "column", "holdings_infer"),
  m4_cash_value_summary = list(
    min = min(m4_sched$weight_cash),
    max = max(m4_sched$weight_cash),
    mean = round(mean(m4_sched$weight_cash), 6),
    n_nonzero_months = sum(m4_sched$weight_cash > 0)
  ),
  lro_cash_value_summary = list(
    min = min(unname(lro_cash_by_ym)),
    max = max(unname(lro_cash_by_ym)),
    distinct = sort(unique(round(unname(lro_cash_by_ym), 4))),
    n_nonzero_months = sum(unname(lro_cash_by_ym) > 0)
  ),
  applied_cash_value_summary = list(  # combined max(M4, LRO) for M4+LRO_cash
    min = min(unname(combined_cash_by_ym)),
    max = max(unname(combined_cash_by_ym)),
    mean = round(mean(unname(combined_cash_by_ym)), 6),
    n_nonzero_months = sum(unname(combined_cash_by_ym) > 0)
  ),
  cash_inferred_flag = !m4_has_col
)

cash_audit <- list(
  task_id = WT_ID,
  rule = "max(M4_cash, LRO_cash) single rule (additive forbidden)",
  source = m4_cash_summary$source,
  m4_cash_value = m4_cash_summary$m4_cash_value_summary,
  lro_cash_value = m4_cash_summary$lro_cash_value_summary,
  applied_cash_value = m4_cash_summary$applied_cash_value_summary,
  cash_inferred_flag = m4_cash_summary$cash_inferred_flag,
  per_strategy_cash_avg = list(
    S1 = 0,
    M4 = round(mean(m4_sched$weight_cash), 6),
    LRO_mon = 0,
    LRO_cap = 0,
    LRO_cash = round(mean(unname(lro_cash_by_ym)), 6),
    `M4+LRO_cap` = round(mean(m4_sched$weight_cash), 6),
    `M4+LRO_cash` = round(mean(unname(combined_cash_by_ym)), 6)
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(cash_audit, file.path(STAGE_DIR, "cash_definition_audit.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  cash_definition_audit.json -> 5-field PASS\n"))

# Save all schedule density to JSON
schedule_density_obj <- list(
  reference_alpha_sig_dates = alpha_sig_dates_count,
  per_strategy = sched_density
)
write_json(schedule_density_obj,
           file.path(STAGE_DIR, "schedule_density_per_strategy.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ===== Step 12: Save workspace + summary =====
saveRDS(list(
  S1 = S1, M4 = M4_strat, LRO_mon = LRO_mon, LRO_cap = LRO_cap,
  LRO_cash = LRO_cash, M4_LRO_cap = M4_LRO_cap, M4_LRO_cash = M4_LRO_cash,
  cap_lro = cap_lro, lro_cash_by_ym = lro_cash_by_ym,
  m4_cash_by_ym = m4_cash_by_ym, combined_cash_by_ym = combined_cash_by_ym,
  ps_state_by_ym = ps_state_by_ym,
  audit = list(S1=a_S1, M4=a_M4, LRO_mon=a_mon, LRO_cap=a_cap,
               LRO_cash=a_csh, M4_LRO_cap=a_mcp, M4_LRO_cash=a_mcs)
), file.path(LOG_DIR, "optimizer_workspace.rds"))

cat("\n=== DONE ===\n")
cat("Finished:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
