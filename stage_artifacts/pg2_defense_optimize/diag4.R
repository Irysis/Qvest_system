## Per-factor sign diagnosis: correlate each aligned factor with stored def_z.
## If a factor that SHOULD load + shows strong NEGATIVE cor, its sign flipped (IC-vintage drift).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
CUR_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[,Date:=as.Date(Date)]
DTS <- as.Date(c("2008-01-01","2018-03-01","2022-09-01"))
for(ii in seq_along(DTS)){
  SD <- DTS[ii]; fym <- format(SD,"%Y%m")
  f <- as.data.table(read_parquet(file.path(FACTOR_DB_DIR,sprintf("factor_db_%s.parquet",fym)),col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% CUR_DEF & Coverage==TRUE, .(Ticker,Factor_Name,Z_Score)]
  fa <- align_factor_direction(f, .load_registry(), sig_date=SD, min_ic_months=12L)
  fa[, aligned := if("Z_Score_Aligned" %in% names(fa)) Z_Score_Aligned else Z_Score]
  fa[, sign_flip := sign(aligned) != sign(Z_Score)]
  fw <- dcast(fa, Ticker ~ Factor_Name, value.var="aligned", fill=NA_real_)
  tks <- ap[Date==SD, Ticker]; fw <- fw[Ticker %in% tks]
  st <- ap[Date==SD, .(Ticker, stored=score_defense_z)]
  mg <- merge(fw, st, by="Ticker")
  cat(sprintf("\n=== %s ===\n", as.character(SD)))
  for(fn in intersect(CUR_DEF,names(mg))){
    cc <- suppressWarnings(cor(mg[[fn]], mg$stored, use="complete.obs"))
    flip <- fa[Factor_Name==fn, mean(sign_flip,na.rm=T)]
    cat(sprintf("  cor(stored, aligned %s)=%+.3f | flipped-frac=%.2f\n", fn, cc, flip))
  }
}
