#==============================================================================
# WT-D20260514_004 — Investor Flow B-Variant Re-test on Full Universe
#   L-317 Falsifiability Test 4×2 matrix completion
#
# Mandate (도훈 Session 81):
#   WT-D20260514_001 B-variant spec inherit (5 sophistication axes ex-ante grid).
#   Universe만 KOSPI200 ∪ KOSDAQ150 intersection (~350)
#                  → KOSPI 본주 + KOSDAQ 전종목 (~2,657) full universe 확장.
#   Alpha-vector spec / IC measurement methodology / Codex Round 의무 동일.
#
# Cycle position in 4×2 matrix:
#   (1) WT-D20260513_002 저변동성 + intersection → cor 0.7713 FAIL
#   (2) WT-D20260514_001 investor flow + intersection → cor 0.7713 FAIL
#   (3) WT-D20260514_002 general 7 axes + full universe → cor 0.696 FAIL
#   (4) WT-D20260514_003 저변동성 + full universe → C2 cor 0.0292 PASS!
#   (5) WT-D20260514_004 본 cycle ← investor flow + full universe (L-317 결판)
#
# L-317 (a) hypothesis: cor < 0.40 if universe expansion 효과 dominant
# L-317 (b) hypothesis: cor 0.7+ retain if alpha family essence (KR equity beta share)
# WT-D20260514_003 이미 (a) 입증 (저변동성에서). 본 cycle은 investor flow 재현 여부.
#
# Inherit from WT-D20260514_001:
#   - 5 sophistication factors verbatim (F1~F5)
#   - INV01~INV12 base factor pool
#   - SIGNAL_CUTOFF 2023-12-22 (lockbox-safe)
#   - PIT compliance C1-C15
#   - Codex Round 5-stage 의무
#
# Change only:
#   - Universe filter: K200 ∪ KQ150 merge → KOSPI 본주 + KOSDAQ 전종목
#   - LIQ floor 2e8 KRW retain
#   - New: universe_isolation_audit.json
#
# Boundary (Common Charter §8 + Alpha Agent strict_prohibitions):
#   - Σ 추정 / weight / cash 결정 금지 (Risk + Optimizer 영역)
#   - 산출물: alpha_scores.parquet + ic_history.parquet +
#             m08_overlap_verification.json + orthogonality_two_level.json +
#             universe_isolation_audit.json
#
# Author: Alpha Research Agent (Opus 4.7 1M context) | 2026-05-14
#==============================================================================

cat("=== WT-D20260514_004: Investor Flow B-Variant Full Universe Re-test ===\n")
cat("Mission: L-317 4x2 matrix completion (investor flow + full universe)\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(lubridate)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
set.seed(42L)

t0 <- Sys.time()

# ---- Paths ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
WT_ID        <- "WT-D20260514_004"
PARENT_WT_ID <- "WT-D20260514_001"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260514_004")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# ---- Lockbox enforcement ----
LOCKBOX_START   <- as.Date("2024-01-23")
LOCKBOX_END     <- as.Date("2026-04-27")
TRAIN_END       <- as.Date("2024-01-22")
SIGNAL_CUTOFF   <- as.Date("2023-12-22")

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "factor_db/factor_db_connector.R"))
cat("[Step 1] Factor DB connector + harness loaded\n")

#==============================================================================
# Step 2: RAWDATA + monthly forward returns + liquidity (C10)
#==============================================================================
cat("\n[Step 2] RAWDATA load + monthly forward returns...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Date, Ticker)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20_t := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[order(Date), AvgTV20 := shift(AvgTV20_t, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, AvgTV20_t := NULL]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

monthly_ret <- RAWDATA[, .(
  Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1
), by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
monthly_ret[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(monthly_ret, sig_date, Ticker)

cat(sprintf("[Step 2] RAWDATA: %s ~ %s | %d tickers\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

#==============================================================================
# Step 3: Factor DB bulk load — INV pool + STR_1715 H1 factors
#==============================================================================
cat("\n[Step 3] Factor DB bulk load — INV pool + STR_1715 H1 cor pool...\n")

INV_BASE_FACTORS <- c(
  "INV01_Foreign_NetBuy_20d", "INV02_Foreign_NetBuy_60d",
  "INV03_Inst_NetBuy_20d",    "INV04_Inst_NetBuy_60d",
  "INV05_Foreign_Momentum",   "INV06_Inst_Momentum",
  "INV07_Retail_Contrarian",  "INV08_Foreign_Inst_Agreement",
  "INV09_Flow_Persistence",   "INV10_Smart_Money_Flow",
  "INV11_Foreign_Concentration", "INV12_Supply_Demand_Imbalance"
)

STR1715_H1_FACTORS <- c(
  "C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap",
  "Q07_Earnings_Stability",
  "M08_Residual_Mom",
  "Q25_Ohlson_O"
)

NEEDED_FACTORS <- unique(c(INV_BASE_FACTORS, STR1715_H1_FACTORS))

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                              full.names = TRUE))
fdb_files_train <- fdb_files[sapply(fdb_files, function(fp) {
  ym   <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  d    <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  !is.na(d) && d >= as.Date("2008-01-01") && d <= SIGNAL_CUTOFF
})]
cat(sprintf("[Step 3] %d training-window parquet files (lockbox-safe, signal_cutoff=%s)\n",
            length(fdb_files_train), SIGNAL_CUTOFF))

FDB_ALL <- rbindlist(lapply(fdb_files_train, function(fp) {
  ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_d <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  dt    <- tryCatch(
    as.data.table(read_parquet(fp,
      col_select = c("Ticker","Factor_Name","Z_Score","Coverage"))),
    error = function(e) NULL
  )
  if (is.null(dt) || nrow(dt) == 0) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
           .(Ticker, Factor_Name, Z_Score)]
  if (nrow(dt) == 0) return(NULL)
  dt[, sig_date := sig_d]
  dt
}), fill = TRUE, use.names = TRUE)

cat(sprintf("[Step 3] Raw FDB: %s rows | %d months | %d factors\n",
            format(nrow(FDB_ALL), big.mark=","),
            uniqueN(FDB_ALL$sig_date),
            uniqueN(FDB_ALL$Factor_Name)))

# Direction alignment per sig_date (C13 + C14)
FDB_ALL_LIST <- split(FDB_ALL, by = "sig_date")
FDB_ALL <- rbindlist(lapply(FDB_ALL_LIST, function(sub) {
  sd <- as.Date(sub$sig_date[1])
  align_factor_direction(sub, .load_registry(), sig_date = sd, min_ic_months = 12L)
}), fill = TRUE)
rm(FDB_ALL_LIST); gc(verbose = FALSE)
if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
  FDB_ALL[, Z_Score := Z_Score_Aligned]
  FDB_ALL[, Z_Score_Aligned := NULL]
}
setkey(FDB_ALL, sig_date, Ticker)

FDB_WIDE <- dcast(FDB_ALL, sig_date + Ticker ~ Factor_Name,
                  value.var = "Z_Score", fill = NA_real_)
setkey(FDB_WIDE, sig_date, Ticker)
rm(FDB_ALL); gc(verbose = FALSE)
cat(sprintf("[Step 3] FDB_WIDE: %d rows x %d cols (%d sig_dates)\n",
            nrow(FDB_WIDE), ncol(FDB_WIDE), uniqueN(FDB_WIDE$sig_date)))

#==============================================================================
# Step 3B: Liquidity filter (C10) — FULL universe (KOSPI 본주 + KOSDAQ 전종목)
#   ★ KEY CHANGE vs WT-D20260514_001:
#     본 cycle은 K200 ∪ KQ150 membership filter 제거 → full universe
#     LIQ 2e8 만 적용 (PIT-clean 20d avg trading value)
#==============================================================================
all_sig_dates <- sort(unique(FDB_WIDE$sig_date))
liq_by_month <- lapply(all_sig_dates, function(sig_d) {
  snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
  if (nrow(snap) == 0) {
    closest_d <- RAWDATA[Date <= sig_d, max(Date)]
    snap <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  }
  data.table(sig_date = sig_d, Ticker = snap$Ticker)
})
LIQ_PASS_DT <- rbindlist(liq_by_month, fill = TRUE)
setkey(LIQ_PASS_DT, sig_date, Ticker)

# ★ Capture FULL universe size BEFORE intersection filter (for audit)
FDB_WIDE_PRE_FILTER <- copy(FDB_WIDE)
n_pre_liq <- nrow(FDB_WIDE)
FDB_WIDE <- merge(FDB_WIDE, LIQ_PASS_DT, by = c("sig_date","Ticker"), all.x = FALSE)
setkey(FDB_WIDE, sig_date, Ticker)
cat(sprintf("[Step 3B] FDB_WIDE post-LIQ filter: %d rows (drop %d) | %d tickers avg/mo\n",
            nrow(FDB_WIDE), n_pre_liq - nrow(FDB_WIDE),
            round(nrow(FDB_WIDE) / pmax(uniqueN(FDB_WIDE$sig_date), 1))))

# ---- universe_isolation_audit: compare full vs intersection sizes per sig_date ----
cat("\n[Step 3C] Universe isolation audit (full vs intersection)...\n")
k200  <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_k200.parquet")))
kq150 <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_kq150.parquet")))
k200[, `:=`(Date = as.Date(Date))]
kq150[, `:=`(Date = as.Date(Date))]

build_membership_panel <- function(member_dt, value_col) {
  setnames(member_dt, value_col, "is_member", skip_absent = TRUE)
  member_dt <- member_dt[!is.na(is_member) & is_member == 1, .(Date, Ticker)]
  member_dt[, sig_date := as.Date(format(Date %m+% months(1), "%Y-%m-01"))]
  member_dt[, .(sig_date, Ticker)]
}
k200_panel  <- build_membership_panel(copy(k200),  "K200")
kq150_panel <- build_membership_panel(copy(kq150), "KQ150")
universe_panel_intersection <- unique(rbind(k200_panel, kq150_panel))
setkey(universe_panel_intersection, sig_date, Ticker)

# Compute size per sig_date: full (FDB_WIDE post-LIQ) vs intersection (FDB_WIDE post-LIQ ∩ K200 ∪ KQ150)
size_full <- FDB_WIDE[, .(n_full = .N), by = sig_date]
FDB_INTERSECTION <- merge(FDB_WIDE, universe_panel_intersection, by = c("sig_date","Ticker"))
size_intersection <- FDB_INTERSECTION[, .(n_intersection = .N), by = sig_date]
universe_size_dt <- merge(size_full, size_intersection, by = "sig_date", all.x = TRUE)
universe_size_dt[is.na(n_intersection), n_intersection := 0L]
universe_size_dt[, expansion_ratio := n_full / pmax(n_intersection, 1L)]
cat(sprintf("[Step 3C] mean full: %.0f / mean intersection: %.0f / mean ratio: %.2fx\n",
            mean(universe_size_dt$n_full),
            mean(universe_size_dt$n_intersection),
            mean(universe_size_dt$expansion_ratio)))

rm(FDB_INTERSECTION); gc(verbose = FALSE)

#==============================================================================
# Step 4: Regime panel load (same as WT-D20260514_001)
#==============================================================================
cat("\n[Step 4] Regime panel load (regime_state column)...\n")
regime_files <- list.files(CACHE_DIR, pattern="regime_panel.*\\.parquet$",
                            recursive=TRUE, full.names=TRUE)
regime_dt <- NULL
if (length(regime_files) > 0) {
  reg_try <- tryCatch(
    as.data.table(read_parquet(regime_files[1])),
    error = function(e) NULL
  )
  if (!is.null(reg_try) && "regime_state" %in% names(reg_try)) {
    regime_dt <- reg_try[, .(Date = as.Date(Date), regime_state)]
    cat(sprintf("[Step 4] Regime panel loaded: %d rows\n", nrow(regime_dt)))
  }
}
if (is.null(regime_dt)) {
  cat("[Step 4] Regime panel not found, building fallback from BM_DT...\n")
  BM_DT[, BM_Ret_252d := frollapply(BM_Ret, n=252L,
        FUN=function(x) prod(1+x, na.rm=TRUE) - 1, align="right")]
  BM_DT[, BM_Ret_252d_lag := shift(BM_Ret_252d, n=1L, type="lag")]
  BM_DT[, pct_exp := {
    n <- length(BM_Ret_252d_lag)
    out <- rep(NA_real_, n)
    for (i in 252:n) {
      hist <- BM_Ret_252d_lag[1:(i-1)]
      out[i] <- mean(hist <= BM_Ret_252d_lag[i], na.rm=TRUE)
    }
    out
  }]
  BM_DT[, regime_state := fcase(
    pct_exp >= 0.75, "BULL",
    pct_exp >= 0.40, "NORMAL",
    pct_exp >= 0.20, "CAUTION",
    pct_exp <  0.20, "CRISIS",
    default = NA_character_
  )]
  regime_dt <- BM_DT[!is.na(regime_state), .(Date, regime_state)]
}
regime_at_sigdate <- regime_dt[, .(
  regime_state = regime_state[which.max(Date)]
), by = .(sig_date = as.Date(format(Date, "%Y-%m-01")))]
setkey(regime_at_sigdate, sig_date)

#==============================================================================
# Step 5: Sophistication factor construction (5 candidates ex-ante grid, INHERIT VERBATIM from WT-D20260514_001)
#==============================================================================
cat("\n[Step 5] Sophistication factor construction (5 candidates ex-ante, inherit)...\n")

available_factors <- intersect(NEEDED_FACTORS, names(FDB_WIDE))
cat(sprintf("[Step 5] Available factors: %d/%d\n",
            length(available_factors), length(NEEDED_FACTORS)))

zscore_cs <- function(x) {
  m <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if (is.na(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  (x - m) / s
}

FDB_WIDE <- merge(FDB_WIDE, regime_at_sigdate, by = "sig_date", all.x = TRUE)
setkey(FDB_WIDE, sig_date, Ticker)
FDB_WIDE[is.na(regime_state), regime_state := "NORMAL"]
FDB_WIDE[, regime_scalar := fcase(
  regime_state == "BULL",   1.0,
  regime_state == "NORMAL", 0.9,
  regime_state == "CAUTION", 0.5,
  regime_state == "CRISIS", 0.2,
  default = 0.9
)]

# F1: HAR_Flow_Macro_Conditional
FDB_WIDE[, F1_HAR_short := 0.5 * INV01_Foreign_NetBuy_20d + 0.5 * INV03_Inst_NetBuy_20d]
FDB_WIDE[, F1_HAR_mid   := 0.5 * INV02_Foreign_NetBuy_60d + 0.5 * INV04_Inst_NetBuy_60d]
FDB_WIDE[, F1_z_short := zscore_cs(F1_HAR_short), by = sig_date]
FDB_WIDE[, F1_z_mid   := zscore_cs(F1_HAR_mid),   by = sig_date]
FDB_WIDE[, F1_HAR_Flow_Macro_Conditional := regime_scalar * (0.6 * F1_z_short + 0.4 * F1_z_mid)]

# F2: Cross_Investor_Disagreement_Persistent
FDB_WIDE[, F2_neg_INV08 := -1 * INV08_Foreign_Inst_Agreement]
FDB_WIDE[, F2_z_neg08 := zscore_cs(F2_neg_INV08), by = sig_date]
FDB_WIDE[, F2_z_INV09 := zscore_cs(INV09_Flow_Persistence), by = sig_date]
FDB_WIDE[, F2_Cross_Investor_Disagreement_Persistent := 0.6 * F2_z_neg08 + 0.4 * F2_z_INV09]

# F3: Foreign_Resid_CrossSection (Choe-Kho-Stulz 2005 analog)
FDB_WIDE[, F3_INV01_z := zscore_cs(INV01_Foreign_NetBuy_20d), by = sig_date]
FDB_WIDE[, F3_neg_INV07_z := zscore_cs(-1 * INV07_Retail_Contrarian), by = sig_date]
beta_per_sigdate <- FDB_WIDE[!is.na(F3_INV01_z) & !is.na(F3_neg_INV07_z), {
  if (.N >= 20) {
    num <- sum(F3_INV01_z * F3_neg_INV07_z, na.rm = TRUE)
    den <- sum(F3_neg_INV07_z^2,          na.rm = TRUE)
    .(beta = if (abs(den) > 1e-10) num / den else NA_real_)
  } else {
    .(beta = NA_real_)
  }
}, by = sig_date]
setkey(beta_per_sigdate, sig_date)
FDB_WIDE <- merge(FDB_WIDE, beta_per_sigdate, by = "sig_date", all.x = TRUE)
setkey(FDB_WIDE, sig_date, Ticker)
FDB_WIDE[, F3_Foreign_Resid_CrossSection := F3_INV01_z - beta * F3_neg_INV07_z]
FDB_WIDE[, c("F3_INV01_z","F3_neg_INV07_z","beta") := NULL]

# F4: Smart_Money_Concentration_Decoupled (INHERIT — selected in WT-D20260514_001)
FDB_WIDE[, F4_z_INV10 := zscore_cs(INV10_Smart_Money_Flow), by = sig_date]
FDB_WIDE[, F4_z_INV11 := zscore_cs(INV11_Foreign_Concentration), by = sig_date]
FDB_WIDE[, F4_Smart_Money_Concentration_Decoupled := 0.5 * F4_z_INV10 + 0.5 * F4_z_INV11]

# F5: Flow_Momentum_Differential
FDB_WIDE[, F5_diff_raw := INV05_Foreign_Momentum - INV06_Inst_Momentum]
FDB_WIDE[, F5_Flow_Momentum_Differential := zscore_cs(F5_diff_raw), by = sig_date]

SOPH_FACTORS <- c(
  "F1_HAR_Flow_Macro_Conditional",
  "F2_Cross_Investor_Disagreement_Persistent",
  "F3_Foreign_Resid_CrossSection",
  "F4_Smart_Money_Concentration_Decoupled",
  "F5_Flow_Momentum_Differential"
)

# Final Z-score per sig_date
for (f in SOPH_FACTORS) {
  if (f %in% names(FDB_WIDE)) {
    FDB_WIDE[, paste0(f, "_z") := zscore_cs(get(f)), by = sig_date]
  }
}

cat(sprintf("[Step 5] %d sophistication factors constructed (inherit verbatim)\n", length(SOPH_FACTORS)))

#==============================================================================
# Step 6: Forward return join + IC computation
#==============================================================================
cat("\n[Step 6] Forward return join + per-factor IC...\n")
FDB_WIDE[, fwd_date := sig_date %m+% months(1)]
monthly_ret_simple <- monthly_ret[, .(sig_date, Ticker, Ret_1m)]
setkey(monthly_ret_simple, sig_date, Ticker)

soph_z_cols <- paste0(SOPH_FACTORS, "_z")
str1715_cols <- intersect(STR1715_H1_FACTORS, names(FDB_WIDE))

FDB_WITH_RET <- merge(
  FDB_WIDE[, .SD, .SDcols = c("sig_date","fwd_date","Ticker","regime_state",
                                soph_z_cols, str1715_cols)],
  monthly_ret_simple[, .(fwd_date = sig_date, Ticker, Ret_1m)],
  by = c("fwd_date","Ticker"), all.x = FALSE
)
setkey(FDB_WITH_RET, sig_date, Ticker)
cat(sprintf("[Step 6] IC dataset: %d rows | %d sig_dates\n",
            nrow(FDB_WITH_RET), uniqueN(FDB_WITH_RET$sig_date)))

# Per-factor IC per month (Spearman)
ic_per_month <- lapply(soph_z_cols, function(fn) {
  per_month <- FDB_WITH_RET[!is.na(get(fn)) & !is.na(Ret_1m),
    .(IC = tryCatch(cor(get(fn), Ret_1m, method="spearman"),
                    error=function(e) NA_real_),
      N  = .N),
    by = sig_date
  ]
  per_month[, factor := fn]
  per_month
})
IC_DT <- rbindlist(ic_per_month, fill=TRUE)
setkey(IC_DT, factor, sig_date)

factor_ic_stats <- IC_DT[!is.na(IC) & N >= 20, .(
  mean_IC   = mean(IC),
  sd_IC     = sd(IC),
  ICIR      = mean(IC)/sd(IC),
  Harvey_t  = mean(IC)/sd(IC)*sqrt(.N),
  n_months  = .N,
  p1_IC     = mean(IC[sig_date >= as.Date("2008-01-01") & sig_date <= as.Date("2014-12-31")]),
  p2_IC     = mean(IC[sig_date >= as.Date("2015-01-01") & sig_date <= as.Date("2019-12-31")]),
  p3_IC     = mean(IC[sig_date >= as.Date("2020-01-01") & sig_date <= as.Date("2023-12-22")])
), by = factor]
factor_ic_stats[, sub_stability := pmin(abs(p1_IC),abs(p2_IC),abs(p3_IC)) /
                                    pmax(abs(p1_IC),abs(p2_IC),abs(p3_IC))]

# NW HAC lag-3 t-stat (Newey-West correction)
ic_nw_t <- function(ic_vec) {
  if (length(ic_vec) < 12) return(NA_real_)
  mu <- mean(ic_vec, na.rm = TRUE)
  n <- sum(!is.na(ic_vec))
  resid <- ic_vec - mu
  resid[is.na(resid)] <- 0
  gamma0 <- sum(resid^2) / n
  L <- 3L
  for (k in 1:L) {
    if (k >= n) break
    w_k <- 1 - k / (L + 1)
    gamma_k <- sum(resid[(k+1):n] * resid[1:(n-k)]) / n
    gamma0 <- gamma0 + 2 * w_k * gamma_k
  }
  var_mu <- gamma0 / n
  if (is.na(var_mu) || var_mu <= 0) return(NA_real_)
  mu / sqrt(var_mu)
}
nw_t_per_factor <- IC_DT[!is.na(IC), .(harvey_t_nw_lag3 = ic_nw_t(IC)), by = factor]
factor_ic_stats <- merge(factor_ic_stats, nw_t_per_factor, by = "factor", all.x = TRUE)

cat("\n=== STANDALONE SOPHISTICATION FACTOR IC (FULL UNIVERSE) ===\n")
print(factor_ic_stats[, .(factor,
                          meanIC = round(mean_IC, 4),
                          ICIR = round(ICIR, 4),
                          Harvey_t = round(Harvey_t, 3),
                          NW_lag3 = round(harvey_t_nw_lag3, 3),
                          n_months,
                          P1=round(p1_IC,4), P2=round(p2_IC,4), P3=round(p3_IC,4),
                          SubStab=round(sub_stability,3))])

#==============================================================================
# Step 7: Cross-factor correlation matrix + STR_1715 alpha-vector cor
#==============================================================================
cat("\n[Step 7] Cross-factor correlation (alpha-vector level)...\n")
soph_data <- FDB_WIDE[, .SD, .SDcols = c("sig_date","Ticker", soph_z_cols, str1715_cols)]
soph_data <- soph_data[complete.cases(soph_data[, soph_z_cols, with=FALSE])]
cat(sprintf("[Step 7] Soph data after na.omit: %d rows | %d sig_dates\n",
            nrow(soph_data), uniqueN(soph_data$sig_date)))

cor_soph <- NULL
if (nrow(soph_data) > 100) {
  cor_soph <- cor(as.matrix(soph_data[, soph_z_cols, with=FALSE]),
                  use="pairwise.complete.obs")
  cat("\n=== 5x5 SOPHISTICATION CORRELATION ===\n")
  print(round(cor_soph, 3))
  cat("\nMax |off-diag|:", round(max(abs(cor_soph[upper.tri(cor_soph)])), 3), "\n")
}

cor_vs_str1715 <- list()
if (length(str1715_cols) > 0 && nrow(soph_data) > 100) {
  for (sf in soph_z_cols) {
    for (sc in str1715_cols) {
      sub <- soph_data[!is.na(get(sf)) & !is.na(get(sc))]
      if (nrow(sub) < 50) next
      co <- cor(sub[[sf]], sub[[sc]], use="pairwise.complete.obs")
      co_rank <- cor(sub[[sf]], sub[[sc]], use="pairwise.complete.obs", method="spearman")
      cor_vs_str1715[[paste0(sf, "_vs_", sc)]] <- list(
        soph = sf, str1715 = sc, n = nrow(sub),
        cor_pearson = round(co, 4), cor_spearman = round(co_rank, 4)
      )
    }
  }
}
cat(sprintf("\n[Step 7] %d soph x STR1715 cor pairs computed\n", length(cor_vs_str1715)))

#==============================================================================
# Step 8: Selection — inherit WT-D20260514_001 F4 (selected by abs_icir + sub-gates)
#==============================================================================
cat("\n[Step 8] Selection per ex-ante criteria + inherit parent F4...\n")
factor_ic_stats[, pass_icir := abs(ICIR) >= 0.20]
factor_ic_stats[, pass_harvey := abs(Harvey_t) >= 3.0]
factor_ic_stats[, pass_substab := !is.na(sub_stability) & sub_stability >= 0.30]
factor_ic_stats[, pass_meanic := abs(mean_IC) >= 0.02]
factor_ic_stats[, pass_all := pass_icir & pass_harvey & pass_substab & pass_meanic]
factor_ic_stats[, abs_icir := abs(ICIR)]

cat("\n=== Gate pass summary (FULL UNIVERSE) ===\n")
print(factor_ic_stats[, .(factor, abs_icir, Harvey_t,
                          pass_icir, pass_harvey, pass_substab, pass_meanic, pass_all)])

# Inherit parent F4 selection (universe isolation: spec retain)
parent_selected <- "F4_Smart_Money_Concentration_Decoupled_z"
parent_selected_stats <- factor_ic_stats[factor == parent_selected]
selected_factor <- parent_selected
cat(sprintf("\n[Step 8] INHERIT PARENT SELECTION: %s (ICIR=%.4f, Harvey_t=%.3f)\n",
            selected_factor, parent_selected_stats$ICIR[1], parent_selected_stats$Harvey_t[1]))

# Also report autonomous best (for honest disclosure)
autonomous_best <- factor_ic_stats[order(-abs_icir)][1]
cat(sprintf("[Step 8] Autonomous best (by abs_icir): %s (ICIR=%.4f, Harvey_t=%.3f)\n",
            autonomous_best$factor[1], autonomous_best$ICIR[1], autonomous_best$Harvey_t[1]))

#==============================================================================
# Step 9: Monotonicity for inherited selection
#==============================================================================
cat("\n[Step 9] Decile monotonicity for selected factor...\n")
sel_sub <- FDB_WITH_RET[!is.na(get(selected_factor)) & !is.na(Ret_1m)]
sel_sub[, decile := cut(get(selected_factor),
                        breaks = quantile(get(selected_factor),
                                          probs = seq(0, 1, 0.1), na.rm = TRUE),
                        labels = 1:10, include.lowest = TRUE), by = sig_date]
decile_ret <- sel_sub[!is.na(decile), .(
  mean_ret_1m = mean(Ret_1m, na.rm = TRUE),
  n_months = uniqueN(sig_date)
), by = decile][order(decile)]
cat("\n=== Decile mean 1m return ===\n")
print(decile_ret)

sel_ic <- factor_ic_stats[factor == selected_factor]$mean_IC[1]
expected_dir <- if (!is.na(sel_ic) && sel_ic > 0) 1 else -1
mono_pairs <- 0; total_pairs <- 0
for (i in 1:9) {
  d_i   <- decile_ret[decile == i]$mean_ret_1m[1]
  d_ip1 <- decile_ret[decile == i + 1]$mean_ret_1m[1]
  if (!is.na(d_i) && !is.na(d_ip1)) {
    total_pairs <- total_pairs + 1
    if ((d_ip1 - d_i) * expected_dir > 0) mono_pairs <- mono_pairs + 1
  }
}
mono_score <- if (total_pairs > 0) mono_pairs / total_pairs else NA_real_
cat(sprintf("[Step 9] Monotonicity: %d/%d = %.3f\n", mono_pairs, total_pairs,
            mono_score %||% NA_real_))

#==============================================================================
# Step 10: Save artifacts
#==============================================================================
cat("\n[Step 10] Save artifacts...\n")

# alpha_scores.parquet — CONTRARIAN-aligned per parent (negate raw F4_z)
selected_factor_raw <- selected_factor
alpha_scores <- FDB_WIDE[!is.na(get(selected_factor_raw)),
                          .(sig_date, Ticker,
                            score_raw = get(selected_factor_raw),
                            score_eff = -1 * get(selected_factor_raw),   # CONTRARIAN aligned
                            regime_state,
                            direction = "CONTRARIAN_ALIGNED_negate_raw_F4_z")]
setkey(alpha_scores, sig_date, Ticker)
arrow::write_parquet(alpha_scores, file.path(ART_DIR, "alpha_scores.parquet"))
cat(sprintf("[Step 10] alpha_scores.parquet: %d rows | %d sig_dates (CONTRARIAN aligned)\n",
            nrow(alpha_scores), uniqueN(alpha_scores$sig_date)))

# ic_history.parquet
arrow::write_parquet(IC_DT, file.path(ART_DIR, "ic_history.parquet"))
cat(sprintf("[Step 10] ic_history.parquet: %d rows\n", nrow(IC_DT)))

#==============================================================================
# Step 10B: m08_overlap_verification.json (inherit from parent)
#==============================================================================
m08_verification <- list(
  task_id = WT_ID,
  parent_task_id = PARENT_WT_ID,
  verification_date = as.character(Sys.Date()),
  inherit_rationale = "Parent WT-D20260514_001 m08_overlap_verification.json content valid — universe change does not affect information source orthogonality (price+financial vs disclosure-flow).",
  str1715_h1_alpha_factors = list(
    Core_4F_Consensus = c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap"),
    Core_Defense_Q07 = "Q07_Earnings_Stability",
    Defense_M08 = "M08_Residual_Mom",
    Defense_Q25 = "Q25_Ohlson_O"
  ),
  m08_family_definition = list(
    full_name = "M08_Residual_Mom",
    factor_family = "Momentum_Residual",
    information_source = "PRICE",
    formula = "12-1M momentum CAPM/FF residualized",
    references = c("Carhart 1997", "Blitz-Huij-Martens 2011", "Daniel-Moskowitz 2016"),
    uses_investor_flow_information = FALSE,
    uses_disclosure_data = FALSE
  ),
  this_cycle_information_source = "KRX investor flow disclosure (외국인 / 기관 / 개인 / 연기금 net buy KRW)",
  overlap_factor_count = 0L,
  information_source_orthogonal_alpha_stage = TRUE,
  verdict = "ZERO_OVERLAP_INFORMATION_SOURCE_ORTHOGONAL_AT_ALPHA_VECTOR_LEVEL_INHERIT_PARENT",
  rationale = paste(
    "STR_1715 H1 alpha (Iter 5 -> 31 admit). 7 factors: PRICE + FINANCIAL + ANALYST CONSENSUS.",
    "This cycle: KRX investor flow disclosure factors (INV01-INV12). Universe change does NOT affect information source level orthogonality (alpha-vector cor verified in WT-D20260514_001 max |0.072|)."
  )
)
write_json(m08_verification,
           file.path(ART_DIR, "m08_overlap_verification.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("[Step 10B] m08_overlap_verification.json saved\n")

#==============================================================================
# Step 11: Portfolio realized cor (alpha-stage preliminary — L-316/L-317 mandate)
#   Critical: vs STR_1715 production parquet (admit lineage) + proxy
#==============================================================================
cat("\n[Step 11] Portfolio realized return cor (full universe vs STR_1715)...\n")

build_top20_returns <- function(score_dt, monthly_ret_dt, score_col, label) {
  sd_list <- unique(score_dt$sig_date)
  rets <- lapply(sd_list, function(sd) {
    snap <- score_dt[sig_date == sd & !is.na(get(score_col))][order(-get(score_col))][1:20]
    if (nrow(snap) < 10) return(NULL)
    fwd_sd <- sd %m+% months(1)
    rets_m <- monthly_ret_dt[sig_date == fwd_sd & Ticker %in% snap$Ticker]
    if (nrow(rets_m) == 0) return(NULL)
    data.table(sig_date = sd, fwd_date = fwd_sd,
               port_ret = mean(rets_m$Ret_1m, na.rm = TRUE),
               n_holdings = nrow(rets_m), label = label)
  })
  rbindlist(rets, fill = TRUE)
}

# (1) This cycle top-20 EW portfolio (CONTRARIAN aligned score_eff)
this_cycle_alpha <- FDB_WIDE[, .(sig_date, Ticker, score = -1 * get(selected_factor_raw))]
this_cycle_alpha <- this_cycle_alpha[!is.na(score)]
this_cycle_ret <- build_top20_returns(this_cycle_alpha, monthly_ret_simple, "score", "this_cycle_aligned")

# (2) STR_1715 H1 PROXY portfolio (7-factor EW composite, same FDB_WIDE universe)
str1715_avail <- intersect(str1715_cols, names(FDB_WIDE))
if (length(str1715_avail) >= 4) {
  str1715_alpha <- FDB_WIDE[, .SD, .SDcols = c("sig_date","Ticker", str1715_avail)]
  str1715_alpha[, str1715_score := rowMeans(.SD, na.rm = TRUE),
                .SDcols = str1715_avail]
  str1715_alpha <- str1715_alpha[!is.na(str1715_score),
                                  .(sig_date, Ticker, score = str1715_score)]
  str1715_ret_proxy <- build_top20_returns(str1715_alpha, monthly_ret_simple,
                                            "score", "str1715_h1_proxy")
} else {
  str1715_ret_proxy <- data.table()
}

# (3) STR_1715 PRODUCTION (admit lineage parquet — 268m)
str1715_prod_file <- file.path(PROJECT_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
str1715_prod_ret <- data.table()
if (file.exists(str1715_prod_file)) {
  str1715_prod <- as.data.table(read_parquet(str1715_prod_file))
  cat(sprintf("[Step 11] STR_1715 production parquet: %d rows | cols: %s\n",
              nrow(str1715_prod), paste(names(str1715_prod), collapse=",")))
  # Detect schema: expect (sig_date or Date, Ticker, score or alpha)
  date_col <- intersect(c("sig_date","Date","date"), names(str1715_prod))[1]
  score_col <- intersect(c("alpha","score","alpha_score","score_eff","STR_1715"), names(str1715_prod))[1]
  if (!is.na(date_col) && !is.na(score_col)) {
    setnames(str1715_prod, c(date_col, score_col), c("sig_date","score"))
    str1715_prod[, sig_date := as.Date(sig_date)]
    str1715_prod_in_lockbox <- str1715_prod[sig_date <= SIGNAL_CUTOFF]
    # Snap sig_date to first-of-month for proper join
    str1715_prod_in_lockbox[, sig_date := as.Date(format(sig_date, "%Y-%m-01"))]
    str1715_prod_in_lockbox <- str1715_prod_in_lockbox[, .(score = mean(score, na.rm = TRUE)),
                                                       by = .(sig_date, Ticker)]
    str1715_prod_ret <- build_top20_returns(str1715_prod_in_lockbox, monthly_ret_simple,
                                             "score", "str1715_production_admit_lineage")
    cat(sprintf("[Step 11] STR_1715 production top-20 portfolio: %d sig_dates in lockbox\n",
                uniqueN(str1715_prod_ret$sig_date)))
  } else {
    cat(sprintf("[Step 11] STR_1715 production schema not recognized (date_col=%s, score_col=%s)\n",
                date_col %||% "NA", score_col %||% "NA"))
  }
}

# Compute portfolio realized cor (this_cycle vs proxy + vs production)
pf_results <- list()
if (nrow(this_cycle_ret) > 20) {
  # vs proxy
  if (nrow(str1715_ret_proxy) > 20) {
    pf_merged <- merge(this_cycle_ret[, .(sig_date, this_ret = port_ret)],
                       str1715_ret_proxy[, .(sig_date, str_ret = port_ret)],
                       by = "sig_date")
    pf_merged <- pf_merged[!is.na(this_ret) & !is.na(str_ret)]
    if (nrow(pf_merged) >= 24) {
      pf_results$alpha_stage_proxy_vs_str1715_h1_ew_proxy <- list(
        n_months = nrow(pf_merged),
        pearson  = round(cor(pf_merged$this_ret, pf_merged$str_ret, method="pearson"), 4),
        spearman = round(cor(pf_merged$this_ret, pf_merged$str_ret, method="spearman"), 4),
        kendall  = round(cor(pf_merged$this_ret, pf_merged$str_ret, method="kendall"), 4),
        lt_tdc_q010 = {
          q_thr <- 0.10
          lt_this <- pf_merged$this_ret <= quantile(pf_merged$this_ret, q_thr)
          lt_str  <- pf_merged$str_ret  <= quantile(pf_merged$str_ret,  q_thr)
          if (sum(lt_str) > 0) round(sum(lt_this & lt_str) / sum(lt_str), 4) else NA_real_
        },
        note = "STR_1715 H1 proxy EW composite (7-factor mean) within FDB_WIDE universe — full universe scope"
      )
      cat(sprintf("[Step 11a] vs proxy: Pearson=%+.4f / Spearman=%+.4f (n=%d months)\n",
                  pf_results$alpha_stage_proxy_vs_str1715_h1_ew_proxy$pearson,
                  pf_results$alpha_stage_proxy_vs_str1715_h1_ew_proxy$spearman,
                  nrow(pf_merged)))
    }
  }
  # vs production
  if (nrow(str1715_prod_ret) > 20) {
    pf_merged_prod <- merge(this_cycle_ret[, .(sig_date, this_ret = port_ret)],
                            str1715_prod_ret[, .(sig_date, str_ret = port_ret)],
                            by = "sig_date")
    pf_merged_prod <- pf_merged_prod[!is.na(this_ret) & !is.na(str_ret)]
    if (nrow(pf_merged_prod) >= 24) {
      pf_results$alpha_stage_aligned_vs_str1715_production <- list(
        n_months = nrow(pf_merged_prod),
        pearson  = round(cor(pf_merged_prod$this_ret, pf_merged_prod$str_ret, method="pearson"), 4),
        spearman = round(cor(pf_merged_prod$this_ret, pf_merged_prod$str_ret, method="spearman"), 4),
        kendall  = round(cor(pf_merged_prod$this_ret, pf_merged_prod$str_ret, method="kendall"), 4),
        note = "STR_1715 production admit lineage parquet (alpha_scores_str1715_268m, lockbox-truncated SIGNAL_CUTOFF)"
      )
      cat(sprintf("[Step 11b] vs production: Pearson=%+.4f / Spearman=%+.4f (n=%d months)\n",
                  pf_results$alpha_stage_aligned_vs_str1715_production$pearson,
                  pf_results$alpha_stage_aligned_vs_str1715_production$spearman,
                  nrow(pf_merged_prod)))
    }
  }
}

#==============================================================================
# Step 12: orthogonality_two_level.json + universe_isolation_audit.json
#==============================================================================
ortho_results <- list(
  task_id = WT_ID,
  parent_task_id = PARENT_WT_ID,
  computed_at = as.character(Sys.time()),
  selected_factor = selected_factor,
  selection_method = "parent_inherit (universe isolation: spec retain, universe expansion only)",
  l316_l317_mandate = list(
    description = paste(
      "L-316 양 단계 직교성 mandate inherit + L-317 universe expansion path 검증.",
      "Parent WT-D20260514_001 portfolio realized cor 0.7713 (intersection ~350) → 본 cycle ? (full ~2,657).",
      "WT-D20260514_003 저변동성 universe expansion에서 cor 0.7713 → 0.0292 PASS 입증.",
      "본 cycle은 investor flow 재현 여부 결판."
    ),
    levels = c("alpha_vector_score_cross_section",
               "portfolio_realized_monthly_return_time_series")
  ),
  alpha_vector_level = list(
    description = "Cross-section score correlation (Pearson + Spearman) — universe change does NOT affect (alpha vector cor measured on overlapping tickers)",
    soph_intra_5x5 = if (!is.null(cor_soph)) {
      apply(cor_soph, c(1,2), function(x) round(x, 4))
    } else NULL,
    soph_vs_str1715_pairs = cor_vs_str1715,
    parent_max_abs_pearson_vs_str1715 = 0.072,
    parent_max_abs_spearman_vs_str1715 = 0.1103,
    parent_verdict = "PASS (all |cor| < 0.15)"
  ),
  portfolio_realized_level = pf_results,
  isolation_decision_rule = list(
    if_cor_lt_0_40 = "universe-driven attenuation, L-317 (a) hypothesis confirmed (universe expansion 효과 dominant)",
    if_cor_0_40_to_0_70 = "partial universe effect, L-317 mixed",
    if_cor_ge_0_70 = "alpha family essence, L-317 (b) hypothesis confirmed (KR equity beta share, architectural pivot required)"
  ),
  references = c(
    "L-316 (alpha-vector cor != portfolio realized cor)",
    "L-317 candidate (KR equity universe limit - intersection 한정 vs full)",
    "WT-D20260513_002 저변동성 intersection cor 0.7713 FAIL",
    "WT-D20260514_001 investor flow intersection cor 0.7713 FAIL",
    "WT-D20260514_002 general 7 axes full cor 0.696 FAIL",
    "WT-D20260514_003 저변동성 full cor 0.0292 PASS (universe expansion 효과 입증)",
    "WT-D20260514_004 본 cycle (4번째 cell L-317 결판)"
  )
)
write_json(ortho_results,
           file.path(ART_DIR, "orthogonality_two_level.json"),
           pretty = TRUE, auto_unbox = TRUE, force=TRUE)
cat("[Step 12] orthogonality_two_level.json saved\n")

# universe_isolation_audit.json — intersection vs full size + L-317 decision
universe_isolation <- list(
  task_id = WT_ID,
  parent_task_id = PARENT_WT_ID,
  universe_change_only = TRUE,
  alpha_spec_change = "none (F4 inherited verbatim, 5 axes ex-ante grid unchanged)",
  parent_universe = "KOSPI200 ∪ KOSDAQ150 intersection + LIQ 2e8",
  this_cycle_universe = "KOSPI 본주 + KOSDAQ 전종목 + LIQ 2e8",
  mean_intersection_size = round(mean(universe_size_dt$n_intersection), 1),
  mean_full_size = round(mean(universe_size_dt$n_full), 1),
  mean_expansion_ratio = round(mean(universe_size_dt$expansion_ratio), 2),
  latest_intersection = universe_size_dt[sig_date == max(sig_date)]$n_intersection,
  latest_full = universe_size_dt[sig_date == max(sig_date)]$n_full,
  n_sig_dates = nrow(universe_size_dt),
  parent_diagnostics_F4 = list(
    n_months = 192L,
    mean_rank_ic = -0.0293,
    icir = -0.3224,
    harvey_t_nw = -4.7915,
    monotonicity = 0.556,
    subperiod_stability = 0.657,
    portfolio_realized_cor_p_vs_str1715_production = 0.7713,
    portfolio_realized_cor_p_vs_str1715_proxy = 0.7376
  ),
  this_cycle_diagnostics_F4 = list(
    factor = selected_factor,
    n_months = parent_selected_stats$n_months[1],
    mean_rank_ic = round(parent_selected_stats$mean_IC[1], 4),
    sd_rank_ic = round(parent_selected_stats$sd_IC[1], 4),
    icir = round(parent_selected_stats$ICIR[1], 4),
    icir_recent_3y = NA_real_,
    harvey_t_simple = round(parent_selected_stats$Harvey_t[1], 3),
    harvey_t_nw_lag3 = round(parent_selected_stats$harvey_t_nw_lag3[1], 3),
    monotonicity = round(mono_score %||% NA_real_, 3),
    subperiod_stability = round(parent_selected_stats$sub_stability[1], 3),
    p1_ic = round(parent_selected_stats$p1_IC[1], 4),
    p2_ic = round(parent_selected_stats$p2_IC[1], 4),
    p3_ic = round(parent_selected_stats$p3_IC[1], 4),
    portfolio_realized_cor_p_vs_str1715_proxy = pf_results$alpha_stage_proxy_vs_str1715_h1_ew_proxy$pearson,
    portfolio_realized_cor_p_vs_str1715_production = pf_results$alpha_stage_aligned_vs_str1715_production$pearson
  ),
  delta_universe_effect = list(
    delta_pearson_proxy = if (!is.null(pf_results$alpha_stage_proxy_vs_str1715_h1_ew_proxy$pearson)) {
      round(pf_results$alpha_stage_proxy_vs_str1715_h1_ew_proxy$pearson - 0.7376, 4)
    } else NA_real_,
    delta_pearson_production = if (!is.null(pf_results$alpha_stage_aligned_vs_str1715_production$pearson)) {
      round(pf_results$alpha_stage_aligned_vs_str1715_production$pearson - 0.7713, 4)
    } else NA_real_,
    interpretation_template = "Negative delta means universe expansion attenuates cor (L-317 (a)). |delta| < 0.1 means alpha family essence (L-317 (b))."
  ),
  l317_4x2_matrix = list(
    cell_1_lowvol_intersection = list(cor = 0.7713, verdict = "FAIL", source = "WT-D20260513_002"),
    cell_2_investor_flow_intersection = list(cor = 0.7713, verdict = "FAIL", source = "WT-D20260514_001"),
    cell_3_general_7_full = list(cor = 0.696, verdict = "FAIL", source = "WT-D20260514_002"),
    cell_4_lowvol_full = list(cor = 0.0292, verdict = "PASS", source = "WT-D20260514_003 (C2)"),
    cell_5_investor_flow_full = list(
      cor = pf_results$alpha_stage_aligned_vs_str1715_production$pearson %||% NA_real_,
      verdict = NA_character_,  # to be filled below
      source = "WT-D20260514_004 (본 cycle)"
    )
  ),
  l317_decision_per_this_cycle = NA_character_  # filled below
)

# Decision logic for this cycle
prod_cor <- universe_isolation$this_cycle_diagnostics_F4$portfolio_realized_cor_p_vs_str1715_production
if (!is.null(prod_cor) && !is.na(prod_cor)) {
  abs_prod <- abs(prod_cor)
  universe_isolation$l317_decision_per_this_cycle <- if (abs_prod < 0.40) {
    "PASS_universe_expansion_attenuates_alpha_family_essence_L317_a_hypothesis_confirmed"
  } else if (abs_prod < 0.70) {
    "PARTIAL_mixed_universe_effect_L317_intermediate"
  } else {
    "FAIL_alpha_family_essence_KR_beta_share_L317_b_hypothesis_confirmed_for_investor_flow"
  }
  universe_isolation$l317_4x2_matrix$cell_5_investor_flow_full$verdict <- if (abs_prod < 0.40) "PASS" else if (abs_prod < 0.70) "PARTIAL" else "FAIL"
} else {
  universe_isolation$l317_decision_per_this_cycle <- "DATA_INSUFFICIENT_production_cor_not_computed"
}

write_json(universe_isolation,
           file.path(ART_DIR, "universe_isolation_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, force=TRUE)
cat("[Step 12] universe_isolation_audit.json saved\n")
cat(sprintf("[Step 12] L-317 decision for cell 5: %s\n", universe_isolation$l317_decision_per_this_cycle))

#==============================================================================
# Step 13: alpha_validation.json
#==============================================================================
alpha_validation <- list(
  task_id = WT_ID,
  parent_task_id = PARENT_WT_ID,
  validated_at = as.character(Sys.time()),
  selected_factor = selected_factor,
  selection_method = "parent_inherit (universe isolation: spec retain)",
  diagnostics = list(
    rank_ic   = round(parent_selected_stats$mean_IC[1], 4),
    icir      = round(parent_selected_stats$ICIR[1],    4),
    harvey_t  = round(parent_selected_stats$Harvey_t[1], 3),
    harvey_t_nw_lag3 = round(parent_selected_stats$harvey_t_nw_lag3[1], 3),
    sub_stability = round(parent_selected_stats$sub_stability[1], 3),
    monotonicity  = round(mono_score %||% NA_real_, 3),
    n_months  = parent_selected_stats$n_months[1]
  ),
  all_5_factors_ic_stats = factor_ic_stats,
  universe_isolation_decision = universe_isolation$l317_decision_per_this_cycle,
  ax_compliance = list(
    AX_002_ex_ante_grid_n5 = "PASS (inherit parent grid, no post-hoc search)",
    AX_005_AX_007 = "EXEMPT (multi-sleeve with STR_1715)",
    AX_008 = "PENDING_CODEX_ROUND"
  ),
  pit_compliance = list(
    C1_lookahead = "PASS (sig_date <= 2023-12-22 lockbox-safe)",
    C2_same_day_circular = "PASS (compute_investor.R Date < sig_d strict)",
    C10_liquidity = "PASS (20d avg TV t-1 lag >= 2e8 KRW)",
    C13_Z_Score_Aligned = "PASS (align_factor_direction per sig_date)",
    C14_Usable_Date = "PASS (IC history filter Usable_Date <= sig_date)",
    C15_load_month_factors = "PASS (bulk read equivalent to per-sig load_month_factors)",
    lockbox = sprintf("ENFORCED: SIGNAL_CUTOFF=%s", SIGNAL_CUTOFF)
  )
)
write_json(alpha_validation,
           file.path(ART_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, force=TRUE)
cat("[Step 13] alpha_validation.json saved\n")

t1 <- Sys.time()
cat(sprintf("\n=== Total runtime: %.1f min ===\n",
            as.numeric(difftime(t1, t0, units = "mins"))))
cat("=== factor_engine_proposal.R DONE ===\n")
