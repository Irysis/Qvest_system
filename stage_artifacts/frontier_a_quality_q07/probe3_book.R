ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts) })

bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
cat("=== bt_result names ===\n"); print(names(bt))

cat("\n=== period_returns structure ===\n")
pr <- bt$period_returns
cat("class:", paste(class(pr), collapse=","), "\n")
if (is.data.frame(pr)) { print(names(pr)); print(head(pr,3)); print(tail(pr,3)); cat("nrow:", nrow(pr), "\n") }

cat("\n=== benchmark_returns structure ===\n")
br <- bt$benchmark_returns
if (!is.null(br)) { cat("class:", paste(class(br), collapse=","), "\n"); if (is.data.frame(br)) { print(names(br)); print(head(br,3)); cat("nrow:", nrow(br), "\n") } }

cat("\n=== benchmark_compare IR row ===\n")
bc <- bt$benchmark_compare
if (is.data.frame(bc)) {
  print(bc[grepl("Information_Ratio|Alpha|Active|Tracking", bc$metric_name, ignore.case=TRUE), ])
}

# Reconstruct net-active monthly and verify IR = 1.416
cat("\n=== reconstruct net-active IR ===\n")
prd <- as.data.table(pr)
cat("period_returns cols:", paste(names(prd), collapse=" | "), "\n")
print(head(prd,3))
