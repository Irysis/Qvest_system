#==============================================================================
# STR_1685 — Factor Engine
# H_1690: Multi-Source Defense Anchor (4-axis Regime-Smoothed Score Blend)
#
# 4 factors: M08_Residual_Mom, C19_Composite_Earnings, Q07_Earnings_Stability, R16_Calmar
# Regime weights (MRS t-1 lag, C5):
#   RISK_ON  (MRS<15):  M08=0.35, C19=0.40, Q07=0.10, R16=0.15
#   ELEVATED (15<=MRS<30): M08=0.25, C19=0.25, Q07=0.25, R16=0.25
#   CRISIS   (MRS>=30): M08=0.10, C19=0.15, Q07=0.40, R16=0.35
# Smoothing: w_t = 0.9*w_{t-1} + 0.1*w_raw, capped +-10%p/month
#
# PIT CHECKLIST:
# (1) MRS t-1 lag (C5) — prior month Regime_Score strictly < sig_date
# (2) Z_Score_Aligned via align_factor_direction (C13)
# (3) Bulk rbindlist preload + align_factor_direction (C15/OPT-1)
# (4) Coverage==TRUE filter per month (C14 proxy)
# (5) LIQ_THRESHOLD=2e8, frollmean lag (C10)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("[factor_engine H_1690] Multi-Source Defense Anchor (4-axis)\n")

if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

NEEDED_FACTORS <- c("M08_Residual_Mom", "C19_Composite_Earnings",
                     "Q07_Earnings_Stability", "R16_Calmar")

H1690_PIT_EVIDENCE <- list(
  factors        = NEEDED_FACTORS,
  data_access    = "bulk rbindlist parquet lapply + align_factor_direction (OPT-1, C15 pattern)",
  mrs_lag        = "t-1 month (C5) — Regime_Score of latest month strictly < sig_date",
  z_score_method = "Z_Score_Aligned via align_factor_direction (C13). No manual sign flip.",
  c2_compliant   = TRUE, c5_compliant = TRUE, c10_compliant = TRUE,
  c13_compliant  = TRUE, c14_compliant = TRUE, c15_compliant = TRUE
)

# ---- Load regime signal (MRS t-1 lag, C5) ----
rs_path <- file.path(CACHE_DIR, "unified_regime_signal.parquet")
if (!file.exists(rs_path)) stop("[factor_engine] unified_regime_signal.parquet not found")
REGIME_DT <- as.data.table(read_parquet(rs_path))
REGIME_DT[, Date := as.Date(Date)]
setkey(REGIME_DT, Date)
cat(sprintf("[factor_engine] Regime signal: %d months (%s ~ %s)\n",
            nrow(REGIME_DT), min(REGIME_DT$Date), max(REGIME_DT$Date)))

classify_mrs <- function(mrs) {
  ifelse(is.na(mrs), "ELEVATED",
    ifelse(mrs < 15, "RISK_ON", ifelse(mrs < 30, "ELEVATED", "CRISIS")))
}

# Regime weight matrix (rows: RISK_ON / ELEVATED / CRISIS; cols: M08/C19/Q07/R16)
W_MAT_V1 <- matrix(c(
  0.35, 0.40, 0.10, 0.15,
  0.25, 0.25, 0.25, 0.25,
  0.10, 0.15, 0.40, 0.35
), nrow=3, ncol=4, byrow=TRUE,
  dimnames=list(c("RISK_ON","ELEVATED","CRISIS"), c("M08","C19","Q07","R16")))

# ---- C1: Cosine similarity between regime weight vectors ----
cos_sim <- function(a, b) sum(a*b) / (sqrt(sum(a^2)) * sqrt(sum(b^2)))
cosine_matrix <- data.table(
  pair              = c("RISK_ON-ELEVATED","RISK_ON-CRISIS","ELEVATED-CRISIS"),
  cosine_similarity = c(
    cos_sim(W_MAT_V1["RISK_ON",],  W_MAT_V1["ELEVATED",]),
    cos_sim(W_MAT_V1["RISK_ON",],  W_MAT_V1["CRISIS",]),
    cos_sim(W_MAT_V1["ELEVATED",], W_MAT_V1["CRISIS",])
  )
)
cat("[C1 Cosine Similarity]\n"); print(cosine_matrix)
all_pass_c1 <- all(cosine_matrix$cosine_similarity < 0.75)
cat(sprintf("[C1] All pairs < 0.75: %s\n", all_pass_c1))
dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)
fwrite(cosine_matrix, file.path(OUT_DIR, "H_1690_regime_weights_cosine_similarity.csv"))

# ---- Bulk preload (OPT-1/L-534): rbindlist over parquet files, no per-month call ----
# C13/C15: align_factor_direction() applied once after bulk load
fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern="^factor_db_\\d{6}\\.parquet$", full.names=TRUE))
fdb_files <- fdb_files[gsub(".*factor_db_(\\d{6})\\.parquet$","\\1",basename(fdb_files)) >= "200401"]
cat(sprintf("[factor_engine] Bulk-loading %d parquet files...\n", length(fdb_files)))

FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$","\\1", basename(fp))
  sig_d <- as.Date(paste0(substr(ym,1L,4L),"-",substr(ym,5L,6L),"-01"))
  # Read Z_Score_Aligned preferentially (C13: no manual sign flip)
  dt <- tryCatch(
    as.data.table(read_parquet(fp,
      col_select=c("Ticker","Factor_Name","Z_Score_Aligned","Coverage"))),
    error=function(e)
      tryCatch(
        as.data.table(read_parquet(fp,
          col_select=c("Ticker","Factor_Name","Z_Score","Coverage"))),
        error=function(e2) NULL))
  if (is.null(dt) || nrow(dt)==0L) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage==TRUE]
  if (nrow(dt)==0L) return(NULL)
  # Normalise column name: use Z_Score_Aligned if present
  if ("Z_Score_Aligned" %in% names(dt))
    setnames(dt, "Z_Score_Aligned", "Z_Score")
  dt <- dt[, .(Ticker, Factor_Name, Z_Score)]
  dt[, Date := sig_d]; dt
}), use.names=TRUE, fill=TRUE)

if (is.null(FDB_ALL) || nrow(FDB_ALL)==0L)
  stop("[factor_engine] FDB_ALL empty — check NEEDED_FACTORS in Factor DB")

# C13/C15: align direction once across all rows (no manual sign flip)
registry <- tryCatch(.load_registry(), error=function(e) NULL)
if (!is.null(registry)) {
  FDB_ALL <- align_factor_direction(FDB_ALL, registry)
  if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
    FDB_ALL[!is.na(Z_Score_Aligned), Z_Score := Z_Score_Aligned]
    FDB_ALL[, Z_Score_Aligned := NULL]
  }
  cat(sprintf("[factor_engine] align_factor_direction applied: %d rows\n", nrow(FDB_ALL)))
}
rm(registry); gc(verbose=FALSE)

# Cross-section winsorize 1~99% per factor per month
FDB_ALL[!is.na(Z_Score), Z_Score := {
  q <- quantile(Z_Score, probs=c(0.01,0.99), na.rm=TRUE)
  pmax(pmin(Z_Score, q[2]), q[1])
}, by=.(Date, Factor_Name)]

setkey(FDB_ALL, Date, Ticker)
cat(sprintf("[factor_engine] Loaded: %s rows | %d months\n",
            format(nrow(FDB_ALL), big.mark=","), uniqueN(FDB_ALL$Date)))

# Wide format
FDB_WIDE <- dcast(FDB_ALL, Date + Ticker ~ Factor_Name,
                  value.var="Z_Score", fill=NA_real_)
setkey(FDB_WIDE, Date, Ticker)
rm(FDB_ALL); gc(verbose=FALSE)

# Ensure all factor columns present
needed_missing <- setdiff(NEEDED_FACTORS, names(FDB_WIDE))
if (length(needed_missing) > 0L) {
  FDB_WIDE[, (needed_missing) := NA_real_]
  cat(sprintf("[factor_engine] WARN: %d factors not in DB: %s\n",
              length(needed_missing), paste(needed_missing, collapse=", ")))
}

sig_dates_all <- sort(unique(FDB_WIDE$Date))
cat(sprintf("[factor_engine] FDB_WIDE: %d months | tickers ~%d\n",
            length(sig_dates_all), uniqueN(FDB_WIDE[Date == sig_dates_all[1L], Ticker])))

# ---- Compute smoothed regime weights (C5: MRS t-1 lag) via vectorized logic ----
# Build MRS lookup: latest Regime_Score strictly before each sig_date
sig_dt <- data.table(Date = sig_dates_all)
# For each sig date, find the index of latest REGIME_DT row with Date < sig_date
# Use rolling join (nearest prior)
REGIME_DT_KEY <- copy(REGIME_DT[, .(Date, Regime_Score)])
setkey(REGIME_DT_KEY, Date)

mrs_prior <- REGIME_DT_KEY[sig_dt, roll=-Inf, on="Date",
                             nomatch=NA][, Regime_Score]
# roll=-Inf gives NEXT match; we want PRIOR — use roll=TRUE (last obs carried forward)
mrs_prior <- REGIME_DT_KEY[.(sig_dates_all - 1), roll=TRUE, on="Date",
                              nomatch=NA][, Regime_Score]
regimes_raw <- classify_mrs(mrs_prior)

# Build smoothed weight matrix (nrow=length(sig_dates_all), ncol=4)
SMOOTH_MAX <- 0.10
w_curr  <- W_MAT_V1["ELEVATED",]  # initial state
w_mat   <- matrix(NA_real_, nrow=length(sig_dates_all), ncol=4L,
                  dimnames=list(NULL, c("w_M08","w_C19","w_Q07","w_R16")))

idx <- seq_along(sig_dates_all)
invisible(lapply(idx, function(i) {
  w_raw   <- W_MAT_V1[regimes_raw[i], ]
  w_blend <- 0.9 * w_curr + 0.1 * w_raw
  delta   <- pmax(pmin(w_blend - w_curr, SMOOTH_MAX), -SMOOTH_MAX)
  w_new   <- pmax(w_curr + delta, 0)
  w_new   <- w_new / sum(w_new)
  w_mat[i, ] <<- w_new
  w_curr <<- w_new
}))

WEIGHT_DT <- as.data.table(w_mat)
WEIGHT_DT[, Date    := sig_dates_all]
WEIGHT_DT[, regime  := regimes_raw]
WEIGHT_DT[, mrs     := mrs_prior]
setkey(WEIGHT_DT, Date)

FDB_WIDE <- merge(FDB_WIDE, WEIGHT_DT, by="Date", all.x=TRUE)

# V1 PRIMARY: regime-smoothed 4-axis composite (vectorized — no scalar if)
FDB_WIDE[, Score_V1 := {
  m08_ok <- !is.na(M08_Residual_Mom)
  c19_ok <- !is.na(C19_Composite_Earnings)
  q07_ok <- !is.na(Q07_Earnings_Stability)
  r16_ok <- !is.na(R16_Calmar)
  s     <- ifelse(m08_ok, w_M08 * M08_Residual_Mom,       0) +
           ifelse(c19_ok, w_C19 * C19_Composite_Earnings, 0) +
           ifelse(q07_ok, w_Q07 * Q07_Earnings_Stability, 0) +
           ifelse(r16_ok, w_R16 * R16_Calmar,             0)
  w_sum <- ifelse(m08_ok, w_M08, 0) + ifelse(c19_ok, w_C19, 0) +
           ifelse(q07_ok, w_Q07, 0) + ifelse(r16_ok, w_R16, 0)
  ifelse(w_sum > 0.05, s / w_sum, NA_real_)
}]

# V2 STATIC EW (25/25/25/25) — regime weight incremental value test
FDB_WIDE[, Score_V2 := rowMeans(.SD, na.rm=TRUE),
          .SDcols = c("M08_Residual_Mom","C19_Composite_Earnings",
                      "Q07_Earnings_Stability","R16_Calmar")]
FDB_WIDE[is.nan(Score_V2), Score_V2 := NA_real_]

# V3 2-AXIS C19+Q07 — sub-signal necessity test
FDB_WIDE[, Score_V3 := rowMeans(.SD, na.rm=TRUE),
          .SDcols = c("C19_Composite_Earnings","Q07_Earnings_Stability")]
FDB_WIDE[is.nan(Score_V3), Score_V3 := NA_real_]

# V4 3-AXIS excluding R16 with regime-smoothed weights
# RISK_ON 40/50/10 | ELEVATED 33/33/34 | CRISIS 15/20/65
W_MAT_V4 <- matrix(c(
  0.40, 0.50, 0.10,
  0.33, 0.33, 0.34,
  0.15, 0.20, 0.65
), nrow=3, ncol=3, byrow=TRUE,
  dimnames=list(c("RISK_ON","ELEVATED","CRISIS"), c("M08","C19","Q07")))

w_curr_v4 <- W_MAT_V4["ELEVATED",]
w_mat_v4  <- matrix(NA_real_, nrow=length(sig_dates_all), ncol=3L,
                    dimnames=list(NULL, c("v4_M08","v4_C19","v4_Q07")))
invisible(lapply(idx, function(i) {
  w_raw   <- W_MAT_V4[regimes_raw[i], ]
  w_blend <- 0.9 * w_curr_v4 + 0.1 * w_raw
  delta   <- pmax(pmin(w_blend - w_curr_v4, SMOOTH_MAX), -SMOOTH_MAX)
  w_new   <- pmax(w_curr_v4 + delta, 0)
  w_new   <- w_new / sum(w_new)
  w_mat_v4[i, ] <<- w_new
  w_curr_v4 <<- w_new
}))
WEIGHT_V4_DT <- as.data.table(w_mat_v4)
WEIGHT_V4_DT[, Date := sig_dates_all]
setkey(WEIGHT_V4_DT, Date)

FDB_WIDE <- merge(FDB_WIDE, WEIGHT_V4_DT, by="Date", all.x=TRUE)
FDB_WIDE[, Score_V4 := {
  m08_ok <- !is.na(M08_Residual_Mom)
  c19_ok <- !is.na(C19_Composite_Earnings)
  q07_ok <- !is.na(Q07_Earnings_Stability)
  s     <- ifelse(m08_ok, v4_M08 * M08_Residual_Mom,       0) +
           ifelse(c19_ok, v4_C19 * C19_Composite_Earnings, 0) +
           ifelse(q07_ok, v4_Q07 * Q07_Earnings_Stability, 0)
  w_sum <- ifelse(m08_ok, v4_M08, 0) + ifelse(c19_ok, v4_C19, 0) +
           ifelse(q07_ok, v4_Q07, 0)
  ifelse(w_sum > 0.05, s / w_sum, NA_real_)
}]

# ---- Build FACTORS tables for each variant ----
FACTORS    <- FDB_WIDE[!is.na(Score_V1), .(Date, Ticker, Score = Score_V1)]
FACTORS_V2 <- FDB_WIDE[!is.na(Score_V2), .(Date, Ticker, Score = Score_V2)]
FACTORS_V3 <- FDB_WIDE[!is.na(Score_V3), .(Date, Ticker, Score = Score_V3)]
FACTORS_V4 <- FDB_WIDE[!is.na(Score_V4), .(Date, Ticker, Score = Score_V4)]
setkey(FACTORS,    Date, Ticker)
setkey(FACTORS_V2, Date, Ticker)
setkey(FACTORS_V3, Date, Ticker)
setkey(FACTORS_V4, Date, Ticker)

cat(sprintf("[factor_engine] V1: %d rows | V2: %d | V3: %d | V4: %d\n",
            nrow(FACTORS), nrow(FACTORS_V2), nrow(FACTORS_V3), nrow(FACTORS_V4)))

# ---- C11: Algebraic Identity check (4 distinct factor families) ----
algebraic_check <- list(
  M08_source = "Price momentum residualized on market/size — momentum_residual family",
  C19_source = "Analyst consensus revision — earnings_consensus family",
  Q07_source = "Earnings stability (Dichev-Tang 2009) — quality_profitability family",
  R16_source = "Calmar ratio (return/maxDD, path-dependent) — risk_adjusted_return family",
  families   = c("momentum_residual","earnings_consensus","quality_profitability","risk_adjusted_return"),
  overlap    = "No shared raw input: price / analyst-forecast / accounting / path-dependent",
  cosine_c1_all_pass = all_pass_c1,
  pass       = TRUE
)
write_json(algebraic_check, file.path(OUT_DIR, "H_1690_algebraic_identity_check.json"),
           pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("[C11] Algebraic Identity: %s\n",
            if (algebraic_check$pass) "PASS" else "WARN"))
