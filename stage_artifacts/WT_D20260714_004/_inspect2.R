## R28 inspection 2 — theta_core evolution + defense factor construction
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]
tc <- unique(bk[,.(Date, theta_core)])
setorder(tc, Date)
cat("=== theta_core at selected dates ===\n")
for(d in as.character(c("2004-01-01","2005-01-01","2006-01-01","2010-06-01","2015-06-01","2020-01-01","2024-06-01","2026-04-01"))){
  row <- tc[Date==as.Date(d)]
  if(nrow(row)) cat(sprintf("%s : %s\n", d, row$theta_core))
}
cat("\n=== how many distinct theta_core strings ===\n")
cat(sprintf("distinct theta_core = %d over %d dates\n", uniqueN(tc$theta_core), nrow(tc)))
cat("\n=== theta_defense distinct ===\n")
cat(sprintf("distinct theta_defense = %d\n", uniqueN(bk$theta_defense)))
## check if C06 ever has 0 weight or negative
cat("\n=== parse theta_core, show C06 weight distribution ===\n")
tc[, c06 := vapply(theta_core, function(s){v<-fromJSON(s); as.numeric(v[["C06_TP_Gap"]])}, numeric(1))]
print(summary(tc$c06))
cat("first date where theta_core != EW(0.25):\n")
tc[, is_ew := abs(c06-0.25)<1e-6]
print(tc[is_ew==FALSE][order(Date)][1:3, .(Date, theta_core)])
cat("INSPECT2_DONE\n")
