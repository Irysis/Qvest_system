## R28 parity test 2 — stored-theta reconstruction (faithful to deployed book) + debug NA
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source(file.path(QM,"stage_artifacts/WT_D20260714_004/_build_score.R"))
recon_init()
SLEEVE7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]

## stored theta_core map per date
theta_map <- unique(bk[,.(Date, theta_core)])
get_stored_theta <- function(d){ s<-theta_map[Date==d, theta_core][1]; v<-unlist(fromJSON(s)); v[SLEEVE7] }

test_dates <- as.Date(c("2005-01-01","2010-06-01","2015-06-01","2020-01-01","2024-06-01","2026-04-01"))
cat("=== STORED-THETA reconstruction parity (7F) ===\n")
for(d in test_dates){
  th <- get_stored_theta(d)
  r <- build_month_score(d, SLEEVE7, theta_mode="stored", theta_override=th)
  if(is.null(r)||!is.null(r$err)){cat(sprintf("%s ERR\n",d)); next}
  m <- merge(r$dt[,.(Ticker,se_recon=score_eff)], bk[Date==d,.(Ticker,se_stord=score_eff)], by="Ticker")
  m <- m[is.finite(se_recon)&is.finite(se_stord)]
  cat(sprintf("%s | n=%d fin=%d | cor=%.4f spear=%.4f max|d|=%.3f mean|d|=%.3f | any_na_recon=%d\n",
    d, nrow(r$dt), nrow(m), cor(m$se_recon,m$se_stord), cor(m$se_recon,m$se_stord,method="spearman"),
    max(abs(m$se_recon-m$se_stord)), mean(abs(m$se_recon-m$se_stord)),
    sum(!is.finite(r$dt$score_eff))))
}
cat("\n=== debug: 2005-01 recon score_eff head + NA check ===\n")
r <- build_month_score(as.Date("2005-01-01"), SLEEVE7, theta_mode="stored", theta_override=get_stored_theta(as.Date("2005-01-01")))
print(head(r$dt))
cat(sprintf("recon NA/Inf in score_eff: %d / %d\n", sum(!is.finite(r$dt$score_eff)), nrow(r$dt)))
st <- bk[Date==as.Date("2005-01-01")]
cat(sprintf("stored NA/Inf in score_eff: %d / %d\n", sum(!is.finite(st$score_eff)), nrow(st)))
cat("PARITY_TEST2_DONE\n")
