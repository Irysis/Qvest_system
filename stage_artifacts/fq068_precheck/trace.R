suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
E <- as.data.table(read_parquet("stage_artifacts/fq068_precheck/fq068b_ecos_semi.parquet"))
item_lab <- "반도체"; ccy_sel <- "D"
cat("step1 filter... "); s <- E[item==item_lab & ccy==ccy_sel][order(ym)]; cat("ok", nrow(s), "\n")
cat("step2 mom... "); s[, `:=`(dx = Value/shift(Value,1)-1, mom6 = Value/shift(Value,6)-1)]; cat("ok\n")
cat("step3 ref_ym... "); s[, ref_ym := ym]; cat("ok\n")
cat("step4 hold_ym... ")
s[, hold_ym := format(as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")) %m+% months(2), "%Y-%m")]
cat("ok\n")
cat("step5 sel... "); x <- s[, .(ref_ym, dx)]; cat("ok", nrow(x), "\n")
cat("head:\n"); print(head(s[, .(ym, ref_ym, hold_ym, Value, dx, mom6)], 3))
