library(jsonlite)
p <- "qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"
if (!file.exists(p)) p <- "stage_artifacts/WT_R20260829_007/alpha_package_divguard_probe.json"
d <- fromJSON(p, simplifyVector=FALSE)
cat("FILE:", p, "\n")
cat(paste(names(d), collapse="\n"), "\n")
cat("--- diagnostics keys ---\n"); cat(paste(names(d$diagnostics), collapse=", "), "\n")
cat("--- factors[1] ---\n"); print(names(d$factors[[1]]))
cat("--- verdict:", d$verdict, "| spec:", d$spec_version, "\n")
cat("--- self_pit_check names:", paste(names(d$self_pit_check),collapse=","), "\n")
cat("--- combination_rule:", d$combination_rule, "\n")
