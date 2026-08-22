suppressPackageStartupMessages({library(arrow); library(data.table)})
as <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_001/alpha_scores.parquet"))
u <- sort(unique(as$sig_date))
out <- c(
  paste("n_sig_dates:", length(u)),
  paste("range:", as.character(min(u)), "..", as.character(max(u))),
  paste("last6:", paste(tail(as.character(u),6), collapse=",")),
  paste("names_per_last_date:", nrow(as[sig_date==max(sig_date)])),
  paste("names_per_date_summary:", paste(range(as[, .N, by=sig_date]$N), collapse="-"))
)
# per-date count of names
cnt <- as[, .N, by=sig_date][order(sig_date)]
out <- c(out, paste("median_names_per_date:", median(cnt$N)))
writeLines(out, "stage_artifacts/WT-D20260813_001/inspect2.txt")
