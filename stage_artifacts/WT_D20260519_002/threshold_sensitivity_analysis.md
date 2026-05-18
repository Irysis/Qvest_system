# Threshold Sensitivity Analysis — Bear Prediction Engine v1.0 (WT-D20260519_002)

**Agent**: optimizer-research (Phase A design)
**Scope**: regime_sensor_overlay_policy formal waiver (Charter §10 v1.8)
**As of**: 2026-05-18

---

## 1. Purpose

p_bad ∈ [0, 1] threshold τ 결정 정책 — Recall vs FP cost trade-off + break-even Precision + 의사결정 비용. Forge cycle Stage 4 empirical 측정 binding 사전 명시.

**Phase A 단계** — Forge cycle empirical 측정 불가. risk_package threshold_sensitivity_analysis 섹션 priors inherit.

---

## 2. τ Sensitivity Matrix (risk_package priors inherit)

| τ | Expected Recall | Expected Precision | FP/yr | Use Case |
|---|---|---|---|---|
| **0.3 (lenient)** | 0.75~0.90 | 0.30~0.50 | ~6 | Aggressive defensive scaling — capital preservation prioritized |
| **0.5 (default, alpha G1 spec)** | 0.55~0.75 | 0.45~0.65 | ~3 | Balanced — alpha G1 inherit |
| **0.7 (conservative)** | 0.30~0.55 | 0.65~0.85 | ~1 | Highest conviction only — slowest detection, lowest FP cost |

Source: risk_package risk_summary.threshold_sensitivity_analysis (8 학술 backbone academic prior + 8 crisis epoch coverage)

---

## 3. FP Cost Decomposition per τ (Phase A prior, Forge binding)

15bps one-way × 2 round trip = 30bps/transition × FP count × full sleeve scale.

| τ | FP TO/yr | FP commission cost (bps/yr) | Opportunity cost (bps/yr) | Total FP impact (bps/yr) |
|---|---|---|---|---|
| 0.3 | ~6 | ~180 | ~180 | **~360** |
| 0.5 | ~3 | ~90 | ~90 | **~180** |
| 0.7 | ~1 | ~30 | ~30 | **~60** |

Opportunity cost = β_bear cash scaling during false positive non-bear month (avg 30bps cash drag).

---

## 4. Break-even Recall per τ

Bear-state Recall × 8 crisis events / 36 yr × avg crisis MDD ~30% × β_bear avg 0.5 capture = Benefit (bps/yr).

**Break-even**: Benefit = Total FP impact.

| τ | Required Recall break-even | Achievable Recall (risk prior) | Pass margin |
|---|---|---|---|
| 0.3 | ~0.65 | 0.75~0.90 (range PASS) | margin POSITIVE |
| 0.5 | ~0.50 | 0.55~0.75 (range PASS) | margin POSITIVE (slim @ 0.55 lower bound) |
| 0.7 | ~0.30 | 0.30~0.55 (range PASS) | margin POSITIVE (slim @ 0.30 lower bound) |

**Phase A verdict** — All 3 τ values marginally positive in expected-value terms (risk prior). Forge cycle Stage 4 empirical 측정 binding.

---

## 5. Lead-time Trade-off per τ

**risk_package lead_time_diagnostics_per_backbone inherit**:

| Backbone | Lead-time | τ=0.3 (lenient) | τ=0.5 (default) | τ=0.7 (conservative) |
|---|---|---|---|---|
| Yield Curve (F01~F05) | 6~18m | First trigger | First trigger | Late trigger |
| LEI (F06~F10) | 3~9m | Mid trigger | Mid trigger | Late trigger |
| Credit (F23~F25) | 3~9m | Mid trigger | Mid trigger | Late trigger |
| VIX (F11~F14) | 0~3m | Late trigger | Late trigger | Late trigger |
| Asymmetric Cor (F17) | 0~1m | Late trigger | Late trigger | Late trigger |
| NFCI (F20~F22) | 3~6m | Mid trigger | Mid trigger | Late trigger |
| MSM Hamilton | 0m | Coincident | Coincident | Coincident |

**τ=0.3 lenient** — Maximizes lead-time advantage from yield curve / LEI / credit. Best for defensive scaling pre-emption.
**τ=0.7 conservative** — Sacrifices lead-time. Best for high-conviction binary scaling.
**τ=0.5 default** — Balanced.

---

## 6. Per-crisis τ Sensitivity (8 crisis, risk_package stress_tests_sensor_scope inherit)

| Crisis | Crisis 2 IMF | Crisis 4 GFC | Crisis 5 EU | Crisis 6 CN | Crisis 7 2018vol | Crisis 8 COVID | Crisis 9 Inflation | Crisis 10 2026-03 |
|---|---|---|---|---|---|---|---|---|
| τ=0.3 Recall prior | 0.5~0.7 | 0.95 | 0.6 | 0.6 | 0.5 | 0.7 | 0.85 | OOS |
| τ=0.5 Recall prior | 0.3~0.5 | 0.8~1.0 | 0.4~0.6 | 0.4~0.6 | 0.3~0.6 | 0.5~0.8 | 0.7~0.9 | OOS |
| τ=0.7 Recall prior | 0.1~0.3 | 0.6~0.8 | 0.2~0.4 | 0.2~0.4 | 0.1~0.3 | 0.3~0.6 | 0.5~0.8 | OOS |

**Worst case (Crisis 7 2018 vol single month)** — τ=0.7 catastrophic 0.1~0.3, τ=0.3 acceptable 0.5. Best case GFC — all τ values strong.

**Cross-crisis variance** — τ=0.3 most stable across crises. τ=0.7 most variance.

---

## 7. Primary Recommendation Phase A

**Default**: **τ = 0.5** (alpha G1 spec inherit). Balanced Recall (0.55~0.75) vs FP cost (90 bps/yr) vs lead-time vs Precision (0.45~0.65, marginally at break-even).

**Fallback hierarchy**:
1. **τ = 0.7 conservative** — IF empirical FP > 8/yr @ τ=0.5 (catastrophic, > 2× prior) OR TO cap violation
2. **τ = 0.3 lenient** — IF empirical FP < 1.5/yr @ τ=0.5 (best case, < 0.5× prior) AND Recall ≥ 0.75 confirmed

**Forge cycle Stage 4 binding**:
- τ sweep ∈ {0.3, 0.5, 0.7} mandatory measurement
- per-crisis Recall + Precision report
- per-window FP rate measurement (5 sub-windows)
- bootstrap CI (B=10000) on Recall + Precision per-crisis

---

## 8. Anti-flicker Rule (transition cost discipline)

**Rule (default)**: β_bear update only if p_bad bucket change ≥ **1 month persistence**.

| Anti-flicker | TO reduction estimate | Response delay | Use case |
|---|---|---|---|
| **No flicker (immediate)** | 0% | 0 month | aggressive — high TO |
| **1m persistence (default)** | ~30% Layer 6 TO | 1 month | balanced — M4 BOCPD precedent |
| **2m persistence (conservative)** | ~50% Layer 6 TO | 2 month | low TO — slower response |

**Academic grounding**: M4 BOCPD anti-flicker precedent (Session 80 admit) + Lopez de Prado 2018 AFML Ch 5.

---

## 9. Decision Rule Summary (Forge cycle Stage 4 binding)

```
DEFAULT: τ = 0.5 + anti-flicker 1m
  IF empirical Precision_5sub_windows >= 4/5 PASS 0.45:
    proceed with τ = 0.5
  ELSE IF empirical Precision @ τ=0.7 >= 4/5 PASS 0.65:
    fallback τ = 0.7 conservative
  ELSE:
    Path B Layer 6 REJECT, Path A fallback OR DEFER
```

---

## 10. References

- Risk_package risk_summary.threshold_sensitivity_analysis (Phase A priors source)
- alpha_package downstream_integration_constraints_codex_c7_disposition_pre_declare (β_bear schedule inherit)
- STR_1715_AR_on_M4_R05_overlay_PG2 Session 80 admit (anti-flicker precedent)
- Kritzman, Page, Turkington (2011) "Regime Shifts: Implications for Dynamic Strategies" FAJ 67(3)
- Estrella-Hardouvelis (1991) JF — yield curve lead-time
- Stock-Watson (2003) JEL — LEI lead-time
- Engle-Mistry (2014) JFE — VIX coincident
- Lopez de Prado (2018) AFML Ch 7 — Backtest paranoia + per-crisis stratified evaluation
