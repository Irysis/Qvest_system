---
name: s4-integration-test
description: "S4 통합 테스트 시 적용 — KOSPI beat, delta_sharpe, role 라우팅"
---
## S4 통합 테스트

### 판정 기준
- `kospi_beat`: CAGR > KOSPI CAGR
- `delta_sharpe`: SR - KOSPI SR

### 라우팅
| kospi_beat | delta_sharpe | 경로 |
|-----------|-------------|------|
| TRUE | > 0 | → **S6** (Judge 직행) |
| FALSE 또는 ≤ 0 | — | → **S5** (mutation) |

### Role 결정 (sg_determine_role)
- `kospi_beat && delta > 0.2` → core_alpha
- `orthogonality > 0.7 && conditional_ic > 0` → defense
- `orthogonality > 0.5` → diversifier

### s4_integration artifact
`kospi_beat`, `delta_sharpe`, `provisional_role`, `route`(S5/S6)
