library(jsonlite)
d <- fromJSON("06_Registry/reinforce_ledger_l1.json", simplifyVector=FALSE)
e <- d$entries[[1]]
cat("strategy:", e$strategy_id %||% "NA", "\n")
for (a in e$attempts) {
  cat("n=", a$n, "| status=", paste(a$status,collapse=","), "|", substr(paste(a$idea,collapse=" "),1,200), "\n")
}
