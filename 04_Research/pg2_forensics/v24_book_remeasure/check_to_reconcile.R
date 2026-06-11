suppressPackageStartupMessages({library(data.table)})
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/pg2_forensics/v24_book_remeasure"
pr <- fread(file.path(OUT, "base_str1715_03_period_returns.csv"))
l5 <- fread(file.path(OUT, "period_returns_layer5.csv"))
pr[, ym := format(as.Date(date), "%Y-%m")]
cat(sprintf("TO ann full incl m1 : %.4f\n", mean(pr$turnover)*12))
cat(sprintf("TO ann 255m (>=2005-02): %.4f\n", mean(pr[ym >= "2005-02"]$turnover)*12))
cat(sprintf("db_thr ann (AR legs)   : %.4f\n", mean(l5$db_thr)*12))
cat(sprintf("db_R05_V2 ann          : %.4f\n", mean(l5$db_R05_V2)*12))
cat(sprintf("base+AR                : %.4f\n", mean(pr$turnover)*12 + mean(l5$db_thr)*12))
cat(sprintf("base+AR+R05V2          : %.4f\n", mean(pr$turnover)*12 + mean(l5$db_thr)*12 + mean(l5$db_R05_V2)*12))
cat(sprintf("base255+AR             : %.4f\n", mean(pr[ym >= "2005-02"]$turnover)*12 + mean(l5$db_thr)*12))
