## 프로그램 라운드 칸 1개 측정 — 공용 진입점(round_kit.R::rk_measure_cell)
## 실행: Rscript measure_round_cell.R <round_dir(저장소 상대)> <prereg(저장소 상대)> <code>
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 3L) stop("usage: measure_round_cell.R <round_dir> <prereg> <code>")
rk_measure_cell(ROOT, file.path(ROOT, a[1]), file.path(ROOT, a[2]), a[3])
