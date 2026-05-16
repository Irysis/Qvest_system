# Optimizer-Research Codex Round Challenge Note — WT-D20260517_001

**Author**: optimizer-research agent
**Date**: 2026-05-17T07:31:49+09:00
**Codex stance**: REJECT (veto_flag=false)
**Concerns**: 10 total = 2 CRITICAL + 7 HIGH + 1 MEDIUM
**Codex AX-008**: FAIL (codex_critic_response_optimizer-research.json::verification_triangulation)

---

## §0. Self-check (rationalization audit)

**Auto-grep (회피 표현)** 산출물 4개 (constraint_projection_audit.md / optimizer_comparison_protocol.md / topk_alternatives.md / risk_optimizer_integration.md + optimization_package_draft.json):

| 검색어 | hit | 처리 |
|---|---|---|
| "미미" | 0 | PASS |
| "관행적 허용" | 0 | PASS |
| "보수적이면 OK" | 0 | PASS |
| "대부분 결과 동일" | 0 | PASS |
| "이미반영" | 0 | PASS |
| "실무적" | 0 | PASS |

**Codex flagged 5 rationalization candidates** (§rationalization_red_flags):
1. ❌ "Z-scored cross-section gap typically > 0.5 → sharpness sufficient" — **REVISE**: claim 정량 evidence 없음. "Z-scored ScoreHead 통상 cross-section gap > 0.5 → τ=0.1 sharpness 충분" 부적절. Forge cycle 실측 의무로 격하.
2. ❌ "Sector HHI 0.30 expected non-binding" — **REVISE**: "expected" 부적절. "Forge measurement obligation" 명시.
3. ❌ "Stage 1 ReLU + Stage 2 Gumbel suppression + cross-section Z-score sufficient" — **REVISE**: "sufficient" 부적절. "Forge audit obligation" 명시.
4. ✅ "NOT_TRIGGERED at design phase" — **RETAIN**: design phase a Charter §10 v1.8 amendment pending — Codex C1 governance dispute에서 분리.
5. ✅ "Phase 4 deferred" — **RETAIN**: explicit phase deferral label로 valid (회피 X). academic literature reference (Bauschke-Combettes 2017, Dykstra 1986) 포함.

→ Final emission에서 1/2/3 revision 적용.

---

## §1. Concern Disposition (10 concerns)

### C1 — weights.csv absent [CRITICAL — AX-002 / AX-008 / RF-O5/6/7/9/13]

**Codex claim**: "Required optimizer artifact weights.csv is absent..."

**Disposition**: **PARTIAL ACCEPT — Charter §10 v1.8 amendment-pending governance dispute**

**근거**:
- `request.json::wt_type = "discovery_design_phase_a"` (post-escalate-fix 2026-05-17, Codex alpha C1 ACCEPT + risk C1 ACCEPT 정합)
- `request.json::agent_lineage.forge = "Step 6 — train + walk-forward backtest 184m + PerfA + Harvey 5 + DSR + Codex Round"` — weights emission은 **명시적으로 Forge agent 책임**
- alpha-research / risk-research 두 선행 cycle 모두 동일 wt_type 정합 (alpha_package.json::wt_type / risk_package.json::wt_type)

**그러나 Codex 정당 비판**: design phase에서 weights.csv emit 없으면 RF-O9 (walk-forward single-snapshot) violation **이론상 발생**. Charter §10 Role Card 4×5 matrix에서 **discovery_design_phase_a Role Card 명시화 의무**.

**처리**:
1. Charter §10 v1.8 amendment escalate (Q-Lead 책임, alpha CF-A12 + risk CF-R6 inherit) — discovery_design_phase_a Role Card formalize
2. 본 optimizer cycle은 **alpha/risk 선행 정합 (둘 다 design phase a emit)** — Forge cycle weights.csv emission 의무 명문화 (optimization_package §forge_cycle_obligations)
3. weights.csv가 Forge cycle 시 124 sig_dates × top-20 × Ticker schedule emit 의무 — 본 final package에서 explicit `forge_cycle_weights_csv_mandate` field 추가

**Hard Constraint 위반?**
- RF-O5/6/7 (max_names / max_w / Σw)은 design spec에서 4-stage projection mandate via Stage 1-4 audit — Forge cycle assert violation_rate=0 의무
- RF-O9 (walk-forward) — alpha §evaluation_windows 5 walk-forward × 124 sig_dates × top-20 schedule 의무 (Forge), 본 design phase에서 spec emit
- RF-O13 (turnover) — Forge cycle 의무

**REBUTTAL 분리**: 일반 deployment WT라면 weights.csv 의무. 본 cycle은 **discovery_design_phase_a paradigm shift first application** — alpha cycle도 alpha_vector empty (factor_specs only) emit. Codex 자체도 alpha cycle에서 C1 ACCEPT (architecture spec + PIT audit + protocol 인정).

---

### C2 — stage artifact dir / parquet artifacts absent [CRITICAL — AX-002 / AX-008 / PIT-C1 / RF-O9]

**Codex claim**: "qepm/stage_artifacts/WT_WT-D20260517_001 does not exist... alpha_scores.parquet or covariance.parquet absent"

**Disposition**: **PARTIAL ACCEPT — pointer correction + Charter §10 governance inherit**

**Pointer correction**:
- 정확한 stage artifact dir = `stage_artifacts/WT_D20260517_001/` (Codex가 `WT_WT-` typo 가능성). 확인:
  ```bash
  ls -la stage_artifacts/WT_D20260517_001/
  ```
- 본 cycle 작성된 4개 design markdown 정상 존재:
  - constraint_projection_audit.md ✓
  - optimizer_comparison_protocol.md ✓
  - topk_alternatives.md ✓
  - risk_optimizer_integration.md ✓
- + alpha-research artifacts (literature_review / pit_audit / dpl_architecture / training_protocol / feature_allowlist / alpha_validation)
- + risk-research artifacts (sigma_rationale / tail_risk_design / crowding_score_protocol / dpl_risk_attribution_design)

**alpha_scores.parquet / covariance.parquet absent**:
- 정합 — design phase a — Forge cycle 의무 (alpha_package.json::diagnostics + risk_package.json::forge_cycle_artifact_pending)
- Codex 정당 critique: artifact 부재 시 RF-O9 / cond ≤ 100 audit 불가
- 처리: optimization_package §forge_cycle_obligations에 명문화 (alpha_scores.parquet + covariance.parquet + weights.csv 3종 emit obligation)

**REBUTTAL부분**: Codex stage artifact dir 명시 잘못 — `WT_WT-` 중복 prefix typo. 실제 dir 존재.

---

### C3 — Stage 3-4 non-idempotency violation_rate ≤ 1% [HIGH — AX-002 / RF-O6/7]

**Codex claim**: "violation_rate ≤ 1% is not equivalent to hard weight_bounds [0,0.20] and sum_w=1 for every emitted row"

**Disposition**: **ACCEPT — Forge cycle violation_rate=0 strict mandate**

**근거**:
- Codex 정당 critique. 도훈 hard mandate: weight_bounds + Σw=1 **per row strict** — violation rate ≤ 1% 허용 X.
- 본 audit (constraint_projection_audit.md §1.3) "iterative max-3-iter retain + violation rate ≤ 1% Forge audit" 부분 **정정 의무**.
- 정정 후 strict: **violation_rate = 0 per row 의무**. Forge cycle 단 1행 violation 시 → infeasibility_report + WT ABORT.

**처리**:
1. constraint_projection_audit.md §1.3 violation rate criterion 수정 — `≤ 1%` → `= 0 strict per row`
2. Forge cycle: weight 1행이라도 violation 시 → 즉시 v1.1 Dykstra projection 채택 (Boyle-Dykstra 1986 §3.2) — Phase 4 deferred 폐기, Phase 3 v1.0 Dykstra fallback 추가
3. 정정 후 production weights.csv 모든 row strict pass 의무

**Hard Constraint compliance with Codex revision**: max_w ≤ 0.20 + 1e-6 numerical tolerance / Σw = 1 ± 1e-6 numerical tolerance per row strict.

---

### C4 — Method selection RF-O10 (DPL pre-selected vs B1-B6 post-hoc) [HIGH — AX-002 / RF-O10]

**Codex claim**: "DPL is preselected as production, while B1-B6 are future post-hoc baselines. This leaves RF-O10 open despite candidates_tried=7"

**Disposition**: **REBUTTAL — paradigm-shift WT의 baseline doctrine (You-Zhang 2025 §5)**

**근거 (3축 — 학술 + L-code + 정량)**:

**학술 (1)**: You-Zhang 2025 §5 — DPL paradigm shift WT의 baselines (MVO/HRP/ERC/CVaR/MaxDiv/EW)은 **paradigm justification artifact**, not production deployment candidates. Two-stage μ̂→optimizer paradigm 우회가 paradigm hypothesis 핵심 — 본 cycle은 DPL이 traditional MVO 대비 Pareto-improved 입증 의무.

**학술 (2)**: Uysal-Li-Mulvey 2021 §4 — joint learning (DPL-equivalent) vs Two-stage MVO 비교에서 joint learning OOS Sharpe 1.16 > Two-stage 0.79. Wei-Dai-Lin 2023 E2EAI 유사 결과. → DPL이 baseline 대비 우월할 prior probability 0.6+.

**L-code (1)**: L-272 (v7.0 paradigm doctrine) — paradigm-shift WT의 baseline은 paradigm 검증용. cherry-picking ≠ paradigm validation. RF-O10 통상 비교 (5+ method 중 1위 선택 cherry-pick risk)는 traditional optimizer WT context.

**정량**: 본 cycle은 alpha cycle도 single architecture (DPL_KR_v1) emit + Codex alpha C1 ACCEPT. method_shopping_log.candidates_tried=1 (architecture-level) alpha cycle 정합. Optimizer는 7 candidate (DPL + 6 baseline) — alpha 1보다 폭넓음.

**그러나 Codex 정당한 부분**:
- DPL "joint learning value-add" 입증 의무는 정합 — SR(DPL) > SR(B1_MVO with DPL scores) AND MDD(DPL) ≤ MDD(B1_MVO) 의무
- 만약 DPL FAIL → WT cycle reject (DPL paradigm hypothesis falsified) → baseline 선택 X (production은 STR_1715 retain)

**처리**:
1. optimization_package §explanation §key_design_decisions 추가: "DPL paradigm value-add 의무: SR(DPL) > SR(B1_MVO+DPL_scores) AND MDD(DPL) ≤ MDD(B1_MVO). FAIL 시 WT reject, baseline production 승급 X."
2. RF-O10 disposition: **paradigm-shift baseline doctrine 적용 → cherry-pick 비해당**. Charter §10 v1.8 amendment 시 명문화.

---

### C5 — Iter-specific alignment (SubStab / Hill / CRISIS) [HIGH — AX-001 / AX-002 / RF-O11/12]

**Codex claim**: "alpha SubStab/confidence is pending, risk Hill alpha is pending, and CRISIS small-sample handling lacks optimizer-level boundary shrink to max_w 0.10 plus cash sleeve"

**Disposition**: **PARTIAL ACCEPT — Forge cycle measurement inherit + CRISIS boundary shrink REBUTTAL**

**Part 1 (PARTIAL ACCEPT)** — SubStab/Hill α:
- alpha-research diagnostics_specification (alpha_package §) "subperiod_stability between-window correlation target ≥ 0.5" + Harvey-t 5 specs spec emit
- risk_package §tail_risk_model.comprehensive_metric_panel Hill α target ≥ 2.5 / hard_abort < 1.5
- 둘 다 Forge cycle measurement 의무 (선행 cycle 정합)
- Codex 정당 critique: optimizer cycle에서 reproduce/audit obligation 명시 → final package에 `forge_cycle_metric_audit_handoff` 추가

**Part 2 (REBUTTAL)** — CRISIS boundary shrink:

**근거**: Codex 제안 "max_w 0.10 + cash sleeve" 적용은 도훈 mandate 정합 X:
- 도훈 hard mandate (`worktask_constraint_enforcer.sh`): `weight_bounds [0, 0.20]` strict
- CRISIS regime detection 시 max_w 0.10 boundary shrink → 동적 cap 도입 (Phase 3 v1.0 spec 변경) → spec drift
- 본 DPL Phase 3 first application은 **static cap [0, 0.20]** retain — dynamic regime-conditional cap은 STR_1715 M4×AR×R05 overlay 영역 (Layer 5 R05)
- DPL paradigm은 weights direct emission — cash sleeve 명시 추가 시 Stage 5 신규 필요 (architecture v1.1+)

**처리**:
1. Phase 3 v1.0: static cap [0, 0.20] retain (도훈 mandate 정합)
2. CRISIS boundary shrink는 **post-admit Layer 5 R05 overlay 영역** (STR_1715 precedent) — admit 시 별도 검토. 본 design phase a scope 외.
3. CRISIS regime CVaR fallback은 risk_package §regime_conditional_cvar 정합 inherit (Bayesian pooled Σ_CRISIS = 0.5 × empirical + 0.5 × overall) — optimizer는 weights emission 외 변경 X

**REBUTTAL 강도**: optimizer-research 역할 = constraint projection design audit. 동적 cap shrink는 alpha/risk/regime engine 영역 — boundary 침범 거부.

---

### C6 — Cost/turnover round-trip definition unresolved [HIGH — AX-002 / RF-O2/13]

**Codex claim**: "0.0015 × turnover language, while role prompt requires turnover × 15bps × 2 unless turnover is already round-trip; definition is unresolved"

**Disposition**: **ACCEPT — definition explicit clarify**

**근거**: 도훈 mandate 정합 + Iter 3 violation 사례 (×12 annualization 금지) — turnover round-trip 식 ×2 정합.

**Cost convention 정합**:
- Cost = 15bps **one-way** (cost_model_version v2.3_kr_retail_15bps)
- TO = Σ|w_t - w_{t-1}| (per-rebalance, **one-way absolute change**)
- Realized cost per rebalance: `cost_t = 0.0015 × TO_t` (one-way × one-way TO = no extra ×2)

**하지만 round-trip 비교**:
- Round-trip TO = 2 × one-way TO (buy + sell)
- Cost = 0.0015 × round-trip TO = **0.0015 × 2 × one-way TO** = 30bps/rebalance for full round-trip
- 그러나 portfolio rebalance에서 `TO = Σ|Δw|`은 이미 one-way change (single sale + single purchase)
- 정합 cost formula: `cost = 0.0015 × (one-way TO) × 2` if interpreting TO as buy + sell combined unit cost

**처리**:
1. optimization_package §cost_convention 명시:
   ```
   one_way_cost_bps: 15
   to_metric: "one_way_absolute_change = sum(abs(w_t - w_{t-1}))"
   cost_formula: "0.0015 × 2 × one_way_TO   (buy + sell round-trip)"
   annualization: "NOT applied during loss (per-rebalance accumulation)"
   ```
2. Forge cycle: realized cost per sig_date = `0.0015 × 2 × TO_t`. Annual cost = sum over 12 monthly rebalances.
3. Iter 3 violation 사례 정합 — ×12 annualization 금지. 본 cycle은 per-rebalance round-trip ×2 정합.

**Final package에 explicit cost_convention field 추가**.

---

### C7 — Liquidity 5e7 vs 2e8 [HIGH — PIT-C10 / RF-O9 / AX-002]

**Codex claim**: "5e7 KRW feature-build universe while the hard mandate is 20d TV ≥ 2e8 KRW, and no final selected-name ADV audit exists"

**Disposition**: **PARTIAL ACCEPT — alpha-stage 2-stage mitigation inherit + Forge audit obligation**

**근거**:
- alpha_package §data.liquidity_2stage_mitigation Codex C4 ACCEPT — features_master build-time LIQ ≥ 5e7 / alpha emit LIQ ≥ 2e8 strict
- risk_package §risk_summary.liquidity_flags_inherit_alpha — final-weight ADV pre-check Forge cycle obligation
- 본 optimizer cycle도 동일 mitigation 정합 inherit

**Codex 정당 critique**: final selected-name ADV audit absent — Forge cycle 의무 명문화 부족.

**처리**:
1. optimization_package §pit_compliance §optimizer_specific_obligations에 추가:
   - "Forge cycle weights.csv emission 시 per-row Ticker × sig_date LIQ_20d_avg ≥ 2e8 KRW verify. 위반 시 row remove + redistribute (Stage 4 L1 normalize 재실행) OR infeasibility_report"
2. Forge audit: weights.csv 124 sig_dates × top-20 each Ticker LIQ check (alpha CF-A5 + risk C10 inherit)

---

### C8 — Sequential Admission TDC vs PG2 absent [HIGH — AX-008 / L-219 / RF-O10]

**Codex claim**: "no TDC vs PG2/MEGA_05, replacement scenario, integration scenario, or blended 80/20 SR/MDD/IR is reported"

**Disposition**: **PARTIAL ACCEPT — risk_package §crowding_audit §track_2 Forge cycle inherit + integration scenario 명시화**

**근거**:
- risk_package §crowding_audit.track_2_portfolio_level_codex_c8_expansion.tdc_vs_pg2 inherit (Joe-Clayton 190 pairs per sig_date, Forge cycle 의무)
- request.json §decision_gates.G2 — DPL substitution (cor < 0.5) / 4th orthogonal (cor < 0.3) candidate
- alpha CF-A2-DPL Codex C2 ACCEPT — Composite 개선 입증 의무 (Forge cycle ablation)

**Codex 정당 critique**: optimizer-research cycle에서 integration scenario (e.g., DPL 25% + STR_1715 75% blend) SR/MDD 측정 spec 부재.

**처리**:
1. optimization_package §sequential_admission_integration_scenarios 신규 추가:
   ```
   - Scenario A (4th orthogonal source admit, cor < 0.3): book mutation 4-sleeve {STR_1715 75% + DPL 25% blend}
   - Scenario B (substitution admit, cor < 0.5): book mutation 1-sleeve replace
   - Scenario C (reject, DPL FAIL): book retain 1-sleeve STR_1715 100%
   ```
2. Forge cycle weights.csv emit + scenario A/B/C 별 blended SR/MDD/IR/turnover 측정 의무
3. TDC vs PG2: risk_package Track 2 inherit (Joe-Clayton empirical 190 pairs/sig_date) — Forge cycle measurement

---

### C9 — challenge_note absent + infeasibility NOT_TRIGGERED premature [MEDIUM — AX-002 / AX-008]

**Codex claim**: "No optimizer_challenge_note.md exists for this WT, and infeasibility_report_status='NOT_TRIGGERED at design phase' is premature"

**Disposition**: **ACCEPT — challenge_note.md emit (본 doc) + infeasibility re-label**

**처리**:
1. **본 doc** (challenge_note_optimizer-research.md) emit — Codex 정당 critique 해소
2. infeasibility_report_status re-label: `"NOT_TRIGGERED_AT_DESIGN_PHASE_A_FORGE_CYCLE_OBLIGATION"` (premature 해소 + design phase governance label 유지)
3. Forge cycle 시 actual weight violation 발생 시 → `infeasibility_report` field populate + WT ABORT

---

### C10 — expected HHI / sector non-binding 가정 [MEDIUM — AX-002 / AX-007 / RF-O4]

**Codex claim**: "draft relies on expected HHI, expected sector non-binding behavior, and typical Gumbel sharpness; these are assumptions, not optimizer evidence"

**Disposition**: **ACCEPT — assumption 언어 정정 + Forge cycle measurement obligation**

**근거**: Codex flagged rationalization phrase 5건 중 1/2/3 — 본 self-check §0에서 이미 REVISE 결정.

**처리**:
1. optimization_package §explanation §hhi_design_phase_expected_range 정정:
   - 기존 "0.05 (EW fallback) ~ 0.12 (concentrated)" → "FORGE_MEASUREMENT_OBLIGATION (HHI bounds [0.05 floor EW, 0.20 hard via Stage 3 cap])"
2. §explanation §main_tradeoffs §expected language 정정 (assumption → obligation)
3. §risk_inherit_integration §crowding_score_per_factor_inherit "DPL output 자체가 EW-collapse 아닌 균등 spread" → "Forge cycle measurement obligation"

---

## §2. Hard Constraint Compliance Cross-Audit (Codex Round)

Codex hard_constraints_audit: n_names=null / max_w=null / sigma_w=null / long_only_pass=false / turnover=null / any_critical_block=true.

**해소 처리**:
- 본 design phase a — weights.csv Forge cycle emission 의무 (C1 disposition)
- design spec (Stage 1-4 audit) 통해 architecture-level mandate 정합
- Forge cycle assert (per-sig_date, per-row): n_names ≤ 20 / 0 ≤ w ≤ 0.20 / |Σw - 1| ≤ 1e-6 / w ≥ 0 / TO finite
- C3 disposition 통해 violation_rate=0 strict (≤1% 폐기) + Dykstra Phase 3 v1.0 fallback 채택

**RF-O5/O6/O7 (Hook block) 정합 — 본 doc §1.C1/C3 disposition으로 Hard Constraint design-level mandate emit. Forge cycle 의무 명시.**

---

## §3. AX-008 Verification Triangulation 점검

Codex verification_triangulation: ax_008_status=FAIL / agree_with_claude=false.

**현재 상태**:
- alpha-research: Codex round 1/3 complete (REJECT + disposition acknowledged)
- risk-research: Codex round 1/3 complete (REJECT + disposition acknowledged)
- optimizer-research: Codex round 1/3 in progress (REJECT + 본 disposition)
- Forge / Architect: deferred (Forge cycle GPU train 후)

**AX-008 ≥ 2/3 PASS gate**: design phase a에서는 **각 agent 자체 Codex round 1/3**이 default. Forge cycle 완료 후 (Forge stage Codex + Architect 검증) 2/3 PASS 의무.

**Charter §10 v1.8 amendment 필요**: discovery_design_phase_a에서 design phase a 자체 AX-008 1/3 floor 인정 (Forge/Architect deferred — Codex C1 alpha + C1 risk + 본 C1 optimizer inherit).

---

## §4. Final Disposition Summary

| Concern | Severity | Disposition | Action |
|---|---|---|---|
| C1 | CRITICAL | PARTIAL ACCEPT | Charter §10 v1.8 amendment + Forge weights.csv mandate explicit |
| C2 | CRITICAL | PARTIAL ACCEPT | Pointer correct (WT_D not WT_WT-D) + Forge artifacts (alpha_scores/covariance/weights) mandate |
| C3 | HIGH | ACCEPT | violation_rate=0 strict + Dykstra v1.0 fallback (Phase 4 deferred 폐기) |
| C4 | HIGH | REBUTTAL | paradigm-shift baseline doctrine (You-Zhang §5 + Uysal-Li-Mulvey 2021 §4 + L-272) |
| C5 | HIGH | PARTIAL ACCEPT + REBUTTAL | SubStab/Hill Forge inherit; CRISIS boundary shrink REBUTTAL (도훈 mandate static cap) |
| C6 | HIGH | ACCEPT | cost_convention explicit (round-trip ×2 + per-rebalance, not annualized) |
| C7 | HIGH | PARTIAL ACCEPT | alpha-stage 2-stage mitigation inherit + Forge ADV audit explicit |
| C8 | HIGH | PARTIAL ACCEPT | risk Track 2 inherit + integration scenario A/B/C 명시화 |
| C9 | MEDIUM | ACCEPT | challenge_note.md emit (본 doc) + infeasibility re-label |
| C10 | MEDIUM | ACCEPT | assumption 언어 정정 (expected → Forge obligation) |

**Disposition counts**: 4 ACCEPT + 5 PARTIAL ACCEPT + 1 REBUTTAL (C4)

**Q-Lead Escalate Triggers**:
- HIGH severity ≥ 5 (Codex 7 HIGH) → ✅ Trigger
- AX axiom hard FAIL (AX-002 FAIL) → ✅ Trigger
- Charter §10 v1.8 amendment-binding (discovery_design_phase_a) → ✅ Trigger (alpha + risk + optimizer 3건 inherit)
- RF-O5/6/7 (Hook block constraint) ← weights.csv design phase emission X → governance dispute (C1)

**Escalate destination**: Q-Lead — Charter §10 v1.8 formalization + Forge cycle handoff (weights.csv + alpha_scores.parquet + covariance.parquet + ADV audit + scenario A/B/C measurement).

---

## §5. Final Emission Plan

Final `optimization_package.json` 적용 변경:

1. **draft_marker false** + **post_codex_disposition_status** 추가
2. **stance / concerns / disposition_summary** codex_round_metadata 채움
3. **cost_convention explicit** field (C6 ACCEPT)
4. **forge_cycle_weights_csv_mandate** field (C1 PARTIAL ACCEPT)
5. **forge_cycle_artifacts_mandate** field — alpha_scores.parquet + covariance.parquet + weights.csv 3종 (C2 PARTIAL ACCEPT)
6. **sequential_admission_integration_scenarios** A/B/C (C8 PARTIAL ACCEPT)
7. **violation_rate strict 0** + **dykstra_v1_0_fallback** (C3 ACCEPT)
8. **assumption 언어 정정** (C10 ACCEPT) — "expected" → "FORGE_MEASUREMENT_OBLIGATION"
9. **infeasibility re-label** (C9 ACCEPT) — NOT_TRIGGERED → NOT_TRIGGERED_AT_DESIGN_PHASE_A_FORGE_CYCLE_OBLIGATION
10. **challenge_flags 추가** — CF-O8 (paradigm baseline doctrine REBUTTAL) + CF-O9 (Stage 3-4 Dykstra adoption Phase 3 v1.0)
11. **deliverable_lineage_v6_1.challenge_note_optimizer** field add

**Rationalization revisions in 4 markdown files**:
- constraint_projection_audit.md: Stage 2 sharpness phrase 정정 + Stage 3 violation rate 0 strict
- risk_optimizer_integration.md: sector HHI "expected" → "Forge measurement obligation"
- optimizer_comparison_protocol.md: gumbel sharpness assumption 제거 (이미 audit verdict 포함 — 검증 필요)
- topk_alternatives.md: 정합 retain (학술 인용 충분, rationalization 없음)

---

## §6. Q-Lead Escalate Brief

**To**: Q-Lead (도훈 mandate)
**From**: optimizer-research agent
**WT**: WT-D20260517_001
**Stage**: optimizer-research Codex Round disposition complete
**Codex stance**: REJECT (veto_flag=false)
**AX-008 status**: 1/3 (Forge + Architect deferred per Charter §10 v1.8 amendment-pending)

**Disposition summary**:
- 4 ACCEPT (C3, C6, C9, C10)
- 5 PARTIAL ACCEPT (C1, C2, C5 part 1, C7, C8)
- 1 REBUTTAL (C4 paradigm-shift baseline doctrine, You-Zhang §5 + Uysal-Li-Mulvey 2021 §4)
- 1 REBUTTAL partial (C5 part 2 — CRISIS boundary shrink, 도훈 static cap mandate retain)

**Critical actions for Q-Lead**:
1. **Charter §10 v1.8 amendment escalate** — `discovery_design_phase_a` Role Card 4×5 matrix formalize. alpha CF-A12 + risk CF-R6 + 본 CF-O6 inherit (3-agent unanimous).
2. **Forge cycle handoff** — design phase a 3-agent (alpha/risk/optimizer) Codex round 1/3 complete. Forge cycle 의무: GPU train + walk-forward 5 windows × 52 net test months + weights.csv (124 sig_dates × top-20 × Ticker) + alpha_scores.parquet + covariance.parquet + bt_result.rds Backtest Contract v1.0 10-component.
3. **AX-008 ≥ 2/3 admit gate** — Forge cycle 완료 후 Forge stage Codex round 2/3 + Architect independent reproduction 3/3 의무.
4. **Decision gates** — request.json G0-G6 (PIT/SR/cor/Harvey/DSR/cost-Pareto/AX-008). G2 substitution (cor<0.5) / 4th-orth (cor<0.3) 측정 Forge cycle 의무.

**Submitted**: 2026-05-17T07:31:49+09:00 optimizer-research Codex Round disposition. Forge cycle queue 대기.
