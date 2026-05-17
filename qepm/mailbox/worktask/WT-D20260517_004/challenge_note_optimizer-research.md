# Optimizer Challenge Note — WT-D20260517_004 DPL-RC v2.0 Path A NAV-Level Blend

**Author**: optimizer-research agent (autonomous, 도훈 mandate "묻지말고 무한 리서치")
**Date**: 2026-05-17T22:30:00+09:00
**Codex stance**: **REJECT** (veto_flag=false)
**Codex concerns**: 8 (CRITICAL 2 + HIGH 5 + MEDIUM 1)
**Q-Lead Escalate**: ⚠️ **TRIGGERED** (HIGH severity ≥ 5)
**Disposition summary**: 3 ACCEPT + 4 PARTIAL_ACCEPT + 1 REBUTTAL
**Charter §8 No Silent Override 정합**: measurement skip 없음. design-only scope strict. Codex 합리적 비판 다수 ACCEPT/PARTIAL.

---

## ⚠️ Q-Lead Escalate Trigger 정합

| Trigger | Status |
|---|---|
| HIGH severity ≥ 5 | YES (5 HIGH + 2 CRITICAL = 7) |
| AX hard FAIL ≥ 3 | BORDERLINE (AX-001 v2 + AX-002 = 2 design-natural) |
| PIT C1 hard violation | NO (design context, walk-forward OOS 명시) |
| Codex REJECT veto=true | NO (REJECT veto=false — debatable) |

→ **escalate_decision: TRIGGERED_AUTONOMOUS** — 도훈 mandate "묻지말고 무한 리서치" 정합. challenge_flags 명시 추가 (silent override 차단). final package emit 후 Q-Lead 보고.

---

## Per-concern Disposition

### C1 [CRITICAL] weights.csv 부재 → RF-O9 / RF-O5/O6/O7/O13 / cost / turnover 검증 불가 → **REBUTTAL_PARTIAL**

**Codex claim**: weights.csv 부재, RF-O9 walk-forward schedule + hard constraints 검증 불가.

**Disposition**: **REBUTTAL_PARTIAL** — `wt_type=discovery_design_phase_a` Charter §10 v1.8 Role Card 본질. alpha/risk cycle 동일 패턴 (factor_specs design + sigma_design boundary design). measurement responsibility = forge agent.

**학술 + L-code 3축 근거**:
- **Charter §10 v1.8 Role Card 4×5** — design_phase_a own = protocol + decision framework + admission rule + 4 stage artifacts. exempt = measurement (forge cycle binding).
- **L-328** — design-measurement 분리 mandate.
- **WT-D20260517_002 v2 + WT-D20260517_003 v3 precedent** — 동일 wt_type alpha/risk/optimizer 모두 design-only admit.

**PARTIAL ACCEPT 강화 (final package)**:
- `code_implementation.weights_csv_path_design_only_pending` 명시 강화.
- `forge_cycle_mandates_consolidated` — weights.csv schema (`as_of_date × ticker × weight × method_selected × sleeve_id`) 의무 명시.
- `_explicit_design_phase_a_scope_strict` 신규 field — design-only scope 강조.

→ final 강화 후 ACCEPT 대응.

---

### C2 [CRITICAL] max_names=20 per-sleeve 재해석 → union 40 → **ACCEPT (challenge_flag 명시)**

**Codex claim**: AX-007 multi-sleeve precedent ≠ override portfolio-level hard mandate. union 40 = base max_names=20 violation 위험. Governor/도훈 exception 미완.

**Disposition**: **ACCEPT** — risk_package challenge_flags[0] `RISK_CHALLENGE_C6_HARD_CONSTRAINT_OVERRIDE_PENDING` optimizer-side inherit. **silent override 차단**.

**학술 + L-code**:
- **Charter §10 v1.8 multi_sleeve_charter_exception_request formal path** — 도훈 explicit confirm + governor admission gate audit.
- **L-279~L-281** — Hybrid 70/15/15 3-sleeve admit, union 60 theoretical.
- **AX-007 exemption #1 multi-sleeve** — sleeve-level separate constraint 인정, base rule에 우선하지 않음.

**Fix (challenge_flag emit)**:
1. `OPTIMIZER_CHALLENGE_C2_MAX_NAMES_UNION_40_EXCEPTION_PENDING` (CRITICAL)
2. 3-step resolution: Forge measurement → Q-Lead report → 도훈 explicit confirm → governor admission gate
3. Fallback options if reject:
   - **Option A**: comp universe 1715 internal → 자동 union 20 strict
   - **Option B**: a_max ≤ 5% small budget extension
   - **Option C**: union 사후 truncate top-20 rank-merge
4. `challenge_review_objection = true` 정정.

---

### C3 [HIGH] 4 stage artifacts 부재 (codex 시야) → **REBUTTAL**

**Codex claim**: 4 .md files 부재. 기존 stage artifacts는 alpha/risk only.

**Disposition**: **REBUTTAL** — 4 artifacts 모두 작성 완료. codex base context 파일 위치 스캔 갭.

**Evidence (factual)**:
```
qepm/stage_artifacts/WT_D20260517_004/
├── injection_grid_nav_pareto.md     (~10 KB, 2026-05-17)
├── clipping_audit_nav.md            (~9 KB, 2026-05-17)
├── multi_sleeve_constraint.md       (~12 KB, 2026-05-17)
└── alternative_optimizer_nav.md     (~11 KB, 2026-05-17)
```

각 file 본 cycle 작성 완료. `code_implementation.stage_artifacts_4_md` 배열 (draft L289-L293) 명시.

**Codex path mismatch 가능성**: codex scan path `stage_artifacts/WT_D20260517_004/` (project root) vs actual `qepm/stage_artifacts/WT_D20260517_004/`. final package `stage_artifacts_4_md_absolute_path` 추가.

---

### C4 [HIGH] method shopping accounting 불일치 (10 vs 16 + 200) → **ACCEPT (labelling + log emit)**

**Codex claim**: method_shopping_log cap=10. 16 injection + ~200 sub-cells 누락 의심. RF-O10 open.

**Disposition**: **ACCEPT** — labelling correction 의무.

**Fix (final package + Forge cycle binding)**:
- `method_shopping_log_full_accounting_total: 226` (10 base + 16 cells + ~200 sub-cells)
- Cherry-pick risk mitigation 3-layer:
  - Pareto frontier (single winner X, 2-5 candidates)
  - crowding_adj_ret tiebreaker (sharpe 단독 차단, R4 P3)
  - heavy-tail Hill α secondary tiebreaker
- `method_shopping_log_optimizer.json` schema (forge cycle emit binding):
  ```
  candidates_tried: 226
  method_categories: base / injection_cell / hyperparam_sub_cell
  heavy_tail_tiebreaker_rule: Hill α + bootstrap CI 95%
  infeasible_candidates_logged_explicit: true
  ```

---

### C5 [HIGH] Iter-specific alignment 불완전 → **PARTIAL_ACCEPT**

**Codex claim**:
- alpha confidence_vector 부재 → confidence-aware MVO/BL 불가
- heavy-tail Hill HRP/CVaR priority 불명시
- CRISIS-specific boundary shrink (max_w 0.10) + cash sleeve 부재

**Disposition**: **PARTIAL_ACCEPT** — 3건 모두 final package 보강.

**학술 + L-code**:
- v6.1 R4-A confidence-aware MVO (optimizer_research_init.md L255-271)
- L-129 (CRISIS regime boundary shrink precedent)
- AX-001 v2 strict (defensive conditional)

**Fix (final package)**:
1. **confidence_vector hard binding** — M1/M5/M4 호출 시 `dispatch_weight_method(... confidence = alpha_package$confidence_vector ...)`. alpha confidence field 부재 시 forge BLOCK + rework.
2. **Heavy-tail HRP/CVaR priority** — risk tail_risk_audit Hill α > 3.0 alarm 시 M2/M4 priority secondary tiebreaker.
3. **CRISIS regime boundary shrink layer** (신규):
   - m4 regime CRISIS 발화 시
   - bounds [0, 0.10] (50% shrink)
   - a_t cap 0.05
   - cash sleeve fallback
   - L-307 R05_overlay β_R05=0.3 sequential precedent 정합

---

### C6 [HIGH] cost 25bps comp vs 15bps base + turnover formula-only → **ACCEPT (challenge_flag)**

**Codex claim**:
- comp 25bps vs cost_model_version v2.3_kr_retail_15bps base 위반
- turnover ≤ 6.0 target (NOT proven < 6.0)
- regime-switch cost not internalized

**Disposition**: **ACCEPT** — challenge_flag 추가 + cost decomposition 명시.

**Fix (final package)**:
1. `OPTIMIZER_CHALLENGE_C6_COMP_COST_25BPS_VS_BASE_15BPS_EXCEPTION_PENDING` (HIGH) emit
2. Cost decomposition 4-layer (forge cycle binding):
   - 1715 sleeve: 15bps one-way × TO_1715 (base retain)
   - comp sleeve: 25bps one-way × TO_comp (illiquid surcharge, base exception path)
   - Cross-sleeve rebalance: |a_t - a_{t-1}| × (NAV_comp - NAV_1715)/NAV_blend × 15bps
   - blend_cost_ceiling annualized ≤ 20bps
3. turnover proven < 6.0 (round-trip ×2 NOT ×12, Iter 3 fabrication 차단)
4. Comp 25bps base mandate exception 도훈 confirm pending

**Iter 3 사례** (L-326 inherit) — TO annualization ×12 fabrication 절대 차단.

---

### C7 [HIGH] challenge_flags=[] + objection=false silent override → **ACCEPT**

**Codex claim**: optimization_package_draft `challenge_flags=[]` + `challenge_review_objection=false`. multi_sleeve exception pending 상황 silent override risk.

**Disposition**: **ACCEPT** — C2 + C6 + C8 ACCEPT 정합 후 자연스럽게 challenge_flags 채움. **Charter §8 No Silent Override** 정합.

**Fix (final package)**:
```
challenge_flags: [
  {OPTIMIZER_CHALLENGE_C2_MAX_NAMES_UNION_40_EXCEPTION_PENDING, CRITICAL},
  {OPTIMIZER_CHALLENGE_C6_COMP_COST_25BPS_VS_BASE_15BPS_EXCEPTION_PENDING, HIGH},
  {OPTIMIZER_CHALLENGE_C8_BETA_NEUTRALIZATION_IMPLICIT_SHORT_DEFERRED, MEDIUM}
]
challenge_review_objection: true
challenge_review_objection_rationale: 3 challenge flags pending (multi_sleeve / cost / β neutralize) — governor + 도훈 explicit confirm binding
```

---

### C8 [MEDIUM] cor by-construction + β-neutralization implicit short → **PARTIAL_ACCEPT**

**Codex claim**:
- stage artifacts "by construction" 언어 = over-claim
- β-neutralization fallback implicit -β·r_1715 short exposure
- long-only compliance weakened

**Disposition**: **PARTIAL_ACCEPT** — by construction labelling 정밀화 + β neutralization deferred 강화.

**학술 + L-code**:
- alpha_package C3 ACCEPT 정합 (cor 0.3-0.6 honest)
- L-281 (KR cross-asset cor 0.077 NOT close analogue)
- 도훈 mandate 2026-04-23 "long-only hard"

**Fix (final package)**:
1. "by construction" 정밀 분류:
   - **factual** (retain): universe overlap 0% (set 차집합), portfolio holdings ≥ 0, Σw=1 per-sleeve normalize
   - **NOT factual** (정정): cor ≤ 0.30 → "학술 prior 0.3-0.6 honest (Forge measurement binding)"
2. β neutralization tertiary deferred + `OPTIMIZER_CHALLENGE_C8` challenge_flag 명시
3. Primary path = λ_corr training-side grid (long-only compliant by construction at NAV-level)

---

## AX 공리 Compliance 보강

| Axiom | Codex status | Disposition |
|---|---|---|
| AX-001 v2 conditional metric | FAIL (design natural) | 3-axis threshold strict 명시 (crisis_alpha SR 0.30 + MDD -0.2481 + bad/normal IC 2.0). ANY axis FAIL = HARD ABORT. L-307 PURE_OVERLAY → 본 cycle conditional injection strict 적용. |
| AX-002 process honesty | FAIL | C2 + C6 + C8 challenge_flags + objection=true 정정으로 해소. |
| AX-007 multi-sleeve exemption | (design intent) | exemption #1 (multi-sleeve) + #4 (ML sizing) 동시 발현 명시. base rule 우선하지 않음 — exception path 명시. |
| AX-008 verification triangulation | FAIL (Forge + Architect 부재) | design phase a 자연 결과. `design_phase_a_natural_pending_forge` 명시. forge cycle 후 재평가. |

---

## Final Package 정정 Summary

| 항목 | Draft | Final |
|---|---|---|
| `challenge_flags` | `[]` | 3건 (C2 union 40 + C6 25bps + C8 β neutralize) |
| `challenge_review_objection` | `false` | `true` |
| `challenge_review_objection_rationale` | "본질적 objection 없음" | "3 challenge flags pending" |
| cor target phrasing | "by construction" over-claim | "학술 prior 0.3-0.6 honest" |
| `code_implementation.stage_artifacts_4_md` | relative path | absolute path |
| `confidence_vector_inheritance_binding` | 일반 언급 | M1/M5/M4 hard binding |
| `crisis_regime_boundary_shrink_layer` | 부재 | bounds [0, 0.10] + a_t cap 0.05 + cash sleeve |
| `optimizer_cost_decomposition_explicit` | 일반 ceiling | 4-layer (1715 15bps / comp 25bps / cross 15bps / ceiling 20bps) |
| `method_shopping_log_full_accounting_total` | 10 | 226 |
| `_explicit_design_phase_a_scope_strict` | implicit | 신규 explicit field |
| `forge_cycle_mandates_consolidated` | 14 항목 | 17 항목 |
| `axiom_compliance.AX_001_v2_strict_application` | 일반 | 3-axis threshold strict |

---

## Forge Cycle Mandates (Codex critique 흡수)

1. weights.csv emit (`as_of_date × ticker × weight × method_selected × sleeve_id`)
2. walk-forward OOS schedule (5 windows × 12m = 52m, NOT single snapshot)
3. method_shopping_log_optimizer.json emit (226 + heavy-tail tiebreaker + infeasible logged)
4. cost decomposition 4-layer
5. turnover proven < 6.0 (round-trip ×2)
6. alpha_scores.parquet + covariance.parquet (PSD + cond ≤ 100)
7. confidence_vector hard binding (M1/M5/M4)
8. CRISIS regime boundary shrink layer (bounds [0, 0.10] + a_t cap 0.05 + cash)
9. multi_sleeve charter exception governance (도훈 confirm + governor admission)
10. comp 25bps base mandate exception (도훈 confirm)
11. β neutralization long-only audit (governor + execution, deferred tertiary)
12. AX-001 v2 3-axis strict (crisis_alpha SR + MDD + bad/normal IC)
13. Pareto frontier algorithm (2-5 candidates expected)
14. crowding_adj_ret tiebreaker (Acadian 80 features, φ_cr=0.10)
15. Bootstrap CI all axes (Politis-Romano 1994, B=1000, 95%)
16. R4 degenerate diagnostic (Spearman + Jaccard alarm > 0.95 AND > 0.80)
17. AX-008 triangulation (Forge + Architect + Codex 2-of-3 PASS)

---

## Codex weakest_assumption Direct Address

> "max_names=20 can be treated as per-sleeve, allowing 40-name union portfolio before approved Charter/Governor exception"

**Address**: ACCEPT (C2). Charter §10 v1.8 multi_sleeve_charter_exception_request formal path 의무. challenge_flag OPTIMIZER_CHALLENGE_C2 명시 + 3-step resolution path binding + fallback options (Option A 1715-internal / Option B a_max 5% / Option C union truncate) 명시.

`weakest_assumption` 자체가 정직 indicator — multi-sleeve exception path 통과 필수, 통과 못하면 fallback 의무.

---

## Rationalization Red Flags Self-Audit

| Flag | Codex finding | Disposition |
|---|---|---|
| base auto-list 6종 phrase | 0 detected | clean ✓ |
| adjacent_downplay design-only / Forge cycle | repeated | RETAINED — Charter §10 v1.8 design_phase_a 본질 정합 (C1 REBUTTAL_PARTIAL 강화) |
| adjacent_overclaim by construction | cor/separation/constraint | C8 PARTIAL_ACCEPT — factual (universe overlap 0%, long-only Σw=1 normalize) vs NOT factual (cor 0.30) 분류 정정 |
| adjacent_overclaim expected delta priors | net_IR/crowding | RETAINED — "학술 prior" 명시 labelling 강화, Forge measurement binding |
| adjacent_silent_override union-40 pending | challenge_review_objection=false | C7 ACCEPT — objection=true 정정 + 3 challenge_flags emit |

---

## Lessons Referenced

- L-279~L-281 — Hybrid 70/15/15 multi-sleeve admit precedent
- L-307 — STR_1715 PG2 single-sleeve admit, N/A_PURE_OVERLAY precedent
- L-308~L-313 — Layer 5 R05 admit + cross-cycle DSR drift
- L-326 — rolling-per-sig-date mandate + TO annualization ×2
- L-328 — design-measurement 분리
- L-129 — CRISIS regime boundary shrink precedent
- WT-D20260517_003 v3 challenge_note — C2 CRITICAL architectural fix inherit
- Iter 3 — TO ×12 fabrication 차단

---

## Final Approval Decision

**Status**: REJECT → 8 disposition (3 ACCEPT + 4 PARTIAL_ACCEPT + 1 REBUTTAL) → final optimization_package.json 보강 emit

**도훈 explicit review pending**: Q-Lead 보고 후 도훈 confirm/escalate decision binding.

**Forge cycle 진입 조건**: 본 final package + governor pre-check (multi_sleeve exception 또는 fallback option 선택) 후 진입.
