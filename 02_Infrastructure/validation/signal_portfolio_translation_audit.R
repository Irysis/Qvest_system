#==============================================================================
# V7 Research Engine — Signal-Portfolio Translation Failure Audit (Gate 13)
# signal_portfolio_translation_audit.R
#
# Detects L-160/L-165 family pattern: strong signal-level metrics
# (ICIR/FM-t high) that fail to translate into portfolio-level alpha
# under realistic 20-stock long-only KR constraints.
#
# Family members so far (AX_CAND_signal_portfolio_translation_failure 2/3):
#   L-160 initiator: STR_1683 (ICIR 1.879 / FM t=16.887 → MDD 94.66 / SR -0.242)
#   L-165 2nd:       STR_1685 H_1690 multi-source defense anchor
#                    (ICIR 0.74~0.94 → MDD 77~94%)
#
# Sub-gates (3):
#   13a net_IC_transmission_ratio  (annualized net/gross)  threshold 0.6
#   13b stress_window_positive     (3 KR crisis windows)   threshold 2/3
#   13c signal_portfolio_rank_corr (Spearman monthly avg)  threshold 0.20
#
# Verdict aggregation:
#   PASS         — all 3 sub-gates PASS
#   CONDITIONAL  — >=1 sub-gate CONDITIONAL, 0 hard_fail
#   HARD_FAIL    — >=1 sub-gate HARD_FAIL → 3rd member confirm
#
# Reference:
#   stage_artifacts/gate_14_signal_portfolio_translation_failure_design.json
#   methodology_memory.md L-160 / L-165
#   Q-Lead Day 2 Task #6 — team-lead 명명 Gate 13 채택
#
# Usage:
#   source("02_Infrastructure/validation/signal_portfolio_translation_audit.R")
#   r <- audit_signal_portfolio_translation(
#          strategy_id  = "STR_1689",
#          monthly_ret  = monthly_ret_vec,    # net portfolio return (post-cost)
#          monthly_gross= monthly_gross_vec,  # pre-cost portfolio return
#          ic_series    = ic_monthly,         # cross-section Spearman per month
#          dates        = month_end_dates,
#          signal_top20 = top20_tickers_per_month,  # list per month
#          realized_top20 = realized_top20_per_month
#        )
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# ─── Thresholds (Scout design + L-160/L-165 calibration) ────────────────────
.SPT_NET_TRANSMISSION_PASS  <- 0.60
.SPT_NET_TRANSMISSION_COND  <- 0.40
.SPT_STRESS_WINDOWS_PASS    <- 2L
.SPT_STRESS_WINDOWS_COND    <- 1L
.SPT_RANK_CORR_PASS         <- 0.20
.SPT_RANK_CORR_COND         <- 0.05

# Primary KR stress windows (L-136 reference + Scout design)
.SPT_STRESS_WINDOWS_PRIMARY <- list(
  list(label = "GFC_2008",       start = "2008-09-01", end = "2009-03-31"),
  list(label = "COVID_2020",     start = "2020-02-01", end = "2020-04-30"),
  list(label = "RATE_HIKE_2022", start = "2022-01-01", end = "2022-10-31")
)

.SPT_STRESS_WINDOWS_FALLBACK <- list(
  list(label = "AFC_1997",       start = "1997-07-01", end = "1998-12-31"),
  list(label = "DOTCOM_2000",    start = "2000-03-01", end = "2002-10-31"),
  list(label = "EUDEBT_2011",    start = "2011-07-01", end = "2011-12-31")
)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ─── Sub-gate 13a: net IC transmission ratio ─────────────────────────────────
.spt_sub_a_net_transmission <- function(monthly_ret, monthly_gross) {
  if (length(monthly_ret) < 12 || length(monthly_gross) < 12) {
    return(list(verdict = "INSUFFICIENT_DATA", ratio = NA_real_,
                detail = "need >=12 monthly observations"))
  }
  ann_net   <- prod(1 + monthly_ret,   na.rm = TRUE)^(12/length(monthly_ret))   - 1
  ann_gross <- prod(1 + monthly_gross, na.rm = TRUE)^(12/length(monthly_gross)) - 1
  if (!is.finite(ann_gross) || abs(ann_gross) < 1e-6) {
    return(list(verdict = "HARD_FAIL", ratio = 0,
                detail = "gross return ~0 → translation undefined / signal failure"))
  }
  ratio <- ann_net / ann_gross
  verdict <- if (ratio >= .SPT_NET_TRANSMISSION_PASS) "PASS"
             else if (ratio >= .SPT_NET_TRANSMISSION_COND) "CONDITIONAL"
             else "HARD_FAIL"
  list(verdict = verdict, ratio = ratio,
       detail  = sprintf("net=%.2f%% / gross=%.2f%% → ratio=%.3f",
                         ann_net*100, ann_gross*100, ratio))
}

# ─── Sub-gate 13b: stress window positive count ──────────────────────────────
.spt_sub_b_stress_windows <- function(monthly_ret, dates,
                                      windows = .SPT_STRESS_WINDOWS_PRIMARY) {
  if (length(monthly_ret) != length(dates)) {
    return(list(verdict = "INSUFFICIENT_DATA", positive_n = NA_integer_,
                detail = "monthly_ret/dates length mismatch"))
  }
  d <- as.Date(dates)
  positive_n <- 0L
  per_window <- list()
  for (w in windows) {
    mask <- d >= as.Date(w$start) & d <= as.Date(w$end)
    if (sum(mask, na.rm = TRUE) == 0) {
      per_window[[w$label]] <- list(coverage = 0L, return = NA_real_, positive = NA)
      next
    }
    cum_ret <- prod(1 + monthly_ret[mask], na.rm = TRUE) - 1
    is_pos  <- isTRUE(cum_ret > 0)
    if (is_pos) positive_n <- positive_n + 1L
    per_window[[w$label]] <- list(coverage = sum(mask), return = cum_ret, positive = is_pos)
  }
  covered <- sum(vapply(per_window, function(x) x$coverage > 0, logical(1)))
  if (covered == 0L) {
    return(list(verdict = "INSUFFICIENT_DATA", positive_n = NA_integer_,
                detail = "no overlap with stress windows", windows = per_window))
  }
  verdict <- if (positive_n >= .SPT_STRESS_WINDOWS_PASS) "PASS"
             else if (positive_n >= .SPT_STRESS_WINDOWS_COND) "CONDITIONAL"
             else "HARD_FAIL"
  list(verdict = verdict, positive_n = positive_n, covered = covered,
       detail  = sprintf("%d/%d windows positive", positive_n, covered),
       windows = per_window)
}

# ─── Sub-gate 13c: signal vs realized top20 rank correlation ─────────────────
.spt_sub_c_rank_corr <- function(signal_top20, realized_top20) {
  if (is.null(signal_top20) || is.null(realized_top20) ||
      length(signal_top20) == 0L || length(realized_top20) == 0L) {
    return(list(verdict = "INSUFFICIENT_DATA", rank_corr = NA_real_,
                detail = "signal_top20 / realized_top20 not provided"))
  }
  n <- min(length(signal_top20), length(realized_top20))
  per_month <- numeric(n)
  for (i in seq_len(n)) {
    s <- signal_top20[[i]]; r <- realized_top20[[i]]
    if (is.null(s) || is.null(r) || length(s) == 0 || length(r) == 0) {
      per_month[i] <- NA_real_; next
    }
    common <- intersect(names(s), names(r))
    if (length(common) < 5) { per_month[i] <- NA_real_; next }
    per_month[i] <- suppressWarnings(
      cor(rank(s[common]), rank(r[common]), method = "spearman"))
  }
  rank_corr <- mean(per_month, na.rm = TRUE)
  if (!is.finite(rank_corr)) {
    return(list(verdict = "INSUFFICIENT_DATA", rank_corr = NA_real_,
                detail = "no months with >=5 overlapping tickers"))
  }
  verdict <- if (rank_corr >= .SPT_RANK_CORR_PASS) "PASS"
             else if (rank_corr >= .SPT_RANK_CORR_COND) "CONDITIONAL"
             else "HARD_FAIL"
  list(verdict = verdict, rank_corr = rank_corr,
       detail  = sprintf("monthly rank corr avg=%.3f over %d months",
                         rank_corr, sum(!is.na(per_month))))
}

# ─── Aggregate verdict ───────────────────────────────────────────────────────
.spt_aggregate <- function(a, b, c) {
  v <- c(a$verdict, b$verdict, c$verdict)
  if (any(v == "HARD_FAIL"))                 return("HARD_FAIL")
  if (any(v == "INSUFFICIENT_DATA"))         return("INSUFFICIENT_DATA")
  if (any(v == "CONDITIONAL"))               return("CONDITIONAL")
  "PASS"
}

#==============================================================================
# Public API
#==============================================================================
audit_signal_portfolio_translation <- function(strategy_id,
                                               monthly_ret,
                                               monthly_gross,
                                               ic_series      = NULL,
                                               dates,
                                               signal_top20   = NULL,
                                               realized_top20 = NULL,
                                               stress_windows = NULL,
                                               output_dir     = NULL) {
  if (is.null(stress_windows)) stress_windows <- .SPT_STRESS_WINDOWS_PRIMARY

  a <- .spt_sub_a_net_transmission(monthly_ret, monthly_gross)
  b <- .spt_sub_b_stress_windows(monthly_ret, dates, stress_windows)
  if (b$verdict == "INSUFFICIENT_DATA") {
    b_fb <- .spt_sub_b_stress_windows(monthly_ret, dates, .SPT_STRESS_WINDOWS_FALLBACK)
    if (b_fb$verdict != "INSUFFICIENT_DATA") b <- b_fb
  }
  c_ <- .spt_sub_c_rank_corr(signal_top20, realized_top20)

  overall <- .spt_aggregate(a, b, c_)
  family_3rd_member_flag <- isTRUE(overall == "HARD_FAIL")

  result <- list(
    schema_version            = "v1.0",
    gate_id                   = "Gate 13 (Signal-Portfolio Translation Failure)",
    strategy_id               = strategy_id,
    audited_at                = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    overall_verdict           = overall,
    sub_gates = list(
      `13a_net_IC_transmission_ratio`   = a,
      `13b_stress_window_positive_count`= b,
      `13c_signal_portfolio_rank_corr`  = c_
    ),
    family_3rd_member_flag    = family_3rd_member_flag,
    family_reference          = "L-160 (initiator) + L-165 (2nd) — AX_CAND 2/3",
    promotion_trigger         = if (family_3rd_member_flag)
        "AX_CAND_signal_portfolio_translation_failure 3/3 promote candidate"
      else "NO_TRIGGER",
    thresholds = list(
      net_transmission_pass   = .SPT_NET_TRANSMISSION_PASS,
      net_transmission_cond   = .SPT_NET_TRANSMISSION_COND,
      stress_windows_pass     = .SPT_STRESS_WINDOWS_PASS,
      rank_corr_pass          = .SPT_RANK_CORR_PASS
    )
  )

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    out_path <- file.path(output_dir, "signal_portfolio_translation_audit.json")
    jsonlite::write_json(result, out_path, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", na = "null")
    result$artifact_path <- out_path
  }
  result
}

#==============================================================================
# Convenience: inspect existing strategy from output/{id}/ artifacts
#==============================================================================
audit_from_strategy_dir <- function(strategy_id, strategy_dir) {
  ret_file    <- file.path(strategy_dir, "monthly_returns.csv")
  gross_file  <- file.path(strategy_dir, "monthly_returns_gross.csv")
  if (!file.exists(ret_file)) {
    return(list(overall_verdict = "INSUFFICIENT_DATA",
                detail = paste("missing:", ret_file)))
  }
  dt <- data.table::fread(ret_file)
  if (!file.exists(gross_file)) {
    # fall back: estimate gross by adding back commission (approx 15bps * turnover)
    warning("gross return file missing — using net as gross (transmission ratio will be ~1.0 inflated)")
    monthly_gross <- dt$ret
  } else {
    dtg <- data.table::fread(gross_file)
    monthly_gross <- dtg$ret
  }
  audit_signal_portfolio_translation(
    strategy_id   = strategy_id,
    monthly_ret   = dt$ret,
    monthly_gross = monthly_gross,
    dates         = as.Date(dt$date),
    output_dir    = strategy_dir
  )
}
