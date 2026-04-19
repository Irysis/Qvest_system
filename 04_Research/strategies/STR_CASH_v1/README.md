# STR_CASH_v1 — Regime-Conditional Cash Allocation Sleeve

**Role**: `cash_allocation` (v55 신규 role)
**Trail**: `standard`
**Gap Targeting**: `[cash_efficiency, MDD_regime]`
**Version**: v1.0 (2026-04-19)

## 설계 의도

Defense sleeve 공석 상태에서 **가장 효율적인 drawdown 완화 장치**.
팩터가 아닌 **배분 결정(allocation rule)** — AX-005(Defense standalone 실패)를 구조적으로 우회.

```
MRS Crisis (≥70)  → cash 30%
MRS Bad (50~70)   → cash 15%
MRS Normal (30~50)→ cash 5%
MRS Good (<30)    → cash 0%
나머지는 equity sleeve (Core/Div/Defense 앙상블)
```

## Regime Signal Source

- `.cache/regime_v7.parquet` (MRS monthly)
- 또는 `.cache/unified_regime_signal.parquet`

## AX 준수

- **AX-005 우회**: cash는 팩터가 아니라 배분 결정 → standalone defense 금지 규칙과 무관
- **AX-001 v2 적용**: crisis 구간 alpha > 0 (cash가 equity drag 회피로 core 대비 positive alpha)
- **AX-002**: regime signal은 t-1 lag (C5) 준수

## 평가 지표 (role = cash_allocation)

- `opportunity_cost_bps_annualized < 20` (audit_cash_allocation)
- `tail_risk = 0` (정의상)
- `avg_cash_pct` 및 `max_cash_pct` 기록
- Regime 기반 동적 cash allocation의 **crisis drawdown 완화 효과** 측정

## 입력 / 출력

**입력**:
- `RAWDATA` (KOSPI 구성종목 월간 수익률, equal-weight index proxy)
- `.cache/regime_v7.parquet` (MRS monthly)
- 3M 금리 (FRED 또는 상수 2.5% 가정)

**출력**:
- `output/hurdle_result.json` — SR/CAGR/MDD + cash 전용 지표 (opp_cost, avg_cash_pct, crisis_alpha)
- `output/cash_weight_timeseries.csv` — monthly date × cash_weight

## 구현

- `factor_engine.R`: regime → cash_weight 시그널
- `run_all.R`: 전체 파이프라인 (데이터 로드 → 시그널 → 백테스트 → hurdle)
