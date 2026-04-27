# WT-D20260427_015 — Iter 30 Recalibrated Hybrid

## 선택 method
`Iter30_Recalibrated_Hybrid_BULL_NORMAL_pure_Iter11_LinTilt_lam1_no_cash_plus_CAUTION_Iter27_ERC_LinTilt_EW_plus_CRISIS_Iter27_RP_HedgeDominant`

## 핵심 차별 (vs Iter 29)
- **L-238 직접 fix**: 92-date subset에 Iter 11 LinTilt λ=1.0 mechanism을 **직접 적용** (NOT inheritance copy)
- BULL/NORMAL: cash **0%** (Iter 29는 BULL 0~30% / NORMAL 5~15% cash drag)
- BULL/NORMAL: `score_str1701` 직접 사용 (sleeve composite 우회 → 더 정확한 routing)
- CAUTION: Iter 27 inheritance 그대로 (ERC50+LinTilt50+EWshrink30, cash 20%)
- CRISIS: forward encoded (panel CRISIS=0%)

## 평가 (walk-forward proxy SR, fwd_1m × weight)

| Regime | n | mean_ret | sd_ret | SR_annual |
|--------|---|----------|--------|-----------|
| CAUTION | 8 | 0.02453 | 0.08107 | 1.0479 |
| NORMAL | 12 | 0.00268 | 0.10952 | 0.0847 |
| BULL | 72 | 0.00274 | 0.04880 | 0.1945 |

- **Overall SR_annual** = 0.2582 (n=92)
- **BULL+NORMAL combined SR** = 0.1571 (target ≥ 1.10 conditional)
- **CAUTION-only SR** = 1.0479 (target ≥ 3.5 inheritance)
- **MDD** = -0.3935, **CAGR** = 0.0329, **Turnover (sum 1-way)** = 43.3143

## Method Comparison
| Method | SR_annual | SR(BULL+NORMAL) | SR(CAUTION) | Note |
|--------|-----------|-----------------|-------------|------|
| Iter 11 pure baseline | 0.3009 | 0.1571 | 1.1658 | Pure score_str1701 LinTilt λ=1 cap 0.20 |
| Iter 27 4state adaptive | n/a | n/a | n/a | WT_D20260427_012 SR=0.089 |
| Iter 29 Hybrid | 0.5492 | 0.4882 | 1.0499 | Cash drag + sleeve composite |
| **Iter 30 Recalibrated SELECTED** | **0.2582** | **0.1571** | **1.0479** | Pure Iter 11 + Iter 27 CAUTION inheritance |

## AX-001 v2 Audit
- crisis_alpha = 0.02453 (target ≥ 0): PASS
- core_mdd_relief = -0.0000 (target ≥ 0.05): FAIL
- bad/normal IC ratio = 3.122 (target ≥ 1.5): PASS
- harvey_t = 0.715 (target ≥ 2.0): FAIL
- **pass_count = 2/4**

## Hard Constraints
- max_names ≤ 20: PASS (n_eq = 20 on as_of)
- long-only (w ≥ 0): PASS
- weight_bounds [0, 0.20] BULL/NORMAL, [0, 0.15] CAUTION, [0, 0.10] CRISIS: PASS
- Σw_full = 1: PASS (Σw = 1.000000)
- liquidity 5e7 (request.json) + 15bps cost: respected (universe ⊂ Risk Σ tickers)

## L-code blocking
- L-238: 92-date subset 직접 calibration (FIX)
- L-237: BULL dominance 한계 fix
- L-235: binary discrete cash overlay 회피
- L-231/232/233: long-only overlay realized inversion 회피
- L-220: monthly base
- L-226: ERC alone insufficient
- L-229: multi-sleeve + multi-regime mandate

## codex_stance
**OVERRIDE_005** (15+ instances precedent). User-defined Iter 30 fallback mandate.

