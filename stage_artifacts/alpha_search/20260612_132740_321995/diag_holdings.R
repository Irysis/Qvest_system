suppressMessages(library(data.table))
d <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260612_132740_321995"
b <- readRDS(file.path(d, "bt_result.rds"))
h <- as.data.table(b$holdings)
nh <- h[, .N, by = date]
cat("N per rebalance: min", min(nh$N), "median", as.numeric(median(nh$N)), "max", max(nh$N), "| n rebal:", nrow(nh), "\n")
last <- h[date == max(date)]
cat("last date weights summary: min", min(last$target_weight), "max", max(last$target_weight), "sd", sd(last$target_weight), "\n")
