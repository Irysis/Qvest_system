#==============================================================================
# STR_1682 — Factor Engine
# H_1676: Residual Consensus Revision Breadth (Orthogonal PEAD, Diversifier)
#
# Signal: C13_Revision_Breadth_3m residualized on log(MarketCap) + R12_Idiosyncratic_Risk
# PIT: C13/R12/Size Z_Score_Aligned (C13), load via bulk parquet preload (C15/OPT-1)
# Expanding cross-section Z-score (C1). t+1 execution (C2). Winsorize 1~99%.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("[factor_engine H_1676] Residual Consensus Revision Breadth\n")

# ---- PIT evidence (COND_05) ----
# C13_Revision_Breadth_3m: analyst revision snapshot taken at month-end.
# load_month_factors uses sig_date <= Usable_Date (C14 compliant).
# Execution at t+1 month first trading day (C2 compliant).
# No forward revision data is used in signal construction.
H1676_PIT_EVIDENCE <- list(
  factor          = "C13_Revision_Breadth_3m",
  usable_date     = "Month-end consensus snapshot. Revision timestamps locked at month-end cutoff.",
  c14_compliant   = TRUE,   # load_month_factors(sig_date) uses Usable_Date <= sig_date
  c15_compliant   = TRUE,   # bulk parquet preload via factor_db_connector
  c2_compliant    = TRUE,   # signal → t+1 execution in run_all.R
  regressors_pit  = "log(MarketCap) from same-month factor DB (pre-event Z_Score_Aligned). R12_Idiosyncratic_Risk: rolling idiosyncratic vol, month-end snapshot. Both available at sig_date."
)

# ---- Bulk preload: C13, R12, Size (OPT-1: no loop load) ----
NEEDED_FACTORS <- c("C13_Revision_Breadth_3m", "R12_Idiosyncratic_Risk",
                    "S01_MarketCap", "S02_LnMktCap")  # size proxy candidates

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                        full.names = TRUE)
fdb_files <- sort(fdb_files)

cat(sprintf("[factor_engine] Bulk-loading %d factor DB files (C13+R12+Size)...\n",
            length(fdb_files)))

FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  ym  <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_d <- tryCatch(as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")),
                    error = function(e) NA)
  if (is.na(sig_d) || sig_d < as.Date("2002-01-01")) return(NULL)
  dt <- tryCatch(
    as.data.table(read_parquet(fp,
      col_select = c("Ticker", "Factor_Name", "Z_Score_Aligned", "Coverage"))),
    error = function(e) NULL
  )
  if (is.null(dt) || nrow(dt) == 0) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
           .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(dt) == 0) return(NULL)
  dt[, Date := sig_d]
  dt
}), use.names = TRUE, fill = TRUE)

setkey(FDB_ALL, Date, Ticker)
cat(sprintf("[factor_engine] Loaded: %s rows | %d months\n",
            format(nrow(FDB_ALL), big.mark=","), uniqueN(FDB_ALL$Date)))

# ---- Wide pivot (single dcast, OPT-1 compliant) ----
FDB_WIDE <- dcast(FDB_ALL, Date + Ticker ~ Factor_Name,
                  value.var = "Z_Score_Aligned", fill = NA_real_)
setkey(FDB_WIDE, Date, Ticker)
rm(FDB_ALL); gc(verbose = FALSE)

# Resolve size column
size_col <- if ("S02_LnMktCap" %in% names(FDB_WIDE)) "S02_LnMktCap" else
            if ("S01_MarketCap" %in% names(FDB_WIDE)) "S01_MarketCap" else NULL
c13_col  <- "C13_Revision_Breadth_3m"
r12_col  <- "R12_Idiosyncratic_Risk"

has_c13 <- c13_col %in% names(FDB_WIDE)
has_r12 <- r12_col %in% names(FDB_WIDE)

cat(sprintf("[factor_engine] C13: %s | R12: %s | Size(%s): %s\n",
            has_c13, has_r12, size_col %||% "none", !is.null(size_col)))

# ---- Liquidity-filtered signal universe (C10 — OPT-10) ----
# Use RAWDATA pre-computed AvgTV20 (20d lagged avg trading value, set in run_all.R)
# LIQ_THRESHOLD must be set before sourcing factor_engine.R
if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8

# ---- Winsorize helper (cross-section, 1~99%) ----
winsor <- function(x, lo = 0.01, hi = 0.99) {
  q <- quantile(x, probs = c(lo, hi), na.rm = TRUE)
  pmax(pmin(x, q[2]), q[1])
}

# ---- Cross-section OLS residualization per month (lapply, no for-loop) ----
all_sig_dates <- sort(unique(FDB_WIDE$Date))

# Expanding Z-score: accumulate cross-section residuals over months
# Per-cross-section OLS residuals → pool all months → expanding Z-score

# Step 1: compute raw residuals for each month (lapply, single pass)
resid_list <- lapply(all_sig_dates, function(sig_d) {
  sub <- FDB_WIDE[Date == sig_d]
  if (!has_c13 || !c13_col %in% names(sub)) return(NULL)

  # Liquidity filter (C10): keep only liquid tickers at sig_d
  # AvgTV20 in RAWDATA is lagged (no same-day), join by last RAWDATA date <= sig_d
  liq_snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
  if (is.null(liq_snap) || nrow(liq_snap) == 0) {
    # fallback: find closest RAWDATA date
    closest_d <- RAWDATA[Date <= sig_d, max(Date)]
    liq_snap  <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  }
  sub <- sub[Ticker %in% liq_snap$Ticker]
  if (nrow(sub) < 20L) return(NULL)

  sub[, c13_w := winsor(get(c13_col))]

  regs <- character(0)
  if (!is.null(size_col) && size_col %in% names(sub)) {
    sub[, size_w := winsor(get(size_col))]; regs <- c(regs, "size_w")
  }
  if (has_r12 && r12_col %in% names(sub)) {
    sub[, r12_w := winsor(get(r12_col))]; regs <- c(regs, "r12_w")
  }

  if (length(regs) == 0) {
    sub[, resid_raw := c13_w]
  } else {
    fm_str  <- paste("c13_w ~", paste(regs, collapse = " + "))
    use_idx <- complete.cases(sub[, c("c13_w", regs), with = FALSE])
    if (sum(use_idx) < 20L) {
      sub[, resid_raw := c13_w]
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

# ---- Expanding cross-section Z-score (C1 — no full-sample stats) ----
# For each month t, Z-score = (resid - mean(all resids through t)) / sd(all resids through t)
all_z_list <- lapply(seq_along(all_sig_dates), function(i) {
  sig_d    <- all_sig_dates[i]
  past     <- RESID_DT[Date <= sig_d]          # expanding window (C1)
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

cat(sprintf("[factor_engine] FACTORS: %d rows | %d months | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# ---- COND_04 rolling 3Y ICIR drift tracking data ----
# Stored in RESID_DT; run_all.R computes rolling ICIR after simulation
H1676_RESID_DT_FOR_ICIR <- RESID_DT
