setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(jsonlite)})
rp <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/risk_package.json", simplifyVector = FALSE)
pr <- function(l,x){cat("\n===",l,"===\n"); cat(toJSON(x,auto_unbox=TRUE,pretty=TRUE,digits=6),"\n")}
cat("top-level fields:\n"); print(names(rp))
for (k in names(rp)) {
  if (grepl("walk|wf|retract|correction|amend|stress|bear|revis", k, ignore.case=TRUE)) pr(k, rp[[k]])
}
if (!is.null(rp$risk_summary)) { cat("\nrisk_summary keys:\n"); print(names(rp$risk_summary)) }
if (!is.null(rp$diagnostics)) { cat("\ndiagnostics keys:\n"); print(names(rp$diagnostics)) }
pr("handoff_to_optimizer", rp$handoff_to_optimizer)
