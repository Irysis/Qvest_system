suppressMessages({library(arrow);library(data.table)})
WD<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
f<-file.path(WD,"stage_artifacts/WT-D20260705_005/rawdata_monthend_slim.parquet")
sink(file.path(WD,"stage_artifacts/pg2_overlay_gate_composition_20260705/diag_raw.txt"))
d<-as.data.table(read_parquet(f))
cat("slim cols:",paste(names(d),collapse=" | "),"\n"); cat("nrow:",nrow(d)," date range:",as.character(min(d[[1]])),"..",as.character(max(d[[1]])),"\n")
cat("head:\n"); print(head(d,3))
# top-2 by size (Size col?) across full universe per month
sz<-grep("size|Size|cap|Cap|Vol|시총",names(d),value=TRUE); cat("size-like cols:",paste(sz,collapse=","),"\n")
sink(); cat("done\n")
