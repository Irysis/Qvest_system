## R28 parity decomposition — core vs defense sleeve, stored-theta recon
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source(file.path(QM,"stage_artifacts/WT_D20260714_004/_build_score.R")); recon_init()
SLEEVE7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]
theta_map <- unique(bk[,.(Date, theta_core)])
get_stored_theta <- function(d){ v<-unlist(fromJSON(theta_map[Date==d, theta_core][1])); v[SLEEVE7] }
test_dates <- as.Date(c("2005-01-01","2010-06-01","2015-06-01","2020-01-01","2024-06-01"))
cat("=== core_z vs defense_z parity (stored theta) ===\n")
cat(sprintf("%-12s %8s %8s %8s %8s %8s\n","date","cor_core","spr_core","cor_def","spr_def","cor_eff"))
for(d in test_dates){
  r <- build_month_score(d, SLEEVE7, theta_mode="stored", theta_override=get_stored_theta(d))
  if(is.null(r)||!is.null(r$err)) next
  m <- merge(r$dt, bk[Date==d,.(Ticker,se=score_eff,cz=score_core_z,dz=score_defense_z)], by="Ticker")
  m <- m[is.finite(score_core_z)&is.finite(cz)&is.finite(score_defense_z)&is.finite(dz)&is.finite(score_eff)&is.finite(se)]
  cc <- cor(m$score_core_z,m$cz); sc <- cor(m$score_core_z,m$cz,method="spearman")
  cd <- cor(m$score_defense_z,m$dz); sd_ <- cor(m$score_defense_z,m$dz,method="spearman")
  ce <- cor(m$score_eff,m$se)
  cat(sprintf("%-12s %8.4f %8.4f %8.4f %8.4f %8.4f\n", as.character(d), cc, sc, cd, sd_, ce))
}
## also: how many stored score_defense_z are NA (M08 gap)?
cat("\n=== stored NA counts by component (2015-06) ===\n")
st <- bk[Date==as.Date("2015-06-01")]
cat(sprintf("stored: eff NA=%d core NA=%d def NA=%d / n=%d\n",
  sum(!is.finite(st$score_eff)), sum(!is.finite(st$score_core_z)), sum(!is.finite(st$score_defense_z)), nrow(st)))
cat("PARITY_DECOMP_DONE\n")
