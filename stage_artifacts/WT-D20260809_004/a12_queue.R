setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
ids <- sapply(Q$entries, function(e) if (is.null(e$id)) NA_character_ else e$id)
i <- which(ids == "FQ-173")
cat(sprintf("FQ-173 index: %s / entries %d\n", paste(i, collapse=","), length(Q$entries)))
if (length(i) == 1L) {
  e <- Q$entries[[i]]
  cat("현재 필드:", paste(names(e), collapse=", "), "\n")
  cat("status:", as.character(e$status), "\n")
  cat("owner:", as.character(e$owner), "\n")
}
