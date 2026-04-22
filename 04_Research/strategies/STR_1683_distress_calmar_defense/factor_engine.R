#==============================================================================
# STR_1683 — Factor Engine
# H_1682: Distress + Calmar Defense Anchor
# Q25_Ohlson_O (60%) + R16_Calmar (40%) cross-family composite
#
# PIT: Z_Score_Aligned (C13), bulk parquet preload (C15/OPT-1)
# C1: expanding Z-score. C2: t+1 execution in run_all.R. C10: LIQ pre-filter.
# AX-003 PASS (no value). AX-004 PASS (distress != profitability). AX-005 PASS (no BAB/low-beta).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("[factor_engine H_1682] Distress+Calmar Defense Anchor\n")

# ---- PIT evidence (COND_04) ----
# Q25_Ohlson_O: annual financial statement logit. Usable_Date = May (annual T+5M lag, C4).
# R16_Calmar: price-based CAGR/MaxDD rolling ratio. Monthly snapshot, no C4 lag needed.
# Both loaded via load_month_factors (C14/C15 compliant).
H1682_PIT_EVIDENCE <- list(
  Q25_pit  = list(
    factor        = "Q25_Ohlson_O",
    data_type     = "annual financial statement (logit 9 ratios)",
    usable_date   = "May rebalance (annual T+5M lag, C4). load_month_factors uses Usable_Date <= sig_date.",
    c4_compliant  = TRUE,
    c14_compliant = TRUE,
    c15_compliant = TRUE,
    restatement   = "Non-retroactive: snapshot policy in compute_quality.R uses as-of fiscal year end data only."
  ),
  R16_pit  = list(
    factor        = "R16_Calmar",
    data_type     = "price-based CAGR/MaxDD ratio (rolling lookback)",
    usable_date   = "Month-end price snapshot. No financial statement lag needed.",
    c4_compliant  = TRUE,
    c14_compliant = TRUE,
    c15_compliant = TRUE
  ),
  composite_note = "Defense_score = 0.60 * z_Q25 + 0.40 * z_R16. Fixed weights, no re-tuning (COND_01)."
)

# ---- Bulk preload: Q25, R16 (OPT-1: no loop load) ----
NEEDED_FACTORS <- c("Q25_Ohlson_O", "R16_Calmar")

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                              full.names = TRUE))

cat(sprintf("[factor_engine] Bulk-loading %d files (Q25+R16)...\n", length(fdb_files)))

# LIQ_THRESHOLD=2e8 유동성 필터는 run_all.R Step 2 LiqPass 컬럼으로 적용됨 (C10)
# C13: Z_Score 로드 후 align_factor_direction() 경유 (Z_Score_Aligned 컬럼 parquet에 없음)
FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_d <- tryCatch(as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")),
                    error = function(e) NA)
  if (is.na(sig_d) || sig_d < as.Date("2002-01-01")) return(NULL)
  dt <- tryCatch(
    as.data.table(read_parquet(fp,
      col_select = c("Ticker","Factor_Name","Z_Score","Coverage"))),
    error = function(e) NULL
  )
  if (is.null(dt) || nrow(dt) == 0) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
           .(Ticker, Factor_Name, Z_Score)]
  if (nrow(dt) == 0) return(NULL)
  dt[, Date := sig_d]; dt
}), use.names = TRUE, fill = TRUE)

if (nrow(FDB_ALL) == 0) stop("[factor_engine] FDB_ALL empty — NEEDED_FACTORS not in parquet")
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
  FDB_ALL[, Z_Score := Z_Score_Aligned]; FDB_ALL[, Z_Score_Aligned := NULL]
}
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("[factor_engine] Loaded: %s rows | %d months\n",
            format(nrow(FDB_ALL), big.mark=","), uniqueN(FDB_ALL$Date)))

FDB_WIDE <- dcast(FDB_ALL, Date + Ticker ~ Factor_Name,
                  value.var = "Z_Score", fill = NA_real_)
setkey(FDB_WIDE, Date, Ticker)
rm(FDB_ALL); gc(verbose = FALSE)

q25_col <- "Q25_Ohlson_O"
r16_col <- "R16_Calmar"
has_q25 <- q25_col %in% names(FDB_WIDE)
has_r16 <- r16_col %in% names(FDB_WIDE)
cat(sprintf("[factor_engine] Q25: %s | R16: %s\n", has_q25, has_r16))

if (!has_q25 && !has_r16) stop("[factor_engine] Neither Q25 nor R16 found in Factor DB.")

# ---- Liquidity filter reference (C10 — LIQ_THRESHOLD from run_all.R) ----
if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

# ---- 4 variants per month: composite(60/40), 50/50, Q25-only, R16-only (COND_03) ----
all_sig_dates <- sort(unique(FDB_WIDE$Date))

# Step 1: build per-month raw composite scores (lapply, no for-loop)
raw_score_list <- lapply(all_sig_dates, function(sig_d) {
  sub <- FDB_WIDE[Date == sig_d]

  # Liquidity filter (C10)
  liq_snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
  if (nrow(liq_snap) == 0) {
    closest_d <- RAWDATA[Date <= sig_d, max(Date)]
    liq_snap  <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  }
  sub <- sub[Ticker %in% liq_snap$Ticker]
  if (nrow(sub) < 20L) return(NULL)

  z_q25 <- if (has_q25 && q25_col %in% names(sub)) sub[[q25_col]] else rep(NA_real_, nrow(sub))
  z_r16 <- if (has_r16 && r16_col %in% names(sub)) sub[[r16_col]] else rep(NA_real_, nrow(sub))

  data.table(
    Date    = sig_d,
    Ticker  = sub$Ticker,
    z_q25   = z_q25,
    z_r16   = z_r16,
    # Primary: 60/40 composite
    score_6040 = fifelse(!is.na(z_q25) & !is.na(z_r16),
                         0.6 * z_q25 + 0.4 * z_r16,
                         fifelse(!is.na(z_q25), z_q25, z_r16)),
    # Baseline: 50/50 composite (COND_03)
    score_5050 = fifelse(!is.na(z_q25) & !is.na(z_r16),
                         0.5 * z_q25 + 0.5 * z_r16,
                         fifelse(!is.na(z_q25), z_q25, z_r16)),
    # Q25-only baseline (COND_03)
    score_q25  = z_q25,
    # R16-only baseline (COND_03)
    score_r16  = z_r16
  )
})

RAW_SCORES <- rbindlist(raw_score_list[!sapply(raw_score_list, is.null)], fill = TRUE)
setkey(RAW_SCORES, Date, Ticker)
cat(sprintf("[factor_engine] Raw scores: %s rows | %d months\n",
            format(nrow(RAW_SCORES), big.mark=","), uniqueN(RAW_SCORES$Date)))

# ---- Expanding cross-section Z-score (C1) for primary composite ----
all_z_list <- lapply(seq_along(all_sig_dates), function(i) {
  sig_d <- all_sig_dates[i]
  past  <- RAW_SCORES[Date <= sig_d & !is.na(score_6040)]
  if (nrow(past) < 30L) return(NULL)
  mu <- mean(past$score_6040, na.rm = TRUE)
  s  <- sd(past$score_6040, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(NULL)
  cur <- RAW_SCORES[Date == sig_d & !is.na(score_6040)]
  if (nrow(cur) == 0) return(NULL)
  cur[, Score := (score_6040 - mu) / s]
  cur[, .(Date, Ticker, Score)]
})

FACTORS <- rbindlist(all_z_list[!sapply(all_z_list, is.null)], fill = TRUE)
setkey(FACTORS, Date, Ticker)

cat(sprintf("[factor_engine] FACTORS (primary 60/40): %d rows | %d months | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# ---- Store variant data for multi-variant analysis (COND_03) ----
H1682_RAW_SCORES <- RAW_SCORES
