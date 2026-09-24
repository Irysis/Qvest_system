suppressPackageStartupMessages({library(arrow); library(data.table)})
p <- as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/replication/20260902_192126_25496/factors_panel.parquet", mmap=FALSE))
cat(names(p), "\n"); print(head(p,3)); if ("Factor_Name" %in% names(p)) print(p[, .N, by=Factor_Name]); cat("dates", format(range(p$Date)), uniqueN(p$Date), "\n")
