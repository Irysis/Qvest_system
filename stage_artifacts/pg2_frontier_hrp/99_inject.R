suppressPackageStartupMessages({library(data.table);library(jsonlite)})
OUT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
M<-fread(file.path(OUT,"MASTER_results.csv"))
cols<-c("method","PORT_t","IR_active","SR","Calmar","MDD","TO_annual","active_cor","dIR_blend50","dIR_IRmax","PORT_t_2021","verdict")
M<-M[,..cols]
js<-toJSON(list(rows=M),dataframe="rows",auto_unbox=TRUE,na="null",digits=6)
tmpl<-readLines(file.path(OUT,"frontier_hrp_dossier.html"),warn=FALSE)
tmpl<-gsub("__DATA__",js,tmpl,fixed=TRUE)
writeLines(tmpl,file.path(OUT,"frontier_hrp_dossier.html"))
cat("injected",nrow(M),"rows into artifact\n")
