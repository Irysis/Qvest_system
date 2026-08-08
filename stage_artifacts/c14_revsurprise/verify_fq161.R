suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[161] ",fmt,"\n"),...))
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
e <- Filter(function(x) isTRUE(identical(x$id,"FQ-161")), q$entries)
if (!length(e)) { say("★FQ-161 미발견 — 내가 옮긴 수치의 출처가 없다"); quit(status=0) }
e <- e[[1]]
for (k in names(e)) say("%-24s: %s", k, substr(paste(unlist(e[[k]]),collapse=" | "),1,420))
say("=== 산출물 실재 확인 ===")
for (p in c("qepm/mailbox/worktask/WT-D20260808_002",
            "qepm/mailbox/worktask/WT-D20260808_002/alpha_package.json",
            "stage_artifacts/WT_D20260808_002")) say("  %-58s %s", p, file.exists(p))
