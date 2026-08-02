# emit_wt023.R — WT-D20260802_023 alpha_validation 방출 + lineage 기록
#   (run_fq125_confirm.R 완료 후 실행. 수치는 전부 fq125_confirm_results.json 실측 소비)
#   순서: alpha_package.json 은 메인이 Write 도구로 직접 작성(ast_spec_gate 경유) 후
#         본 스크립트의 lineage 기록이 이어진다 (L-194 순서: package write → lineage)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
WT   <- "WT-D20260802_023"
STG  <- file.path("stage_artifacts", paste0("WT_", gsub("^WT-", "", WT)))
MBX  <- file.path("qepm/mailbox/worktask", WT)
dir.create(STG, recursive = TRUE, showWarnings = FALSE)

J <- fromJSON(file.path(OUTD, "fq125_confirm_results.json"), simplifyVector = TRUE)

validation <- list(
  task_id = WT, measured_at = J$measured_at,
  prereg = J$prereg, grid_vintage = J$grid_vintage, panel_reuse = J$panel_reuse,
  selection_type = "chain", n_trials = 1,
  parity_wt018 = J$parity_wt018,
  perturbation = J$perturbation[setdiff(names(J$perturbation), "draws")],
  verdict = J$verdict,
  ic = J$ic,
  correction_ab_size = J$correction_ab_size,
  subperiod_halves = J$subperiod_halves,
  canonical_A_size = J$canonical_A_size,
  coverage = J$coverage,
  pit_battery = list(test = "08_Tests/data/test_contract_panel.R",
                     pass = 9, fail = 0, injection_included = TRUE,
                     rerun_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  metric_type_map = list(ic = "diagnostic_statistic",
                         perturbation_q05 = "diagnostic_statistic (사전등록 판정 기준)",
                         canonical_A_size = "canonical_screen",
                         dual_basis_diag = "canonical_screen_diag"),
  universe_comparison = NULL,
  notes = c(
    "확정 라운드 — graduation HARD 미적용(파일럿 표본 n=24, 사전등록 scope_limit).",
    "같은 패널 재사용 — 섭동 q05는 멤버십/스코어 강건성 검정이지 독립 표본 확인이 아님(사전등록 provenance_honesty).",
    "cap-w PORT_t -0.371 / EW-uni +1.488 = 전이 벽 미통과 불변 — IC 확정은 랭킹 신호력까지.",
    "WT_D20260714_004 screen_inputs.rds 미사용 — grid_* 신선 빈티지(RAWDATA@20260802_0304) 사용 (WT-020 플래그 비해당).")
)
write_json(validation, file.path(STG, "alpha_validation.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = 6, null = "null")
cat("[emit] alpha_validation →", file.path(STG, "alpha_validation.json"), "\n")

# lineage (alpha_package.json 실존 확인 후 기록 — L-194 순서)
pkg <- file.path(MBX, "alpha_package.json")
if (file.exists(pkg)) {
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WT, package_type = "alpha_package",
    method_selected = "CTR_MAG_12M_MCAP (계약금액 12M 누적/시가총액) — 섭동 q05 사전등록 확정",
    input_file_paths = c(
      file.path(OUTD, "panel_A.parquet"),
      file.path(OUTD, "panel_B_corrected.parquet"),
      file.path(OUTD, "grid_returns.parquet"),
      file.path(OUTD, "grid_universe_size.parquet"),
      file.path(OUTD, "fq125_confirm_results.json")))
  cat("[emit] lineage 기록 완료\n")
} else {
  cat("[emit] alpha_package.json 미존재 — lineage 는 package write 후 재실행\n")
}
