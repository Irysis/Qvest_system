Sys.setenv(LC_ALL = "English_United States.utf8")
suppressMessages({ library(data.table); library(arrow) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/factor_db/factor_db_connector.R")

cons_factors <- c("GR03_Asset_Growth","Q06_Asset_Growth","AC24_NOA_Growth","AC05_NOA",
                  "AC09_NNI","IN04_Net_Equity_Issuance","IN05_Net_Debt_Issuance",
                  "IN06_Investment_to_Assets","IN01_CapEx_to_Assets","Q20_Net_Equity_Issuance")

# 1) latest months available
fdir <- FACTOR_DB_DIR
avail <- list.files(fdir, pattern="^factor_db_\\d{6}\\.parquet$")
ym <- sort(gsub("factor_db_(\\d{6})\\.parquet","\\1", avail))
cat("FACTOR_DB_DIR:", fdir, "\n")
cat("N monthly files:", length(ym), " range:", head(ym,1), "->", tail(ym,1), "\n\n")

# 2) coverage of each conservative factor at latest complete months
for (tag in tail(ym, 3)) {
  f <- file.path(fdir, paste0("factor_db_", tag, ".parquet"))
  dt <- as.data.table(read_parquet(f))
  # which column holds factor code
  fcol <- intersect(c("Factor_Name","Factor","factor_name"), names(dt))[1]
  cat("=== month", tag, " rows=", nrow(dt), " factors=", uniqueN(dt[[fcol]]), "===\n")
  sub <- dt[get(fcol) %in% cons_factors]
  zcol <- intersect(c("Z_Score","Z_Score_Aligned","Z"), names(sub))[1]
  cnt <- sub[, .(n=.N, n_nonNA=sum(!is.na(get(zcol)))), by=fcol]
  print(cnt)
  cat("\n")
}

# 3) load_month_factors at 2026-06-30 (last complete month) — does it return the cons factors?
cat("=== load_month_factors(2026-06-30) probe ===\n")
lm <- tryCatch(load_month_factors(as.Date("2026-06-30"), factor_names=cons_factors),
               error=function(e) { cat("ERROR:", conditionMessage(e),"\n"); NULL })
if (!is.null(lm)) {
  cat("rows:", nrow(lm), " unique factors:", uniqueN(lm$Factor_Name), "\n")
  print(lm[, .(n_tickers=uniqueN(Ticker), mean_z=round(mean(Z_Score_Aligned,na.rm=TRUE),3)), by=Factor_Name])
}
