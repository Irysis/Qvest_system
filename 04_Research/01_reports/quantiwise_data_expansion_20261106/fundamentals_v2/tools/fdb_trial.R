# One-month factor DB trial (save = FALSE: nothing written to .cache/factor_db).
# Usage: Rscript fdb_trial.R <label> <fund_merged_path> <out_dir> [--xlsx <fund_xlsx_path>] <sig_date> [<sig_date> ...]
args <- commandArgs(trailingOnly = TRUE)
label <- args[1]; fund <- args[2]; out_dir <- args[3]; rest <- args[-(1:3)]
ix <- match("--xlsx", rest)
if (!is.na(ix)) { Sys.setenv(QVEST_FUND_XLSX = rest[ix + 1L]); rest <- rest[-c(ix, ix + 1L)] }
sigs <- rest
Sys.setenv(QVEST_FUND_MERGED = fund)
root <- Sys.getenv("QM_ROOT")
source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_builder.R"))
suppressPackageStartupMessages(library(arrow))
for (s in sigs) {
  t0 <- Sys.time()
  res <- build_factor_db(s, save = FALSE, force = TRUE)
  f <- file.path(out_dir, sprintf("trial_%s_%s.parquet", label, gsub("-", "", s)))
  write_parquet(as.data.frame(res), f)
  cat(sprintf("[trial] %s %s -> %s rows %d (%.0fs)\n", label, s, f, nrow(res), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
print(warnings())
