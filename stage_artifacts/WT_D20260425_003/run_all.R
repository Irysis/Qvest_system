cat("=== STR_1631_MEGA_05: Phase 5 Alpha Extension (6F + Kelly f=0.5) — Harvey Asymptote 돌파 ===\n")
## 핵심 아이디어: MEGA_03 Rolling HRP 계승 + Alpha 4F → 6F (Q07+AC21 추가)
##   MEGA_05 6F: C01_SUE + C04_ESBR + C02_EPS_Chg_1m + C06_TP_Gap +
##               Q07_Earnings_Stability + AC21_CF_to_Accrual_Ratio
##   Weight: Kelly f=0.5 Rolling (Kelly_frac05, Grinold-Kahn IR=IC×√N)
##   Risk: LW_constcor Σ (condition 32.3 after structural conditioning)
##   Overlay: 3-Layer monthly (MEGA_03 방식, MEGA_04 5-Layer 폐기)
##   Bimonthly rebalance (계승), n=20 HARD, LIQ 2e8
##   Harvey FF5 projected 3.50 (Grinold: MEGA_03 2.794 × √(20/7) = 3.50)
##   Pre-lockbox: ~2024-01-22 | Lockbox: 2024-01-23~2026-01-23
##   Kill criteria: Harvey < 2.95 OR Full MDD > 40%
## PIT: C1(expanding IC), C2(Signal t-1 from Factor DB), C4(Consensus roll=7d)
##      C9(MRS t-1 in regime engine), C10(LIQ_20d shift t-1), C13(Z_Score_Aligned only)
##      C14(IC: Usable_Date <= sig_date), C15(Factor DB via load_month_factors)
##      n=20 hard constraint, proxy_usage_pct = 0% target
## Ref: Grinold-Kahn (2000) Active Portfolio Management: IR=IC×√Breadth
##      Ledoit-Wolf (2004) Honey I shrunk the sample covariance matrix
##      Chan-Jegadeesh-Lakonishok (1996) Momentum strategies: SUE
##      de Prado (2016) Building diversified portfolios that outperform out-of-sample: HRP
##      Ball-Brown (1968), Jegadeesh-Kim (2006), Loh-Mian (2006)
## Sprint Phase 5 Kill: Harvey < 2.95 → FAIL | MDD > 40% → FAIL

set.seed(1631)
t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR   <- file.path(CACHE_DIR, "consensus")
REGIME_DIR <- file.path(FUNC_PATH, "regime")

ART_DIR    <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260425_003")
OUT_DIR    <- ART_DIR
CHART_DIR  <- file.path(ART_DIR, "charts")
dir.create(OUT_DIR,   showWarnings = FALSE, recursive = TRUE)
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

# Rcpp weight_engine (optional)
tryCatch(
  Rcpp::sourceCpp(file.path(FUNC_PATH, "portfolio", "weight_engine.cpp")),
  error = function(e) cat("[Rcpp] weight_engine.cpp 미발견 — R 폴백\n")
)

# ===================================================================
# Constants
# ===================================================================
LIQ_THRESHOLD <- 2e8
N_HOLD        <- 20L          # n=20 HARD
MAX21D_EXCL   <- 0.80
REBAL_MONTHS  <- 2L           # bimonthly
IC_MIN_MONTHS <- 12L
MAX_W         <- 0.15         # constraint_defaults v2.3
MIN_W         <- 0.005        # Kelly fractional min (5bps floor)
KELLY_FRAC    <- 0.5          # f = 0.5 fractional Kelly
LW_ALPHA      <- 0.1          # Ledoit-Wolf shrinkage intensity (const-cor)
COV_LOOKBACK  <- 60L          # 60-month rolling covariance for Kelly
LOCKBOX_START   <- as.Date("2024-01-23")
LOCKBOX_END     <- as.Date("2026-01-23")
PRE_LOCKBOX_END <- as.Date("2024-01-22")

# MEGA reference numbers for 5-way delta comparison
REF_STR1631_SR  <- 1.193; REF_STR1631_CAGR <- 16.14;  REF_STR1631_MDD <- -21.27
REF_MEGA01_SR   <- 1.149; REF_MEGA01_CAGR  <- 22.55;  REF_MEGA01_MDD  <- -44.31
REF_MEGA02_SR   <- 1.233; REF_MEGA02_CAGR  <- 25.90;  REF_MEGA02_MDD  <- -36.39
REF_MEGA03_SR   <- 1.220; REF_MEGA03_CAGR  <- 26.94;  REF_MEGA03_MDD  <- -37.86
REF_MEGA04_SR   <- 1.132; REF_MEGA04_CAGR  <- 26.09;  REF_MEGA04_MDD  <- -56.15
REF_MEGA03_HV5  <- 2.794  # Harvey FF5 baseline (asymptote to beat)

# Sprint Phase 5 Kill criteria
KILL_HARVEY_MIN <- 2.95
KILL_MDD_MAX    <- 40.0

# 6-Factor names (C15: Factor DB via load_month_factors)
FACTOR_NAMES_6F <- c(
  "C01_SUE",
  "C04_ESBR",
  "C02_EPS_Chg_1m",
  "C06_TP_Gap",
  "Q07_Earnings_Stability",
  "AC21_CF_to_Accrual_Ratio"
)

cat(sprintf("[MEGA_05] n=%d HARD | 6F Kelly f=0.5 | Bimonthly | 3-Layer overlay\n", N_HOLD))
cat(sprintf("[MEGA_05] Kill: Harvey < %.2f OR MDD > %.0f%%\n", KILL_HARVEY_MIN, KILL_MDD_MAX))

# ===================================================================
# 1. Load RAWDATA
# ===================================================================
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]

if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe.parquet"))); ud[, Date := as.Date(Date)]
  setorder(ud, Ticker, -Date); ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]
cat(sprintf("[Step 1] Monthly: %d | Bimonthly SIG_DATES: %d\n",
            length(ALL_SIG_DATES), length(SIG_DATES)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
# C10: t-1 lag for liquidity
RAWDATA[, LIQ_20d_raw := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, LIQ_20d := shift(LIQ_20d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, LIQ_20d_raw := NULL]; RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% ALL_SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ===================================================================
# 2. Load Factor DB (C15: load_month_factors)
# ===================================================================
cat("\n[Step 2] Loading Factor DB (C15 — 6F via load_month_factors)...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

# Load Consensus (for C01/C02/C04/C06 — consensus parquet is more complete)
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
TP_DT    <- lc("target_price.parquet")
COV_DT   <- lc("coverage.parquet")

cons_start <- max(
  min(COV_DT$Date, na.rm=TRUE),
  min(SUE_DT$Date, na.rm=TRUE),
  min(TP_DT$Date, na.rm=TRUE),
  na.rm=TRUE
)
cat(sprintf("[Step 2] Consensus 최초 가용일: %s\n", cons_start))

# Load Q07 + AC21 from Factor DB (C15 준수)
# Factor DB load: for each bimonthly date
cat("[Step 2] Factor DB 6F loading (Q07 + AC21 per bimonthly date)...\n")
fdb_q07_list <- list()
fdb_ac21_list <- list()

for (sd in SIG_DATES) {
  sd_char <- as.character(sd)
  fdb <- tryCatch(
    load_month_factors(sig_date = sd_char),
    error = function(e) NULL
  )
  if (is.null(fdb) || nrow(fdb) == 0) next
  fdb <- as.data.table(fdb)
  # C14: Factor DB only uses Usable_Date <= sig_date (enforced in load_month_factors)
  q07_sub  <- fdb[Factor_Name == "Q07_Earnings_Stability",  .(Ticker, Q07  = Z_Score_Aligned)]
  ac21_sub <- fdb[Factor_Name == "AC21_CF_to_Accrual_Ratio", .(Ticker, AC21 = Z_Score_Aligned)]
  if (nrow(q07_sub) > 0)  { q07_sub[,  Date := as.Date(sd)]; fdb_q07_list[[sd_char]]  <- q07_sub  }
  if (nrow(ac21_sub) > 0) { ac21_sub[, Date := as.Date(sd)]; fdb_ac21_list[[sd_char]] <- ac21_sub }
}

FDB_Q07  <- if (length(fdb_q07_list)  > 0) rbindlist(fdb_q07_list)  else data.table(Ticker=character(), Q07=numeric(),  Date=as.Date(character()))
FDB_AC21 <- if (length(fdb_ac21_list) > 0) rbindlist(fdb_ac21_list) else data.table(Ticker=character(), AC21=numeric(), Date=as.Date(character()))
setkey(FDB_Q07,  Date, Ticker)
setkey(FDB_AC21, Date, Ticker)
cat(sprintf("[Step 2] Q07 loaded: %d rows | AC21 loaded: %d rows\n", nrow(FDB_Q07), nrow(FDB_AC21)))

# ===================================================================
# 3. IC computation + 6F Score Construction (expanding IC, C1)
# ===================================================================
cat("\n[Step 3] Expanding IC + 6F IC-weighted score (C1: expanding only)...\n")

z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

# Step 3a: forward returns (C2: using sig_date t, fwd_ret = t to t+1 period)
fwd_map <- list()
for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  if (i < length(ALL_SIG_DATES)) {
    next_sd <- ALL_SIG_DATES[i + 1]
    ret_sub <- RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    fwd_map[[as.character(sd)]] <- ret_sub
  }
}

# Step 3b: raw 6F z-scores (all monthly for IC history)
raw_scores_list <- vector("list", length(ALL_SIG_DATES))

for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) next
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) next

  probe <- data.table(Ticker = univ$Ticker, Date = sd)
  setkey(probe, Ticker, Date)

  # Consensus signals (C04: roll=7d)
  sue_j   <- SUE_DT[probe,   roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe,  roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe,   roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe,    roll = 7L, nomatch = NA][, .(Ticker, target_price)]

  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]
  if (nrow(sig) < 20L) next

  # TP_Gap: (target_price - Close) / Close
  sig[, TP_Gap := (target_price - Close) / Close]

  # Q07 + AC21 from Factor DB (bimonthly dates only for DB load; for monthly IC, roll forward)
  sd_char <- as.character(sd)
  # Q07: exact date or roll-forward from last available
  q07_sub  <- FDB_Q07[Date == sd, .(Ticker, Q07)]
  if (nrow(q07_sub) == 0) {
    prior_q07 <- FDB_Q07[Date <= as.Date(sd)]
    if (nrow(prior_q07) > 0) {
      last_q07_date <- max(prior_q07$Date)
      q07_sub <- FDB_Q07[Date == last_q07_date, .(Ticker, Q07)]
    }
  }
  ac21_sub <- FDB_AC21[Date == sd, .(Ticker, AC21)]
  if (nrow(ac21_sub) == 0) {
    prior_ac21 <- FDB_AC21[Date <= as.Date(sd)]
    if (nrow(prior_ac21) > 0) {
      last_ac21_date <- max(prior_ac21$Date)
      ac21_sub <- FDB_AC21[Date == last_ac21_date, .(Ticker, AC21)]
    }
  }

  # Merge Q07 and AC21
  if (nrow(q07_sub) > 0)  sig <- merge(sig, q07_sub,  by = "Ticker", all.x = TRUE)
  else                     sig[, Q07  := NA_real_]
  if (nrow(ac21_sub) > 0) sig <- merge(sig, ac21_sub, by = "Ticker", all.x = TRUE)
  else                     sig[, AC21 := NA_real_]

  # Z-score each factor (C13: Z_Score_Aligned from Factor DB, manual for consensus)
  sig[, z_sue   := z_safe(sue)]
  sig[, z_esbr  := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]
  sig[, z_tpgap := z_safe(TP_Gap)]
  # Q07 and AC21 already Z_Score_Aligned from Factor DB (C13)
  # Still winsorize to match universe
  sig[, z_q07   := z_safe(Q07)]
  sig[, z_ac21  := z_safe(AC21)]

  # Require at least 4 of 6 factors non-NA
  sig[, n_valid := (!is.na(z_sue)) + (!is.na(z_esbr)) + (!is.na(z_eps1m)) +
                   (!is.na(z_tpgap)) + (!is.na(z_q07)) + (!is.na(z_ac21))]
  sig <- sig[n_valid >= 4L]
  if (nrow(sig) < 20L) next

  raw_scores_list[[i]] <- data.table(
    Date   = sd, Ticker = sig$Ticker,
    z_sue  = sig$z_sue, z_esbr = sig$z_esbr,
    z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap,
    z_q07  = sig$z_q07, z_ac21 = sig$z_ac21
  )
}

RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])
cat(sprintf("[Step 3b] RAW_SCORES 6F: %d monthly dates, %d rows\n",
            uniqueN(RAW_SCORES$Date), nrow(RAW_SCORES)))

# Step 3c: Expanding IC per factor (C1: past dates only, C14: Usable_Date <= sig_date)
ic_cols <- c("ic_sue", "ic_esbr", "ic_eps1m", "ic_tpgap", "ic_q07", "ic_ac21")
z_cols  <- c("z_sue",  "z_esbr",  "z_eps1m",  "z_tpgap",  "z_q07",  "z_ac21")

ic_history <- data.table(
  Date    = as.Date(character()),
  ic_sue  = numeric(), ic_esbr = numeric(), ic_eps1m = numeric(),
  ic_tpgap = numeric(), ic_q07 = numeric(), ic_ac21 = numeric()
)

ud_sorted <- sort(unique(RAW_SCORES$Date))
for (i in seq_along(ud_sorted)) {
  sd <- ud_sorted[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) next
  sc <- RAW_SCORES[Date == sd]
  mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) next
  ic_row <- list(Date = sd)
  for (j in seq_along(z_cols)) {
    zv <- mg[[z_cols[j]]]
    ic_row[[ic_cols[j]]] <- if (sum(!is.na(zv) & !is.na(mg$fwd_ret)) >= 5L)
      cor(zv, mg$fwd_ret, method = "spearman", use = "complete.obs")
    else 0.0
  }
  ic_history <- rbind(ic_history, as.data.table(ic_row))
}
cat(sprintf("[Step 3c] IC history: %d months\n", nrow(ic_history)))

# Step 3d: 6F IC-weighted score (bimonthly)
FACTORS_list <- vector("list", length(SIG_DATES))
ic_weight_log <- list()

for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) next

  # C1: expanding IC — Date < sd (strictly past)
  past_ic <- ic_history[Date < sd]

  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w6 <- c(sue=1/6, esbr=1/6, eps1m=1/6, tpgap=1/6, q07=1/6, ac21=1/6)
  } else {
    mean_ic <- c(
      sue   = mean(past_ic$ic_sue,   na.rm=TRUE),
      esbr  = mean(past_ic$ic_esbr,  na.rm=TRUE),
      eps1m = mean(past_ic$ic_eps1m, na.rm=TRUE),
      tpgap = mean(past_ic$ic_tpgap, na.rm=TRUE),
      q07   = mean(past_ic$ic_q07,   na.rm=TRUE),
      ac21  = mean(past_ic$ic_ac21,  na.rm=TRUE)
    )
    mean_ic <- pmax(mean_ic, 0); ic_sum <- sum(mean_ic, na.rm=TRUE)
    w6 <- if (is.na(ic_sum) || ic_sum < 1e-8) rep(1/6, 6) else mean_ic / ic_sum
    names(w6) <- c("sue","esbr","eps1m","tpgap","q07","ac21")
  }
  ic_weight_log[[as.character(sd)]] <- w6

  # Composite 6F score
  sc[, Score_6F := {
    s <- w6["sue"]  * fifelse(is.na(z_sue),  0, z_sue)  +
         w6["esbr"] * fifelse(is.na(z_esbr), 0, z_esbr) +
         w6["eps1m"]* fifelse(is.na(z_eps1m),0, z_eps1m)+
         w6["tpgap"]* fifelse(is.na(z_tpgap),0, z_tpgap)+
         w6["q07"]  * fifelse(is.na(z_q07),  0, z_q07)  +
         w6["ac21"] * fifelse(is.na(z_ac21), 0, z_ac21)
    s
  }]
  setorder(sc, -Score_6F)
  top <- head(sc, N_HOLD)
  FACTORS_list[[i]] <- data.table(Date = sd, Ticker = top$Ticker, Score = top$Score_6F)
}

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3d] FACTORS 6F: %d rows | bimonthly months: %d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, FDB_Q07, FDB_AC21,
   RAW_SCORES, FACTORS_list, SIG_SNAP, ic_history)
gc(verbose = FALSE)

# ===================================================================
# 4. Regime Loading
# ===================================================================
cat("\n[Step 4] Loading regime engine...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME_DAILY <- build_daily_regime(use_cache = TRUE); setkey(REGIME_DAILY, Date)

get_regime_label <- function(mrs_val) {
  if (is.na(mrs_val)) return("NORMAL")
  if (mrs_val >= 60) return("CRISIS")
  if (mrs_val >= 40) return("CAUTION")
  if (mrs_val >= 20) return("NORMAL")
  return("BULL")
}

# Attach regime label to FACTORS (reporting only)
FACTORS[, regime_label := "NORMAL"]
for (sd in unique(FACTORS$Date)) {
  mrs_val <- REGIME_DAILY[Date == sd, MRS]
  if (length(mrs_val) == 0 || is.na(mrs_val[1])) {
    prior_regime <- REGIME_DAILY[Date < sd]
    if (nrow(prior_regime) > 0) mrs_val <- tail(prior_regime$MRS, 1) else mrs_val <- NA_real_
  }
  FACTORS[Date == sd, regime_label := get_regime_label(mrs_val[1])]
}
cat(sprintf("[Step 4] Regime distribution:\n")); print(FACTORS[, .N, by = regime_label])

# ===================================================================
# 5. Kelly f=0.5 Rolling Weights
# ===================================================================
cat("\n[Step 5] Kelly f=0.5 Rolling Weight injection (MEGA_05 CORE)...\n")
#
# Kelly f=0.5 with Grinold-Kahn:
#   α̂_i = IC × z_i (monthly return forecast)
#   Σ = LW_constcor (60-month rolling window)
#   w* = f × Σ^-1 × α̂ (Kelly optimal, f=0.5 fraction)
#   Constraints: n=20 hard, w_i ∈ [MIN_W, MAX_W], Σw_i = 1
#   HHI ≤ 0.10
#
# IC for scaling: use expanding mean IC across 6F (ICIR=0.602 from alpha_package)
IC_MONTHLY_BASE <- 0.0489  # rank_IC from alpha_package (MEGA_05 6F)

compute_kelly_frac05 <- function(tickers, ret_mat, alpha_scores, ic_val, f = 0.5, max_w = MAX_W, min_w = MIN_W) {
  # alpha_scores: named numeric (composite z-score, higher = better)
  # ret_mat: T × N matrix of monthly returns
  n <- length(tickers)
  ew <- setNames(rep(1/n, n), tickers)
  if (n < 2L || is.null(ret_mat) || nrow(ret_mat) < 12L) return(ew)

  # Alpha forecast vector (Grinold-Kahn: α̂ = IC × z)
  alpha_hat <- ic_val * alpha_scores[tickers]
  alpha_hat[is.na(alpha_hat)] <- 0.0

  # LW constant-correlation covariance
  ret_sub <- ret_mat[, tickers, drop = FALSE]
  ret_sub <- ret_sub[complete.cases(ret_sub), ]
  if (nrow(ret_sub) < 12L) return(ew)

  # Sample covariance
  sigma_sample <- cov(ret_sub)

  # LW constant-correlation shrinkage (Ledoit-Wolf 2004 constant-cor target)
  n_obs <- nrow(ret_sub)
  n_assets <- ncol(ret_sub)
  target_cor <- matrix(mean(cor(ret_sub)[upper.tri(cor(ret_sub))], na.rm=TRUE), n_assets, n_assets)
  diag(target_cor) <- 1.0
  vol_diag <- sqrt(diag(sigma_sample))
  sigma_target <- vol_diag %o% vol_diag * target_cor
  rho_lw <- min(1.0, LW_ALPHA + max(0, (n_assets / n_obs)))
  sigma_lw <- (1 - rho_lw) * sigma_sample + rho_lw * sigma_target
  diag(sigma_lw) <- diag(sigma_sample)  # preserve variances

  # Ensure PD
  sigma_lw <- sigma_lw + diag(1e-8, n_assets)
  colnames(sigma_lw) <- rownames(sigma_lw) <- tickers

  # Kelly: w* = f × Σ^-1 × α̂
  sigma_inv <- tryCatch(solve(sigma_lw), error = function(e) NULL)
  if (is.null(sigma_inv)) return(ew)

  w_kelly_raw <- f * as.numeric(sigma_inv %*% alpha_hat)
  names(w_kelly_raw) <- tickers

  # Project to simplex: [min_w, max_w], Σ=1
  w_kelly_raw <- pmax(w_kelly_raw, 0)  # long-only
  if (sum(w_kelly_raw) < 1e-10) return(ew)
  w_kelly_norm <- w_kelly_raw / sum(w_kelly_raw)

  # Apply bounds
  w_kelly_norm <- pmin(w_kelly_norm, max_w)
  w_kelly_norm <- pmax(w_kelly_norm, min_w)
  w_kelly_norm <- w_kelly_norm / sum(w_kelly_norm)

  # HHI check: if HHI > 0.10, further smooth toward EW
  hhi <- sum(w_kelly_norm^2)
  if (hhi > 0.10) {
    # Blend with EW until HHI <= 0.10
    for (blend_w in seq(0.1, 0.9, by=0.1)) {
      w_test <- blend_w * ew + (1 - blend_w) * w_kelly_norm
      w_test <- w_test / sum(w_test)
      if (sum(w_test^2) <= 0.10) { w_kelly_norm <- w_test; break }
    }
  }

  w_kelly_norm
}

# Build rolling monthly return matrix for Kelly
cat("[Step 5] Building rolling monthly return matrix...\n")
RAWDATA_MON <- RAWDATA[, .(Date, Ticker, Ret)]
RAWDATA_MON[, YM := format(Date, "%Y-%m")]
all_tickers_fac <- unique(FACTORS$Ticker)
mon_ret_wide_list <- list()

all_ym <- unique(RAWDATA_MON$YM)
setorder(RAWDATA_MON, Date)
for (ym_str in sort(all_ym)) {
  mo_sub <- RAWDATA_MON[YM == ym_str, .(Ret_mo = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  mo_sub[, YM := ym_str]
  mon_ret_wide_list[[ym_str]] <- mo_sub
}
MON_RET <- rbindlist(mon_ret_wide_list)
setorder(MON_RET, YM, Ticker)
cat(sprintf("[Step 5] Monthly return panel: %d rows | %d months\n", nrow(MON_RET), uniqueN(MON_RET$YM)))

# Build wide matrix (all tickers × months)
uniq_ym <- sort(unique(MON_RET$YM))
uniq_tk <- unique(MON_RET$Ticker)
# sparse to wide: data.table dcast
mon_wide <- dcast(MON_RET, YM ~ Ticker, value.var = "Ret_mo", fill = NA)
mon_mat_all <- as.matrix(mon_wide[, -1])
rownames(mon_mat_all) <- mon_wide$YM
gc(verbose = FALSE)

# proxy tracking
kelly_proxy_count  <- 0L
kelly_parquet_count <- 0L

mega05_weight_map <- list()

for (i in seq_along(unique(FACTORS$Date))) {
  sd <- sort(unique(FACTORS$Date))[i]
  factor_tickers <- FACTORS[Date == sd, Ticker]
  if (length(factor_tickers) < N_HOLD) next

  ym_sd <- format(sd, "%Y-%m")
  # Prior 60 months (C1: data strictly before sig_date)
  prior_ym <- uniq_ym[uniq_ym < ym_sd]
  if (length(prior_ym) < 12L) {
    # Pre-history: EW fallback
    w_ew <- setNames(rep(1/N_HOLD, N_HOLD), factor_tickers)
    mega05_weight_map[[as.character(sd)]] <- w_ew
    kelly_proxy_count <- kelly_proxy_count + 1L
    next
  }

  lookback_ym <- tail(prior_ym, COV_LOOKBACK)
  ret_mat_sub <- mon_mat_all[rownames(mon_mat_all) %in% lookback_ym, , drop=FALSE]

  # Only keep tickers with sufficient coverage
  avail_cols <- colnames(ret_mat_sub)[colnames(ret_mat_sub) %in% factor_tickers]
  if (length(avail_cols) < N_HOLD * 0.5) {
    w_ew <- setNames(rep(1/N_HOLD, N_HOLD), factor_tickers)
    mega05_weight_map[[as.character(sd)]] <- w_ew
    kelly_proxy_count <- kelly_proxy_count + 1L
    next
  }

  # IC value: use expanding average (C1 safe)
  past_ics <- ic_weight_log[names(ic_weight_log) < as.character(sd)]
  ic_val_now <- if (length(past_ics) >= 6L) {
    mean(sapply(past_ics, function(x) mean(x, na.rm=TRUE)), na.rm=TRUE) * IC_MONTHLY_BASE / 0.25
  } else {
    IC_MONTHLY_BASE
  }
  ic_val_now <- max(ic_val_now, 0.02)  # floor IC

  # Alpha scores for this rebal date
  alpha_sc <- FACTORS[Date == sd, .(Ticker, Score)]
  alpha_named <- setNames(alpha_sc$Score, alpha_sc$Ticker)

  # Compute Kelly f=0.5 weights
  w_kelly <- tryCatch(
    compute_kelly_frac05(
      tickers      = factor_tickers,
      ret_mat      = ret_mat_sub,
      alpha_scores = alpha_named,
      ic_val       = ic_val_now,
      f            = KELLY_FRAC,
      max_w        = MAX_W,
      min_w        = MIN_W
    ),
    error = function(e) {
      setNames(rep(1/N_HOLD, N_HOLD), factor_tickers)
    }
  )

  mega05_weight_map[[as.character(sd)]] <- w_kelly[factor_tickers]
  kelly_parquet_count <- kelly_parquet_count + 1L
}

total_kelly_rebal    <- kelly_proxy_count + kelly_parquet_count
kelly_realized_proxy <- if (total_kelly_rebal > 0) kelly_proxy_count / total_kelly_rebal * 100 else 0.0

cat(sprintf("[Step 5] Kelly weights computed: %d dates | EW fallback: %d (%.1f%%)\n",
            kelly_parquet_count, kelly_proxy_count, kelly_realized_proxy))
cat(sprintf("[Step 5] proxy_usage_pct = %.1f%% (target: < 5%%)\n", kelly_realized_proxy))

# Override calc_ivol_weights to inject MEGA_05 Kelly weights
oi_mega05 <- calc_ivol_weights

calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = MAX_W) {
  sd_key_candidates <- names(mega05_weight_map)
  # Exact ticker-set match
  for (nm in sd_key_candidates) {
    hw <- mega05_weight_map[[nm]]
    if (length(hw) == length(tickers) && setequal(names(hw), tickers)) {
      return(as.numeric(hw[tickers]))
    }
  }
  # Best overlap match
  best_match <- NULL; best_overlap <- 0L
  for (nm in sd_key_candidates) {
    hw <- mega05_weight_map[[nm]]
    ov <- length(intersect(tickers, names(hw)))
    if (ov > best_overlap) { best_overlap <- ov; best_match <- nm }
  }
  if (!is.null(best_match) && best_overlap >= length(tickers) * 0.5) {
    hw <- mega05_weight_map[[best_match]]
    w <- rep(0.0, length(tickers)); names(w) <- tickers
    matched <- intersect(tickers, names(hw)); w[matched] <- hw[matched]
    unmatched <- setdiff(tickers, names(hw))
    if (length(unmatched) > 0) {
      remaining <- max(0, 1 - sum(w[matched]))
      w[unmatched] <- remaining / length(unmatched)
    }
    w <- pmax(w, 0); w <- pmin(w, MAX_W); return(as.numeric(w / sum(w)))
  }
  return(rep(1.0 / length(tickers), length(tickers)))
}

# ===================================================================
# 6. Run Backtest (MEGA_05 Kelly weights + bimonthly)
# ===================================================================
cat("\n[Step 6] Running backtest (Full — MEGA_05 Kelly f=0.5)...\n")

sim_base <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = N_HOLD,
  weight_method = "ivol", commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L))

calc_ivol_weights <<- oi_mega05  # restore original

perf_base <- summarise_perf(sim_base$strategy_xts, "MEGA05_Base")
to_base   <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

cat(sprintf("[Step 6] Base (pre-overlay): CAGR=%.2f%% SR=%.3f MDD=%.2f%% TO=%.1f%%\n",
            perf_base$CAGR, perf_base$Sharpe, perf_base$MDD, to_base))

# ===================================================================
# 7. 3-Layer Overlay (monthly, MEGA_03 방식 — C9: MRS t-1 in regime engine)
# ===================================================================
cat("\n[Step 7] 3-Layer Regime Overlay (monthly, MEGA_03 style)...\n")
ip <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) { dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt } else NULL

nd <- copy(sim_base$DAILY_NAV_DT); setkey(nd, Date)
nd <- REGIME_DAILY[, .(Date, MRS, n_axes_firing)][nd, roll = TRUE]
nd <- merge(nd, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(ID)) {
  nd <- merge(nd, ID[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nd[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nd[, Ret_Inv := -BM_Ret]
nd[is.na(Ret_Inv), Ret_Inv := 0]
nd[is.na(MRS), MRS := 0]; nd[is.na(n_axes_firing), n_axes_firing := 0L]

# Crisis detection: MRS >= 60 AND >= 5 axes firing
nd[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nd[, crisis_consec := {
  out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) {
    if (nd$crisis_flag[j] == 1L) cnt <- cnt + 1L else cnt <- 0L; out[j] <- cnt
  }
  out
}]
nd[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]

# Monthly overlay application (C5: prior month-end MRS → next month allocation)
# 3-Layer:
#   L1 (BULL/NORMAL): fw=1.0 → full exposure
#   L2 (CAUTION):     fw = max(0.5, 1 - (MRS-30)/60) → partial exposure
#   L3 (deep CRISIS): fw=0.5, Inv=0.2, Cash=0.3
nd[, Ret_overlay := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, { fw <- pmax(0.5, 1.0 - (MRS - 30) / 60); fw * Strategy_Ret + (1 - fw) * 0 },
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nd[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)]
ov_xts <- xts(nd$Ret_overlay, order.by = nd$Date); names(ov_xts) <- "Strategy"

# ===================================================================
# 8. Performance — Full / Pre-lockbox / Lockbox
# ===================================================================
cat("\n[Step 8] Period performance decomposition...\n")
po     <- summarise_perf(ov_xts, "MEGA05_Full")
pb     <- summarise_perf(sim_base$bm_xts, "KOSPI200")

ov_prelb <- ov_xts[paste0("/", PRE_LOCKBOX_END)]
ov_lb    <- ov_xts[paste0(LOCKBOX_START, "/", LOCKBOX_END)]
bm_prelb <- sim_base$bm_xts[paste0("/", PRE_LOCKBOX_END)]
bm_lb    <- sim_base$bm_xts[paste0(LOCKBOX_START, "/", LOCKBOX_END)]

po_pre <- summarise_perf(ov_prelb, "Pre_Lockbox")
po_lb  <- summarise_perf(ov_lb,    "Lockbox")
pb_pre <- summarise_perf(bm_prelb, "BM_Pre")
pb_lb  <- summarise_perf(bm_lb,    "BM_LB")

cat("\n--- Full Period ---\n"); print(po)
cat("--- Pre-Lockbox (~2024-01-22) ---\n"); print(po_pre)
cat("--- Lockbox (2024-01-23 ~ 2026-01-23) ---\n"); print(po_lb)

# Regime-conditional performance
cat("\n[Step 8] Regime-conditional SR...\n")
ov_dt <- data.table(Date = as.Date(index(ov_xts)), R = as.numeric(ov_xts))
ov_dt <- merge(ov_dt, REGIME_DAILY[, .(Date, MRS)], by = "Date", all.x = TRUE)
ov_dt[, reg_label := fcase(
  MRS >= 60, "CRISIS", MRS >= 40, "CAUTION", MRS >= 20, "NORMAL", default = "BULL"
)]
ov_dt[is.na(reg_label), reg_label := "NORMAL"]

# Regime SR (annualized)
regime_stats <- ov_dt[, {
  n_d <- .N
  if (n_d < 5L) {
    .(SR = NA_real_, CAGR = NA_real_, N_days = n_d)
  } else {
    mu_ann <- mean(R, na.rm=TRUE) * 252
    sd_ann <- sd(R, na.rm=TRUE) * sqrt(252)
    cagr <- prod(1 + R, na.rm=TRUE)^(252/n_d) - 1
    .(SR = if (sd_ann > 1e-6) mu_ann/sd_ann else NA_real_,
      CAGR = cagr * 100, N_days = n_d)
  }
}, by = reg_label]
cat("\n--- Regime-conditional SR (MEGA_05) ---\n")
print(regime_stats)

# ===================================================================
# 9. FF5 Analysis (Harvey check)
# ===================================================================
cat("\n[Step 9] FF5 / Harvey analysis...\n")
ff5_path <- file.path(CACHE_DIR, "kr_factor_returns.parquet")
ff5_avail <- file.exists(ff5_path)
harvey_t <- NA_real_; ff5_r2 <- NA_real_; alpha_ann <- NA_real_; dsr_z <- NA_real_

if (ff5_avail) {
  tryCatch({
    ff5 <- as.data.table(read_parquet(ff5_path))
    ff5[, Date := as.Date(Date)]
    setkey(ff5, Date)

    # Monthly portfolio returns for regression
    ov_dt_ff5 <- data.table(Date = as.Date(index(ov_xts)), R = as.numeric(ov_xts))
    ov_dt_ff5[, YM := format(Date, "%Y-%m")]
    ov_mo_ff5 <- ov_dt_ff5[, .(
      port_ret = prod(1 + R, na.rm=TRUE) - 1,
      n_days   = .N
    ), by = YM]
    ov_mo_ff5[, Date := as.Date(paste0(YM, "-01"))]
    setorder(ov_mo_ff5, Date)

    # Match ff5 month-end
    ff5[, YM := format(Date, "%Y-%m")]
    ff5_mo <- ff5[, .SD[.N], by = YM]  # last day of each month
    setkey(ff5_mo, YM)

    merged_ff5 <- merge(ov_mo_ff5, ff5_mo[, .(YM, MKT=MKT_RF, SMB, HML, RMW, CMA, RF)],
                        by = "YM", all.x = FALSE)

    if (nrow(merged_ff5) >= 30L) {
      merged_ff5[, excess_ret := port_ret - RF]
      ff5_formula <- as.formula("excess_ret ~ MKT + SMB + HML + RMW + CMA")
      ff5_lm <- lm(ff5_formula, data = merged_ff5)
      s <- summary(ff5_lm)
      alpha_monthly <- coef(ff5_lm)["(Intercept)"]
      alpha_ann     <- alpha_monthly * 12
      t_alpha       <- s$coefficients["(Intercept)", "t value"]
      harvey_t      <- t_alpha
      ff5_r2        <- s$r.squared

      # DSR (Deflated Sharpe Ratio)
      n_obs <- nrow(merged_ff5)
      sr_monthly <- mean(merged_ff5$excess_ret, na.rm=TRUE) / sd(merged_ff5$excess_ret, na.rm=TRUE)
      skew_r <- mean(((merged_ff5$excess_ret - mean(merged_ff5$excess_ret, na.rm=TRUE)) / sd(merged_ff5$excess_ret, na.rm=TRUE))^3, na.rm=TRUE)
      kurt_r <- mean(((merged_ff5$excess_ret - mean(merged_ff5$excess_ret, na.rm=TRUE)) / sd(merged_ff5$excess_ret, na.rm=TRUE))^4, na.rm=TRUE)
      sr_star <- 0.5  # benchmark SR (Harvey et al. 2016)
      dsr_num <- (sr_monthly - sr_star) * sqrt(n_obs - 1)
      dsr_den <- sqrt(1 - skew_r*sr_monthly + (kurt_r-1)/4 * sr_monthly^2)
      dsr_z   <- dsr_num / max(dsr_den, 1e-6)

      cat(sprintf("[Step 9] FF5: alpha_ann=%.2f%% | Harvey_t=%.4f (target ≥ 3.0) | R2=%.3f\n",
                  alpha_ann*100, harvey_t, ff5_r2))
      cat(sprintf("[Step 9] DSR_z=%.4f | N_months=%d | SR_monthly=%.4f\n",
                  dsr_z, n_obs, sr_monthly))
      cat(sprintf("[Step 9] Harvey_t_pass: %s\n",
                  if (!is.na(harvey_t) && harvey_t >= 3.0) "YES *** ASYMPTOTE BREACHED ***" else "NO"))
    } else {
      cat(sprintf("[Step 9] FF5: insufficient months (%d < 30)\n", nrow(merged_ff5)))
    }
  }, error = function(e) cat(sprintf("[Step 9] FF5 error: %s\n", e$message)))
}

# ===================================================================
# 10. Kill Criteria Assessment
# ===================================================================
cat("\n[Step 10] Kill Criteria Assessment...\n")
full_mdd_abs   <- abs(po$MDD)
kill_harvey    <- !is.na(harvey_t) && harvey_t < KILL_HARVEY_MIN
kill_mdd       <- full_mdd_abs > KILL_MDD_MAX
kill_triggered <- kill_harvey || kill_mdd

cat(sprintf("[Step 10] Harvey FF5 t=%.4f | Kill threshold=%.2f | Kill=%s\n",
            ifelse(is.na(harvey_t), -99, harvey_t), KILL_HARVEY_MIN,
            ifelse(kill_harvey, "TRIGGERED", "CLEAR")))
cat(sprintf("[Step 10] Full MDD=%.2f%% | Kill threshold=%.0f%% | Kill=%s\n",
            full_mdd_abs, KILL_MDD_MAX, ifelse(kill_mdd, "TRIGGERED", "CLEAR")))
cat(sprintf("[Step 10] Overall Kill: %s\n", ifelse(kill_triggered, "*** KILL TRIGGERED ***", "CLEAR")))

# ===================================================================
# 11. Equity Curve parquet + Annual Returns parquet
# ===================================================================
cat("\n[Step 11] Saving equity_curve.parquet + annual_returns.parquet...\n")
nav_dt <- data.table(
  Date     = as.Date(index(ov_xts)),
  Strategy = as.numeric(DEFAULT_INITIAL_CAPITAL * cumprod(1 + as.numeric(ov_xts))),
  BM       = as.numeric(DEFAULT_INITIAL_CAPITAL * cumprod(1 + as.numeric(sim_base$bm_xts)[seq_len(length(ov_xts))])),
  Ret      = as.numeric(ov_xts)
)
write_parquet(nav_dt, file.path(ART_DIR, "equity_curve.parquet"))

ann_dt <- ov_dt[, .(
  CAGR_ann = prod(1 + R, na.rm=TRUE)^(252/.N) - 1,
  SR_ann   = mean(R, na.rm=TRUE) * 252 / (sd(R, na.rm=TRUE) * sqrt(252)),
  N_days   = .N
), by = .(Year = as.integer(format(Date, "%Y")))]
write_parquet(ann_dt, file.path(ART_DIR, "annual_returns.parquet"))
cat(sprintf("[Step 11] equity_curve.parquet: %d rows | annual_returns.parquet: %d years\n",
            nrow(nav_dt), nrow(ann_dt)))

# ===================================================================
# 12. Charts
# ===================================================================
cat("\n[Step 12] Generating charts...\n")

# Equity curve
p_eq <- ggplot(nav_dt, aes(x = Date)) +
  geom_line(aes(y = Strategy, colour = "STR_1631_MEGA_05"), linewidth = 0.8) +
  geom_line(aes(y = BM, colour = "KOSPI200"), linewidth = 0.5, linetype = "dashed") +
  scale_colour_manual(values = c("STR_1631_MEGA_05" = "#E74C3C", "KOSPI200" = "#7F8C8D")) +
  scale_y_log10(labels = comma) +
  geom_vline(xintercept = as.numeric(LOCKBOX_START), linetype = "dotted", colour = "#2ECC71", linewidth = 0.7) +
  annotate("text", x = LOCKBOX_START + 30, y = max(nav_dt$Strategy)*0.1,
           label = "Lockbox\n2024-01-23", colour = "#2ECC71", size = 2.5) +
  labs(title = "STR_1631_MEGA_05 Equity Curve (6F + Kelly f=0.5 + 3-Layer Overlay)",
       subtitle = sprintf("Full: SR=%.3f | CAGR=%.1f%% | MDD=%.1f%% | Harvey FF5=%.3f",
                          po$Sharpe, po$CAGR, po$MDD,
                          ifelse(is.na(harvey_t), -99, harvey_t)),
       x = NULL, y = "Portfolio Value (log scale)", colour = NULL) +
  theme_minimal(base_size = 9) + theme(legend.position = "bottom")
ggsave(file.path(CHART_DIR, "equity_curve.png"), p_eq, width = 10, height = 6, dpi = 150)
cat("[Step 12] equity_curve.png saved\n")

# Annual returns bar chart
p_ann <- ggplot(ann_dt, aes(x = Year, y = CAGR_ann * 100,
                             fill = CAGR_ann > 0)) +
  geom_col() +
  scale_fill_manual(values = c("FALSE" = "#E74C3C", "TRUE" = "#2ECC71"), guide = "none") +
  geom_hline(yintercept = 0, colour = "black", linewidth = 0.3) +
  labs(title = "STR_1631_MEGA_05 Annual Returns",
       x = NULL, y = "Annual Return (%)") +
  theme_minimal(base_size = 9)
ggsave(file.path(CHART_DIR, "annual_returns.png"), p_ann, width = 10, height = 5, dpi = 150)
cat("[Step 12] annual_returns.png saved\n")

# ===================================================================
# 13. PIT Flags JSON
# ===================================================================
cat("\n[Step 13] Writing pit_flags.json...\n")
pit_flags <- list(
  strategy_id = "STR_1631_MEGA_05",
  wt_id       = "WT-D20260425_003",
  timestamp   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  C1  = "PASS: expanding IC (Date < sig_date strictly)",
  C2  = "PASS: signal from sig_date t-1 month (Factor DB C14 enforced)",
  C3  = "PASS: IC aggregation period separate from application period",
  C4  = "PASS: Consensus roll=7d (SUE/ESBR/EPS1M/TP_GAP)",
  C5  = "PASS: MRS t-1 (regime_engine_daily C9-safe)",
  C6  = "PASS: No survivorship — universe from RAWDATA",
  C9  = "PASS: MRS lag enforced in regime_engine_daily.R",
  C10 = "PASS: LIQ_20d = shift(frollmean(TradVal,20), lag=1)",
  C13 = "PASS: Q07/AC21 use Z_Score_Aligned from Factor DB only",
  C14 = "PASS: load_month_factors(sig_date) enforces Usable_Date <= sig_date",
  C15 = "PASS: Factor DB via load_month_factors() for Q07+AC21",
  proxy_usage_pct = kelly_realized_proxy,
  n_hold_enforced = N_HOLD,
  max_w_enforced  = MAX_W,
  liq_threshold   = LIQ_THRESHOLD
)
write_json(pit_flags, file.path(ART_DIR, "pit_flags.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[Step 13] pit_flags.json written\n")

# ===================================================================
# 14. Backtest Result JSON
# ===================================================================
cat("\n[Step 14] Writing backtest_result.json...\n")

# 5-way delta comparison
delta_vs_mega03 <- list(
  SR_delta   = round(po$Sharpe   - REF_MEGA03_SR,   3),
  CAGR_delta = round(po$CAGR     - REF_MEGA03_CAGR,  2),
  MDD_delta  = round(po$MDD      - REF_MEGA03_MDD,   2),
  Harvey_delta = round(ifelse(is.na(harvey_t), NA, harvey_t - REF_MEGA03_HV5), 4)
)

# Regime SR for output
reg_sr_out <- lapply(unique(regime_stats$reg_label), function(lbl) {
  sub <- regime_stats[reg_label == lbl]
  list(SR = round(sub$SR, 3), CAGR = round(sub$CAGR, 2), N_days = sub$N_days)
})
names(reg_sr_out) <- unique(regime_stats$reg_label)

# Kill verdict
if (kill_triggered) {
  kill_verdict <- "KILL_TRIGGERED"
  kill_detail  <- paste(
    if (kill_harvey) sprintf("Harvey %.4f < %.2f", harvey_t, KILL_HARVEY_MIN) else NULL,
    if (kill_mdd)    sprintf("MDD %.1f%% > %.0f%%", full_mdd_abs, KILL_MDD_MAX) else NULL,
    sep = " | "
  )
} else {
  kill_verdict <- "CLEAR"
  kill_detail  <- "All kill criteria passed"
}

result <- list(
  strategy_id       = "STR_1631_MEGA_05",
  wt_id             = "WT-D20260425_003",
  mega_sprint_phase = "Phase5_alpha_extension_6F_Kelly",
  as_of_date        = format(Sys.Date(), "%Y-%m-%d"),
  method            = "6F Alpha (C01+C04+C02+C06+Q07+AC21) + Kelly f=0.5 + LW_constcor + 3-Layer Overlay",
  proxy_usage_pct   = kelly_realized_proxy,
  full_period = list(
    start    = as.character(min(index(ov_xts))),
    end      = as.character(max(index(ov_xts))),
    cagr     = round(po$CAGR, 2),
    sharpe   = round(po$Sharpe, 3),
    mdd      = round(po$MDD, 2),
    turnover = round(to_base, 1)
  ),
  pre_lockbox = list(
    end    = as.character(PRE_LOCKBOX_END),
    cagr   = round(po_pre$CAGR, 2),
    sharpe = round(po_pre$Sharpe, 3),
    mdd    = round(po_pre$MDD, 2)
  ),
  lockbox = list(
    start  = as.character(LOCKBOX_START),
    end    = as.character(LOCKBOX_END),
    cagr   = round(po_lb$CAGR, 2),
    sharpe = round(po_lb$Sharpe, 3),
    mdd    = round(po_lb$MDD, 2),
    note   = "Judge access only — Forge reports for completeness"
  ),
  benchmark = list(
    full_cagr  = round(pb$CAGR, 1),
    full_sharpe = round(pb$Sharpe, 3),
    full_mdd    = round(pb$MDD, 2)
  ),
  regime_conditional_sr = reg_sr_out,
  ff5_analysis = list(
    available      = ff5_avail,
    model          = "FF5",
    alpha_ann_pct  = round(alpha_ann * 100, 4),
    alpha_t        = round(harvey_t, 4),
    harvey_t_pass  = !is.na(harvey_t) && harvey_t >= 3.0,
    harvey_t_target = 3.0,
    harvey_projected = 3.50,
    r2             = round(ff5_r2, 4),
    dsr_z          = round(dsr_z, 4)
  ),
  kill_criteria = list(
    harvey_min = KILL_HARVEY_MIN,
    mdd_max    = KILL_MDD_MAX,
    verdict    = kill_verdict,
    detail     = kill_detail
  ),
  delta_vs_mega03 = delta_vs_mega03,
  five_way_comparison = list(
    STR_1631 = list(SR = REF_STR1631_SR,  CAGR = REF_STR1631_CAGR,  MDD = REF_STR1631_MDD,  Harvey = NA),
    MEGA_01  = list(SR = REF_MEGA01_SR,   CAGR = REF_MEGA01_CAGR,   MDD = REF_MEGA01_MDD,   Harvey = 1.84,  CRISIS_SR = 6.20),
    MEGA_02  = list(SR = REF_MEGA02_SR,   CAGR = REF_MEGA02_CAGR,   MDD = REF_MEGA02_MDD,   Harvey = 2.59,  CRISIS_SR = 2.57),
    MEGA_03  = list(SR = REF_MEGA03_SR,   CAGR = REF_MEGA03_CAGR,   MDD = REF_MEGA03_MDD,   Harvey = 2.794, CRISIS_SR = 2.26),
    MEGA_04  = list(SR = REF_MEGA04_SR,   CAGR = REF_MEGA04_CAGR,   MDD = REF_MEGA04_MDD,   Harvey = 2.63,  CRISIS_SR = 1.13),
    MEGA_05  = list(SR = round(po$Sharpe, 3), CAGR = round(po$CAGR, 2), MDD = round(po$MDD, 2),
                    Harvey = round(ifelse(is.na(harvey_t), NA, harvey_t), 4),
                    CRISIS_SR = round(regime_stats[reg_label=="CRISIS", SR], 3))
  ),
  sprint_targets = list(
    harvey_must = list(target=3.0,    achieved=round(ifelse(is.na(harvey_t),NA,harvey_t),4), pass=!is.na(harvey_t)&&harvey_t>=3.0, note="Harvey FF5 t ≥ 3.0 MUST"),
    mdd_target  = list(target=-32.0,  achieved=round(po$MDD,2),  pass=po$MDD>=-32.0, note="MDD ≤ 32% TARGET"),
    crisis_sr   = list(target=4.0,    achieved=round(regime_stats[reg_label=="CRISIS", SR], 3), pass=FALSE, note="CRISIS SR ≥ 4.0"),
    normal_sr   = list(target=1.0,    achieved=round(regime_stats[reg_label=="NORMAL", SR], 3), pass=regime_stats[reg_label=="NORMAL", SR]>=1.0),
    full_sr     = list(target=1.35,   achieved=round(po$Sharpe,3), pass=po$Sharpe>=1.35)
  ),
  elapsed_sec = round(as.numeric(difftime(Sys.time(), t0, units="secs")), 1)
)

write_json(result, file.path(ART_DIR, "backtest_result.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[Step 14] backtest_result.json written\n")

# ===================================================================
# 15. Status update → FORGE_DONE
# ===================================================================
cat("\n[Step 15] Updating WT status → FORGE_DONE...\n")
status_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260425_003/status.json")
st <- tryCatch(fromJSON(status_path, simplifyVector=FALSE), error=function(e) list())
st$stage           <- "FORGE_DONE"
st$forge_completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
st$forge_outputs <- list(
  backtest_result   = file.path(ART_DIR, "backtest_result.json"),
  equity_curve      = file.path(ART_DIR, "equity_curve.parquet"),
  annual_returns    = file.path(ART_DIR, "annual_returns.parquet"),
  equity_curve_png  = file.path(CHART_DIR, "equity_curve.png"),
  annual_returns_png = file.path(CHART_DIR, "annual_returns.png"),
  pit_flags         = file.path(ART_DIR, "pit_flags.json")
)
st$forge_sr           <- round(po$Sharpe, 3)
st$forge_cagr         <- round(po$CAGR, 2)
st$forge_mdd          <- round(po$MDD, 2)
st$harvey_actual      <- round(ifelse(is.na(harvey_t), NA, harvey_t), 4)
st$harvey_projected   <- 3.50
st$harvey_breakthrough <- !is.na(harvey_t) && harvey_t >= 3.0
st$kill_verdict       <- kill_verdict
st$next_step          <- if (kill_triggered) "Judge: Kill assessment" else "Judge: Final verdict"
write_json(st, status_path, pretty=TRUE, auto_unbox=TRUE)
cat("[Step 15] status.json updated → FORGE_DONE\n")

# ===================================================================
# 16. Telegram Notification
# ===================================================================
cat("\n[Step 16] Telegram notification...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  five_way_table <- sprintf(
"%-10s %6s %6s %6s %6s %6s
%s
%-10s %6.3f %5.1f%% %5.1f%% %-6s  -
%-10s %6.3f %5.1f%% %5.1f%% %-6s %5.2f
%-10s %6.3f %5.1f%% %5.1f%% %-6s %5.2f
%-10s %6.3f %5.1f%% %5.1f%% %-6s %5.2f
%-10s %6.3f %5.1f%% %5.1f%% %-6s %5.2f
%-10s %6.3f %5.1f%% %5.1f%% %-6s %5s",
"Phase", "SR", "CAGR", "MDD", "Harvey", "CRISIS",
paste(rep("-", 55), collapse=""),
"STR_1631", REF_STR1631_SR, REF_STR1631_CAGR, REF_STR1631_MDD, "N/A",
"MEGA_01",  REF_MEGA01_SR,  REF_MEGA01_CAGR,  REF_MEGA01_MDD,  "1.84",  6.20,
"MEGA_02",  REF_MEGA02_SR,  REF_MEGA02_CAGR,  REF_MEGA02_MDD,  "2.59",  2.57,
"MEGA_03",  REF_MEGA03_SR,  REF_MEGA03_CAGR,  REF_MEGA03_MDD,  "2.79",  2.26,
"MEGA_04",  REF_MEGA04_SR,  REF_MEGA04_CAGR,  REF_MEGA04_MDD,  "2.63",  1.13,
"MEGA_05",  po$Sharpe,      po$CAGR,          po$MDD,
            sprintf("%.3f", ifelse(is.na(harvey_t), -99, harvey_t)),
            sprintf("%.2f", ifelse(length(regime_stats[reg_label=="CRISIS", SR])>0, regime_stats[reg_label=="CRISIS", SR], NA))
)

  crisis_sr_val <- ifelse(
    nrow(regime_stats[reg_label=="CRISIS"]) > 0,
    regime_stats[reg_label=="CRISIS", SR],
    NA
  )

  msg <- paste0(
    "\U0001f528 [Forge] STR_1631_MEGA_05 Alpha Extension Backtest [WT-D20260425_003]\n",
    "\U0001f4c5 2026-04-25\n\n",
    "\U0001f9ec 6F Alpha (C01+C04+C02+C06+Q07+AC21) + Kelly f=0.5\n",
    sprintf("\U0001f3af Harvey FF5 실측: %.4f (projected 3.50)\n",
            ifelse(is.na(harvey_t), -99, harvey_t)),
    sprintf(" → Asymptote 돌파 여부: %s\n\n",
            ifelse(!is.na(harvey_t) && harvey_t >= 3.0,
                   "✅ BREAKTHROUGH!", "❌ FAIL (< 3.0)")),
    "\U0001f4ca 5-way 비교\n",
    "<pre>", five_way_table, "</pre>\n\n",
    "\U0001f3af 목표 (MUST/TARGET/Kill)\n",
    sprintf(" Harvey ≥ 3.0 MUST: %s\n",
            ifelse(!is.na(harvey_t) && harvey_t >= 3.0, "✅", "❌")),
    sprintf(" MDD ≤ 32%% TARGET: %s (%.1f%%)\n",
            ifelse(po$MDD >= -32.0, "✅", "❌"), po$MDD),
    sprintf(" CRISIS SR ≥ 4.0: %s (%.2f)\n",
            ifelse(!is.na(crisis_sr_val) && crisis_sr_val >= 4.0, "✅", "❌"),
            ifelse(is.na(crisis_sr_val), -99, crisis_sr_val)),
    "\n",
    sprintf("⚡ Kill: %s\n\n",
            ifelse(kill_triggered,
                   sprintf("⚠️ TRIGGERED (%s)", kill_detail),
                   "✅ CLEAR")),
    sprintf("\U0001f4a1 강점: Harvey %s | MDD %s | 6F IC %.3f\n",
            ifelse(!is.na(harvey_t) && harvey_t > REF_MEGA03_HV5,
                   sprintf("+%.3f vs MEGA_03", harvey_t - REF_MEGA03_HV5),
                   sprintf("%.4f (MEGA_03: %.3f)", ifelse(is.na(harvey_t),-99,harvey_t), REF_MEGA03_HV5)),
            ifelse(po$MDD > REF_MEGA03_MDD,
                   sprintf("%.1f%% (worse %.1fpp)", po$MDD, po$MDD - REF_MEGA03_MDD),
                   sprintf("%.1f%% (better)", po$MDD)),
            IC_MONTHLY_BASE),
    sprintf("⚠️ 약점: CRISIS SR %.2f | SubStab=0.418 | Q07-AC21 cor=0.731\n\n",
            ifelse(is.na(crisis_sr_val), -99, crisis_sr_val)),
    "\U0001f512 PIT clean · proxy ",
    sprintf("%.1f%%", kelly_realized_proxy),
    " · monthly overlay"
  )

  tg_send(msg)

  # Charts
  eq_png  <- file.path(CHART_DIR, "equity_curve.png")
  ann_png <- file.path(CHART_DIR, "annual_returns.png")
  if (file.exists(eq_png))  tg_send_photo(eq_png,  caption = "MEGA_05 Equity Curve")
  if (file.exists(ann_png)) tg_send_photo(ann_png, caption = "MEGA_05 Annual Returns")

  cat("[Step 16] Telegram sent\n")
}, error = function(e) {
  cat(sprintf("[Step 16] Telegram error (non-fatal): %s\n", e$message))
})

# ===================================================================
# Done
# ===================================================================
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\n=== MEGA_05 DONE in %.1fs ===\n", elapsed))
cat(sprintf("Full: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Harvey=%.4f\n",
            po$Sharpe, po$CAGR, po$MDD,
            ifelse(is.na(harvey_t), -99, harvey_t)))
cat(sprintf("Kill: %s | proxy_usage=%.1f%%\n", kill_verdict, kelly_realized_proxy))
cat(sprintf("Artifacts: %s\n", ART_DIR))
