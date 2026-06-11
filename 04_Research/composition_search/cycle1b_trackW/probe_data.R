# probe_data.R — Track W data inventory probe (read-only)
suppressPackageStartupMessages({ library(arrow); library(data.table) })
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

pan <- as.data.table(read_parquet(file.path(PROJECT_ROOT, "04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
cat("panel cols:", paste(names(pan), collapse=", "), "\n")
pan[, Date := as.Date(Date)]
cat("panel dates:", as.character(min(pan$Date)), "~", as.character(max(pan$Date)), "| rows:", nrow(pan), "| n_dates:", uniqueN(pan$Date), "\n")

rd <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/RAWDATA.parquet"),
                                 col_select = c("Date","Ticker")))
cat("RAWDATA:", as.character(min(rd$Date)), "~", as.character(max(rd$Date)),
    "| rows:", nrow(rd), "| tickers:", uniqueN(rd$Ticker), "\n")
all_d <- sort(unique(rd$Date))
cat("n trading days:", length(all_d), "\n")
cat("date with >=756 prior days:", as.character(all_d[757]), "\n")
rm(rd); gc(verbose=FALSE)

rdf <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/RAWDATA.parquet"),
                                  col_select = c("Date","Ticker","Close","Ret","Vol")))
cat("RAWDATA cols sample:\n"); print(head(rdf, 3))
bm <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
cat("BM cols:", paste(names(bm), collapse=", "), "| dates:",
    as.character(min(bm$Date)), "~", as.character(max(bm$Date)), "\n")

sel <- fread(file.path(PROJECT_ROOT, "04_Research/pg2_forensics/intermediate/variant_top20_selections.csv"))
sel <- sel[variant == "blend_65_35"]
cat("S1 selections (blend_65_35):", nrow(sel), "rows |",
    as.character(min(sel$Date)), "~", as.character(max(sel$Date)), "\n")
cat("names per month range:", sel[, .N, by=Date][, paste(min(N), max(N))], "\n")

# factor_db check for S3
fdb_dir <- file.path(PROJECT_ROOT, ".cache/factor_db")
cat("factor_db exists:", dir.exists(fdb_dir), "\n")
# consensus + investor caches for S2
cat("eps_chg_1m exists:", file.exists(file.path(PROJECT_ROOT, ".cache/consensus/eps_chg_1m.parquet")), "\n")
cat("investor_wide exists:", file.exists(file.path(PROJECT_ROOT, ".cache/investor_stock/investor_wide.parquet")), "\n")
cat("macro_regime exists:", file.exists(file.path(PROJECT_ROOT, ".cache/macro_regime.parquet")), "\n")
cat("PROBE_OK\n")
