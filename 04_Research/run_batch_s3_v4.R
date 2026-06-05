## Batch S3: STR_1487, STR_1489, STR_1490
cat("=== Batch S3: D51, L13, L16 ===\n")

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
LIQ_THRESHOLD <- 2e8

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

run_s3 <- function(strat_id, factor_id, component_factors) {
  cat(sprintf("\n======== S3: %s (%s) ========\n", strat_id, factor_id))
  strat_dir <- file.path(PROJECT_ROOT, "04_Research/strategies", strat_id)
  source(file.path(strat_dir, "factor_engine.R"))
  latest_date <- max(FACTORS$Date)
  latest_scores <- FACTORS[Date == latest_date, .(Ticker, Score)]
  new_z <- setNames(latest_scores$Score, latest_scores$Ticker)
  cat(sprintf("[S3] Latest: %s | N: %d\n", latest_date, length(new_z)))

  fdt <- load_month_factors(latest_date, coverage_min = 0.01)
  fw <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  merged <- merge(fw, data.table(Ticker=names(new_z), New_Z=as.numeric(new_z)), by="Ticker")
  fc <- setdiff(names(merged), c("Ticker","New_Z", component_factors))
  cat(sprintf("[S3] Excl: %s | Cmp: %d\n", paste(component_factors,collapse=","), length(fc)))

  pw <- rbindlist(lapply(fc, function(f) {
    v <- !is.na(merged[[f]])&!is.na(merged$New_Z)
    if(sum(v)<20) data.table(Factor_Name=f,Corr=NA_real_) else data.table(Factor_Name=f,Corr=cor(merged[[f]][v],merged$New_Z[v],method="spearman"))
  }))[!is.na(Corr)]
  mi <- which.max(abs(pw$Corr)); mc <- abs(pw$Corr[mi]); mf <- pw$Factor_Name[mi]
  ind <- ifelse(mc<0.3,"independent",ifelse(mc<0.6,"partial","redundant"))
  pw[, Category := gsub("^([A-Z]+)\\d+.*","\\1",Factor_Name)]
  cc <- pw[, .(Max_Corr=max(abs(Corr),na.rm=T)), by=Category]; setorder(cc,-Max_Corr)
  t10 <- pw[order(-abs(Corr))][1:min(10,nrow(pw))]

  cat(sprintf("[S3] max: %.3f (vs %s) | %s\n", mc, mf, ind))
  for(j in 1:min(5,nrow(t10))) cat(sprintf("  %d. %s: %.3f\n",j,t10$Factor_Name[j],t10$Corr[j]))

  # Multi-date
  ad <- sort(unique(FACTORS$Date),decreasing=T); cd <- ad[seq_len(min(3,length(ad)))]
  mr <- lapply(cd, function(d){
    zd <- setNames(FACTORS[Date==d]$Score,FACTORS[Date==d]$Ticker); if(length(zd)<30) return(NULL)
    fd <- tryCatch(load_month_factors(d,coverage_min=0.01),error=function(e)NULL); if(is.null(fd)) return(NULL)
    md <- merge(dcast(fd,Ticker~Factor_Name,value.var="Z_Score_Aligned"),data.table(Ticker=names(zd),New_Z=as.numeric(zd)),by="Ticker")
    if(nrow(md)<30) return(NULL)
    fcd <- setdiff(names(md),c("Ticker","New_Z",component_factors))
    ccd <- sapply(fcd,function(f){v<-!is.na(md[[f]])&!is.na(md$New_Z);if(sum(v)<20)NA_real_ else cor(md[[f]][v],md$New_Z[v],method="spearman")})
    ccd <- ccd[!is.na(ccd)]; if(length(ccd)==0) return(NULL)
    mx<-which.max(abs(ccd)); data.table(Date=d,max_corr=abs(ccd[mx]),max_factor=names(ccd)[mx])
  })
  mdt <- rbindlist(mr[!sapply(mr,is.null)]); ac <- ifelse(nrow(mdt)>0,mean(mdt$max_corr),mc)

  s3 <- list(factor_id=factor_id,strategy_id=strat_id,components=as.list(component_factors),
    max_abs_corr_db=round(mc,4),most_correlated_factor=mf,
    top5_corr=as.list(setNames(round(t10$Corr[1:min(5,nrow(t10))],4),t10$Factor_Name[1:min(5,nrow(t10))])),
    category_max_corr=as.list(setNames(round(cc$Max_Corr,4),cc$Category)),
    independence_class=ind,n_compared=nrow(pw),n_months_analyzed=nrow(mdt),
    avg_max_corr_multidate=round(ac,4),computed_date=as.character(Sys.Date()),
    scout_note=sprintf("max %.3f(vs %s). %s. avg %.3f. N=%d.",mc,mf,ind,ac,length(new_z)))
  art_dir <- file.path(strat_dir,"stage_artifacts")
  jsonlite::write_json(s3,file.path(art_dir,sprintf("s3_orthogonality_%s.json",factor_id)),auto_unbox=T,pretty=T)
  cat("[S3] Saved.\n")
  list(strat_id=strat_id,factor_id=factor_id,max_corr=mc,max_factor=mf,independence=ind)
}

r1 <- run_s3("STR_1487_ulcer_index","D51_UlcerIndex","D51_Ulcer_Index")
r2 <- run_s3("STR_1489_vol_variance_ratio","L13_VolVarianceRatio","L13_Vol_Variance_Ratio")
r3 <- run_s3("STR_1490_turnover_vol","L16_TurnoverVol","L16_Turnover_Vol")

cat("\n===== SUMMARY =====\n")
for(r in list(r1,r2,r3)) if(!is.null(r)) cat(sprintf("  %s | %.3f vs %s | %s\n",r$strat_id,r$max_corr,r$max_factor,r$independence))
