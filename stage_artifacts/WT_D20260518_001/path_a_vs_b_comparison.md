# Path A (Sequential) vs Path B (Replacement) vs M4 Standalone — Overlay Composition Analysis

**Optimizer Agent v1.0 design_phase_a**
**WT-D20260518_001**
**Cycle: 2026-05-19**

---

## 1. Three Paths Defined

### Path A — Sequential stack (Layer 6)
```
w_final(t) = w_str1715(t) × m4_scalar(t) × β_AR(t) × β_R05(t) × β_bear(t)
```
- All 5 production layers + bear overlay as Layer 6
- Multiplicative composition (Kritzman-Page-Turkington 2011 FAJ + Kelly-Jiang 2014 RFS precedent)
- β_bear ∈ {1.0, 0.7, 0.3} based on quantile hysteresis policy (M05)

### Path B — Replacement of Layer 3 (M4 BOCPD)
```
w_final(t) = w_str1715(t) × β_bear(t) × β_AR(t) × β_R05(t)
```
- m4_scalar removed; β_bear replaces it
- Retains AR + R05 overlays
- Conditional admission: Forge Stage 5 DM test p < 0.05 AND p_bad_t outperforms M4 in 3+/5 windows

### Path C — M4 Standalone (control / no Layer 6)
```
w_final(t) = w_str1715(t) × m4_scalar(t) × β_AR(t) × β_R05(t)  -- production baseline
```
- Current PG2 STR_1715_AR_on_M4_R05_overlay v2.3 (effective 2026-05-13, admit SR=1.95)
- No bear sensor addition
- Reject hypothesis baseline

---

## 2. Comparison Matrix

### 2.1 Crowding & Redundancy (risk-pkg numbers)

| Metric | Path A (Sequential) | Path B (Replacement) | Path C (Standalone M4) |
|---|---|---|---|
| Layer count | 6 | 5 | 5 |
| Bear sensor present | YES | YES (as Layer 3) | NO |
| M4 BOCPD present | YES | NO | YES |
| Crowding cor PG2 alpha | -0.136 | -0.136 | -0.130 (M4-only) |
| TDC_lower with PG2 alpha | 0.077 | 0.077 | similar |
| M4 incremental info captured | 31.4% (M4 fires when bear doesn't) + 68.6% (bear fires when M4 doesn't) | 0% (M4 deleted) | 100% (M4 only) |
| Bear incremental info captured | 100% (both retained) | 100% (bear only) | 0% (no bear) |
| Independent signal sources | M4 + bear | bear only | M4 only |

**Insight**: Path A captures both M4 (BOCPD cross-sectional regime change) and bear (44-feature time-series probability) — different signal kinds. Replacement (Path B) discards 31.4% of M4 informational coverage.

### 2.2 Statistical Defense Stack

| Metric | Path A | Path B | Path C |
|---|---|---|---|
| Layers requiring fresh validation | Layer 6 (β_bear only — Layers 1~5 admit retain) | Layer 3 (β_bear replaces M4) + Layers 4/5 retain | Layers 1~5 admit retain |
| Sequential admit precedent | Kritzman 2011 (AR) + Kelly 2014 (R05) ✓ | None — no replacement precedent in PG2 lineage | n/a |
| DM test required | **YES** — Path A admission requires DM 1-sided p < 0.15 AND mean(d_t) > 0 (m4_incrementality_protocol.md A1/A2) | **YES** — stricter: DM 1-sided p < 0.05 AND mean(d_t) > 0 AND 3+/5 windows AND HIGH_VOL_TAPER+INFLATION significant | n/a (Path C control baseline) |
| AX-007 single-sleeve exception | YES (overlay role) | YES (overlay role) | YES |
| Harvey-t fresh required | YES (β_bear contribution to L5_V2 alpha) | YES (β_bear replaces M4 in alpha) | NO (admit retain) |
| DSR fresh required | YES (n_trials=90 alpha-pkg method_shopping_log) | YES + Bonferroni for replacement claim | NO |

### 2.3 Production Architecture Coherence

| Aspect | Path A | Path B | Path C |
|---|---|---|---|
| Production v2.3 manifest changes | Minor (Layer 6 added, Layers 1~5 retain) | Major (Layer 3 reassigned, manifest version bump v2.3 → v3.0) | None |
| Re-promotion required | YES if admit (sub-slot 2-1.STR_1715_AR_on_M4_R05_bear_overlay_PG2) | YES (Layer 3 reassignment = architectural rename) | NO |
| Lineage chain extension | append L-323 type | branch / rename L-323 + L-324 | n/a |
| Backward compat with PG2 v2.3 | YES (multiplicative scalar Layer 6 is no-op if β_bear=1.0 always) | NO (M4 replacement breaks v2.3 reproduce) | YES (no change) |

### 2.4 Risk Profile

| Metric | Path A | Path B | Path C |
|---|---|---|---|
| Compound β floor (theoretical) | 0.5 × 0.7 × 0.3 × 0.3 × 0.3 = 0.0095 (~1% net) | 0.3 × 0.7 × 0.3 × 0.3 = 0.0189 (~1.9% net) | 0.5 × 0.7 × 0.3 = 0.105 (~10.5% net) |
| Compound β floor empirical (268m) | not observed (no joint extreme triple-hit) | not observed | observed 6 months (2008+2022 stress) |
| Over-defensive risk | LOW (joint extreme never observed) | MEDIUM (bear+AR+R05 stack thinner) | LOW (production baseline) |
| Under-defensive risk | LOW (5 layers compound) | MEDIUM (only 4 layers) | MEDIUM (no bear sensor = miss 68.6% incremental bear) |

### 2.5 Turnover & Cost (UNIFIED: cost_bps = TO_ann × 15 × 2 sides per Codex C4 disposition)

| Metric | Path A (Sequential) | Path B (Replacement) | Path C (Standalone M4) |
|---|---|---|---|
| Underlying TO_ann (STR_1715 base inherit) | ~2.5/yr | ~2.5/yr | ~2.5/yr |
| Overlay TO_ann (Layer 6 incremental) | hypothesis 1.5~2.5/yr (Forge S5 realized binding) | hypothesis 3.0~5.0/yr (Forge S5 realized) | 0 |
| Total TO_ann | 4.0~5.0/yr (within 6.0 cap) | 5.5~7.5/yr (borderline / potential cap violation) | 2.5/yr |
| Cost_bps unified = TO × 15bps × 2 sides | hypothesis 120~150bps | hypothesis 165~225bps (cap violation risk) | 75bps |
| Cost-adjusted alpha potential | hypothesis -120~150bps net vs +ΔSR_bear | hypothesis -165~225bps net vs +ΔSR_bear (admission threshold higher) | baseline |

**Codex C4 disposition**: 
- ACCEPT — units unified `cost_bps = TO_ann × 15bps × 2 sides`
- Previous draft had 3 inconsistent estimates (10~25bps incremental / 54bps / 75bps baseline) — those have been deprecated
- Hypothesis numbers are design-phase estimates only; **Forge Stage 5 realized cost emission replaces** when actual p_bad_t available
- **infeasibility_report trigger**: If Forge Stage 5 emits realized TO_ann > 6.0/yr in Path A → mandatory infeasibility_report + admission re-examination

**Note**: Path B TO higher because M4 BOCPD changepoint detection produces different transition pattern than bear sensor (BOCPD detects after the fact; bear sensor predicts ahead). Replacing M4 with bear changes underlying TO structure.

---

## 3. Selection Logic

### 3.1 Phase A design phase default (subject to Forge Stage 5 DM admission gate)

**Default: Path A (Sequential)** — pending Forge Stage 5 DM test outcome

**Rationale (qualitative — Codex C5 disposition)**:
1. **Both M4 and bear retained** — captures 31.4% (M4-only) + 68.6% (bear-only) incremental info = ~100% combined coverage in design hypothesis
2. **Production architecture echo** — multiplicative Layer 6 follows Layers 4+5 precedent (NOT a "safe no-op fallback" claim — that requires realized backtest evidence)
3. **Sequential admit precedent established** — Kritzman 2011 (AR Layer 4 admit 2026-05-04, L-277/278) + Kelly 2014 (R05 Layer 5 admit 2026-05-13, L-308)
4. **TO cap hypothesis 4~5/yr** — design estimate only, Forge Stage 5 realized TO replaces hypothesis. If realized TO > 6.0/yr, infeasibility_report mandatory
5. **DM admission gate** — **Path A admission CONDITIONAL on DM 1-sided p < 0.15 + mean(d_t) > 0 + 3+/5 windows + HIGH_VOL_TAPER or INFLATION significant**. If DM fails, sensor REJECT entirely (no Path A admission). See `m4_incrementality_protocol.md` Section 6.

### 3.2 Conditional branch — Replacement (Path B)

**Triggered if and only if**:
- Forge Stage 5 DM test p_bad_t vs M4 standalone p-value < 0.05 AND
- p_bad_t outperforms M4 net_SR in 3+ of 5 walk-forward windows AND
- Underlying TO_ann remains ≤ 6.0/yr cap AND
- Manifest v2.3 → v3.0 architectural rename approved by 도훈 mandate

**Decision branch ID**: DB-A (see method_shopping_log_optimizer.json)

### 3.3 Rejection — Standalone (Path C)

**Path C reject because**:
- No-bear-sensor production reduces incremental info coverage by 68.6%
- Bear sensor v2.0 W3 OOS AUC 0.6875 + Recall@τ=0.5=1.0 represents real signal value
- WT-D20260518_001 hypothesis specifically targets bear sensor admission — Path C = WT failure mode

---

## 4. Forge Stage 5 Binding

### 4.1 Required emissions

Forge Stage 5 emits 3 backtest variants:

| Variant | Definition | Purpose |
|---|---|---|
| V_Path_A | Path A Sequential 6-layer | Primary admission test |
| V_Path_B | Path B Replacement 5-layer (β_bear replaces m4) | DM test branch DB-A |
| V_Path_C | Path C M4 standalone 5-layer (production v2.3) | Control baseline |

### 4.2 Required metrics per variant

- SR full sample (1990~2026.05) + Lo 2002 CI
- DSR Bailey-LdP n_trials=90
- Net IR vs KOSPI200
- MDD + Calmar + Sortino
- TO_ann full + per-layer breakdown
- Harvey-t 5-spec NW-HAC lag-12 + DSR
- Per-regime AUC + ICIR + Brier + ECE
- Crowding cor with PG2 production alpha
- DM test p-value for Path B admission

### 4.3 Admission decision rule (Forge Stage 6 + Judge G3 / G4)

```
IF Path_A SR > Path_C SR + 0.10 AND Harvey-t 5/5 ≥ 3.0 AND DSR ≥ 1.5:
    ADMIT Path A (Sequential L6 bear)
ELIF DM_p < 0.05 AND Path_B SR > Path_A SR > Path_C SR:
    ADMIT Path B (Replacement) -- DB-A branch
ELIF Path_A SR < Path_C SR:
    REJECT bear sensor admission -- continue PG2 v2.3 production
ELSE:
    HOLD admission, request stratified retrain Variant_M06 (DB-C)
```

---

## 5. Verdict

**Phase A design phase recommendation**: **Path A Sequential** as default policy.

**Forge Stage 5 binding**: V_Path_A + V_Path_B + V_Path_C all 3 variants required. DM test admission for Path B conditional. Stratified retrain Variant_M06 conditional on Path A admission marginal performance.

**Production rollback path**: If admit Path A fails after deployment, β_bear=1.0 universally rolls back to v2.3 production with no architectural change.

---

## 6. References

- Kritzman-Page-Turkington 2011 FAJ (regime overlay multiplicative precedent — Layer 4 admit L-277/278)
- Kelly-Jiang 2014 RFS (tail-risk overlay precedent — Layer 5 admit L-308)
- Diebold-Mariano 1995 (incremental info test for replacement decision)
- Bailey-Lopez de Prado 2014 (DSR for multi-test claim correction)
- Harvey-Liu-Zhu 2016 RFS (multi-testing t-stat threshold)
- Pesaran-Timmermann 2007 JBES (regime stratification)
