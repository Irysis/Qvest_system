# PD36 Overlay Diagnostic — Challenge Note

## Mode

**Research diagnostic** — Legacy STR 호환. NOT admission cycle.
Codex Round 5-step **skip 가능** (research mode, no admit graduation).

## Mandate Origin

도훈 직접 명령 2026-05-12 KST:
> "PG2 강화 path PD30 raw + AR threshold + M4 overlay 결합 backtest도 병렬로 진행해줘"

WT-D20260512_001 strict admit cycle 별도 진행중 + 본 task = quick measurement for feedback / 무한리서치 mandate 정합.

## Primary Coupling Spec — 도훈 mandate 인용

```
final_w_it = (z_composite_it × β_AR_t × β_M4_t) [renormalize to Σw=1, top20, cap [0, 0.20]]
```

## 해석 결정 — Stock-level normalize vs Sleeve-level scaling

### 도훈 mandate 문구 표면 해석 (Stock-level)

z×β×β 각 stock-month 곱 → top20 selection → renormalize Σw=1 → top20 cap.

**문제점**: β_AR=0.5, β_M4=0.7인 경우, 모든 stock의 z에 동일 scalar 곱 → sleeve 내부 normalize 시 stock weight 분포 동일, β effect cancel out. KR equity sleeve 0.55 portfolio share도 그대로 유지 → **β overlay effect = 0 (no-op)**.

### Pure overlay 해석 (Sleeve-level, L-281 STR_1715_AR_threshold_overlay_PG2 패러다임)

`β_t = β_AR_t × β_M4_t` (multiplicative) = **KR equity sleeve risk-on scalar**.

- KR_EQUITY allocation = 0.55 × β_t (dynamic, t 시점)
- Excess (0.55 × (1 − β_t)) → CASH sleeve로 이동
- TSMOM (0.225), KR_10Y (0.18) sleeve unchanged
- Stock-level z_composite top20 + softmax weights 그대로 보존 (alpha 100% 보존, L-281 mandate 정합)

### 채택 — Pure overlay 해석 (Sleeve-level)

**근거 3가지**:

1. **mandate intent**: 도훈은 "PD30 raw + AR threshold + M4 overlay 결합"으로 명시. AR threshold (STR_1715_AR_threshold_overlay_PG2 admit 2026-05-04, L-276~L-278) + M4 overlay (STR_1715 PG2 admit 2026-05-02, L-274) 모두 sleeve-level risk-on/off scalar로 admit. Stock-level normalize 해석은 admit된 overlay 본질 (sequential layered risk management)과 어긋남.

2. **L-281 (Cross-Asset TSMOM 정의상 직교)**: pure overlay = β_t scalar emission per period → alpha 100% 보존 + cash로 underweight 보충 → sequential layered risk management 가능. weight modification (z 직접 곱)은 alpha 침범 (Round 2 6-trial 폐기 path, L-278).

3. **Round 3 cycle 끝 도훈 Path A 명시 admit 정합 (L-277)**: AR Pure Overlay (Kritzman-Page-Turkington 2011 FAJ) = "alpha + AR overlay 직교" mandate. Stock-level normalize 해석은 직교성 깨짐.

**Stock-level 표면 해석 reject** (no-op 결과 = mandate intent 무효화 의심).

## Primary spec (Pure overlay, multiplicative)

```
β_t = β_AR_t-1 × β_M4_t-1   (t-1 PIT lag mandatory)

KR_EQUITY_alloc_t = 0.55 × β_t
CASH_alloc_t      = 0.045 + 0.55 × (1 - β_t)
TSMOM_alloc_t     = 0.225 (unchanged)
KR_10Y_alloc_t    = 0.18  (unchanged)

# Inner sleeve: z_composite top20 softmax (PD30 C_softmax 유지)
```

## Alternative spec (Secondary, time permits)

- **Conservative**: β_t = min(β_AR_t-1, β_M4_t-1)
- **Linear blend**: β_t = 0.5 × β_AR_t-1 + 0.5 × β_M4_t-1

## PIT t-1 Lag Mandate

AR/M4 신호 t시점 weight_str1715 → held_period t+1m return에 적용 = 이미 t-1 lag built-in (alpha label = sig_date / held = sig_date+1m). 추가 lag 불필요. 하지만 보수적으로 sig_date 기준 align (held_period에 이미 t+1m forward lag).

## Signal Coverage Gap

| Signal | Coverage | Gap |
|---|---|---|
| PD30 sig_dates | 2001-07 ~ 2026-04 (298) | — |
| M4 schedule | 2004-02 ~ 2026-05 (268) | 2001-07~2004-01 (31m) |
| AR threshold | 2004-02 ~ 2026-05 (268) | 2001-07~2004-01 (31m) |

**Pre-2004-02 (31m) 처리**: β_t = 1.0 passthrough (no overlay, baseline alpha only).
이는 운용 트래킹 단계 lockbox-scope 폐기 mandate (도훈 2026-05-09) 정합 + AR/M4 무명 시점은 overlay 없는 raw alpha = PD30 C_softmax baseline 그대로 = comparison 정합 (overlay effect는 2004-02 이후 marginal).

## Constraint Compliance

- **PerformanceAnalytics 표준만** (Return.portfolio / table.AnnualizedReturns / maxDrawdown) — `prod(1+r)-1` 자체 합성 금지 (L-282 학습)
- **PIT C1~C15** 전체 (AR/M4 t-1 lag retain)
- **Backtest Result Contract v1.0** 10-component bt_result + audit
- **15bps cost** (turnover-based, sleeve rebal + inner churn)
- **20 names cap, weight bounds [0, 0.20], long-only, Σw=1** (sleeve internal)
- **Lockbox 폐기** (`.claude/rules/lockbox-scope.md` 도훈 mandate 2026-05-09) — forge 단계 운용 트래킹

## L-code 적립 후보 (diagnostic 종료 후 검토)

- **L-289 candidate**: "Pure overlay sleeve-level scaling vs Stock-level normalize 차이 — multiplicative β 적용 위치가 alpha 침범 여부 결정"
- **L-290 candidate**: "AR threshold × M4 multiplicative coupling 효과 — 단일 overlay 대비 marginal MDD/SR 개선 측정"

## Output

- `bt_result.rds` (10-component standard)
- `manifest.json` / `metrics.csv` / `nav.csv` / `period_returns.csv` / `holdings.csv` / `audit.json`
- Comparison vs PD30 C_softmax raw + vs S4 v2 baseline (provenance: WT-T20260509_001 measured_metrics_255m)
- DM test vs PD30 raw SR (Diebold-Mariano significance)

## Codex Round Limitation

본 diagnostic Codex Round skip — research mode, no admit graduation, quick measurement only. Final admit cycle (WT-D20260512_001 strict)는 별도 6-agent strict 진행중. 이 diagnostic 결과는 strict admit cycle의 input feedback으로 사용.

---

작성일: 2026-05-12 KST
작성자: Q-Lead Forge agent (PD36 diagnostic)
