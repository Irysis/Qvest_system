PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R")
res <- load_rawdata(TRUE); RAWDATA <- res$RAWDATA; rm(res); gc()
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y-%m")]
me <- sort(RAWDATA[, .(Date=max(Date)), by=.ym]$Date); RAWDATA[, .ym := NULL]
me <- me[me >= as.Date("2005-01-01")]
RAWDATA[, .TV := Close*Vol]
RAWDATA[, .A20 := shift(frollmean(.TV,20L,align="right"),1L), by=Ticker]
M <- RAWDATA[Date %in% me, .(Date,Ticker,K200,KQ150,A20=.A20)]
M[, k2 := !is.na(K200) & K200==TRUE][, kq := !is.na(KQ150) & KQ150==TRUE]
M[, liq := is.finite(A20) & A20 >= 2e8]
agg <- M[, .(n_all=.N, n_liq=sum(liq),
             k200=sum(k2), k200_liq=sum(k2&liq),
             kq150=sum(kq), kq150_liq=sum(kq&liq),
             union_liq=sum((k2|kq)&liq),
             neither_liq=sum(!k2&!kq&liq),
             both=sum(k2&kq)), by=Date]
cat("\n== yearly medians of month-end counts ==\n")
print(agg[, lapply(.SD, function(x) as.integer(median(x))), by=.(yr=year(Date)),
          .SDcols=c("n_all","n_liq","k200_liq","kq150_liq","union_liq","neither_liq")])
cat("\n== overlap K200&KQ150 (should be 0) total:", sum(agg$both), "\n")
cat("\n== KQ150 months with 0 members:", sum(agg$kq150==0), "of", nrow(agg), "\n")
cat("== KQ150 first month with >0 members:", format(min(agg[kq150>0]$Date)), "\n")
cat("== months where kq150_liq < 25 (from first KQ150 month):",
    nrow(agg[Date>=min(agg[kq150>0]$Date) & kq150_liq<25]), "\n")
cat("== months where union_liq < 25:", nrow(agg[union_liq<25]), "\n")
saveRDS(agg, "04_Research/strategies/RF_B3_12_KOSDAQ_All/agg_cells.rds")
# KQ150 membership dynamics: entries vs exits
kqm <- M[kq==TRUE, .(Date,Ticker)][order(Date)]
sp <- split(kqm$Ticker, kqm$Date); dts <- names(sp)
ent <- exi <- integer(length(sp)-1)
for(i in 2:length(sp)){ ent[i-1] <- length(setdiff(sp[[i]], sp[[i-1]])); exi[i-1] <- length(setdiff(sp[[i-1]], sp[[i]])) }
cat("\n== KQ150 membership churn: total entries =", sum(ent), " total exits =", sum(exi), "\n")
cat("== KQ150 distinct tickers ever:", uniqueN(kqm$Ticker), "\n")
