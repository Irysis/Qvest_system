suppressMessages({library(data.table);library(arrow)})
setDTthreads(1)
W5<-"04_Research/method_frontier/wt005_factor_timing"
FAM<-as.data.table(read_parquet(file.path(W5,"family_z_panel.parquet")))
cat("FAM cols:",paste(names(FAM),collapse=","),"\n")
cat("FAM dates:",uniqueN(FAM$Date)," range",as.character(min(FAM$Date)),as.character(max(FAM$Date)),"\n")
oos<-sort(unique(as.Date(read_parquet(file.path(W5,"theta_transformer_ensemble.parquet"))$date)))
cat("OOS n:",length(oos)," range",as.character(min(oos)),as.character(max(oos)),"\n")
cat("low_vol NA frac:",round(mean(is.na(FAM$low_vol)),3),"\n")
