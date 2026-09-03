# R12 — PIT 게이트 결과(양방향) 패키지 등재 + challenge review 기록
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004"); MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
g  <- fromJSON(file.path(OUT,"pit_gate_risk.json"), simplifyVector=FALSE)
pc <- fromJSON(file.path(OUT,"pit_gate_positive_control.json"), simplifyVector=FALSE)
p  <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector=FALSE)

p$pit$gate_detect_lookahead <- list(
  scanned_files=g$scanned, all_clean=g$all_clean, per_file=g$per_file,
  positive_control=list(
    probeA_declared_idioms=list(fired=pc$probeA$fired, n=pc$probeA$n, checks=pc$probeA$checks),
    probeB_risk_specific=list(fired=pc$probeB$fired, n=pc$probeB$n),
    reading=paste0("A(선언 idiom C1/C5_VT/C5_DDshort) 3/3 발화 → 계기는 살아 있다. ",
      "B(전 표본 cov · 국면라벨 shift(-1)) 0/3 → detect_lookahead 의 R 경로에는 **전 표본 공분산에 대한 ",
      "일반 검사가 없다**. 따라서 본 라운드의 detect_lookahead PASS 를 'Sigma 의 C1 통과' 근거로 ",
      "인용하면 안 된다 — 그 축은 아래 c1_evidence 가 담보한다."),
    c1_evidence=pc$risk_c1_evidence,
    instrument_gap="detect_lookahead R 경로 미검출 축(risk 레인): cov()/var() 전 표본 추정 · 국면 라벨 shift(-1). 인프라 후속 대상."),
  artifacts=list(gate="stage_artifacts/WT_R20260829_004/pit_gate_risk.json",
                 positive_control="stage_artifacts/WT_R20260829_004/pit_gate_positive_control.json"))
write_json(p, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, null="null", na="null")
cat("[R12] pit gate 등재 완료\n")

source(file.path(ROOT,"02_Infrastructure/worktask/worktask_manager.R"))
wt_record_challenge_review(
  task_id="WT-R20260829_004", from_agent="risk", objection=FALSE,
  reason=paste0("정식 challenge(alpha 재작업 요구) 미발행 — 발견 3건은 alpha 판정을 바꾸지 않는다. ",
    "①데이터 무결성 267건은 alpha 선택 경로 침투 12/6475 슬롯이고 패닉월과 공집합 ",
    "②요인모형 walk-forward 시장share 42.7% 는 alpha F2(50.4%) 를 반박이 아니라 **확인** ",
    "③오버레이 미적용은 S0/S1 규약 준수. 대신 challenge_flags 6건을 하류로 이관한다."),
  targets_reviewed=c("alpha_package","alpha_vector","confidence_vector","factor_specs",
                     "regime_signal_timeseries","preregistered_verdicts_F1_F2_F8",
                     "alpha_validation","challenge_note"))
cat("[R12] challenge review 기록 완료\n")
