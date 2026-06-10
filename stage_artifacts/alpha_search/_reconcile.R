suppressPackageStartupMessages({library(arrow);library(data.table);library(PerformanceAnalytics);library(xts)})
b <- as.data.table(read_parquet("G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2/baselines_net_returns.parquet"))
cat("baselines cols:\n"); print(names(b)); cat("dims",dim(b),"\n"); print(head(b,3))
dc <- intersect(c("ym","date","Date","month"), names(b))
if(length(dc)) cat("range",as.character(range(b[[dc[1]]])),"n",length(unique(b[[dc[1]]])),"\n")
# find STR_1715 column
str_cols <- grep("1715|STR", names(b), value=TRUE, ignore.case=TRUE)
cat("STR cols:", str_cols, "\n")
