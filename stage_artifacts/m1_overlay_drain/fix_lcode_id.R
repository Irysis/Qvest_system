suppressMessages(library(jsonlite))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
id <- read_json("stage_artifacts/l_code/alpha_research/l_code_FQ-017_m1_overlay_drain.json")$l_code
cat("L-code id:", id, "\n")
writeLines(id, "stage_artifacts/m1_overlay_drain/lcode_id.txt")
QP <- "06_Registry/alpha_frontier_queue.json"
q <- read_json(QP, simplifyVector=FALSE)
idx <- which(vapply(q$entries, function(x) identical(x$id,"FQ-017"), logical(1)))
q$entries[[idx]]$result$l_code <- id
tmp <- paste0(QP,".tmp",Sys.getpid())
write_json(q, tmp, auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null")
file.copy(QP, paste0(QP,".bak"), overwrite=TRUE); file.remove(QP); stopifnot(file.rename(tmp,QP))
cat("done\n")
