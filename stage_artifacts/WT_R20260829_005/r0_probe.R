suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
A <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_005/alpha_scores.parquet"))
cat("alpha_scores cols:", paste(names(A), collapse=","), " rows=", nrow(A), "\n")
print(head(A,3)); cat("date range:", as.character(range(A$Date)), "\n")
rl <- load_rawdata(use_cache = TRUE); RAWDATA <- rl$RAWDATA; BM <- rl$BM_DT
cat("RAWDATA cols:", paste(names(RAWDATA), collapse=","), "\n")
cat("RAWDATA rows:", nrow(RAWDATA), " range:", as.character(range(RAWDATA$Date)), "\n")
cat("BM cols:", paste(names(BM), collapse=","), " range:", as.character(range(BM$Date)), "\n")
if ("Sector" %in% names(RAWDATA)) { s <- RAWDATA[Date==max(Date), .N, by=Sector]; print(s) }
if ("Sector_Lv2" %in% names(RAWDATA)) { s2 <- RAWDATA[Date==max(Date), .N, by=Sector_Lv2]; print(head(s2,40)) }
