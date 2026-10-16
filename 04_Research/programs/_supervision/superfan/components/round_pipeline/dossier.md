# 라운드 파이프라인 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: round_pipeline`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#round_pipeline` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 1계층 라운드 파이프라인(측정 · 셀 평가 · 판정)
- 일정: 세션이 띄우는 분리 실행(pipeline_v2 · measure.sh · eval_parallel.sh)
- 코드: `04_Research/programs/_lib/round_kit.R` · `04_Research/programs/_lib/eval_parallel.sh` · `02_Infrastructure/reinforcement/rf_cell_engine.R` · `02_Infrastructure/contracts/matched_controls.R`
- 감시 규칙:
- `pipeline_errors` (log_patterns): R 오류, 측정 무효, 사전등록 가드

## 알려진 고장 형태 (기억 카드 · 실측)

- 카탈로그 비중 칸: 어댑터 예외 → 셀 엔진 tryCatch → NULL 로 그 신호일이 기록 없이 빠진다(커버리지 ≥ 80% 가드만 있음 — 기억 카드 project-catalog-cap-post-hoc-silent-date-drop…).
- 파이프라인 단계 순서 실수로 사전등록 R2 가드에 걸린 적이 있다(10-15 — P3R01 판정이 P3R02 재핀보다 먼저 돌았다).
- 센티널 = 04_Research/programs/_lib/night_state/<단계>.done.
- 분리 실행은 Git\bin\bash.exe 로(usr\bin\bash.exe 는 PATH 문제로 즉시 종료 — 10-15 실측).

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
