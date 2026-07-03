# debug_five_inputs.R — verify sim_result path existence rate + rawdata cache + factor-DB FWL inputs
suppressMessages({ library(data.table); library(jsonlite) })
sink("scripts/ramp/_debug_inputs.txt")

# 1) catalog sim_result_path existence rate
mc <- fromJSON("06_Registry/module_catalog.json", simplifyVector=FALSE)
mods <- mc$modules
cat("catalog modules:", length(mods), "\n")
exist <- 0L; miss <- 0L; paths <- character(0)
for (m in mods) {
  p <- m$sim_result_path
  if (!is.null(p) && file.exists(p)) { exist <- exist + 1L; if(length(paths)<3) paths <- c(paths,p) } else miss <- miss + 1L
}
cat("sim_result exists:", exist, " missing:", miss, "\n")

# 2) confirm a sim_result is net or gross + freq
sr <- readRDS(paths[1])
d <- sr$DAILY_NAV_DT
cat("\nsim DAILY_NAV_DT range:", as.character(min(d$Date)), "..", as.character(max(d$Date)), " n:", nrow(d), "\n")
cat("Strategy_Ret summary:\n"); print(summary(d$Strategy_Ret))

# 3) rawdata cache — for Gate 4 FWL (sector/log_mktcap/beta/vol/liquidity controls + factor signals)
cat("\n=== rawdata cache candidates ===\n")
rc <- list.files(".cache", pattern="rawdata.*\\.parquet$", full.names=TRUE)
cat(paste(rc, collapse="\n"), "\n")
# try arrow read schema
ok_arrow <- requireNamespace("arrow", quietly=TRUE)
cat("arrow available:", ok_arrow, "\n")
if (ok_arrow && length(rc)) {
  for (f in rc) {
    sch <- tryCatch({ s <- arrow::open_dataset(f); names(s) }, error=function(e) paste("ERR", conditionMessage(e)))
    cat("\n", basename(f), " cols:\n  ", paste(head(sch,40), collapse=", "), "\n")
  }
}

# 4) factor_db connector + compute_*.R availability (for FWL economic labels)
cat("\n=== factor_db / fe inputs ===\n")
cat("factor_db_connector exists:", file.exists("02_Infrastructure/factor_db/factor_db_connector.R"), "\n")
cat("compute_*.R:\n"); cat(paste("  ", list.files("02_Infrastructure/factor_db", pattern="compute_.*\\.R$"), collapse="\n"), "\n")
cat("fe_*.R:\n"); cat(paste("  ", list.files("02_Infrastructure/alpha_search", pattern="fe_.*\\.R$"), collapse="\n"), "\n")
cat("\nload_month_factors present?:", any(grepl("load_month_factors", readLines("02_Infrastructure/factor_db/factor_db_connector.R", warn=FALSE))), "\n")
sink(); cat("inputs done\n")
