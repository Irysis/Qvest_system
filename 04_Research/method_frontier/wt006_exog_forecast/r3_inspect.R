# r3_inspect.R — inspect .FAM structure for captier_stock lane
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")

cat("\n=== .FAM cols ===\n"); print(names(.FAM))
cat("\n=== .FAM head ===\n"); print(head(.FAM,3))
cat("\n=== dims ===\n"); print(dim(.FAM))
cat("\n=== membership summary ===\n")
print(.FAM[, .(.N, K200_sum=sum(K200,na.rm=TRUE), KQ150_sum=sum(KQ150,na.rm=TRUE),
               K200_class=class(K200)[1])])
cat("\n=== per-month tier counts (sample) ===\n")
mc <- .FAM[Date %in% .oos_dates, .(n=.N, nK200=sum(K200==1,na.rm=TRUE), nKQ=sum(KQ150==1,na.rm=TRUE),
        both=sum(K200==1 & KQ150==1,na.rm=TRUE), neither=sum((K200!=1|is.na(K200))&(KQ150!=1|is.na(KQ150)))), by=Date]
print(head(mc,4)); print(tail(mc,4))
cat("\n=== Size distribution ===\n")
print(.FAM[Date==max(.oos_dates), quantile(Size, c(0,.25,.5,.75,1), na.rm=TRUE)])
cat("\n=== NA counts in factor z per col ===\n")
print(.FAM[Date %in% .oos_dates, sapply(.SD, function(x) mean(is.na(x))), .SDcols=.fams])
cat("\n=== .Rg cols ===\n"); print(names(.Rg)); print(head(.Rg,2))
cat("\n=== oos range ===\n"); print(range(.oos_dates)); print(length(.oos_dates))
cat("\n=== baseline mom port_t ===\n"); print(.BASELINE_MOM_PORT_T)
cat("\n[inspect] done\n")
