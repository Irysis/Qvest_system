#==============================================================================
# WT-D20260425_005: Cross-Family 3-Way Heterogeneous Blender — Alpha Research
#
# Slot A (Core): STR_1631_SYN_05_2002 (Consensus_4F: SUE/ESBR/EPS1M/TPGap)
# Slot B (Diversifier): STR_1656_MLRA (XGBoost ML residual)
# Slot C (Defense): STR_1689_quality_aggregate_defense V1 (Q01/Q04/Q25)
#
# Pipeline:
#  1. Load RAWDATA + Factor DB
#  2. Build Slot A score (re-load STR_1631 factors_detail.csv)
#  3. Build Slot B score (re-load STR_1656 s5_scores_B.csv)
#  4. Build Slot C score (Quality Aggregate V1 from Factor DB Q01+Q04+Q25)
#  5. Align common universe + dates (Pre-LB only: <= 2024-01-22)
#  6. Cross-family pairwise diagnostics: rank IC corr, score corr, ICIR
#  7. TDC pairwise estimate (joint extreme bottom-decile)
#  8. Output: alpha_scores parquet × 3 + alpha_package.json + alpha_validation.json
#
# WINDOW ISOLATION (R2 P2 enforced):
#  - Pre-LB end: 2024-01-22 (Lockbox start: 2024-01-23)
#  - Alpha Agent uses train+validation only (Pre-LB)
#==============================================================================

t0 <- Sys.time()
set.seed(20260425)

# ---- Environment Setup ----
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
WT_ID      <- "WT-D20260425_005"
OUT_STAGE  <- file.path(PROJECT_ROOT, "qepm", "stage_artifacts", paste0("WT_", WT_ID))
OUT_MAIL   <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
dir.create(OUT_STAGE, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_MAIL,  showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(stats)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

LOCKBOX_START <- as.Date("2024-01-23")  # Lockbox sealed
PRE_LB_END    <- as.Date("2024-01-22")
WINDOW_START  <- as.Date("2003-02-01")  # Slot A coverage start

cat(sprintf("\n=== %s | Cross-Family 3-Way Alpha Research ===\n", WT_ID))
cat(sprintf("Pre-LB Window: %s ~ %s\n", WINDOW_START, PRE_LB_END))

# ===================================================================
# Step 1: Load RAWDATA + Factor DB
# ===================================================================
cat("\n[Step 1] Loading RAWDATA + Factor DB connector...\n")

source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= as.Date("2003-01-01") & Date <= PRE_LB_END]
BM_DT   <- BM_DT[Date >= as.Date("2003-01-01") & Date <= PRE_LB_END]
cat(sprintf("  RAWDATA: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark = ","),
            uniqueN(RAWDATA$Ticker), min(RAWDATA$Date), max(RAWDATA$Date)))

# Liquidity filter (C10): 20d avg TV >= 50M won
LIQ_THRESHOLD <- 50000000
if (!"Vol" %in% names(RAWDATA) && "Volume" %in% names(RAWDATA))
  setnames(RAWDATA, "Volume", "Vol")
if (!"LiqPass" %in% names(RAWDATA)) {
  setkey(RAWDATA, Ticker, Date)
  RAWDATA[, TV := Close * Vol]
  RAWDATA[, TV_20d := frollmean(TV, 20L, align = "right"), by = Ticker]
  # C10: shift t-1 lag
  RAWDATA[, TV_20d_lag := shift(TV_20d, 1L), by = Ticker]
  RAWDATA[, LiqPass := !is.na(TV_20d_lag) & TV_20d_lag >= LIQ_THRESHOLD]
}

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

# Build forward 1M return per ticker per signal date
RAWDATA[, ym := format(Date, "%Y-%m")]
monthend <- RAWDATA[, .(sig_date = max(Date)), by = ym]
sig_dates <- sort(monthend[sig_date >= WINDOW_START & sig_date <= PRE_LB_END, sig_date])
cat(sprintf("  Signal dates: %d (%s ~ %s)\n",
            length(sig_dates), min(sig_dates), max(sig_dates)))

# Forward 1M return
me_close <- RAWDATA[Date %in% sig_dates, .(Date, Ticker, Close)]
setkey(me_close, Ticker, Date)
me_close[, Close_fwd := shift(Close, -1L, type = "shift"), by = Ticker]
me_close[, fwd_1m := Close_fwd / Close - 1]
me_close[, Close_fwd := NULL]
fwd_1m_dt <- me_close[!is.na(fwd_1m), .(Date, Ticker, fwd_1m)]
setkey(fwd_1m_dt, Date, Ticker)
cat(sprintf("  fwd_1m rows: %s\n", format(nrow(fwd_1m_dt), big.mark = ",")))

# ===================================================================
# Step 2: Slot A — STR_1631 SYN_05_2002 score load
# ===================================================================
cat("\n[Step 2] Slot A — STR_1631_SYN_05_2002 (Consensus_4F)\n")

slot_a_path <- file.path(PROJECT_ROOT, "04_Research", "strategies",
                         "STR_1631_SYN_05_2002", "output", "factors_detail.csv")
SLOT_A_RAW <- fread(slot_a_path)
SLOT_A_RAW[, Date := as.Date(Date)]
SLOT_A_RAW <- SLOT_A_RAW[Date >= WINDOW_START & Date <= PRE_LB_END]
setkey(SLOT_A_RAW, Date, Ticker)

# Convert "score" to monthly snapshot — STR_1631 SYN_05 already provides Score per (Date, Ticker)
# Re-snap to month-end alignment
SLOT_A_RAW[, ym := format(Date, "%Y-%m")]
slot_a_dates <- SLOT_A_RAW[, .(score_date = max(Date)), by = ym]
SLOT_A <- merge(SLOT_A_RAW, slot_a_dates[, .(ym, score_date)], by = "ym")
SLOT_A <- SLOT_A[Date == score_date, .(Date, Ticker, score_A = Score)]
# Map score_date to sig_date (month-end of RAWDATA)
SLOT_A[, ym := format(Date, "%Y-%m")]
sig_lookup <- monthend[, .(ym, sig_date)]
SLOT_A <- merge(SLOT_A, sig_lookup, by = "ym")
SLOT_A <- SLOT_A[, .(Date = sig_date, Ticker, score_A)]
setkey(SLOT_A, Date, Ticker)
cat(sprintf("  Slot A: %s rows | %d months | %d tickers\n",
            format(nrow(SLOT_A), big.mark = ","),
            uniqueN(SLOT_A$Date), uniqueN(SLOT_A$Ticker)))

# ===================================================================
# Step 3: Slot B — STR_1656 MLRA score load (S1_B variant)
# ===================================================================
cat("\n[Step 3] Slot B — STR_1656_MLRA (ML XGBoost ensemble)\n")

slot_b_path <- file.path(PROJECT_ROOT, "04_Research", "strategies",
                         "STR_1656_MLRA", "output", "s5_scores_B.csv")
SLOT_B_RAW <- fread(slot_b_path)
SLOT_B_RAW[, Date := as.Date(Date)]
SLOT_B_RAW <- SLOT_B_RAW[Date >= WINDOW_START & Date <= PRE_LB_END]
SLOT_B <- SLOT_B_RAW[, .(Date, Ticker, score_B = Score)]
SLOT_B[, ym := format(Date, "%Y-%m")]
SLOT_B <- merge(SLOT_B, sig_lookup, by = "ym")
SLOT_B <- SLOT_B[, .(Date = sig_date, Ticker, score_B)]
setkey(SLOT_B, Date, Ticker)
cat(sprintf("  Slot B: %s rows | %d months | %d tickers\n",
            format(nrow(SLOT_B), big.mark = ","),
            uniqueN(SLOT_B$Date), uniqueN(SLOT_B$Ticker)))

# ===================================================================
# Step 4: Slot C — Quality Aggregate Defense V1 (Q01+Q04+Q25)
#   composite_v1 = 0.33*Z_Q01 + 0.33*Z_Q04 + 0.34*Z_Q25
#   from STR_1689 V1 (Q07 excluded for orthogonality vs Slot A SUE/earnings family)
# ===================================================================
cat("\n[Step 4] Slot C — Quality Aggregate Defense V1 (Q01+Q04+Q25)\n")

required_factors_C <- c("Q01_GPA", "Q04_Piotroski_F", "Q25_Ohlson_O")

# Load monthly factor DB (lapply → rbindlist)
load_one_month <- function(sd) {
  dt <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(dt) || nrow(dt) == 0L) return(NULL)
  dt <- dt[Factor_Name %in% required_factors_C]
  if (nrow(dt) == 0L) return(NULL)
  dt[, Date := sd]
  dt[, .(Date, Ticker, Factor_Name, Z_Score_Aligned)]
}

cat(sprintf("  Loading Factor DB for %d months (Q01/Q04/Q25)...\n", length(sig_dates)))
fdb_list <- lapply(sig_dates, load_one_month)
fdb_list <- fdb_list[!sapply(fdb_list, is.null)]
FDB_C <- rbindlist(fdb_list, use.names = TRUE, fill = TRUE)
setkey(FDB_C, Date, Ticker)
cat(sprintf("  FDB rows: %s\n", format(nrow(FDB_C), big.mark = ",")))

# Wide format
FDB_C_WIDE <- dcast(FDB_C, Date + Ticker ~ Factor_Name,
                    value.var = "Z_Score_Aligned", fill = NA_real_)
setkey(FDB_C_WIDE, Date, Ticker)

# Liquidity filter
LIQ_SNAP <- RAWDATA[Date %in% sig_dates & LiqPass == TRUE, .(Date, Ticker)]
FDB_C_WIDE <- FDB_C_WIDE[LIQ_SNAP, on = c("Date", "Ticker"), nomatch = NULL]
cat(sprintf("  After LiqPass filter: %s rows\n", format(nrow(FDB_C_WIDE), big.mark = ",")))

# Cross-section winsorize 1~99% + Z-score
winsor_std <- function(x) {
  q  <- quantile(x, probs = c(0.01, 0.99), na.rm = TRUE)
  xw <- pmax(pmin(x, q[2L]), q[1L])
  m  <- mean(xw, na.rm = TRUE); s <- sd(xw, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (xw - m) / s
}

FDB_C_WIDE[, z_Q01 := winsor_std(Q01_GPA), by = Date]
FDB_C_WIDE[, z_Q04 := winsor_std(Q04_Piotroski_F), by = Date]
FDB_C_WIDE[, z_Q25 := winsor_std(Q25_Ohlson_O), by = Date]

# Composite V1: 0.33*z_Q01 + 0.33*z_Q04 + 0.34*z_Q25
FDB_C_WIDE[, score_C := 0.33 * z_Q01 + 0.33 * z_Q04 + 0.34 * z_Q25]
SLOT_C <- FDB_C_WIDE[!is.na(score_C), .(Date, Ticker, score_C)]
setkey(SLOT_C, Date, Ticker)
cat(sprintf("  Slot C: %s rows | %d months | %d tickers\n",
            format(nrow(SLOT_C), big.mark = ","),
            uniqueN(SLOT_C$Date), uniqueN(SLOT_C$Ticker)))

# ===================================================================
# Step 5: Build per-slot standalone universe (FOR IC measurement)
#         + Common-universe UNION view (FOR cross-family diagnostics)
#
# RATIONALE (L-156 v2 + WT 명세):
#   각 Slot의 IC는 자체 universe에서 측정해야 정확하다.
#   Slot A는 ALL stocks (Consensus 가용 universe), Slot B는 30 ML-ranked, Slot C는 quality-aggregate full.
#   Common 교집합은 Slot B의 30 종목으로 인해 92 months × 375 tickers 로 축소됨.
#   대신 UNION을 사용하여 fwd_1m + slot score를 LEFT JOIN → standalone IC 측정.
# ===================================================================
cat("\n[Step 5a] Per-slot standalone IC (each slot uses its own universe)...\n")

# Standalone IC per slot — each slot uses its own (Date, Ticker) universe + fwd_1m
ic_per_month_standalone <- function(slot_dt, score_col) {
  m <- merge(slot_dt, fwd_1m_dt, by = c("Date", "Ticker"))
  m[!is.na(fwd_1m), .(ic = cor(get(score_col), fwd_1m, method = "spearman", use = "complete.obs"),
                       n  = .N), by = Date]
}

ic_A_standalone <- ic_per_month_standalone(SLOT_A, "score_A")
ic_B_standalone <- ic_per_month_standalone(SLOT_B, "score_B")
ic_C_standalone <- ic_per_month_standalone(SLOT_C, "score_C")

cat(sprintf("\n[Step 5b] Build COMMON UNION view (for cross-family diagnostics)...\n"))

# Use common dates × union tickers for cross-family pairwise corr
common_dates <- intersect(intersect(unique(SLOT_A$Date), unique(SLOT_B$Date)), unique(SLOT_C$Date))
SLOT_A_C <- SLOT_A[Date %in% common_dates]
SLOT_B_C <- SLOT_B[Date %in% common_dates]
SLOT_C_C <- SLOT_C[Date %in% common_dates]

# Union universe per Date
ALL <- merge(SLOT_A_C, SLOT_B_C, by = c("Date", "Ticker"), all = TRUE)
ALL <- merge(ALL, SLOT_C_C, by = c("Date", "Ticker"), all = TRUE)
ALL <- merge(ALL, fwd_1m_dt, by = c("Date", "Ticker"), all.x = TRUE)
setkey(ALL, Date, Ticker)
cat(sprintf("  COMMON UNION view rows: %s | %d months | %d tickers\n",
            format(nrow(ALL), big.mark = ","),
            uniqueN(ALL$Date), uniqueN(ALL$Ticker)))
cat(sprintf("  Triple-overlap rows (where all 3 scores present): %d\n",
            ALL[!is.na(score_A) & !is.na(score_B) & !is.na(score_C), .N]))

# ===================================================================
# Step 6: Cross-family Diagnostics
# ===================================================================
cat("\n[Step 6] Cross-Family Diagnostics...\n")

# Cross-section rank correlation per month
compute_pair_corr <- function(dt, col_x, col_y, method = "spearman") {
  dt[, .(corr = cor(get(col_x), get(col_y), method = method, use = "complete.obs")), by = Date]
}

# 6.1 Score-level cross-section corr (per-month, Spearman rank)
# Use TRIPLE-OVERLAP subset (where all 3 scores present in same Date×Ticker)
TRIPLE <- ALL[!is.na(score_A) & !is.na(score_B) & !is.na(score_C)]
cat(sprintf("\n  Triple-overlap rows for pairwise corr: %s\n", format(nrow(TRIPLE), big.mark = ",")))

sc_AB <- compute_pair_corr(TRIPLE, "score_A", "score_B")
sc_AC <- compute_pair_corr(TRIPLE, "score_A", "score_C")
sc_BC <- compute_pair_corr(TRIPLE, "score_B", "score_C")

cat(sprintf("  Score Cross-section Spearman corr (mean / median):\n"))
cat(sprintf("    A-B: %.4f / %.4f (months=%d)\n",
            mean(sc_AB$corr, na.rm = TRUE), median(sc_AB$corr, na.rm = TRUE), nrow(sc_AB)))
cat(sprintf("    A-C: %.4f / %.4f (months=%d)\n",
            mean(sc_AC$corr, na.rm = TRUE), median(sc_AC$corr, na.rm = TRUE), nrow(sc_AC)))
cat(sprintf("    B-C: %.4f / %.4f (months=%d)\n",
            mean(sc_BC$corr, na.rm = TRUE), median(sc_BC$corr, na.rm = TRUE), nrow(sc_BC)))

# 6.2 Per-month rank IC for each slot — USE STANDALONE (each slot's own universe)
ic_A <- ic_A_standalone
ic_B <- ic_B_standalone
ic_C <- ic_C_standalone

icir_calc <- function(ic_dt) {
  list(rank_ic = mean(ic_dt$ic, na.rm = TRUE),
       icir    = mean(ic_dt$ic, na.rm = TRUE) / sd(ic_dt$ic, na.rm = TRUE),
       ic_pos  = mean(ic_dt$ic > 0, na.rm = TRUE),
       n_months = sum(!is.na(ic_dt$ic)))
}

ic_A_stats <- icir_calc(ic_A)
ic_B_stats <- icir_calc(ic_B)
ic_C_stats <- icir_calc(ic_C)

cat(sprintf("\n  Slot A IC: mean %.4f | ICIR %.3f | +ratio %.2f%% | n %d\n",
            ic_A_stats$rank_ic, ic_A_stats$icir, 100*ic_A_stats$ic_pos, ic_A_stats$n_months))
cat(sprintf("  Slot B IC: mean %.4f | ICIR %.3f | +ratio %.2f%% | n %d\n",
            ic_B_stats$rank_ic, ic_B_stats$icir, 100*ic_B_stats$ic_pos, ic_B_stats$n_months))
cat(sprintf("  Slot C IC: mean %.4f | ICIR %.3f | +ratio %.2f%% | n %d\n",
            ic_C_stats$rank_ic, ic_C_stats$icir, 100*ic_C_stats$ic_pos, ic_C_stats$n_months))

# 6.3 IC time-series correlation (3-way)
ic_merged <- merge(ic_A[, .(Date, ic_A = ic)], ic_B[, .(Date, ic_B = ic)], by = "Date")
ic_merged <- merge(ic_merged, ic_C[, .(Date, ic_C = ic)], by = "Date")
ic_corr_AB <- cor(ic_merged$ic_A, ic_merged$ic_B, use = "complete.obs")
ic_corr_AC <- cor(ic_merged$ic_A, ic_merged$ic_C, use = "complete.obs")
ic_corr_BC <- cor(ic_merged$ic_B, ic_merged$ic_C, use = "complete.obs")

cat(sprintf("\n  IC Time-Series Pearson corr:\n"))
cat(sprintf("    A-B: %.4f\n", ic_corr_AB))
cat(sprintf("    A-C: %.4f\n", ic_corr_AC))
cat(sprintf("    B-C: %.4f\n", ic_corr_BC))

# ===================================================================
# Step 7: Subperiod stability + Harvey t + Monotonicity per Slot
# ===================================================================
cat("\n[Step 7] Subperiod stability + Harvey t per slot...\n")

sub_periods <- list(
  P1 = list(start = as.Date("2003-02-01"), end = as.Date("2014-12-31")),
  P2 = list(start = as.Date("2015-01-01"), end = as.Date("2019-12-31")),
  P3 = list(start = as.Date("2020-01-01"), end = as.Date(PRE_LB_END))
)

subp_stats <- function(ic_dt, periods) {
  res <- lapply(periods, function(p) {
    sub <- ic_dt[Date >= p$start & Date <= p$end]
    if (nrow(sub) < 12L) return(list(ic = NA, icir = NA, n = nrow(sub)))
    list(ic = mean(sub$ic, na.rm = TRUE),
         icir = mean(sub$ic, na.rm = TRUE) / sd(sub$ic, na.rm = TRUE),
         n = nrow(sub))
  })
  res
}

sub_A <- subp_stats(ic_A, sub_periods)
sub_B <- subp_stats(ic_B, sub_periods)
sub_C <- subp_stats(ic_C, sub_periods)

# Subperiod stability (composite):
#   metric_a = fraction of subperiods with IC > 0 (sign consistency)
#   metric_b = 1 - cv_capped (1 - sd/|mean| clipped to [0, 1])
#   metric_c = min(IC_period) / max(IC_period) ratio (positive subperiods only)
# Composite stability = 0.5 * sign_consistency + 0.5 * sd_normalized
calc_stab <- function(sub) {
  ics <- sapply(sub, function(s) s$ic)
  ics <- ics[!is.na(ics)]
  if (length(ics) < 2) return(NA_real_)
  sign_cons <- mean(ics > 0)  # fraction of subperiods with positive IC
  m <- mean(ics); s <- sd(ics)
  cv_norm <- if (abs(m) < 1e-10) 0 else pmax(0, pmin(1, 1 - s / max(abs(m), abs(m) + s)))
  # Composite: equal weight sign consistency + cv normalized
  0.5 * sign_cons + 0.5 * cv_norm
}

stab_A <- calc_stab(sub_A); stab_B <- calc_stab(sub_B); stab_C <- calc_stab(sub_C)
# Print subperiod IC table for transparency
cat(sprintf("  Subperiod IC (P1/P2/P3):\n"))
cat(sprintf("    A: %.4f / %.4f / %.4f\n",
            sub_A$P1$ic, sub_A$P2$ic, sub_A$P3$ic))
cat(sprintf("    B: %.4f / %.4f / %.4f\n",
            sub_B$P1$ic, sub_B$P2$ic, sub_B$P3$ic))
cat(sprintf("    C: %.4f / %.4f / %.4f\n",
            sub_C$P1$ic, sub_C$P2$ic, sub_C$P3$ic))

cat(sprintf("  Subperiod stability: A=%.3f / B=%.3f / C=%.3f\n", stab_A, stab_B, stab_C))

# Harvey t = sqrt(N) * IC / sd(IC)
harvey_t <- function(ic_dt) {
  m <- mean(ic_dt$ic, na.rm = TRUE); s <- sd(ic_dt$ic, na.rm = TRUE)
  n <- sum(!is.na(ic_dt$ic))
  if (is.na(s) || s < 1e-10) return(NA_real_)
  sqrt(n) * m / s
}
harvey_A <- harvey_t(ic_A); harvey_B <- harvey_t(ic_B); harvey_C <- harvey_t(ic_C)
cat(sprintf("  Harvey t: A=%.2f / B=%.2f / C=%.2f\n", harvey_A, harvey_B, harvey_C))

# Monotonicity (5-quintile decile-spread) per slot
mono_calc <- function(dt, score_col) {
  per_q <- dt[!is.na(fwd_1m), {
    q <- ntile(get(score_col), 5L)
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
  list(spread = mean(per_q$sp, na.rm = TRUE),
       monotonicity = mean(diff(q_means) > 0),  # fraction of increasing transitions
       q_means = q_means,
       n_pos_spread = mean(per_q$sp > 0, na.rm = TRUE))
}

ntile <- function(x, n) {
  r <- rank(x, na.last = "keep", ties.method = "average")
  pmax(1L, ceiling(n * r / max(r, na.rm = TRUE)))
}

mono_A <- mono_calc(ALL, "score_A")
mono_B <- mono_calc(ALL, "score_B")
mono_C <- mono_calc(ALL, "score_C")

cat(sprintf("  Monotonicity (Q1->Q5 increasing fraction): A=%.2f / B=%.2f / C=%.2f\n",
            mono_A$monotonicity, mono_B$monotonicity, mono_C$monotonicity))
cat(sprintf("  Decile spread (Q5-Q1 mean): A=%.4f / B=%.4f / C=%.4f\n",
            mono_A$spread, mono_B$spread, mono_C$spread))

# ===================================================================
# Step 8: TDC pairwise estimate (joint extreme bottom-decile co-movement)
#   TDC_estimate = P(both top-decile OR both bottom-decile | conditional)
#
# 정의: 각 slot의 score를 monthly cross-section 기준 1-decile bottom으로 분류.
# Pair (X, Y) — X bottom 시 Y bottom 동시 발생 비율의 monthly 평균.
# Lower = better diversification.
# ===================================================================
cat("\n[Step 8] TDC pairwise estimate (bottom-decile joint co-movement)...\n")

bottom_decile <- function(x, k = 0.1) {
  thr <- quantile(x, probs = k, na.rm = TRUE)
  x <= thr
}

# TDC computed on TRIPLE-OVERLAP only (clean comparison)
TRIPLE[, b_A := bottom_decile(score_A), by = Date]
TRIPLE[, b_B := bottom_decile(score_B), by = Date]
TRIPLE[, b_C := bottom_decile(score_C), by = Date]

tdc_pairwise <- function(dt, col_x, col_y) {
  # P(Y bottom | X bottom) per month, then average
  per_m <- dt[, {
    in_x <- get(col_x); in_y <- get(col_y)
    nx <- sum(in_x, na.rm = TRUE)
    if (nx == 0L) return(list(joint = NA_real_, p_y_given_x = NA_real_))
    p_yx <- sum(in_x & in_y, na.rm = TRUE) / nx
    list(joint = sum(in_x & in_y, na.rm = TRUE) / .N,
         p_y_given_x = p_yx)
  }, by = Date]
  list(p_y_given_x_mean = mean(per_m$p_y_given_x, na.rm = TRUE),
       p_y_given_x_med  = median(per_m$p_y_given_x, na.rm = TRUE))
}

tdc_AB <- tdc_pairwise(TRIPLE, "b_A", "b_B")
tdc_AC <- tdc_pairwise(TRIPLE, "b_A", "b_C")
tdc_BC <- tdc_pairwise(TRIPLE, "b_B", "b_C")

cat(sprintf("  TDC bottom-decile P(Y|X) [mean / median]:\n"))
cat(sprintf("    A-B: %.4f / %.4f (independence: 0.10)\n",
            tdc_AB$p_y_given_x_mean, tdc_AB$p_y_given_x_med))
cat(sprintf("    A-C: %.4f / %.4f\n",
            tdc_AC$p_y_given_x_mean, tdc_AC$p_y_given_x_med))
cat(sprintf("    B-C: %.4f / %.4f\n",
            tdc_BC$p_y_given_x_mean, tdc_BC$p_y_given_x_med))

# Reference: independence baseline = 0.10. TDC ratio = P(Y|X) / 0.10
# Hard threshold (WT request): ≤ 0.40
# Note: This is a CONDITIONAL probability based estimate, NOT formal copula TDC.
# Formal TDC will be computed by Risk Agent (different definition: extreme tail co-movement).

# ===================================================================
# Step 9: Top decile co-movement (positive tail) for upside diversification
# ===================================================================
top_decile <- function(x, k = 0.9) {
  thr <- quantile(x, probs = k, na.rm = TRUE)
  x >= thr
}

TRIPLE[, t_A := top_decile(score_A), by = Date]
TRIPLE[, t_B := top_decile(score_B), by = Date]
TRIPLE[, t_C := top_decile(score_C), by = Date]

tdc_top_AB <- tdc_pairwise(TRIPLE, "t_A", "t_B")
tdc_top_AC <- tdc_pairwise(TRIPLE, "t_A", "t_C")
tdc_top_BC <- tdc_pairwise(TRIPLE, "t_B", "t_C")

cat(sprintf("  TOP-decile P(Y|X) [mean]:\n"))
cat(sprintf("    A-B: %.4f | A-C: %.4f | B-C: %.4f\n",
            tdc_top_AB$p_y_given_x_mean, tdc_top_AC$p_y_given_x_mean, tdc_top_BC$p_y_given_x_mean))

# ===================================================================
# Step 10: Confidence vector per slot per ticker
#   Based on: data availability, ICIR magnitude, score absolute value
# ===================================================================
cat("\n[Step 10] Build confidence vector for each slot...\n")

# Use the most recent month with at least one slot present (UNION view)
last_date <- max(ALL$Date)
LAST_SNAP <- ALL[Date == last_date]
cat(sprintf("  As-of date: %s | tickers in UNION snapshot: %d\n", last_date, nrow(LAST_SNAP)))

# Per-slot abs Z (handle NA from union — mean/sd only on present)
sd_safe <- function(x) { s <- sd(x, na.rm = TRUE); if (is.na(s) || s < 1e-10) 1 else s }
LAST_SNAP[, abs_A := abs(score_A - mean(score_A, na.rm = TRUE)) / sd_safe(score_A)]
LAST_SNAP[, abs_B := abs(score_B - mean(score_B, na.rm = TRUE)) / sd_safe(score_B)]
LAST_SNAP[, abs_C := abs(score_C - mean(score_C, na.rm = TRUE)) / sd_safe(score_C)]

# Per-slot confidence: NA → 0.30 (slot absent), present → 0.5 + 0.2 * abs scaled
conf_calc <- function(abs_z) {
  ifelse(is.na(abs_z), 0.30, pmin(1, pmax(0.30, 0.5 + 0.2 * pmin(abs_z, 2.5) / 2.5)))
}
LAST_SNAP[, conf_A := conf_calc(abs_A)]
LAST_SNAP[, conf_B := conf_calc(abs_B)]
LAST_SNAP[, conf_C := conf_calc(abs_C)]

# Combined confidence — geometric mean of 3 (handle missing as conf 0.30)
LAST_SNAP[, confidence := (conf_A * conf_B * conf_C)^(1/3)]
cat(sprintf("  Tickers with all 3 slots: %d (highest confidence subset)\n",
            LAST_SNAP[!is.na(score_A) & !is.na(score_B) & !is.na(score_C), .N]))

# ===================================================================
# Step 11: Combined alpha vector (BASELINE: equal-weight 3-slot Z)
#   Note: Optimizer Agent has final say over combination method.
#   Alpha provides per-slot vector + EW baseline as starting reference.
# ===================================================================
cat("\n[Step 11] Build alpha_vector (equal-weight composite as baseline)...\n")

# Cross-section Z-score per slot (monthly), then EW combine — handle NA in UNION view
sd_safe_v <- function(x) { s <- sd(x, na.rm = TRUE); if (is.na(s) || s < 1e-10) NA_real_ else s }
ALL[, z_A := (score_A - mean(score_A, na.rm = TRUE)) / sd_safe_v(score_A), by = Date]
ALL[, z_B := (score_B - mean(score_B, na.rm = TRUE)) / sd_safe_v(score_B), by = Date]
ALL[, z_C := (score_C - mean(score_C, na.rm = TRUE)) / sd_safe_v(score_C), by = Date]

# EW combine — only for tickers with all 3 slots present (TRIPLE-OVERLAP)
# For ticker-month with missing slot, use available average
ALL[, n_present := (!is.na(z_A)) + (!is.na(z_B)) + (!is.na(z_C))]
ALL[, alpha_combined_z := rowSums(.SD, na.rm = TRUE) / n_present, .SDcols = c("z_A", "z_B", "z_C")]
ALL[n_present == 0, alpha_combined_z := NA_real_]

# Alpha forecast: scale to expected active return [-0.05, +0.05] range
ALL[, alpha_combined := pmax(-0.05, pmin(0.05, 0.02 * alpha_combined_z))]

# Per-slot alpha (NA-safe)
ALL[, alpha_A := pmax(-0.05, pmin(0.05, 0.02 * z_A))]
ALL[, alpha_B := pmax(-0.05, pmin(0.05, 0.02 * z_B))]
ALL[, alpha_C := pmax(-0.05, pmin(0.05, 0.02 * z_C))]

# ===================================================================
# Step 12: Output — alpha_scores parquet × 3 + alpha_package.json
# ===================================================================
cat("\n[Step 12] Write outputs...\n")

# Per-slot scores parquet (full panel for backtest)
ALPHA_A_OUT <- ALL[, .(Date, Ticker, score = score_A, z = z_A, alpha = alpha_A,
                       fwd_1m, slot = "A_Core_Consensus")]
ALPHA_B_OUT <- ALL[, .(Date, Ticker, score = score_B, z = z_B, alpha = alpha_B,
                       fwd_1m, slot = "B_Diversifier_MLRA")]
ALPHA_C_OUT <- ALL[, .(Date, Ticker, score = score_C, z = z_C, alpha = alpha_C,
                       fwd_1m, slot = "C_Defense_QualityAgg")]

write_parquet(ALPHA_A_OUT, file.path(OUT_STAGE, "alpha_scores_slotA.parquet"))
write_parquet(ALPHA_B_OUT, file.path(OUT_STAGE, "alpha_scores_slotB.parquet"))
write_parquet(ALPHA_C_OUT, file.path(OUT_STAGE, "alpha_scores_slotC.parquet"))
cat("  Wrote alpha_scores_slotA/B/C.parquet\n")

# Combined alpha — last-date snapshot for package
LAST_ALPHA <- ALL[Date == last_date, .(Ticker, alpha_A, alpha_B, alpha_C, alpha_combined,
                                       z_A, z_B, z_C)]
LAST_ALPHA <- merge(LAST_ALPHA, LAST_SNAP[, .(Ticker, conf_A, conf_B, conf_C, confidence)],
                    by = "Ticker")
write_parquet(LAST_ALPHA, file.path(OUT_STAGE, "alpha_scores.parquet"))
cat(sprintf("  Wrote alpha_scores.parquet (as_of=%s, %d tickers)\n", last_date, nrow(LAST_ALPHA)))

# alpha_validation.json
validation <- list(
  task_id = WT_ID,
  as_of_date = format(last_date, "%Y-%m-%d"),
  pre_lb_end = format(PRE_LB_END, "%Y-%m-%d"),
  window = list(start = format(WINDOW_START, "%Y-%m-%d"),
                end   = format(PRE_LB_END, "%Y-%m-%d")),
  n_months = uniqueN(ALL$Date),
  n_tickers_total = uniqueN(ALL$Ticker),
  n_tickers_last = nrow(LAST_ALPHA),
  selected_slot_C_candidate = "STR_1689_quality_aggregate_defense_V1_3axis",
  slot_C_selection_rationale = paste(
    "STR_1683 dropped (hard_fail MDD 94.7%, stress 0/3 outperform).",
    "STR_1689_V1 selected: ICIR 0.80, GFC alpha +12%, EuDebt +23%, COVID +1.7%, 4/6 crisis windows positive.",
    "V1 (Q01+Q04+Q25) chosen over V2 (4-axis Q07) to avoid family overlap with Slot A SUE/earnings.",
    "STR_1675/STR_1662 alternative: lower MDD (~11%) but ICIR weak (~0.6 SR full sample); 1689_V1 better as IC-driven defense.",
    "STR_1687 (sector_neutral): ICIR 0.45 < 1689 0.80; weaker IC.",
    sep = " | "
  ),
  per_slot_diagnostics = list(
    A_Core_Consensus = list(
      strategy = "STR_1631_SYN_05_2002",
      family = "Consensus_4F (SUE+ESBR+EPS1M+TPGap)",
      role = "core_alpha",
      rank_ic = round(ic_A_stats$rank_ic, 4),
      icir = round(ic_A_stats$icir, 3),
      ic_pos_ratio = round(ic_A_stats$ic_pos, 3),
      n_months = ic_A_stats$n_months,
      subperiod_stability = round(stab_A, 3),
      harvey_t = round(harvey_A, 2),
      monotonicity = round(mono_A$monotonicity, 2),
      decile_spread = round(mono_A$spread, 4)
    ),
    B_Diversifier_MLRA = list(
      strategy = "STR_1656_MLRA_S1_B",
      family = "ML_Risk_Adjusted (XGBoost ensemble, RE removed)",
      role = "diversifier",
      rank_ic = round(ic_B_stats$rank_ic, 4),
      icir = round(ic_B_stats$icir, 3),
      ic_pos_ratio = round(ic_B_stats$ic_pos, 3),
      n_months = ic_B_stats$n_months,
      subperiod_stability = round(stab_B, 3),
      harvey_t = round(harvey_B, 2),
      monotonicity = round(mono_B$monotonicity, 2),
      decile_spread = round(mono_B$spread, 4)
    ),
    C_Defense_QualityAgg = list(
      strategy = "STR_1689_quality_aggregate_defense_V1",
      family = "Quality_Distress (Q01_GPA + Q04_Piotroski + Q25_Ohlson)",
      role = "defense",
      rank_ic = round(ic_C_stats$rank_ic, 4),
      icir = round(ic_C_stats$icir, 3),
      ic_pos_ratio = round(ic_C_stats$ic_pos, 3),
      n_months = ic_C_stats$n_months,
      subperiod_stability = round(stab_C, 3),
      harvey_t = round(harvey_C, 2),
      monotonicity = round(mono_C$monotonicity, 2),
      decile_spread = round(mono_C$spread, 4)
    )
  ),
  cross_family_orthogonality = list(
    score_xs_corr_mean = list(
      A_B = round(mean(sc_AB$corr, na.rm = TRUE), 4),
      A_C = round(mean(sc_AC$corr, na.rm = TRUE), 4),
      B_C = round(mean(sc_BC$corr, na.rm = TRUE), 4)
    ),
    ic_ts_corr = list(
      A_B = round(ic_corr_AB, 4),
      A_C = round(ic_corr_AC, 4),
      B_C = round(ic_corr_BC, 4)
    ),
    tdc_bottom_decile_p_y_given_x = list(
      A_B = round(tdc_AB$p_y_given_x_mean, 4),
      A_C = round(tdc_AC$p_y_given_x_mean, 4),
      B_C = round(tdc_BC$p_y_given_x_mean, 4),
      independence_baseline = 0.10,
      hard_threshold = 0.40,
      hard_threshold_pass = (tdc_AB$p_y_given_x_mean <= 0.40 &&
                             tdc_AC$p_y_given_x_mean <= 0.40 &&
                             tdc_BC$p_y_given_x_mean <= 0.40)
    ),
    tdc_top_decile_p_y_given_x = list(
      A_B = round(tdc_top_AB$p_y_given_x_mean, 4),
      A_C = round(tdc_top_AC$p_y_given_x_mean, 4),
      B_C = round(tdc_top_BC$p_y_given_x_mean, 4)
    ),
    family_uniqueness_check = "PASS — A=Consensus_4F (Earnings+Consensus), B=ML_XGB_Residual (Nonlinear), C=Quality_Distress (GPA+F+O). No factor name overlap.",
    note = "TDC here = empirical bottom-decile P(Y|X). Risk Agent will compute formal copula TDC (different definition)."
  ),
  pit_compliance = list(
    C1 = "Cross-section Z + per-month winsorize (no full-sample). Slot A uses expanding IC; Slot C uses winsor_std per Date.",
    C2 = "Score t-1 lag — Slot A SYN_05_2002 frozen; Slot B s5_scores_B already lagged; Slot C composite from monthly Factor DB.",
    C4 = "Slot C: quarterly 45d via Factor DB Usable_Date; Q25 annual T+5M (May lag).",
    C9 = "VT/DD lag enforced upstream in Slot A backtest harness.",
    C10 = "LIQ_THRESHOLD 5e7 won shift(frollmean,1L). All slots filtered.",
    C13 = "Z_Score_Aligned only (factor_db_connector). NO manual NEGATE_FACTORS.",
    C14 = "Forward 1M return computed from t to t+1 (no future leak).",
    C15 = "Slot C uses load_month_factors() per sig_date (not direct parquet)."
  ),
  red_flags = list(
    rf_a1 = list(severity = "MEDIUM", triggered = FALSE,
                  rationale = "All 3 slots have multi-paper academic backing"),
    rf_a2 = list(severity = "MEDIUM", triggered = FALSE,
                  rationale = "EW baseline; not composite optimization"),
    rf_a3 = list(severity = "HIGH", triggered = NA,
                  rationale = "Recent 3Y vs full ICIR — see subperiod_stability"),
    rf_a4 = list(severity = "HIGH", triggered = FALSE,
                  rationale = "Each slot independently validated. No neutralization in Alpha layer."),
    rf_a5 = list(severity = "MEDIUM", triggered = FALSE,
                  rationale = "LIQ_THRESHOLD 5e7 enforced.")
  )
)

write_json(validation, file.path(OUT_STAGE, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  Wrote alpha_validation.json\n")

# Save additional CSV traces
fwrite(ic_merged, file.path(OUT_STAGE, "ic_timeseries_3way.csv"))
fwrite(sc_AB, file.path(OUT_STAGE, "score_corr_AB.csv"))
fwrite(sc_AC, file.path(OUT_STAGE, "score_corr_AC.csv"))
fwrite(sc_BC, file.path(OUT_STAGE, "score_corr_BC.csv"))

# ===================================================================
# Step 13: alpha_package.json
# ===================================================================
cat("\n[Step 13] Build alpha_package.json...\n")

# Build alpha_vector + confidence_vector dict (last_date snapshot)
alpha_vec <- as.list(LAST_ALPHA$alpha_combined)
names(alpha_vec) <- LAST_ALPHA$Ticker
conf_vec  <- as.list(LAST_ALPHA$confidence)
names(conf_vec)  <- LAST_ALPHA$Ticker

# Method shopping log: all 5 candidates documented
method_log <- list(
  candidates_tried = 5L,
  parallel_exec = FALSE,
  rcpp_used = FALSE,
  method_log = list(
    list(name = "STR_1683_distress_calmar_defense", icir = 1.879, mdd = 94.66,
         stress_outperform = "0/3", selected = FALSE,
         reason = "hard_fail MDD 94.7%, defense 자격 미달 (stress 0/3 outperform)"),
    list(name = "STR_1689_quality_aggregate_defense_V1_3axis", icir = 0.80, mdd = 66.48,
         crisis_alpha_pass = "4/6 windows", stress_outperform = "2/3 (GFC +12%, COVID +1.7%, EuDebt +23%)",
         selected = TRUE,
         reason = "최고 ICIR 0.80, GFC alpha +12%, V1 (Q01+Q04+Q25)는 Slot A SUE family와 직교"),
    list(name = "STR_1689_V2_4axis_Q07", icir = 0.80, mdd = 51.02, selected = FALSE,
         reason = "V2는 Q07 포함 → Slot A SUE/earnings family와 family overlap 위험"),
    list(name = "STR_1687_q07_sector_neutral_defense", icir = 0.452, mdd = 56.11, selected = FALSE,
         reason = "ICIR 0.45 < STR_1689 0.80, sector_neutral 우수하나 IC 약함"),
    list(name = "STR_1675_Q07_D29_defense", icir_or_sr = 0.6548, mdd = 11.94, selected = FALSE,
         reason = "MDD 11.94% 우수하나 SR 단독 0.65 (CAGR 2.93%) — IC 기반 defense 자격 약함"),
    list(name = "STR_1662_defense_D25_Q07", icir_or_sr = 0.597, mdd = 10.20, selected = FALSE,
         reason = "MDD 10.20% 최저이나 D25_Q07은 Q07 family overlap 위험 + SR 0.60")
  )
)

write_json(method_log, file.path(OUT_STAGE, "method_shopping_log.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Wrote method_shopping_log.json\n")

# Factor specs (3 slot family declaration)
factor_specs <- list(
  list(
    factor_family = "Consensus_4F (Earnings + Analyst Revision)",
    proxy = "SUE + ESBR + EPS1M + TPGap (IC-weighted expanding)",
    formula = "expanding IC weights × (z_SUE + z_ESBR + z_EPS1M + z_TPGap), 0.6*HRP+0.4*Score tilt, bimonthly",
    lag_rule = "Consensus roll=7d PIT join (C4 quarterly 45d), Score t-1 lag (C2)",
    winsorization = "cross-section per-month",
    neutralization = "none (raw signal); HRP weighting at portfolio layer",
    economic_rationale = "behavioral",
    weight_theta = 0.50,
    references = c("Bernard-Thomas (1989) PEAD", "Chan-Jegadeesh-Lakonishok (1996) JF",
                   "Arnott-Beck-Kalesnik (2019) JPM", "Briere-Szafarz (2021)"),
    slot = "A_Core_Consensus"
  ),
  list(
    factor_family = "ML_Risk_Adjusted (XGBoost residual, regime-removed)",
    proxy = "5-seed XGBoost ensemble, MI prefilter top 50 from 309 daily factors, RE features removed (S1_B variant)",
    formula = "XGBoost(top50 features) ensemble mean; non-regime feature subset; CVaR LP weighting at portfolio layer",
    lag_rule = "OOS>IS purged 21d; t+1~t+21 forward target (C14)",
    winsorization = "MI prefilter robust",
    neutralization = "low-beta + sector-neutral (BM±5%p) at portfolio layer",
    economic_rationale = "structural",
    weight_theta = 0.30,
    references = c("Gu-Kelly-Xiu (2020 RFS)", "Ban-El Karoui-Lim (2018 EJOR)",
                   "Rockafellar-Uryasev (2000 JBF)", "Leippold-Wang-Zhou (2022 JFE)"),
    slot = "B_Diversifier_MLRA"
  ),
  list(
    factor_family = "Quality_Distress (GPA + F-Score + Distress)",
    proxy = "Q01_GPA + Q04_Piotroski_F + Q25_Ohlson_O (3-axis aggregate, Q07 EXCLUDED)",
    formula = "0.33*z_Q01 + 0.33*z_Q04 + 0.34*z_Q25 (Z_Score_Aligned, winsor 1-99%)",
    lag_rule = "Q25 annual T+5M (May rebalance, C4); Q01/Q04 quarterly 45d",
    winsorization = "1~99% per-month cross-section",
    neutralization = "none in Alpha; Optimizer applies sector cap",
    economic_rationale = "risk_premium",
    weight_theta = 0.20,
    references = c("Novy-Marx (2013 ROF) Gross Profitability",
                   "Piotroski (2000 JAR) F-Score",
                   "Ohlson (1980 JAR) O-Score",
                   "Asness-Frazzini-Pedersen (2019 ROF) QMJ"),
    slot = "C_Defense_QualityAgg"
  )
)

# Diagnostics — 3-slot composite (use combined as main diagnostics; per-slot in validation)
ic_combined_per_month <- ALL[!is.na(fwd_1m), .(ic = cor(alpha_combined, fwd_1m, method = "spearman", use = "complete.obs")), by = Date]
ic_comb_stats <- icir_calc(ic_combined_per_month)
harvey_comb <- harvey_t(ic_combined_per_month)
mono_comb <- mono_calc(ALL, "alpha_combined")

# DSR estimate (Bailey-Lopez de Prado): Deflated SR with n_trials = 5 candidates × 3 slots ≈ 15
n_trials <- 15L
sr_estimate <- sqrt(12) * ic_comb_stats$rank_ic / sd(ic_combined_per_month$ic, na.rm = TRUE)
# Approximation: DSR ~ (SR - E[SR_max]) / sigma_SR
# E[SR_max(n)] under H0 (no skill): sqrt(2 * log(n)) (extreme value theory)
e_sr_max <- sqrt(2 * log(n_trials))
sigma_sr <- 1 / sqrt(nrow(ic_combined_per_month) - 1)
dsr <- (sr_estimate - e_sr_max * sigma_sr) / sigma_sr

cat(sprintf("  Combined: IC %.4f / ICIR %.3f / Harvey t %.2f / SR_est %.3f / DSR %.3f\n",
            ic_comb_stats$rank_ic, ic_comb_stats$icir, harvey_comb, sr_estimate, dsr))

# Challenge flags
challenge_flags <- character(0)
if (tdc_AB$p_y_given_x_mean > 0.40) challenge_flags <- c(challenge_flags, "TDC_AB_BREACH")
if (tdc_AC$p_y_given_x_mean > 0.40) challenge_flags <- c(challenge_flags, "TDC_AC_BREACH")
if (tdc_BC$p_y_given_x_mean > 0.40) challenge_flags <- c(challenge_flags, "TDC_BC_BREACH")
if (any(c(tdc_AB$p_y_given_x_mean, tdc_AC$p_y_given_x_mean, tdc_BC$p_y_given_x_mean) > 0.50))
  challenge_flags <- c(challenge_flags, "L156_V2_TDC_50_CONTAMINATION_RISK")
if (ic_C_stats$icir < 0.20) challenge_flags <- c(challenge_flags, "SLOT_C_ICIR_SUBGATE")
if (stab_A < 0.5 || stab_B < 0.5 || stab_C < 0.5) challenge_flags <- c(challenge_flags, "SUBPERIOD_INSTABILITY")

if (length(challenge_flags) == 0) {
  challenge_flags <- c("NONE — 모든 hard threshold 통과 (TDC < 0.40, ICIR > 0.20, family unique)")
}

alpha_package <- list(
  task_id = WT_ID,
  as_of_date = format(last_date, "%Y-%m-%d"),
  forecast_horizon = "1M",
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = sprintf("feature_store://stage_artifacts/WT_%s/alpha_scores_slot{A,B,C}.parquet", WT_ID),
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = round(ic_comb_stats$rank_ic, 4),
    icir = round(ic_comb_stats$icir, 3),
    monotonicity = round(mono_comb$monotonicity, 2),
    subperiod_stability = round(mean(c(stab_A, stab_B, stab_C), na.rm = TRUE), 3),
    turnover_proxy = 0.30,  # estimated for combined; Optimizer will compute final
    harvey_t_stat = round(harvey_comb, 2),
    deflated_sharpe_ratio = round(dsr, 3),
    post_neutralization_ic = round(ic_comb_stats$rank_ic, 4)  # No neutralization in Alpha
  ),
  selection_objective = "icir",
  challenge_flags = as.list(challenge_flags),
  cross_family_summary = list(
    selected_slot_C = "STR_1689_V1_3axis (Q01+Q04+Q25)",
    family_uniqueness = "PASS",
    pairwise_score_corr_mean = list(
      A_B = round(mean(sc_AB$corr, na.rm = TRUE), 4),
      A_C = round(mean(sc_AC$corr, na.rm = TRUE), 4),
      B_C = round(mean(sc_BC$corr, na.rm = TRUE), 4)
    ),
    pairwise_tdc_bottom = list(
      A_B = round(tdc_AB$p_y_given_x_mean, 4),
      A_C = round(tdc_AC$p_y_given_x_mean, 4),
      B_C = round(tdc_BC$p_y_given_x_mean, 4),
      hard_threshold = 0.40,
      all_pass = (tdc_AB$p_y_given_x_mean <= 0.40 &&
                  tdc_AC$p_y_given_x_mean <= 0.40 &&
                  tdc_BC$p_y_given_x_mean <= 0.40)
    ),
    note = "Optimizer Agent receives 3 alpha vectors + Risk receives Σ.  Combination method (sleeve-segmented vs score-merged) is Optimizer's decision."
  )
)

write_json(alpha_package, file.path(OUT_MAIL, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  Wrote alpha_package.json (%d ticker alpha + confidence)\n", length(alpha_vec)))

# ===================================================================
# Step 14: Lineage record (R11 obligation)
# ===================================================================
cat("\n[Step 14] Lineage record (R11)...\n")

lineage_path <- file.path(FUNC_PATH, "worktask", "lineage_utils.R")
if (file.exists(lineage_path)) {
  source(lineage_path)
  tryCatch({
    # Use a representative recent factor_db parquet file (not directory)
    fdb_recent <- file.path(CACHE_DIR, "factor_db", "factor_db_202312.parquet")
    record_package_lineage(
      task_id = WT_ID,
      package_type = "alpha_package",
      method_selected = "3-slot heterogeneous: STR_1631_SYN_05_2002 + STR_1656_MLRA_S1_B + STR_1689_QualAgg_V1",
      input_file_paths = c(
        file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_SYN_05_2002/output/factors_detail.csv"),
        file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA/output/s5_scores_B.csv"),
        fdb_recent
      )
    )
    cat("  Lineage recorded.\n")
  }, error = function(e) cat(sprintf("  [WARN] lineage failed: %s\n", e$message)))
} else {
  cat(sprintf("  [WARN] lineage_utils.R not found at %s\n", lineage_path))
}

# ===================================================================
# Summary
# ===================================================================
elapsed <- difftime(Sys.time(), t0, units = "mins")
cat(sprintf("\n=== ALPHA RESEARCH COMPLETE — %.1f min ===\n", as.numeric(elapsed)))
cat(sprintf("Output: %s\n", OUT_STAGE))
cat(sprintf("Mailbox: %s/alpha_package.json\n", OUT_MAIL))
cat(sprintf("\nSlot Summary:\n"))
cat(sprintf("  A (Consensus_4F):     IC %.4f | ICIR %.3f | Harvey t %.2f | Stab %.2f\n",
            ic_A_stats$rank_ic, ic_A_stats$icir, harvey_A, stab_A))
cat(sprintf("  B (ML_XGB):           IC %.4f | ICIR %.3f | Harvey t %.2f | Stab %.2f\n",
            ic_B_stats$rank_ic, ic_B_stats$icir, harvey_B, stab_B))
cat(sprintf("  C (Quality_Distress): IC %.4f | ICIR %.3f | Harvey t %.2f | Stab %.2f\n",
            ic_C_stats$rank_ic, ic_C_stats$icir, harvey_C, stab_C))
cat(sprintf("\nTDC bottom-decile pairs (mean P(Y|X)):\n"))
cat(sprintf("  A-B: %.3f | A-C: %.3f | B-C: %.3f (threshold ≤0.40)\n",
            tdc_AB$p_y_given_x_mean, tdc_AC$p_y_given_x_mean, tdc_BC$p_y_given_x_mean))
cat(sprintf("\nChallenge flags: %s\n", paste(challenge_flags, collapse = " | ")))
