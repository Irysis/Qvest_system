# _probe_fix.R - diagnose B2 engine error (NA r_idx) + lo_screen cache contents
suppressMessages({library(data.table); library(arrow)})
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TV <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV")
mep <- as.data.table(read_parquet(file.path(TV, "inputs/me_panel.parquet")))
cat("me_panel rows:", nrow(mep), "\n")
cat("NA ret_date rows:", mep[, sum(is.na(ret_date))], "| NA ret_fwd rows:", mep[, sum(is.na(ret_fwd))], "\n")
cat("NA ret_date AND finite ret_fwd:", mep[is.na(ret_date) & is.finite(ret_fwd), .N], "\n")
FC <- readRDS(file.path(PROJ, "stage_artifacts/alpha_search/lo_screen/_factor_cache.rds"))
cat("lo_screen factor cache factors:", paste(sort(unique(FC$Factor_Name)), collapse=", "), "\n")
cat("cols:", paste(names(FC), collapse=","), "\n")
cat("dates:", as.character(min(FC$Date)), "~", as.character(max(FC$Date)), "| n_dates:", uniqueN(FC$Date), "\n")
cat("PROBE_FIX DONE\n")
