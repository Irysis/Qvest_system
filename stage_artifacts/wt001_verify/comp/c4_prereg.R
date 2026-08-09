suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
nn <- function(a,b) if (is.null(a)) b else a
h <- fromJSON("qepm/mailbox/worktask/WT-D20260808_001/alpha_hypothesis.json", simplifyVector=FALSE)
cat("HYP top keys:", paste(names(h), collapse=", "), "\n")
cat("HYP verdict:", nn(h$verdict, "NA"), "\n")
hp <- nn(h$hypothesis, h)
cat("HYP hypothesis keys:", paste(names(hp), collapse=", "), "\n")
fl <- nn(hp$falsification, list())
cat("HYP n_falsification:", length(fl), "\n")
for (i in seq_along(fl)) {
  x <- fl[[i]]; cat("---- F", i, "\n", sep="")
  for (nm in names(x)) cat("  ", nm, " = ", substr(paste(unlist(x[[nm]]), collapse=" | "), 1, 420), "\n", sep="")
}
p <- fromJSON("qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json", simplifyVector=FALSE)
pf <- p$hypothesis$falsification
cat("\nPKG n_falsification:", length(pf), "\n")
for (i in seq_along(pf)) {
  x <- pf[[i]]
  cat("---- P", i, " keys=", paste(names(x), collapse=","), "\n", sep="")
  cat("  has_실측_in_expectation: ",
      grepl("[실측", x$expectation, fixed = TRUE), "\n", sep="")
}
# 사전등록 파일과 대조
pr <- fromJSON("stage_artifacts/WT_D20260808_001/preregistration.json", simplifyVector=FALSE)
cat("\nPREREG top keys:", paste(names(pr), collapse=", "), "\n")
cat("PREREG created/ts fields: ",
    paste(unlist(pr[intersect(names(pr), c("created_at","timestamp","as_of","frozen_at","registered_at"))]),
          collapse=" | "), "\n")
pra <- fromJSON("stage_artifacts/WT_D20260808_001/preregistration_addendum.json", simplifyVector=FALSE)
cat("PREREG_ADDENDUM keys:", paste(names(pra), collapse=", "), "\n")
