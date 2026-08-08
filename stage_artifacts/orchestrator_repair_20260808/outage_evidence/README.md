# 일간 orchestrator 경로 사망의 증거 (2026-08-08 수리 시 회수)

`forward_weights_orchestrator.R` 의 PROJECT_ROOT 해석 결함으로, manifest 가 **프로젝트 밖 사용자 홈**
(`C:\Users\99922\qepm\mailbox\governor\forward_weights_manifests\`)에 적재되고 있었다.
내용은 전부 `MISSING_WRAPPER`(3전략 전건) — 즉 **일간 forward-weights 산출이 5주 이상 전혀 없었다**.

- `manifest_20260701` · `20260715` · `20260801` : 사망 기간의 실제 산출(전부 436바이트 동일)
- `manifest_20260808` : 2026-08-08 수리 착수 시 내가 재현 실행한 것(동일 증상 확인용)

★이 파일들은 **유효한 manifest 가 아니다** — 운영 경로(`qepm/mailbox/governor/forward_weights_manifests/`)
에 넣지 않고 증거로만 보존한다. 수리 후 정상 manifest 는 프로젝트 내 경로에 새로 쌓인다.
