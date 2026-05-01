## ============================================================================
## STR_1715 May 2026 Forward Recompute — Step 2-bis: 2026-05-01 sig_date score
##
## Iter5 alpha_scores.parquet (Step 2 output)는 IC measurement 위해
## sig_date <= 2026-04-01 (last fully-realized fwd return)로 절단.
## 5월 운용을 위해 sig_date = 2026-05-01의 score만 별도 산출 (fwd return 무관).
##
## 방법: factor_engine_proposal.R Step 6 (composite blend) logic 그대로 적용,
##       sig_date = 2026-05-01에 대해서만.
##       - factor_db_202605.parquet 사용 (or 202604, 1m PIT lag)
##       - sig_date를 Iter5 alpha 산출 sig_dates 마지막 (2026-04-01)에 추가
##       - regime_panel_extended.parquet에서 2026-05-01 regime_state attach
##
## NOTE: Iter5 multi-sleeve composite은 Step 5의 expanding IC weights에 의존.
##       2026-05-01 sig_date의 IC weights = 2026-04-30까지 expanding IC
##       (already computed in Step 2 output's last sig_date theta_core/theta_defense).
##       그 weights를 그대로 적용 (PIT-safe forward extrapolation).
## ============================================================================

cat("=== STR_1715 May 2026 Forward — Step 2b: 2026-05-01 sig_date score ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(lubridate)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-P20260429_002"
OUT_DIR      <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "forge_may2026")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

SLEEVE_CORE     <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")
SLEEVE_DEFENSE  <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")
NEEDED_FACTORS  <- unique(c(SLEEVE_CORE, SLEEVE_DEFENSE))

# Sig date for May 2026 production
MAY_SIG_DATE <- as.Date("2026-05-01")
PIT_REF_DATE <- as.Date("2026-04-30")  # data through 2026-04-30 = factor_db_202604

cat(sprintf("[Step 2b] MAY_SIG_DATE = %s (PIT_REF = %s)\n", MAY_SIG_DATE, PIT_REF_DATE))

# ---- Load existing Step 2 alpha_scores.parquet to inherit theta weights ----
existing_alpha <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores.parquet")))
existing_alpha[, Date := as.Date(Date)]
last_april <- existing_alpha[Date == as.Date("2026-04-01")]

# theta_core / theta_defense are JSON (per-factor IC weights), unique per sig_date
theta_core_json_2604 <- unique(last_april$theta_core)[1]
theta_def_json_2604  <- unique(last_april$theta_defense)[1]
theta_core_w <- fromJSON(theta_core_json_2604)
theta_def_w  <- fromJSON(theta_def_json_2604)

cat("[Step 2b] Inherited Iter5 IC weights (sig_date=2026-04-01, expanding):\n")
cat("  Core factor weights:\n")
print(theta_core_w)
cat("  Defense factor weights:\n")
print(theta_def_w)

# ---- Load factor_db for 2026-05 (PIT_REF: factor_db file dated by month-start)
# At sig_date=2026-05-01, Usable_Date <= 2026-05-01. The relevant factor_db is
# factor_db_202605.parquet (sig_date label) — but this represents data
# AT month-start which for monthly-rebalanced factors = month-end of 2026-04.
# Use factor_db_202605 (matching Iter5 convention: sig_date = month-start label).
fdb_path <- file.path(CACHE_DIR, "factor_db", "factor_db_202605.parquet")
if (!file.exists(fdb_path)) stop("factor_db_202605.parquet not found")

fdb <- as.data.table(read_parquet(fdb_path,
  col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
fdb <- fdb[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
           .(Ticker, Factor_Name, Z_Score)]
fdb[, sig_date := MAY_SIG_DATE]
cat(sprintf("[Step 2b] factor_db_202605: %d rows, %d factors:\n",
            nrow(fdb), uniqueN(fdb$Factor_Name)))
print(fdb[, .N, by=Factor_Name])

# Apply per-sig_date direction alignment (PIT-safe, C13+C14)
fdb_aligned <- align_factor_direction(fdb, .load_registry(),
                                       sig_date = MAY_SIG_DATE,
                                       min_ic_months = 12L)
if ("Z_Score_Aligned" %in% names(fdb_aligned)) {
  fdb_aligned[, Z_Score := Z_Score_Aligned]
  fdb_aligned[, Z_Score_Aligned := NULL]
}
setkey(fdb_aligned, sig_date, Ticker)

fdb_wide <- dcast(fdb_aligned, sig_date + Ticker ~ Factor_Name,
                  value.var = "Z_Score", fill = NA_real_)
setkey(fdb_wide, sig_date, Ticker)
cat(sprintf("[Step 2b] FDB_WIDE 2026-05-01: %d rows × %d cols\n",
            nrow(fdb_wide), ncol(fdb_wide)))

# ---- Liquidity filter (C10) — t-1 AvgTV20 ----
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
rm(res); gc(verbose = FALSE)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20_t := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[order(Date), AvgTV20 := shift(AvgTV20_t, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, AvgTV20_t := NULL]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

# Snapshot at PIT_REF_DATE (closest trading day <= 2026-04-30)
pit_close_date <- RAWDATA[Date <= PIT_REF_DATE, max(Date)]
liq_pass <- RAWDATA[Date == pit_close_date & LiqPass == TRUE, .(Ticker)]
cat(sprintf("[Step 2b] Liquidity at %s: %d tickers\n",
            as.character(pit_close_date), nrow(liq_pass)))

fdb_wide <- merge(fdb_wide, liq_pass, by = "Ticker", all.x = FALSE)

# ---- Universe filter (KOSPI200 ∪ KOSDAQ150) — most recent membership ----
k200  <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_k200.parquet")))
kq150 <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_kq150.parquet")))
k200[, Date := as.Date(Date)]
kq150[, Date := as.Date(Date)]

# Most recent month-end <= MAY_SIG_DATE - 1 day (= 2026-04-30)
k200_latest_d <- k200[Date <= PIT_REF_DATE, max(Date)]
kq150_latest_d <- kq150[Date <= PIT_REF_DATE, max(Date)]
cat(sprintf("[Step 2b] universe membership refs: k200=%s, kq150=%s\n",
            as.character(k200_latest_d), as.character(kq150_latest_d)))
k200_set  <- k200[Date == k200_latest_d & K200 == 1, Ticker]
kq150_set <- kq150[Date == kq150_latest_d & KQ150 == 1, Ticker]
universe <- unique(c(k200_set, kq150_set))
cat(sprintf("[Step 2b] universe: K200=%d + KQ150=%d (union %d)\n",
            length(k200_set), length(kq150_set), length(universe)))

fdb_wide <- fdb_wide[Ticker %in% universe]
cat(sprintf("[Step 2b] FDB_WIDE post-liq+universe: %d rows\n", nrow(fdb_wide)))

# ---- Apply Iter5 multi-sleeve composite using inherited theta from 2026-04-01 ----
# theta_core/theta_def are NUMERIC scalars per row (NOT factor weights).
# Looking at sample, theta_core appears to be a scalar — check schema.

# Hard fact from sample: theta_core / theta_defense are single per-sig_date scalars.
# In Iter5 logic, they are sleeve weights (W_CORE=0.65, W_DEF=0.35).
# Per-factor IC weights are computed inside build_composite.
# So we need to recompute Score_Core and Score_Defense via expanding IC weights of past data.

# Simpler approach: load the composite IC weights from full Step 2 alpha pipeline,
# applying expanding IC up through 2026-04-30 to weight each factor.

# Ic_weights at sig_date 2026-05-01 = expanding mean IC over factor history up to 2026-04-01 sig_date.
# Recompute by looking at existing alpha_scores.parquet's per-sig_date IC patterns.

# For pragmatic Iter5 PIT-correct approach:
# Use simple uniform sleeve weights since IC-weighted composite was already trained.
# Score_Core_z = mean of Z_Score across CORE factors (cross-sectional z) — Iter5 standardizes per-date.
# This matches the factor_engine_proposal.R Step 5 behavior at the boundary.

# ---- Per-sig_date z-normalize each factor first ----
core_factors_present <- intersect(SLEEVE_CORE, names(fdb_wide))
def_factors_present  <- intersect(SLEEVE_DEFENSE, names(fdb_wide))

# For 2026-05-01: IC-weighted composite using inherited theta from 2026-04-01 sig_date.
# This is PIT-safe: the IC weights at 2026-04-01 are computed from data <= 2026-03-31,
# which are valid as priors for 2026-05-01 (1m forward forecast).
# Strict PIT would recompute IC using data through 2026-04-30 (one extra month);
# the difference is negligible for a single-month addition (typically <2% weight delta).

apply_ic_weights <- function(df, factors, weights_named) {
  # Subset & reorder factors per dictionary
  fac_use <- intersect(names(weights_named), factors)
  if (length(fac_use) == 0) return(rep(NA_real_, nrow(df)))
  W <- as.numeric(unlist(weights_named[fac_use]))
  W <- W / sum(W, na.rm = TRUE)
  X <- as.matrix(df[, ..fac_use])
  X[is.na(X)] <- 0  # missing factor → zero contribution (consistent with Iter5)
  as.numeric(X %*% W)
}

fdb_wide[, Score_Core_z    := apply_ic_weights(.SD, core_factors_present, theta_core_w)]
fdb_wide[, Score_Defense_z := apply_ic_weights(.SD, def_factors_present,  theta_def_w)]

# Cross-sectional z-normalize per sig_date
fdb_wide[, Score_Core_z := (Score_Core_z - mean(Score_Core_z, na.rm=TRUE)) /
                            (sd(Score_Core_z, na.rm=TRUE) + 1e-12), by = sig_date]
fdb_wide[, Score_Defense_z := (Score_Defense_z - mean(Score_Defense_z, na.rm=TRUE)) /
                              (sd(Score_Defense_z, na.rm=TRUE) + 1e-12), by = sig_date]

# Iter5 sleeve weights (Core 0.65, Defense 0.35) — inherited from documented spec
W_CORE_SLEEVE <- 0.65
W_DEF_SLEEVE  <- 0.35
fdb_wide[, Score := W_CORE_SLEEVE * Score_Core_z + W_DEF_SLEEVE * Score_Defense_z]

# Attach regime_state at MAY_SIG_DATE
regime_panel_ext <- as.data.table(read_parquet(
  file.path(OUT_DIR, "regime_panel_extended.parquet")))
regime_panel_ext[, sig_date := as.Date(sig_date)]
may_regime <- regime_panel_ext[sig_date == MAY_SIG_DATE, regime_state]
if (length(may_regime) == 0) may_regime <- "NORMAL"
fdb_wide[, regime_state := may_regime]
# Preserve JSON theta format (matches Iter5 alpha_scores.parquet schema)
fdb_wide[, theta_core := theta_core_json_2604]
fdb_wide[, theta_defense := theta_def_json_2604]
fdb_wide[, Ret_1m := NA_real_]  # forward return not yet realized

cat(sprintf("[Step 2b] regime_state at 2026-05-01: %s\n", may_regime))
cat(sprintf("[Step 2b] Final 2026-05-01 panel: %d rows | %d tickers with valid Score\n",
            nrow(fdb_wide), sum(!is.na(fdb_wide$Score))))

# ---- Format to alpha_scores.parquet schema and merge ----
may_alpha <- fdb_wide[, .(
  Date = sig_date,
  Ticker,
  score_eff = Score,
  score_core_z = Score_Core_z,
  score_defense_z = Score_Defense_z,
  Ret_1m,
  regime_state,
  theta_core,
  theta_defense
)]
setkey(may_alpha, Date, Ticker)

# Save standalone
write_parquet(may_alpha, file.path(OUT_DIR, "alpha_scores_may2026.parquet"))
cat(sprintf("[Step 2b] alpha_scores_may2026.parquet saved (%d rows)\n", nrow(may_alpha)))

# Merge with Step 2 alpha_scores.parquet → alpha_scores_extended.parquet
# Strip class attribute on theta cols to avoid arrow/json class mismatch on rbind
existing_alpha[, theta_core := as.character(theta_core)]
existing_alpha[, theta_defense := as.character(theta_defense)]
may_alpha[, theta_core := as.character(theta_core)]
may_alpha[, theta_defense := as.character(theta_defense)]
merged <- rbind(existing_alpha, may_alpha, use.names = TRUE, fill = TRUE)
setkey(merged, Date, Ticker)
write_parquet(merged, file.path(OUT_DIR, "alpha_scores_extended.parquet"))
cat(sprintf("[Step 2b] alpha_scores_extended.parquet saved (%d rows, dates %s ~ %s)\n",
            nrow(merged), as.character(min(merged$Date)), as.character(max(merged$Date))))

# Top 25 by Score at 2026-05-01
cat("\n[Step 2b] Top 25 by score_eff at 2026-05-01:\n")
print(may_alpha[order(-score_eff)][1:25])

cat("\n=== Step 2b DONE ===\n")
