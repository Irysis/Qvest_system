---
name: pg0-gap-diagnosis
description: "PG0 포트폴리오 gap 진단 시 적용 — Cold Start, Gap Vector, sleeve_needs"
---
## PG0 Gap Diagnosis

### 호출
```r
source("02_Infrastructure/portfolio_governor.R")
gap <- pg0_gap_review("V7_ALLWEATHER_001")
```

### Cold Start Protocol
- Phase 0 (빈 포트): "core_alpha 필요"
- Phase 1 (1 전략): gap 재계산 → diversifier/defense 필요 여부
- Phase 2+ (정상): 정규 PG0~PG3

### Gap Vector
```json
{
  "cagr_gap": target_cagr - current_cagr,
  "sharpe_gap": target_sr - current_sr,
  "mdd_gap": target_mdd - current_mdd,
  "sleeve_needs": ["core_alpha", "diversifier", "defense"],
  "regime_state": {"category": "CAUTION", "score": 51.4}
}
```

### 목표
CAGR 16%, SR 2.0, MDD < 25%
