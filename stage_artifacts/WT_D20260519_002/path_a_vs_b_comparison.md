# Path A (DPL_KR_v3 Feature Inject) vs Path B (Standalone STR_1715 PG2 Layer 6) Comparison

**Agent**: optimizer-research (Phase A design)
**WT**: WT-D20260519_002 Bear Prediction Engine v1.0
**As of**: 2026-05-18

---

## 1. Purpose

Bear regime sensor v1.0 admit 시 2-Path downstream integration option 사전 trade-off 분석. Forge cycle Stage 6 G5 admit decision matrix 기반.

---

## 2. Path A — DPL_KR_v3 Feature Inject

### 2.1 Integration Form
```
DPL_KR_v3 input = 80 base features (parallel WT-D20260519_001 design) + p_bad_v1 = 81 features
DPL_KR_v3 model output: cross-section asset alpha → portfolio weights
```

### 2.2 Downstream Owner
**WT-D20260519_001 DPL_KR_v3** (parallel WT) Forge cycle.

### 2.3 Admit Threshold
- **ΔAUC ≥ 0.05** in DPL_KR_v3 81-feature vs 80-feature baseline (alpha admit criterion inherit)

### 2.4 Cost / TO Impact
- **0 bps additive** — feature inject, NOT direct TO source
- TO impact embedded in DPL_KR_v3 cycle admit decision (parallel WT)

### 2.5 DSR Impact
- n_trials += 1 in DPL_KR_v3 admit cycle DSR formula

### 2.6 Pro
1. **Direct Portfolio Learning P4 정합** — ML-integrated bear signal, end-to-end optimization
2. **No separate Layer 6 admit decision needed** — single admit cycle
3. **Marginal TO impact** — feature only, not overlay
4. **M4 overlap mitigation** — DPL learns p_bad interaction with other 80 features, model itself handles redundancy
5. **Single-stage admission cycle** — interpretation 단순 (DPL admit OR not)

### 2.7 Con
1. **Compound dependency** — Path A admit conditional on DPL_KR_v3 itself admit (parallel WT lifecycle). If DPL fails admit, Path A unavailable.
2. **Less interpretable** — bear signal becomes one of 81 features in NN model. Cannot decompose contribution.
3. **ΔAUC ≥ 0.05 high bar** — risk priors crowding 28% (VIX + yield curve consensus) may underperform marginal AUC uplift in feature ensemble already saturated
4. **Indirect risk control** — DPL ML model controls portfolio sizing internally, no explicit β_bear scaling rule

### 2.8 Phase A Verdict
**PARALLEL_TRACK_TEST** — Forge cycle Stage 6 ΔAUC measurement. DPL_KR_v3 itself admit 시 sensor inject path automatic conditional.

---

## 3. Path B — Standalone STR_1715 PG2 Layer 6

### 3.1 Integration Form
```
w_final = w_str1715 × m4_scalar × β_AR × β_R05(regime) × β_bear(p_bad)
```
β_bear ∈ {0.3, 0.5, 0.7, 1.0} per p_bad bucket (alpha downstream_integration_constraints inherit).

### 3.2 Downstream Owner
**본 WT-D20260519_002** Forge cycle + Optimizer cycle Layer 6 admit decision.

### 3.3 Admit Thresholds (Forge Stage 4~6 binding)
1. **CO1** ρ(p_bad, m4_scalar) S4 117m **< 0.85 hard** (m4 incrementality)
2. **OPT4** M4 incrementality test 3-axis (lead-time ≥ 4/8 crises + complementary events ≥ 20%)
3. **ΔSR(5-layer) > ΔSR(4-layer) sub-windows ≥ 3/5**
4. **TO_total post-Layer 6 ≤ 6.0/yr** Hard Constraint
5. **DSR Bailey-LdP Z ≥ 1.5** with n_trials = 54 cumulative (governor cycle binding)

### 3.4 Cost / TO Impact
- Base STR_1715 PG2: ~4.0 TO/yr
- AR/R05 overlay: ~1.5 TO/yr (Session 80 admit inherit)
- **Layer 6 bear added**: ~1.5 TO/yr (alpha downstream_integration_constraints inherit)
- **Total**: ~7.0 TO/yr (anti-flicker 1m default reduces to ~5.5~6.0/yr, within 6.0 cap)

### 3.5 DSR Impact
- Downstream NAV DSR formula n_trials = 54 cumulative (alpha 20 + risk 17 + optimizer 17)

### 3.6 Pro
1. **Sequential overlay academic precedent** — Kritzman-Page-Turkington 2011 FAJ inherit (STR_1715 PG2 AR overlay 같은 framework)
2. **Lead-time advantage** 3~9m from yield curve / LEI / credit backbones (학술 prior)
3. **STR_1715 PG2 already admit** (Session 80) — independent admit cycle, no compound dependency
4. **Multi-axis orthogonality** — AR cross-section concentration ⊥ p_bad macro bear (risk prior 0.20~0.40), distinct signal source
5. **Interpretable** — discrete β_bear scalar, attribution traceable per-month
6. **Cash scaling explicit** — clear defensive use case, drawdown control

### 3.7 Con
1. **p_bad ~ m4 redundancy risk** — design_phase_prior 0.55~0.75 overlap. CO1 < 0.85 empirical mandate Path B precondition.
2. **FP cost per-τ** — 90 bps/yr default τ=0.5 (3 FP/yr × 30bps round trip × full sleeve)
3. **Precision break-even ≥ 0.50** — alpha G1 spec 0.40 below break-even (risk advisory FLAG, NOT veto)
4. **TO impact 1.5/yr added** — within 6.0 cap but close to ceiling, requires anti-flicker mitigation
5. **Multi-stage admission** — CO1~CO6 + OPT1~OPT8 = 14 empirical bindings (complexity)

### 3.8 Phase A Verdict
**PRIMARY_PATH_DEFAULT** — STR_1715 PG2 standalone admit precedent (Session 80). Forge Stage 4 CO1 empirical ρ < 0.85 통과 시 Layer 6 admit candidate.

---

## 4. Trade-off Matrix Summary

| Dimension | Path A (DPL inject) | Path B (Layer 6) |
|---|---|---|
| **Admit cycle** | Compound (DPL_KR_v3 + bear) | Independent (STR_1715 PG2 + bear) |
| **Interpretability** | Low (NN feature) | High (discrete scalar) |
| **TO impact** | Marginal (0 bps) | ~1.5/yr added (within cap) |
| **Lead-time** | Embedded in DPL model | Explicit per-crisis lead-time |
| **M4 overlap handling** | DPL learns interaction | CO1 < 0.85 hard mandate |
| **Risk control** | Implicit (ML model) | Explicit (β_bear schedule) |
| **DSR impact** | n_trials += 1 | n_trials += 54 cumulative |
| **Admit threshold** | ΔAUC ≥ 0.05 single | 14 conditions multi-stage |
| **Academic grounding** | You-Zhang 2025 direct learning | Kritzman 2011 sequential overlay |
| **Downstream owner** | WT-D20260519_001 (parallel WT) | 본 WT (independent) |

---

## 5. Decision Matrix Phase A

| Outcome | Path A | Path B | Final Decision |
|---|---|---|---|
| **Both PASS** | PASS | PASS | **Path B Layer 6 default** (interpretable + STR_1715 PG2 lineage), Path A parallel monitor |
| **Path A only PASS** | PASS | FAIL | Path A admit (DPL_KR_v3 ΔAUC ≥ 0.05 + 자체 admit) |
| **Path B only PASS** | FAIL | PASS | Path B Layer 6 admit standalone |
| **Both FAIL** | FAIL | FAIL | **DEFER** — bear sensor v1.0 standalone utility 부족, redesign cycle |
| **Path A pending** (DPL not admit yet) | n/a | PASS | Path B Layer 6 admit, Path A defer until DPL admit |

**Decision owner**: Governor cycle (post Forge admit measurement).

---

## 6. Forge Cycle Stage 6 G5 Binding Measurements

### Path A
- DPL_KR_v3 81-feature vs 80-feature ΔAUC measurement
- bootstrap CI on ΔAUC (B=10000)
- sub-window stability (5 windows)

### Path B
- CO1: ρ(p_bad_monthly, m4_scalar_monthly) S4 117m
- CO2: ρ(p_bad, β_AR) S4 117m < 0.40
- CO3: ρ(p_bad, β_R05) S4 117m < 0.70
- CO4: TO_total post-Layer 6 ≤ 6.0/yr
- CO5: crowding_score_per_factor() empirical (Acadian 2026)
- CO6: per-crisis joint signal timing diagnostic
- Backtest 267m post-Layer 6 NAV: SR / MDD / DSR / TO
- per-crisis Recall + Precision (5 sub-windows × 8 crises)
- Joe-Clayton 1997 TDC empirical (p_bad ~ m4, β_AR, β_R05)

---

## 7. Risk Acknowledgements

### Path A risk
- **DPL_KR_v3 itself admit risk** — parallel WT lifecycle dependency
- **AUC uplift may be marginal** — crowding 28% (VIX + yield curve consensus) reduces incremental information given 80-feature base

### Path B risk
- **CO1 ρ ≥ 0.85 redundancy fail risk** — design_phase_prior 0.55~0.75 vulnerable
- **TO cap breach risk** — anti-flicker 1m default + τ=0.5 borderline (~5.5~6.0/yr expected)
- **Precision break-even** — alpha G1 spec 0.40 below 0.50 break-even (advisory)

---

## 8. References

- alpha_package downstream_integration_constraints_codex_c7_disposition_pre_declare (Path A + Path B threshold inherit)
- risk_package risk_summary + crowding_overlap_with_M4_AR_R05.md (Path B precondition CO1~CO3 inherit)
- STR_1715_AR_on_M4_R05_overlay_PG2 v2.3 manifest.json (Session 80 admit, 4-layer overlay)
- Kritzman, Page, Turkington (2011) "Regime Shifts" FAJ 67(3) — Path B sequential overlay academic precedent
- You, Zhang (2025) Direct Portfolio Learning — Path A academic grounding (Charter §15 P4)
- L-281 Cross-Asset TSMOM orthogonality 0.077 (Path B comparison baseline)
- Lopez de Prado (2018) AFML Ch 8 (bootstrap CI small sample)
