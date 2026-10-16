# 충실구현 레인 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: replication_lane`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#replication_lane` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 충실구현 레인(Qvest_ReinforceAutoLoop → reinforce_auto_tick · rf_replication_auto.sh)
- 일정: Qvest_ReinforceAutoLoop 수 분 간격 틱(실행 중이면 다음 틱 거부 0x800710E0 = 정상)
- 코드: `02_Infrastructure/ops/rf_replication_auto.sh` · `02_Infrastructure/ops/reinforce_auto_tick.sh` · `02_Infrastructure/alpha_search/run_paper_replication.R`
- 감시 규칙:
- `lane_errors` (log_patterns): 틱 비정상 종료, R 오류, 레인 정지 사유, 감사 상충, 리프레시 잠금 stale
- `lane_alive` (freshness): .cache/scheduler_logs/reinforce_auto_{YYYYMMDD}.log
- `request_state` (json_field): 06_Registry/replication_request.json

## 알려진 고장 형태 (기억 카드 · 실측)

- claim 2시간이면 살아 있는 실행도 회수해 이중 실행할 수 있다(기억 카드 project-unattended-replication-lane-reclaims-live-runs-at-2h-20260913).
- 세션에서 띄운 레인의 'OAuth 만료'는 가짜 — 무인 인증 = 사용자 환경변수 CLAUDE_CODE_OAUTH_TOKEN(기억 카드 reference-session-launched-lanes-inherit-desktop-auth-env-20261010).
- 주간 사용 한도(rate_limit · weekly limit)에 걸리면 틱마다 같은 줄을 남기고 초기화 시각까지 멈춘다(2026-10-15~16 실측).
- 재감사 번복 = audit_conflict(세션 판정 · 다음 논문 진행 — 기억 카드 project-audit-conflict-…-20261014).
- 실행 중이면 다음 틱이 거부된다(작업 결과 0x800710E0) — 정상.

## 기준선 — 정상일 때의 모습

- (첫 진단 때 채운다 — 정상 실행의 소요 시간 · 마지막 줄 · 산출 신선도)

## 사건 기록 (최신이 위)

- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
