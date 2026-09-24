suppressMessages({library(arrow);library(data.table)})
for (ym in c("202003","202608")) {
  p <- sprintf(".cache/factor_db/factor_db_%s.parquet", ym)
  if (!file.exists(p)) { cat("missing", p, "\n"); next }
  sc <- names(open_dataset(p)$schema)
  d <- as.data.table(read_parquet(p, mmap=FALSE))
  if ("Factor_Name" %in% sc) {
    x <- d[Factor_Name %in% c("D32_Beta_VIX","MA01_GDP_Sensitivity","MA02_CPI_Sensitivity","MA07_BusinessCycle_Composite","RE14_Inflation_YoY","RE10_VIX_Pctile","MA04_YieldCurve_Sensitivity"), .(n=.N, date=max(as.Date(Date))), by=Factor_Name]
  } else {
    cols <- intersect(c("D32_Beta_VIX","MA01_GDP_Sensitivity","MA02_CPI_Sensitivity","RE14_Inflation_YoY"), sc)
    x <- data.table(cols=cols)
  }
  cat("==", ym, "\n"); print(x)
}
