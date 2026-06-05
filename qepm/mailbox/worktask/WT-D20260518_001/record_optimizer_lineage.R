#!/usr/bin/env Rscript
# record_optimizer_lineage.R
# Optimizer Agent v1.1 — WT-D20260518_001
# v6.1 R11 Lineage 직접 호출
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260518_001",
  package_type = "optimization_package",
  method_selected = "M05_Sequential_Layer6_Quantile_Hard3step_Hysteresis_5pct",
  input_file_paths = c(
    "qepm/mailbox/worktask/WT-D20260518_001/alpha_package.json",
    "qepm/mailbox/worktask/WT-D20260518_001/risk_package.json",
    "qepm/mailbox/worktask/WT-D20260518_001/request.json",
    "stage_artifacts/WT_D20260518_001/W3_OOS_explicit_check.json",
    "stage_artifacts/WT_D20260518_001/crowding_overlap_with_PG2_STR_1715.json",
    "stage_artifacts/WT_D20260518_001/tail_risk_evt_gpd.json",
    "stage_artifacts/WT_D20260518_001/covariance.parquet",
    "stage_artifacts/WT_D20260518_001/feature_panel_design_v2.parquet",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/manifest.json",
    ".cache/benchmark.parquet"
  )
)
cat("[lineage] Optimizer recorded.\n")
