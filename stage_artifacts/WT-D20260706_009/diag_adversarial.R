# diag_adversarial.R — Self-Adversarial Challenge verification
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PAN <- file.path(ROOT,"stage_artifacts/WT-D20260706_009/panel")
sc <- as.data.table(read_parquet(file.path(PAN,"nsi_scores_monthly.parquet")))[Date>=as.Date("2005-01-01")]
rets<- as.data.table(read_parquet(file.path(PAN,"returns_monthly.parquet")))[Date>=as.Date("2005-01-01")]

# (ii) large-cap RETIRE breadth: how many DISTINCT large-cap retirers per month? few-names coincidence?
d <- merge(sc[is.finite(nsi_shares), .(Date,Ticker,s=nsi_shares,size_pctile)], rets, by=c("Date","Ticker"))
lc_ret <- d[size_pctile>=0.60 & s>0.005]
cat(sprintf("(ii) large-cap RETIRE bucket: %d obs, %d distinct tickers, over %d months\n",
    nrow(lc_ret), uniqueN(lc_ret$Ticker), uniqueN(lc_ret$Date)))
cat(sprintf("     mean names/month = %.1f\n", nrow(lc_ret)/uniqueN(lc_ret$Date)))
# top contributors: is outperformance concentrated in <5 names?
byT <- lc_ret[, .(n=.N, mean_fwd=mean(Ret_1m,na.rm=TRUE)), by=Ticker][order(-n)]
cat("     top-8 most-frequent large-cap retirers:\n"); print(head(byT,8))

# (iv) value-up era 2024+ breadth
vu <- d[Date>=as.Date("2024-01-01") & s>0.005]
cat(sprintf("\n(iv) value-up 2024+ RETIRE bucket: %d obs, %d distinct tickers, %d months\n",
    nrow(vu), uniqueN(vu$Ticker), uniqueN(vu$Date)))

# (iii) EW-vs-capw: is EW-post17 positive purely small-cap? median size of top-25 picks post-2017
setorder(sc, Date, -nsi_shares)
t25 <- sc[is.finite(nsi_shares) & Date>=as.Date("2017-01-01"), .SD[seq_len(min(25L,.N))], by=Date]
cat(sprintf("\n(iii) POST-2017 top-25 NSI picks: median size-pctile=%.1f%% (100=largest), frac in size top-40%%=%.2f\n",
    100*median(t25$size_pctile), mean(t25$size_pctile>=0.60)))

# Additional adversarial: is rank-IC t=4.30 an illiquid microcap artifact? re-run IC with liq>=2e8 enforced
univ <- as.data.table(read_parquet(file.path(PAN,"universe_flags.parquet")))[Date>=as.Date("2005-01-01")]
liq <- univ[adv20>=2e8, .(Date,Ticker)]
d2 <- merge(d, liq, by=c("Date","Ticker"))
icm <- d2[, .(ic=suppressWarnings(cor(s,Ret_1m,method="spearman"))), by=Date][is.finite(ic)]
cat(sprintf("\n(v) rank-IC among LIQUID (adv>=2e8) names only: mean=%.4f t=%.2f n=%d\n",
    mean(icm$ic), mean(icm$ic)/(sd(icm$ic)/sqrt(nrow(icm))), nrow(icm)))
cat("[adv] DONE\n")
