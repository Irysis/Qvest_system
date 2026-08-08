suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[fq068] ",fmt,"\n"),...))
f <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
ids <- f[, .N, by=.(Series_ID, Series, Frequency)][order(-N)]
say("보유 시리즈 %d종", nrow(ids)); print(head(ids, 25))
say("PCU334413334413 보유? %s", "PCU334413334413" %in% ids$Series_ID)
say("반도체 관련 검색:")
print(ids[grepl("semi|chip|PCU33|electronic", paste(Series_ID, Series), ignore.case=TRUE)])
