suppressPackageStartupMessages({library(arrow);library(data.table)})
R<-as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns_202608.parquet")); R<-R[is.finite(Market)]
for(f in c("Value","Size","Momentum","Quality","LowVol","Growth")) cat(sprintf("%s NA=%.3f%% ",f,100*mean(!is.finite(R[[f]]))))
cat("
rows:",nrow(R)," range:",as.character(range(as.Date(R$Date))),"
")
