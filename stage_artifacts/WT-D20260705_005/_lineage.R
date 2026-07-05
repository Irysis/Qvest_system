source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260705_005",
  package_type = "alpha_package",
  method_selected = "11 orthogonal economic sleeve individual canonical_screen_bt (cap-w PORT_t authoritative)",
  input_file_paths = c(
    "outputs/ramp/factor_group_scores.parquet",
    "stage_artifacts/WT-D20260705_005/rawdata_monthend_slim.parquet"
  )
)
