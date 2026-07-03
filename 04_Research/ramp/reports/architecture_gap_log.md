# RAMP Architecture Gap Log (가이드 §9.2)

| ID | Date | Gate | Gap | Severity | Affected Score | Proposed Fix | Status |
|---|---|---|---|---|---|---|---|
| GAP-0001 | 2026-06-17 | 3.6 | 4단 비용보고(market-impact/capacity_adj) 미구현 — 15bps 단일 delta | Medium | CCS2 | 자본 후보 시 impact/capacity 분해 추가 | Open(ADR-0002) |
| GAP-0002 | 2026-06-17 | 3.7 | model-risk 9차원 중 ~3(valuation-cycle/factor-crash/corr-breakdown/dd-clustering) 미구현 | Medium | RMCS | Gate 7 risk_manager 확장 | Open(ADR-0002) |
| GAP-0003 | 2026-06-17 | 3 | strategy_holdings 부재(NAV-only 풀) → holdings-overlap/exposure-distance dim unavailable | Low | SDS | return-space dedup으로 충당, holdings 백필은 별도 | Accepted(정직표기) |
| GAP-0004 | 2026-06-17 | ops | 모닝브리핑 스케줄 작업이 Qvest_Codex 경로 실행 + config sink로 regime brief 발송 검증 불가 | Medium | — | 스케줄 작업 3종 원본 재배선(도훈 confirm 대기) | Open |
| GAP-0005 | 2026-06-17 | 3 | batch_434 result rds vanilla readRDS 세그폴트 | Medium | SDS/coverage | robust 읽기(data.table/xts + 결과계약 로드) | Open(구현 중) |
