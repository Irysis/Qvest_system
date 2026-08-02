# record_lineage_wt018.R — alpha_package lineage 기록 (L-194: package write 후 실행)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
setwd(.rt())
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_018",
  package_type = "alpha_package",
  method_selected = "CTR_MAG_12M single_factor (사전등록 primary=revenue 분모, 4셀 전량보고)",
  input_file_paths = c(
    ".cache/dart/contract_backfill",
    "04_Research/method_frontier/fq002_contract_magnitude/panel_A.parquet",
    "04_Research/method_frontier/fq002_contract_magnitude/panel_B_corrected.parquet",
    "04_Research/method_frontier/fq002_contract_magnitude/grid_returns.parquet",
    ".cache/RAWDATA.parquet",
    ".cache/benchmark.parquet"
  ),
  extra = list(grid_vintage = "RAWDATA@20260802_0304+benchmark@20260802_0151",
               prereg = "04_Research/method_frontier/fq002_contract_magnitude_prereg.md",
               parser_version = "dart_contract_doc_parser.R v2 (2026-08-02)")
)
cat("[lineage] recorded\n")
