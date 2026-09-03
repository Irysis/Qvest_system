setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(jsonlite)})
ap <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json", simplifyVector = FALSE)
cat("=== ALPHA PACKAGE FIELDS ===\n")
for (n in names(ap)) {
  v <- ap[[n]]
  cat(sprintf("%-40s %-12s len=%d\n", n, paste(class(v), collapse=","), length(v)))
}
cat("\n=== RISK PACKAGE FIELDS ===\n")
rp <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/risk_package.json", simplifyVector = FALSE)
for (n in names(rp)) {
  v <- rp[[n]]
  cat(sprintf("%-40s %-12s len=%d\n", n, paste(class(v), collapse=","), length(v)))
  if (is.list(v) && length(v) <= 30 && !is.null(names(v))) {
    for (m in names(v)) {
      vv <- v[[m]]
      if (!is.list(vv) && length(vv) <= 4) cat(sprintf("      .%-34s %s\n", m, paste(format(unlist(vv)), collapse=", ")))
      else cat(sprintf("      .%-34s <%s len=%d>\n", m, paste(class(vv),collapse=","), length(vv)))
    }
  }
}
