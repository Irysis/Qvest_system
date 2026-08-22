suppressPackageStartupMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
s <- readRDS("stage_artifacts/WT-D20260813_001/walkforward_series.rds")
ew <- s[["EW"]]; ti <- s[["ScoreTilt"]]; iv <- s[["InvVol"]]
mid <- ew$date[floor(nrow(ew)/2)]
sr <- function(px) as.numeric(SharpeRatio.annualized(xts(px$net, order.by=px$date), Rf=0, scale=12, geometric=FALSE))
out <- c(
 sprintf("EW    full %.4f IS %.4f OOS %.4f", sr(ew), sr(ew[date<=mid]), sr(ew[date>mid])),
 sprintf("Tilt  full %.4f IS %.4f OOS %.4f", sr(ti), sr(ti[date<=mid]), sr(ti[date>mid])),
 sprintf("InvV  full %.4f IS %.4f OOS %.4f", sr(iv), sr(iv[date<=mid]), sr(iv[date>mid])),
 sprintf("Tilt-EW delta  full %.4f IS %.4f OOS %.4f",
   sr(ti)-sr(ew), sr(ti[date<=mid])-sr(ew[date<=mid]), sr(ti[date>mid])-sr(ew[date>mid])),
 sprintf("InvV-EW delta  full %.4f IS %.4f OOS %.4f",
   sr(iv)-sr(ew), sr(iv[date<=mid])-sr(ew[date<=mid]), sr(iv[date>mid])-sr(ew[date>mid])),
 sprintf("split_date %s  n_IS %d n_OOS %d", as.character(mid), nrow(ew[date<=mid]), nrow(ew[date>mid]))
)
writeLines(out, "stage_artifacts/WT-D20260813_001/oos_check.txt")
