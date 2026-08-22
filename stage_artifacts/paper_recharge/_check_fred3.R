library(arrow)
library(data.table)
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
fred <- as.data.table(read_parquet(file.path(PROJ, ".cache/fred_macro.parquet")))
# BBB_Spread 확인
sub_bbb <- fred[Series == "BBB_Spread"]
cat(sprintf("[BBB_Spread] rows=%d, date: %s ~ %s, NA_pct=%.1f%%\n",
  nrow(sub_bbb), as.character(min(sub_bbb$Date)), as.character(max(sub_bbb$Date)),
  100*sum(is.na(sub_bbb$Value))/nrow(sub_bbb)))
