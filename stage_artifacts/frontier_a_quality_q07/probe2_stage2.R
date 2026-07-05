ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts); library(arrow) })

bk <- readRDS("04_Research/pg2_forensics/intermediate/variant_returns_xts.rds")
cat("=== R_gross full colnames ===\n"); print(colnames(bk$R_gross))
cat("\n=== R_net full colnames ===\n"); print(colnames(bk$R_net))
cat("\n=== R_gross index (monthly? end-of-month?) head/tail ===\n")
print(head(index(bk$R_gross), 6)); print(tail(index(bk$R_gross), 6))
cat("\n=== sample R_gross first 3 rows (all cols) ===\n")
print(head(bk$R_gross, 3))

# check the qual_q07 full sleeve (the actual sleeve, 258m?) vs qual_caution (13m)
cat("\n=== qual_q07_active.rds (full sleeve) ===\n")
q07 <- readRDS("stage_artifacts/frontier_a_quality_q07/qual_q07_active.rds")
cat("class:", paste(class(q07), collapse=","), " nrow:", NROW(q07), "\n")
if (is.data.frame(q07)) { print(head(q07,3)); print(tail(q07,3)) }

cat("\n=== stage1_summary.csv ===\n")
print(fread("stage_artifacts/frontier_a_quality_q07/stage1_summary.csv"))

cat("\n=== qual_q07_result.json ===\n")
cat(paste(readLines("stage_artifacts/frontier_a_quality_q07/qual_q07_result.json"), collapse="\n"), "\n")
