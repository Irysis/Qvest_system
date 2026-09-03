setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(jsonlite); library(arrow); library(data.table)})
pr <- function(lbl, x) { cat("\n=== ", lbl, " ===\n"); cat(toJSON(x, auto_unbox=TRUE, pretty=TRUE, digits=6), "\n") }

rp <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/risk_package.json", simplifyVector = FALSE)
pr("handoff_to_optimizer", rp$handoff_to_optimizer)
pr("tail_risk.json", fromJSON("stage_artifacts/WT_R20260829_005/tail_risk.json", simplifyVector=FALSE))
pr("covariance_contract.estimation_window", rp$covariance_contract$estimation_window)
pr("risk_summary.variance_decomposition_pct", rp$risk_summary$variance_decomposition_pct)
pr("risk_summary.concentration", rp$risk_summary$concentration)
pr("risk_summary.liquidity", rp$risk_summary$liquidity)
pr("risk_summary.measured_beta", rp$risk_summary$measured_beta_vs_kospi200)
pr("red_flags", rp$red_flags)

a <- read_parquet("stage_artifacts/WT_R20260829_005/alpha_scores.parquet")
setDT(a)
cat("\n=== alpha_scores.parquet ===\n"); print(dim(a)); print(names(a)); print(head(a,3))
cat("n unique dates:", length(unique(a[[1]])), "\n")
cat("date range:", as.character(min(a[[1]])), as.character(max(a[[1]])), "\n")

cv <- read_parquet("stage_artifacts/WT_R20260829_005/covariance.parquet")
cat("\n=== covariance.parquet ===\n"); print(dim(cv)); cat(names(cv)[1:5], "...\n")

pn <- fread("stage_artifacts/WT_R20260829_005/period_returns_production.csv")
cat("\n=== period_returns_production.csv ===\n"); print(dim(pn)); print(names(pn)); print(head(pn,3))
