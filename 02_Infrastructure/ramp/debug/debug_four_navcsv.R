# debug_four_navcsv.R — confirm 02_nav.csv schema + bt_contract$return_series + metric_type
suppressMessages({ library(data.table) })
dir.create(".cache/scratch/ramp_debug", recursive = TRUE, showWarnings = FALSE)
sink(".cache/scratch/ramp_debug/debug_navcsv.txt")
translate <- function(p) sub("^/mnt/c/", "C:/", p)

b <- list.files("stage_artifacts/batch_434", pattern="_result\\.rds$", recursive=TRUE, full.names=TRUE)
rich <- readRDS(b[grep("codegen_direct_409/ALPHA_01_result\\.rds$", b)][1])
od <- translate(rich$out_dir)

cat("=== 02_nav.csv ===\n")
nav <- fread(file.path(od, "02_nav.csv"))
cat("cols:", paste(names(nav), collapse=", "), " nrow:", nrow(nav), "\n")
print(head(nav, 3)); print(tail(nav, 2))

cat("\n=== 03_period_returns.csv ===\n")
pr <- fread(file.path(od, "03_period_returns.csv"))
cat("cols:", paste(names(pr), collapse=", "), " nrow:", nrow(pr), "\n")
print(head(pr, 3))

cat("\n=== bt_contract$return_series ===\n")
rs <- rich$bt_contract$return_series
cat("class:", class(rs), "\n")
if (is.data.frame(rs)||is.data.table(rs)) { cat("cols:", paste(names(rs),collapse=", "), " nrow:", nrow(rs), "\n"); print(head(as.data.table(rs),3)) } else { cat("len:", length(rs), " head:\n"); print(utils::head(rs,3)) }
cat("\nbt_contract$metric_type:", rich$bt_contract$metric_type, "\n")
cat("bt_contract$bt_result_path:", rich$bt_contract$bt_result_path, "\n")

# Are there summary objects whose out_dir is MISSING a nav file? what do they look like
cat("\n=== which 438-summary lack navfile (438-416=22) ===\n")
miss <- 0L
for (f in b) {
  o <- tryCatch(readRDS(f), error=function(e) NULL); if (is.null(o)) next
  if (!("strategy_id" %in% names(o))) next
  od2 <- translate(o$out_dir %||% NA)
  navf <- if (!is.na(od2) && dir.exists(od2)) list.files(od2, pattern="^02_nav\\.csv$", recursive=TRUE, full.names=TRUE) else character(0)
  if (length(navf)==0) { miss <- miss + 1L; if (miss<=5) cat("  no-nav:", o$strategy_id, "grade=", o$grade, "out_dir_exists=", (!is.na(od2)&&dir.exists(od2)), "\n") }
}
`%||%` <- function(a,b) if(is.null(a)) b else a
cat("total summary w/o 02_nav.csv:", miss, "\n")
sink(); cat("navcsv done\n")
