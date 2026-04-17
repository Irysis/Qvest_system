---
name: factor-db-access
description: "Factor DB 팩터 조회/IC 계산 시 적용 — 288팩터, Z_Score_Aligned, PIT 접근"
---
## Factor DB 접근 규칙

### 로드
```r
source("02_Infrastructure/factor_db_connector.R")
factors <- load_month_factors(sig_date)  # C15 필수 경유
```

### 288 팩터 카테고리
V(24 Value), M(31 Momentum), Q(33 Quality), D(56 Defense), S(2 Size),
C(19 Consensus), L(44 Liquidity), AC(12 Accrual), R(19 Risk),
RE(10 Regime), CR(13 Crowding), GR(12 Growth), XF(44 xlsx-derived)

### 접근 원칙
1. `Z_Score_Aligned`만 사용 (C13). NEGATE_FACTORS 절대 금지.
2. IC 접근 시 `Usable_Date <= sig_date` (C14)
3. 필요 팩터만 필터 (15~20개). 288개 전체 로드 금지.
4. `setkey(dt, Date, Ticker)` 후 keyed join

### IC 계산
```r
source("02_Infrastructure/factor_db_builder.R")
compute_all_factor_ic_monthly()  # 전기간 IC
```

### conditional_ic_matrix
`.cache/conditional_ic_matrix.csv` — ic_all, ic_bad, ic_good, conditional_value
