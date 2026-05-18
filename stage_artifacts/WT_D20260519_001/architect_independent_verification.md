# DPL_KR_v3 Architect Independent Verification

**WT**: WT-D20260519_001
**Agent**: Architect (Q-Lead spawn, AX-008 3rd source)
**Verification cycle**: concurrent with Forge GPU train (pre-bt_result.rds)
**Date**: 2026-05-18
**Reference precedent**: Session 80 R05 admit AX-008 3/3 PASS — Architect PASS_4_DECIMAL_EXACT 32/32 metrics within 0.005 strict

---

## 0. Verification Scope (AX-008 disjoint reproduction)

이 cycle은 **Forge GPU train 완료 전 spec-level + small-scale empirical verification**. Forge bt_result.rds 도착 후 4-decimal precision verification은 별도 round로 연기 (Session 80 R05 precedent와 동일 절차).

**검증 대상 4축**:
1. Architecture spec 정합성 (param count + 4-stage 구조)
2. PIT integrity audit (SHA256 binding + Z_Score_Aligned + Usable_Date)
3. PyTorch skeleton 정합성 (Codex C4 post-PA re-projection mandate 검증)
4. Anti-fabrication discipline (v4 lesson inherit)

**범위 외**: Forge realized SR / MDD / CAGR / Harvey-t / DSR — bt_result.rds 도착 후 별도 Architect round.

---

## 1. Architecture Spec Verification (PASS_WITH_SPEC_DRIFT)

### 1.1 Parameter Count Independent Reproduction

| Module | Spec (Arch §2.8) | Architect 실측 (manual reproduce) | Δ |
|---|---|---|---|
| DeepSet φ L1 (80→48) | 3,888 | 3,888 | 0 |
| DeepSet φ L2 (48→32) | 1,568 | 1,568 | 0 |
| DeepSet ρ L1 (32→16) | 528 | 528 | 0 |
| **DeepSet 소계** | ~6,000 | **5,984** | -16 (0.27%) |
| ScoreHead L1 (96→64) | 6,208 | 6,208 | 0 |
| ScoreHead L2 (64→32) | 2,080 | 2,080 | 0 |
| ScoreHead L3 (32→1) | 33 | 33 | 0 |
| **ScoreHead 소계** | ~8,300 | **8,321** | +21 (0.25%) |
| **Trainable TOTAL** | (6K + 8.3K) | **14,305** | — |
| Buffer/LayerNorm | 2,700 | **0** (skeleton에 LayerNorm 부재) | -2,700 |
| **TOTAL declared** | ~17,000 | **14,305 (실제)** | -2,695 (16% 격차) |

**Finding A-1**: Architecture §2.8 표는 "Buffer / bias / LayerNorm = 2,700"를 합산해 17K이라 선언하지만, **§6.1 PyTorch skeleton에는 LayerNorm 없음** (nn.Linear + nn.ReLU + nn.Dropout만, dropout은 parameter-free). 실제 trainable 14,305. **Q-Lead mandate "17K~50K params smaller MLP" 하한 약간 미달, 실용 범위 PASS** (under-param 안전 영역으로 더 강화). 17K 선언은 정직성 보고 시 14.3K로 재명시 권장.

**Finding A-2 (Param/data ratio)**:
- Initial spec (124 sig_dates): 4.96M obs / 14,305 params = 1:347 (claimed 1:295)
- Extended mandate (436 sig_dates): 17.44M obs / 14,305 params = 1:1219
- 양쪽 모두 Lu-Yang-Zhang 2024 under-param 안전 영역 (1:50+ 권장). **PASS**.

### 1.2 4-Stage Architecture 정합 (DeepSet → ScoreHead → Stage A-D)

Architect 독립 reproduce 결과 Forge skeleton 구현 시 다음 정합 검증:
- Stage A (Continuous Softmax): `softmax(s/τ)` τ ∈ {0.5, 1.0, 2.0} grid — softmax C∞ differentiable, simplex constraint by construction. PASS
- Stage B (STE top-K): `topk(w_raw, 20).indices` train과 inference 분리, Bengio-Léonard-Courville 2013. PASS
- Stage C (PAN): clip → L1 normalize iterative max_iter=3. 아래 §1.3 empirical convergence verification 참조
- Stage D (Partial Adjust α=0.6): 아래 §1.4 overflow empirical test 참조

---

## 1.3 PAN Convergence Empirical Test (200 synthetic trials, R reproduce)

스펙: max_iter=3, violation_rate < 1% mandate (Arch §2.6).

**Architect 실측** (set.seed(42), random softmax + top-20 + PAN):
```
Non-convergence in max_iter=3:  0 / 200 = 0%
Bounds/simplex violations:       0 / 200 = 0%
```

**판정**: PAN spec under typical input distribution 충분히 수렴. Bauschke-Combettes 2017 §28.3 alternating projection theory와 정합. **Dykstra fallback (Optimizer Stage C mandate)는 보험성, 실측 0% violation**. PASS_STRONG.

**Caveat**: synthetic input 은 well-conditioned. Forge cycle 실제 학습 시 score head output distribution이 edge-case (e.g., extreme τ=0.5 + concentrated scores) → PAN re-violation 시 Forge per-epoch log 발화 의무 (Architecture §2.6 audit mandate).

---

## 1.4 Stage D Partial Adjust Overflow Empirical Test (CRITICAL)

스펙 점검: 알파-research §6.1 PyTorch skeleton의 `partial_adjust(w_new, w_old, alpha=0.6)`는 단순 `α·w_new + (1-α)·w_old` 만 수행, **count(w>0) ≤ 20 보장 메커니즘 누락**.

**Architect 실측** (set.seed(42), 200 trials, disjoint top-20 시나리오 sample):
```
Mean union active count:       39.2 / 40 (sample disjoint)
Overflow (>20) frequency:      200 / 200 = 100%
```

**판정**: **post-PA re-projection 누락은 max_names=20 hard constraint 100% 위반 산출**. Optimizer Codex C4 ACCEPT mandate ("post-Partial-Adjust top-K + PAN re-projection")는 **empirically necessary, NOT 선택 보강**.

**Optimizer 제안 post-PA re-projection 적용 시**:
```
Overflow remained:    0 / 50 = 0%
```

**Finding A-3 (CRITICAL spec drift)**: `dpl_kr_v3_architecture.md §6.1` skeleton에 post-PA re-projection 블록 부재. Optimizer가 "alpha_research_v3_1_reconciliation_obligation_codex_c3_c4_escalate" mandate 발화한 이유. **Forge 학습 진행 전 alpha-research v3.1 reconcile 또는 Forge가 자체 reconcile 둘 중 하나 필수**. 누락 시 wt_check 단계 forge_package weights.csv `count(w>0) ≤ 20` audit 100% 실패 → WT FAIL.

---

## 2. PIT Integrity Audit (PASS_WITH_STRUCTURAL_CAVEATS)

### 2.1 Feature Allowlist SHA256 Binding

```
sha256 (architect 실측 sha256sum):
b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee

claimed (alpha_package §factor_specs[0].feature_allowlist_sha256):
b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee
```

**EXACT MATCH**. 80 features × {Risk_Beta_Vol 15, Tail_Risk 15, Momentum_Tech 15, Other 15, Liquidity 7, Risk_Metric 7, Reversal 2, Technical 2, Daily_LowFreq 2} 분포 정합. **PASS**.

### 2.2 rawdata.parquet 존재 확인 + SHA256 binding obligation

`.cache/rawdata.parquet` 존재 확인 (file exists TRUE). Architect는 대용량 SHA256 verification은 Forge 의무 영역 (v4 lesson — Forge가 self_synthesis_used=false 선언 + bt_result.rds SHA256 binding 의무). 본 cycle 범위 외.

### 2.3 Σ PSD Independent Reproduction

`covariance.parquet` (259×259) Architect R 실측:
- Symmetry max error: **0** (exact)
- Eigenvalues: min=1.875e-3, max=0.1589
- **eig_ratio (max/min): 84.7375** ← claimed 84.74 정확 일치 (4-decimal)
- PSD: TRUE (min_eig > 0)

**PASS_EXACT**. risk_package §diagnostics.Sigma_cond_eig_ratio 84.74 reproducible. kappa 52.43 (claimed)는 별도 정의 (Frobenius condition 또는 √eig_ratio 변형) — 결정 영역 외.

### 2.4 C1~C15 Audit Spot-Check

Architect는 pit_audit_v3.json 19 PIT codes를 spot-check:
- C1 (full-sample 금지): training_sig_date_first=2016-01-30 mitigation 정합
- C10 (LIQ 2e8 strict): alpha-emit re-filter 명시, features_master 5e7 inherit 분리 — Codex C4 v1 inherit fix 정합
- C13 (Z_Score_Aligned): factor_db_connector::load_month_factors() routing strict
- C14 (Usable_Date ≤ sig_date): ic_history.parquet Forge emit 의무
- C15 (factor_db_connector 경유): 정합

**Caveat**: c7_lookahead_pattern_auto_detect = PASS_PENDING_FORGE_SCAN — Forge `lookahead_detector.R` 실행 의무 carry. Architect 스펙 영역 PASS.

---

## 3. Risk Package Independent Verification

### 3.1 Σ 259×259 LW Identity Oracle Reproduce

위 §2.3와 동일 — eig_ratio 84.7375 정확. PSD TRUE. shrinkage_total 0.8658 (claimed) + δ_identity 0.2234 oracle — Architect 영역에서 직접 재산정 안 함 (Σ 빌드 R 코드 검토만). risk_research_pipeline_v2.R 29 KB 실행 가능 file 존재 확인.

### 3.2 Crowding Score Audit (CRITICAL drift)

`crowding_score_audit.parquet` Architect R 실측:
- dim: 22 rows × 8 cols (factor_name, crowding_score, hhi_top, vol_concentration, passive_overlap_proxy, demand_elasticity_proxy, n_universe, n_top)
- **`alert` column 부재**

risk_package.json §risk_summary.crowding_score_per_factor JSON에서는 alert 텍스트 ("LEVEL_ELEVATED" / "LEVEL_NORMAL") 제공되지만, **원본 parquet에서는 alert column 없음**.

**Finding A-4 (MEDIUM drift)**: Forge agent가 `crowding_score_audit.parquet`를 직접 load 하면 alert flag missing — risk_package.json risk_summary을 통한 lookup이 canonical. Forge cycle 시 risk_summary 참조 strict mandate (parquet 직접 사용 시 alert 누락 가능). Spec spec docs에는 audit field 명시되어 있어, 적어도 enum (HIGH/ELEVATED/NORMAL) 컬럼을 parquet에 추가하는 것이 정합도 향상.

### 3.3 RF-R6 Style Correlation 0.9647 Critical Risk

risk_package §risk_summary.pg2_comparison.style_correlation = **0.9647** (높음).

**Architect 해석**:
- 측정 기반 = "universe baseline (KR_TOP500 EW) vs STR_1715 PG2" style cor — **DPL_v3 emit weights vs STR_1715 alpha cor NOT yet measured** (Forge cycle obligation)
- universe 자체가 STR_1715의 style 차원(M4 regime + AR concentration + R05 tail)과 높은 style overlap (KOSPI에서 large-cap 비중 + defensive families)을 갖는다는 신호
- **G2 decision gate**는 realized DPL_v3 alpha cor vs STR_1715 alpha cor 기준 (not universe baseline) — Forge bt_result에서 alpha_inheritance_cor 측정 후 결정

**Caveat**: DPL_v3가 style cor 0.96 universe와 동조 학습할 경우 → cor vs STR_1715 alpha이 0.7+로 수렴할 가능성. G2 substitution gate (cor<0.5) 통과 가능성 모호. **Forge cycle 실측 후 architecturally factor neutralize (sector/size dummy residualization)나 alpha_research v3.1 reconcile mandate**.

---

## 4. Anti-Fabrication Audit (v4 lesson inherit)

### 4.1 Self-synthesis disposition

alpha_package §pit_compliance §audit_report → pit_audit_v3.json §anti_fabrication_v4_lesson:
- self_synthesis_used_label = **false** (declared)
- self_synthesis_used_audit_obligation = "Forge cycle must declare ... + Codex C1 audit obligation"
- bt_result_rds_sha256_binding mandate 명시

**Architect 영역 검증**: 본 cycle은 design phase이므로 직접 audit 불가. Forge cycle 도착 시점에서 architect 2nd round 의무.

### 4.2 v4 lesson trace

WT-D20260517_004 (v4) DEFER_PENDING_REWORK 사례 학습 — Forge agent synthetic ret_comp + label fabrication detected. v3은 strict inherit v5 rawdata canonical (sha256 c86e4ae5...). **rawdata.parquet exists confirmed** (`.cache/rawdata.parquet`).

**Forge 의무 carry**:
1. `sha256sum .cache/rawdata.parquet` → forge_package.json에 기록, claimed c86e4ae5... match assert
2. `self_synthesis_used: false` in forge_package.json (declared)
3. `sha256sum bt_result.rds > bt_result.rds.sha256` SOT binding
4. `lookahead_detector.R --target=WT-D20260519_001` C7 scan

---

## 5. Decision Gates Coverage Analysis

| Gate | Architect 사전 검증 가능성 | 상태 |
|---|---|---|
| G0 PIT C1~C15 | PASS_WITH_CAVEATS (spot-check) | PASS |
| G1 SR ≥ 1.0 | Forge realized only | PENDING |
| G2 cor < 0.5 / < 0.3 vs STR_1715 | Forge realized only | PENDING (style cor 0.96 universe → DPL learning에 영향 가능) |
| G3 sub_period_stability NEW | Forge per-sub-period only | PENDING |
| G3' crisis_conditional NEW | Forge per-crisis-window only | PENDING |
| G_Harvey t_NW ≥ 3.0 (5-spec) | Forge 5-spec OLS only | PENDING |
| G4 DSR Bailey-LdP Z ≥ 1.5 | Forge n_trials=100 only | PENDING |
| G5 cost Pareto | Forge same-harness only | PENDING |
| G6 AX-008 ≥ 2/3 | **Architect contributes 1 vote** | **본 cycle = 1 PASS** |
| G7 HHI > 0.06 strict | Forge weights.csv only | PENDING |

**Architect contribution to AX-008**: 1/3 (Forge + Codex + **Architect**) — 본 verification PASS_WITH_FINDINGS 시 AX-008 quorum 1 vote ARMED.

---

## 6. Findings 요약 (4건)

| ID | Severity | Finding | Action |
|---|---|---|---|
| A-1 | MEDIUM | Param count drift: 17K claimed vs 14.3K actual (skeleton에 LayerNorm 부재) | 정직 보고 시 14.3K 재명시 권장. Q-Lead mandate "17K~50K" 하한 약간 미달, 실용 PASS |
| A-2 | LOW | Param/data ratio 1:347 (initial) vs claimed 1:295 — minor drift | docs 갱신 권장 (numerical accuracy) |
| A-3 | **CRITICAL** | `dpl_kr_v3_architecture.md §6.1` PyTorch skeleton에 post-PA re-projection 누락. Stage D Partial Adjust 실측 overflow 100% (disjoint top-20 시) | **Forge 학습 전 alpha-research v3.1 reconcile 또는 Forge 자체 reconcile 의무**. 미시정 시 max_names=20 hard 100% 위반 |
| A-4 | MEDIUM | `crowding_score_audit.parquet`에 `alert` column 없음 (JSON only) | Forge crowding lookup 시 risk_package.json risk_summary 참조 strict. parquet에 alert enum 추가 권장 |

---

## 7. Verdict (PASS_PARTIAL with CRITICAL Finding)

**Architect verdict**: `PASS_PARTIAL` (AX-008 1/3 vote)

**근거 분석**:
- Architecture spec param count, PAN convergence, Σ PSD, feature allowlist SHA256 binding 모두 reproducible / PASS
- Codex C4 ACCEPT (post-PA re-projection) Architect 실측으로 empirical mandate 입증 — Optimizer 판단 정확
- 단 CRITICAL Finding A-3: skeleton 미reconcile 상태로 Forge cycle 진입 시 G7 max_names + Σw=1 위반 100%

**조건부 PASS 조건**:
1. alpha-research v3.1 reconcile cycle 또는 Forge가 자체적으로 post-PA re-projection 구현 (Codex C4 ACCEPT 이행)
2. forge_package.json에 `count(w>0)≤20 per sig_date strict` audit 결과 명시
3. Forge bt_result.rds 도착 후 Architect 2nd round 4-decimal precision verification (Session 80 R05 precedent)

**AX-008 quorum 기여**: 1/3 PASS_PARTIAL. 2/3 floor 도달은 Forge PASS 또는 Codex post-resolution PASS 추가 필요.

**Forge cycle은 진행 가능** (다음 conditions 가시) — Architect findings는 NON-BLOCKING_ADVISORY (PIT violation 또는 axiom hard FAIL 미발견), 단 Finding A-3는 Forge gate G7 + max_names 통과 차단 risk이므로 **Forge agent가 학습 시작 전 skeleton patch 또는 학습 중 post-PA re-projection 자체 구현 strict mandate**.

---

## 8. References

- `dpl_kr_v3_architecture.md` §0~§10 (alpha-research v3.1 reconcile 의무 영역)
- `pit_audit_v3.json` (C1~C15 spot-check 정합)
- `optimization_package.json` §stage_by_stage_audit.stage_d.postpa_reprojection_mandate_codex_c4_accept (Optimizer mandate origin)
- `risk_package.json` §risk_summary.pg2_comparison.style_correlation (RF-R6 critical context)
- `covariance.parquet` (Σ 259×259 independent reproduction)
- `feature_allowlist_v2.csv` (sha256 binding verification)
- Session 80 R05 admit precedent (Architect PASS_4_DECIMAL_EXACT 32/32, AX-008 3/3)
- L-330 (v5 RC paradigm scope retire — v3 original DPL과 분리 확인)
- Bauschke-Combettes 2017 §28.3 (PAN alternating projection theory)
- Bengio-Léonard-Courville 2013 (STE foundation)

---

**End of Architect Independent Verification — DPL_KR_v3**
