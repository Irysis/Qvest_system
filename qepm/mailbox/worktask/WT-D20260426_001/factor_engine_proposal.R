#==============================================================================
# WT-D20260426_001 Iter 7 Cross-family Diversifier Alpha
# Factor Engine Proposal — Liquidity Premium multi-axis + R13 NCSKEW (cross-family)
#
# Hypothesis: STR_1700 (Analyst_Consensus + Quality_Earnings + Momentum_Residual
#   + Distress) NOT IN. Liquidity premium (Pastor-Stambaugh 2003 / Amihud 2002 /
#   Kyle 1985) + tail risk (Chen-Hong-Stein 2001 NCSKEW) cross-family composite.
#
# Sequential Admission target: TDC vs STR_1700 < 0.30 (Replacement 아닌 add-on).
#
# Factors (4-axis composite — all multi-axis to avoid single-quality AX-004):
#   Slot A: L01_Amihud         (illiquidity premium, lower_better → flipped)
#   Slot B: L11_Kyle_Lambda    (price impact lambda, lower_better → flipped)
#   Slot C: L12_PS_Gamma       (Pastor-Stambaugh gamma proxy, lower_better)
#   Slot D: R13_NCSKEW         (negative coskewness, cross-family tail risk)
#
# Composite: equal-weight 25% × 4-axis (multi-axis avoids single-signal失敗 AX-004
#   pattern, and provides Liquidity_Risk × Tail_Risk 2-family base + within-Liquidity
#   3-axis diversification).
#
# AX axiom check:
#   AX-003 (KR value EP_STANDALONE): EXCLUSION — no value factor used
#   AX-004 (single quality_profitability): EXCLUSION — no quality_profitability
#   AX-005 (BAB single-sleeve): EXCLUSION — no MK01_CAPM_Beta
#   AX-007 (single-sleeve top20 fail): EXCEPTION (1) multi-sleeve — proposal:
#     Forge에 STR_1700 + 본 alpha = paired multi-sleeve (50/50 또는 70/30)
#     구조 명시. single-sleeve top20 unconditional 사용 시 hard fail 위험 명시.
#
# Output: stage_artifacts/WT_D20260426_001/alpha_scores.parquet (시계열 alpha)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

# ---- Paths & config ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID    <- "WT-D20260426_001"
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_001")
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 4-axis composite definition ----
# Liquidity 3-axis + Tail-risk 1-axis (cross-family)
SELECTED_FACTORS <- c(
  "L01_Amihud",        # Amihud (2002) illiquidity ratio
  "L11_Kyle_Lambda",   # Kyle (1985) lambda price impact
  "L12_PS_Gamma",      # Pastor-Stambaugh (2003) gamma proxy
  "R13_NCSKEW"         # Chen-Hong-Stein (2001) negative coskewness
)
THETA <- c(0.25, 0.25, 0.25, 0.25)
names(THETA) <- SELECTED_FACTORS

# ---- STR_1700 reference (TDC / period alignment) ----
str1700 <- read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet") |>
  setDT()
sig_dates_pool <- sort(unique(str1700$Date))   # 239 months

# Discovery WT — full period (2004-01 ~ 2023-11) for max statistical power
# Train/Validation split: 2004-2017 train | 2018-2023 validation (holdout)
TRAIN_END  <- as.Date("2017-12-31")
VALID_END  <- as.Date("2023-11-30")

cat("[Iter7-Alpha] Sig dates:", length(sig_dates_pool),
    "from", as.character(min(sig_dates_pool)), "to",
    as.character(max(sig_dates_pool)), "\n")
cat("[Iter7-Alpha] Train end:", as.character(TRAIN_END),
    "| Validation end:", as.character(VALID_END), "\n")

# ---- R13 parallel rolling alpha generation per sig_date ----
n_workers <- min(8L, parallel::detectCores() - 1L)
cat("[Iter7-Alpha] Parallel workers:", n_workers, "\n")
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

t_alpha_start <- Sys.time()

# Per-sig_date alpha_score generation (PIT-safe via load_month_factors)
results <- future_lapply(sig_dates_pool, function(sd) {
  tryCatch({
    fdt <- suppressMessages(load_month_factors(sig_date = sd, coverage_min = 0.05))
    if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
    setDT(fdt)
    # Subset to selected
    sub <- fdt[Factor_Name %in% names(THETA),
               .(Ticker, Factor_Name, Z_Score_Aligned)]
    if (nrow(sub) == 0) return(NULL)
    # Wide cast
    w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
               fun.aggregate = mean)
    # Composite alpha (equal-weight 4-axis)
    w[, alpha_raw := 0]
    counts <- 0
    for (fn in names(THETA)) {
      if (fn %in% names(w)) {
        v <- w[[fn]]
        v[is.na(v)] <- 0  # missing → neutral (already z-score)
        w[, alpha_raw := alpha_raw + THETA[fn] * v]
        counts <- counts + 1L
      }
    }
    if (counts == 0L) return(NULL)
    # Cross-sectional re-standardize composite
    w[, alpha := {
      m <- mean(alpha_raw, na.rm = TRUE)
      s <- sd(alpha_raw, na.rm = TRUE)
      if (!is.na(s) && s > 1e-12) (alpha_raw - m) / s else alpha_raw - m
    }]
    # Confidence: based on # of non-missing axes (1 axis missing → 0.75 etc)
    w[, axes_present := 0]
    for (fn in names(THETA)) {
      if (fn %in% names(w)) {
        w[, axes_present := axes_present + as.integer(!is.na(get(fn)))]
      }
    }
    w[, confidence := pmax(0.25, axes_present / length(THETA))]
    w[, sig_date := sd]
    w[, .(sig_date, Ticker, alpha, confidence, axes_present,
          alpha_raw)]
  }, error = function(e) {
    message("[Iter7-Alpha] sig_date=", sd, " error: ", conditionMessage(e))
    NULL
  })
})

plan(sequential)

t_alpha_end <- Sys.time()
elapsed_alpha <- as.numeric(difftime(t_alpha_end, t_alpha_start, units = "secs"))
cat("[Iter7-Alpha] Alpha time-series gen:",
    round(elapsed_alpha, 1), "s\n")

results <- results[!sapply(results, is.null)]
alpha_ts <- rbindlist(results, fill = TRUE)
cat("[Iter7-Alpha] Total rows:", nrow(alpha_ts),
    "| sig_dates:", uniqueN(alpha_ts$sig_date),
    "| tickers:", uniqueN(alpha_ts$Ticker), "\n")

# ---- Save ----
out_path <- file.path(ART_DIR, "alpha_scores.parquet")
write_parquet(alpha_ts, out_path)
cat("[Iter7-Alpha] Saved:", out_path, "\n")

# ---- Diagnostics computation ----
cat("\n[Iter7-Alpha] Computing diagnostics...\n")

# Need 1M-forward returns. Use RAWDATA cache.
load_rawdata_cached <- function() {
  rds <- file.path(".cache", "rawdata.rds")
  if (!file.exists(rds)) stop("rawdata.rds not found")
  readRDS(rds)
}
raw <- tryCatch(load_rawdata_cached(), error = function(e) NULL)
if (!is.null(raw)) {
  rd <- as.data.table(raw)
  if ("Ret" %in% names(rd) && "Date" %in% names(rd) && "Ticker" %in% names(rd)) {
    rd <- rd[, .(Date = as.Date(Date), Ticker, Ret)]
    # Monthly forward return: aggregate daily Ret to monthly compound
    rd[, ym := format(Date, "%Y-%m")]
    monthly_ret <- rd[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
                      by = .(Ticker, ym)]
    monthly_ret[, sig_date := as.Date(paste0(ym, "-01"))]
    monthly_ret[, sig_date_prev := sig_date]
    # Forward-1m: alpha at month t paired with realized return month t (sig_date == sig_date)
    # STR_1700 alpha 'sig_date' == start of month. Forward 1M return is realized
    # over that month. We use prev month's alpha → current month return.
    # alpha_ts$sig_date matches STR_1700 first-of-month. Use realized return at
    # same month (alpha at start-of-month → return realized over that month).
    fwd_ret <- monthly_ret[, .(Ticker, sig_date, Ret_1m)]
    setkey(fwd_ret, sig_date, Ticker)
    setkey(alpha_ts, sig_date, Ticker)
    merged <- fwd_ret[alpha_ts, on = c("sig_date", "Ticker"), nomatch = NA]

    # Per-month rank IC (Spearman)
    ic_per_month <- merged[!is.na(Ret_1m) & !is.na(alpha),
                            .(IC = cor(alpha, Ret_1m, method = "spearman"),
                              N = .N),
                            by = sig_date]
    ic_per_month <- ic_per_month[!is.na(IC) & N >= 30L]

    rank_ic <- mean(ic_per_month$IC, na.rm = TRUE)
    icir    <- if (sd(ic_per_month$IC, na.rm = TRUE) > 1e-9) {
      rank_ic / sd(ic_per_month$IC, na.rm = TRUE)
    } else NA_real_
    n_months <- nrow(ic_per_month)
    harvey_t <- if (!is.na(icir)) icir * sqrt(n_months) else NA_real_

    # Subperiod stability
    ic_per_month[, period := fifelse(sig_date <= as.Date("2014-12-31"), "P1_08_14",
                                     fifelse(sig_date <= as.Date("2019-12-31"),
                                             "P2_15_19", "P3_20_23"))]
    sp_ic <- ic_per_month[, .(IC_sp = mean(IC), N = .N), by = period]

    # Subperiod stability metric: fraction of subperiods with same-sign IC
    same_sign <- mean(sign(sp_ic$IC_sp) == sign(rank_ic), na.rm = TRUE)

    # Decile monotonicity (use last 60 months for speed; optional for time)
    last_dates <- tail(sort(unique(merged$sig_date)), 60)
    mono_dt <- merged[sig_date %in% last_dates & !is.na(alpha) & !is.na(Ret_1m)]
    mono_dt[, decile := cut(alpha,
                            breaks = quantile(alpha,
                                              probs = seq(0, 1, 0.1),
                                              na.rm = TRUE),
                            include.lowest = TRUE,
                            labels = 1:10),
            by = sig_date]
    decile_ret <- mono_dt[, .(Ret = mean(Ret_1m, na.rm = TRUE)),
                          by = .(decile)]
    decile_ret <- decile_ret[!is.na(decile)]
    decile_ret[, decile_n := as.integer(as.character(decile))]
    setorder(decile_ret, decile_n)
    monotonicity <- if (nrow(decile_ret) >= 5L) {
      cor(decile_ret$decile_n, decile_ret$Ret, method = "spearman")
    } else NA_real_

    cat("\n=== Diagnostics ===\n")
    cat("Rank IC (full):     ", round(rank_ic, 4), "\n")
    cat("ICIR:               ", round(icir, 3), "\n")
    cat("Harvey t (≈ICIR√N): ", round(harvey_t, 2), "(N=", n_months, ")\n")
    cat("Subperiod IC:\n"); print(sp_ic)
    cat("Same-sign subperiod stability:", round(same_sign, 2), "\n")
    cat("Monotonicity (last 60m):", round(monotonicity, 3), "\n")

    # Save diagnostics
    diag_path <- file.path(ART_DIR, "alpha_diagnostics.rds")
    saveRDS(list(
      rank_ic = rank_ic,
      icir = icir,
      harvey_t = harvey_t,
      n_months = n_months,
      ic_per_month = ic_per_month,
      subperiod_ic = sp_ic,
      same_sign_stability = same_sign,
      monotonicity = monotonicity,
      decile_returns = decile_ret
    ), diag_path)
    cat("Saved diagnostics:", diag_path, "\n")
  } else {
    cat("[WARN] RAWDATA missing required columns\n")
  }
}

cat("\n[Iter7-Alpha] DONE.\n")
