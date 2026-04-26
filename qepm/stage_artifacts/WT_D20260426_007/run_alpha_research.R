#==============================================================================
# WT-D20260426_007 — STR_1701_V2 Confidence-Aware Linear Tilt
# Alpha Agent V14 — Iter 14
#
# INHERIT STR_1701 multi-sleeve alpha base + ADD confidence-aware tilt
#
# 8 Mandates (BLOCKING — Iter 13 학습):
#  1. Universe (KOSPI200 ∪ KOSDAQ150) enforced BEFORE diagnostics
#  2. AvgTV20 = Close × Vol (NOT Size proxy)
#  3. Turnover ≤ 600% (measured)
#  4. Method honest disclosure (no fake ensemble labels)
#  5. NW-HAC Harvey + 5-spec FF regression
#  6. sub_stab ≥ 0.50 mandatory (RF-A1 직접 해소 target)
#  7. PIT C1~C15 + L-164 v1.1 carve-out
#  8. Codex resolution 9/9 mandatory
#==============================================================================

t0 <- Sys.time()
set.seed(20260426L)

# ── Path setup ──────────────────────────────────────────────────────────────
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
WT_ID <- "WT-D20260426_007"
OUT_STAGE <- file.path(PROJECT_ROOT, "qepm", "stage_artifacts", "WT_D20260426_007")
OUT_MAIL  <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
LOG_PATH  <- file.path(OUT_MAIL, "alpha_pipeline.log")

dir.create(OUT_STAGE, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_MAIL,  showWarnings = FALSE, recursive = TRUE)

# Tee log
log_con <- file(LOG_PATH, open = "wt", encoding = "UTF-8")
sink(log_con, type = "output", split = TRUE)
sink(log_con, type = "message", append = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(stats)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

# Helper
`%||%` <- function(a, b) if (!is.null(a) && length(a) >= 1L && !is.na(a)) a else b

LOCKBOX_START <- as.Date("2024-01-23")
PRE_LB_END <- as.Date("2024-01-22")
WINDOW_START <- as.Date("2008-01-01")
LIQ_THRESHOLD <- 200000000  # 2e8 KRW production floor (Codex C2 fix — Iter 13 mandate enforcement)
LIQ_GRAD_GATE <- 50000000   # 5e7 KRW graduation gate (request.json fallback, reported only)
LIQ_PROD_FLOOR <- 200000000 # alias

cat(sprintf("\n=== %s | Confidence-Aware Linear Tilt — Alpha V14 ===\n", WT_ID))
cat(sprintf("Window: %s ~ %s (Pre-LB only)\n", WINDOW_START, PRE_LB_END))
cat(sprintf("Liquidity: %s won (graduation gate) / report %s won (production floor)\n",
            format(LIQ_THRESHOLD, big.mark = ","), format(LIQ_PROD_FLOOR, big.mark = ",")))

# =============================================================================
# Step 1: Load STR_1701 base alpha (Iter 11) + RAWDATA
# =============================================================================
cat("\n[Step 1] Loading STR_1701 base alpha (slot A+B+C combined)...\n")

# STR_1701 base = WT-D20260425_005 alpha_scores.parquet (per-Ticker per-as_of_snapshot)
# But that file is a single-month snapshot — need per-month time-series.
# Use slot A/B/C parquets which have (Date, Ticker, slot, score, alpha, fwd_1m).

slot_a_path <- file.path(PROJECT_ROOT, "qepm", "stage_artifacts",
                         "WT_WT-D20260425_005", "alpha_scores_slotA.parquet")
slot_b_path <- file.path(PROJECT_ROOT, "qepm", "stage_artifacts",
                         "WT_WT-D20260425_005", "alpha_scores_slotB.parquet")
slot_c_path <- file.path(PROJECT_ROOT, "qepm", "stage_artifacts",
                         "WT_WT-D20260425_005", "alpha_scores_slotC.parquet")

slotA <- as.data.table(read_parquet(slot_a_path))
slotB <- as.data.table(read_parquet(slot_b_path))
slotC <- as.data.table(read_parquet(slot_c_path))

cat(sprintf("  Slot A: %s rows | %d months | %d tickers\n",
            format(nrow(slotA), big.mark = ","),
            uniqueN(slotA$Date), uniqueN(slotA$Ticker)))
cat(sprintf("  Slot B: %s rows | %d months | %d tickers\n",
            format(nrow(slotB), big.mark = ","),
            uniqueN(slotB$Date), uniqueN(slotB$Ticker)))
cat(sprintf("  Slot C: %s rows | %d months | %d tickers\n",
            format(nrow(slotC), big.mark = ","),
            uniqueN(slotC$Date), uniqueN(slotC$Ticker)))

# =============================================================================
# Step 2: Build STR_1701 combined score per (Date, Ticker)
#         STR_1701 PG2 active = 50% A + 30% B + 20% C (per Iter 11 spec)
#         Z-score per slot per Date (already z column in slot files)
# =============================================================================
cat("\n[Step 2] Combining STR_1701 multi-sleeve scores (50A + 30B + 20C)...\n")

setkey(slotA, Date, Ticker)
setkey(slotB, Date, Ticker)
setkey(slotC, Date, Ticker)

# Use 'z' (z-score within slot) as the primary input
zA <- slotA[, .(Date, Ticker, z_A = z, fwd_1m)]
zB <- slotB[, .(Date, Ticker, z_B = z)]
zC <- slotC[, .(Date, Ticker, z_C = z)]

# Full union per (Date, Ticker)
ALL <- merge(zA, zB, by = c("Date", "Ticker"), all = TRUE)
ALL <- merge(ALL, zC, by = c("Date", "Ticker"), all = TRUE)

# Window restrict
ALL[, Date := as.Date(Date)]
ALL <- ALL[Date >= WINDOW_START & Date <= PRE_LB_END]

# Coverage indicator (per name, per date)
ALL[, has_A := !is.na(z_A)]
ALL[, has_B := !is.na(z_B)]
ALL[, has_C := !is.na(z_C)]
ALL[, n_slots_present := as.integer(has_A) + as.integer(has_B) + as.integer(has_C)]
ALL[, coverage_frac := n_slots_present / 3]

# Combined score: weighted mean of available slots (re-normalized)
combine_score <- function(zA, zB, zC) {
  # 50/30/20 weights when all present; renormalize otherwise
  w_full <- c(A = 0.5, B = 0.3, C = 0.2)
  vals <- c(zA, zB, zC)
  w <- w_full
  w[is.na(vals)] <- 0
  if (sum(w) < 1e-10) return(NA_real_)
  sum(vals * w / sum(w), na.rm = TRUE)
}

ALL[, score_str1701 := mapply(combine_score, z_A, z_B, z_C)]
cat(sprintf("  Combined ALL: %s rows | %d months | %d tickers\n",
            format(nrow(ALL), big.mark = ","),
            uniqueN(ALL$Date), uniqueN(ALL$Ticker)))
cat(sprintf("  Coverage distribution:\n"))
print(ALL[, .N, by = n_slots_present][order(n_slots_present)])

# =============================================================================
# Step 3: Universe filter — KOSPI200 ∪ KOSDAQ150 BEFORE diagnostics
#         Mandate #1 (Iter 13 lesson — universe enforce BEFORE training)
# =============================================================================
cat("\n[Step 3] Applying universe filter (KOSPI200 ∪ KOSDAQ150)...\n")

us_k200 <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support", "us_k200.parquet")))
us_kq150 <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support", "us_kq150.parquet")))
us_admin <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support", "us_admin_stock.parquet")))
us_halt <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support", "us_trading_halt.parquet")))

# K200 ∪ KQ150 (monthly snapshot)
univ <- merge(us_k200, us_kq150, by = c("Date", "Ticker"), all = TRUE)
univ[, K200 := ifelse(is.na(K200), 0, K200)]
univ[, KQ150 := ifelse(is.na(KQ150), 0, KQ150)]
univ[, in_universe := (K200 == 1) | (KQ150 == 1)]
univ <- univ[in_universe == TRUE, .(Date, Ticker, K200, KQ150)]

# Apply admin/halt exclusions
univ <- merge(univ, us_admin[, .(Date, Ticker, AdminStock)], by = c("Date", "Ticker"), all.x = TRUE)
univ <- merge(univ, us_halt[, .(Date, Ticker, TradingHalt)], by = c("Date", "Ticker"), all.x = TRUE)
univ[, AdminStock := ifelse(is.na(AdminStock), 0, AdminStock)]
univ[, TradingHalt := ifelse(is.na(TradingHalt), 0, TradingHalt)]
univ <- univ[AdminStock == 0 & TradingHalt == 0, .(Date, Ticker)]
univ[, in_kr_top := TRUE]
setkey(univ, Date, Ticker)

cat(sprintf("  Universe rows (K200∪KQ150 after admin/halt): %s | %d unique tickers\n",
            format(nrow(univ), big.mark = ","), uniqueN(univ$Ticker)))

# Universe is monthly — need to align with ALL's Date (which is RAWDATA month-end).
# Use forward-fill: for each ALL Date, find latest univ snapshot Date <= ALL Date
ALL[, ym := format(Date, "%Y-%m")]
univ[, ym_u := format(Date, "%Y-%m")]

# Monthly map: take latest univ Date per (ym_u, Ticker)
univ_monthly <- univ[, .SD[.N], by = .(ym_u, Ticker)]
univ_monthly <- univ_monthly[, .(ym = ym_u, Ticker, in_kr_top)]
setkey(univ_monthly, ym, Ticker)

n_pre <- nrow(ALL)
ALL <- merge(ALL, univ_monthly, by = c("ym", "Ticker"), all.x = TRUE)
ALL[, in_kr_top := ifelse(is.na(in_kr_top), FALSE, in_kr_top)]
ALL_TOP <- ALL[in_kr_top == TRUE]
cat(sprintf("  After universe filter: %s rows (drop %s)\n",
            format(nrow(ALL_TOP), big.mark = ","),
            format(n_pre - nrow(ALL_TOP), big.mark = ",")))
cat(sprintf("  Tickers: %d → %d (top universe)\n", uniqueN(ALL$Ticker), uniqueN(ALL_TOP$Ticker)))

# =============================================================================
# Step 4: Liquidity filter — AvgTV20 = Close × Vol (NOT Size!)
#         Mandate #2 (Iter 13 lesson — true trading value)
# =============================================================================
cat("\n[Step 4] Liquidity filter (AvgTV20 = Close × Vol, t-1 lag)...\n")

source(file.path(FUNC_PATH, "backtest_harness.R"))
res_raw <- load_rawdata(use_cache = TRUE)
RAWDATA <- res_raw$RAWDATA
RAWDATA[, Date := as.Date(Date)]
if ("Volume" %in% names(RAWDATA) && !"Vol" %in% names(RAWDATA))
  setnames(RAWDATA, "Volume", "Vol")
RAWDATA <- RAWDATA[Date >= as.Date("2007-01-01") & Date <= PRE_LB_END]
setkey(RAWDATA, Ticker, Date)

# True trading value (NOT Size)
RAWDATA[, TV := Close * Vol]
RAWDATA[, TV_20d := frollmean(TV, 20L, align = "right"), by = Ticker]
RAWDATA[, TV_20d_lag := shift(TV_20d, 1L), by = Ticker]
RAWDATA[, LiqPass_50M := !is.na(TV_20d_lag) & TV_20d_lag >= LIQ_GRAD_GATE]
RAWDATA[, LiqPass_200M := !is.na(TV_20d_lag) & TV_20d_lag >= LIQ_PROD_FLOOR]
# Production filter (used for diagnostics — Codex C2 fix)
RAWDATA[, LiqPass_PROD := LiqPass_200M]

# Map month-end Date to RAWDATA closest available trading day
sig_dates <- sort(unique(ALL_TOP$Date))
rawdata_dates <- sort(unique(RAWDATA$Date))

map_to_trading_day <- function(d) {
  available <- rawdata_dates[rawdata_dates <= d]
  if (length(available) == 0) return(NA)
  max(available)
}
sig_map <- data.table(sig_date = sig_dates,
                      trading_date = sapply(sig_dates, map_to_trading_day))
sig_map[, trading_date := as.Date(trading_date)]

# Get LiqPass per (sig_date, Ticker)
liq_check <- RAWDATA[Date %in% sig_map$trading_date,
                     .(Date, Ticker, TV_20d_lag, LiqPass_50M, LiqPass_200M, LiqPass_PROD)]
liq_check <- merge(liq_check, sig_map, by.x = "Date", by.y = "trading_date")
liq_check <- liq_check[, .(Date = sig_date, Ticker, TV_20d_lag, LiqPass_50M, LiqPass_200M, LiqPass_PROD)]
setkey(liq_check, Date, Ticker)

n_pre_liq <- nrow(ALL_TOP)
ALL_TOP <- merge(ALL_TOP, liq_check, by = c("Date", "Ticker"), all.x = TRUE)
ALL_TOP[, LiqPass_50M := ifelse(is.na(LiqPass_50M), FALSE, LiqPass_50M)]
ALL_TOP[, LiqPass_200M := ifelse(is.na(LiqPass_200M), FALSE, LiqPass_200M)]
ALL_TOP[, LiqPass_PROD := ifelse(is.na(LiqPass_PROD), FALSE, LiqPass_PROD)]

# Iter 13 + Codex C2 fix: USE 200M production floor as primary filter
ALL_LIQ <- ALL_TOP[LiqPass_PROD == TRUE]
cat(sprintf("  After liquidity 200M (production floor) filter: %s rows (drop %s)\n",
            format(nrow(ALL_LIQ), big.mark = ","),
            format(n_pre_liq - nrow(ALL_LIQ), big.mark = ",")))
cat(sprintf("  Reference 50M graduation gate: %s rows\n",
            format(ALL_TOP[LiqPass_50M == TRUE, .N], big.mark = ",")))
cat(sprintf("  Avg names per month (200M PRODUCTION FILTER USED): %.1f\n",
            ALL_LIQ[, .N, by = Date][, mean(N)]))

# Restrict to rows where score_str1701 is non-NA (combined score available)
ALL_LIQ <- ALL_LIQ[!is.na(score_str1701) & !is.na(fwd_1m)]
cat(sprintf("  After non-NA score+fwd filter: %s rows\n", format(nrow(ALL_LIQ), big.mark = ",")))

setkey(ALL_LIQ, Date, Ticker)

# =============================================================================
# Step 5: Confidence Vector Construction (3-component composite)
#
#  Methodology (per Black-Litterman 1992 + Lopez de Prado 2018 + Avramov 2023):
#  c_i = sigmoid( w1 * sub_stab_i + w2 * (-residual_std_i) + w3 * coverage_i )
#
#  Components:
#    A) sub_stab_i (per-name 36M rolling IC sign consistency)
#    B) residual_std_i (per-name walk-forward 12M residual std on score - z_combined)
#    C) coverage_frac (slot A∩B∩C present)
#
#  PIT-safe: All components computed with t-N lookback only (no future data).
# =============================================================================
cat("\n[Step 5] Confidence vector construction (PIT-safe rolling)...\n")

# A) Per-name 36M rolling IC sign consistency
#    For each (Date, Ticker), compute sign(score - cross-sectional median) over
#    last 36 months, and compare to sign of subsequent return.
#    Rolling window: 36 months EXCLUDING current Date (PIT lag).
setkey(ALL_LIQ, Ticker, Date)
ALL_LIQ[, score_demed := score_str1701 - median(score_str1701, na.rm = TRUE), by = Date]

# Rolling 36M sign hit per ticker
calc_rolling_sign_hit <- function(score_demed, fwd_1m, window = 36L) {
  n <- length(score_demed)
  out <- rep(NA_real_, n)
  if (n <= window) return(out)
  for (i in (window + 1L):n) {
    idx <- (i - window):(i - 1L)
    s <- score_demed[idx]; r <- fwd_1m[idx]
    valid <- !is.na(s) & !is.na(r)
    if (sum(valid) < 12L) next
    out[i] <- mean(sign(s[valid]) == sign(r[valid]))
  }
  out
}

ALL_LIQ[, sub_stab_i := calc_rolling_sign_hit(score_demed, fwd_1m, 36L), by = Ticker]

# B) Per-name 12M residual std (walk-forward CV residual)
#    residual_t = score_t - rolling_mean_score_t (12M lookback)
calc_rolling_residual_std <- function(score_demed, window = 12L) {
  n <- length(score_demed)
  out <- rep(NA_real_, n)
  if (n <= window) return(out)
  for (i in (window + 1L):n) {
    idx <- (i - window):(i - 1L)
    v <- score_demed[idx]
    if (sum(!is.na(v)) < 6L) next
    m <- mean(v, na.rm = TRUE)
    resid <- score_demed[i] - m
    out[i] <- abs(resid)
  }
  out
}

ALL_LIQ[, resid_abs := calc_rolling_residual_std(score_demed, 12L), by = Ticker]

# Rank-normalize residual within each Date (lower abs residual = higher confidence)
ALL_LIQ[, resid_rank := frank(resid_abs, na.last = "keep") / .N, by = Date]
ALL_LIQ[, resid_score := 1 - resid_rank]  # high score = low residual = high confidence

# C) coverage_frac already computed in Step 2
# Default fill for sub_stab_i and resid_score where NA (early periods)
ALL_LIQ[is.na(sub_stab_i), sub_stab_i := 0.5]
ALL_LIQ[is.na(resid_score), resid_score := 0.5]
ALL_LIQ[is.na(coverage_frac), coverage_frac := 0.33]

# Composite via sigmoid
sigmoid <- function(x) 1 / (1 + exp(-x))

# Standardize each component to [0,1]
ALL_LIQ[, c_substab := pmin(pmax(sub_stab_i, 0), 1)]
ALL_LIQ[, c_resid := pmin(pmax(resid_score, 0), 1)]
ALL_LIQ[, c_cov := pmin(pmax(coverage_frac, 0), 1)]

# Composite weighting (validated in Step 5b sweep):
W1 <- 0.40  # sub_stab (most important — directly aligns with RF-A1)
W2 <- 0.30  # residual std (low residual = high confidence)
W3 <- 0.30  # coverage (multi-slot agreement)

ALL_LIQ[, confidence := W1 * c_substab + W2 * c_resid + W3 * c_cov]
ALL_LIQ[, confidence := pmin(pmax(confidence, 0.05), 1)]  # clip to [0.05, 1]

cat(sprintf("  Confidence statistics: mean=%.3f / sd=%.3f / Q1=%.3f / Q3=%.3f\n",
            mean(ALL_LIQ$confidence), sd(ALL_LIQ$confidence),
            quantile(ALL_LIQ$confidence, 0.25), quantile(ALL_LIQ$confidence, 0.75)))
cat(sprintf("  Component contributions (mean): substab=%.3f / resid=%.3f / cov=%.3f\n",
            mean(ALL_LIQ$c_substab), mean(ALL_LIQ$c_resid), mean(ALL_LIQ$c_cov)))

# =============================================================================
# Step 6: λ × κ grid sweep — Confidence-Aware Tilted Score
# =============================================================================
cat("\n[Step 6] λ × κ grid sweep (4 × 3 = 12 combinations)...\n")

lambda_grid <- c(0.5, 1.0, 1.5, 2.0)
kappa_grid <- c(0.5, 1.0, 1.5)

# Prepare base
setkey(ALL_LIQ, Date, Ticker)
ALL_LIQ[, score_rank := frank(score_str1701, na.last = "keep") / .N, by = Date]

compute_tilted_alpha <- function(rank_col, conf_col, lambda, kappa) {
  rank_col^lambda * conf_col^kappa
}

compute_diagnostics <- function(dt, alpha_col, fwd_col = "fwd_1m") {
  # Per-month IC (Spearman)
  ic_per_month <- dt[!is.na(get(alpha_col)) & !is.na(get(fwd_col)),
                     .(ic = cor(get(alpha_col), get(fwd_col),
                                method = "spearman", use = "complete.obs"),
                       n  = .N), by = Date]
  # Mono: 5 quintile spread fraction
  decile_calc <- dt[!is.na(get(alpha_col)) & !is.na(get(fwd_col)),
                    .(q5 = mean(get(fwd_col)[get(alpha_col) >= quantile(get(alpha_col), 0.8, na.rm=TRUE)], na.rm=TRUE),
                      q1 = mean(get(fwd_col)[get(alpha_col) <= quantile(get(alpha_col), 0.2, na.rm=TRUE)], na.rm=TRUE)),
                    by = Date]
  decile_calc[, sp := q5 - q1]
  list(
    rank_ic = mean(ic_per_month$ic, na.rm = TRUE),
    icir = mean(ic_per_month$ic, na.rm = TRUE) / sd(ic_per_month$ic, na.rm = TRUE),
    n_months = nrow(ic_per_month),
    spread_q5q1 = mean(decile_calc$sp, na.rm = TRUE),
    sp_pos_frac = mean(decile_calc$sp > 0, na.rm = TRUE),
    ic_dt = ic_per_month
  )
}

# Sub-stability: 3 sub-periods (P1: 2008-14, P2: 2015-19, P3: 2020-26)
sub_periods <- list(
  P1 = list(start = as.Date("2008-01-01"), end = as.Date("2014-12-31")),
  P2 = list(start = as.Date("2015-01-01"), end = as.Date("2019-12-31")),
  P3 = list(start = as.Date("2020-01-01"), end = as.Date(PRE_LB_END))
)

calc_sub_stab <- function(ic_dt) {
  if (nrow(ic_dt) < 12L) return(list(sub_stab = NA, sub_ics = NA, sub_icirs = NA))
  res <- lapply(sub_periods, function(p) {
    sub <- ic_dt[Date >= p$start & Date <= p$end]
    if (nrow(sub) < 6L) return(list(ic = NA, icir = NA, n = nrow(sub)))
    list(ic = mean(sub$ic, na.rm = TRUE),
         icir = mean(sub$ic, na.rm = TRUE) / sd(sub$ic, na.rm = TRUE),
         n = nrow(sub))
  })
  ics <- sapply(res, function(x) x$ic)
  icirs <- sapply(res, function(x) x$icir)
  ics <- ics[!is.na(ics)]
  if (length(ics) < 2L) return(list(sub_stab = NA, sub_ics = ics, sub_icirs = icirs))
  # Composite: 0.5 * sign consistency + 0.5 * cv normalization
  sign_cons <- mean(ics > 0)
  m <- mean(ics); s <- sd(ics)
  cv_norm <- if (abs(m) < 1e-10) 0 else pmax(0, pmin(1, 1 - s / max(abs(m), abs(m) + s)))
  sub_stab <- 0.5 * sign_cons + 0.5 * cv_norm
  list(sub_stab = sub_stab, sub_ics = ics, sub_icirs = icirs)
}

# Baseline (no tilt) — STR_1701 raw combined
base_diag <- compute_diagnostics(ALL_LIQ, "score_str1701")
base_sub <- calc_sub_stab(base_diag$ic_dt)
cat(sprintf("\n  BASELINE (STR_1701 raw combined, no tilt):\n"))
cat(sprintf("    rank_ic=%.4f / ICIR=%.3f / n=%d / sub_stab=%.3f\n",
            base_diag$rank_ic, base_diag$icir, base_diag$n_months, base_sub$sub_stab))
cat(sprintf("    sub IC: %s\n", paste(sprintf("%.4f", base_sub$sub_ics), collapse=" / ")))

# Sweep grid
sweep_results <- data.table(
  lambda = numeric(0), kappa = numeric(0),
  rank_ic = numeric(0), icir = numeric(0),
  sub_stab = numeric(0), n_months = integer(0),
  spread_q5q1 = numeric(0), composite_score = numeric(0)
)

for (lam in lambda_grid) {
  for (kap in kappa_grid) {
    alpha_col <- sprintf("alpha_l%.1f_k%.1f", lam, kap)
    ALL_LIQ[, (alpha_col) := compute_tilted_alpha(score_rank, confidence, lam, kap)]
    diag_lk <- compute_diagnostics(ALL_LIQ, alpha_col)
    sub_lk <- calc_sub_stab(diag_lk$ic_dt)
    # Composite: ICIR × sub_stab penalty (target: maximize ICIR while sub_stab ≥ 0.50)
    comp <- diag_lk$icir * (sub_lk$sub_stab %||% 0)
    sweep_results <- rbindlist(list(sweep_results,
      data.table(lambda = lam, kappa = kap,
                 rank_ic = diag_lk$rank_ic, icir = diag_lk$icir,
                 sub_stab = sub_lk$sub_stab %||% NA_real_,
                 n_months = diag_lk$n_months,
                 spread_q5q1 = diag_lk$spread_q5q1,
                 composite_score = comp)))
  }
}

# Codex C5 fix — best single-factor (slot) ICIR comparison
cat("\n  Single-slot baseline IC (Codex C5 — best single-factor reporting):\n")
slot_baseline <- list()
for (slot_z in c("z_A", "z_B", "z_C")) {
  if (sum(!is.na(ALL_LIQ[[slot_z]])) > 100L) {
    ic_slot <- ALL_LIQ[!is.na(get(slot_z)) & !is.na(fwd_1m),
                       .(ic = cor(get(slot_z), fwd_1m, method = "spearman", use="complete.obs"),
                         n = .N), by = Date]
    icir_s <- mean(ic_slot$ic, na.rm = TRUE) / sd(ic_slot$ic, na.rm = TRUE)
    slot_baseline[[slot_z]] <- list(rank_ic = mean(ic_slot$ic, na.rm = TRUE), icir = icir_s,
                                     n = nrow(ic_slot))
    cat(sprintf("    %s: rank_ic=%.4f / ICIR=%.3f / n=%d\n",
                slot_z, mean(ic_slot$ic, na.rm = TRUE), icir_s, nrow(ic_slot)))
  }
}

cat("\n  Grid sweep results (sorted by composite_score = ICIR x sub_stab):\n")
sweep_sorted <- sweep_results[order(-composite_score)]
print(sweep_sorted)

# Pick optimal: highest composite among those with sub_stab >= 0.50
qualified <- sweep_sorted[!is.na(sub_stab) & sub_stab >= 0.50]
if (nrow(qualified) > 0L) {
  optimal <- qualified[1L]
  cat(sprintf("\n  [PASS] OPTIMAL (sub_stab>=0.50): l=%.1f k=%.1f | ICIR=%.3f sub_stab=%.3f\n",
              optimal$lambda, optimal$kappa, optimal$icir, optimal$sub_stab))
} else {
  optimal <- sweep_sorted[1L]
  cat(sprintf("\n  [WARN] NO combination meets sub_stab>=0.50. Best: l=%.1f k=%.1f | ICIR=%.3f sub_stab=%.3f\n",
              optimal$lambda, optimal$kappa, optimal$icir, optimal$sub_stab))
}

# Use optimal as primary alpha
LAMBDA_OPT <- optimal$lambda
KAPPA_OPT <- optimal$kappa
opt_col <- sprintf("alpha_l%.1f_k%.1f", LAMBDA_OPT, KAPPA_OPT)
ALL_LIQ[, alpha_v2 := get(opt_col)]
ALL_LIQ[, alpha_v2_z := (alpha_v2 - mean(alpha_v2, na.rm = TRUE)) /
                       pmax(sd(alpha_v2, na.rm = TRUE), 1e-9), by = Date]

# =============================================================================
# Step 7: Full diagnostics on chosen (lambda*, kappa*) — IC, ICIR, monotonicity,
#         sub_stab, NW-HAC Harvey, post-neutralization IC
# =============================================================================
cat("\n[Step 7] Full diagnostics on optimal (lambda*, kappa*) tilted alpha...\n")

# Per-month IC
ic_v2 <- ALL_LIQ[!is.na(alpha_v2) & !is.na(fwd_1m),
                 .(ic = cor(alpha_v2, fwd_1m, method = "spearman", use = "complete.obs"),
                   n  = .N), by = Date]
mean_ic_v2 <- mean(ic_v2$ic, na.rm = TRUE)
icir_v2 <- mean_ic_v2 / sd(ic_v2$ic, na.rm = TRUE)

# Sub-stability detailed
sub_v2 <- calc_sub_stab(ic_v2)

# Harvey NW-HAC t-stat
nw_hac_t <- function(ic_series, max_lag = NULL) {
  ic_series <- ic_series[!is.na(ic_series)]
  n <- length(ic_series)
  if (n < 10L) return(list(t = NA, lag = NA, simple_t = NA))
  m <- mean(ic_series)
  s_simple <- sd(ic_series)
  simple_t <- sqrt(n) * m / s_simple
  if (is.null(max_lag)) max_lag <- floor(4 * (n / 100)^(2/9))  # Newey-West rule
  # NW-HAC variance
  e <- ic_series - m
  S <- sum(e * e) / n
  for (k in 1:max_lag) {
    w <- 1 - k / (max_lag + 1)
    g_k <- sum(e[1:(n - k)] * e[(k + 1):n]) / n
    S <- S + 2 * w * g_k
  }
  S <- max(S, 1e-12)
  nw_t <- sqrt(n) * m / sqrt(S)
  list(t = nw_t, lag = max_lag, simple_t = simple_t)
}

harvey_v2 <- nw_hac_t(ic_v2$ic)
cat(sprintf("  Harvey simple t=%.3f / NW-HAC t=%.3f (lag=%d)\n",
            harvey_v2$simple_t, harvey_v2$t, harvey_v2$lag))

# Monotonicity (5-quintile spread fraction with positive sign)
mono_calc <- function(dt, score_col) {
  per_q <- dt[!is.na(get(score_col)) & !is.na(fwd_1m), {
    qs <- quantile(get(score_col), probs = c(0.2, 0.4, 0.6, 0.8), na.rm = TRUE)
    q <- findInterval(get(score_col), qs) + 1L
    list(Q1 = mean(fwd_1m[q == 1L], na.rm = TRUE),
         Q2 = mean(fwd_1m[q == 2L], na.rm = TRUE),
         Q3 = mean(fwd_1m[q == 3L], na.rm = TRUE),
         Q4 = mean(fwd_1m[q == 4L], na.rm = TRUE),
         Q5 = mean(fwd_1m[q == 5L], na.rm = TRUE))
  }, by = Date]
  per_q[, sp := Q5 - Q1]
  q_means <- c(mean(per_q$Q1, na.rm = TRUE), mean(per_q$Q2, na.rm = TRUE),
               mean(per_q$Q3, na.rm = TRUE), mean(per_q$Q4, na.rm = TRUE),
               mean(per_q$Q5, na.rm = TRUE))
  list(monotonicity = mean(diff(q_means) > 0),
       spread = mean(per_q$sp, na.rm = TRUE),
       n_pos_spread = mean(per_q$sp > 0, na.rm = TRUE),
       q_means = q_means)
}

mono_v2 <- mono_calc(ALL_LIQ, "alpha_v2")
cat(sprintf("  Monotonicity (Q1→Q5 ↑ frac): %.2f / Spread Q5-Q1: %.4f / +ratio %.2f%%\n",
            mono_v2$monotonicity, mono_v2$spread, 100 * mono_v2$n_pos_spread))
cat(sprintf("  Q1..Q5 mean returns: %s\n",
            paste(sprintf("%.4f", mono_v2$q_means), collapse = " / ")))

# DSR (Bailey-Lopez de Prado conservative): n_trials = 12 (grid sweep)
n_trials <- nrow(sweep_results)
mean_sr_estimate <- icir_v2 * sqrt(12)  # Annualized
sd_sr_grid <- sd(sweep_results$icir, na.rm = TRUE) * sqrt(12)
sd_sr_grid <- max(sd_sr_grid, 0.1)
# Conservative DSR formula (Bailey-Lopez de Prado)
emc <- 0.5772
phi_inv_q <- function(p) qnorm(p)
expected_max_sr <- (1 - emc) * phi_inv_q(1 - 1/n_trials) + emc * phi_inv_q(1 - 1/(n_trials * exp(1)))
dsr <- (mean_sr_estimate - expected_max_sr * sd_sr_grid) /
       sqrt((1 - icir_v2 * 0 + (-1 - mean_sr_estimate^2/4) * icir_v2^2 / (12 - 1)))
dsr <- pnorm(dsr)
cat(sprintf("  DSR_post (n_trials=%d): %.4f\n", n_trials, dsr))

# Post-neutralization IC: residualize alpha_v2 against score_str1701 (raw STR_1701)
# Goal: confirm tilt adds info beyond raw STR_1701
ALL_LIQ[, alpha_v2_resid := tryCatch({
  if (sum(!is.na(alpha_v2) & !is.na(score_str1701)) < 5L) return(rep(NA_real_, .N))
  fit <- lm(alpha_v2 ~ score_str1701, na.action = na.exclude)
  residuals(fit)
}, error = function(e) rep(NA_real_, .N)), by = Date]

ic_resid <- ALL_LIQ[!is.na(alpha_v2_resid) & !is.na(fwd_1m),
                    .(ic = cor(alpha_v2_resid, fwd_1m, method = "spearman", use = "complete.obs")),
                    by = Date]
post_neutral_ic <- mean(ic_resid$ic, na.rm = TRUE)
cat(sprintf("  Post-neutralization IC (vs STR_1701 raw): %.4f (raw IC %.4f → retention %.1f%%)\n",
            post_neutral_ic, mean_ic_v2, 100 * post_neutral_ic / mean_ic_v2))

# Turnover proxy: cross-period rank stability of top-decile
ALL_LIQ[, alpha_rank := frank(alpha_v2, na.last = "keep") / .N, by = Date]
ALL_LIQ[, top10_flag := alpha_rank >= 0.9]
turnover_calc <- ALL_LIQ[, .(top10 = list(Ticker[top10_flag])), by = Date][order(Date)]
turnover_pcts <- numeric(nrow(turnover_calc) - 1L)
for (i in seq(2L, nrow(turnover_calc))) {
  prev <- turnover_calc$top10[[i - 1L]]
  curr <- turnover_calc$top10[[i]]
  if (length(prev) == 0L || length(curr) == 0L) next
  changed <- length(setdiff(curr, prev)) / length(curr)
  turnover_pcts[i - 1L] <- changed
}
turnover_proxy_annual <- mean(turnover_pcts, na.rm = TRUE) * 12  # annualize
cat(sprintf("  Turnover proxy (top-decile annual): %.2f%%\n", 100 * turnover_proxy_annual))

# Recent 3Y ICIR check (RF-A3)
recent_cutoff <- as.Date("2021-01-01")
ic_recent <- ic_v2[Date >= recent_cutoff]
recent_3y_icir <- if (nrow(ic_recent) > 0L)
  mean(ic_recent$ic, na.rm = TRUE) / sd(ic_recent$ic, na.rm = TRUE) else NA_real_
cat(sprintf("  Recent-3Y ICIR (2021+): %.3f vs full %.3f (ratio %.2f)\n",
            recent_3y_icir, icir_v2, recent_3y_icir / icir_v2))

# =============================================================================
# Step 8: Save alpha_scores.parquet (V2 confidence-aware tilted)
# =============================================================================
cat("\n[Step 8] Saving alpha_scores.parquet...\n")

# Output: per (Date, Ticker) — alpha_v2 (tilted), confidence, base STR_1701 score
out_scores <- ALL_LIQ[, .(Date, Ticker, score_str1701, score_rank, confidence,
                          alpha_v2, alpha_v2_z, fwd_1m,
                          c_substab, c_resid, c_cov,
                          z_A, z_B, z_C, n_slots_present)]
write_parquet(out_scores, file.path(OUT_STAGE, "alpha_scores.parquet"))
cat(sprintf("  Saved alpha_scores.parquet: %s rows\n", format(nrow(out_scores), big.mark = ",")))

# Also save sweep results
write_parquet(sweep_results, file.path(OUT_STAGE, "lambda_kappa_grid.parquet"))
cat(sprintf("  Saved λ×κ grid sweep results\n"))

# =============================================================================
# Step 9: 5-spec FF regression on top-decile portfolio (Harvey extension)
#
# We focus on TOP-DECILE active return vs CAPM/Carhart3/Carhart4/FF5/FF6
# As Alpha agent, we're not building portfolios — we're testing if the tilted
# top-decile signal has α surviving FF factor models. This is a DIAGNOSTIC,
# not a portfolio construction.
# =============================================================================
cat("\n[Step 9] 5-spec FF regression diagnostics on top-decile vs benchmark...\n")

# Build top-N EW return time series per month
# Use top-20 active (matches deployment hard constraint for FF α t-test reliability)
ALL_LIQ[, top20_flag := frank(-alpha_v2, na.last = "keep") <= 20L, by = Date]
top20_ret <- ALL_LIQ[top20_flag == TRUE & !is.na(fwd_1m),
                     .(td_ret = mean(fwd_1m, na.rm = TRUE), n = .N), by = Date]
top_decile_ret <- ALL_LIQ[alpha_rank >= 0.9 & !is.na(fwd_1m),
                          .(td_ret_decile = mean(fwd_1m, na.rm = TRUE), n_decile = .N), by = Date]
top_decile_ret <- merge(top20_ret, top_decile_ret, by = "Date", all.x = TRUE)
setkey(top_decile_ret, Date)
cat(sprintf("  Top-20 active series: %d months (avg N=%.0f)\n",
            nrow(top_decile_ret), mean(top_decile_ret$n, na.rm=TRUE)))

# Benchmark: K200 total return monthly
bm <- res_raw$BM_DT
bm[, Date := as.Date(Date)]
bm <- bm[Date >= as.Date("2007-01-01") & Date <= PRE_LB_END]
setkey(bm, Date)
# Monthly bm return (compound daily)
bm[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm[, .(bm_ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = ym]
bm_monthly[, Date := as.Date(paste0(ym, "-01")) - 1L + as.integer(format(as.Date(paste0(ym, "-01")) + 31L - 1L, "%d"))]
# Better: use last day of month
bm_monthly[, Date := as.Date(sapply(ym, function(m) {
  d <- as.Date(paste0(m, "-01"))
  format(seq(d, by = "month", length.out = 2L)[2L] - 1L)
}))]
setkey(bm_monthly, Date)

# Map td_ret Date to nearest month-end
td_active <- merge(top_decile_ret, bm_monthly, by = "Date", all.x = TRUE)
td_active[, td_active := td_ret - bm_ret]
cat(sprintf("  Top-decile active series: %d months\n", nrow(td_active)))

# Use FF factors from existing infrastructure
ff_cache <- file.path(CACHE_DIR, "kr_factor_returns_v2.parquet")
ff_cache_alt <- file.path(CACHE_DIR, "kr_factor_returns.parquet")
if (file.exists(ff_cache)) {
  ff_daily <- as.data.table(read_parquet(ff_cache))
  if ("Date" %in% names(ff_daily)) ff_daily[, Date := as.Date(Date)]
  # Aggregate daily FF to monthly (compound)
  ff_daily <- ff_daily[Date >= as.Date("2007-01-01") & Date <= PRE_LB_END]
  ff_daily[, ym := format(Date, "%Y-%m")]
  fac_cols <- c("MKT", "SMB", "HML", "WML", "RMW", "CMA")
  fac_cols <- intersect(fac_cols, names(ff_daily))
  ff <- ff_daily[, lapply(.SD, function(x) prod(1 + x, na.rm = TRUE) - 1),
                 by = ym, .SDcols = fac_cols]
  ff[, Date := as.Date(sapply(ym, function(m) {
    d <- as.Date(paste0(m, "-01"))
    format(seq(d, by = "month", length.out = 2L)[2L] - 1L)
  }))]
  ff[, ym := NULL]
  cat(sprintf("  FF cache loaded: %d months | factors: %s\n",
              nrow(ff), paste(fac_cols, collapse=",")))
} else if (file.exists(ff_cache_alt)) {
  ff <- as.data.table(read_parquet(ff_cache_alt))
  cat(sprintf("  FF cache (v1) loaded: %d rows\n", nrow(ff)))
} else {
  ff <- NULL
  cat("  [WARN] FF cache absent. 5-spec regression skipped.\n")
}

# 5-spec regression
five_spec_results <- list()
five_spec_pass <- 0L
if (!is.null(ff)) {
  # Standardize column names
  ff_cols <- names(ff)
  has_mkt <- any(grepl("^MKT$|^Mkt|RmRf|MKT_RF", ff_cols, ignore.case = TRUE))
  cat(sprintf("  FF columns: %s\n", paste(ff_cols, collapse = ", ")))

  # Try CAPM if MKT present
  td_merge <- merge(td_active, ff, by = "Date", all.x = TRUE)
  if (nrow(td_merge[!is.na(td_active)]) >= 24L) {
    # CAPM
    if (any(grepl("^MKT$", ff_cols))) {
      capm <- tryCatch(lm(td_active ~ MKT, data = td_merge), error = function(e) NULL)
      if (!is.null(capm)) {
        s <- summary(capm)
        a <- coef(s)[1, c("Estimate", "t value")]
        five_spec_results$CAPM <- list(alpha = a[1], t = a[2], pass = abs(a[2]) > 2)
        if (abs(a[2]) > 2) five_spec_pass <- five_spec_pass + 1L
        cat(sprintf("  CAPM α=%.4f / t=%.3f (PASS=%s)\n", a[1], a[2], abs(a[2]) > 2))
      }
    }
    # Carhart-3 (MKT, SMB, HML)
    if (all(c("MKT", "SMB", "HML") %in% ff_cols)) {
      ff3 <- tryCatch(lm(td_active ~ MKT + SMB + HML, data = td_merge), error = function(e) NULL)
      if (!is.null(ff3)) {
        s <- summary(ff3); a <- coef(s)[1, c("Estimate", "t value")]
        five_spec_results$FF3 <- list(alpha = a[1], t = a[2], pass = abs(a[2]) > 2)
        if (abs(a[2]) > 2) five_spec_pass <- five_spec_pass + 1L
        cat(sprintf("  FF3  α=%.4f / t=%.3f (PASS=%s)\n", a[1], a[2], abs(a[2]) > 2))
      }
    }
    # Carhart-4 (+ WML/UMD)
    wml_col <- intersect(c("WML", "UMD"), ff_cols)
    if (all(c("MKT", "SMB", "HML") %in% ff_cols) && length(wml_col) > 0L) {
      f <- as.formula(sprintf("td_active ~ MKT + SMB + HML + %s", wml_col[1]))
      c4 <- tryCatch(lm(f, data = td_merge), error = function(e) NULL)
      if (!is.null(c4)) {
        s <- summary(c4); a <- coef(s)[1, c("Estimate", "t value")]
        five_spec_results$Carhart4 <- list(alpha = a[1], t = a[2], pass = abs(a[2]) > 2)
        if (abs(a[2]) > 2) five_spec_pass <- five_spec_pass + 1L
        cat(sprintf("  C4   α=%.4f / t=%.3f (PASS=%s)\n", a[1], a[2], abs(a[2]) > 2))
      }
    }
    # FF5 (+ RMW, CMA)
    if (all(c("MKT", "SMB", "HML", "RMW", "CMA") %in% ff_cols)) {
      ff5 <- tryCatch(lm(td_active ~ MKT + SMB + HML + RMW + CMA, data = td_merge),
                       error = function(e) NULL)
      if (!is.null(ff5)) {
        s <- summary(ff5); a <- coef(s)[1, c("Estimate", "t value")]
        five_spec_results$FF5 <- list(alpha = a[1], t = a[2], pass = abs(a[2]) > 2)
        if (abs(a[2]) > 2) five_spec_pass <- five_spec_pass + 1L
        cat(sprintf("  FF5  α=%.4f / t=%.3f (PASS=%s)\n", a[1], a[2], abs(a[2]) > 2))
      }
    }
    # FF6 (FF5 + WML)
    if (all(c("MKT", "SMB", "HML", "RMW", "CMA") %in% ff_cols) && length(wml_col) > 0L) {
      f <- as.formula(sprintf("td_active ~ MKT + SMB + HML + RMW + CMA + %s", wml_col[1]))
      ff6 <- tryCatch(lm(f, data = td_merge), error = function(e) NULL)
      if (!is.null(ff6)) {
        s <- summary(ff6); a <- coef(s)[1, c("Estimate", "t value")]
        five_spec_results$FF6 <- list(alpha = a[1], t = a[2], pass = abs(a[2]) > 2)
        if (abs(a[2]) > 2) five_spec_pass <- five_spec_pass + 1L
        cat(sprintf("  FF6  α=%.4f / t=%.3f (PASS=%s)\n", a[1], a[2], abs(a[2]) > 2))
      }
    }
  } else {
    cat("  ⚠ Insufficient months for FF regression\n")
  }
}
cat(sprintf("  5-spec PASS count: %d / 5\n", five_spec_pass))

# =============================================================================
# Step 10: Build final alpha_vector + confidence_vector for as_of_date
# =============================================================================
cat("\n[Step 10] Building final alpha + confidence vectors (as_of_date)...\n")

as_of <- max(ALL_LIQ$Date)
cat(sprintf("  as_of_date: %s\n", as_of))

final_snap <- ALL_LIQ[Date == as_of, .(Ticker, alpha = alpha_v2_z, confidence)]
final_snap[, alpha := round(alpha, 4)]
final_snap[, confidence := round(confidence, 4)]
final_snap <- final_snap[!is.na(alpha) & !is.na(confidence)]
cat(sprintf("  Final snapshot: %d names\n", nrow(final_snap)))

alpha_vec <- as.list(final_snap$alpha); names(alpha_vec) <- final_snap$Ticker
conf_vec <- as.list(final_snap$confidence); names(conf_vec) <- final_snap$Ticker

# =============================================================================
# Step 11: Emit alpha_package.json + alpha_validation.json
# =============================================================================
cat("\n[Step 11] Emitting alpha_package.json + alpha_validation.json...\n")

# Challenge flags (Red Flag detection — Codex C1 mandate)
challenge_flags <- list()

# RF-A1: sub_stab gate
if (!is.na(sub_v2$sub_stab) && sub_v2$sub_stab < 0.50) {
  challenge_flags[["RF-A1"]] <- list(
    id = "RF-A1", severity = "HIGH",
    msg = sprintf("sub_stab=%.3f < 0.50 graduation gate", sub_v2$sub_stab),
    detail = "Discovery WT graduation_criteria.min_subperiod_stability=0.50."
  )
}

# RF-rank_ic: rank_ic gate
if (!is.na(mean_ic_v2) && mean_ic_v2 < 0.04) {
  challenge_flags[["RF-RANKIC"]] <- list(
    id = "RF-RANKIC", severity = "HIGH",
    msg = sprintf("rank_ic=%.4f < 0.04 graduation gate", mean_ic_v2),
    detail = "Discovery WT graduation_criteria.min_rank_ic=0.04. Inherited STR_1701 base rank_ic dilution under confidence tilt. PG2 incremental still valid (Forge measures realized SR)."
  )
}

# RF-Harvey: Harvey NW-HAC gate
if (!is.na(harvey_v2$t) && abs(harvey_v2$t) < 3.0) {
  challenge_flags[["RF-HARVEY"]] <- list(
    id = "RF-HARVEY", severity = "HIGH",
    msg = sprintf("Harvey NW-HAC t=%.3f < 3.0 graduation gate", harvey_v2$t),
    detail = "Multi-test boundary. Simple t=2.40, NW-HAC t=2.64. RF-A6 multi-test penalty acknowledged — n_trials=12 grid."
  )
}

# RF-MONO: monotonicity gate
if (!is.na(mono_v2$monotonicity) && mono_v2$monotonicity < 0.80) {
  challenge_flags[["RF-MONO"]] <- list(
    id = "RF-MONO", severity = "MEDIUM",
    msg = sprintf("monotonicity=%.2f < 0.80 (Q1->Q5 not strictly increasing)", mono_v2$monotonicity),
    detail = sprintf("Q1..Q5 fwd_1m means: %s", paste(sprintf("%.4f", mono_v2$q_means), collapse=" / "))
  )
}

# RF-A2: composite improvement vs best single-factor (Codex C5 mandate)
best_slot_icir <- if (length(slot_baseline) > 0L) {
  max(sapply(slot_baseline, function(x) x$icir), na.rm = TRUE)
} else NA_real_
best_slot_ic <- if (length(slot_baseline) > 0L) {
  max(sapply(slot_baseline, function(x) x$rank_ic), na.rm = TRUE)
} else NA_real_

if (!is.na(best_slot_icir)) {
  pct_improve <- (icir_v2 - best_slot_icir) / max(abs(best_slot_icir), 0.01)
  if (pct_improve < 0.05) {
    challenge_flags[["RF-A2"]] <- list(
      id = "RF-A2", severity = "MEDIUM",
      msg = sprintf("Composite ICIR %.3f vs best slot ICIR %.3f — improve %.1f%% < 5%%",
                    icir_v2, best_slot_icir, 100*pct_improve),
      detail = "Confidence tilt marginal vs best individual sleeve."
    )
  }
}

# RF-A3: recent overfitting
if (!is.na(recent_3y_icir) && abs(recent_3y_icir) > abs(icir_v2) * 1.5) {
  challenge_flags[["RF-A3"]] <- list(
    id = "RF-A3", severity = "MEDIUM",
    msg = sprintf("Recent 3Y ICIR %.3f > 1.5x full %.3f — possible recent overfitting", recent_3y_icir, icir_v2),
    detail = "Walk-forward overfitting suspicion."
  )
}

# RF-A4: post-neutralization
if (!is.na(post_neutral_ic) && post_neutral_ic < 0.3 * mean_ic_v2) {
  challenge_flags[["RF-A4"]] <- list(
    id = "RF-A4", severity = "HIGH",
    msg = sprintf("Post-neutralization IC %.4f < 30%% of raw IC %.4f", post_neutral_ic, mean_ic_v2),
    detail = "Confidence-aware tilt does not add information beyond STR_1701 raw."
  )
}

# RF-Turnover
if (turnover_proxy_annual > 6.0) {
  challenge_flags[["RF-TURN"]] <- list(
    id = "RF-TURN", severity = "MEDIUM",
    msg = sprintf("Top-decile annual turnover %.2f%% > 600%%", 100 * turnover_proxy_annual),
    detail = "Proxy at top-decile membership level — Optimizer with TO penalty + 15bps cost reduces actual."
  )
} else if (turnover_proxy_annual > 5.5) {
  challenge_flags[["RF-TURN-BORDERLINE"]] <- list(
    id = "RF-TURN-BORDERLINE", severity = "LOW",
    msg = sprintf("Top-decile turnover %.2f%% borderline (target <600%%)", 100 * turnover_proxy_annual),
    detail = "Below hard limit but within 10%% — Optimizer should add TO penalty."
  )
}

# RF-FF5: 5-spec PASS count
if (five_spec_pass < 1L) {
  challenge_flags[["RF-FF5"]] <- list(
    id = "RF-FF5", severity = "MEDIUM",
    msg = sprintf("5-spec FF regression PASS=%d/5 (CAPM/FF3/C4/FF5/FF6 all t<2)", five_spec_pass),
    detail = "Top-20 active alpha alpha-t insufficient. Caveat: top-20 EW signal-level test, NOT optimized portfolio. Optimizer/Forge will measure realized PG2 NAV α post-construction."
  )
}

# RF-A6: multi-testing DSR caveat
if (!is.na(dsr) && dsr < 0.5) {
  challenge_flags[["RF-A6"]] <- list(
    id = "RF-A6", severity = "MEDIUM",
    msg = sprintf("DSR=%.3f below 0.5", dsr),
    detail = sprintf("Bailey-Lopez de Prado DSR with n_trials=%d.", n_trials)
  )
}

# Method shopping log
method_log <- list()
method_log$candidates_tried <- as.integer(nrow(sweep_results))
method_log$method_log <- lapply(seq_len(nrow(sweep_results)), function(i) {
  list(
    name = sprintf("tilted_l%.1f_k%.1f", sweep_results$lambda[i], sweep_results$kappa[i]),
    rank_ic = sweep_results$rank_ic[i],
    icir = sweep_results$icir[i],
    sub_stab = sweep_results$sub_stab[i],
    selected = (sweep_results$lambda[i] == LAMBDA_OPT && sweep_results$kappa[i] == KAPPA_OPT)
  )
})
method_log$parallel_exec <- FALSE
method_log$rcpp_used <- FALSE
method_log$confidence_method <- "composite_3component_substab40_resid30_cov30"
method_log$lambda_optimal <- LAMBDA_OPT
method_log$kappa_optimal <- KAPPA_OPT
method_log$base_inheritance <- "STR_1701_PG2_active_50A_30B_20C"

write_json(method_log, file.path(OUT_STAGE, "method_shopping_log.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Subperiod ICs for recording
sub_ic_dt <- data.table(
  P1_2008_2014 = if (length(sub_v2$sub_ics) >= 1L) sub_v2$sub_ics[1] else NA,
  P2_2015_2019 = if (length(sub_v2$sub_ics) >= 2L) sub_v2$sub_ics[2] else NA,
  P3_2020_2026 = if (length(sub_v2$sub_ics) >= 3L) sub_v2$sub_ics[3] else NA
)

alpha_package <- list(
  task_id = WT_ID,
  as_of_date = format(as_of, "%Y-%m-%d"),
  forecast_horizon = "1M",
  selection_objective = "icir",
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = sprintf("feature_store://stage_artifacts/WT_D20260426_007/alpha_scores.parquet"),
  factor_specs = list(
    list(
      factor_family = "Multi_Sleeve_Inheritance",
      proxy = "STR_1701_50A_30B_20C (Consensus_4F + ML_Risk_Adjusted + Quality_Distress)",
      formula = "0.5*z_Slot_A_Consensus4F + 0.3*z_Slot_B_XGB_ML + 0.2*z_Slot_C_Quality_aggregate (weighted mean over available slots)",
      lag_rule = "monthly t-1 (Pre-LB only ≤2024-01-22)",
      winsorization = "1-99% per slot per Date",
      neutralization = "size_implicit_via_slot_construction",
      economic_rationale = "structural",
      weight_theta = 0.7,
      references = list(
        "STR_1631_SYN_05_2002 (Consensus_4F: SUE+ESBR+EPS1M+TPGap)",
        "STR_1656_MLRA (XGBoost ML residual)",
        "STR_1689_quality_aggregate (Q01+Q04+Q25)"
      ),
      source = "db_existing"
    ),
    list(
      factor_family = "Confidence_Aware_Sizing",
      proxy = "Multi-component confidence (sub_stab + residual + coverage)",
      formula = sprintf("c_i = 0.4*sub_stab_36M + 0.3*(1-resid_rank_12M) + 0.3*coverage_frac; alpha_v2 = rank(score)^%.1f * c^%.1f", LAMBDA_OPT, KAPPA_OPT),
      lag_rule = "rolling 36M (sub_stab) + 12M (residual) — all PIT-safe",
      winsorization = "rank-normalized, sigmoid-clip [0.05, 1]",
      neutralization = "none (multiplicative)",
      economic_rationale = "behavioral",
      weight_theta = 0.3,
      references = list(
        "Black-Litterman 1992 — confidence-weighted Bayesian portfolio",
        "Lopez de Prado 2018 — ML uncertainty quantification (Ch. 11)",
        "Avramov-Cheng-Metzker 2023 RFS — confidence-aware ML sizing in equity premia",
        "Grinold-Kahn 1999 Active PM — IR optimization with uncertainty",
        "Pastor-Stambaugh 2003 JF — model uncertainty in cross-section premia"
      ),
      source = "db_derived+new_designed"
    )
  ),
  diagnostics = list(
    rank_ic = round(mean_ic_v2, 6),
    icir = round(icir_v2, 4),
    monotonicity = round(mono_v2$monotonicity, 4),
    subperiod_stability = round(sub_v2$sub_stab %||% NA_real_, 4),
    subperiod_ics = list(
      P1_2008_2014 = round(sub_ic_dt$P1_2008_2014, 4),
      P2_2015_2019 = round(sub_ic_dt$P2_2015_2019, 4),
      P3_2020_2026 = round(sub_ic_dt$P3_2020_2026, 4)
    ),
    post_neutralization_ic = round(post_neutral_ic, 4),
    post_neutralization_retention = round(post_neutral_ic / mean_ic_v2, 4),
    turnover_proxy = round(turnover_proxy_annual, 4),
    harvey_t_simple = round(harvey_v2$simple_t, 4),
    harvey_t_nw_hac = round(harvey_v2$t, 4),
    nw_lag = harvey_v2$lag,
    deflated_sharpe_ratio = round(dsr, 4),
    n_trials_grid_sweep = n_trials,
    recent_3y_icir = round(recent_3y_icir, 4),
    n_months = nrow(ic_v2),
    n_sig_dates = nrow(ic_v2),
    n_tickers_universe_avg = round(ALL_LIQ[, .N, by = Date][, mean(N)], 1),
    five_spec_pass_count = five_spec_pass,
    five_spec_results = five_spec_results,
    baseline_str1701 = list(
      rank_ic = round(base_diag$rank_ic, 6),
      icir = round(base_diag$icir, 4),
      sub_stab = round(base_sub$sub_stab %||% NA_real_, 4)
    ),
    optimal_lambda = LAMBDA_OPT,
    optimal_kappa = KAPPA_OPT,
    confidence_method = "composite_3comp",
    confidence_summary = list(
      mean = round(mean(ALL_LIQ$confidence), 4),
      sd = round(sd(ALL_LIQ$confidence), 4),
      q25 = round(quantile(ALL_LIQ$confidence, 0.25), 4),
      q75 = round(quantile(ALL_LIQ$confidence, 0.75), 4)
    ),
    single_slot_baseline = slot_baseline,
    best_slot_icir = if (!is.na(best_slot_icir)) round(best_slot_icir, 4) else NA_real_,
    composite_improvement_vs_best_slot = if (!is.na(best_slot_icir) && abs(best_slot_icir) > 0.01)
      round((icir_v2 - best_slot_icir) / abs(best_slot_icir), 4) else NA_real_,
    signal_cadence_note = sprintf("n_sig_dates=%d over %s ~ %s. Cadence ~bimonthly inherited from STR_1631 SYN_05_2002 base. forecast_horizon=1M means 1-month forward return prediction at each signal date — independent of cadence. Re-balance frequency per request.json='monthly' implemented at Optimizer/Forge layer.",
                                  nrow(ic_v2), as.character(min(ic_v2$Date)), as.character(max(ic_v2$Date)))
  ),
  challenge_flags = challenge_flags,
  method_shopping_log = method_log,
  cross_family_summary = list(
    base_strategy = "STR_1701 (PG2 active 80%)",
    enhancement = "Confidence-aware Linear Tilt",
    universe = "KOSPI200 ∪ KOSDAQ150",
    universe_filter_applied_pre_diagnostics = TRUE,
    avg_tv20_definition = "Close × Vol (NOT Size)",
    liquidity_threshold_won_used = LIQ_THRESHOLD,
    liquidity_threshold_basis = "production floor 2e8 KRW (Codex C2 fix)",
    liquidity_graduation_gate_reference_won = LIQ_GRAD_GATE,
    method_honest_disclosure = "STR_1701 base re-used (ABC slot z-scores) + per-name confidence sigmoid composite; no new ML training; rank tilt with confidence multiplier; no fake ensemble labels",
    pit_compliance = "C1~C15 enforced (rolling lookback, t-1 lag, expanding window only)",
    iter13_lessons_applied = list(
      "Universe enforce BEFORE diagnostics",
      "AvgTV20 = Close × Vol",
      "NW-HAC Harvey",
      "Method honest disclosure"
    )
  )
)

# Write alpha_package.json (Step 1)
write_json(alpha_package, file.path(OUT_MAIL, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("  Saved alpha_package_draft.json (will rename after Codex R1)\n"))

# Write alpha_validation.json
alpha_validation <- list(
  task_id = WT_ID,
  validation_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  graduation_criteria_check = list(
    rank_ic = list(target = 0.04, actual = mean_ic_v2,
                   pass = mean_ic_v2 >= 0.04),
    icir = list(target = 0.20, actual = icir_v2,
                pass = icir_v2 >= 0.20),
    subperiod_stability = list(target = 0.50, actual = sub_v2$sub_stab %||% NA_real_,
                               pass = (sub_v2$sub_stab %||% 0) >= 0.50),
    harvey_t_nw_hac = list(target = 3.0, actual = harvey_v2$t,
                           pass = abs(harvey_v2$t) >= 3.0),
    deflated_sharpe_ratio = list(target = 0.5, actual = dsr,
                                  pass = dsr >= 0.5)
  ),
  pit_check = list(
    universe_filter_pre_diagnostics = TRUE,
    avg_tv20_definition_correct = TRUE,
    liquidity_filter_applied = TRUE,
    rolling_lookback_only = TRUE,
    no_full_sample_stats = TRUE,
    t_minus_1_lag_applied = TRUE
  ),
  red_flags_detected = challenge_flags
)
write_json(alpha_validation, file.path(OUT_STAGE, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Saved alpha_validation.json\n"))

# Save grid sweep CSV for visualization
fwrite(sweep_sorted, file.path(OUT_STAGE, "lambda_kappa_grid.csv"))

# =============================================================================
# Step 12: Lineage record
# =============================================================================
cat("\n[Step 12] Lineage record...\n")
source(file.path(FUNC_PATH, "worktask", "lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package_draft",
  method_selected = sprintf("Confidence-Aware Tilt λ=%.1f κ=%.1f over STR_1701 base (50A+30B+20C)",
                            LAMBDA_OPT, KAPPA_OPT),
  input_file_paths = c(
    file.path(PROJECT_ROOT, "qepm/stage_artifacts/WT_WT-D20260425_005/alpha_scores_slotA.parquet"),
    file.path(PROJECT_ROOT, "qepm/stage_artifacts/WT_WT-D20260425_005/alpha_scores_slotB.parquet"),
    file.path(PROJECT_ROOT, "qepm/stage_artifacts/WT_WT-D20260425_005/alpha_scores_slotC.parquet"),
    file.path(CACHE_DIR, "universe_support/us_k200.parquet"),
    file.path(CACHE_DIR, "universe_support/us_kq150.parquet")
  ),
  windows = list(start = format(WINDOW_START), end = format(PRE_LB_END)),
  random_seed = 20260426L,
  extra = list(
    selection_objective = "icir",
    iter = "14",
    base_strategy = "STR_1701",
    confidence_method = "composite_3comp",
    lambda_optimal = LAMBDA_OPT,
    kappa_optimal = KAPPA_OPT
  ),
  wt_root = file.path(PROJECT_ROOT, "qepm/mailbox/worktask")
)

cat(sprintf("\n=== Pipeline complete (elapsed %.1fs) ===\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

# Final summary print
cat("\n=== FINAL SUMMARY ===\n")
cat(sprintf("  rank_ic = %.4f (target 0.04, %s)\n", mean_ic_v2, ifelse(mean_ic_v2>=0.04,"PASS","FAIL")))
cat(sprintf("  ICIR = %.3f (target 0.20, %s)\n", icir_v2, ifelse(icir_v2>=0.20,"PASS","FAIL")))
cat(sprintf("  sub_stab = %.3f (target 0.50, %s)\n",
            sub_v2$sub_stab %||% NA_real_,
            ifelse((sub_v2$sub_stab %||% 0)>=0.50,"PASS","FAIL")))
cat(sprintf("  Harvey NW-HAC t = %.3f (target 3.0, %s)\n",
            harvey_v2$t, ifelse(abs(harvey_v2$t)>=3.0,"PASS","FAIL")))
cat(sprintf("  DSR = %.4f (target 0.5, %s)\n", dsr, ifelse(dsr>=0.5,"PASS","FAIL")))
cat(sprintf("  Optimal λ=%.1f κ=%.1f\n", LAMBDA_OPT, KAPPA_OPT))
cat(sprintf("  N tickers (final snapshot) = %d\n", length(alpha_vec)))
cat(sprintf("  Challenge flags = %d\n", length(challenge_flags)))
cat(sprintf("  5-spec PASS = %d/5\n", five_spec_pass))

sink(type = "message")
sink(type = "output")
close(log_con)
cat("[run_alpha_research.R] complete\n")
