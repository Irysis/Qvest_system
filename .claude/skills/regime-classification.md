---
name: regime-classification
description: "국면 판단/overlay 적용 시 참조 — 4-Layer 국면엔진, t-1 lag"
---
## Regime Engine v7.1

### 호출
```r
source("02_Infrastructure/regime_signal.R")
regime <- build_regime_signal_table()         # 전체 기간
current <- get_regime_at_date(Sys.Date() - 1) # t-1 lag 필수 (C5)
```

### 4-Layer 구조
1. **L1 Global** (FRED): VIX, TED, Credit Spread 등 (cor=-0.137)
2. **L2 Korean Internals**: VKOSPI, 외국인 순매수 등 (cor=-0.460, L1보다 우수)
3. **L3 Derivatives**: 옵션 Put/Call, VRP
4. **L4 Endogenous**: price-only GMM

### 국면 분류
| Category | Score 범위 | 의미 |
|----------|----------|------|
| RISK_OFF | < 30 | 위기 |
| CAUTION | 30~50 | 경계 |
| NEUTRAL | 50~70 | 정상 |
| RISK_ON | > 70 | 적극 |

### 핵심 원칙
- "정상 시 헤지 안함 + 위기 확인 시에만 헤지"
- Expanding Percentile Threshold (full-sample 금지)
- 항상 t-1 lag (C5, C9)
