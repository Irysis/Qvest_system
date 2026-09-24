suppressPackageStartupMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
m4 <- as.data.table(read_parquet(file.path(R,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"), mmap=FALSE))
cat(names(m4), "\n"); print(tail(m4[, intersect(names(m4), c("Date","YM","Regime_Score","Regime_Score_lag","weight_str1715","FRED_MRS")), with=FALSE], 5))
u <- as.data.table(read_parquet("C:/qm_cache/unified_regime_signal.parquet", mmap=FALSE)); u[, Date:=as.Date(Date)]
print(tail(u[, .(Date, Regime_Score, FRED_MRS)], 4))
