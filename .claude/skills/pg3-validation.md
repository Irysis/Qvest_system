---
name: pg3-validation
description: "PG3 포트폴리오 검증/모니터링 시 적용 — 리서치 PG3(백테스트) + 프로덕션 PG3(실투)"
---
## PG3 Validation & Monitoring

### 리서치 PG3 (백테스트 기반)
PG2 확정 조합으로 **20년 rolling 백테스트** 실행:
- 전체 기간 성과: SR, CAGR, MDD
- 위기 구간 검증: GFC, COVID, RATE
- Regime별 payoff 확인
- Drift 시뮬레이션: 분기 리밸런싱 가정
- 완료 시 → **Axiom distill 트리거**

### 프로덕션 PG3 (실투 기반)
- Daily NAV 모니터링
- Drift ±5% 초과 시 경고
- Regime 변화 감지 → 슬리브 가중치 재조정
- MDD 목표 5pp+ 초과 시 긴급 알림

### 재오픈 트리거 (5가지)
1. 역할 불일치 3개월 지속
2. Concentration budget 위반
3. MDD 목표 5pp+ 초과
4. Regime gap 재확대
5. 신규 Grade A 전략이 기존 sleeve 대체 가능

### Axiom Distill
PG3 완료 → `sg_sync_methodology_memory()` + `scan_axiom_candidates()`
