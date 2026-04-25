# Weight Method Selected — WT-D20260425_007 (Iter 2)

**Selected Method**: `RegimeSigma_MinCVaR`
**Selection objective**: `to_adj_ret` (cost-adjusted return; R4 P3 enum)
**Iter 2 verdict**: `ITER2_SUPERIOR` (vs baseline Kelly_frac05_LW)

## 1. 핵심 결정 요약

| Metric | Selected (Iter 2) | Baseline (Kelly_frac05_LW) | Δ |
|---|---|---|---|
| Overall SR | **1.129** | 0.945 | +0.184 |
| NORMAL SR | **0.952** | 0.804 | +0.149 |
| CAUTION SR | **2.242** | 1.969 | +0.273 |
| MDD | **-41.8%** | -44.6% | +2.8pp |
| cost_adj_SR | **1.112** | 0.945 | +0.167 |

**판정**: Iter 2 가설(RegimeSigma_MinCVaR)은 baseline 대비 **uniformly superior**. 12 candidate method 중 **cost_adj_sr 1위**.

## 2. NORMAL SR 1.30 목표 미달 — 정직한 보고

- 목표: NORMAL SR 1.30+
- 달성: **0.952** (gap -0.348)
- 가설 verification: PASS (baseline 대비 +0.149, SUPERIOR 등급)
- **그러나 절대 breakthrough 미확인** — 추가 작업 필요 (confidence calibration / regime hysteresis / alpha winsor 완화 등)

## 3. 선택 근거

### 3.1 데이터 근거
- **CAUTION ρ = 0.221** vs BULL/NORMAL 0.125 (76% 상승) — Risk Mgr 발견
- regime-conditional Σ가 CAUTION/CRISIS 진입 시 자동 dispersion penalty 부과
- Pooled MVO은 이 정보 손실 (정적)

### 3.2 method_comparison Top 3
1. **RegimeSigma_MinCVaR**: 1.112 (Iter 2) — CAUTION/CRISIS 진입 시 weight 적응
2. RegimeSigma_MinCVaR_Cautious: 1.112 — variant (CAUTION confidence 30% shrink)
3. Blended_Sigma_MVO: 1.100 — regime probability weighted Σ (정적)

## 4. CRISIS Fallback Strategy (명시)

```
alpha_scale     = 0.0    (full shrinkage to zero — IC=-0.0466 contra-indicator)
sigma_source    = POOLED (T=5 fallback, δ=0.907 from Risk)
bounds_override = [0, 0.10] (tighter, 50% of normal bound)
optimizer       = MinVar (no alpha tilt — pure dispersion)
```

근거: AX-001 v2 (defense conditional) + RF-CRISIS-THIN (T=5) + RF-CRISIS-ALPHA-COUPLING (IC<0).

## 5. Regime Transition Cost Internalized

- Annual switch rate: 3.93/yr (Risk 측정)
- Estimated ann_turnover: **141.8%** (< 600% hard cap)
- Estimated ann_cost: 0.43%/yr
- Largest transition: NORMAL→CAUTION (Frobenius 0.093)
- 권고: 운용 시 regime label hysteresis (연속 2개월 동일 라벨 시만 switch) 고려

## 6. Hard Constraints Compliance

| | spec | achieved |
|---|---|---|
| max_names | ≤ 20 | 15 |
| weight_bounds | [0, 0.20] | [0.013, 0.107] |
| Σw | = 1 | 1.0000 |
| long-only | ≥ 0 | min 0.013 |
| HHI | ≤ 0.10 | 0.077 |
| Ann_TO | < 600% | 141.8% |

모든 hard constraint PASS. silent override 없음. infeasibility 없음.

## 7. Top 5 Overweights (CAUTION regime, current decision)

1. A058470 — 0.107 (max_w boundary)
2. A025540 — 0.107 (max_w boundary)
3. A007340 — 0.107 (max_w boundary, conf=0.95)
4. A166090 — 0.080
5. A047080 — 0.067 (conf=0.946)

## 8. References

- Rockafellar-Uryasev (2000) — CVaR LP
- Ang-Bekaert (2002) — regime conditional asset allocation
- Ledoit-Wolf (2004) — shrinkage covariance
- L-122 — factor timing risk-managed (Barroso&Santa-Clara 2015)
- AX-001 v2 — defense conditional crisis_alpha + MDD ratio
- AX-002 — process honesty (no silent override)
- QEPM §10 — conditional alpha
