PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R")
res <- load_rawdata(TRUE); RAWDATA <- res$RAWDATA; rm(res); gc()
# ticker-level market label consistency
tk <- RAWDATA[, .(n=.N, n_kospi=sum(Market=="KOSPI", na.rm=TRUE), n_na=sum(is.na(Market)),
                  k200=sum(K200, na.rm=TRUE), kq150=sum(KQ150, na.rm=TRUE),
                  src=paste(unique(source), collapse="|")), by=Ticker]
tk[, lbl := fifelse(n_kospi>0 & n_na==0, "KOSPI_only", fifelse(n_kospi==0 & n_na>0, "NA_only", "MIXED"))]
cat("\n== ticker-level Market label ==\n"); print(tk[, .N, by=lbl])
cat("\n== cross: label x has-K200 x has-KQ150 ==\n")
print(tk[, .(N=.N, anyK200=sum(k200>0), anyKQ150=sum(kq150>0)), by=lbl])
cat("\n== source values by label ==\n"); print(tk[, .N, by=.(lbl, src)][order(-N)][1:15])
cat("\n== sample NA_only names ==\n"); print(head(RAWDATA[Ticker %in% tk[lbl=="NA_only", Ticker][1:8], .(Name=Name[1], Ticker=Ticker[1]), by=Ticker], 10))
cat("\n== sample KOSPI_only names ==\n"); print(head(RAWDATA[Ticker %in% tk[lbl=="KOSPI_only", Ticker][1:8], .(Name=Name[1]), by=Ticker], 10))
cat("\n== MIXED sample ==\n"); print(head(tk[lbl=="MIXED"], 10))
saveRDS(tk, "04_Research/strategies/RF_B3_12_KOSDAQ_All/tk_labels.rds")
