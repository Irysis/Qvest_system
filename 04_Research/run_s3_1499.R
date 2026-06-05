cat("=== S3: STR_1499 (CR07_Momentum_Crowding) ===\n")
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
LIQ_THRESHOLD <- 2e8
res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
strat_dir <- file.path(PROJECT_ROOT,"04_Research/strategies/STR_1499_momentum_crowding_defense")
source(file.path(strat_dir,"factor_engine.R"))
COMP <- c("CR07_Momentum_Crowding")
ld<-max(FACTORS$Date); ls<-FACTORS[Date==ld,.(Ticker,Score)]
nz<-setNames(ls$Score,ls$Ticker); cat(sprintf("[S3] %s | N=%d\n",ld,length(nz)))
fdt<-load_month_factors(ld,coverage_min=0.01)
fw<-dcast(fdt,Ticker~Factor_Name,value.var="Z_Score_Aligned")
mg<-merge(fw,data.table(Ticker=names(nz),New_Z=as.numeric(nz)),by="Ticker")
fc<-setdiff(names(mg),c("Ticker","New_Z",COMP))
pw<-rbindlist(lapply(fc,function(f){v<-!is.na(mg[[f]])&!is.na(mg$New_Z);if(sum(v)<20)data.table(Factor_Name=f,Corr=NA_real_) else data.table(Factor_Name=f,Corr=cor(mg[[f]][v],mg$New_Z[v],method="spearman"))}))[!is.na(Corr)]
mi<-which.max(abs(pw$Corr));mc<-abs(pw$Corr[mi]);mf<-pw$Factor_Name[mi]
ind<-ifelse(mc<0.3,"independent",ifelse(mc<0.6,"partial","redundant"))
pw[,Category:=gsub("^([A-Z]+)\\d+.*","\\1",Factor_Name)]
cc<-pw[,.(Max_Corr=max(abs(Corr),na.rm=T)),by=Category];setorder(cc,-Max_Corr)
t10<-pw[order(-abs(Corr))][1:min(10,nrow(pw))]
cat(sprintf("[S3] max: %.3f (vs %s) | %s\n",mc,mf,ind))
for(j in 1:min(5,nrow(t10))) cat(sprintf("  %d. %s: %.3f\n",j,t10$Factor_Name[j],t10$Corr[j]))
ad<-sort(unique(FACTORS$Date),decreasing=T);cds<-ad[seq_len(min(3,length(ad)))]
mr<-lapply(cds,function(d){zd<-setNames(FACTORS[Date==d]$Score,FACTORS[Date==d]$Ticker);if(length(zd)<30)return(NULL);fd<-tryCatch(load_month_factors(d,coverage_min=0.01),error=function(e)NULL);if(is.null(fd))return(NULL);md<-merge(dcast(fd,Ticker~Factor_Name,value.var="Z_Score_Aligned"),data.table(Ticker=names(zd),New_Z=as.numeric(zd)),by="Ticker");if(nrow(md)<30)return(NULL);fcd<-setdiff(names(md),c("Ticker","New_Z",COMP));ccd<-sapply(fcd,function(f){v<-!is.na(md[[f]])&!is.na(md$New_Z);if(sum(v)<20)NA_real_ else cor(md[[f]][v],md$New_Z[v],method="spearman")});ccd<-ccd[!is.na(ccd)];if(length(ccd)==0)return(NULL);mx<-which.max(abs(ccd));data.table(Date=d,max_corr=abs(ccd[mx]),max_factor=names(ccd)[mx])})
mdt<-rbindlist(mr[!sapply(mr,is.null)]);ac<-ifelse(nrow(mdt)>0,mean(mdt$max_corr),mc)
s3<-list(factor_id="CR07_MomCrowding",strategy_id="STR_1499",components=as.list(COMP),max_abs_corr_db=round(mc,4),most_correlated_factor=mf,top5_corr=as.list(setNames(round(t10$Corr[1:min(5,nrow(t10))],4),t10$Factor_Name[1:min(5,nrow(t10))])),category_max_corr=as.list(setNames(round(cc$Max_Corr,4),cc$Category)),independence_class=ind,n_compared=nrow(pw),n_months_analyzed=nrow(mdt),avg_max_corr_multidate=round(ac,4),computed_date=as.character(Sys.Date()),scout_note=sprintf("Conditional IC #1 (cond_value 0.114, ic_bad=0.083). max %.3f(vs %s). %s. avg %.3f. N=%d.",mc,mf,ind,ac,length(nz)))
jsonlite::write_json(s3,file.path(strat_dir,"stage_artifacts","s3_orthogonality_CR07_MomCrowding.json"),auto_unbox=T,pretty=T)
cat(sprintf("\n[Scout] S3 done: %.3f vs %s | %s\n",mc,mf,ind))
