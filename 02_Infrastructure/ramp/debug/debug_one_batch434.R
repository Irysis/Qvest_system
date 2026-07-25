# debug_one_batch434.R — isolated-subprocess SEGV-safe read of ONE batch_434 _result.rds
# Designed to be invoked as a child process: Rscript debug_one_batch434.R <rds_path> <out_csv>
# Loads data.table/xts FIRST, then readRDS, extracts NAV-only to a flat csv. If it segfaults,
# the parent sees a non-zero exit / missing out_csv and logs SKIP.
suppressMessages({ library(data.table); library(xts) })

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  # interactive default: probe first file + dump structure
  b <- list.files("stage_artifacts/batch_434", pattern="_result\\.rds$", recursive=TRUE, full.names=TRUE)
  rds <- b[1]; out <- ".cache/scratch/ramp_debug/debug_batch434_probe.txt"
  sink(out)
  cat("PROBE:", rds, "\n")
  obj <- tryCatch(readRDS(rds), error=function(e){cat("ERROR:",conditionMessage(e),"\n"); NULL})
  if (!is.null(obj)) {
    cat("class:", class(obj), " names:", paste(names(obj), collapse=", "), "\n")
    str(obj, max.level=2, list.len=25)
    # try to find NAV/returns
    for (nm in names(obj)) {
      x <- obj[[nm]]
      if (is.data.frame(x) || is.data.table(x)) cat(sprintf("  $%s : df cols=%s nrow=%d\n", nm, paste(names(x),collapse="/"), nrow(x)))
      if (xts::is.xts(x)) cat(sprintf("  $%s : xts cols=%s nrow=%d\n", nm, paste(colnames(x),collapse="/"), nrow(x)))
    }
  }
  sink()
  cat("probe done\n")
  quit(save="no", status=0)
}

rds <- args[1]; out_csv <- args[2]
obj <- readRDS(rds)   # may segfault — that's the point; isolated child absorbs it

# Extraction strategy: find a daily NAV/return series. Priority:
#   DAILY_NAV_DT(Date,NAV,Strategy_Ret) -> strategy_xts -> any xts -> any df with Date+Ret-like
nav_dt <- NULL
extract <- function(obj) {
  if (!is.null(obj$DAILY_NAV_DT)) {
    d <- as.data.table(obj$DAILY_NAV_DT)
    if (all(c("Date","Strategy_Ret") %in% names(d))) return(d[, .(Date, Ret = Strategy_Ret)])
  }
  if (!is.null(obj$strategy_xts) && xts::is.xts(obj$strategy_xts)) {
    x <- obj$strategy_xts
    return(data.table(Date = as.Date(zoo::index(x)), Ret = as.numeric(x[,1])))
  }
  for (nm in names(obj)) {
    x <- obj[[nm]]
    if (xts::is.xts(x)) return(data.table(Date = as.Date(zoo::index(x)), Ret = as.numeric(x[,1])))
    if (is.data.frame(x)) {
      dd <- as.data.table(x)
      dcol <- intersect(c("Date","date"), names(dd))
      rcol <- intersect(c("Strategy_Ret","Ret","ret","return","Return"), names(dd))
      if (length(dcol) && length(rcol)) return(dd[, .(Date = as.Date(get(dcol[1])), Ret = as.numeric(get(rcol[1])))])
    }
  }
  NULL
}
nav_dt <- extract(obj)
if (is.null(nav_dt) || nrow(nav_dt) == 0) {
  quit(save="no", status=3)  # parent treats as SKIP (no extractable NAV)
}
nav_dt <- nav_dt[!is.na(Date) & !is.na(Ret)]
fwrite(nav_dt, out_csv)
quit(save="no", status=0)
