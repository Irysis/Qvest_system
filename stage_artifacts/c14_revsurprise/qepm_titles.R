suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[t] ",fmt,"\n"),...))
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
ids <- c("FQ-090","FQ-091","FQ-105","FQ-106","FQ-109","FQ-113","FQ-114","FQ-117","FQ-119","FQ-120","FQ-122","FQ-124","FQ-126")
for (k in ids) {
  e <- Filter(function(x) isTRUE(identical(x$id,k)), q$entries)
  if (!length(e)) { say("%s 미발견", k); next }
  e <- e[[1]]
  g <- function(f){ v<-e[[f]]; if(is.null(v)) "" else paste(unlist(v),collapse=" ") }
  say("%s | %s", k, substr(g("title"),1,100))
  say("      EV: %s", substr(g("ev_rationale"),1,110))
}
