#==============================================================================
# Step 2 — 8-Family Factor Panel v3.5 (load_month_factors PIT-C15 compliant)
#
# v1 lesson 적용:
#   - load_month_factors() 경유 (PIT-C13 Z_Score_Aligned + PIT-C15 direct read 금지)
#   - S01_Size: direction=higher_better (registry retain) — v1 double-flip bug 회피
#   - 5 composites: V12, Q08, M32, GR07, C19 (Z_Score_Aligned 단일 사용)
#   - low_vol multi-proxy: mean(Z_aligned of D01+D02+D03+D04) [auto-flipped lower_better]
#   - dividend multi-proxy: mean(Z_aligned of V06+V11+V17)
#
# Output:
#   - outputs/v3_5/k200_factor_panel_v35.parquet
#     columns: Date, Ticker, F_value, F_quality, F_momentum, F_growth,
#              F_consensus, F_low_vol, F_size, F_dividend
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_5")
FACTOR_DB_MONTHLY <- file.path(BASE, ".cache/factor_db")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")

# Source PIT-C15 compliant connector
source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

SIGNAL_CUTOFF <- as.Date("2023-12-22")
LIQ_THRESHOLD <- 50000000  # 20d avg trading volume KRW (50 M minimum, request.json)
LIQ_WINDOW <- 20L

# Factor mapping per family
FAMILY_SPECS <- list(
  value = list(type = "composite_single", factors = "V12_Composite_Value"),
  quality = list(type = "composite_single", factors = "Q08_Composite_Quality"),
  momentum = list(type = "composite_single", factors = "M32_Composite_Mom_v2"),
  growth = list(type = "composite_single", factors = "GR07_Composite_Growth"),
  consensus = list(type = "composite_single", factors = "C19_Composite_Earnings"),
  low_vol = list(type = "multi_proxy_mean",
                  factors = c("D01_IdioVol", "D02_Beta", "D03_RealVol", "D04_Downside_Beta")),
  size = list(type = "composite_single", factors = "S01_Size"),   # higher_better retain, v1 fix
  dividend = list(type = "multi_proxy_mean",
                   factors = c("V06_fDY", "V11_Shareholder_Yield", "V17_Payout_Ratio"))
)
ALL_TARGET_FACTORS <- unique(unlist(lapply(FAMILY_SPECS, function(x) x$factors)))
cat("[Factor Panel v3.5] Target factors (n=", length(ALL_TARGET_FACTORS), "):",
    paste(ALL_TARGET_FACTORS, collapse = ", "), "\n")

cat("[Factor Panel v3.5] === START ===\n")
t0 <- Sys.time()

# ---- 1. Universe identification ----
cat("[1] Loading rawdata.parquet ...\n")
rd <- as.data.table(read_parquet(RAWDATA, col_select = c("Date","Ticker","Close","K200","Vol","Size","Ret")))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)
cat("  rawdata rows:", nrow(rd), "\n")

# ---- 2. Sig_date list: K200 universe month-end factor_db dates within lockbox ----
ym_list <- list.files(FACTOR_DB_MONTHLY, pattern = "^factor_db_\\d{6}\\.parquet$")
ym_list <- sort(ym_list)
# Find month-end dates
sig_dates_all <- c()
for (f in ym_list) {
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", f)
  yr <- as.integer(substr(ym, 1, 4))
  mn <- as.integer(substr(ym, 5, 6))
  # Last K200 trading day of that month
  date_first <- as.Date(sprintf("%04d-%02d-01", yr, mn))
  date_last <- as.Date(sprintf("%04d-%02d-%02d", yr, mn,
                                  if (mn==12) 31 else as.integer(format(as.Date(sprintf("%04d-%02d-01",
                                          if(mn==12) yr+1 else yr,
                                          if(mn==12) 1 else mn+1)) - 1, "%d"))))
  k_dates <- rd[Date >= date_first & Date <= date_last & K200 == 1, unique(Date)]
  if (length(k_dates) > 0) {
    sig_dates_all <- c(sig_dates_all, max(k_dates))
  }
}
sig_dates_all <- sort(unique(as.Date(sig_dates_all)))

# v3.5 evaluation window: 2017-01 (Phase 1 v3 inheritance) ~ SIGNAL_CUTOFF
sig_dates <- sig_dates_all[sig_dates_all >= as.Date("2017-01-01") & sig_dates_all <= SIGNAL_CUTOFF]
cat("  sig_dates total:", length(sig_dates_all), " | in eval window:", length(sig_dates), "\n")
cat("  eval window:", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), "\n")

# ---- 3. Per sig_date: load_month_factors() + liquidity filter + family aggregation ----
cat("[3] Per sig_date factor load via load_month_factors() ...\n")

# Pre-compute 20d trading value (lagged t-1 enforcement: window = [t-20, t-1])
cat("  pre-compute lagged 20d trading value (PIT t-1)...\n")
rd[, TV := Vol * Close]
setorder(rd, Ticker, Date)
rd[, TV_20d_lag := frollmean(shift(TV, n = 1L, type = "lag"), n = LIQ_WINDOW, align = "right", na.rm = TRUE), by = Ticker]

panel_list <- list()
n_dates <- length(sig_dates)
for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]

  # PIT-C15: load via connector (Z_Score_Aligned + Usable_Date enforced)
  fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                   error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) {
    cat(sprintf("  [%d/%d] %s SKIP load_month_factors empty\n", i, n_dates, sig_d))
    next
  }

  # Universe filter: K200=1 AND liquidity pass at sig_d
  uni_dt <- rd[Date == sig_d & K200 == 1 & !is.na(TV_20d_lag) & TV_20d_lag >= LIQ_THRESHOLD,
                 .(Ticker, TV_20d_lag)]
  if (nrow(uni_dt) == 0) {
    cat(sprintf("  [%d/%d] %s SKIP empty universe\n", i, n_dates, sig_d))
    next
  }

  fdt <- fdt[Ticker %in% uni_dt$Ticker]

  # Per family aggregation
  fam_panel <- uni_dt[, .(Ticker)]
  fam_panel[, Date := sig_d]
  for (fam in names(FAMILY_SPECS)) {
    spec <- FAMILY_SPECS[[fam]]
    target_factors <- spec$factors
    sub <- fdt[Factor_Name %in% target_factors, .(Ticker, Factor_Name, Z_Score_Aligned)]
    if (nrow(sub) == 0) {
      fam_panel[, (paste0("F_", fam)) := NA_real_]
      next
    }
    if (spec$type == "composite_single") {
      # Single composite — direct use
      sub <- sub[, .(F_fam = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]
    } else if (spec$type == "multi_proxy_mean") {
      # Multi-proxy: per-Ticker mean of all factor Z_aligned in the family
      sub <- sub[, .(F_fam = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]
    }
    fam_panel <- merge(fam_panel, sub, by = "Ticker", all.x = TRUE)
    setnames(fam_panel, "F_fam", paste0("F_", fam))
  }

  panel_list[[i]] <- fam_panel
  if (i %% 12 == 0) {
    cat(sprintf("  [%d/%d] %s | universe=%d | factors loaded\n", i, n_dates, sig_d, nrow(uni_dt)))
  }
}

panel <- rbindlist(panel_list, fill = TRUE, use.names = TRUE)
setcolorder(panel, c("Date", "Ticker", paste0("F_", names(FAMILY_SPECS))))
setorder(panel, Date, Ticker)
cat("  panel rows:", nrow(panel), " | unique sig_dates:", length(unique(panel$Date)), " | unique tickers:", length(unique(panel$Ticker)), "\n")

# ---- 4. Cross-sectional re-standardization per family per Date ----
# (compositive z already standardized in builder; re-z guards against load_month_factor re-scaling artifacts)
cat("[4] Cross-sectional re-standardization (per Date per family) ...\n")
fam_cols <- paste0("F_", names(FAMILY_SPECS))
for (fc in fam_cols) {
  panel[!is.na(get(fc)), (fc) := {
    x <- get(fc)
    mu <- mean(x, na.rm = TRUE)
    s <- sd(x, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) (x - mu) / s else x - mu
  }, by = Date]
}

# ---- 5. Coverage diag per family per Date ----
cov_diag <- panel[, lapply(.SD, function(x) round(sum(!is.na(x)) / .N, 3)),
                    .SDcols = fam_cols, by = Date]
cat("[5] Coverage diag (per family per Date) — first 3 sig_dates:\n")
print(head(cov_diag, 3))

# ---- 6. Output ----
cat("[6] Saving v3.5 factor panel ...\n")
write_parquet(panel, file.path(OUT_DIR, "k200_factor_panel_v35.parquet"))
write_parquet(panel, file.path(STAGE_DIR, "k200_factor_panel_v35.parquet"))

meta <- list(
  spec = "v3.5 8-family factor panel via load_month_factors()",
  family_specs = FAMILY_SPECS,
  s01_size_fix = "direction=higher_better retain (v1 double-flip bug fix). Registry already encodes SMB convention (-log(MarketCap)).",
  pit_compliance = list(
    C13_z_aligned_only = TRUE,
    C14_usable_date = "enforced via load_month_factors() PIT-safe expanding window",
    C15_load_month_factors = TRUE
  ),
  sig_date_range = c(as.character(min(panel$Date)), as.character(max(panel$Date))),
  n_sig_dates = length(unique(panel$Date)),
  n_unique_tickers = length(unique(panel$Ticker)),
  n_obs = nrow(panel),
  family_coverage_avg = round(sapply(fam_cols, function(c) mean(!is.na(panel[[c]]))), 4),
  liquidity_threshold = LIQ_THRESHOLD,
  liquidity_window = LIQ_WINDOW,
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "k200_factor_panel_v35.meta.json"))

cat("[Factor Panel v3.5] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
