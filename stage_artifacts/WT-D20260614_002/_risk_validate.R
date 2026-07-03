suppressMessages({library(arrow);library(data.table);library(jsonlite)})
cv<-as.data.table(read_parquet("stage_artifacts/WT-D20260614_002/covariance.parquet"))
M<-as.matrix(cv[,-1]); ev<-eigen(M,symmetric=TRUE,only.values=TRUE)$values
cat("Sigma: dim",dim(M)[1],"x",dim(M)[2]," min_eig",signif(min(ev),3)," cond",round(max(ev)/min(ev[ev>0]),2),
    " PSD",min(ev)>-1e-10," symmetric",isTRUE(all.equal(M,t(M))),"\n")
pk<-fromJSON("qepm/mailbox/worktask/WT-D20260614_002/risk_package.json")
cat("JSON parse OK. top-level keys:",length(names(pk)),"\n")
cat("flags:",length(pk$challenge_flags)," | stress_audit.stress_8_pass:",pk$risk_summary$stress_audit$stress_8_pass,"\n")
cat("market_factor_included:",pk$sigma_structure$market_factor_included," omega_estimator:",pk$sigma_structure$omega_estimator,"\n")
