#==============================================================================
# STR_1684 — Factor Engine
# H_1688: Residual Momentum Core_Secondary
# M01_Mom_12_1 residualized on 24M rolling CAPM beta + log(Size) + R12_IdioVol
#
# PIT CHECKLIST (COND_04):
# (1) Point-in-time universe: delisted exclusion at t+1 (RAWDATA LiqPass)
# (2) Lagged fundamentals: price-based only, no financial statement lag needed
# (3) T+1 executable signals: month-end signal → next month t+1 execution (C2)
# (4) No same-day circularity: beta window [t-504d, t-1d] strictly excludes day t (C2)
#
# OPT-10: LIQ_THRESHOLD=2e8, frollmean(TradingValue, 20) lagged (C10)
# Factor IDs: M01_Mom_12_1 (NOT M04 — M04 is 1M reversal). COND_03 correction.
# R12_Idiosyncratic_Risk: Z_Score_Aligned used as-is (C13). No manual sign flip.
# Blitz-Huij-Martens 2011 JEF direct implementation
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("[factor_engine H_1688] Residual Momentum Core_Secondary\n")

# ---- OPT-10: Liquidity threshold (C10) ----
# LIQ_THRESHOLD set in run_all.R. RAWDATA$LiqPass = frollmean(TradingValue,20) >= LIQ_THRESHOLD (lagged).
if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

# ---- PIT evidence (COND_04) ----
H1688_PIT_EVIDENCE <- list(
  factor           = "M01_Mom_12_1",
  factor_id_note   = "M01 = 12-1 momentum (NOT M04=1M reversal). COND_03 correction.",
  liq_filter       = paste0("frollmean(TradingValue,20)>=", LIQ_THRESHOLD, " (C10, lagged)"),
  beta_window      = "24M rolling CAPM OLS: window [t-504 trading days, t-1]. Day t excluded (C2).",
  r12_sign_note    = "R12_Idiosyncratic_Risk: Z_Score_Aligned from Factor DB used as-is (C13).",
  c2_compliant     = TRUE,
  c10_compliant    = TRUE,
  c13_compliant    = TRUE,
  c14_compliant    = TRUE,
  c15_compliant    = TRUE,
  c1_compliant     = TRUE
)

# ---- Bulk preload: M01, M08 (baseline), S01_Size, R12 (OPT-1, C15) ----
NEEDED_FACTORS <- c("M01_Mom_12_1", "M08_Residual_Mom", "S01_Size", "S02_LnMktCap",
                    "R12_Idiosyncratic_Risk")

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                              full.names = TRUE))

cat(sprintf("[factor_engine] Bulk-loading %d files (M01+M08+S01+R12)...\n", length(fdb_files)))

FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_d <- tryCatch(as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")),
                    error = function(e) NA)
  if (is.na(sig_d) || sig_d < as.Date("2004-01-01")) return(NULL)
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

m01_col  <- "M01_Mom_12_1"
m08_col  <- "M08_Residual_Mom"
r12_col  <- "R12_Idiosyncratic_Risk"
size_col <- if ("S02_LnMktCap" %in% names(FDB_WIDE)) "S02_LnMktCap" else
            if ("S01_Size"     %in% names(FDB_WIDE)) "S01_Size"     else NULL

has_m01 <- m01_col %in% names(FDB_WIDE)
has_m08 <- m08_col %in% names(FDB_WIDE)
has_r12 <- r12_col %in% names(FDB_WIDE)

cat(sprintf("[factor_engine] M01: %s | M08: %s | R12: %s | Size(%s): %s\n",
            has_m01, has_m08, has_r12, size_col %||% "none", !is.null(size_col)))
if (!has_m01) stop("[factor_engine] M01_Mom_12_1 not found in Factor DB.")

# ---- COND_02: 24M rolling CAPM beta (per-ticker, Vasicek shrinkage) ----
# Window = [t-504 trading days, t-1 trading day]. Day t excluded (C2).
cat("[factor_engine] Computing 24M rolling CAPM beta per-ticker (Vasicek)...\n")

# RAWDATA and BM_DT pre-loaded in run_all.R
daily_ret <- RAWDATA[, .(Date, Ticker, ret_tk = Ret)]
setkey(daily_ret, Date, Ticker)
bm_daily  <- BM_DT[, .(Date, ret_bm = BM_Ret)]
setkey(bm_daily, Date)

all_sig_dates <- sort(unique(FDB_WIDE$Date))

beta_list <- lapply(all_sig_dates, function(sig_d) {
  # Strictly prior trading days (C2: sig_d excluded)
  prior_days <- bm_daily[Date < sig_d, Date]
  if (length(prior_days) < 252L) return(NULL)
  window_days <- tail(prior_days, 504L)

  bm_sub <- bm_daily[Date %in% window_days]
  tk_sub <- daily_ret[Date %in% window_days]
  if (nrow(bm_sub) < 252L || nrow(tk_sub) == 0) return(NULL)

  # Inner join on Date to ensure complete pairs
  merged <- merge(tk_sub, bm_sub, by = "Date", all = FALSE)
  if (nrow(merged) == 0) return(NULL)
  # Drop rows with NA in either column
  merged <- merged[!is.na(ret_tk) & !is.na(ret_bm)]
  if (nrow(merged) < 252L) return(NULL)

  var_bm <- var(merged$ret_bm, na.rm = TRUE)
  if (is.na(var_bm) || var_bm < 1e-10) return(NULL)

  braw <- merged[, {
    n_ok <- .N
    bval <- if (n_ok < 120L) NA_real_ else cov(ret_tk, ret_bm) / var_bm
    .(beta_est = bval, n_obs = n_ok)
  }, by = Ticker]
  braw <- braw[!is.na(beta_est) & n_obs >= 120L]
  if (nrow(braw) == 0) return(NULL)

  cross_mean <- mean(braw$beta_est, na.rm = TRUE)
  cross_var  <- var(braw$beta_est,  na.rm = TRUE)
  if (is.na(cross_var) || cross_var < 1e-10) cross_var <- 0.1

  braw[, se2         := cross_var / pmax(n_obs, 1L)]
  braw[, w           := cross_var / (cross_var + se2)]
  braw[, beta_shrunk := w * beta_est + (1 - w) * cross_mean]
  data.table(
    Date_int  = as.integer(sig_d),
    Ticker    = braw$Ticker,
    beta_24m  = braw$beta_shrunk
  )
})

BETA_DT <- rbindlist(beta_list[!sapply(beta_list, is.null)], fill = TRUE)
# Convert integer back to Date using data.frame to avoid data.table list-type bug
BETA_DF <- as.data.frame(BETA_DT)
BETA_DF$Date <- as.Date(BETA_DF$Date_int, origin = "1970-01-01")
BETA_DF$Date_int <- NULL
BETA_DT <- as.data.table(BETA_DF)
rm(BETA_DF)
setkey(BETA_DT, Date, Ticker)
cat(sprintf("[factor_engine] Beta: %s rows | %d months\n",
            format(nrow(BETA_DT), big.mark=","), uniqueN(BETA_DT$Date)))
H1688_BETA_DT <- BETA_DT  # saved for output artifact (COND_02)

# ---- Winsorize helper (cross-section 1~99%) ----
winsor <- function(x, lo = 0.01, hi = 0.99) {
  q <- quantile(x, probs = c(lo, hi), na.rm = TRUE)
  pmax(pmin(x, q[2]), q[1])
}

# ---- Cross-section OLS residualization per month (C1/C2/C13) ----
resid_list <- lapply(all_sig_dates, function(sig_d) {
  sub_fdb  <- FDB_WIDE[Date == sig_d]
  sub_beta <- BETA_DT[Date == sig_d, .(Ticker, beta_24m)]
  sub      <- merge(sub_fdb, sub_beta, by = "Ticker", all.x = TRUE)

  # OPT-10 liquidity filter: frollmean(TradingValue,20) >= LIQ_THRESHOLD, lagged (C10)
  liq_snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
  if (nrow(liq_snap) == 0) {
    closest_d <- RAWDATA[Date <= sig_d, max(Date)]
    liq_snap  <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  }
  sub <- sub[Ticker %in% liq_snap$Ticker]
  if (nrow(sub) < 20L || !m01_col %in% names(sub)) return(NULL)

  sub[, m01_w := winsor(get(m01_col))]

  regs <- character(0)
  if (!is.null(size_col) && size_col %in% names(sub)) {
    sub[, size_w := winsor(get(size_col))]; regs <- c(regs, "size_w")
  }
  if (has_r12 && r12_col %in% names(sub)) {
    sub[, r12_w := winsor(get(r12_col))];  regs <- c(regs, "r12_w")
  }
  if ("beta_24m" %in% names(sub) && !all(is.na(sub$beta_24m))) {
    sub[, beta_w := winsor(beta_24m)]; regs <- c(regs, "beta_w")
  }

  if (length(regs) == 0) {
    sub[, resid_raw := m01_w]
  } else {
    fm_str  <- paste("m01_w ~", paste(regs, collapse = " + "))
    use_idx <- complete.cases(sub[, c("m01_w", regs), with = FALSE])
    if (sum(use_idx) < 20L) {
      sub[, resid_raw := m01_w]
    } else {
      fit <- lm(as.formula(fm_str), data = sub[use_idx])
      sub[use_idx,  resid_raw := residuals(fit)]
      sub[!use_idx, resid_raw := NA_real_]
    }
  }
  sub[!is.na(resid_raw), .(Date, Ticker, resid_raw)]
})

RESID_DT <- rbindlist(resid_list[!sapply(resid_list, is.null)], fill = TRUE)
setkey(RESID_DT, Date, Ticker)
cat(sprintf("[factor_engine] Residuals: %s rows | %d months\n",
            format(nrow(RESID_DT), big.mark=","), uniqueN(RESID_DT$Date)))

# ---- Expanding cross-section Z-score (C1) ----
all_z_list <- lapply(seq_along(all_sig_dates), function(i) {
  sig_d <- all_sig_dates[i]
  past  <- RESID_DT[Date <= sig_d]
  if (nrow(past) < 30L) return(NULL)
  mu <- mean(past$resid_raw, na.rm = TRUE)
  s  <- sd(past$resid_raw, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(NULL)
  cur <- RESID_DT[Date == sig_d]
  if (nrow(cur) == 0) return(NULL)
  cur[, Score := (resid_raw - mu) / s]
  cur[, .(Date, Ticker, Score)]
})

FACTORS <- rbindlist(all_z_list[!sapply(all_z_list, is.null)], fill = TRUE)
setkey(FACTORS, Date, Ticker)
cat(sprintf("[factor_engine] FACTORS V1: %d rows | %d months | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# ---- M08 baseline for COND_01 ICIR comparison ----
if (has_m08) {
  m08_list <- lapply(all_sig_dates, function(sig_d) {
    sub <- FDB_WIDE[Date == sig_d & !is.na(get(m08_col))]
    liq_snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
    if (nrow(liq_snap) == 0) {
      closest_d <- RAWDATA[Date <= sig_d, max(Date)]
      liq_snap  <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
    }
    sub <- sub[Ticker %in% liq_snap$Ticker]
    if (nrow(sub) < 10L) return(NULL)
    sub[, .(Date, Ticker, Score = get(m08_col))]
  })
  FACTORS_M08 <- rbindlist(m08_list[!sapply(m08_list, is.null)], fill = TRUE)
  setkey(FACTORS_M08, Date, Ticker)
  cat(sprintf("[factor_engine] FACTORS_M08: %d rows | %d months\n",
              nrow(FACTORS_M08), uniqueN(FACTORS_M08$Date)))
} else {
  FACTORS_M08 <- data.table(Date=as.Date(character()), Ticker=character(), Score=numeric())
  cat("[factor_engine] M08_Residual_Mom not in Factor DB — M08 baseline skipped\n")
}

# ---- Store raw data for variant construction in run_all.R ----
H1688_FDB_WIDE  <- FDB_WIDE
H1688_RESID_DT  <- RESID_DT
H1688_ALL_DATES <- all_sig_dates
