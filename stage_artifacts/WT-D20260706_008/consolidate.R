suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
SNAPDIR <- "C:/Users/99922/AppData/Local/Temp/claude/wt008_snap"
OUT <- "stage_artifacts/WT-D20260706_008"
files <- list.files(SNAPDIR, pattern="^snap_.*[.]rds$", full.names=TRUE)
allsnap <- rbindlist(lapply(files, readRDS), use.names=TRUE, fill=TRUE)
allsnap[, me_date := as.Date(me_date)]
setorder(allsnap, me_date, -tot_val)
# one write to OneDrive (safe - single write, not loop)
write_parquet(allsnap, file.path(OUT, "stockfut_monthend_raw.parquet"))
cat("Consolidated rows:", nrow(allsnap), " months:", uniqueN(allsnap$me_date), "\n")
cat("Range:", as.character(min(allsnap$me_date)), "~", as.character(max(allsnap$me_date)), "\n")
np <- allsnap[, .N, by=me_date]
cat("Names/month: min", min(np$N), " median", median(np$N), " max", max(np$N), "\n")
# basis dispersion sanity
cat("basis_pct overall summary:\n"); print(summary(allsnap$basis_pct))
