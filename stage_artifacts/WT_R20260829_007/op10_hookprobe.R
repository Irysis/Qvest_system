suppressWarnings(suppressMessages({library(jsonlite); library(data.table)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
W <- fread(file.path(OUT,"weights.csv")); w <- W[as_of_date==max(as_of_date)]
base <- setNames(as.list(w$weight), w$Ticker)
mk <- function(tw) toJSON(list(hook_event_name="PreToolUse", tool_name="Write",
  tool_input=list(file_path="qepm/mailbox/worktask/WT-R20260829_007/optimization_package.json",
                  content=toJSON(list(task_id="WT-R20260829_007", target_weights=tw), auto_unbox=TRUE))),
  auto_unbox=TRUE)
cases <- list(
  CLEAN_25 = base,
  VIOL_n26 = c(base, setNames(list(0.0), "ZZZTEST")),                 # 26종
  VIOL_neg = { b<-base; b[[1]] <- -0.04; b[[2]] <- 0.12; b },          # w<0
  VIOL_sum = { b<-base; b[[1]] <- 0.30; b }                           # Sw != 1
)
for(nm in names(cases)){
  tw <- cases[[nm]]
  f <- file.path(OUT, paste0("_hookprobe_", nm, ".json")); writeLines(mk(tw), f)
  cat(sprintf("%-10s n=%d Sw=%.4f minw=%+.4f\n", nm, length(tw), sum(unlist(tw)), min(unlist(tw))))
}
