suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
U <- as.data.table(read_parquet(".cache/universe.parquet"))
say("universe 컬럼: %s", paste(names(U), collapse=", "))
say("행 %d", nrow(U)); print(head(U,3))
for (cc in setdiff(names(U), c("Ticker","Date"))) {
  v <- U[[cc]]
  if (is.logical(v)||uniqueN(v)<=6) say("  %s: %s", cc, paste(head(sort(unique(as.character(v))),6), collapse=" | "))
}
