suppressPackageStartupMessages({library(data.table)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd)
d <- frd[is.finite(Ret_1m), .(n=.N, sd_r=sd(Ret_1m), mean_r=mean(Ret_1m)), by=Date][order(Date)]
cat("상수-수익 월:\n"); print(d[sd_r == 0])
cat("\n마지막 3개월:\n"); print(tail(d,3))
