Sys.setenv(ARROW_IO_THREADS="2")
suppressWarnings(suppressMessages({library(data.table)}))
setDTthreads(1)
bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
cat("=== names(bt) ===\n"); print(names(bt))
cat("\n=== class period_returns ===\n"); print(class(bt$period_returns)); 
pr <- bt$period_returns
cat("names period_returns:\n"); print(names(pr))
cat("dim:", dim(pr), "\n")
cat("head:\n"); print(utils::head(as.data.frame(pr), 3))
cat("tail:\n"); print(utils::tail(as.data.frame(pr), 6))
cat("\n=== benchmark_returns ===\n"); print(class(bt$benchmark_returns)); print(utils::head(bt$benchmark_returns,3)); print(utils::tail(bt$benchmark_returns,3))
cat("\n=== holdings names ===\n"); print(names(bt$holdings)); 
if(!is.null(bt$holdings)){h<-as.data.frame(bt$holdings); cat("holdings dim:",dim(h),"\n"); print(utils::head(h,3))}
cat("\n=== manifest ===\n"); print(bt$manifest)
