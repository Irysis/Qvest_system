suppressMessages({library(arrow);library(data.table);library(jsonlite)})
cv<-as.data.table(read_parquet("stage_artifacts/WT-D20260614_002/covariance.parquet"))
M<-as.matrix(cv[,-1]); cat("max asym:",max(abs(M-t(M))),"\n")  # should be ~0
pk<-fromJSON("qepm/mailbox/worktask/WT-D20260614_002/risk_package.json",simplifyVector=FALSE)
cat("challenge_flags n:",length(pk$challenge_flags),"\n")
for(f in pk$challenge_flags) cat("  ",f$id,"(",f$severity,")\n")
