x <- readRDS("04_Research/method_frontier/wt006_exog_forecast/R4_mid_construction.rds")
cat("class:", class(x), "\n")
if (is.list(x)) { cat("names:", paste(names(x), collapse=", "), "\n")
  for (n in names(x)) {
    e <- x[[n]]
    cat(sprintf("  %-22s %s  %s\n", n, paste(class(e),collapse="/"),
      if (is.data.frame(e)) paste0("dim ", nrow(e), "x", ncol(e), " cols: ",
        paste(head(names(e),10), collapse=",")) else
      if (is.list(e)) paste0("list(", length(e), ") ", paste(head(names(e),6),collapse=",")) else ""))
  }
}
