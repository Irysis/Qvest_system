## P0R01 칸 1개 측정 — 정본 셀 워커(원장 미개방 · L-code 미발행 · 텔레그램 없음 · close_t1) · 이미 있으면 건너뜀
## 실행: Rscript measure_cell.R <code>
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
RD <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
source(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/round_common.R"))   # rc_measure_cell
code <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(code) || !nzchar(code)) stop("usage: measure_cell.R <code>")
spec <- file.path(RD, "specs", paste0(code, ".json"))
if (!file.exists(spec)) stop("사양 없음: ", spec)
# 사전등록 md5 불변 확인(측정 전 · R2)
pre <- fromJSON(file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/prereg.json"), simplifyVector = FALSE)
cell <- Filter(function(z) identical(z$code, code), pre$cells)
if (!length(cell) || !identical(cell[[1]]$md5, rc_md5(spec))) stop("[P0R01] 사양 md5 ≠ 사전등록 — 등록 뒤 사양 변경 의심(R2): ", code)
rc_measure_cell(ROOT, spec, code, file.path(RD, "results"))
