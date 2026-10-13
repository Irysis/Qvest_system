## P2R01 — RX0(같은 판본 기저 대조) 선행 측정. 처방과 독립이라 처방 담당 실행 중에 먼저 잰다(기저 신호 캐시 시드 겸).
## ★결과는 평가 단계(evaluate.R) 전까지 열지 않는다 — 처방 · 사전등록에 영향을 주지 않게.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/round_common.R"))
P <- rx_paths("P2_DEFENSE", "P2R01_s2_pilot", ROOT)
n_lin <- rc_lineage_trials(ROOT)
sp0 <- rc_rx0_spec(P, "P2R01_s2_pilot", n_lin)
f0 <- file.path(P$specs_dir, "P2R01_RX0.json")
cat("RX0 사양 md5:", rc_write_spec(sp0, f0), " · 계보 측정 시도:", n_lin, "\n")
rc_measure_cell(ROOT, f0, "P2R01_RX0", file.path(P$round_dir, "results"))
