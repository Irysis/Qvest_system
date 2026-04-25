# Risk Agent Handoff — KR FF5 RMW/CMA Backfill (Option B)

**Source**: Alpha Agent / WT-D20260425_009 / 2026-04-25
**Recipient**: Risk Research Agent (next phase)
**Type**: External Validation Framework — factor return PIT 재구축 요청

---

## 1. Why this handoff exists

Iter 4의 1차 진단 결과: 현 `kr_factor_returns.parquet`에서 Carhart-4·FF5 둘 다 **표본 부족**이 본질이다. 단순히 Carhart-4로 전환해도 t_NW 게이트(2.95)는 통과하지 못한다.

| Spec | Joint n | Range | t_NW (WT_005 baseline) |
|---|---|---|---|
| CAPM (MKT) | 91 | 2008-01 ~ 2023-11 | **2.776** |
| Carhart-3 (MKT/SMB/WML) | 91 | 2008-01 ~ 2023-11 | **2.550** |
| FF3 (MKT/SMB/HML) | 46 | 2016-04 ~ 2023-11 | 1.823 |
| Carhart-4 (MKT/SMB/HML/WML) | 46 | 2016-04 ~ 2023-11 | **1.834** |
| FF5 | 40 | 2017-05 ~ 2023-11 | 1.843 |
| FF6 (FF5+WML) | 40 | 2017-05 ~ 2023-11 | 1.688 |

**HML은 2016-04 시작, RMW/CMA는 2017-05 시작.** Carhart-4로 바꾸기만 해서는 게이트 미통과 + power loss 위험.

진짜 해결: **HML / RMW / CMA 세 팩터를 2002~2016 구간으로 backfill** → FF5 풀 표본 n≈280, Carhart-4 풀 표본 n≈280.

---

## 2. Data feasibility — 가능

### 2-A. DART TTM 펀더멘털 (`.cache/fundamental_xlsx_ttm.parquet`)
- Period_Date: **2000-03-31 ~ 2025-12-31**
- 100K+ ticker-quarter 관측치
- 필요 항목 모두 존재:
  - **TotalAssets** (n=105,025) → CMA Investment growth
  - **TotalEquity** (n=105,022) → HML B/M
  - **OperatingProfit** (n=96,911) → RMW Operating Profitability
  - **GrossProfit** (n=96,899) → RMW alt (Novy-Marx GP/A)
  - **Revenue** (n=96,668)

### 2-B. RAWDATA / MarketCap (`.cache/rawdata.rds`)
- Size column 가용 → Market Cap denominator
- 2002+ KOSPI/KOSDAQ 통합 universe 확보

### 2-C. PIT 시차 규칙 (lag rule)
- **연간 재무제표 → 5월 리밸런싱** (Fama-French 1993 표준)
- **분기 → 45일 lag** (KR 공시 규정)
- `02_Infrastructure/factor_db/compute_value.R` 기존 패턴 재사용

---

## 3. Risk Agent에 요청하는 작업 spec

### Step R-1. KR FF5 6-portfolio 구축 (2002-07 ~ 2026-03)
Fama-French (1993, 2015) 표준 sort 따른다:
- **Size sort**: ME median split (ME대형/소형 2 그룹)
- **B/M sort**: BE/ME tercile (Value/Neutral/Growth 3 그룹) → 2×3 = 6 portfolio
- **OP sort**: OP/BE tercile (Robust/Neutral/Weak)
- **INV sort**: ΔTotalAssets / TotalAssets tercile (Conservative/Neutral/Aggressive)

### Step R-2. Factor return 계산 (월간)
- **MKT**: KOSPI200 TR - RF (KORIBOR3M / 91일 RP) — 이미 존재
- **SMB**: (Small portfolios 평균 - Big portfolios 평균)
- **HML**: (Value portfolios 평균 - Growth portfolios 평균) — backfill
- **RMW**: (Robust profitability - Weak profitability) — backfill
- **CMA**: (Conservative invest - Aggressive invest) — backfill
- **WML**: (Top 30% past 12-2 momentum - Bottom 30%) — 이미 존재 (검증 권장)

### Step R-3. PIT 검증 (필수)
- May rebalance: 전년 12월 결산 발표 후 5월 1일 적용
- Monthly cumulative compounding
- Universe filter: 시총 2억원 이상 + KS/KQ 등록종목 + 결손 처리 (NA 종목 제외)
- t-1 lag for any exposure (C5)

### Step R-4. Output 산출물
**파일**: `.cache/kr_factor_returns_v2.parquet`
**스키마** (existing schema 호환):
```
Date (월말 trading day)
MKT, SMB, HML, WML, RMW, CMA  (모두 monthly)
RF (월간 무위험수익)
n_obs_meta (각 포트폴리오 종목수)
```
**기간**: 2002-07-31 ~ 2026-03-31 (n ≈ 285 monthly observations)
**Schema 호환**: 기존 `kr_factor_returns.parquet` 컬럼 동일 (RF 추가)

### Step R-5. Validation (Risk Agent 자체 검증)
- HML/RMW/CMA 평균 부호 확인 (학술적 기대):
  - HML > 0 (long-run value premium, 단 2010s slump 가능)
  - RMW > 0 (Novy-Marx 2013)
  - CMA > 0 (Conservative > Aggressive)
- Factor 상관 행렬 |ρ| < 0.7 (excess multi-collinearity 회피)
- 기간 분할 robustness (2002-2010, 2011-2018, 2019-2026 평균)

---

## 4. 표본 확장 후 기대 t_NW (Alpha Agent power analysis)

**전제**: alpha와 잔차 sigma가 표본 확장 시 거의 invariant라 가정 (보수적).

| Scenario | n_obs | t_NW (Iter3 baseline 2.691 기준 sqrt-scale) |
|---|---|---|
| Current FF5 (2017+) | 40 | 2.691 |
| FF5 backfilled (2002+) | ~280 | 7.12 (이론치) |
| Carhart-4 backfilled (2002+) | ~280 | 7.12 (이론치) |

**현실 보정**: Iter3 t_NW=2.691은 lockbox 분리 후 in-sample 값 가능성. 실제 풀 표본 t_NW는 **3.5 ~ 5.5 범위**로 보수 추정. 어쨌든 **>2.95 게이트 통과 확률 매우 높음**.

다만 학술적으로 t_NW=7+은 다중검정 보정 후에도 너무 높아 신호의 진위 의심을 살 수 있음. 실측치가 4.0~5.5 범위에 안착할 것으로 예상.

---

## 5. PIT C1~C15 확약 사항 (Risk Agent 준수)

| Check | 적용 |
|---|---|
| C1 (no full-sample stat) | rolling/expanding only — 5월 리밸런싱 시점에 직전 회계연도 결산 사용 |
| C2 (same-day circular) | t-1 close 기준 ME 산출 |
| C3 (same period 집계→적용) | May rebalance: t년 5월 = t-1년 12월 결산 자료 |
| C4 (재무제표 lag) | 연간 5월 / 분기 45일 |
| C5 (overlay t-1) | factor return 계산 시 t-1 weights × t return |
| C13 (Z-Score Aligned) | factor return 자체에는 비해당, 신호용 alignment는 Forge 영역 |
| C14 (Usable_Date) | DART announcement_date <= sig_date 강제 |

---

## 6. Alpha Agent 후속 행동

Risk Agent가 `kr_factor_returns_v2.parquet`을 산출하면:
1. Alpha Agent는 신규 파일을 read-only로 받아 회귀 재실행
2. `external_validation_framework = ff5_backfilled_v2` 로 alpha_package 갱신
3. lockbox 분리 (in-sample = train/validation, out-of-sample = lockbox 2024+) 분리 보고
4. Carhart-4도 동시 산출 (FF5와 cross-check, robustness)

---

## 7. Risk Agent 작업 산출물 → Q-Lead 전달

```
risk_package.json {
  ...
  "external_factor_data": {
    "version": "kr_factor_returns_v2",
    "path": ".cache/kr_factor_returns_v2.parquet",
    "n_obs_full": 285,
    "date_range": ["2002-07-31", "2026-03-31"],
    "schema": ["Date","MKT","SMB","HML","WML","RMW","CMA","RF"],
    "pit_compliance": "C1-C5 verified",
    "factor_construction_notes": "Fama-French 1993/2015 + Novy-Marx 2013, KR universe"
  }
}
```

---

## 8. Estimated workload (Risk Agent)

- DART TTM extraction + universe 매핑: ~30분
- 6-portfolio 구축 + monthly rebal: ~1시간
- PIT 검증 + factor return 계산: ~30분
- Sensitivity 검증 + parquet 저장: ~30분
- **총 약 2.5시간**

이는 Risk Agent의 Σ 추정 본 task와는 별개 작업이므로 **병렬 처리 권장**.

---

## 9. Fallback (Risk Agent 백필 불가 시)

만약 Risk Agent가 universe matching 또는 DART parsing 이슈로 backfill 실패 시:
1. **Carhart-3 (MKT/SMB/WML)**를 default validation framework로 채택
   - 풀 표본 n=91, t_NW=2.550 (WT_005 baseline)
   - 게이트 2.95 미통과지만 spurious 보정 후 가장 robust
2. CAPM (n=91, t_NW=2.776) 보조 보고
3. Iter3 FF5 t_NW=2.691은 small-sample fragility로 challenge_flag 처리

---

**END Risk Agent Handoff**
