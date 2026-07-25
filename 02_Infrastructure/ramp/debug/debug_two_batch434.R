# debug_two_batch434.R — survey structure variety across batch_434 + locate NAV source
suppressMessages({ library(data.table); library(xts) })
dir.create(".cache/scratch/ramp_debug", recursive = TRUE, showWarnings = FALSE)
sink(".cache/scratch/ramp_debug/debug_batch434_survey.txt")

b <- list.files("stage_artifacts/batch_434", pattern="_result\\.rds$", recursive=TRUE, full.names=TRUE)
cat("total:", length(b), "\n")
# subdir breakdown
sub <- dirname(b); cat("\nsubdir counts:\n"); print(table(sub))

# sample across different subdirs
samp <- c(b[1], b[grep("codegen_direct_409", b)][1:3], tail(b,2))
samp <- unique(samp[!is.na(samp)])
cat("\n===== structure variety =====\n")
nav_field_found <- 0L; has_outdir <- 0L
for (f in samp) {
  obj <- tryCatch(readRDS(f), error=function(e) NULL)
  if (is.null(obj)) { cat(f, " -> READ ERROR\n"); next }
  cat("\n--", basename(f), "--\n")
  cat("  names:", paste(names(obj), collapse=", "), "\n")
  navlike <- intersect(c("DAILY_NAV_DT","strategy_xts","nav","NAV","returns","daily_returns","equity"), names(obj))
  cat("  nav-like fields:", if(length(navlike)) paste(navlike,collapse=",") else "<none>", "\n")
  if (!is.null(obj$out_dir)) { cat("  out_dir:", obj$out_dir, "\n"); has_outdir <- has_outdir + 1L }
}

# Check: do out_dir paths (mnt/c) translate to existing files? what's inside?
cat("\n===== out_dir contents probe =====\n")
obj1 <- readRDS(b[grep("codegen_direct_409", b)][1])
if (!is.null(obj1$out_dir)) {
  od <- obj1$out_dir
  # translate /mnt/c/Users/... -> C:/Users/...
  od_win <- sub("^/mnt/c/", "C:/", od)
  cat("out_dir(win):", od_win, " exists:", dir.exists(od_win), "\n")
  if (dir.exists(od_win)) {
    fs <- list.files(od_win, recursive=TRUE)
    cat("  files:\n"); cat(paste("   ", head(fs, 30), collapse="\n"), "\n")
  }
}
sink()
cat("survey done\n")
