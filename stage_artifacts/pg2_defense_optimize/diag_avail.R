suppressPackageStartupMessages({library(arrow); library(data.table)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
for(ym in c("200801","201206","201803","202209","202605","202606")){
  f <- as.data.table(read_parquet(sprintf("%s/.cache/factor_db/factor_db_%s.parquet",ROOT,ym), col_select=c("Factor_Name","Z_Score","Coverage")))
  for(fn in c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")){
    n <- f[Factor_Name==fn & Coverage==TRUE & !is.na(Z_Score), .N]
    cat(sprintf("%s %s: n_valid=%d\n", ym, fn, n))
  }
  cat("---\n")
}
