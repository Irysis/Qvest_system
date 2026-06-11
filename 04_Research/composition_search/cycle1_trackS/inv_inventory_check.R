# inv_inventory_check.R — Track S Stage A data inventory (read-only diagnostics)
# Checks: (1) INV factor coverage in monthly factor DB, (2) investor_wide.parquet freshness
suppressPackageStartupMessages({ library(arrow); library(data.table) })

root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
fdb  <- file.path(root, ".cache/factor_db")

months <- c("200001","200201","200501","200801","201001","201501","201706",
            "202001","202201","202401","202601","202604","202605")
cat("== INV factor coverage by month ==\n")
for (m in months) {
  f <- file.path(fdb, paste0("factor_db_", m, ".parquet"))
  if (!file.exists(f)) { cat(m, ": MISSING FILE\n"); next }
  d <- as.data.table(read_parquet(f))
  inv <- d[grepl("^INV", Factor_Name)]
  cat(m, ": total_rows=", nrow(d), " inv_factors=", uniqueN(inv$Factor_Name),
      " inv_rows=", nrow(inv), "\n", sep = "")
  rm(d, inv); invisible(gc(FALSE))
}

# Full INV factor list + first/last month present (scan all month files, INV rows only)
cat("\n== INV factor first/last month scan ==\n")
files <- sort(list.files(fdb, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
res <- list()
for (f in files) {
  m <- gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)
  d <- tryCatch(as.data.table(read_parquet(f, col_select = c("Factor_Name"))),
                error = function(e) NULL)
  if (is.null(d)) next
  fn <- unique(d$Factor_Name[grepl("^INV", d$Factor_Name)])
  if (length(fn)) res[[m]] <- fn
  rm(d)
}
all_inv <- sort(unique(unlist(res)))
mns <- names(res)
for (fx in all_inv) {
  present <- mns[vapply(res, function(v) fx %in% v, logical(1))]
  cat(fx, ": ", min(present), " ~ ", max(present), " (n_months=", length(present), ")\n", sep = "")
}
cat("\nDONE\n")
