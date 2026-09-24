suppressPackageStartupMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
car <- as.data.table(read_parquet(file.path(R,".cache/pins/WT-D20260718_007_r1/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"), mmap=FALSE))
print(tail(unique(car[, .(decision_date, eval_date, regime)]), 6))
car2 <- as.data.table(read_parquet(file.path(R,"06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"), mmap=FALSE))
cat(names(car2), "\n"); print(tail(unique(car2[, intersect(names(car2), c("decision_date","eval_date","regime","gate","ae_fire")), with=FALSE]), 6))
