setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressWarnings(suppressMessages({library(arrow);library(data.table)}))
sink("stage_artifacts/WT-D20260813_001/final_check.txt")
# 1. covariance PSD re-check from disk
cv <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_001/covariance.parquet"))
tk <- cv$Ticker; M <- as.matrix(cv[, ..tk]); rownames(M)<-tk
M <- (M+t(M))/2
ev <- eigen(M, symmetric=TRUE, only.values=TRUE)$values
cat(sprintf("covariance.parquet: %dx%d  min_eig=%.6f  cond=%.1f  PSD=%s\n",
            nrow(M),ncol(M),min(ev),max(ev)/max(min(ev),1e-12), min(ev) > -1e-8))
# 2. regime parquet
rc <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_001/regime_correlation.parquet"))
cat("regime_correlation.parquet rows:", nrow(rc), "\n"); print(rc)
# 3. artifacts exist
for (f in c("qepm/mailbox/worktask/WT-D20260813_001/risk_package.json",
            "qepm/mailbox/worktask/WT-D20260813_001/challenge_note.md",
            "qepm/mailbox/worktask/WT-D20260813_001/artifact_lineage.json",
            "stage_artifacts/WT-D20260813_001/covariance.parquet",
            "stage_artifacts/WT-D20260813_001/regime_correlation.parquet"))
  cat(sprintf("%-70s %s\n", f, file.exists(f)))
# 4. risk_package required fields present
p <- jsonlite::fromJSON("qepm/mailbox/worktask/WT-D20260813_001/risk_package.json")
req <- c("task_id","as_of_date","agent","risk_summary","diagnostics","challenge_flags","metric_type",
         "selection_objective","method_shopping_log","security_covariance_ref")
cat("\nrequired fields:\n")
for(k in req) cat(sprintf("  %-25s %s\n", k, k %in% names(p)))
cat("\nrisk_summary keys:", paste(names(p$risk_summary),collapse=", "), "\n")
cat("selection_objective:", p$selection_objective, "\n")
cat("metric_type:", p$metric_type, "\n")
sink()
