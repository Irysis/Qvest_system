# Crowding Overlap with M4/AR/R05 — WT-D20260519_002 Bear Prediction Engine v1.0

**Agent**: risk-research (regime_sensor crowding scope)
**As-of**: 2026-05-18
**Scope**: Bear sensor (p_bad) vs existing admit regime signals (M4 BOCPD / AR threshold / R05 tail trigger) orthogonality + crowding diagnostic
**Authority**: Risk diagnostic only — signal 추가/제거/weight 결정 금지.

---

## 1. Audit Philosophy

STR_1715 PG2 production v2.3 (2026-05-13 admit, manifest.json) 4-layer regime overlay system:
```
w_final = w_str1715 × m4_scalar × β_AR × β_R05(regime)
```

본 cycle bear sensor (p_bad ∈ [0,1]) standalone admit (Codex C7 Path B) 시 **Layer 6** 추가:
```
w_final = w_str1715 × m4 × β_AR × β_R05 × β_bear(p_bad)
```

**핵심 risk question**: 이 5-layer overlay system의 **signal cor + factor crowding + redundancy** 진단.
- p_bad와 m4_scalar의 **information overlap** — duplicate detection?
- p_bad와 β_AR의 cross-section concentration trigger 차이
- p_bad와 β_R05의 tail event trigger 차이
- 8 학술 backbone의 **factor crowding** (Acadian 2026 Research Philosophy P5)

---

## 2. Existing Admit Signals — Mechanism Comparison

| Signal | Type | Source | Trigger basis | Output domain |
|---|---|---|---|---|
| **m4_scalar** | regime trend (1-dim) | BOCPD on KOSPI200 BM_Ret 1m/3m | Bayesian Change Point Detection | {BULL=1.0, NORMAL=1.0, CAUTION=0.5, CRISIS=0.3} |
| **β_AR** | cross-section concentration (2-dim) | K=5 top eigenvalue ratio (Kritzman-Page-Turkington 2011 FAJ) | concentration > q90 threshold | {0.4, 0.7, 1.0} |
| **β_R05** | tail risk overlay (cash control) | Kelly-Jiang 2014 tail measure + regime conditional | regime_t state | {BULL=1.0, NORMAL=1.0, CAUTION=0.5, CRISIS=0.3} (sequential cash) |
| **p_bad (NEW)** | bear regime classifier (multi-dim) | 8 학술 backbone × 32 features × 5-model ensemble | p ≥ τ ∈ {0.3, 0.5, 0.7} | continuous [0,1] → β_bear ∈ {0.3, 0.5, 0.7, 1.0} |

**Orthogonality prior** (학술 framework 기반):

| Pair | Expected ρ | Mechanism overlap | Verdict |
|---|---|---|---|
| **p_bad vs m4_scalar** | **0.50~0.70** | both detect regime shift, but p_bad uses 32 macro features vs m4 uses 1 BM_Ret series. partial overlap | medium-high cor expected |
| **p_bad vs β_AR** | **0.20~0.40** | β_AR is cross-section concentration (Mahalanobis distance Kritzman 2011), p_bad is forward bear probability. distinct axes | low-medium cor expected |
| **p_bad vs β_R05** | **0.40~0.60** | β_R05 uses tail measure (Kelly-Jiang 2014) regime conditional, p_bad has VIX/credit/yield curve. medium overlap | medium cor expected |
| **m4 vs β_AR** | empirical 0.077 (L-281) | distinct axes (trend vs cross-section) | proven distinct |
| **m4 vs β_R05** | unknown | both regime-state | possibly overlap |

**Risk diagnosis**:
- **p_bad ~ m4_scalar overlap concern**: 둘 다 regime shift detection. p_bad가 m4보다 strictly more information (32 features vs 1 series) → m4를 dominate 또는 redundant 가능성.
- **Forge cycle empirical cor measurement binding** (alpha admit Path B precondition): if `cor(p_bad_monthly, m4_scalar_monthly) > 0.85` over 117 monthly S4 period → **redundancy flag** → Path B Layer 6 admit 재검토.
- **p_bad ~ β_AR distinct** expected (학술 framework 다름) → Layer 6 의미있는 orthogonal source 추가 가능.

---

## 3. Bear Sensor vs M4 BOCPD Empirical Overlap Audit (Forge cycle binding)

본 risk agent는 empirical cor measurement 미수행 (Forge cycle binding). 하지만 **expected overlap regions** prior:

### Region 1: 2008 GFC (S2~S3)
- m4_scalar: NORMAL → CAUTION → CRISIS transition expected 2008-08~2008-10
- p_bad@τ=0.5: expected ≥ 0.5 from 2008-01 (yield curve inversion 2007-Q3 prior signal)
- **Lead-time overlap**: p_bad lead m4 by 3~6 months expected
- **Information overlap**: ~70% in 2008-10 peak (both crisis)

### Region 2: 2018 vol spike (S3~S4)
- m4_scalar: BOCPD may trigger CAUTION 2018-10 only
- p_bad@τ=0.5: weak signal (학술 backbone underperforms — feature_stability_audit Crisis 7)
- **Overlap**: ~30~50% — m4 detects vol cluster but bear sensor weak

### Region 3: 2020 COVID (S4)
- m4_scalar: BOCPD fast trigger 2020-02 (VIX surge)
- p_bad@τ=0.5: full feature set, expected ≥ 0.7 around 2020-02
- **Lead-time match**: 0~1 month — both coincident
- **Information overlap**: ~80~90% in 2020-02 (both signal extreme)

### Region 4: 2022 inflation (S4)
- m4_scalar: BOCPD detects 2022-06 + 2022-09 spikes
- p_bad@τ=0.5: backbone optimal match (yield curve inverted + credit spread)
- **Overlap**: ~70% — both signal but bear sensor possibly leads

**Expected overall cor** (S4 period 2016-09~2026-05, 117m where both ON):
- **ρ(p_bad_monthly, m4_scalar_monthly) ∈ [0.55, 0.75]** prior

**Risk Verdict**: 
- ρ < 0.70 → orthogonal enough, Layer 6 admit candidate
- ρ ≥ 0.85 → redundancy flag (Path B reject candidate)
- ρ ∈ [0.70, 0.85] → marginal — Optimizer Path B sequential overlay justification 의무 (Codex round 평가)

---

## 4. Factor Crowding Score per Backbone (Acadian 2026 Research Philosophy P5)

8 학술 backbone의 **crowding flag** — multi-axis crowding risk:

| Backbone | Features | Crowding axes | Crowding flag |
|---|---|---|---|
| **F01~F05 Yield Curve** | yield slope | global macro consensus indicator, **very crowded** (institutional FED watching) | **HIGH 0.85** |
| **F06~F10 LEI** | PMI/Housing/etc | published macro indicator, **moderately crowded** | medium 0.55 |
| **F11~F14 VIX** | volatility | **most crowded vol risk indicator globally** | **HIGH 0.90** |
| **F17 Asymmetric cor** | down-market correlation | less mainstream, niche academic | LOW 0.30 |
| **F20~F22 NFCI** | financial conditions | Fed publishes, regional Fed indices | medium 0.50 |
| **F23~F25 Credit spread** | corporate spreads | mainstream institutional indicator | **HIGH 0.75** |
| **F26~F28 SEFRS** | KR ETF flow | SEFRS Phase A inherit (WT-D20260518_001) **moderately crowded** | medium 0.65 |
| **F29~F30 Foreign flow** | KRX investor type | KR public data, daily watched | medium 0.55 |
| **F31~F32 Defensive rotation** | sector spreads | academic Frazzini-Pedersen 2014 framework | medium 0.45 |

**Crowding-weighted ensemble**:
- 32 features weighted by inverse-crowding → less-crowded features (F17, F31, F32) gain more relative weight
- **NOT** alpha decision — risk recommendation only
- Forge cycle Stage 3 LightGBM gain importance × (1 - crowding_score) = effective uniqueness score

**Risk diagnosis**: 
- **F11~F14 VIX cluster** (4 features) = 0.90 crowding × 4 features = **concentrated crowding cluster**
- **F01~F05 Yield curve cluster** (5 features) = 0.85 × 5 = **most concentrated crowding cluster**
- 두 cluster 합쳐 9/32 features (28%) high-crowding → 본 sensor의 ~30% information is "consensus regime" not "alpha edge"
- **Implication**: bear sensor가 작동할 때 = **모든 institutional player가 동시에 detect** → KOSPI200 sell-off 시 본 sensor가 emit하는 timing = market consensus timing, **alpha lead 적음**

**Counter-argument** (학술 정합):
- Recession prediction 자체가 consensus signal — yield curve / VIX / credit spread는 **policy-relevant macroeconomics** 정합
- Forge cycle G1 Recall ≥ 0.60 mandate가 commit되면 본 sensor의 utility는 **timing not alpha edge** — defensive scaling 의 정합 use case
- Codex C7 Path B β_bear schedule = defensive (NOT offensive) use → crowding cluster 인정 가능

---

## 5. Path B Layer 6 Admit Decision Risk Recommendation

Codex C7 disposition Path B β_bear schedule integration analysis:

### Pro (admit 정합)
- p_bad ⊥ β_AR (cross-section concentration ⊥ macro bear) → orthogonal source 추가
- Lead-time 3~6m on yield curve / credit (학술 prior) → m4 보다 빠른 detection
- 8 학술 backbone academic prior strong (Estrella + Stock-Watson + Gilchrist)

### Con (admit 우려)
- **p_bad ~ m4_scalar overlap 0.55~0.75 prior** — redundant overlay concern (Forge cycle empirical binding)
- **F11~F14 + F01~F05 VIX + yield curve crowding cluster 28%** — consensus signal, alpha edge 약함
- TO impact estimate +1.5/yr (alpha downstream_integration_constraints) → STR_1715 PG2 base 4.0/yr + AR 1.5/yr (이미 추정) + bear sensor 1.5/yr = 5.5/yr (within 6.0 cap, marginal)

### Risk Verdict
**ADMIT_CONDITIONAL** (Forge cycle binding):
1. Forge Stage 4 empirical: ρ(p_bad, m4_scalar) S4 period **< 0.85** mandatory
2. Forge Stage 4 empirical: ρ(p_bad, β_AR) S4 period **< 0.40** mandatory (orthogonality preserved)
3. Forge Stage 4 empirical: TO_total post-Layer 6 **≤ 6.0/yr** strict (Hard Constraint inherit)
4. Optimizer cycle weight schedule = alpha pre-declared β_bear (no grid search, anti data mining)

조건 미충족 시 **Path A (DPL_KR_v3 integration)** alternative.

---

## 6. Comparison: This sensor vs alternative orthogonal sources (Defense P0 gap context)

MEMORY.md P0 = "4th orthogonal source 발굴 (gap 0.0464, V6 prospective parallel 6m 후 admit re-시도)". 본 sensor candidate vs alternative:

| Candidate | Source | Estimated ρ with M4 | Estimated SR uplift | Risk verdict |
|---|---|---|---|---|
| **p_bad bear sensor** (this) | 8 학술 backbone × ML | 0.55~0.75 | +0.05~0.15 (β_bear scaling) | medium-high cor risk |
| KR 10y bond ETF | A148070 admit precedent | empirical 0.07~0.15 | +0.05 (Hybrid PG2 inherit) | LOW cor confirmed |
| TSMOM ETF | KODEX KTB10Y precedent | 0.077 (L-281 confirmed) | +0.08 (Hybrid PG2 inherit) | LOW cor confirmed |
| ML M6 ensemble | various | unknown | unknown | low-medium |

**Risk comparative diagnosis**: p_bad sensor의 estimated cor with existing M4 = **highest in candidate set**. KR 10y bond + TSMOM이 이미 더 직교적 source로 입증됨 (L-281). **본 sensor의 P0 SR gap 0.0464 closing utility는 cross-asset bond / TSMOM 보다 낮을 가능성 있음**.

**그러나** — bear sensor의 **defensive value**는 KR bond / TSMOM 과 다른 axis:
- KR bond = passive defensive allocation (15% PG2 inherit)
- TSMOM = active trend hedge (15% PG2 inherit)
- bear sensor = **dynamic regime detection** (defensive scaling β_bear ∈ [0.3, 1.0])

3 axis 모두 admit 가능 → **P0 gap closing은 multi-axis defensive overlay 누적 효과**.

---

## 7. Stage Artifact Outputs (binding)

Forge cycle 의무 추가 empirical audits (Path B admit precondition):

| Audit ID | Metric | Threshold | Forge Stage |
|---|---|---|---|
| CO1 | ρ(p_bad_monthly, m4_scalar_monthly) S4 117m | < 0.85 hard, < 0.70 preferred | Stage 4 |
| CO2 | ρ(p_bad_monthly, β_AR_monthly) S4 117m | < 0.40 (orthogonality) | Stage 4 |
| CO3 | ρ(p_bad_monthly, β_R05_monthly) S4 117m | < 0.70 (acceptable overlap) | Stage 4 |
| CO4 | TO_total estimate post-Layer 6 | ≤ 6.0/yr strict | Optimizer Stage |
| CO5 | crowding_score_per_factor for 8 backbones | report (advisory) | Stage 4 |
| CO6 | per-crisis joint signal (m4 + p_bad both trigger) timing | report (advisory) | Stage 4 |

---

## 8. Summary

**Risk Crowding Audit Verdict**:
- ⚠️ **Bear sensor (p_bad) ~ M4 BOCPD overlap medium-high prior (0.55~0.75)** — Forge cycle binding ρ < 0.85 hard
- ✅ p_bad ⊥ β_AR (cross-section concentration) prior LOW (0.20~0.40)
- ⚠️ VIX (F11~F14) + Yield curve (F01~F05) **crowding cluster 28% of features** — consensus signal, alpha edge limited
- ✅ Lead-time prior 3~6m (학술 backbone strong) — M4 보다 빠른 detection 가능
- ⚠️ KR bond + TSMOM이 이미 LOW-cor confirmed (L-281) — bear sensor의 P0 gap closing utility는 multi-axis defensive overlay 누적 효과로만 정당화
- ✅ Layer 6 sequential overlay 학술 grounding (Kritzman-Page-Turkington 2011 FAJ) inherit OK

**Path B Recommendation**: ADMIT_CONDITIONAL (Forge cycle CO1~CO6 binding pass 시 admit, 미충족 시 Path A DPL_KR_v3 integration fallback).

---

## References

- Kritzman, M., Page, S., & Turkington, D. (2011). Regime Shifts: Implications for Dynamic Strategies. FAJ 67(3), 22-39.
- Kelly, B., & Jiang, H. (2014). Tail Risk and Asset Prices. RFS 27(10), 2841-2871. (R05 backbone)
- Acadian Asset Management. (2026). Crowding Risk in Multi-Factor Portfolios. Research note. (Charter §15 P5)
- L-281 (Cross-Asset TSMOM orthogonality empirical 0.077 ρ)
- WT-D20260518_001 SEFRS Phase A (F26~F28 inherit)
- STR_1715_AR_on_M4_R05_overlay_PG2 manifest.json (2026-05-13 admit)
