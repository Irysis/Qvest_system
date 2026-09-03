suppressWarnings(suppressMessages(library(jsonlite)))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT<-getwd(); setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
fs <- list.files(OUT, pattern="^rk[0-9]+_", full.names=TRUE)
fs <- fs[grepl("[.]R$", fs)]
for(f in fs){ r <- tryCatch(detect_lookahead(f, verbose=FALSE), error=function(e) list(error=conditionMessage(e)))
  n <- if(!is.null(r$violations)) length(r$violations) else NA
  cat(sprintf("%-28s violations=%s passed=%s\n", basename(f), n, if(!is.null(r$passed)) r$passed else NA))
  if(!is.null(r$violations) && length(r$violations)>0) for(v in r$violations) cat("   -", paste(unlist(v),collapse=" | "), "\n") }
