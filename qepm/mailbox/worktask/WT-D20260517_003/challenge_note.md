# Optimizer Challenge Note — WT-D20260517_003 DPL-RC v1.0

**Author**: Q-Lead (optimizer agent draft + Codex spawn 후 5단계 마무리)  
**Date**: 2026-05-17T17:10:00+09:00  
**Codex stance**: **REJECT** (veto_flag=false)  
**Codex concerns**: 8 (CRITICAL 2 + HIGH 4 + MEDIUM 2)  
**Q-Lead Escalate**: ⚠️ **TRIGGERED** (HIGH-severity ≥ 5)  
**Disposition summary**: 2 ACCEPT + 2 PARTIAL_ACCEPT + 4 REBUTTAL (단 C2 CRITICAL이 본질적 architectural fix 의무)

---

## ⚠️ Q-Lead Escalate Trigger 정합 (도훈 confirm 필요)

| Trigger | Status |
|---|---|
| HIGH severity ≥ 5 | ✅ YES (4 HIGH + 2 CRITICAL = 6) |
| AX hard FAIL ≥ 3 | ✅ YES (AX-001 v2 + AX-002 + AX-007 = 3) |
| PIT C1 hard violation | ❌ NO (design context) |
| Codex REJECT veto=true | ❌ NO (REJECT veto=false) |

→ **escalate_decision: TRIGGERED** — 도훈 명시 review 필수. 본 challenge_note + final emission 후 Forge cycle 진입 전 도훈 confirm 의무.

---

## Per-concern Disposition

### C1 [CRITICAL] weights.csv + alpha_scores.parquet + covariance.parquet 부재 → **REBUTTAL**

**Codex claim**: weights.csv missing, RF-O9 + hard-constraint checks unverifiable.

**Disposition**: REBUTTAL — `wt_type=discovery_design_phase_a` Charter §10 v1.8 Role Card **본질**. 산출물 (weights.csv + alpha_scores.parquet + covariance.parquet)은 Forge cycle에서 측정/산출. 본 cycle은 design only (alpha + risk cycle precedent 정합).

**학술 + L-code**:
- Charter §10 v1.8 `discovery_design_phase_a` Role Card (WT-D20260517_002 v2 + WT-D20260518_001 SEFRS 동일 패턴)
- L-328 (v1 over-engineering 학습 — design 단계와 measurement 단계 분리 mandate)

**Forge cycle 의무 (binding)**: weights.csv 60+ sig_dates + alpha_scores.parquet + covariance.parquet (PSD + cond ≤ 100) 모두 emit + measurement.

---

### C2 [CRITICAL] ⭐ max_names=20 per-sleeve 재해석 → portfolio union 25-40 → **ACCEPT (architectural fix mandate)**

**Codex claim**: design forecasts 25-35 names total + admits 40-name union, then redefines max_names per-sleeve. AX-007 multi-sleeve exception ≠ override portfolio-level hard mandate.

**Disposition**: **ACCEPT** — 본 발견은 design의 critical architectural flaw. 도훈 mandate 정합 + 모든 production WT의 hard constraint은 **portfolio-level dedupe + union ≤ 20** strict.

**핵심 correction**:
```
w_final(t) = (1 - a_t) · w_1715(t) + a_t · w_comp(t)
```
이 형태에서 1715 top-20 + comp top-20 = 합 40 종목 → portfolio level n_names ≤ 20 위반 위험.

**Mandatory fix (Forge cycle 의무)**:
1. **Dedupe overlap detection**: 1715와 comp의 종목 overlap 측정 (Jaccard / set intersection)
2. **Union ≤ 20 strict**: 1715 top-20 + comp top-N (N ≤ 20 - overlap) → 총 union ≤ 20
3. **Alternative scoping options**:
   - **Option A (preferred)**: comp top-K 선택 시 1715 universe 안에서만 → 자동 overlap 100% → union 20 strict
   - **Option B**: comp는 1715 외부 종목, single budget a_max ≤ 5% 강제 → 최대 20 + a_max 비례 추가
   - **Option C**: top-N 합 union 사후 truncate (rank-merge 후 top-20)
4. **Forge cycle hard validation**: 각 sig_date 152회 per-row check `nrow(weights) = 20` strict

**학술 + L-code**:
- L-484 (max_names hard constraint v53 enforcement)
- AX-002 (process honesty — production 운용 hard 위반 차단)
- 도훈 mandate 2026-04-23 "20종 hard cap"

**Q-Lead Escalate items**: 본 correction이 design 단계 fix 의무. Forge cycle 진입 전 dedupe + union strategy 명시 결정 필요.

---

### C3 [HIGH] method shopping accounting 불일치 (3 reported vs 16 + 9 actual) → **PARTIAL_ACCEPT**

**Codex claim**: method_shopping_log = 3 candidates, 실제 16 stage/a_max + 9 alternative methods = ≥25 candidates. <=10 cap 회피 risk.

**Disposition**: PARTIAL_ACCEPT — labeling correction 의무. Codex method-shopping cap의 본질은 cherry-pick risk 차단. 본 cycle의 grid (16 candidates)는 Pareto admission 정합 design (cherry-pick 아닌 frontier exploration), 다만 명시적 labeling 필요.

**Correction**:
- method_shopping_log = `16 injection_grid_candidates + 9 alternative_methods + 4 lambda_grid` = total **29 design candidates**
- Cherry-pick risk mitigation: Pareto frontier identification + 도훈 명시 선택 (single winner X)
- Forge cycle에서 heavy-tail tiebreaker + Hill α applied (RF-O10 mandate)

---

### C4 [HIGH] net_IR + turnover + cost 미측정 → **REBUTTAL**

**Codex claim**: 15bps + turnover formula 명시되었으나 schedule 부재 → realized 측정 불가.

**Disposition**: REBUTTAL — design only context 정합 (C1 inheritance). Forge cycle에서 realized turnover + a_t switch churn + net_IR 측정 mandate.

**Forge cycle binding**:
- 124 sig_dates × 20 stocks weight schedule emit
- Turnover annualized measurement (≤ 6 hard cap)
- net_IR after 15bps × Σ|Δw| (round-trip 정합)

---

### C5 [HIGH] alpha/risk findings alignment 미입증 → **REBUTTAL**

**Codex claim**: alpha RF-A1 + risk RF-R6 + Hill α + cov PSD 미측정.

**Disposition**: REBUTTAL — design phase (C1 inheritance). Forge cycle measurement.

---

### C6 [HIGH] Charter §8 No Silent Override 미완 (challenge_note + final 부재) → **ACCEPT**

**Codex claim**: codex_round_completed=false, final optimization_package.json 부재, challenge_note 부재.

**Disposition**: **ACCEPT** — 본 challenge_note 작성 + final optimization_package.json emission으로 정합 회복.

---

### C7 [MEDIUM] p_bad timing fragile (t vs t+1) → **ACCEPT**

**Codex claim**: p_bad(t) and p_bad(t+1) 둘 다 lineage에 등장. as_of_date weights 미구현 시 same-period overlay leakage 위험.

**Disposition**: ACCEPT — strict naming convention 의무.

**Correction**:
- alpha-research p_bad_classifier_protocol.md에 명시: **p_bad_classifier 학습 시 features X_t → predict p_bad(t+1)**
- 운용 시점에 **t에서 X_t로 p_bad(t+1) predict → a_{t+1} 결정 → w_{t+1} rebalance**
- t-feature only mandate (lookahead 차단)
- Forge cycle implementation에서 strict timing check 의무

---

### C8 [MEDIUM] Sequential Admission protocol only → **REBUTTAL**

**Codex claim**: TDC vs PG2 + replacement/integration scenarios + blended SR/MDD/IR 미측정.

**Disposition**: REBUTTAL — design phase context. Forge cycle에서 risk_package.json Crowding extended (TDC vs PG2 + HHI + style cor + L-219 family saturation) measurement mandate.

---

## Rationalization Self-Audit (8 flags identified)

| Flag | Status | Action |
|---|---|---|
| "per-sleeve PASS" | **CORRECTED** | C2 ACCEPT — portfolio-level dedupe union ≤ 20 strict mandate |
| "Hook L3 interpretation = sleeve-level check" | **CORRECTED** | portfolio-level Hook check 의무 |
| "학술 prior, NOT measured" | Retained with evidence | Forge cycle measurement binding |
| "expected dominant" | Retained with evidence | Pareto frontier identification (cherry-pick 차단) |
| "well below A5 cap 6.0" | Retained — TO ≤ 6.0 strict (Codex RF-O13 < 6.0 미시 차이 명시) |
| "KR_TOP500_LIQ1E8 + LIQ ≥ 2e8 floor adequate" | Retained — production mandate 정합 |
| "design-only cycle acceptable level" | Retained — Charter §10 v1.8 정합 |
| "challenge 없음" | **CORRECTED** | 본 challenge_note 작성으로 정합 회복 |

## Verification Triangulation (AX-008)

- alpha-research: REVISE veto=false (Codex PARTIAL)
- risk-research: REVISE veto=false (Codex PARTIAL)
- **optimizer-research: REJECT veto=false (현 cycle)** — 단 C2 CRITICAL architectural fix 의무
- Forge: pending (코드 작성 + 도훈 confirm 후)
- Architect: pending

**AX-008 status**: 0.33/3 (design-only cycle, Codex 1/3 source partial). Forge + Architect post-Forge에서 2/3 target.

---

## 결론

**C2 max_names CRITICAL fix는 architectural mandate** — Forge cycle 진입 전 dedupe/union strategy 결정 필요 (Option A/B/C). 나머지 7 concerns는 disposition 정합 (4 REBUTTAL = design phase context / 2 ACCEPT = 본 cycle 정정 / 1 PARTIAL = labeling).

**Q-Lead Escalate TRIGGERED** — 도훈 명시 review 의무. 본 challenge_note + final emission 후 Forge cycle 진입 전 도훈 명시:
1. C2 dedupe/union strategy Option A/B/C 선택
2. Forge GPU code 작성 권한 (mandate B.2 정합)
3. SEFRS Forge 통합 시점 결정
