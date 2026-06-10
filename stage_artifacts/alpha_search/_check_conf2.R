suppressPackageStartupMessages({library(arrow);library(data.table)})
BASE <- "G:/Quant_Module_Moltbot"
PROD <- file.path(BASE,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
a <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_str1715_268m.parquet")))
r05 <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_r05_panel.parquet")))
a <- merge(a, r05[,.(Date,Ticker,confidence)], by=c("Date","Ticker"), all.x=TRUE)
sig_dates <- sort(unique(a[!is.na(score_eff), Date]))
MAXN<-20L
sds <- c()
for(sl in sig_dates){
  panel <- a[Date==sl & !is.na(score_eff)]; if(nrow(panel)==0) next
  setorder(panel,-score_eff); picks <- panel[seq_len(min(MAXN,nrow(panel)))]
  cf <- picks$confidence; cf <- cf[is.finite(cf)]
  if(length(cf)>1) sds <- c(sds, sd(cf))
}
cat("WITHIN top-20 picks: median cross-sectional sd of confidence =", round(median(sds),6), "\n")
cat("  dates where within-pick sd==0:", sum(sds==0), "of", length(sds), "\n")
cat("  fraction dates with sd<0.01:", round(mean(sds<0.01),4), "\n")
cat("  summary of within-pick sd:\n"); print(summary(sds))
