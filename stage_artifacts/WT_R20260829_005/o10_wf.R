setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(jsonlite)})
rp <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/risk_package.json", simplifyVector = FALSE)
pr <- function(l,x){cat("\n===",l,"===\n"); cat(toJSON(x,auto_unbox=TRUE,pretty=TRUE,digits=6),"\n")}
pr("risk_summary.walk_forward_validation", rp$risk_summary$walk_forward_validation)
pr("risk_summary.stress_tests", rp$risk_summary$stress_tests)
pr("risk_summary.stress_test_detail", rp$risk_summary$stress_test_detail)
