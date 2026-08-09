suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

paths <- c(file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json"),
           file.path(ROOT, ".cache/factor_db/factor_registry.json"))
for (p in paths) {
  cat(sprintf("[d2] %-70s exists=%s  md5=%s\n", p, file.exists(p),
              if (file.exists(p)) substr(tools::md5sum(p), 1, 12) else "-"))
}

reg <- fromJSON(paths[1], simplifyVector = FALSE)

for (f in c("C01_SUE", "C11_Earnings_Streak", "M25_Earnings_Mom_Streak",
            "C04_ESBR", "C13_Revision_Breadth_3m",
            "C09_Earnings_Surprise_Sq", "C10_SUE_Persistence")) {
  cat("\n===== ", f, " =====\n")
  e <- reg[[f]]
  cat("  category      : ", as.character(e$category %||% NA), "\n")
  cat("  direction     : ", as.character(e$direction %||% NA), "\n")
  cat("  data_source   : ", as.character(e$data_source %||% NA), "\n")
  cat("  added_date    : ", as.character(e$lifecycle$added_date %||% NA), "\n")
  cat("  definition    : ", substr(as.character(e$definition %||% ""), 1, 150), "\n")
  if (!is.null(e$dedup)) {
    cat("  dedup:\n")
    cat(paste0("    ", strsplit(toJSON(e$dedup, auto_unbox = TRUE, pretty = 2,
                                       digits = NA), "\n")[[1]]), sep = "\n")
  } else cat("  dedup         : NONE\n")
}

# earnings_surprise cluster 전체 멤버
cl <- vapply(names(reg), function(f) {
  d <- reg[[f]]$dedup
  if (is.null(d) || is.null(d$cluster)) NA_character_ else as.character(d$cluster)[1]
}, character(1))
target_cl <- cl[["C01_SUE"]]
cat(sprintf("\n[d2] C01_SUE cluster = %s ; 멤버 = %s\n", target_cl,
            paste(names(cl)[which(cl == target_cl)], collapse = ", ")))
