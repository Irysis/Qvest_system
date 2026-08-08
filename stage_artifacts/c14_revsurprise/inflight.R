suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[if] ",fmt,"\n"),...))
hi <- paste(unlist(fromJSON("06_Registry/hypothesis_index.json", simplifyVector=FALSE)), collapse=" ")
q  <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
qb <- paste(unlist(q), collapse=" ")
for (k in c("M26_Revenue_Mom","Revenue_Mom","Jegadeesh-Livnat","revenue_fy1","C14_Revenue_Surprise")) {
  say("%-22s | hypothesis_index %-5s | queue %-5s", k, grepl(k, hi, fixed=TRUE), grepl(k, qb, fixed=TRUE))
}
say("--- 최근 WT 디렉토리 (오늘) ---")
d <- list.dirs("qepm/mailbox/worktask", recursive=FALSE)
d <- d[grepl("20260808", basename(d), fixed=TRUE)]
for (x in sort(d)) {
  st <- file.path(x, "status.json")
  s <- if (file.exists(st)) tryCatch(fromJSON(st)$status, error=function(e) "?") else "(no status)"
  say("  %-28s %s", basename(x), s)
}
