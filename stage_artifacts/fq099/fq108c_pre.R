suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[108c] ",fmt,"\n"),...))
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
e <- Filter(function(x) isTRUE(identical(x$id,"FQ-108c")), q$entries)
if (!length(e)) { say("FQ-108c 미발견"); quit(status=0) }
e <- e[[1]]
for (k in c("id","status","data_gate","wall_check","owner","ev_rationale")) {
  v <- e[[k]]; if (!is.null(v)) say("%-14s : %s", k, substr(paste(unlist(v),collapse=" "),1,300))
}
say("--- 선행 FQ-108 산출물 존재 확인 ---")
for (p in c("stage_artifacts/l_code/method_frontier/l_code_FQ108_TAILVOL_RISK_AXIS.json",
            "stage_artifacts/WT_D20260802_001")) say("  %-70s %s", p, file.exists(p))
