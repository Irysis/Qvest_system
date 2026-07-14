## R28 parity pre-test — reconstruct 7F score_eff for a test window vs stored, before full run.
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source(file.path(QM,"stage_artifacts/WT_D20260714_004/_build_score.R"))
recon_init()
SLEEVE7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")

bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]

test_dates <- as.Date(c("2005-01-01","2005-02-01","2010-06-01","2015-06-01","2020-01-01","2024-06-01"))
cat("=== theta_core parity (recon vs stored) ===\n")
for(d in test_dates){
  r <- build_month_score(d, SLEEVE7)
  if(is.null(r)||!is.null(r$err)){cat(sprintf("%s : ERR %s\n", d, if(is.null(r))"null" else r$err)); next}
  st <- unique(bk[Date==d, theta_core])[1]
  cat(sprintf("%s recon: %s\n", d, toJSON(as.list(round(r$theta_core,4)),auto_unbox=TRUE)))
  cat(sprintf("%s stord: %s\n", d, st))
  ## score_eff parity
  m <- merge(r$dt[,.(Ticker,se_recon=score_eff)], bk[Date==d,.(Ticker,se_stord=score_eff)], by="Ticker")
  cat(sprintf("   n_common=%d (recon=%d, stored=%d) | cor=%.5f | spearman=%.5f | max|diff|=%.4f | mean|diff|=%.4f\n\n",
    nrow(m), nrow(r$dt), bk[Date==d,.N],
    cor(m$se_recon,m$se_stord), cor(m$se_recon,m$se_stord,method="spearman"),
    max(abs(m$se_recon-m$se_stord)), mean(abs(m$se_recon-m$se_stord))))
}
cat("PARITY_TEST_DONE\n")
