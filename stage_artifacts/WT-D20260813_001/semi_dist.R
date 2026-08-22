suppressPackageStartupMessages({library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sched<-fread("stage_artifacts/WT-D20260813_001/weights.csv")
ss<-sched[,.(semi=sum(weight[sector=="반도체"])),by=as_of_date]
o<-c(paste("semi share: mean",round(mean(ss$semi),3),"median",round(median(ss$semi),3),
  "max",round(max(ss$semi),3),"p90",round(as.numeric(quantile(ss$semi,0.9)),3),
  "n_dates_capped",sum(ss$semi>0.4999)))
writeLines(o,"stage_artifacts/WT-D20260813_001/semi_dist.txt")
