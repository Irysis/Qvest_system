# Feature Stability Audit — WT-D20260519_002 Bear Prediction Engine v1.0

**Agent**: risk-research (regime_sensor scope, NOT portfolio Σ)
**As-of**: 2026-05-18
**Scope**: 32 dedicated features × 5-model ensemble × 5 sub-windows × 8 crisis epochs **stability priors** (Forge cycle empirical execution 미수행)
**Authority**: Risk diagnostic only — feature 추가/model 재구성 금지 (Hook agent_role_guard).

---

## 1. Audit Philosophy

본 cycle은 **discovery_design_phase_a** (Charter §10 v1.8). 실제 5-model ensemble fitting + feature importance 산출은 Forge Stage 3~4에서 발생. Risk Agent scope에서 측정 가능한 것은 **design-level stability priors** (학술 backbone 정합성 + per-stratum feature 가용성 + sub-period coverage 불균형 + Codex C5 disposition 정합).

따라서 본 audit은 **3가지 차원**의 stability priors emission:
1. **Stratum-conditional feature availability** (S1~S4 32 features × stratum)
2. **Sub-window class imbalance ratio** (5 windows × bad month count)
3. **Cross-period economic rationale stability** (8 학술 backbone × crisis epoch)

Forge cycle binding metric (deferred):
- Per-window LightGBM gain importance × Jaccard top-10 overlap ≥ 0.6 (alpha G3 binding)
- Stratum_id_S1 dummy NOT in top-5 (alpha Strategy A admit precondition, Codex C5)
- SHAP value Gini < 0.5 (concentration check)
- Bootstrap CI on importance (Lopez de Prado 2018 AFML Ch 8 MDA)

---

## 2. Stratum-conditional Feature Availability (32 features × 4 strata)

Alpha package `max_history_mandate_addendum_2026_05_19.stratum_handling` 정합 + per-feature publish-lag 점검.

| Stratum | Period | n_months | n_features_active | Notes |
|---|---|---|---|---|
| **S1** universal | 1990-01 ~ 2000-12 | 132 | **3** (F14 + F31 + F32) | macro/yield/credit/VIX/foreign ALL missing |
| **S2** + macro | 2001-01 ~ 2002-12 | 24 | **27** (S1 3 + 24 macro) | yield curve / LEI / VIX / credit / NFCI / foreign ON |
| **S3** + VKOSPI | 2003-04 ~ 2016-08 | 161 | **29** (S2 27 + F15/F16 conditional) | VKOSPI activate if fetch successful |
| **S4** + SEFRS | 2016-09 ~ 2026-05 | 117 | **32** (S3 29 + F26/F27/F28 SEFRS) | all features active |

**Risk diagnosis**:
- S1 (1990~2000) 30% of total sample is **3-feature regime** — LSTM / MSM cannot fit (require full feature vector). Tree ensemble + stratum_id_S1 indicator handles, but **risk: model learning era membership not bear mechanism** (Codex C5 ACCEPT).
- S4 (2016~2026) 27% of sample is **full 32-feature regime** with SEFRS. 본 stratum이 가장 데이터 풍부 + bear epoch (COVID + 2022 + 2026-03) 모두 포함.
- **Imbalance flag**: S2 (24m, 5.5%) too sparse for standalone validation despite containing key macro features. **Strategy B (2001+) admit decision 시 S2 weight 충분 검증** Forge binding.

**Codex C5 disposition reinforcement**: Strategy A vs Strategy B parallel benchmark **MANDATORY** (alpha admit rule pre-declared) + per-stratum feature importance audit binding (stratum_id_S1 top-5 → Strategy A invalidate).

---

## 3. Sub-window Class Imbalance Diagnostic (5 windows)

Alpha `crisis_sample_inclusion.md` 정합 + class imbalance per-window stability.

| Window | Period | n_obs | n_bad(<-5%) | imbalance_ratio | crisis_present | feature_coverage |
|---|---|---|---|---|---|---|
| **W1** | 1990-01 ~ 1997-09 | 93 | ~5 | 5.4% | pre-IMF baseline | **3 features S1 only** |
| **W2** | 1997-10 ~ 2003-12 | 75 | ~14 | **18.7%** | IMF + Dotcom (extreme) | S1→S2 transition (3→27) |
| **W3** | 2004-01 ~ 2010-12 | 84 | ~7 | 8.3% | GFC | S3 29 features |
| **W4** | 2011-01 ~ 2017-12 | 84 | ~5 | 6.0% | Eurozone + China + 2015 | S3 29 features |
| **W5** | 2018-01 ~ 2026-05 | 101 | ~6 | 5.9% | COVID + 2022 + 2026-03 | S4 32 features |

**Risk diagnosis**:
- **W1 (5.4% positive class)**: 가장 imbalanced + 3-feature only + pre-IMF era. **Recall 측정 noise 큼** — 5 bad months 중 3 detect (60% recall) vs 4 detect (80% recall) 단 1건 차이. **G1 5-subgate per-window Recall ≥ 0.60 W1 통과는 sample noise dominant** (Cochran 1977 small-n proportion CI).
- **W2 (18.7% positive class)**: 가장 balanced — IMF/Dotcom 두 crisis 포함. **모델 generalization stress test 핵심 window**.
- **W3 GFC만 single crisis** — yield curve inversion 2007 Q3 signal (Estrella-Hardouvelis 1991) 가 학술 prior로 명확 → W3 Recall priorly expected high.
- **W5 modern era** — 3 crisis 다양 + SEFRS feature 활용 가능 → most-features-active window.

**Stability prior**: Per-window AUC variance < 0.10 expected (Stock-Watson 2003 — leading indicators stable). 단 **W1 noise 큼** acknowledged.

**Risk recommendation** (Optimizer agent에 전달 ❌ — Forge cycle binding):
- Per-window evaluation은 W1 noise floor 명시 (n_bad=5 ± Wilson CI ~ 2~10)
- W2 + W3 + W4 + W5 = 4/4 strict, W1 = bonus → 효과적으로 4/5 stability mandate
- Class weight (pos_weight) consider 5×~9× in LightGBM/RF for imbalanced windows

---

## 4. Cross-period Economic Rationale Stability (8 backbones × 8 crisis epochs)

각 학술 backbone이 각 crisis에서 작동 expected stability check (학술 prior 정합).

| Backbone | Estrella-Hardouvelis 1991 | Stock-Watson 2003 | Ang-Chen 2002 | Engle-Mistry 2014 | Adrian-Brunnermeier 2016 | Gilchrist-Zakrajsek 2012 | Frazzini-Pedersen 2014 | Hamilton 1989 |
|---|---|---|---|---|---|---|---|---|
| **Features** | F01~F05 | F06~F10 | F17 | F11~F14 | F20~F22 | F23~F25 | F31~F32 | MSM model |
| **1997 IMF** | partial (KR YC missing) | weak (LEI US base) | strong (KRW shock) | weak (no VKOSPI) | weak (NFCI 2001+) | strong (KR credit spread spike) | strong (KOSPI defensive rotation) | strong (regime switching) |
| **2000 Dotcom** | **strong (yield curve inverted)** | **strong (PMI down)** | medium | medium | medium | medium | strong | strong |
| **2008 GFC** | **strong (2007 inversion)** | **strong** | strong | **strong (VIX 60+)** | **strong (NFCI peak)** | **strong (credit blowout)** | **strong** | strong |
| **2011 EU** | weak (no yield curve inversion) | weak | medium | medium | **strong (NFCI)** | **strong** | medium | medium |
| **2015 CN** | weak | weak | medium | medium | medium | medium | medium | medium |
| **2018 vol** | weak | weak | weak | **strong (VIX spike)** | medium | weak | weak | medium |
| **2020 COVID** | weak (fast onset) | weak (data lag) | strong | **strong (VIX 80+)** | **strong** | **strong** | strong | strong |
| **2022 inflation** | **strong (yield curve inverted)** | medium | medium | medium | medium | **strong** | strong | strong |
| **2026-03 recent** | medium | unknown (recent) | medium | medium | medium | medium | medium | medium |

**Diagnostic findings**:
- **GFC (2008)** = 모든 8 backbone 강하게 작동 → easiest crisis to predict
- **EU (2011) + 2018 vol + 2015 CN** = backbone subset만 작동 → hardest to generalize
- **1997 IMF** = S1 era 학술 backbone partial coverage (KR yield curve data 없음) → **detection 어려움**
- **2026-03 recent** = OOS validation valuable, but unknown ex-ante (real OOS test)

**Risk implication**:
- Per-crisis Recall variance high expected (best GFC vs worst 2018)
- **Forge cycle binding**: per-crisis Recall + Precision report **MANDATORY** (alpha admission protocol G1 정합)
- 단일 crisis (2018 vol) catastrophic Recall (e.g., 0.0) 일지라도 다른 7 crisis 평균 ≥ 0.6 이면 admit candidate

---

## 5. Feature Pre-collinearity Diagnostic (학술 prior)

Forge cycle empirical correlation은 미수행 — **학술 prior 기반 expected collinearity** flag.

| Feature pair | Expected ρ | Reasoning | Risk |
|---|---|---|---|
| F01 + F02 (US 10y-2y vs 10y-3m) | **~0.85+** | both yield curve slope, US Treasury | high redundancy |
| F11 + F12 (VIX level vs zscore) | **~0.90+** | derived, level vs normalized | very high |
| F23 + F25 (KR credit spread vs 3m change) | ~0.50 | derivative | medium |
| F26 + F27 + F28 (SEFRS family) | **~0.65~0.80** | same underlying ETF flow | high (inherited from SEFRS Phase A) |
| F29 + F30 (foreign netsell intensity vs reversal) | ~0.40~0.60 | derivative | medium |

**Risk diagnosis**:
- **Yield curve duplication (F01 vs F02)**: 학술 standard 둘 다 보고 (Estrella-Hardouvelis 1991 + Estrella-Mishkin 1998), 단 LightGBM gain importance 분산 위험.
- **VIX level vs zscore**: 둘 중 하나만 retain 권고 (Forge cycle empirical compare).
- **SEFRS family ρ inherited from WT-D20260518_001 Phase A** — 본 risk가 새로 발견한 것 아님.

**Forge cycle binding** (alpha 영역, risk recommendation only):
- Forge Stage 3 correlation matrix 출력 (32×32) — collinearity score > 0.85 pairs report
- Random Forest permutation importance (Breiman 2001) collinear feature 자동 handle
- Logistic L1 (alpha sparse coefficient) collinear pair 중 하나 drop expected

---

## 6. Forge Cycle Binding Empirical Audits (deferred — risk agent NOT executor)

본 risk audit는 design-level priors. Forge cycle empirical execution 의무 binding:

| Audit ID | Binding to | Metric | Threshold | Owner |
|---|---|---|---|---|
| FS1 | alpha G3 | Top-10 Jaccard overlap across 5 sub-windows | ≥ 0.6 | Forge Stage 4 |
| FS2 | alpha G3 | LightGBM gain importance Gini concentration | < 0.5 | Forge Stage 4 |
| FS3 | alpha Strategy A admit | stratum_id_S1 dummy NOT in top-5 importance | hard | Forge Stage 4 |
| FS4 | alpha G3 | SHAP value sub-period drift coefficient | < 0.30 | Forge Stage 4 |
| FS5 | risk advisory | feature correlation > 0.85 pairs flag | report | Forge Stage 3 |
| FS6 | risk advisory | per-crisis Recall + Precision report | report | Forge Stage 4 |

---

## 7. Stability Prior Summary

**Design-level priors** (risk agent emission, Forge cycle binding):
1. **High prior stability** (학술 backbone정합): yield curve (F01~F05) / VIX (F11~F14) / credit spread (F23~F25) — Estrella + Engle + Gilchrist papers all cross-decade stable
2. **Medium prior stability**: SEFRS (F26~F28) — S4 only, regime-limited (2016+)
3. **Low prior stability**: foreign flow (F29~F30) — KR-specific, no academic cross-country stability prior
4. **Stratum imbalance risk**: S1 30% with only 3 features → era-membership leakage risk → Codex C5 Strategy B benchmark mandatory

**Risk Agent stance**: Feature stability priors satisfactory for Phase A admit. Forge cycle empirical Stage 4 binding metrics MUST pass FS1~FS4 before alpha admission.

---

## References

- Lopez de Prado, M. (2018). Advances in Financial Machine Learning. Wiley. Ch 7 (Walk-forward) + Ch 8 (Feature importance MDA/MDI)
- Breiman, L. (2001). Random Forests. ML 45(1), 5-32. (permutation importance)
- Cochran, W. G. (1977). Sampling Techniques. Wiley. (small-n proportion CI)
- Stock, J. H., & Watson, M. W. (2003). JEL 41(3) (leading indicators stable across crises)
- Codex C5 disposition (alpha challenge_note_alpha-research.md) — Strategy A vs B mandatory benchmark
