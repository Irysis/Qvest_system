suppressPackageStartupMessages(library(data.table))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/contracts/essence_score.R"))
bt <- readRDS(file.path(root, "stage_artifacts/WT-D20260813_001/bt_result.rds"))
res <- essence_score(bt,
                     n_trials_cumulative = 1,
                     selection_type = "chain",
                     oos_is_ratio_override = -0.855)
out <- c(
  paste("GRADE:", res$grade),
  paste("metric_type:", res$metric_type),
  paste("hard_fail:", res$hard_fail),
  "== essence ==",
  paste(names(unlist(res$essence)), unlist(res$essence), sep=" = "),
  "== reasons ==",
  paste(res$reasons, collapse=" | ")
)
writeLines(out, file.path(root, "stage_artifacts/WT-D20260813_001/judge_essence_out.txt"))
cat(paste(out, collapse="\n"), "\n")
