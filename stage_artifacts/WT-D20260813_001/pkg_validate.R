suppressPackageStartupMessages(library(jsonlite))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
p<-fromJSON("qepm/mailbox/worktask/WT-D20260813_001/optimization_package.json")
tw<-unlist(p$target_weights)
o<-c(paste("n:",length(tw)," sum:",round(sum(tw),6)," max:",round(max(tw),4)," min:",round(min(tw),4)),
paste("method:",p$method_selected," sel_obj:",p$selection_objective),
paste("tier:",p$tier," metric_type:",p$metric_type),
paste("density:",p$optimization_diagnostics$schedule_density_ratio," prod_grade:",p$selected_series_walkforward$production_grade),
paste("infeasibility:",is.null(p$infeasibility_report)))
writeLines(o,"stage_artifacts/WT-D20260813_001/pkg_validate.txt")
