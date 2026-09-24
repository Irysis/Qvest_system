suppressPackageStartupMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
ae <- as.data.table(read_parquet(file.path(R,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"), mmap=FALSE))
cat(names(ae), "\n"); ae[, dd:=as.Date(decision_date)]; ae[, lf:=as.Date(last_feat_date)]
print(tail(ae[, .(dd, lf, fire_seq)], 6)); print(head(ae[, .(dd, lf, fire_seq)], 3))
cat("rows", nrow(ae), "fires", sum(ae$fire_seq), "\n"); print(table(as.integer(ae$dd - ae$lf)))
print(table(as.integer(format(ae$dd, "%d"))))
print(list.files(file.path(R,".cache/pins/WT-D20260718_007_r1")))
car <- as.data.table(read_parquet(file.path(R,".cache/pins/WT-D20260718_007_r1/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"), mmap=FALSE))
cat(names(car), "\n"); print(tail(unique(car[, intersect(names(car), c("decision_date","return_ym","holding_ym","sig_date","exec_date","realized_ym")), with=FALSE]), 5))
