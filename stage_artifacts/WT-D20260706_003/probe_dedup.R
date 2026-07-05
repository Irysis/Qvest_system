suppressPackageStartupMessages({ source("02_Infrastructure/tools/hypothesis_index.R") })
r <- tryCatch(lookup_hypothesis(c("공매도","short interest","대차잔고","short balance","lending")), error=function(e){cat("err:",conditionMessage(e),"\n");NULL})
if(!is.null(r)){ cat("n matches:", if(is.data.frame(r)) nrow(r) else length(r), "\n"); print(utils::head(r, 10)) }
