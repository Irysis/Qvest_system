# R14 — handoff 블록 등재(상태전이 차단 사유 포함). status.json 은 우회하지 않는다.
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
p <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector=FALSE)
p$handoff <- list(
  next_agent="optimizer-research",
  consumes=c("qepm/mailbox/worktask/WT-R20260829_004/risk_package.json",
             "stage_artifacts/WT_R20260829_004/covariance.parquet",
             "stage_artifacts/WT_R20260829_004/exposure_matrix.parquet",
             "stage_artifacts/WT_R20260829_004/specific_risk.parquet",
             "stage_artifacts/WT_R20260829_004/factor_covariance.parquet",
             "stage_artifacts/WT_R20260829_004/covariance_panic.parquet (as-of 진단 전용 — consumption_restriction 준수)",
             "stage_artifacts/WT_R20260829_004/covariance_normal.parquet (동일)",
             "stage_artifacts/WT_R20260829_004/tail_risk.json",
             "stage_artifacts/WT_R20260829_004/regime_correlation.parquet"),
  status_transition=list(
    attempted="ALPHA_DONE -> RISK_DONE",
    transition_allowed=TRUE, artifacts_present=TRUE,
    blocked_by="schema validation",
    reason="02_Infrastructure/worktask/schema.json 의 task_id 패턴 '^WT-[DPSH][0-9]{8}_[0-9]{3}$' 가 v10 reinforcement 접두 **R** 을 포함하지 않는다. 동일 검증에서 alpha_package.json 도 같은 사유로 INVALID — 본 라운드가 만든 결함이 아니라 선재하는 스키마 공백이며 _005/_006/_007 도 동일하게 걸린다.",
    action_taken="status.json 을 손으로 쓰지 않았다(게이트 우회 금지). current_phase 는 ALPHA_DONE 으로 남는다.",
    downstream_impact="worktask_sequence_enforcer 는 선행 패키지 **파일 존재**로 허용 판정하므로 optimizer 스폰은 막히지 않는다. 다만 상태기계 기록은 어긋난 채 남는다 — Q-Lead 판단 필요.",
    fix_location="02_Infrastructure/worktask/schema.json:17 (패턴에 R 추가) — risk 권한 밖(WT_004 외부 쓰기 금지)"),
  optimizer_reading_order=c(
    "1) risk_summary.top_common_risks_note → 요인 라벨이 아니라 concentration.sector_block_variance_contribution 으로 집중을 읽을 것",
    "2) risk_summary.regime_sigma_heterogeneity.consumption_restriction → 국면 Sigma 는 as-of 진단 전용",
    "3) diagnostics.factor_correlation_note → 섹터 요인 7쌍 |rho|>0.8, Omega 역행렬 기반 최적화 불안정 구간",
    "4) challenge_flags RISK-CH1(섹터 52%) / RISK-CH2(vintage 위험수준) / RISK-CH4(국면 배율 사전인지 불가)",
    "5) risk_summary.portfolio_beta → 노출가중 0.967 vs 회귀 1.035, 보수측은 회귀값"))
write_json(p, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, null="null", na="null")
cat("[R14] handoff 등재 완료 · top-level fields:", length(p), "\n")
