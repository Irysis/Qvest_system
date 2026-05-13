# WT-D20260512_003 — REBUTTAL evidence: sector-neutral IC + 20d TV liquidity audit + portfolio-level IC

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]

SCHEME <- list(BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80)
p[, w_new := fcase(
  regime_state == "BULL", SCHEME$BULL,
  regime_state == "NORMAL", SCHEME$NORMAL,
  regime_state == "CAUTION", SCHEME$CAUTION,
  regime_state == "CRISIS", SCHEME$CRISIS,
  default = 0.0
)]
p[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

# === Sector-neutral IC ===
# Load sector mapping from RAWDATA if available
sector_path <- ".cache/rawdata.rds"
if (file.exists(sector_path)) {
  rd <- readRDS(sector_path)
  if (is.list(rd) && "sector_mapping" %in% names(rd)) {
    sec_map <- rd$sector_mapping
  } else {
    cat("[sector] no sector_mapping in rawdata.rds — try alternate\n")
    sec_map <- NULL
  }
} else {
  sec_map <- NULL
}

# Try direct sector mapping from 03_Universe
sec_files <- list.files("03_Universe", pattern = "sector.*\\.(parquet|csv|rds)$",
                         recursive = TRUE, full.names = TRUE)
cat("[sector] candidate files:", paste(sec_files, collapse=", "), "\n")

# Fallback: try DART sector
if (is.null(sec_map) && length(sec_files) > 0) {
  for (sf in sec_files) {
    cat("[sector] trying:", sf, "\n")
    if (grepl("\\.parquet$", sf)) {
      tmp <- as.data.table(read_parquet(sf))
    } else if (grepl("\\.csv$", sf)) {
      tmp <- fread(sf)
    } else {
      tmp <- readRDS(sf)
      if (!is.data.table(tmp)) tmp <- as.data.table(tmp)
    }
    if ("Ticker" %in% names(tmp) && any(grepl("sector|Sector|GICS|gics", names(tmp)))) {
      sec_col <- grep("sector|Sector|GICS|gics", names(tmp), value=TRUE)[1]
      sec_map <- unique(tmp[, .(Ticker, sector = get(sec_col))])
      cat("[sector] loaded from", sf, "rows:", nrow(sec_map), "\n")
      break
    }
  }
}

# Fallback 2: use S01_Size (proxy for cap-sector clustering)
# In KR, sector mapping inferrable from Ticker prefix range or via FDB
if (is.null(sec_map)) {
  cat("[sector] no explicit sector mapping found; using S01_Size as proxy for size-stratified IC\n")
  # Use size deciles per month
  p_strat <- p[!is.na(z_blend) & !is.na(Ret_1m)]
  # Need size — get from FDB; for speed proxy as score_eff dominant
  # Just report unable to sector-neutralize without mapping
  cat("[sector] WARN: explicit sector_mapping unavailable; reporting un-neutralized IC + size-decile IC\n")
}

# === Cap/Float-size stratified IC (proxy for sector clustering) ===
# Use S01_Size and L26_Log_MktCap from FDB - here just check robust to controls
source("02_Infrastructure/factor_db/factor_db_connector.R", local = TRUE)
sample_date <- as.Date("2023-06-01")
fm <- as.data.table(load_month_factors(sample_date))
size_av <- fm[Factor_Name == "S01_Size"]
cat("[sector] S01_Size proxy rows:", nrow(size_av), "\n")
# Reconstruct full panel with S01_Size
load_size_panel <- function(sig_dates) {
  rbindlist(lapply(sig_dates, function(sd) {
    fm <- as.data.table(load_month_factors(sd))
    fm[Factor_Name == "S01_Size", .(Date=sd, Ticker, S01_Size = Z_Score_Aligned)]
  }))
}
sig_dates_p <- sort(unique(p$Date))
size_panel <- load_size_panel(sig_dates_p)
cat("[sector] size_panel rows:", nrow(size_panel), "\n")

p2 <- merge(p, size_panel, by = c("Date", "Ticker"), all.x = TRUE)
p2[, size_quintile := as.integer(cut(S01_Size, breaks = quantile(S01_Size, probs = seq(0,1,0.2), na.rm=TRUE),
                                       labels = 1:5, include.lowest = TRUE)), by = Date]

# Size-stratified IC: within each size quintile, compute IC
size_ic <- p2[!is.na(size_quintile), .(
  ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_,
  ic_str1715 = if (.N >= 5) cor(score_eff, Ret_1m, method="spearman") else NA_real_,
  n = .N
), by = .(Date, size_quintile)]
size_ic <- size_ic[!is.na(ic)]
size_ic_summary <- size_ic[, .(
  ic_blend = mean(ic), icir_blend = mean(ic)/sd(ic)*sqrt(12),
  ic_str = mean(ic_str1715), icir_str = mean(ic_str1715)/sd(ic_str1715)*sqrt(12),
  n_months = .N
), by = size_quintile]
setorder(size_ic_summary, size_quintile)
cat("\n=== Size-stratified IC (within each S01 quintile) ===\n")
print(size_ic_summary)

# === Top 20 liquidity audit ===
# Per month, select top 20 by z_blend. Check S01_Size (proxy for liquidity 20d TV)
# Need actual 20d TV from RAWDATA — try L05_Dollar_Volume from FDB
load_liq_panel <- function(sig_dates) {
  rbindlist(lapply(sig_dates, function(sd) {
    fm <- as.data.table(load_month_factors(sd))
    fm[Factor_Name %in% c("L05_Dollar_Volume", "L02_Turnover"),
       .(Date=sd, Ticker, Factor_Name, Z_Score_Aligned)]
  }))
}
liq_panel <- load_liq_panel(sig_dates_p)
liq_wide <- dcast(liq_panel, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
p3 <- merge(p, liq_wide, by = c("Date", "Ticker"), all.x = TRUE)
cat("\n[liquidity] L05_Dollar_Volume coverage:",
    round(100 * sum(!is.na(p3$L05_Dollar_Volume)) / nrow(p3), 1), "%\n")

# Top 20 per month + check L05 quantile (negative z = low liquidity)
p3[, rank_blend := frank(-z_blend, ties.method="random"), by = Date]
top20 <- p3[rank_blend <= 20]
liq_summary <- top20[, .(
  mean_L05_z = round(mean(L05_Dollar_Volume, na.rm = TRUE), 3),
  pct_below_zero_L05 = round(100 * mean(L05_Dollar_Volume < 0, na.rm = TRUE), 1),
  pct_below_neg1_L05 = round(100 * mean(L05_Dollar_Volume < -1, na.rm = TRUE), 1)
), by = regime_state]
cat("\n[liquidity] Top 20 names L05_Dollar_Volume Z stats by regime ===\n")
print(liq_summary)

# Median L05 of top 20 = better liquidity check
overall_liq <- top20[, .(
  median_L05 = round(median(L05_Dollar_Volume, na.rm=TRUE), 3),
  pct_above_zero_L05 = round(100 * mean(L05_Dollar_Volume > 0, na.rm=TRUE), 1),
  pct_above_pos05_L05 = round(100 * mean(L05_Dollar_Volume > 0.5, na.rm=TRUE), 1),
  n = .N
)]
cat("\n[liquidity] Top 20 overall L05 stats:\n")
print(overall_liq)

# === Save ===
saveRDS(list(size_ic_summary = size_ic_summary, top20_liq = liq_summary, overall_liq = overall_liq),
         "stage_artifacts/WT_D20260512_003/sector_neutral_and_liquidity.rds")
cat("\n[saved] sector_neutral_and_liquidity.rds\n")
