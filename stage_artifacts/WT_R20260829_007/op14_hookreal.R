suppressWarnings(suppressMessages(library(jsonlite)))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
f <- "qepm/mailbox/worktask/WT-R20260829_007/optimization_package.json"
ct <- paste(readLines(f, warn=FALSE), collapse="\n")
writeLines(toJSON(list(hook_event_name="PreToolUse", tool_name="Write",
  tool_input=list(file_path=f, content=ct)), auto_unbox=TRUE),
  "stage_artifacts/WT_R20260829_007/_hookprobe_REAL.json")
