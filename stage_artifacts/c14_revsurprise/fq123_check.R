suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[123] ",fmt,"\n"),...))
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
e <- Filter(function(x) isTRUE(identical(x$id,"FQ-123")), q$entries)[[1]]
for (k in c("id","status","title","hypothesis","ev_rationale","wall_check","data_gate","owner","parent","registered")) {
  v <- e[[k]]; if(!is.null(v)) say("%-14s: %s", k, substr(paste(unlist(v),collapse=" "),1,400))
}
