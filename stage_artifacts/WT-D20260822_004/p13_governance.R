suppressPackageStartupMessages(library(jsonlite))
source("02_Infrastructure/config.R")
MB <- "qepm/mailbox/worktask/WT-D20260822_004"
g <- fromJSON(file.path(MB,"governance_log.json"), simplifyVector=FALSE)
g$events <- c(g$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), agent = "alpha-research", action = "ALPHA_DONE",
  summary = "FQ-244 결합 규칙 마디 — 비-ML 결합 2종 paired 판정 완료. C1 rank평균 -0.41%p/yr(t -0.24) · C2 winsor-z -0.67%p/yr(t -0.61) 둘 다 POWERED_NULL_NO_MATERIAL_EFFECT(MATERIAL 8.2228 배제). 음성대조 C3 max-z 는 사전등록 예측대로 EFFECT_NEGATIVE(t -2.08). 대조군 C0 가 FQ-237 공표 PORT_t 0.94741072 를 Δ -4.19e-09 로 재현. 반증 축 2건 발화(R1b 전이-음성 집중 미수송 · R3 잠식→손실 연결 절단 t +0.25). 마디 여유폭 ORACLE_K PORT_t 4.647. NO_TRANSITION.",
  artifacts = c("qepm/mailbox/worktask/WT-D20260822_004/alpha_package.json",
                "qepm/mailbox/worktask/WT-D20260822_004/challenge_note.md",
                "stage_artifacts/WT-D20260822_004/PREREG.json",
                "stage_artifacts/WT-D20260822_004/alpha_scores.parquet",
                "stage_artifacts/WT-D20260822_004/alpha_validation.json"))))
write_json(g, file.path(MB,"governance_log.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[governance_log] appended\n")
d <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
req <- c("task_id","as_of_date","forecast_horizon","alpha_vector","factor_specs","diagnostics")
cat("schema required 6:", all(req %in% names(d)), "\n")
cat("verdict:", d$verdict, "| round_verdict:", d$round_verdict, "\n")
cat("diagnostics.canonical_port_t_nw_lag3:", d$diagnostics$canonical_port_t_nw_lag3, "\n")
cat("falsification entries:", length(d$hypothesis$falsification), "\n")
cat("regime holds/weakens:", length(d$hypothesis$regime_scope$holds_in), "/", length(d$hypothesis$regime_scope$weakens_or_reverses_in), "\n")
