# ADR-ramp-0002: K-RAMP 헌법 이탈 등록부 (정직 — 부풀림 금지)

Date: 2026-06-17
Status: Accepted

## Context
RAMP 플랜은 K-RAMP 헌법을 *매핑*했으나 "완벽 구현"은 아니다(가이드 §2.8/§11/§17 = 주장 말고 evidence). 빌드 전 명시 이탈을 박제하고 `ccs_evaluator`가 매 사이클 표면화한다.

## Decision
명시 이탈 3건을 등록·추적한다(은폐 금지):

| # | 헌법 | 상태 | 처리 |
|---|---|---|---|
| 1 | §3.6 4단 비용보고(gross/net_before_impact/net_after_impact/capacity_adj) | **SIMPLIFY** — Qvest `cost_model v2.4` 15bps 단일 delta 재사용 | CCS2 PARTIAL 정직표기. market-impact/capacity_adj 분해는 후속 Gate(자본 후보 시점) |
| 2 | §3.7 model-risk 9차원 | **PARTIAL** — ~6 커버(data-mining/param/regime/cost/crowding/liq via measurement-graduation+risk flags) | RMCS PARTIAL. valuation-cycle/factor-crash/corr-breakdown/dd-clustering 후속 |
| 3 | §18 synthetic-data-first | **포함(격상)** — 신규 RAMP 코드용 synthetic 생성기 + schema 검증 추가 | Gate 2 정식 충족(이탈 해소) |

## Alternatives Considered
- 4단 비용 즉시 구현 — 기각(market-impact 모델 부재, 자본 후보 전엔 과투자).
- model-risk 9차원 즉시 — 기각(증분 우선, 후속 Gate).

## Consequences
"가이드 준수"는 게이트 리뷰 PASS(CCS+essence)로만 입증. 기지 리스크: KR 베타지배(PC1 압도)·batch_434 rds 세그폴트·NAV-only·CCS 임계 미달 가능성.

## Metrics affected
CCS2(PARTIAL), RMCS(PARTIAL), DCCS/BDS(synthetic 포함으로 충족).

## Rollback plan
이탈 해소 시 본 ADR Superseded 표기 + ccs_evaluator PARTIAL 플래그 해제.

## Related Files
`02_Infrastructure/docs/rules/ramp.md` §3, `02_Infrastructure/ramp/ccs_evaluator.R`
