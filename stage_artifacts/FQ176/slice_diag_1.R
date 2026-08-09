setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table)})
A <- readRDS("stage_artifacts/FQ176/slice_1.rds")
m <- attr(A, "months_meta")
cat("[DIAG] months with <54 factors:\n"); print(m[n_factor < 54, .(Date, n_factor, n_ticker, n_row)])
cov <- A[, .(n_months = uniqueN(Date)), by = Factor_Name][order(n_months)]
cat("[DIAG] factors not present in all 71 months:\n"); print(cov[n_months < 71])
cat("[DIAG] file size MB:",
    round(file.info("stage_artifacts/FQ176/slice_1.rds")$size/1024^2, 2), "\n")
cat("[DIAG] attrs:", paste(setdiff(names(attributes(A)), c("names","row.names",".internal.selfref","class")), collapse=", "), "\n")
