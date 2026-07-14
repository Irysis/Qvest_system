for (f in c("02_Infrastructure/data/rawdata_sanitize.R",
            "02_Infrastructure/contracts/canonical_screen_bt.R",
            "02_Infrastructure/ramp/factor_validation.R")) {
  ok <- tryCatch({parse(file=f); "PARSE OK"}, error=function(e) paste("PARSE ERR:", conditionMessage(e)))
  cat(sprintf("%-30s %s\n", basename(f), ok))
}
cl <- jsonlite::fromJSON(".cache/last_round_closure.json")
cat("closure: round=", cl$round_id, "| type=", cl$verdict_type, "| n_probes=", length(cl$next_probes), "\n")
