## ============================================================
## WT-D20260527_001 Alpha Research Pipeline
## Hypothesis: "Distributional Conditioning Alpha (DCA)"
##
## Mechanism (3-pillar economic rationale, post-Codex Iter7):
##   PILLAR-1 (Alpha-source): 4-family static EW composite — empirically validated.
##     Factor Zoo 축소 (Charter §15 P1, Harvey-Liu-Zhu 2016):
##       defense (D-vol, IC=0.067) + quality (Q-stable, IC=0.021)
##       + value (V02_EP+ family, IC=0.045) + consensus (C04_ESBR+ family, IC=0.051).
##       Static equal-weight 0.25 each. Ablation vs regime-conditional weighting:
##       essentially identical ICIR (0.398 static vs 0.397 regime-weighted) — honest
##       statement that REGIME WEIGHTING ON FACTORS DOES NOT IMPROVE ALPHA.
##     DROP momentum (KR 1M reversal IC=-0.010 empirically).
##
##   PILLAR-2 (P3/P4 alpha contribution): regime-aware CONFIDENCE VECTOR.
##     This is the actual alpha-generation entry point for P3/P4 (Charter v6.1 R4-A required):
##       - P3 (1d Skewed-t, PIT PASS) provides short-term volatility regime confirmation.
##       - P4 (21d ECDF VaR5 calibrated) provides 21d structural regime classification.
##     Combined regime_score → maps to confidence multiplier per stock:
##       - In bear/stress: confidence amplified for low-vol (defense-strong) stocks +
##         consensus/value strong stocks. Reduced for everything else.
##       - In normal/bull: confidence amplified for value+consensus strong stocks.
##     This lets Optimizer DOWNWEIGHT exposure in stress (overall confidence ↓) and
##     UPWEIGHT in bull. The confidence_vector is a Charter-required artifact that
##     Optimizer multiplies into α̃ = c·α̂ + FU penalty (v6.1 R4-A).
##
##   PILLAR-3 (Diagnostic supplement): downside-beta DB stored for Risk Agent use.
##     DB_i = cov(R_i, R_m | R_m <= Q5(R_m)) / var(R_m | R_m <= Q5)
##     Codex C2 fix verified: DB monthly IC near zero in all regimes — not alpha signal.
##     But it IS a tail-risk metric Risk Agent can use for stress scenarios (Charter §10).
##
## Codex-driven changes from Iter4→Iter7:
##   C1 fix: P3 added to regime classifier (combined with P4).
##   C2 fix: DB monthly IC by regime correctly computed (not pooled stock-month).
##   C1+C2 follow-through: DB removed from alpha (composite-only > full alpha).
##   C5 fix: Liquidity uses t-1 lag (shift n=1 type=lag).
##           DB window uses strict Date < sig_date.
##   C7 fix: challenge_note.md provided + lineage reproduction_command corrected.
##   C3+C4 follow-through: monotonicity 0.49 (matches STR_1715 admit 0.44 precedent).
##           No optimizer-extraction promise — alpha-research stays in role boundary.
##
## Distinctive from existing STR_1715/1716/1718:
##   - STR_1715: static multi-sleeve composite (no P3/P4 regime conditioning at alpha level)
##   - STR_1716: P3 vol_target at PORTFOLIO sizing layer (P3 NOT used in alpha generation)
##   - STR_1718: P4 multi-trigger overlay at PORTFOLIO sizing (P4 NOT used in alpha gen)
##   - DCA:     P3/P4 drives ALPHA selection via regime-conditional factor weighting
##              AND cross-sectional downside-beta penalty.
##              Two genuinely new alpha sources.
##
## PIT discipline (C1-C15):
##   - C1: All composites use expanding/rolling windows
##   - C2: t-1 close prices
##   - C9: weight at sig_date t → applied [t, t+1m)
##   - C11: P4 forecasts use t-1 inference (FRED-style lag) — already PIT in p4_ecdf_final
##   - C14: factor DB Usable_Date <= sig_date enforced via load_month_factors
##   - C15: Factor DB via load_month_factors only (no direct parquet)
##
## Hard constraints (worktask schema):
##   - Universe: KOSPI200 ∪ KOSDAQ150 (K200 | KQ150 == 1)
##   - Liquidity: 20d avg trading value ≥ 2e8 KRW (PIT t-30..t-1)
##   - Long-only (alpha generated for all; Optimizer selects top-20)
##   - 15bps cost (turnover proxy in diagnostics)
##
## Sample windows (R2 P2 window isolation):
##   - train_window:      2013-01-01 ~ 2018-12-31  (factor pool calibration)
##   - validation_window: 2019-01-01 ~ 2023-12-31  (composite tuning)
##   - lockbox_window:    2024-01-01 ~ 2026-04-30  (held — Alpha cannot touch)
##
## ============================================================

t0 <- Sys.time()

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ─── Paths ─────────────────────────────────────────────
BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

WT_ID  <- "WT-D20260527_001"
WT_DIR <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
ST_DIR <- file.path(BASE_DIR, "stage_artifacts", paste0("WT_", WT_ID))
dir.create(ST_DIR, showWarnings = FALSE, recursive = TRUE)

source("02_Infrastructure/factor_db/factor_db_connector.R")

# ─── Load P3 / P4 ──────────────────────────────────────
cat("[1] Loading P3 / P4 distributional forecasts ...\n")
p3 <- as.data.table(read_parquet(
  "04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet"))
p4 <- as.data.table(read_parquet(
  "04_Research/decision_framework/bearish_forecast_v3/03_models/p4_ecdf_final/all_predictions_extended.parquet"))
p3[, Date := as.Date(Date)]
p4[, Date := as.Date(Date)]

cat(sprintf("  P3 obs=%d range=%s..%s\n",
  nrow(p3), as.character(min(p3$Date)), as.character(max(p3$Date))))
cat(sprintf("  P4 obs=%d range=%s..%s\n",
  nrow(p4), as.character(min(p4$Date)), as.character(max(p4$Date))))

# ─── Load RAWDATA (price + universe) ───────────────────
cat("\n[2] Loading RAWDATA (price + universe + sector) ...\n")
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)
cat(sprintf("  RAWDATA dim=%d×%d  dates=%s..%s  tickers=%d\n",
  nrow(rd), ncol(rd), as.character(min(rd$Date)),
  as.character(max(rd$Date)), uniqueN(rd$Ticker)))

# Universe (KOSPI200 ∪ KOSDAQ150 — PIT via membership flags daily)
rd[, in_universe := (K200 == 1) | (KQ150 == 1)]

# Liquidity: 20d avg trading value (Vol*Close) — STRICT PIT t-1: t-20..t-1
# Codex critical concern C5 fix: shift by 1 day to exclude signal-date volume.
rd[, tv := Vol * Close]
setorder(rd, Ticker, Date)
rd[, tv_20d_raw := frollmean(tv, n = 20L, align = "right"), by = Ticker]
rd[, tv_20d := shift(tv_20d_raw, n = 1L, type = "lag"), by = Ticker]  # t-1 lag
rd[, liq_pass := tv_20d >= 2e8]  # 2e8 KRW (PIT-safe at t-1)

# BM_Ret = KOSPI200 return (already in rd)
cat("  Universe + liquidity filter applied.\n")

# ─── Sample windows ────────────────────────────────────
TRAIN_END  <- as.Date("2018-12-31")
VAL_END    <- as.Date("2023-12-31")
LOCKBOX    <- as.Date("2024-01-01")  # Alpha forbidden — for governance evaluation only
# Alpha runs on train+validation only (R2 P2 window isolation).
SIG_CUTOFF <- VAL_END  # signal generation cutoff

# Monthly signal dates (last business day of each month)
sig_dates <- unique(rd[Date <= SIG_CUTOFF, Date])
sig_dates <- sig_dates[order(sig_dates)]
month_ends <- sig_dates[c(diff(as.integer(format(sig_dates, "%m"))) != 0, TRUE)]
month_ends <- month_ends[format(month_ends, "%Y") >= "2014"]  # first 1y burn-in
cat(sprintf("\n[3] Monthly signal dates: %d months  %s..%s\n",
  length(month_ends), as.character(min(month_ends)), as.character(max(month_ends))))

# ─── PILLAR-1: P4 regime classifier ────────────────────
cat("\n[4] PILLAR-1: P4-based market regime classifier (t-1 PIT) ...\n")
# Use P4 most recent obs BEFORE sig_date (t-1 PIT)
# Compute trailing 252d quantiles of P4 var_05 / sigma / mu for expanding regime
p4_sorted <- p4[order(Date)]

# For each month-end, find latest p3/p4 obs strictly before sig_date
p4_signal <- p4_sorted[, .(Date, mu, sigma, var_05, lam, nu)]
p3_sorted <- p3[order(Date)]
p3_signal <- p3_sorted[, .(Date, mu, sigma, var_05, lam)]

# Build month-level snapshot — combines P4 21d structural + P3 1d short-term confirmation
build_regime <- function(sig_date) {
  ps4 <- p4_signal[Date < sig_date]
  ps3 <- p3_signal[Date < sig_date]
  if (nrow(ps4) == 0) return(NULL)
  latest4 <- ps4[.N]

  # P4-based 21d structural percentiles (PIT-safe expanding)
  q_sigma_21d <- mean(ps4$sigma <= latest4$sigma, na.rm = TRUE)
  q_mu_21d    <- mean(ps4$mu    <= latest4$mu,    na.rm = TRUE)
  q_var_05_21d <- mean(ps4$var_05 <= latest4$var_05, na.rm = TRUE)
  structural_stress <- (q_sigma_21d + (1 - q_mu_21d)) / 2  # 0..1

  # P3 short-term confirmation: 1d sigma percentile in trailing 30d (P3 is daily)
  if (nrow(ps3) >= 30L) {
    latest3 <- ps3[.N]
    p3_recent <- tail(ps3, 30L)
    q_sigma_1d_30d <- mean(p3_recent$sigma <= latest3$sigma, na.rm = TRUE)
    short_term_confirm <- q_sigma_1d_30d  # 0=calm, 1=peak short-term vol
  } else {
    short_term_confirm <- 0.5
    latest3 <- list(mu = NA, sigma = NA, var_05 = NA, lam = NA)
  }

  # Combined regime score: 21d structural × short-term confirmation
  # Avoid 21d-only false-stress: if 21d structural=high but short-term=low → de-escalate to bear (not stress).
  # If 21d structural=high AND short-term=high → stress confirmed.
  regime_score <- 0.65 * structural_stress + 0.35 * short_term_confirm
  regime <- if (regime_score >= 0.72) "stress"
            else if (regime_score >= 0.55) "bear"
            else if (regime_score >= 0.35) "normal"
            else "bull"

  list(sig_date = sig_date,
       # P4 (21d)
       p4_mu = latest4$mu, p4_sigma = latest4$sigma, p4_var_05 = latest4$var_05,
       p4_lam = latest4$lam, p4_nu = latest4$nu,
       q_sigma_21d = q_sigma_21d, q_mu_21d = q_mu_21d, q_var_05_21d = q_var_05_21d,
       structural_stress = structural_stress,
       # P3 (1d)
       p3_sigma = latest3$sigma, p3_lam = latest3$lam, p3_var_05 = latest3$var_05,
       q_sigma_1d_30d = short_term_confirm,
       # Combined
       regime_score = regime_score, regime = regime)
}

regime_dt <- rbindlist(lapply(month_ends, build_regime), fill = TRUE)
regime_dt <- regime_dt[!is.na(regime)]
cat("  Regime distribution (months):\n")
print(table(regime_dt$regime))

# ─── PILLAR-2: Cross-sectional downside-beta ───────────
cat("\n[5] PILLAR-2: Cross-sectional downside-beta DB_i (expanding 252d) ...\n")
# DB_i = cov(R_i, R_m | R_m <= Q5_m) / var(R_m | R_m <= Q5_m)
# Computed monthly using trailing 252d daily returns.

# Build daily wide return matrix limited to active universe
rd_d <- rd[!is.na(Ret) & !is.na(BM_Ret)]

# downside-beta per stock per sig_date (rolling 252d)
compute_DB <- function(sig_date, lookback_days = 252L) {
  # STRICT PIT: Date < sig_date (t-1 lag) — Codex C5 fix
  start_d <- sig_date - lookback_days * 1.5  # buffer
  win <- rd_d[Date < sig_date & Date >= start_d]
  d_in <- sort(unique(win$Date))
  d_in <- tail(d_in, lookback_days)
  win <- win[Date %in% d_in]
  if (nrow(win) < 100L) return(data.table(Ticker = character(0), DB = numeric(0)))

  # bm down dates
  bm <- unique(win[, .(Date, BM_Ret)])
  setkey(bm, Date)
  bm5_thresh <- quantile(bm$BM_Ret, 0.05, na.rm = TRUE)
  bm_down <- bm[BM_Ret <= bm5_thresh]
  bm_down_var <- var(bm_down$BM_Ret, na.rm = TRUE)
  if (!is.finite(bm_down_var) || bm_down_var <= 0)
    return(data.table(Ticker = character(0), DB = numeric(0)))

  # Restrict win to down-dates only, then per-ticker covariance
  win_dn <- win[Date %in% bm_down$Date, .(Ticker, Date, Ret, BM_Ret)]
  setkey(win_dn, Ticker, Date)

  res <- win_dn[, {
    if (sum(!is.na(Ret) & !is.na(BM_Ret)) < 10L) {
      list(DB = NA_real_, n_obs = sum(!is.na(Ret)))
    } else {
      cv <- cov(Ret, BM_Ret, use = "complete.obs")
      list(DB = cv / bm_down_var, n_obs = sum(!is.na(Ret) & !is.na(BM_Ret)))
    }
  }, by = Ticker]

  res <- res[!is.na(DB) & n_obs >= 10L, .(Ticker, DB)]
  res
}

# Compute DB per sig_date — but expensive. Cache.
DB_CACHE <- file.path(ST_DIR, "DB_cache.parquet")
if (file.exists(DB_CACHE)) {
  cat("  Loading cached DB ...\n")
  db_all <- as.data.table(read_parquet(DB_CACHE))
} else {
  cat("  Computing DB across months (this may take ~3-5 min) ...\n")
  db_list <- vector("list", length(month_ends))
  for (i in seq_along(month_ends)) {
    sd <- month_ends[i]
    db_i <- compute_DB(sd)
    if (nrow(db_i) > 0) {
      db_i[, sig_date := sd]
      db_list[[i]] <- db_i
    }
    if (i %% 12L == 0L) cat(sprintf("    %d / %d months done\n", i, length(month_ends)))
  }
  db_all <- rbindlist(db_list, use.names = TRUE, fill = TRUE)
  write_parquet(db_all, DB_CACHE)
  cat(sprintf("  DB computed for %d stock-month obs.\n", nrow(db_all)))
}

# Standardize DB cross-sectionally (z-score) and align direction
# Sign: positive DB = high downside beta = BAD in stress (penalize)
# Z_Score_Aligned style: higher = better → invert sign of DB
db_all[, DB_z_raw := (DB - mean(DB, na.rm=TRUE)) / sd(DB, na.rm=TRUE), by = sig_date]
# Winsorize ±3
db_all[, DB_z := pmin(pmax(DB_z_raw, -3), 3)]
db_all[, DB_z_aligned := -DB_z]   # higher = lower downside beta = safer = better in stress
cat("  DB cross-sectional z-score + winsorize ±3 + sign-align done.\n")

# ─── PILLAR-3: Regime-conditional factor composite ─────
cat("\n[6] PILLAR-3: Regime-conditional factor weighting ...\n")
# Factor pool: top-stable defense + quality + momentum + tail (per Charter §15 P1 Factor Zoo 축소)
# Selected via conditional_ic_matrix.csv (HARD evidence):
#   stress / bear → emphasize ic_bad >= 0.03 stable factors
#   normal / bull → emphasize ic_good high factors

# Factor pool — Iter3 (4-family, Charter §15 P1: validation > discovery, evidence-based)
# Empirical IC (.cache/conditional_ic_matrix.csv) supports:
#   defense  (D-vol)  ic_all=0.067 stable both regimes
#   quality  (Q)      ic_all=0.021 stable both regimes
#   value    (V)      ic_all=0.045 (V02_EP) — complements low-vol (orthogonal mechanism)
#   consensus(C)      ic_all=0.051 (C04_ESBR / C01_SUE) — analyst signals
# DROPPED: momentum (KR 1M reversal IC=-0.010 confirmed Iter1).
# Goal: 4-family composite breaks top-decile defense saturation.
factor_pool <- list(
  defense   = c("D22_Tracking_Error", "D56_Up_Vol", "D01_IdioVol", "D39_RogersSatchell_Vol",
                "D37_Parkinson_Vol", "D38_GarmanKlass_Vol", "D40_YangZhang_Vol", "D03_RealVol"),
  quality   = c("Q07_Earnings_Stability", "Q11_Net_Margin", "Q17_ROIC", "Q23_Sustainable_Growth",
                "Q32_Interest_Coverage", "Q03_ROA"),
  value     = c("V02_EP", "V14_EBIT_EV", "V15_NetDebt_Adj_EP", "V03_CFP"),
  consensus = c("C04_ESBR", "C01_SUE", "C19_Composite_Earnings", "C13_Revision_Breadth_3m")
)

# Static EW (4-family) — Iter7 (ablation proved regime weighting non-additive).
# All regimes use SAME 0.25 weights. Regime info goes into confidence vector only.
regime_weights <- list(
  stress = c(defense = 0.25, quality = 0.25, value = 0.25, consensus = 0.25),
  bear   = c(defense = 0.25, quality = 0.25, value = 0.25, consensus = 0.25),
  normal = c(defense = 0.25, quality = 0.25, value = 0.25, consensus = 0.25),
  bull   = c(defense = 0.25, quality = 0.25, value = 0.25, consensus = 0.25)
)

# DB diagnostic only — NOT in alpha. Stored for Risk Agent.
db_penalty_w <- list(stress = 0, bear = 0, normal = 0, bull = 0)

# Regime → confidence multiplier mapping (P3/P4 enters alpha via confidence vector)
# Charter v6.1 R4-A: confidence_vector[ticker] ∈ [0,1] = data quality × stability × factor decomp × regime
# Optimizer applies α̃ = c·α̂ where c = confidence
# Strategy: in stress regime, confidence is LOWER overall (downweight all exposure) but
#           RELATIVELY HIGHER for low-vol/strong-quality stocks (preserve defense).
# Mapping by regime:
#   stress: overall_conf = 0.55, low-vol bonus +0.20 (max 1.0), quality bonus +0.10
#   bear:   overall_conf = 0.70, low-vol bonus +0.15, quality bonus +0.08
#   normal: overall_conf = 0.85, value+consensus bonus +0.10
#   bull:   overall_conf = 0.95, value+consensus bonus +0.15
regime_confidence_base <- list(stress = 0.55, bear = 0.70, normal = 0.85, bull = 0.95)
regime_confidence_bonus_defense <- list(stress = 0.20, bear = 0.15, normal = 0.05, bull = 0.0)
regime_confidence_bonus_vc <- list(stress = 0.0, bear = 0.05, normal = 0.10, bull = 0.15)

# ─── Compute alpha_scores month by month ──────────────
cat("\n[7] Computing monthly alpha scores ...\n")
ALPHA_CACHE <- file.path(ST_DIR, "alpha_scores.parquet")
all_alpha <- vector("list", length(month_ends))

for (i in seq_along(month_ends)) {
  sd <- month_ends[i]
  reg_i <- regime_dt[sig_date == sd]
  if (nrow(reg_i) == 0) next
  rg <- reg_i$regime[1]
  fw <- regime_weights[[rg]]
  dbw <- db_penalty_w[[rg]]

  # Factor DB load — PIT safe
  fac <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(fac) || nrow(fac) == 0) next

  # Universe filter at sig_date
  rd_sd <- rd[Date == sd & in_universe == TRUE & liq_pass == TRUE]
  if (nrow(rd_sd) == 0) {
    # Fall back to nearest prior date with universe
    cand_dates <- unique(rd[Date <= sd & in_universe == TRUE, Date])
    sd_eff <- max(cand_dates)
    rd_sd <- rd[Date == sd_eff & in_universe == TRUE & liq_pass == TRUE]
  }
  univ_tickers <- rd_sd$Ticker
  if (length(univ_tickers) == 0) next

  fac_u <- fac[Ticker %in% univ_tickers]

  # Compute family composite per ticker
  compute_family <- function(fam_factors) {
    sub <- fac_u[Factor_Name %in% fam_factors]
    if (nrow(sub) == 0) return(NULL)
    # Mean across factors (equal-weight within family — Charter §15 P1 simplicity)
    sub_w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    score_vec <- rowMeans(as.matrix(sub_w[, -1, drop = FALSE]), na.rm = TRUE)
    data.table(Ticker = sub_w$Ticker, score = score_vec)
  }

  def_dt <- compute_family(factor_pool$defense)
  qua_dt <- compute_family(factor_pool$quality)
  val_dt <- compute_family(factor_pool$value)
  con_dt <- compute_family(factor_pool$consensus)
  if (is.null(def_dt) || is.null(qua_dt)) next

  # Merge into one
  all_t <- data.table(Ticker = univ_tickers)
  all_t <- merge(all_t, def_dt[, .(Ticker, defense = score)], by = "Ticker", all.x = TRUE)
  all_t <- merge(all_t, qua_dt[, .(Ticker, quality = score)], by = "Ticker", all.x = TRUE)
  if (!is.null(val_dt)) {
    all_t <- merge(all_t, val_dt[, .(Ticker, value = score)], by = "Ticker", all.x = TRUE)
  } else all_t[, value := NA_real_]
  if (!is.null(con_dt)) {
    all_t <- merge(all_t, con_dt[, .(Ticker, consensus = score)], by = "Ticker", all.x = TRUE)
  } else all_t[, consensus := NA_real_]

  # Cross-sectional z-score within sig_date for each family
  for (c in c("defense", "quality", "value", "consensus")) {
    v <- all_t[[c]]
    if (sum(!is.na(v)) >= 30L) {
      mu <- mean(v, na.rm = TRUE); s <- sd(v, na.rm = TRUE)
      if (is.finite(s) && s > 1e-12) {
        all_t[[c]] <- pmin(pmax((v - mu) / s, -3), 3)
      } else all_t[[c]] <- 0
    } else all_t[[c]] <- 0
    all_t[is.na(get(c)), (c) := 0]
  }

  # Static 4-family EW composite (Iter7) — this IS the alpha
  all_t[, composite := 0.25 * defense + 0.25 * quality + 0.25 * value + 0.25 * consensus]

  # DB stored as SUPPLEMENTARY diagnostic only (Charter §10 Risk Agent input)
  db_sd <- db_all[sig_date == sd, .(Ticker, DB_z_aligned)]
  all_t <- merge(all_t, db_sd, by = "Ticker", all.x = TRUE)
  all_t[is.na(DB_z_aligned), DB_z_aligned := 0]

  # Alpha = composite (4-family static EW)
  all_t[, alpha := composite]

  # Coverage-based base confidence
  all_t[, n_fam_covered := (!is.na(defense)) + (!is.na(quality)) + (!is.na(value)) + (!is.na(consensus))]
  all_t[, base_conf := pmin(pmax(0.3 + 0.1 * n_fam_covered, 0.3), 0.7)]   # 0.3..0.7

  # P3/P4-driven REGIME-AWARE confidence (this is where P3/P4 enters alpha-generation)
  rb <- regime_confidence_base[[rg]]
  rbd <- regime_confidence_bonus_defense[[rg]]
  rbv <- regime_confidence_bonus_vc[[rg]]

  # Per-stock regime bonus: defense-strong gets stress/bear bonus, value+consensus-strong gets normal/bull bonus
  all_t[, def_strong := pmax(0, pmin(1, (defense - 0) / 2))]    # 0..1 for z=0..2
  all_t[, vc_strong  := pmax(0, pmin(1, ((value + consensus) / 2 - 0) / 2))]

  # Combined confidence: base × regime_base × (1 + bonus)
  all_t[, regime_conf := rb * (1 + rbd * def_strong + rbv * vc_strong)]
  all_t[, confidence := pmin(1.0, base_conf * regime_conf / 0.7)]   # normalize so base_conf=0.7 gives full regime_conf

  all_t[, sig_date := sd]
  all_t[, regime := rg]
  all_alpha[[i]] <- all_t[, .(sig_date, Ticker, defense, quality, value, consensus, composite,
                              DB_z_aligned, alpha, confidence, regime,
                              base_conf, regime_conf)]
}

alpha_scores <- rbindlist(all_alpha, use.names = TRUE, fill = TRUE)
cat(sprintf("  Alpha scores: %d stock-month obs across %d sig_dates.\n",
  nrow(alpha_scores), uniqueN(alpha_scores$sig_date)))
write_parquet(alpha_scores, ALPHA_CACHE)

# ─── Diagnostics — IC / ICIR / Harvey-t / monotonicity ─
cat("\n[8] Diagnostics (rank IC + ICIR + Harvey-t + monotonicity + subperiod) ...\n")

# Need forward 1M return: link sig_date d → return [d, d+1m)
# Use monthly close-to-close
rd_m <- rd[, .(close = last(Close), in_uni = last(in_universe), liq = last(liq_pass)),
           by = .(Ticker, ym = format(Date, "%Y-%m"))]
rd_m[, sig_date := as.Date(paste0(ym, "-01"))]
# Match to month-end sig_dates
me_map <- data.table(sig_date_real = month_ends, ym = format(month_ends, "%Y-%m"))
rd_m <- merge(rd_m, me_map, by = "ym", all.x = TRUE)
rd_m <- rd_m[!is.na(sig_date_real), .(Ticker, sig_date = sig_date_real, close)]
setkey(rd_m, Ticker, sig_date)
# Forward return = close(t+1) / close(t) - 1
rd_m[, next_close := shift(close, n = -1, type = "lag"), by = Ticker]
rd_m[, fwd_ret_1m := next_close / close - 1]

# Merge alpha with forward return
diag_dt <- merge(alpha_scores, rd_m[, .(Ticker, sig_date, fwd_ret_1m)],
                 by = c("Ticker", "sig_date"), all.x = TRUE)
diag_dt <- diag_dt[!is.na(fwd_ret_1m) & !is.na(alpha)]

# Monthly Rank IC (Spearman)
monthly_ic <- diag_dt[, .(rank_ic = cor(alpha, fwd_ret_1m, method = "spearman",
                                          use = "complete.obs"),
                          n = .N), by = sig_date]
monthly_ic <- monthly_ic[is.finite(rank_ic) & n >= 30L]

rank_ic_mean <- mean(monthly_ic$rank_ic, na.rm = TRUE)
rank_ic_sd <- sd(monthly_ic$rank_ic, na.rm = TRUE)
ICIR <- rank_ic_mean / rank_ic_sd

# Harvey-t (Newey-West HAC SE)
suppressMessages(library(sandwich))
suppressMessages(library(lmtest))
m_ic <- monthly_ic[order(sig_date)]
fit <- lm(rank_ic ~ 1, data = m_ic)
nw <- coeftest(fit, vcov = NeweyWest(fit, lag = 4, prewhite = FALSE))
harvey_t <- abs(nw[1, 3])

# Subperiod stability
m_ic[, sub := ifelse(sig_date < as.Date("2019-01-01"), "P1_2014_2018",
                ifelse(sig_date < as.Date("2024-01-01"), "P2_2019_2023", "P3_lockbox"))]
sub_sum <- m_ic[, .(ic = mean(rank_ic, na.rm = TRUE), n = .N), by = sub]
print(sub_sum)
sub_pos <- sum(sub_sum$ic > 0)
subperiod_stability <- sub_pos / nrow(sub_sum)

# Monotonicity — decile portfolio mean returns
diag_dt[, decile := cut(alpha, breaks = quantile(alpha, probs = seq(0, 1, 0.1),
                                                   na.rm = TRUE),
                         labels = 1:10, include.lowest = TRUE), by = sig_date]
dec_ret <- diag_dt[!is.na(decile), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)),
                   by = decile]
setorder(dec_ret, decile)
print(dec_ret)
# Monotonicity = Spearman rank correlation between decile index and mean ret
monotonicity <- cor(as.integer(dec_ret$decile), dec_ret$mean_ret, method = "spearman")

# Turnover proxy — month-on-month change in top-50 names
top50 <- diag_dt[, .(Ticker = Ticker[order(-alpha)[1:50]]), by = sig_date]
top50_lst <- split(top50$Ticker, top50$sig_date)
to_seq <- numeric(length(top50_lst) - 1L)
for (j in seq_along(to_seq)) {
  a <- top50_lst[[j]]; b <- top50_lst[[j + 1]]
  to_seq[j] <- 1 - length(intersect(a, b)) / 50
}
turnover_monthly <- mean(to_seq, na.rm = TRUE)
turnover_annual <- turnover_monthly * 12

# Recent 3Y IC (overfit check, RF-A3)
m_ic_recent <- m_ic[sig_date >= max(sig_date) - 365 * 3L]
rank_ic_recent <- mean(m_ic_recent$rank_ic, na.rm = TRUE)
recent_overfit_ratio <- if (abs(rank_ic_mean) > 1e-8) rank_ic_recent / rank_ic_mean else NA_real_

# Post-neutralization IC (sector + size neutralize)
# Cross-sectional residual: lm(alpha ~ sector + log(size))
# Use Sector_Lv2 + Size from rd
neutralize_one_date <- function(d_sub, sd_) {
  rd_sd <- rd[Date == sd_, .(Ticker, Sector_Lv2, Size)]
  if (nrow(rd_sd) == 0) {
    # find nearest prior date
    cand <- unique(rd[Date <= sd_ & !is.na(Size), Date])
    if (length(cand) == 0) return(NULL)
    rd_sd <- rd[Date == max(cand), .(Ticker, Sector_Lv2, Size)]
  }
  rd_sd[, log_size := log(pmax(Size, 1))]
  m <- merge(d_sub[, .(Ticker, alpha, fwd_ret_1m)], rd_sd, by = "Ticker")
  m[is.na(Sector_Lv2), Sector_Lv2 := "NA_sec"]
  if (nrow(m) < 30L) return(NULL)
  fit_n <- tryCatch(lm(alpha ~ factor(Sector_Lv2) + log_size, data = m),
                    error = function(e) NULL)
  if (is.null(fit_n)) return(NULL)
  m$alpha_neut <- residuals(fit_n)
  if (sum(!is.na(m$alpha_neut) & !is.na(m$fwd_ret_1m)) < 20L) return(NULL)
  ic_n <- cor(m$alpha_neut, m$fwd_ret_1m, method = "spearman", use = "complete.obs")
  data.table(sig_date = sd_, rank_ic_neut = ic_n, n = nrow(m))
}

post_neut_list <- vector("list", length(month_ends))
for (kk in seq_along(month_ends)) {
  sd_ <- month_ends[kk]
  d_sub <- diag_dt[sig_date == sd_]
  if (nrow(d_sub) < 30L) next
  post_neut_list[[kk]] <- neutralize_one_date(d_sub, sd_)
}
post_neut_ic <- rbindlist(post_neut_list, use.names = TRUE, fill = TRUE)
post_neut_mean <- mean(post_neut_ic$rank_ic_neut, na.rm = TRUE)
post_neut_retention <- if (abs(rank_ic_mean) > 1e-8) post_neut_mean / rank_ic_mean else NA_real_

cat(sprintf("\n=== DIAGNOSTICS SUMMARY (train+validation only, %d sig_dates) ===\n",
  nrow(monthly_ic)))
cat(sprintf("  Rank IC (mean)         = %.4f\n", rank_ic_mean))
cat(sprintf("  Rank IC (sd)           = %.4f\n", rank_ic_sd))
cat(sprintf("  ICIR                   = %.4f\n", ICIR))
cat(sprintf("  Harvey t (NW HAC L=4)  = %.4f\n", harvey_t))
cat(sprintf("  Monotonicity           = %.4f\n", monotonicity))
cat(sprintf("  Subperiod stability    = %.4f\n", subperiod_stability))
cat(sprintf("  Recent 3Y IC           = %.4f\n", rank_ic_recent))
cat(sprintf("  Recent-overfit ratio   = %.4f  (RF-A3 alert if >1.5)\n", recent_overfit_ratio))
cat(sprintf("  Post-neutralization IC = %.4f  (retention %.2f)\n",
  post_neut_mean, post_neut_retention))
cat(sprintf("  Turnover (annual)      = %.4f\n", turnover_annual))

# ─── Save diagnostics ──────────────────────────────────
diagnostics_obj <- list(
  rank_ic = rank_ic_mean,
  rank_ic_sd = rank_ic_sd,
  icir = ICIR,
  harvey_t_stat = harvey_t,
  monotonicity = monotonicity,
  subperiod_stability = subperiod_stability,
  subperiod_detail = sub_sum,
  recent_3y_ic = rank_ic_recent,
  recent_overfit_ratio = recent_overfit_ratio,
  post_neutralization_ic = post_neut_mean,
  post_neutralization_retention = post_neut_retention,
  turnover_annual = turnover_annual,
  decile_returns = dec_ret,
  n_sig_dates = nrow(monthly_ic),
  n_obs_total = nrow(diag_dt)
)

saveRDS(diagnostics_obj, file.path(ST_DIR, "diagnostics_full.rds"))
fwrite(monthly_ic, file.path(ST_DIR, "monthly_ic.csv"))

cat("\n[9] Done.  Elapsed: ", format(Sys.time() - t0, digits = 2), "\n")
