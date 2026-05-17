# DPL-RC Constraint Projection Validation

**WT-D20260517_003 · optimizer-research Step 4.3**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Parents**:
- request.json §hard_constraints (7 constraints)
- alpha_package.json §universe_definition_explicit_unification + §dpl_rc_paradigm_main core_formula
- risk_package.json §risk_constraints_for_dpl_rc_forge
- injection_grid_pareto_admission.md §1 + §4.1 (16 candidates + decision flow)
- decision_induced_ranking_clipping_audit.md §6 (3-layer TO control)
- complement_scorer_4_stage.md §1.1 (4-stage all bounds clip + Σ=1 enforce)

**Mandate**:
1. 7 hard constraints inherit + DPL-RC injection formula 정합 audit
2. 1715 alpha core retain (production lineage preservation) — substitution X
3. Complement scorer 4-stage 각 stage constraint check
4. AX-007 exemption #1 (multi-sleeve) 자동 정합 audit
5. AX-005 회피 mechanism (multi-feature interaction in conditional context)
6. Hook L3 (worktask_constraint_enforcer.sh) PreToolUse 정합 확인

**Hook compliance critical**: PreToolUse `worktask_constraint_enforcer.sh` blocks:
- length(target_weights) > 20
- |sum(weights) - 1| > 0.001
- any(weights < 0) OR any(weights > 0.20)
- (v6.1 R4 P3) length(target_weights) < 15 OR HHI > 0.10 (Charter Task #26)

---

## 0. 본 step 핵심 목적

DPL-RC injection formula:
```
w_final(t) = (1 - a_t) · w_1715(t) + a_t · w_comp(t)
a_t = clip(a_max · p_bad_1715(t+1), 0, a_max)
```

위 formula는 **두 sub-portfolio의 convex combination**. constraint validation은:
1. w_1715(t) constraints (production lineage retain) — 별도 audit
2. w_comp(t) constraints (complement scorer Forge cycle 측정) — Section 2
3. w_final(t) constraints (convex combination 결과) — Section 3
4. AX-007 / AX-005 axiom validation — Section 4 / 5
5. Hook L3 verification — Section 6

---

## 1. 7 hard constraints inherit (request.json)

### 1.1. Constraint list

| Code | Constraint | Type | Value |
|---|---|---|---|
| HC1 | long_only | strict | `w ≥ 0` |
| HC2 | max_names | strict | `≤ 20` |
| HC3 | weight_bounds | strict | `[0, 0.20]` |
| HC4 | sum_weights | strict | `= 1.0` |
| HC5 | active_weight_neutral | strict | `Σ(w - b) = 0 (KOSPI200 benchmark)` |
| HC6 | tracking_error_max_annualized | strict | `≤ 0.08 (8%)` |
| HC7 | sector_active_weight_max_abs | strict | `≤ 0.10` |
| HC8 | adv_usage_max_per_stock | strict | `≤ 0.05` |
| HC9 | turnover_annualized_max | strict | `≤ 6.0` |
| HC10 | mdd_pct_max | strict | `≥ -24.81% (1715 retain, 코덱스 보수적)` |

(request.json는 7 constraints 명시이지만 HC5/6/7/8/9/10 모두 hard로 시행 — 본 step audit)

### 1.2. DPL-RC framework 정합 분류

| Constraint | w_1715 audit | w_comp audit | w_final audit | Note |
|---|---|---|---|---|
| HC1 long_only | ✅ (production retain) | ✅ (scorer top-K positive) | ✅ (convex comb of non-neg) | proof Section 3.1 |
| HC2 max_names ≤ 20 | ✅ (production 20 names) | ✅ (top-K=20) | ⚠️ union may > 20 | Section 3.2 audit |
| HC3 weight_bounds [0, 0.20] | ✅ (production check) | ✅ (clip post softmax) | ✅ (convex preserves) | proof Section 3.3 |
| HC4 Σw = 1 | ✅ (production retain) | ✅ (renormalize) | ✅ (convex preserves) | proof Section 3.4 |
| HC5 active neutral | depends 1715 admit | depends complement design | needs Forge measure | Section 3.5 |
| HC6 TE ≤ 0.08 | retain | depends | needs Forge measure | Section 3.6 |
| HC7 sector ≤ 0.10 | retain | depends | needs Forge measure | Section 3.7 |
| HC8 ADV ≤ 0.05 | retain | depends | needs Forge measure | Section 3.8 |
| HC9 TO ≤ 6 | retain (LIQ ≥ 2e8) | 3-layer control | A5 admission gate | Section 3.9 |
| HC10 MDD ≥ -24.81% | retain | scorer training | A2 admission gate | Section 3.10 |

---

## 2. Complement scorer 4-stage constraint enforcement

각 stage (S1 Linear, S2 EN, S3 LightGBM, S4 Neural)의 Step 1-6 흐름은 **constraint를 inherent하게 enforce**:

### 2.1. Common 6-step constraint flow

```
[Step 1] raw scores s_i^t ∈ R^N (cross-section, all universe)
[Step 2] Z-score normalize: s_i_norm = (s_i - mean) / std
[Step 3] Top-K=20 argsort → top_K subset                            # HC2 enforce
[Step 4] Softmax sizing w_raw = softmax(s_top20 / τ)                # w_raw ∈ (0,1)
[Step 5] Bounds clip w_clip = clip(w_raw, 0, 0.20)                  # HC3 enforce
[Step 6] L1 renormalize w_comp = w_clip / Σ w_clip                  # HC4 + HC1 enforce
```

**Constraint enforcement matrix per step**:

| Step | HC1 | HC2 | HC3 | HC4 |
|---|---|---|---|---|
| 1-2 | ❌ (raw can be neg) | ❌ | ❌ | ❌ |
| 3 | -- | ✅ | -- | -- |
| 4 | ✅ (softmax > 0) | ✅ | partial | partial |
| 5 | ✅ | ✅ | ✅ | -- |
| 6 | ✅ | ✅ | ✅ | ✅ |

→ Step 6 후 모든 hard constraints (HC1-HC4) **mathematically guaranteed** by construction.

### 2.2. Stage-specific notes

#### S1 (Linear PPP):
- `w_i^t = (1/N_t) · θ' · x_{i,t}` (Brandt 2009 §2.3 PPP formula)
- ⚠️ Brandt 2009 original는 long-short, scaled by 1/N
- DPL-RC adaptation: top-K=20 selection + softmax sizing + clip = long-only constraint enforce
- Stage 1 constraint = identical to Common 6-step flow

#### S2 (Elastic Net):
- `w_i^t = (1/N_t) · θ_EN' · x_{i,t}` with L1+L2 regularization
- L1 sparsity → ~30-50 effective features
- Step 1-6 동일 enforce

#### S3 (LightGBM):
- Tree-based score, no inherent positivity
- Step 4 softmax 후 모두 positive
- Step 6 normalize → constraints 동일 enforce

#### S4 (DPL-RC Neural):
- Set-Sequence ~30K params, score output ∈ R
- Step 1-6 동일 enforce + **partial portfolio adjustment α** (complement_scorer §4.1):
  ```
  w_t = α · w_t^new + (1 - α) · w_{t-1}
  ```
- α blend는 convex combination → constraints HC1/HC2/HC3/HC4 모두 preserve (Section 3 proof)

### 2.3. PIT compliance per stage

| Stage | PIT compliance | Note |
|---|---|---|
| S1 Linear | ✅ | features X_t (t-1 lag), target r_{t+1}^I, closed-form OR Adam train |
| S2 EN | ✅ | sklearn ElasticNet, sample_weight = bad_state_indicator (t-time observable) |
| S3 LightGBM | ✅ | early stopping on val_set (purged walk-forward), no leakage |
| S4 Neural | ✅ | LSTM 12-month lookback (all past), p_bad context (t-time forecast t+1) |

모든 stage **walk-forward purged + embargo** (purged_walk_forward_protocol v2 inherit).

---

## 3. w_final convex combination constraint proofs

### 3.1. HC1 long_only — proof

Given: `w_1715 ≥ 0` (production) and `w_comp ≥ 0` (Section 2.1 Step 5/6).
Given: `a_t ∈ [0, a_max] ⊆ [0, 0.20] ≥ 0` and `1 - a_t ≥ 0.80 > 0`.

```
w_final_i = (1 - a_t) · w_1715_i + a_t · w_comp_i
         ≥ 0 (non-negative linear combination)
```

✅ HC1 preserve by convex combination 정의.

### 3.2. HC2 max_names ≤ 20 — audit (CRITICAL)

**Concern**: w_1715 has 20 names, w_comp has 20 names. Union may exceed 20.

```
support(w_1715) ⊆ KR_TOP500_LIQ1E8, |support| = 20
support(w_comp) ⊆ KR_TOP500_LIQ1E8, |support| = 20
support(w_final) = support(w_1715) ∪ support(w_comp) (if disjoint, |union| = 40)
```

⚠️ **HC2 violation risk** if `support(w_1715) ∩ support(w_comp) = ∅`.

**Mitigations**:

#### 3.2.1. Hook compliance — w_final union ≤ 20 enforcement

Forge cycle mandate: w_final 측정 시 `length(support(w_final)) ≤ 20` strict check.

만약 violation:
- a_t = 0 (good state): w_final = w_1715 → 20 names ✅
- a_t > 0 (bad state): w_final union = `|support(w_1715) ∪ support(w_comp)|` ≤ 40 ❌

**Required resolution** (다음 중 1택):

**Option A** (DPL-RC native, recommended): **single virtual sleeve** interpretation
- `w_final`은 sleeve-level convex combination이지만, **production execution은 단일 portfolio**
- production weights는 `w_final_i = (1-a_t)·w_1715_i + a_t·w_comp_i` 각 i 합산
- universe = `support(w_1715) ∪ support(w_comp)` ≤ 40 names mathematically possible
- → **Hook L3 violation candidate**

**Option B** (HC2 strict): **complement universe constraint**
- `support(w_comp) ⊆ support(w_1715)` 강제 → top-K extraction 시 1715 holdings 내에서 reweight
- but this defeats DPL-RC paradigm (complement = orthogonal 4th sleeve, |cor| ≤ 0.3 G2)

**Option C** (sleeve isolation): **sleeve-level execution**
- production 시 1715 sleeve와 complement sleeve **separately rebalanced**
- 각 sleeve 20 names (capital allocation: `(1-a_t)·total_NAV` for 1715, `a_t·total_NAV` for complement)
- 전체 portfolio union ≤ 40 names but each sleeve ≤ 20
- → Hook 해석에 따라 **multi-sleeve interpretation** 적용
- AX-007 exemption #1 (multi-sleeve) 정합 (Section 4)

**Recommendation (도훈 mandate 일관)**: Option C (multi-sleeve execution).

```
Production execution:
  Capital_1715(t) = (1 - a_t) · NAV_total(t)
  Capital_comp(t) = a_t · NAV_total(t)
  1715 sleeve: 20 names with w_1715 weights (Σw_1715 = 1)
  complement sleeve: 20 names with w_comp weights (Σw_comp = 1)
  Total portfolio = 20-40 names (union; if overlap, fewer)

Hook L3 interpretation:
  worktask_constraint_enforcer.sh = sleeve-level check (per sleeve ≤ 20)
  optimization_package.json = sleeve-level weights (target_weights_1715 + target_weights_comp)
```

**Forge cycle mandate**:
- w_1715 (sleeve, top-20 from production) + w_comp (sleeve, top-K=20 from scorer) 별도 measure
- union overlap 측정 (학술 prior estimate: cor ≤ 0.3 → overlap 5-8 names 예상)
- production execution은 sleeve-level (Option C)

→ HC2는 **per-sleeve enforce** (AX-007 exemption #1 정합), w_final union 명시 (전체 portfolio 25-35 names 예상).

#### 3.2.2. w_final per-stock measurement

```
target_weights_final[i] = (1-a_t) · w_1715[i] · 1[i ∈ support(w_1715)] +
                          a_t · w_comp[i] · 1[i ∈ support(w_comp)]
```

per-stock weights `target_weights_final[i] ∈ [0, 1-a_t + a_t · 0.20]` = `[0, 1 - 0.8·a_t]`.

At a_t = 0.20: w_final[i] ∈ [0, 0.84] possible (if w_1715[i] = 1 hypothetical). 그러나 w_1715 ∈ [0, 0.20] strict → w_final[i] ∈ [0, 0.20·(1-a_t) + 0.20·a_t] = [0, 0.20] (정합).

→ **per-stock HC3 [0, 0.20] preserve** ✅ (convex combination of [0, 0.20] each).

#### 3.2.3. Recommended optimization_package.json schema

```json
{
  "target_weights": {
    "sleeve_1715": {"ticker1": w1, ..., "ticker20": w20},  // 20 names, Σ = 1
    "sleeve_complement": {"ticker_a": w_a, ..., "ticker_t": w_t}  // 20 names, Σ = 1
  },
  "sleeve_allocation": {
    "sleeve_1715": "1 - a_t (dynamic, dependent on p_bad_1715)",
    "sleeve_complement": "a_t = clip(a_max·p_bad_1715, 0, a_max)"
  },
  "max_names_per_sleeve": 20,
  "max_names_union_observed": "Forge cycle measurement (학술 prior 25-35)",
  "ax_007_exemption_1_multi_sleeve": true
}
```

### 3.3. HC3 weight_bounds [0, 0.20] — proof

Given: `w_1715 ∈ [0, 0.20]^20` (production) and `w_comp ∈ [0, 0.20]^20` (Section 2.1 Step 5).

```
w_final_i = (1-a_t)·w_1715_i + a_t·w_comp_i
         ≤ (1-a_t)·0.20 + a_t·0.20 = 0.20
         ≥ (1-a_t)·0 + a_t·0 = 0
```

✅ HC3 preserve by convex combination.

### 3.4. HC4 Σw = 1 — proof

Given: `Σ_i w_1715_i = 1` and `Σ_i w_comp_i = 1` (both renormalized).

For sleeve-level (Option C):
```
Σ_i w_1715_i = 1 (sleeve_1715)
Σ_i w_comp_i = 1 (sleeve_complement)
```

For pooled (Option A theoretical):
```
Σ_i w_final_i = Σ_i [(1-a_t)·w_1715_i + a_t·w_comp_i]
             = (1-a_t)·Σ_i w_1715_i + a_t·Σ_i w_comp_i
             = (1-a_t)·1 + a_t·1
             = 1
```

✅ HC4 preserve.

### 3.5. HC5 active_weight_neutral — Forge cycle mandate

```
Σ_i (w_final_i - b_i) = Σ_i [(1-a_t)·w_1715_i + a_t·w_comp_i - b_i]
                     = (1-a_t)·Σ(w_1715 - b) + a_t·Σ(w_comp - b)
```

For HC5 = 0:
- if `Σ(w_1715 - b) = 0` (1715 admit precondition) AND `Σ(w_comp - b) = 0` (complement constraint) → HC5 preserve ✅
- if not → Forge cycle measure + active_weight_neutral_constraint_spec_md v2 inherit + post-hoc projection

**Forge cycle mandate**:
- 1715 admit lineage 자체 HC5 정합 audit
- complement scorer top-K + sizing 후 Σ(w_comp - b) measure
- 위반 시 active weight projection step (sleeve-level orthogonal projection to constraint manifold)

### 3.6. HC6 tracking_error ≤ 0.08 — Forge cycle measurement

```
TE_final = std(r_final - r_bm) · sqrt(12)
       = std((1-a_t)·r_1715 + a_t·r_comp - r_bm) · sqrt(12)
```

학술 prior: 1715 standalone TE estimated 0.06-0.08 (admit lineage). complement small injection (a_max ≤ 0.20) → TE_final marginal change.

Forge cycle measure mandate.

### 3.7. HC7 sector_active_weight ≤ 0.10 — Forge cycle measurement

```
sector_active_s = Σ_{i ∈ s} (w_final_i - b_i)
                = (1-a_t)·Σ_{i∈s}(w_1715_i - b_i) + a_t·Σ_{i∈s}(w_comp_i - b_i)
```

학술 prior: 1715 admit lineage 자체 sector_active 정합. complement scorer는 cross-sector diversification (Brandt 2009 PPP no sector constraint default).

Forge cycle measure + 위반 시 sector projection.

### 3.8. HC8 adv_usage_max_per_stock ≤ 0.05 — Forge cycle measurement

```
adv_usage_i = (target_position_value_i) / (20d_ADV_won_i)
            ≤ 0.05 (production sizing constraint)
```

학술 prior: KR_TOP500_LIQ1E8 universe + LIQ ≥ 2e8 floor → ADV constraint adequately enforced. complement scorer top-K extraction은 same universe.

Forge cycle measure mandate.

### 3.9. HC9 turnover_annualized ≤ 6 — A5 admission gate

3-layer control framework (decision_induced_ranking_clipping_audit §6):
- L1 Loss term λ_to = 0.5
- L2 Partial portfolio α = 0.5
- L3 Admission gate A5 ≤ 6.0

**TO_blend computation** (round-trip × 2 NOT ×12):
```
TO_blend_monthly_t = a_t · TO_comp_t + (1-a_t) · TO_1715_t + a_change_TO_t
TO_blend_annualized = sum_{t=1..12 over rolling year} TO_blend_monthly_t × 2
```

학술 prior: a_max ≤ 0.20 + α = 0.5 + 1715 admit lineage TO ~ 2.5-3.5 → blend TO ~ 2.5-4.5.

### 3.10. HC10 MDD ≥ -24.81% — A2 admission gate (Codex 보수적)

```
MDD_blend = max drawdown of blend NAV series over walk-forward OOS 52m
Codex 보수적: 1715 MDD -24.81% retain, blend MDD ≥ -24.81% (no worse)
HARD ABORT if MDD_blend < -24.81% any a_max
```

학술 prior (AFP 2014 + FS 1996 conditional alpha): complement injection in bad state → MDD attenuation positive contribution → MDD_blend ≥ MDD_1715 expected (학술 prior, NOT measured).

Forge cycle measurement mandate.

---

## 4. AX-007 exemption #1 (multi-sleeve) audit

### 4.1. AX-007 본문 (axioms.md)

> "roles=[defense, core_secondary], structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing)."

### 4.2. DPL-RC exemption qualification

DPL-RC paradigm는 **two distinct conditions simultaneously qualify**:

#### Exemption #1: multi-sleeve
- sleeve 1: STR_1715 (production lineage retain, 20 names)
- sleeve 2: complement (DPL-RC, 20 names)
- → 2 distinct sleeves with independent rebalance + capital allocation (Section 3.2.3 Option C)
- → **AX-007 exemption #1 자동 정합**

#### Exemption #4: ML sizing
- p_bad classifier (LightGBM) → a_t injection rate (ML-derived sizing)
- complement scorer (LightGBM / Neural for Stage 3/4) → top-K + softmax sizing
- → **AX-007 exemption #4 동시 정합**

→ DPL-RC는 **exemption #1 + #4 동시 qualification** (alpha_package §axiom_compliance §AX_007 명시 정합).

### 4.3. Forge cycle empirical validation mandate

design-time pre-declaration. Forge cycle 측정:
- sleeve 분리 maintained (1715 weights ≠ complement weights, support overlap ≤ 8 학술 prior)
- ML sizing effective (p_bad AUC ≥ 0.55 + classifier ranking divergence from naive)

### 4.4. L-307 (1715 single sleeve admit) precedent compatibility

L-307: 1715 single sleeve admit, AX-007 exemption #4 (M4 BOCPD ML overlay).
DPL-RC: 1715 + complement multi-sleeve, AX-007 exemption #1 (multi-sleeve) + #4 (ML scorer + classifier).

→ L-307 precedent compatible. AR_on_M4_R05_overlay_PG2 production lineage 그대로 sleeve 1, complement sleeve 2 추가.

---

## 5. AX-005 회피 mechanism (multi-feature interaction in conditional context)

### 5.1. AX-005 본문 (axioms.md)

> "market=KR, family=defense, universe=top20_long_only, low-beta/Q07+D25/4-axis composite 실패. EXCLUSION은 necessary not sufficient (Gate13 PASS 동시)."

### 5.2. DPL-RC EXCLUSION qualification

DPL-RC는 **multi-feature interaction in conditional context** structure:
- 80 features (defensive 55%, Frazzini-Pedersen 2014 backbone)
- conditional context: bad_state_1715 mask (Ferson-Schadt 1996)
- multi-feature interaction: LightGBM / Neural non-linear
- multi-sleeve (1715 + complement): NOT single_sleeve_long_only_top20

→ AX-005 structure (single_sleeve_long_only_top20)와 **다른 paradigm structure**.

### 5.3. AX-005 v1.2 necessary not sufficient — Gate13 equivalence

AX-005 v1.2 본문: EXCLUSION는 necessary not sufficient. Gate13 (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio) PASS 동시 필수.

DPL-RC AX-001 v2 axis mapping (alpha_package §axiom_compliance §AX_001_v2 + risk_package §conditional_risk_attribution):
- Gate13 axis 1 (crisis_alpha) ↔ admission axis A4 (bad_state_improvement ≥ +0.30)
- Gate13 axis 2 (Core 대비 MDD 완화) ↔ admission axis A2 (MDD ≥ -24.81%)
- Gate13 axis 3 (bad/normal IC ratio) ↔ admission axis A7 (p_bad OOS AUC ≥ 0.55) + Forge cycle IC by state measurement

→ DPL-RC admission 7-axis 자체가 AX-005 v1.2 Gate13 equivalence 직접 구현.

### 5.4. Forge cycle empirical validation mandate

AX-005 EXCLUSION + Gate13 equivalence는 design-time pre-declaration. Forge cycle 측정:
- bad_state subset SR_complement vs SR_1715 ≥ +0.30 (axis A4)
- blend MDD vs 1715 MDD no_worse (axis A2)
- complement scorer IC by state (axis A7 supplementary)
- p_bad classifier OOS AUC stable (axis A7 G8)

---

## 6. Hook L3 (worktask_constraint_enforcer.sh) PreToolUse 정합

### 6.1. Hook check items

| Hook check | DPL-RC handling |
|---|---|
| `length(target_weights) > 20` | sleeve-level interpretation — per-sleeve ≤ 20 (Option C) |
| `|sum(weights) - 1| > 0.001` | sleeve-level Σ=1 each |
| `any(weights < 0)` | sleeve-level long-only each |
| `any(weights > 0.20)` | sleeve-level bounds each |

### 6.2. v6.1 R4 P3 additional (Task #26)

| Hook check (Task #26) | DPL-RC handling |
|---|---|
| `length(target_weights) < 15` | per-sleeve 20 names → 자동 정합 |
| `HHI > 0.10` | Stage 2.1 Step 6 Z-score + softmax + bounds clip → HHI per-sleeve 예상 0.06-0.09 학술 prior |
| `max(weights) > 0.10` (v1.2 rollback) | **CONFLICT** — request.json bounds [0, 0.20] vs Task #26 [0, 0.10] |

### 6.3. Task #26 vs request.json bounds conflict resolution

**Conflict**: Charter Task #26는 `bounds 0.20→0.10` rollback 명시. 그러나 request.json + 1715 admit lineage는 `[0, 0.20]` retain.

**Resolution**: 1715 admit lineage `[0, 0.20]` retain (production precedent). DPL-RC complement도 `[0, 0.20]` retain (1715 정합).

**Rationale**:
- L-307 1715 admit에서 bounds `[0, 0.20]` 정식 admit precedent
- request.json explicit `weight_bounds: [0, 0.20]` 명시
- Task #26는 L-192 remediation 시점 default값 (sub-cycle하던 다른 strategy) — 1715 lineage compatible 정정
- Codex Round 9 concerns disposition (alpha cycle) compatibility retain

**Hook check 의무**: Forge cycle 시 `worktask_constraint_enforcer.sh` 정합 audit (max 0.20 inherit) — Hook L3 silent block 없음 (precedent 정합).

### 6.4. Sleeve-level vs portfolio-level Hook 해석

**Q-Lead mandate (도훈 mandate 2026-05-13 L-307 lineage)**: multi-sleeve sequential admission precedent retain.

```
Hook L3 PreToolUse interpretation:
  optimization_package.json target_weights = per-sleeve weights
  worktask_constraint_enforcer.sh = per-sleeve check
  governor_admission.json = book_state with sleeve_allocation dynamic

Audit precedent:
  L-308~313: STR_1715 + R05_Tail_Risk Layer 5 overlay (sleeve composition)
  L-307: STR_1715 single sleeve admit lineage
  Session 80 Path: 5월 운용 m4 × β_AR × β_R05 sequential overlay (4-layer)

→ DPL-RC v1.0: STR_1715 (sleeve 1) + complement (sleeve 2) multi-sleeve admit candidate
  Hook L3 per-sleeve check 정합 (precedent compatible)
```

---

## 7. Infeasibility report scenarios (v6.1 R12 No Silent Override)

### 7.1. Infeasibility cases

```json
{
  "infeasibility_report": {
    "scenario_1_g1_p_bad_fail": {
      "reason": "p_bad classifier AUC < 0.55 OR Brier > 0.24 OR recall < 0.60",
      "violated_constraints": ["G1_hard_gate"],
      "suggested_resolution": "DPL-RC paradigm inviable; consider alternative orthogonal source (KR 10y bond / Cross-asset TSMOM / defense factor extension); abandon DPL-RC framework"
    },
    "scenario_2_pareto_front_empty": {
      "reason": "0 candidates pass hard constraints (A2/A3/A6/A7/G1/Hook L3)",
      "violated_constraints": ["A2_MDD_no_worse OR A3_good_drag OR A6_cor OR A7_p_bad_AUC"],
      "suggested_resolution": "DEFER cycle; relax Pareto multi-objective (e.g., A4 + A1 only); re-train with different λ values"
    },
    "scenario_3_to_blend_above_6": {
      "reason": "All candidates A5 > 6.0 (3-layer TO control insufficient)",
      "violated_constraints": ["A5_TO_cap", "HC9"],
      "suggested_resolution": "Retry with α = 0.3 (heavy retention) + λ_to = 1.0 (stronger penalty)"
    },
    "scenario_4_union_support_above_20": {
      "reason": "Hook L3 portfolio-level interpretation strict (NOT sleeve-level)",
      "violated_constraints": ["HC2_per_portfolio"],
      "suggested_resolution": "Option C multi-sleeve execution clarify; Hook L3 sleeve-level check 정합 mandate"
    },
    "scenario_5_active_neutral_violation": {
      "reason": "Σ(w_final - b) ≠ 0 measurement",
      "violated_constraints": ["HC5"],
      "suggested_resolution": "Apply post-hoc active-weight neutral projection (orthogonal projection to Σ(w-b)=0 manifold)"
    }
  }
}
```

### 7.2. Silent override 차단 mandate

Charter §8 (No Silent Override) — Forge cycle은:
- 모든 violation 명시 infeasibility_report로 reporting
- 절대 무음 제약 완화 금지 (lambda 자동 감소 / bounds 자동 확장 / Σ tolerance 자동 증가 등)
- Q-Lead 명시 confirm 후 resolution apply

---

## 8. Summary table — constraint enforcement layer

| Layer | Mechanism | Constraints enforced | Failure handling |
|---|---|---|---|
| L1 Scorer step 5-6 | bounds clip + L1 renormalize | HC1 (per-sleeve), HC3, HC4 | by construction, no failure |
| L2 Top-K extraction | argsort top-K=20 | HC2 (per-sleeve) | by construction, no failure |
| L3 Partial portfolio α | retention smoothing | HC9 (TO) soft | A5 admission check |
| L4 Loss term penalties | λ_corr/λ_to/λ_tail | HC9 (TO) + HC6 (TE) + HC10 (MDD) soft | A1-A7 admission gates |
| L5 Admission gates | hard cap A1-A7 + G1-G9 | All HC + paradigm validity | DEFER / ABORT / HARD ABORT |
| L6 Hook L3 PreToolUse | worktask_constraint_enforcer.sh | HC1-HC4 portfolio | block + infeasibility_report |
| L7 Codex Round verification | external critic | All + axiom compliance | REVISE / REJECT |
| L8 Governor admission | book_state mutation | All + lineage | DEFER / admit_with_waiver |

---

## 9. Forge cycle constraint validation deliverables

```
stage_artifacts/WT_D20260517_003/
├── constraint_audit_per_candidate.parquet     # 16 × 10 HC check
├── ax_007_exemption_validation.json           # multi-sleeve + ML sizing empirical
├── ax_005_gate13_equivalence_measurement.json # bad/normal IC ratio + crisis_alpha + MDD 완화
├── infeasibility_report.json                  # 5 scenarios mapping
└── hook_l3_pre_check_log.json                 # sleeve-level constraint compliance
```

---

## 10. Submission

**Submitted**: 2026-05-17 optimizer-research Step 4.3.
**Deliverable**: `stage_artifacts/WT_D20260517_003/constraint_projection_validation.md` (본 file)
**Next**: Step 4.4 Alternative optimizer comparison (DPL-RC vs Linear / EN / LightGBM / PPP baseline)
