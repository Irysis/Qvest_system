suppressPackageStartupMessages(library(jsonlite))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB<-"qepm/mailbox/worktask/WT-D20260813_001"
ok<-tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id="WT-D20260813_001",
    package_type="optimization_package",
    method_selected="EW_top25_semicap50",
    input_file_paths=c(file.path(MB,"alpha_package.json"), file.path(MB,"risk_package.json"))
  ); "LINEAGE_OK"
}, error=function(e) paste("LINEAGE_ERR:", conditionMessage(e)))
writeLines(ok, "stage_artifacts/WT-D20260813_001/lineage_result.txt")
