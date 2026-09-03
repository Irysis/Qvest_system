setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_R20260829_006")
suppressPackageStartupMessages({library(data.table); library(arrow)})
A <- as.data.table(read_parquet("alpha_scores.parquet"))
cat("cols:", paste(names(A), collapse = " | "), "\n")
cat("rows:", nrow(A), "\n")
print(head(A, 3))
cat("date range:", as.character(min(A[[grep("^(Date|sig_date)$", names(A), value=TRUE)[1]]])),
    as.character(max(A[[grep("^(Date|sig_date)$", names(A), value=TRUE)[1]]])), "\n")
