# Forge Challenge Note — WT-D20260517_003 DPL-RC v1.0 (FINAL)

**Author**: Forge agent (Q-Lead orchestrated)  
**Date**: 2026-05-17T17:50:00+09:00  
**Cycle**: Forge feasibility (Step 6.1~6.9 + Codex 7-concern remediation)  
**Self-stance**: **DEFER** (3 structural blockers + Codex agreement)  
**Codex stance**: **REVISE** (veto_flag=false) — 7 concerns (5 HIGH + 2 MEDIUM)  
**AX-008 status**: Forge 1/3 PARTIAL + Codex 2/3 PARTIAL_AFTER_REMEDIATION → 2/3 target reached on negative outcome (DEFER consistent)

---

## 0. Codex disposition summary (7 concerns)

| ID | Severity | Concern | Disposition | Status |
|---|---|---|---|---|
| C1 | HIGH | weights.csv sig_date range (2020-08 to 2025-09 NOT 2018-08 to 2021-12) + alpha_scores missing Date column | **ACCEPT** — correction emitted | RESOLVED |
| C2 | HIGH | monthly_returns.parquet absent | **ACCEPT** — emitted | RESOLVED |
| C3 | HIGH | No Harvey 5-spec t_NW + DSR | **ACCEPT** — full 5-spec audit emitted | RESOLVED |
| C4 | HIGH | turnover formula × 12 not round-trip × 2 | **PARTIAL_ACCEPT** — corrected with explicit one-way (2.82) vs round-trip (5.64) split, both ≤ cap 6.0 | RESOLVED |
| C5 | HIGH | No lockbox marker / Pre-LB/Lockbox/Combined report | **ACCEPT** — marker added 2024-01-23 + 3-way split report emitted | RESOLVED |
| C6 | MEDIUM | covariance.parquet only summary not min_eig/PSD | **ACCEPT** — enhanced with min_eig + max_eig + cond_num + PSD + det per sig_date | RESOLVED |
| C7 | MEDIUM | G1 fail but Forge labeled selected candidate | **ACCEPT** — selection_status=DIAGNOSTIC_ONLY + admission_eligibility=FALSE explicit | RESOLVED |

**Codex unresolved disputes** (note + path-forward documented):
- Path divergence `qepm/stage_artifacts/WT_WT-D20260517_003` vs `stage_artifacts/WT_D20260517_003` — Forge used the latter (no `WT_WT-` prefix). Codex flag noted; path can be symlinked if Judge cycle requires.
- OOS window claim 2018-08~2021-12 was an error in draft text (text-only typo, actual weights.csv emits 2020-08~2025-09). Now corrected.
- Lockbox handling for 2024-2025 dates: STR_1715 lockbox start 2024-01-23 (L-308) → Forge re-emits with explicit marker + Pre-LB/Lockbox/Combined split.
- xgboost / nnet substitution for LightGBM / PyTorch Set-Sequence: **environment constraint** (Python sklearn / lightgbm / torch unavailable in WSL Rscript-only environment). Paradigm-equivalent (gradient boosting + small Neural). Forge documents trade-off + acknowledges Codex flag.
- G1 HARD_ABORT but candidate ranking emitted: now labeled DIAGNOSTIC_ONLY (not admission candidate).

---

## 1. Critical findings (structural blockers, post-remediation)

### Blocker 1 — G1 p_bad classifier recall FAIL (alpha_package §G1 hard ABORT)

| Metric | Threshold | Measured | Pass |
|---|---|---|---|
| AUC | ≥ 0.55 | **0.600** | ✅ |
| Brier | < 0.24 | **0.219** | ✅ |
| Recall | ≥ 0.60 | **0.089** | ❌ FAIL |

Per-window detail (3 walk-forward sub-periods):
- W1 (train 1-30, test 31-50): AUC 0.533, Brier 0.232, Recall 0.000
- W2 (train 1-50, test 51-70): AUC 0.575, Brier 0.215, Recall 0.167
- W3 (train 1-70, test 71-90): AUC 0.692, Brier 0.211, Recall 0.100

**Root cause**: classifier at default 0.5 threshold misses 91% of true bad-state events.

### Blocker 2 — A-option architectural invariant FORCES cor ≈ 1.0 (axis_6 FAIL)

| Candidate | cor_1715 (target ≤ 0.30) |
|---|---|
| All 16 candidates | **0.9996 ~ 0.9999** (FAIL by orders of magnitude) |

**Mechanism**: complement universe ⊂ 1715 top-20 → complement portfolio holds same 20 stocks. Blend = convex combination of correlated portfolios → cor ≈ 1.0.

**Trade-off origin**: Codex C2 (optimizer-research cycle) mandated portfolio union ≤ 20 strict → A-option implementation → cor invariant. The architectural fix to portfolio-size constraint inadvertently violates the orthogonality requirement.

### Blocker 3 — production admit SR 1.9536 ≠ canonical weights SR 0.37 (5-Layer overlay vs alpha-only basis)

| Basis | Source | SR | Period |
|---|---|---|---|
| Production admit (L-308~313) | 5-Layer (alpha+M4+AR+R05) overlay | **1.9536** | 255m PerfA |
| Canonical weights (this Forge baseline) | weights.csv alpha-only | **0.3691** | 146m 2014-01~2026-03 |
| Same-period 1715 (40m test window) | weights.csv alpha-only | **0.6817** | 40m 2020-08~2025-09 |
| DPL-RC selected blend (this Forge) | weights blend alpha-only | **0.5378** | 40m same |

**Cross-base incomparability**: Backtest Contract v1.0 + L-282 PerformanceAnalytics convention drift precedent prohibits cross-base.

### Blocker 4 — drag 0.13-0.17 SR points (axis_3 FAIL, target ≤ 0.05)

All 16 candidates introduce 0.13-0.17 SR-points drag on good-state subset.

### Blocker 5 — bad_imp NaN (axis_4 unmeasurable)

Test window 2020-08~2025-09 OOS slice (40m) has **zero bad_state events** under def1_x3 threshold.

---

## 2. Harvey 5-spec + DSR audit (C3 remediation)

**Strategy (DPL-RC selected blend, 40m OOS)**:

| Spec | alpha_monthly | t_NW | p | R² |
|---|---|---|---|---|
| CAPM | +0.0025 | +1.15 | 0.257 | 0.002 |
| FF3 | +0.0030 | +1.22 | 0.231 | 0.037 |
| Carhart4 | +0.0027 | +1.18 | 0.247 | 0.076 |
| FF5 | +0.0033 | +1.34 | 0.190 | 0.083 |
| FF6 | +0.0030 | +1.28 | 0.209 | 0.114 |

**Harvey threshold t > 3.0 (multiple testing)**: **0/5 PASS**. No significant alpha against any factor model.

**DSR Bailey-LdP (N_trials=16, n=40)**:
- SR_obs = 0.5378
- Deflation = 0.3723
- SR_deflated = **0.3375**

**Same-period baseline STR_1715 standalone (40m, same DSR penalty)**:
- SR_obs = 0.6817 (Harvey 5-spec see harvey_5spec_dsr_audit.json)
- SR_deflated ≈ 0.428

**ΔSR_deflated = -0.090** (DPL-RC blend strictly dominated by 1715 same-period under same DSR penalty).

---

## 3. Turnover audit (C4 remediation)

Round-trip × 2 convention explicit:

- Per-period one-way (Σ|Δw|/2): **0.2350** monthly mean
- Annualized one-way × 12 = **2.82**
- Annualized round-trip × 2 = **5.64**
- Both below cap 6.0 (one-way and round-trip)

Previous draft reported 5.64 ambiguously — now split explicitly into one-way 2.82 + round-trip 5.64.

---

## 4. Lockbox split report (C5 remediation)

Lockbox start: **2024-01-23** (STR_1715 production lockbox L-308).

Test window 2020-08 to 2025-09 spans:
- Pre-LB: 2020-08 to 2024-01 (41 months)
- Lockbox period: 2024-01 to 2025-09 (~20 months observed within test)

equity_curve.png re-emitted with vertical dashed marker at 2024-01-23 + 3-way (Pre-LB / Lockbox / Combined) report saved in `lockbox_split_report.json`.

---

## 5. Covariance audit (C6 remediation)

covariance.parquet enhanced from summary-only to full diagnostic:

- 40 sig_dates × 7 columns (sig_date, n_assets, min_eig, max_eig, cond_num, psd, det)
- min_eig range: [0.001250, 0.002075] — all positive
- max cond_num: 19.89 (well below cap 100)
- PSD pass: **40/40**
- Sidecar `sigma_per_sigdate/*.rds` retain (40 matrices, full matrix for re-construction)

---

## 6. Diagnostic-only labeling (C7 remediation)

`admission_decision.json` updated:
- `selection_status`: DIAGNOSTIC_ONLY
- `admission_eligibility`: FALSE
- `selection_purpose`: kept for Pareto frontier identification + measurement transparency
- `admission_status_strict`: HARD_ABORT_G1_FAIL

---

## 7. Pure Function v6.1 R12 audit (CONFIRMED)

MD5 hash check start vs end:

```
alpha_package.json                 : 2b8c872a796d7eed → 2b8c872a796d7eed  MATCH
risk_package.json                  : 89949cc6c5dca95e → 89949cc6c5dca95e  MATCH
optimization_package.json          : 3638ce2bd0a0d2ba → 3638ce2bd0a0d2ba  MATCH
challenge_note_optimizer-research.md: 3e04bbbb9bde8b32 → 3e04bbbb9bde8b32  MATCH
```

**Pure Function audit: PASS** (no upstream package modification).

---

## 8. Verification Triangulation (AX-008)

- **Forge** (this cycle): PARTIAL_PASS_VALIDATED — measurement transparency + DEFER decision (negative outcome accepted, no fabrication) + 7-concern remediation complete
- **Codex** (this cycle, REVISE veto=false): PARTIAL_AFTER_REMEDIATION — all 7 concerns disposed, structural blockers acknowledged (DEFER directionally correct per Codex stance_rationale)
- **Architect**: NOT_REQUIRED for DEFER (Architect cross-validation only triggers on ADMIT-candidate hypotheses)

**AX-008 floor**: 2/3 PASS required for ADMIT (not applicable here — DEFER decision). 2/3 PARTIAL on DEFER consistent with negative-outcome consensus.

---

## 9. Rationalization self-audit (Charter §8)

Codex flagged 4 rationalization candidates in my draft text:
- "well below 6.0 cap" → **CORRECTED**: replaced with explicit numeric "2.82 one-way / 5.64 round-trip, both ≤ cap 6.0 PASS" (C4 audit shows margin)
- "by construction" → **RETAINED with negative-outcome attribution**: only used to describe **structural failure** (cor invariant under A-option), not rationalization. Codex flag misread context.
- "diagnostic value retained" → **RETAINED with explicit DIAGNOSTIC_ONLY label** (C7 remediation): selection clearly separated from admission. Codex C7 ACCEPTed remediation.
- "Stage 1 Linear PPP sufficient" → **RETAINED with conditional clause**: "under A-option constraint" — empirical evidence (all 4 stages within ΔSR 0.028) supports finding, not rationalization.

**Self-audit verdict**: 1 corrected (C4), 3 retained with evidence/clarification.

---

## 10. Path forward (Q-Lead escalate items)

5 items for Q-Lead decision before re-Forge:

1. **Architectural option re-selection** (Blocker 2):
   - A-option (current) admission-infeasible due to cor invariant
   - **Recommend Option B** (comp ∉ 1715, a_max ≤ 5% strict): preserves orthogonality + portfolio union ≤ 20 via small injection cap

2. **Blend layer specification** (Blocker 3):
   - **Recommend Path A** (NAV-level blend): retains 5-Layer overlay benefit on 1715 side, complement injected at NAV
   - Alternative Path B (weights-level + full 5-Layer): more invasive

3. **G1 p_bad classifier re-spec** (Blocker 1):
   - Threshold-adjusted recall operating point + continuous-target regression alternative + 1715-specific cross-section features

4. **Test window expansion** (Blocker 5):
   - Stratified train/test split ensuring both subsets contain bad_state events
   - Span 2014-02 through 2026-04 with 2018-10 / 2020-03 / 2022-09 / 2024 episode coverage

5. **Stage incremental verdict** (under A-option):
   - All 4 stages converge — Stage 1 Linear PPP sufficient + interpretability bonus
   - Economize compute next cycle (skip Stages 2-4 unless option re-selected)

---

## 11. AX compliance summary (this cycle)

| Axiom | Status |
|---|---|
| AX-000 no_limit | documented — pursued (DEFER ≠ abandon, re-Forge path explicit) |
| AX-001 v2 conditional defense | INDETERMINATE (bad_state events absent OOS) |
| AX-002 PIT process honesty | **PASS** (Pure Function audit + transparent measurement + Codex 7-concern remediation honest) |
| AX-005 defense family exclusion | EXCLUSION via multi-sleeve verified |
| AX-007 single sleeve top20 break | EXCLUSION via multi-sleeve + ML sizing verified |
| AX-008 verification triangulation | Forge 1/3 + Codex 2/3 PARTIAL — DEFER consistent |

---

## 12. Lessons captured (preliminary, post-Codex)

- **L (pending)**: A-option architectural mandate creates **cor invariant** trade-off. Future DPL-RC iterations must choose Option B/C/D-3 to preserve orthogonality OR accept admission-inviable.
- **L (pending)**: Production admit SR (multi-layer overlay) vs canonical weights SR (alpha-only) cross-base prohibition. DPL-RC blend specification must explicitly target **same-base** (NAV-level Path A recommended).
- **L (pending)**: p_bad binary classifier with default 0.5 threshold catastrophic recall fail. Operating-point tuning + continuous regression alternative required.
- **L (pending)**: Codex C1 detection — draft text typo on OOS range — reinforces audit discipline. **Always cross-check claimed period vs actual emitted artifact range** before draft emission.

---

**Forge agent commitment**: All findings raw + transparent. Codex 7 concerns all dispositioned + remediated. No silent override. DEFER decision honest reflection of 3 structural blockers + 2 measurement constraints + Codex evidence-grade audit. Path forward explicit (5 items).
