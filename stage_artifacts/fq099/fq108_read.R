suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[108] ",fmt,"\n"),...))
p <- "stage_artifacts/l_code/method_frontier/l_code_FQ108_TAILVOL_RISK_AXIS.json"
j <- fromJSON(p, simplifyVector=FALSE)
for (k in c("l_code","strategy_id","grade","core_reference","metric_type")) if(!is.null(j[[k]])) say("%-16s: %s", k, substr(paste(unlist(j[[k]]),collapse=" "),1,220))
say("--- lesson_text ---")
cat(j$lesson_text, "\n")
