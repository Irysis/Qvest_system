cat("[factor_engine] STR_1453 SUE × NetDebt-Adj EP\n")
suppressPackageStartupMessages({ library(data.table); library(arrow) })
NEEDED_FACTORS <- c("C01_SUE", "V15_NetDebt_Adj_EP")
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"), pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) { dt <- as.data.table(read_parquet(f)); dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE] }))
registry <- .load_registry(); FDB_ALL <- align_factor_direction(FDB_ALL, registry); setkey(FDB_ALL, Date, Ticker)
sig_dates <- sort(unique(FDB_ALL$Date)); FACTORS_list <- list()
for (i in seq_along(sig_dates)) { sig_d <- sig_dates[i]; fdt <- FDB_ALL[Date == sig_d]
  wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  fc <- intersect(NEEDED_FACTORS, names(wide)); if (length(fc) < 2) next
  wide <- wide[complete.cases(wide[, ..fc])]; if (nrow(wide) < 30) next
  for (f in fc) set(wide, j = paste0("R_", f), value = frank(-wide[[f]], ties.method = "average"))
  rc <- paste0("R_", fc); wide[, AvgRank := rowMeans(.SD), .SDcols = rc]; wide[, Score := -AvgRank]
  FACTORS_list[[i]] <- data.table(Date = sig_d, Ticker = wide$Ticker, Score = wide$Score) }
FACTORS <- rbindlist(FACTORS_list, use.names = TRUE); setkey(FACTORS, Date, Ticker)
rm(FDB_ALL, FACTORS_list, fdb_files); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
