## FQ-143 P11 — lineage 기록 (alpha_package.json write 이후 순서 준수, L-194)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
pkg <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260809_002/alpha_package.json")
stopifnot(file.exists(pkg))   # write 선행 확인 — 역순이면 Judge WARN_SEQUENCE
source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260809_002",
  package_type = "alpha_package",
  method_selected = "market-level regime tail overlay (CRISIS|CAUTION -> exposure scale); verdict=config_scoped_negative (lever), hypothesis+label survived falsification",
  input_file_paths = c(
    file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"),
    file.path(ROOT, ".cache/unified_regime_signal.parquet"),
    file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet"),
    file.path(ROOT, "qepm/mailbox/worktask/WT-D20260809_002/alpha_hypothesis.json")
  )
)
cat("[P11] lineage recorded\n")
