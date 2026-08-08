## lineage 기록 (alpha_package.json write 이후 — L-194 순서 준수)
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/worktask/lineage_utils.R")
paths <- c(".cache/RAWDATA.parquet",
           ".cache/factor_db/factor_db_202607.parquet",
           ".cache/factor_db/factor_registry.json",
           "stage_artifacts/WT_D20260808_002/alpha_scores.parquet",
           "qepm/mailbox/worktask/WT-D20260808_002/alpha_hypothesis.json")
ok <- file.exists(paths)
cat("[lin] 입력 실측 — 경로 5건 존재:", paste(sprintf("%s=%s", basename(paths), ok), collapse=" "), "\n")
stopifnot(all(ok))
record_package_lineage(
  task_id = "WT-D20260808_002",
  package_type = "alpha_package",
  method_selected = "M26_Revenue_Mom 증분 FMB NW(lag3) — 단일 시험, no_sweep",
  input_file_paths = paths
)
cat("[lin] lineage 기록 완료\n")
