## WT-D20260822_006 P1c — 팩터 계열(선언) 매핑 실측 + 군집 검정력 (사전등록 재료)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260822_006"
P0 <- readRDS(file.path(OUT,"p0_probe.rds"))
sel <- sort(unique(unlist(P0$sel_rank)))
cat("선별 이력 팩터:", length(sel), "\n")

reg_path <- "02_Infrastructure/factor_db/factor_registry.json"
if (!file.exists(reg_path)) reg_path <- "06_Registry/factor_registry.json"
cat("registry:", reg_path, " exists:", file.exists(reg_path), "\n")
R <- fromJSON(reg_path, simplifyVector = FALSE)
nm <- if (!is.null(R$factors)) R$factors else R
cat("registry entries:", length(nm), "\n")
row1 <- nm[[1]]; cat("fields:", paste(names(row1), collapse=", "), "\n")

getf <- function(e, k) { v <- e[[k]]; if (is.null(v)) NA_character_ else as.character(v)[1] }
ids <- vapply(nm, function(e) { for (k in c("factor_id","id","code","name")) { v <- getf(e,k); if (!is.na(v)) return(v) }; NA_character_ }, "")
cat_ <- vapply(nm, function(e) getf(e, "category"), "")
efam <- vapply(nm, function(e) getf(e, "economic_family"), "")
REG <- data.table(factor_id=ids, category=cat_, economic_family=efam)
cat("\n declared category (전체):\n"); print(sort(table(REG$category), decreasing=TRUE))
cat("\n declared economic_family (전체):\n"); print(sort(table(REG$economic_family), decreasing=TRUE))

M <- REG[factor_id %in% sel]
cat("\n선별 이력 103종 매칭:", nrow(M), "/", length(sel), "\n")
cat(" 계열 분포(category):\n"); print(sort(table(M$category), decreasing=TRUE))
cat(" 계열 분포(economic_family):\n"); print(sort(table(M$economic_family), decreasing=TRUE))
miss <- setdiff(sel, REG$factor_id)
cat(" 미매칭:", length(miss), if (length(miss)) paste(head(miss,15), collapse=", ") else "", "\n")

saveRDS(list(REG=REG, sel=sel, M=M, miss=miss), file.path(OUT,"p1c_family.rds"))
cat("\n[saved] p1c_family.rds\n")
