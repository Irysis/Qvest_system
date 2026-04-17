cat("=== Factor DB Unused Alpha Scan ===\n")
suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
  library(dplyr)
})

PROJ <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
FDB_DIR <- file.path(PROJ, ".cache", "factor_db")

# 1) Load factor registry
reg <- fromJSON(file.path(PROJ, "02_Infrastructure", "factor_db", "factor_registry.json"))
cat("[Scan] Registry:", length(reg), "factors\n")

# 2) Extract metadata
meta <- rbindlist(lapply(names(reg), function(fid) {
  r <- reg[[fid]]
  data.table(
    factor_id = fid,
    name = r$name %||% NA,
    category = r$category %||% NA,
    family = r$labels$economic_family %||% NA,
    direction = r$direction %||% NA,
    evidence_tier = r$labels$evidence_tier %||% NA,
    corr_group = r$labels$correlation_group %||% NA,
    construction = r$labels$construction %||% NA,
    stage = r$lifecycle$research_stage %||% NA
  )
}), fill = TRUE)

cat("\n[Scan] Categories:\n")
print(meta[, .N, by = category][order(-N)])

cat("\n[Scan] Economic Families:\n")
print(meta[, .N, by = family][order(-N)])

cat("\n[Scan] Correlation Groups:\n")
print(meta[, .N, by = corr_group][order(-N)])

# 3) Known Grade A factors (used in existing sleeves)
USED_FACTORS <- c(
  "D01_IdioVol", "D02_Beta",           # Sleeve 1: Defense
  "C19_Composite_Earnings",             # Sleeve 3: Consensus
  "Q04_Piotroski_F", "V15_NetDebt_Adj_EP" # Sleeve 4: QualRev candidates
)
USED_FAMILIES <- c("value", "risk", "quality", "momentum", "earnings")

# 4) Find unused families/correlation groups
cat("\n[Scan] Factors NOT in used correlation groups:\n")
used_groups <- meta[factor_id %in% USED_FACTORS, unique(corr_group)]
unused <- meta[!corr_group %in% used_groups & !is.na(corr_group)]
print(unused[, .N, by = .(family, corr_group)][order(-N)])

# 5) Quick IC scan on recent data (last 36 months)
# Use Arrow dataset for efficiency
cat("\n[Scan] Loading recent 36M factor data via Arrow...\n")
ds <- open_dataset(FDB_DIR, format = "parquet")

# Get available factor names
all_factors <- ds |>
  select(Factor_Name) |>
  collect() |>
  as.data.table()
all_factors <- unique(all_factors$Factor_Name)
cat("[Scan]", length(all_factors), "factors in parquet DB\n")

# Factors NOT in used set
candidates <- setdiff(all_factors, USED_FACTORS)
cat("[Scan]", length(candidates), "candidate factors (excluding used)\n")

# Recent 36 months
recent_dates <- sort(unique((ds |> select(Date) |> collect())$Date), decreasing = TRUE)[1:36]
min_date <- min(recent_dates)
cat("[Scan] Recent window:", as.character(min_date), "~", as.character(max(recent_dates)), "\n")

# Load recent data for candidates (Z_Score only)
cat("[Scan] Loading candidate factor Z-scores...\n")
fdt <- ds |>
  filter(Date >= min_date, Factor_Name %in% candidates) |>
  select(Date, Ticker, Factor_Name, Z_Score) |>
  collect() |>
  as.data.table()
cat("[Scan] Loaded:", nrow(fdt), "rows,", uniqueN(fdt$Factor_Name), "factors\n")

# Load RAWDATA for returns
source(file.path(PROJ, "02_Infrastructure", "config.R"))
source(file.path(PROJ, "02_Infrastructure", "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
setkey(RAWDATA, Date, Ticker)

# Forward 1M return
ret_dt <- RAWDATA[, .(Date, Ticker, Ret)]
setkey(ret_dt, Date, Ticker)

# Merge factor scores with next-month returns
setkey(fdt, Date, Ticker)
monthly_dates <- sort(unique(fdt$Date))

# For each month, merge factor score with NEXT month return
ic_results <- rbindlist(lapply(seq_len(length(monthly_dates) - 1), function(i) {
  sig_d <- monthly_dates[i]
  ret_d <- monthly_dates[i + 1]

  scores <- fdt[Date == sig_d]
  rets <- ret_dt[Date == ret_d, .(Ticker, Ret)]

  merged <- merge(scores, rets, by = "Ticker")
  if (nrow(merged) < 30) return(NULL)

  merged <- merged[!is.na(Z_Score) & !is.na(Ret)]
  if (nrow(merged) < 30) return(NULL)
  merged[, .(
    ic = tryCatch(cor(Z_Score, Ret, use = "complete.obs", method = "spearman"),
                  error = function(e) NA_real_)
  ), by = Factor_Name][!is.na(ic)][, Date := sig_d]
}), fill = TRUE)

cat("[Scan] IC computed for", uniqueN(ic_results$Factor_Name), "factors\n")

# 6) Summarize: mean IC, ICIR, t-stat
ic_summary <- ic_results[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  n_months = .N,
  ic_positive_pct = mean(ic > 0, na.rm = TRUE) * 100
), by = Factor_Name]
ic_summary[, `:=`(
  icir = mean_ic / sd_ic,
  t_stat = mean_ic / sd_ic * sqrt(n_months)
)]

# Merge with meta
ic_summary <- merge(ic_summary, meta, by.x = "Factor_Name", by.y = "factor_id", all.x = TRUE)

# 7) Top candidates: |mean_ic| > 0.02, positive direction, independent group
ic_summary <- ic_summary[order(-abs(mean_ic))]

cat("\n========== TOP 30 UNUSED FACTORS (by |mean_ic|) ==========\n")
top30 <- ic_summary[abs(mean_ic) > 0.01][1:min(30, .N)]
print(top30[, .(Factor_Name, name, category, family, corr_group,
                mean_ic, icir, t_stat, ic_positive_pct, n_months)], nrows = 30)

cat("\n========== INDEPENDENT CANDIDATES (not in used corr_groups) ==========\n")
indep <- ic_summary[!corr_group %in% used_groups & abs(mean_ic) > 0.01]
indep <- indep[order(-abs(mean_ic))]
print(indep[1:min(20, .N), .(Factor_Name, name, category, family, corr_group,
                              mean_ic, icir, t_stat, ic_positive_pct)], nrows = 20)

# Save results
fwrite(ic_summary[order(-abs(mean_ic))],
       file.path(PROJ, "research_output", "factor_scan_results.csv"))
cat("\n[Scan] Results saved to research_output/factor_scan_results.csv\n")
cat("=== Scan Complete ===\n")
