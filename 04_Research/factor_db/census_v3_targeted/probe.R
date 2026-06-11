# probe.R — census v3 targeted: factor DB month probes (diagnostic)
suppressMessages({library(arrow); library(data.table)})
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
FDB <- file.path(PROJECT_ROOT, ".cache/factor_db")

dt <- as.data.table(read_parquet(file.path(FDB, "factor_db_201001.parquet"),
                                 col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
xf <- dt[grepl("^XF_", Factor_Name)]
cat("201001: total factors", uniqueN(dt$Factor_Name), "| XF factors", uniqueN(xf$Factor_Name), "\n")
print(xf[, .(n = sum(Coverage == TRUE & !is.na(Z_Score))), by = Factor_Name][order(Factor_Name)])
cat("maxAbsZ_all 201001:", max(abs(dt$Z_Score), na.rm = TRUE), "\n")

dt2 <- as.data.table(read_parquet(file.path(FDB, "factor_db_200701.parquet"),
                                  col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
cat("200701: XF factors:", uniqueN(dt2[grepl("^XF_", Factor_Name), Factor_Name]),
    "| total", uniqueN(dt2$Factor_Name), "\n")
for (t in c("IN03_RD_to_Market","XF_LL05_WorkingCapital","R05_Tail_Risk","V02_EP")) {
  cat(t, "in 200701:", t %in% dt2$Factor_Name, " in 201001:", t %in% dt$Factor_Name, "\n")
}
dt3 <- as.data.table(read_parquet(file.path(FDB, "factor_db_202001.parquet"),
                                  col_select = c("Factor_Name","Z_Score","Coverage")))
cat("202001: XF factors:", uniqueN(dt3[grepl("^XF_", Factor_Name), Factor_Name]), "\n")
xf3 <- dt3[grepl("^XF_", Factor_Name), .(n = sum(Coverage == TRUE & !is.na(Z_Score))), by = Factor_Name]
print(xf3[order(Factor_Name)])
cat("DONE\n")
