# arm B redundancy fix: IVOL_K vs existing LowRisk factors (Z_Score_Aligned)
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L),silent=TRUE); setDTthreads(2L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT<-"stage_artifacts/WT_D20260713_005"
source("02_Infrastructure/factor_db/factor_db_connector.R")
ivol<-as.data.table(read_parquet(file.path(OUT,"ivol_panel.parquet")))
sd_all<-sort(unique(ivol$Date)); samp<-sd_all[round(seq(1,length(sd_all),length.out=20))]
targ<-c("D01_IdioVol","R12_Idiosyncratic_Risk","D03_RealVol","D02_Beta","D35_RealVol_63d")
accum<-list()
for(t in samp){
  mf<-tryCatch(as.data.table(load_month_factors(as.Date(t))),error=function(e)NULL)
  if(is.null(mf)||!nrow(mf))next
  zc <- if("Z_Score_Aligned"%in%names(mf))"Z_Score_Aligned" else if("Z_Score"%in%names(mf))"Z_Score" else NA
  iv<-ivol[Date==t,.(Ticker,ivK=ivol_K)]
  if("Factor_Name"%in%names(mf) && !is.na(zc)){
    for(fn in intersect(targ,unique(mf$Factor_Name))){
      sub<-mf[Factor_Name==fn & is.finite(get(zc)),.(Ticker,z=get(zc))]
      m<-merge(iv,sub,by="Ticker"); if(nrow(m)>=20) accum[[paste0(fn,t)]]<-data.table(factor=fn,rho=cor(m$ivK,m$z,method="spearman"),n=nrow(m))
    }
  } else if(!is.na(zc)){
    for(fn in intersect(targ,names(mf))){ m<-merge(iv,mf[is.finite(get(fn)),.(Ticker,z=get(fn))],by="Ticker")
      if(nrow(m)>=20) accum[[paste0(fn,t)]]<-data.table(factor=fn,rho=cor(m$ivK,m$z,method="spearman"),n=nrow(m)) }
  }
}
if(length(accum)){ ac<-rbindlist(accum); red<-ac[,.(mean_rho=round(mean(rho,na.rm=T),3),n_months=.N,mean_n=round(mean(n))),by=factor]
  print(red); writeLines(jsonlite::toJSON(red,auto_unbox=TRUE,pretty=TRUE),file.path(OUT,"armB_redundancy.json"))
} else cat("no redundancy computed\n")
