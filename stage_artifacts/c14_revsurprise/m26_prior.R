suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[m26] ",fmt,"\n"),...))
flat <- function(x) unlist(lapply(x, function(y) paste(unlist(y), collapse=" | ")))
ki <- flat(fromJSON("06_Registry/knowledge_index.json", simplifyVector=FALSE))
hi <- flat(fromJSON("06_Registry/hypothesis_index.json", simplifyVector=FALSE))
q  <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
say("--- knowledge_index 내 M26 ---")
for (i in which(sapply(ki, function(s) grepl("M26_Revenue_Mom", s, fixed=TRUE)))) {
  s <- ki[[i]]; p <- regexpr("M26_Revenue_Mom", s, fixed=TRUE)
  say("  ...%s...", gsub("[[:space:]]+"," ", substr(s, max(1,p-180), min(nchar(s), p+260))))
}
say("--- hypothesis_index 내 M26 ---")
for (i in head(which(sapply(hi, function(s) grepl("M26_Revenue_Mom", s, fixed=TRUE))),3)) {
  s <- hi[[i]]; p <- regexpr("M26_Revenue_Mom", s, fixed=TRUE)
  say("  ...%s...", gsub("[[:space:]]+"," ", substr(s, max(1,p-180), min(nchar(s), p+260))))
}
say("--- queue 내 M26 항목 ---")
for (e in q$entries) {
  b <- paste(unlist(e), collapse=" ")
  if (grepl("M26_Revenue_Mom", b, fixed=TRUE)) say("  %s | %s | %s",
    if(is.null(e$id)) "?" else e$id, substr(if(is.null(e$status)) "?" else e$status,1,26),
    substr(if(is.null(e$title)) "?" else e$title,1,80))
}
