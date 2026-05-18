# M4 Incrementality Protocol — Bear Sensor vs M4 BOCPD Overlay (WT-D20260519_002)

**Agent**: optimizer-research (Phase A design)
**Critical**: Path B Layer 6 admit precondition (CO1)
**As of**: 2026-05-18

---

## 1. Purpose

p_bad_monthly ~ m4_scalar_monthly **design_phase_prior overlap 0.55~0.75** (risk_package + crowding_overlap_with_M4_AR_R05.md inherit). If redundant, Layer 6 adds TO cost without incremental detection. Path B admit precondition empirical 측정 binding.

Forge cycle Stage 4 mandatory:
- Empirical ρ measurement on S4 117m period
- Joe-Clayton 1997 TDC parametric copula fit
- Per-crisis lead-time decomposition
- Complementary event ratio

---

## 2. Core Problem Statement

```
m4_scalar (already admit Session 80, BOCPD on KOSPI200 BM_Ret 1m/3m)
  ⟂?
p_bad (new, 32 features × 8 학술 backbone × 5-model ensemble)
```

Both detect regime shift. Question: **p_bad provides incremental signal beyond m4 BOCPD?** OR **p_bad is just smoothed m4?**

---

## 3. Three-Axis Incrementality Test

### Axis 1 — Correlation Empirical Measurement
- **Test**: Pearson ρ(p_bad_monthly, m4_scalar_monthly) on S4 117m period (2016-09 ~ 2026-05)
- **Hard threshold**: ρ < **0.85** (CO1 binding)
- **Preferred threshold**: ρ < **0.70** (clearly distinct)
- **Marginal zone**: 0.70 ≤ ρ < 0.85 — admit conditional on Axis 2 + Axis 3 PASS
- **TDC empirical binding** (Codex risk C4 reinforced):
  - Joe-Clayton 1997 + copula::tCopula parametric fit on (p_bad, m4_scalar) S4 117m
  - Lower tail dependence λ_L
  - Upper tail dependence λ_U
  - **Flag** if λ_L ≥ 0.5 (high tail co-dependence — both trigger at same crises)

### Axis 2 — Lead-time Diagnostic (per crisis)
- **Test**: For each of 8 crises, compute:
  - First m4 regime change (CAUTION trigger or beyond)
  - First p_bad ≥ τ (default τ=0.5)
  - Lead-time gap: `lead_time = first_m4_change - first_p_bad_crossing` (positive = p_bad leads)
- **Expected p_bad advantage**: **3~9 months** (학술 prior — yield curve / LEI / credit backbones)
- **Expected m4 advantage**: **0~3 months** (BOCPD reacts faster to coincident vol)
- **PASS criterion**: p_bad leads m4 by ≥ **3 months** in ≥ **4/8 crises** (academic backbone validation)
- **FAIL criterion**: p_bad lags m4 in ≥ **5/8 crises** (no incremental value, REJECT Layer 6)

### Axis 3 — Complementary Event Capture
- **Test**: Event ratio
  - Total bear-state months (S4 117m): N_bear
  - Months with p_bad ≥ τ but m4 = NORMAL/BULL: N_pbad_only
  - Months with m4 = CAUTION/CRISIS but p_bad < τ: N_m4_only
  - Months with both trigger: N_both
- **Expected pattern**: yield curve inversion event (e.g., 2007-Q3) — p_bad ≥ 0.5 but m4 still BULL (FF return positive lagging signal)
- **PASS criterion**: `N_pbad_only / N_bear ≥ 0.20` (≥ 20% unique events from p_bad)
- **Interpretation**:
  - If most p_bad triggers coincide with m4 changes → **redundant**
  - If ≥ 20% unique events → **incremental**

---

## 4. Decision Rule (Forge Stage 4 binding)

```
IF Axis 1 (ρ < 0.85 hard) AND Axis 2 (≥ 4/8 lead-time) AND Axis 3 (≥ 20% unique events):
    Path B Layer 6 ADMIT CANDIDATE (combined with other hurdles OPT5/OPT6)

ELSE IF 2/3 PASS AND Axis 1 PASS (critical):
    MARGINAL_ADMIT — Optimizer cycle sequential overlay justification 의무 (Codex round 평가)

ELSE IF Axis 1 FAIL (ρ ≥ 0.85):
    Path B REJECT — Path A (DPL_KR_v3 feature inject) fallback

ELSE IF 0/3 PASS:
    DEFER — bear sensor v1.0 redundant with M4 BOCPD, redesign cycle
```

---

## 5. Expected Empirical Patterns per Crisis (risk priors inherit)

### Region 1 — 2008 GFC (S2~S3, outside S4 117m primary scope but reference)
- m4_scalar: NORMAL → CAUTION → CRISIS transition expected 2008-08~2008-10
- p_bad@τ=0.5: expected ≥ 0.5 from 2008-01 (yield curve inversion 2007-Q3 prior signal)
- **Lead-time overlap**: p_bad lead m4 by 3~6 months expected
- **Information overlap**: ~70% in 2008-10 peak (both crisis trigger)
- **Verdict prior**: Axis 2 PASS (lead-time), Axis 3 PASS (early yield curve signal)

### Region 2 — 2018 vol spike (S3~S4)
- m4_scalar: BOCPD may trigger CAUTION 2018-10 only (vol surge)
- p_bad@τ=0.5: **weak signal** (학술 backbone underperforms — risk advisory FLAG Crisis 7)
- **Overlap**: ~30~50% — m4 detects vol cluster but bear sensor weak
- **Verdict prior**: Axis 2 marginal, Axis 3 FAIL (bear sensor underdetects)

### Region 3 — 2020 COVID (S4 primary)
- m4_scalar: BOCPD fast trigger 2020-02 (VIX surge)
- p_bad@τ=0.5: full feature set, expected ≥ 0.7 around 2020-02
- **Lead-time gap**: 0~1 month (coincident — pandemic shock fast)
- **Overlap**: ~80%~90% (both fast trigger)
- **Verdict prior**: Axis 2 marginal (coincident, not leading), Axis 3 marginal

### Region 4 — 2022 inflation (S4 primary)
- m4_scalar: trigger 2022-Q2 (rate hike cycle)
- p_bad@τ=0.5: expected ≥ 0.7 from 2022-Q1 (yield curve + credit + LEI all show)
- **Lead-time gap**: 1~3 months (p_bad leads)
- **Overlap**: ~60%
- **Verdict prior**: Axis 2 PASS, Axis 3 PASS (early inflation detection)

### Region 5 — 2026-03 recent OOS
- m4_scalar: production live (NORMAL/CAUTION TBD)
- p_bad@τ=0.5: pure OOS — Forge measurement post-train
- **Verdict prior**: PURE_OOS_VALUABLE for Forge Stage 4

### S4 117m aggregate prior
- p_bad ~ m4 design_phase_prior cor: **0.55~0.75** (risk_package)
- ≥ 4/8 lead-time pass expected (학술 backbone strong)
- ~30~40% unique events expected
- **Aggregate verdict prior**: PARTIAL_INCREMENTAL — Path B admit candidate IF Axis 1 < 0.85

---

## 6. Academic Grounding

- **Kritzman, Page, Turkington (2011) FAJ 67(3)** — sequential overlay academic precedent. Layer 4 AR overlay (Session 80) inherited this framework — independent value test 의무.
- **L-281 Cross-Asset TSMOM** — ρ 0.077 empirical baseline (cross-section vs time-series orthogonality). 본 cycle p_bad ~ m4 보다 훨씬 distinct example.
- **Lopez de Prado (2018) AFML Ch 6** — sample weight + uniqueness. Overlapping signal handling.
- **Engle-Mistry (2014) JFE** volatility regime vs **Estrella-Hardouvelis (1991) JF** yield curve — distinct mechanisms, distinct lead-times.
- **Joe-Clayton (1997)** Multivariate Models and Dependence Concepts — TDC empirical framework.

---

## 7. Forge Cycle Stage 4 Binding Operations

```
Stage 4 Operation Sequence (post 5-model ensemble train + p_bad_monthly emit):

1. Compute p_bad_monthly on S4 117m (2016-09 ~ 2026-05)
2. Load m4_scalar_monthly on same period (STR_1715 PG2 v2.3 manifest)
3. Pearson ρ(p_bad_monthly, m4_scalar_monthly) + bootstrap CI (B=10000)
4. Joe-Clayton 1997 + copula::tCopula tail dependence λ_L, λ_U
5. Per-crisis (8 crises) lead-time decomposition
6. Complementary event count + ratio
7. Report axis-by-axis PASS/FAIL
8. Composite decision per § 4 above
```

**Output**: `stage_artifacts/WT_D20260519_002/m4_incrementality_empirical.md` (Forge cycle binding).

---

## 8. Risk Acknowledgements

- **S4 117m period** — only 117 monthly obs. Bootstrap CI conservative (Lopez de Prado 2018 AFML Ch 8 small-n).
- **CRISIS regime n=3** within S4 (267m STR_1715 PG2 decomposition, ratio 0.011) — Codex C3 disposition fallback protocol inherit (pooled CAUTION+CRISIS n=18 fallback).
- **2018 vol Crisis 7** known weak coverage — per-crisis prior may dominate Axis 3 statistic. **8-crisis stratified per-crisis report binding** (not just aggregate).

---

## 9. References

- risk_package crowding_overlap_with_M4_AR_R05.md (overlap priors inherit)
- crowding_overlap_with_M4_AR_R05.md Section 2~4 (mechanism orthogonality)
- STR_1715_AR_on_M4_R05_overlay_PG2 v2.3 manifest (m4_scalar production inherit, 267m)
- Kritzman-Page-Turkington (2011) FAJ — sequential overlay precedent
- Joe-Clayton (1997) — TDC framework
- L-281 — orthogonality baseline
- Lopez de Prado (2018) AFML Ch 6 + Ch 8
