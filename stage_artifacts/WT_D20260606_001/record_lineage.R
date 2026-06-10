setwd("G:/Quant_Module_Moltbot")
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260606_001",
  package_type = "optimization_package",
  method_selected = "STATIC_MULTISLEEVE_EW_a0.15 (overlay OFF; net_ir)",
  input_file_paths = c(
    "qepm/mailbox/worktask/WT-D20260606_001/alpha_package.json",
    "qepm/mailbox/worktask/WT-D20260606_001/risk_package.json"
  ),
  windows = list(list(name="book_overlap_months", n=267), list(name="weights_schedule_dates", n=269)),
  random_seed = 606L,
  extra = list(
    selection_objective = "net_ir",
    book_dIR_EW_a0.15 = 0.049,
    book_sr = 1.701,
    overlay_verdict = "REJECTED (no SR lift; thesis refuted)",
    codex_stance = "REVISE",
    recommendation = "DPL_transition"
  )
)
cat("[lineage recorded]\n")
