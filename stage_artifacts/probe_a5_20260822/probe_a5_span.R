suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)]
R[,ym:=format(Date,"%Y-%m")];mon<-R[,.(medate=max(Date)),by=ym];setorder(mon,medate)
cat(sprintf("total months=%d  first=%s last=%s\n",nrow(mon),mon$ym[1],mon$ym[nrow(mon)]))
cat(sprintf("applied window (idx13..N): %s .. %s  n=%d\n",mon$ym[13],mon$ym[nrow(mon)],nrow(mon)-12))
cat(sprintf("medate[13]=%s  medate[N]=%s\n",as.character(mon$medate[13]),as.character(mon$medate[nrow(mon)])))
