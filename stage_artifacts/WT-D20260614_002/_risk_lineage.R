source("02_Infrastructure/config.R")
ok <- tryCatch({ source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id="WT-D20260614_002", package_type="risk_package",
    method_selected="ledoit_wolf_rmt_market_factor",
    input_file_paths=c("qepm/mailbox/worktask/WT-D20260614_002/alpha_package.json",
                       "stage_artifacts/WT-D20260614_002/_factor_return_panel.parquet"),
    windows=list(list(start="2005-01",end="2026-04"))); TRUE
}, error=function(e){cat("[lineage] note:",conditionMessage(e),"\n"); FALSE})
cat("[lineage] recorded:",ok,"\n")
