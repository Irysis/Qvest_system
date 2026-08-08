suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[fq068] ",fmt,"\n"),...))

f <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
say("fred_macro: %d행 · 컬럼 %d", nrow(f), ncol(f))
say("컬럼: %s", paste(head(names(f), 30), collapse=", "))
if ("series_id" %in% names(f)) {
  ids <- sort(unique(f$series_id)); say("series 수 %d: %s", length(ids), paste(head(ids,25), collapse=", "))
  say("PCU334413334413 포함? %s", "PCU334413334413" %in% ids)
}
dc <- names(f)[grepl("date", names(f), ignore.case=TRUE)]
if (length(dc)) { s <- as.Date(f[[dc[1]]]); say("기간 %s ~ %s", min(s,na.rm=TRUE), max(s,na.rm=TRUE)) }
