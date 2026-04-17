# STR_1549: Defense Core Alpha (D01 + D02 + Q07)
# Weighted RankCombo: IdioVol 50% + Beta 30% + EarningsStability 20%
# Academic basis: Frazzini & Pedersen (2014) BAB + Ang et al. (2006) IdioVol puzzle
#   + Dichev & Tang (2009) earnings stability as quality filter
# D01 = primary alpha (ICIR 0.512), D02 = secondary reinforcement (L-555: standalone zero),
#   Q07 = noise filter (L-738: standalone alpha absent but OOS retention 0.96)
#
# Construction: sector-neutral, size-neutral OFF (B1: size-neutral harmful for defense)
# PIT: Factor DB Z_Score_Aligned via Arrow (C13/C15). Daily rawdata (C2 clean).
#      Liquidity t-1 lagged (C10). No full-sample stats (C1).

cat("[factor_engine] STR_1549: Defense Core Alpha (D01+D02+Q07)...\n")
set.seed(1549)
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

LIQ_THRESHOLD  <- 2e8
NEEDED_FACTORS <- c("D01_IdioVol", "D02_Beta", "Q07_Earnings_Stability")
FACTOR_WEIGHTS <- c(D01_IdioVol = 0.50, D02_Beta = 0.30, Q07_Earnings_Stability = 0.20)

# --- Load Factor DB via Arrow (C15 compliant) ---
CACHE_DIR_FDB <- file.path(CACHE_DIR, "factor_db")

ds <- open_dataset(CACHE_DIR_FDB, format = "parquet")
FDB_ALL <- ds |>
  dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |>
  dplyr::select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  dplyr::collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]

# Align factor direction (C13: Z_Score_Aligned only, no manual sign flip)
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | factors: %s\n", nrow(FDB_ALL),
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

# --- Prepare monthly signal dates ---
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]

# --- Liquidity: 20d avg trading value, t-1 lagged (C10) ---
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# --- Sector information for sector-neutral scoring (B1: sector-neutral required) ---
# Use GICS sector from RAWDATA if available, otherwise skip neutralization
has_sector <- "Sector" %in% names(RAWDATA)
if (!has_sector) {
  # Try to get sector from DART or other source
  sector_file <- file.path(INFRA_DIR, "sector_map.csv")
  if (file.exists(sector_file)) {
    sector_map <- fread(sector_file)
    has_sector_map <- TRUE
  } else {
    has_sector_map <- FALSE
    cat("  [WARN] No sector data found. Sector-neutral scoring disabled.\n")
  }
}

# --- Signal generation loop ---
fdb_dates <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  # PIT: use only factor data available on or before signal date (C14, C15)
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)

  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  # Pivot to wide format
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Merge liquidity (t-1 lagged, C10 compliant)
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 30L) { n_skipped <- n_skipped + 1L; next }

  # --- Sector-neutral percentile ranking (B1 requirement) ---
  # Within each sector, compute percentile ranks, then combine
  if (has_sector && "Sector" %in% names(RAWDATA)) {
    sec_info <- RAWDATA[Date == sig_d, .(Ticker, Sector)]
    fdt_wide <- merge(fdt_wide, sec_info, by = "Ticker", all.x = TRUE)
    fdt_wide[is.na(Sector), Sector := "Unknown"]

    # Sector-neutral ranking: rank within sector, then normalize to [0, 1]
    fdt_wide[, Score := 0.0]
    nc <- 0L
    for (fn in NEEDED_FACTORS) {
      if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) >= 10L) {
        # Rank within sector
        fdt_wide[, (paste0("r_", fn)) :=
          frank(get(fn), na.last = "keep", ties.method = "average") / .N,
          by = Sector]
        fdt_wide[, Score := Score + FACTOR_WEIGHTS[fn] *
          fifelse(is.na(get(paste0("r_", fn))), 0.5, get(paste0("r_", fn)))]
        nc <- nc + 1L
      }
    }
  } else if (exists("has_sector_map") && has_sector_map) {
    fdt_wide <- merge(fdt_wide, sector_map[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
    fdt_wide[is.na(Sector), Sector := "Unknown"]

    fdt_wide[, Score := 0.0]
    nc <- 0L
    for (fn in NEEDED_FACTORS) {
      if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) >= 10L) {
        fdt_wide[, (paste0("r_", fn)) :=
          frank(get(fn), na.last = "keep", ties.method = "average") / .N,
          by = Sector]
        fdt_wide[, Score := Score + FACTOR_WEIGHTS[fn] *
          fifelse(is.na(get(paste0("r_", fn))), 0.5, get(paste0("r_", fn)))]
        nc <- nc + 1L
      }
    }
  } else {
    # Fallback: cross-sectional ranking (no sector neutralization)
    fdt_wide[, Score := 0.0]
    nc <- 0L
    for (fn in NEEDED_FACTORS) {
      if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) >= 10L) {
        fdt_wide[, (paste0("r_", fn)) :=
          frank(get(fn), na.last = "keep", ties.method = "average") / sum(!is.na(get(fn)))]
        fdt_wide[, Score := Score + FACTOR_WEIGHTS[fn] *
          fifelse(is.na(get(paste0("r_", fn))), 0.5, get(paste0("r_", fn)))]
        nc <- nc + 1L
      }
    }
  }

  if (nc == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

cat(sprintf("  [Done] %d signal months | %d skipped | %d total FACTORS rows\n",
            n_done, n_skipped, nrow(FACTORS)))
