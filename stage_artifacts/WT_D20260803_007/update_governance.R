suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
MBX <- "qepm/mailbox/worktask/WT-D20260803_007"
p <- file.path(MBX, "governance_log.json")
G <- fromJSON(p, simplifyVector = FALSE)
ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
e1 <- list(timestamp = ts, agent = "alpha-research", action = "ALPHA_PACKAGE_EMITTED",
  summary = paste0("FQ-135 era-robust 성분 선별 실측 완료 — 사전등록 판별 (a) t=+1.212 FAIL / ",
    "(b) t=+1.304 FAIL. 사후 기전 귀속: robustness 순증분 t=-0.571 (음수), level-직교 arm PORT_t=-1.068. ",
    "285-factor 풀 / walk-forward 7 step / OOS 167월 / 215 arm(무작위 귀무 200). ",
    "gate_eligible=FALSE, capital_claim=none. challenge_flags 11 (HIGH 3)."))
e2 <- list(timestamp = ts, agent = "alpha-research", action = "SELF_ADVERSARIAL_CHALLENGE",
  summary = paste0("v8.2 자체 적대검증 8 concern (ACCEPT 2 / PARTIAL 4 / REBUTTAL 2). ",
    "escalate 미발화 — HIGH 3건(문턱 5 미만), AX axiom hard FAIL 0, PIT C1 위반 0. challenge_note.md 기록."))
G$events <- c(G$events, list(e1), list(e2))
write_json(G, p, pretty = TRUE, auto_unbox = TRUE)
S <- fromJSON(file.path(MBX, "status.json"), simplifyVector = FALSE)
S$current_phase <- "ALPHA_DONE"; S$updated_at <- ts
write_json(S, file.path(MBX, "status.json"), pretty = TRUE, auto_unbox = TRUE)
cat("governance_log 2 events + status ALPHA_DONE\n")
