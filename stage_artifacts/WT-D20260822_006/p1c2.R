suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT-D20260822_006"
P0 <- readRDS(file.path(OUT,"p0_probe.rds")); sel <- sort(unique(unlist(P0$sel_rank)))
R <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
nm <- if (!is.null(R$factors)) R$factors else R
ids <- names(nm)
cat("names(nm) head:", paste(head(ids,5), collapse=" | "), "\n")
cats <- vapply(nm, function(e) { v<-e[["category"]]; if (is.null(v)) NA_character_ else as.character(v)[1] }, "")
REG <- data.table(factor_id=ids, category=cats)
M <- REG[factor_id %in% sel]
cat("매칭:", nrow(M), "/", length(sel), "\n")
print(sort(table(M$category), decreasing=TRUE))
cat("미매칭:", paste(head(setdiff(sel, REG$factor_id),10), collapse=", "), "\n")
saveRDS(list(REG=REG, sel=sel, M=M), file.path(OUT,"p1c_family.rds"))
