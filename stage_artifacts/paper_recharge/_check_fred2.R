library(arrow)
library(data.table)
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
fred <- as.data.table(read_parquet(file.path(PROJ, ".cache/fred_macro.parquet")))
target_series <- c("Term_Spread", "VIX", "KRW_USD", "HY_Spread")
for(s in target_series) {
  sub <- fred[Series == s]
  cat(sprintf("[%s] rows=%d, date: %s ~ %s, NA_pct=%.1f%%\n",
    s, nrow(sub), as.character(min(sub$Date)), as.character(max(sub$Date)),
    100*sum(is.na(sub$Value))/nrow(sub)))
}
