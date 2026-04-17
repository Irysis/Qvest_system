---
name: s2-profiling
description: "S2 IC/ICIR 프로파일 시 적용 — 태그 체계, ICIR 기준, RoleBias"
---
## S2 프로파일

### IC/ICIR 계산
rolling/expanding window만 허용. full-sample 금지 (C1).

### 태그 체계
| ICIR | 태그 |
|------|------|
| ≥ 0.20 | **Strong** |
| 0.10~0.20 | **Moderate** |
| < 0.10 | **Weak** |

### RoleBias 태그 (필수)
- `RoleBias_Core`: 정상 장 alpha, SR 기여
- `RoleBias_Diversifier`: 기존 전략과 저상관
- `RoleBias_Defense`: 위기 시 MDD 통제

### Alpha Lab Gate
ICIR < 0.20이면 정식 연구 진입 재검토 (폐기가 아닌 재검토).
5Y IC 유의성 검증 필수.

### EVT Tail Risk 프로파일 (신규 — Pfaff Ch.7)
S2에서 반드시 산출:
```r
source(file.path(INFRA_DIR, "portfolio/tail_risk_engine.R"))
evt <- compute_evt_var(factor_daily_returns, p = 0.99)
# evt$shape_xi: GPD 꼬리 지수 (>0.3이면 극단적 fat tail)
# evt$var_evt / evt$es_evt: 99% VaR/ES
```
- NIG/GHD 분포 피팅 (ghyp 패키지, 가능 시)
- 조건부 VaR 비교: 정상장 VaR vs 위기장 VaR

### s2_profile artifact
`strategy_id`, `factor_id`, `ic_ir`, `tag`, `role_bias`, `ic_timeseries`, `evt_profile`
