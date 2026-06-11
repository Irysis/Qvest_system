suppressMessages({library(arrow); library(data.table)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
p <- file.path(root, ".cache/dart/dart_raw_quarterly.parquet")
dt <- as.data.table(arrow::read_parquet(p, col_select=c("rcept_no","reprt_code","bsns_year","Ticker")))
fil <- unique(dt[, .(rcept_no, reprt_code, bsns_year, Ticker)])
fil[, rcept_date := as.Date(substr(rcept_no,1,8), format="%Y%m%d")]
fil[, rcept_md := format(rcept_date, "%m")]   # month of receipt

# period-end + legal deadline (assume Dec FYE)
period_end <- function(yr, rc) {
  fifelse(rc=="11013", as.Date(sprintf("%d-03-31", yr)),
  fifelse(rc=="11012", as.Date(sprintf("%d-06-30", yr)),
  fifelse(rc=="11014", as.Date(sprintf("%d-09-30", yr)),
  fifelse(rc=="11011", as.Date(sprintf("%d-12-31", yr)), as.Date(NA)))))
}
legal_deadline <- function(pe, rc) fifelse(rc=="11011", pe + 90L, pe + 45L)
fil[, pe := period_end(bsns_year, reprt_code)]
fil[, deadline := legal_deadline(pe, reprt_code)]
fil[, earliness := as.integer(deadline - rcept_date)]   # days early (positive=before deadline)

cat("=== receipt month distribution by reprt_code ===\n")
print(dcast(fil, reprt_code ~ rcept_md, fun.aggregate=length, value.var="Ticker"))

cat("\n=== earliness (days before legal deadline) summary by reprt_code ===\n")
print(fil[, as.list(summary(earliness)), by=reprt_code][order(reprt_code)])

cat("\n=== % filed AFTER deadline (earliness<0, late) by reprt_code ===\n")
print(fil[, .(pct_late = round(100*mean(earliness<0, na.rm=TRUE),1),
              pct_neg30 = round(100*mean(earliness < -30, na.rm=TRUE),1),
              n=.N), by=reprt_code][order(reprt_code)])

cat("\n=== overall earliness quantiles ===\n")
print(round(quantile(fil$earliness, c(0,.01,.05,.25,.5,.75,.95,.99,1), na.rm=TRUE),1))

cat("\nNA earliness:", sum(is.na(fil$earliness)), "of", nrow(fil), "\n")
cat("distinct filings:", nrow(fil), " | distinct tickers:", uniqueN(fil$Ticker), "\n")
