## Replicate EXACT canonical build_composite_ew defense: winsor+EW over post-filter scope,
## NA propagates (NOT zero-fill), zc over same scope. Scope = alpha_scores tickers per date.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
CUR_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
winsor_z <- function(x, sigma=2.5){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[,Date:=as.Date(Date)]

recon <- function(SD){
  fym <- format(SD,"%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet",fym))
  if(!file.exists(fpath)) return(NULL)
  f <- as.data.table(read_parquet(fpath, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  # canonical: Coverage==TRUE only (keep NA Z), NEEDED filter
  f <- f[Factor_Name %in% CUR_DEF & Coverage==TRUE, .(Ticker,Factor_Name,Z_Score)]
  fa <- align_factor_direction(f, .load_registry(), sig_date=SD, min_ic_months=12L)
  if("Z_Score_Aligned" %in% names(fa)) fa[,Z_Score:=Z_Score_Aligned]
  fw <- dcast(fa, Ticker ~ Factor_Name, value.var="Z_Score", fill=NA_real_)
  # SCOPE = alpha_scores tickers this date (post liq/universe)
  tks <- ap[Date==SD, Ticker]
  fw <- fw[Ticker %in% tks]
  facp <- intersect(CUR_DEF, names(fw))
  theta <- setNames(rep(1/length(CUR_DEF), length(CUR_DEF)), CUR_DEF)  # EW over full 3 (not renorm to present)
  score_vec <- rep(0, nrow(fw))
  for(fn in facp){
    cv <- fw[[fn]]; if(all(is.na(cv))) next
    cw <- winsor_z(cv, 2.5)
    score_vec <- score_vec + theta[fn]*cw   # NA in cw -> NA in score (canonical)
  }
  fw[, Score_Defense := score_vec]
  # zc over scope (na.rm)
  m<-mean(fw$Score_Defense,na.rm=T); s<-sd(fw$Score_Defense,na.rm=T)
  fw[, def_z := if(is.na(s)||s<1e-10) Score_Defense-m else (Score_Defense-m)/s]
  merge(ap[Date==SD,.(Ticker,stored=score_defense_z)], fw[,.(Ticker,def_z)], by="Ticker", all.x=TRUE)
}
DTS <- as.Date(c("2008-01-01","2012-06-01","2018-03-01","2022-09-01","2026-05-01","2026-06-01"))
for(ii in seq_along(DTS)){
  d <- DTS[ii]
  r <- recon(d)
  if(is.null(r)){cat(as.character(d),"NULL\n");next}
  md <- max(abs(r$def_z-r$stored),na.rm=T); cc <- suppressWarnings(cor(r$def_z,r$stored,use="complete.obs"))
  n_recon <- sum(!is.na(r$def_z)); n_stored <- sum(!is.na(r$stored))
  cat(sprintf("[%s] maxdiff=%.6f cor=%.5f n_recon=%d n_stored=%d\n", as.character(d), md, cc, n_recon, n_stored))
}
