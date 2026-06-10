suppressPackageStartupMessages({library(arrow);library(data.table)})
BASE <- "G:/Quant_Module_Moltbot"
PROD <- file.path(BASE,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
a <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_str1715_268m.parquet")))
r05 <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_r05_panel.parquet")))
a <- merge(a, r05[,.(Date,Ticker,confidence)], by=c("Date","Ticker"), all.x=TRUE)
cat("rows:", nrow(a), " confidence NA frac:", round(mean(is.na(a$confidence)),4), "\n")
cf <- a$confidence[is.finite(a$confidence)]
cat("confidence: n_finite=", length(cf), " sd=", sd(cf), " range=", min(cf), "~", max(cf), "\n")
cat("unique confidence values (head):", paste(round(head(sort(unique(cf)),10),5),collapse=","), "\n")
# how many distinct per date (cross-sectional)
bydate <- a[is.finite(confidence), .(sd_cf=sd(confidence,na.rm=TRUE), n=.N), by=Date]
cat("median cross-sectional sd of confidence per date:", round(median(bydate$sd_cf,na.rm=TRUE),6),
    " | dates with sd==0:", sum(bydate$sd_cf==0,na.rm=TRUE), "of", nrow(bydate), "\n")
