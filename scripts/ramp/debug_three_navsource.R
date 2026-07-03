# debug_three_navsource.R — pin down the NAV source for batch_434 result objects
suppressMessages({ library(data.table); library(xts) })
sink("scripts/ramp/_debug_navsource.txt")

translate <- function(p) {
  if (is.null(p) || is.na(p)) return(NA_character_)
  p <- sub("^/mnt/c/", "C:/", p)
  p
}

b <- list.files("stage_artifacts/batch_434", pattern="_result\\.rds$", recursive=TRUE, full.names=TRUE)

# 1) Inspect a 'rich' result object (has bt_contract / strategy_manifest)
rich <- b[grep("ALPHA_01_result\\.rds$", b)][1]
cat("RICH:", rich, "\n")
o <- readRDS(rich)
cat("names:", paste(names(o), collapse=", "), "\n")
if (!is.null(o$bt_contract)) {
  cat("\nbt_contract class:", class(o$bt_contract), " names:", paste(names(o$bt_contract), collapse=", "), "\n")
  bc <- o$bt_contract
  for (nm in names(bc)) {
    x <- bc[[nm]]
    if (is.data.frame(x) || is.data.table(x)) cat(sprintf("  bt$%s : df cols=%s nrow=%d\n", nm, paste(names(x),collapse="/"), nrow(x)))
  }
}
if (!is.null(o$strategy_manifest)) {
  cat("\nstrategy_manifest names:", paste(names(o$strategy_manifest), collapse=", "), "\n")
}
cat("\nout_dir:", o$out_dir, "\n")
od <- translate(o$out_dir)
cat("out_dir(win) exists:", dir.exists(od), "\n")
if (dir.exists(od)) {
  fs <- list.files(od, recursive=TRUE, full.names=FALSE)
  cat("files in out_dir:\n"); cat(paste("  ", fs, collapse="\n"), "\n")
}

# 2) Scan: how many result objects have bt_contract w/ nav? how many have out_dir w/ a NAV file?
cat("\n===== inventory scan over all 459 =====\n")
n_summary <- 0L; n_item <- 0L; n_btc <- 0L; n_outdir_exists <- 0L; n_navfile <- 0L; n_other <- 0L
nav_file_examples <- character(0)
for (f in b) {
  o <- tryCatch(readRDS(f), error=function(e) NULL)
  if (is.null(o)) { n_other <- n_other + 1L; next }
  nm <- names(o)
  if ("item_id" %in% nm && !("grade" %in% nm)) { n_item <- n_item + 1L; next }
  if ("strategy_id" %in% nm) {
    n_summary <- n_summary + 1L
    if (!is.null(o$bt_contract)) {
      bc <- o$bt_contract
      if (is.list(bc) && any(sapply(bc, function(x) (is.data.frame(x)||is.data.table(x)) && any(grepl("nav|ret|return", names(x), ignore.case=TRUE))))) n_btc <- n_btc + 1L
    }
    od <- translate(o$out_dir)
    if (!is.null(od) && !is.na(od) && dir.exists(od)) {
      n_outdir_exists <- n_outdir_exists + 1L
      navf <- list.files(od, pattern="(nav|return|equity|sim_result|bt_contract|period).*\\.(csv|rds|parquet)$", recursive=TRUE, full.names=TRUE, ignore.case=TRUE)
      if (length(navf)) { n_navfile <- n_navfile + 1L; if (length(nav_file_examples)<5) nav_file_examples <- c(nav_file_examples, navf[1]) }
    }
  } else n_other <- n_other + 1L
}
cat(sprintf("summary-type(strategy_id): %d\n item-manifest(no grade): %d\n other/error: %d\n", n_summary, n_item, n_other))
cat(sprintf("  of summary: bt_contract-with-nav=%d ; out_dir-exists=%d ; out_dir-has-navfile=%d\n", n_btc, n_outdir_exists, n_navfile))
cat("nav file examples:\n"); cat(paste("  ", nav_file_examples, collapse="\n"), "\n")
sink()
cat("navsource done\n")
