## P2R05 GPU 연쇄(gpu_chain.sh) 비정상 출구 알림 — 1통(푸시) · prep_send 경유(발송 규칙 = qvest-telegram SKILL §0 · 1계층 표제는 prep_send 가 붙인다).
##   판단 Superfan T3 C-20261106-002 수용(11-06): 연쇄의 마감 · 실패 출구가 로그에만 남아 레인 보류 · GPU 창 소실이 조용히 지나갈 수 있었다.
##   측정 절차 · 판정과 무관(사전등록 고정 대상 아님). QVEST_TG_DRY_RUN=1 이면 발송 없이 본문만.
## 실행: Rscript gpu_chain_alert.R "<위치 — 짧게>" "<무슨 일이 있었나>" "<다음 행동>"
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 3) stop("usage: Rscript gpu_chain_alert.R <위치> <사유> <다음 행동>")
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_report.R")))
r <- prep_send(program = "방어 엔진", target = paste0("P2R05 GPU 연쇄 — ", a[1]),
               status = list(stage = "방어 엔진 — P2R05 GPU 창(THGNN 뒤 워밍 · 측정 · gpu_chain.sh 분리 실행)", position = a[1],
                             previous = "P2R05 사전등록 11-06(67a049f81 · md5 9ed7b23f)"),
               verdict_line = a[2], next_step = a[3], push = TRUE, root = ROOT)
cat("gpu_chain_alert ok =", isTRUE(r$ok), "\n")
