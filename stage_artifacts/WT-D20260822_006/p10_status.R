suppressPackageStartupMessages({library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MB <- "qepm/mailbox/worktask/WT-D20260822_006"
st <- fromJSON(file.path(MB,"status.json"), simplifyVector=FALSE)
st$current_phase <- "ALPHA_DONE"
st$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
st$blocker <- NULL
st$round_verdict <- "CONFIG_SCOPED_NEGATIVE__SOFT_TILT_STATE_SELECTION_NO_MATERIAL_RECOVERY"
st$artifacts <- list("qepm/mailbox/worktask/WT-D20260822_006/alpha_package.json",
  "qepm/mailbox/worktask/WT-D20260822_006/challenge_note.md",
  "stage_artifacts/WT-D20260822_006/PREREG.json",
  "stage_artifacts/WT-D20260822_006/alpha_validation.json",
  "stage_artifacts/WT-D20260822_006/alpha_scores.parquet")
write_json(st, file.path(MB,"status.json"), pretty=TRUE, auto_unbox=TRUE)
gl <- fromJSON(file.path(MB,"governance_log.json"), simplifyVector=FALSE)
entry <- list(ts=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), actor="alpha-research",
  event="ALPHA_PACKAGE_EMITTED",
  note=paste("FQ-246 상태 조건부 팩터 선택 — co-primary 2종 POWERED_NULL.",
    "R1/F1 게이트는 자기 적대검증에서 UNRESOLVED_UNDERPOWERED 로 정정(초판 '기각' 철회).",
    "전도성 PASS(오라클 상태 t 2.01~2.47) · F3 PASS(개인 순매수 집중 t 1.78).",
    "여유폭 회수 실질 0(최선 +1.94%). certificate 미발급 정상 — admission 경로 미진입."),
  reclassify_proposal=list(from="discovery", to="node_modulation",
    rationale="alpha_inheritance_cor 0.9282 (문턱 0.95 충족하나 근접). 본 라운드 산출은 신규 알파 원천이 아니라 기존 결합 마디(FQ-244 C0)의 상태 조절 — 전 arm 이 u=0 에서 C0 로 정확히 환원되도록 설계됨. 도훈 confirm 대상."))
if (is.null(gl$entries)) gl$entries <- list()
gl$entries <- c(gl$entries, list(entry))
write_json(gl, file.path(MB,"governance_log.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[status/governance updated]\n")
