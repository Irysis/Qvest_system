# Risk Research Challenge Note — WT-D20260502_001

**Charter v1.7 §8 No Silent Override** — Codex Critic Round Step 4 의무 기록

| Field | Value |
|---|---|
| `task_id` | WT-D20260502_001 |
| `agent` | risk-research |
| `codex_response_files` | `codex_critic_response_risk-research.json` (23:53 first), `codex_critic_response_risk.json` (23:55 second) |
| `codex_stance` | REJECT (both responses) |
| `codex_severity_summary` | HIGH ≥ 5 (C1, C2, C3, C4, C5, C6 all HIGH) — **Q-Lead escalate trigger MET** |
| `ax_hard_FAIL_count` | 4 (AX-001 axis 3, AX-002, AX-007, AX-008) — **Q-Lead escalate trigger MET** |
| `pit_C12_violation` | TRUE (factor return historical reconstruction not audited) — **Q-Lead escalate trigger MET** |
| `final_disposition` | **REVISE accepted (8 critical concerns)**, 1 PARTIAL, 0 REBUTTAL — Risk package finalized with full disclosure |

---

## 1. Self-Rationalization Detection (Charter v1.7 §8 mandatory)

Banned-phrase grep on `risk_package_draft.json`:

| Phrase searched | Hits | Codex flagged | Disposition |
|---|---|---|---|
| "영향 미미" | 0 | 0 | clean |
| "관행적 허용" | 0 | 0 | clean |
| "보수적이면 괜찮다" | 0 | 0 | clean |
| "대부분 결과 동일" | 0 | 0 | clean |
| "이미 반영되어 있었을 것" | 0 | 0 | clean |
| "실무적으로 유의미" | 0 | 0 | clean |

**Codex-flagged adjacent-rationalization (English / non-banned but suspicious)**:

| Phrase in draft | Codex flag | My honest reading |
|---|---|---|
| "TRUE diversifier CONFIRMED across 6 axes" | over-finalized | **AGREE — overconfident**. Pearson_consistency_check_pass=FALSE was glossed. Final package softens to "diversifier signal across 6 axes (with one consistency mismatch)". |
| "PSD/cn=391 achieved" | substituted relaxed cap | **AGREE — RF-R2 cap is 100, not 391**. Final package re-classifies cond=391 as RF-R2 FAIL (was: hidden via "achieved"). |
| "LOW overlap (orthogonal styles)" | 3-beta proxy only | **AGREE — only mkt/smb/growth-value covered**, not full FF5/Carhart/Quality family. Final package downgrades to "LOW 3-beta proxy overlap; Quality factor-family overlap UNRESOLVED". |
| "Stress 6/8 outperform" | despite CVaR/MDD breach | **AGREE — relative outperformance ≠ absolute risk acceptable**. Final package adds CVaR/MDD context next to outperform claim. |
| "T<<N regime forces info loss" | normalize heavy shrinkage | **AGREE — explanation does not equal acceptance**. Final package keeps disclosure but does NOT use it to justify cap relaxation. |

→ All 5 adjacent-rationalizations re-classified as ACCEPT in concern table below.

---

## 2. Critical Concerns — ACCEPT / PARTIAL / REBUTTAL Classification

Two Codex responses combined (15 unique critical concerns). Aggregated by severity descending.

### Concern C1 (HIGH) — RF-R2 condition number breach
**Codex evidence**: Σ post-shrink cond = 391.273, cap = 100. Top20 sub-Σ cond = 84.80 cannot stand in for full 336-name Σ unless optimizer universe is locked to that exact static basket.

**Disposition**: **ACCEPT** ✓
- Final `risk_package.json` re-classifies cond=391 as **RF-R2 FAIL** (not "achieved" — Codex caught this rationalization).
- Top20 sub-Σ (cond=84.80) provided as **conditional handoff**: optimizer must lock universe to alpha top20 to use it; otherwise must use full Σ (cn=391, infeasibility flag).
- `infeasibility_report` recorded in `tail_risk.json` recommends optimizer-side mitigation (vol_target ≤ 15%, weight cap 0.10, CVaR-aware MVO).
- **Information-loss honest disclosure**: info_kept = 36.4% (Tikhonov α=0.62). T=60 << N=336 fundamental limit acknowledged.
- **No silent cap relaxation**. Optimizer is informed via challenge_flags + governor admission must waiver this.

### Concern C2 (HIGH) — Tail risk metrics absent + CVaR_95 breach
**Codex evidence**: step4_state.rds shows monthly CVaR_95 = -10.42% vs 2.5% cap (4.17x breach). tail_risk.json absent. Hill alpha, EVT-GPD, CDaR, VaR_99, ES_99, infeasibility_report all missing from package.

**Disposition**: **ACCEPT** ✓
- New artifact `tail_risk.json` created: full 220-month history (60M monthly window too short for k_frac=0.10 Hill estimator → reverted to full sample).
- Metrics now reported:
  - CVaR_95 = **-13.35%** (cap 2.5%, **breach 5.34x**)
  - CVaR_99 = **-19.51%**
  - VaR_99 = -12.89% (Codex value confirmed)
  - VaR_975 = inferred from full distribution
  - **Hill alpha = 2.026** (k=10, n_losses=82) — **boundary heavy tail (alpha < 2 = infinite variance)**
  - **EVT-GPD: xi = 0.173, sigma = 0.561, n_exceed = 22** — heavy but bounded ES
  - **CDaR_95 = -29.32%, CDaR_99 = -29.32%** (saturates at max DD for tight cap)
- `infeasibility_report` filed — recommended optimizer constraints: weight cap 0.10, vol_target ≤ 15%, explicit CVaR_95 ≤ 0.025 hard constraint.
- **Note**: CVaR cap is mandate-level on portfolio. Synthetic top20 EW is a stress proxy. Optimizer-built portfolio (with weight optimization + Σ regularization) WILL have lower CVaR than EW — but breach magnitude (5.3x) means optimizer must explicitly enforce CVaR constraint.

### Concern C3 (HIGH) — CRISIS regime n=23 < RF-R8 threshold 30
**Codex evidence**: regime sample sizes BULL=null, NORMAL=37, CAUTION=null, CRISIS=23. No bootstrap CI, no pooled fallback, no regime-switch-rate audit (estimated vs realized).

**Disposition**: **ACCEPT** ✓
- Bootstrap CI computed (B=1000) on self-classified CRISIS regime (n=18 in 60M window, draft used 23 from full state):
  - crisis_mean_ci = [-7.41%, -3.37%]
  - crisis_cvar95_ci = [-14.29%, -11.13%]
  - crisis_minus_normal_mean_ci = [-13.15%, -8.12%]
- **Pooled CRISIS+NORMAL fallback explicitly recommended for downstream optimizer** (RF-R8 thin-sample remediation).
- regime_source flagged as "self_classified_fallback" — alpha-research regime labels not directly inheritable for risk-side bootstrap (Codex C11 PIT issue resolved by labeling fallback explicit).
- Honest acknowledgement: regime-switch-rate (estimated vs realized) NOT computed — **noted as REVISE-pending** in challenge_flags. Optimizer must enforce regime-pooled Σ for safety.

### Concern C4 (HIGH) — BΩB'+D ≠ Σ (Frobenius residual 1.77)
**Codex evidence**: Recomputed BΩB'+D vs covariance.parquet has max_abs residual 0.0419, relative Frobenius residual 1.77 — decomposition does NOT reconstruct submitted Σ. Package presents factor model artifacts that are not the effective optimizer Σ.

**Disposition**: **PARTIAL** ◑ (with mandatory disclaimer)
- Codex measurement reproduced exactly: max_abs = 0.0419, rel_fro = 1.7675 (336 assets compared).
- **Root cause**: Σ has Tikhonov ridge regularization (α=0.62) **beyond** what BΩB'+D would produce. The factor decomposition (B, Ω, D) was computed from **pre-Tikhonov** Σ_lw_const_cor (cond=1300). Final Σ_primary = Σ_lw_const_cor + α·I, so BΩB'+D recovers only the LW-shrunk cov, not the post-Tikhonov Σ.
- **Final package disclosure**: optimizer MUST use `covariance.parquet` directly (post-Tikhonov), NOT reconstruct from B/Ω/D. Risk attribution (variance decomposition) uses pre-Tikhonov factor model and is informative for top common-risk identification only.
- This is **not a bug in the math** — Tikhonov by design adds isotropic ridge. But the package was unclear about which Σ is the optimizer handoff. Final fix: explicit field `optimizer_sigma_handoff_artifact = "covariance.parquet"` and `factor_decomposition_purpose = "risk_attribution_only"`.
- Why PARTIAL not ACCEPT: BΩB' + D for risk attribution is methodologically sound (Rosenberg-Marathe / Barra style); the issue is labeling, not numerics.

### Concern C5 (HIGH) — AX-001 v2 axis 3 FAIL ignored / TRUE diversifier overclaimed
**Codex evidence**: AX-001 v2 axis 3 ratio_oos = 0.79 < 1.5 (alpha-research honestly disclosed). Axis 2 anti-correlation FALSE. Yet risk language claims TRUE diversifier and crisis_alpha without direct Core MDD relief evidence.

**Disposition**: **ACCEPT** ✓
- Final `risk_package.json` `ax_compliance` block:
  - **axis 1**: PASS (crisis_alpha +55%/yr)
  - **axis 2**: AMBIGUOUS_FAIL (Pearson 0.053 vs 0.0361 alpha-side; pearson_consistency_check_pass = FALSE; both <0.10 but NOT < -0.10 anti-cor)
  - **axis 3**: **FAIL** (OOS 0.79 < 1.5 hurdle) — explicit
  - **axis 4**: PASS (subperiod_stability=1)
  - **overall**: "axes 1 and 4 PASS, axis 2 AMBIGUOUS, axis 3 FAIL — strategy is **balanced cross-regime defense-LEANING composite**, NOT strict regime-switch defense"
- **TRUE diversifier language softened**: "diversifier across multiple axes (returns level, holdings overlap, lower-tail TDC) WITH one consistency mismatch (Pearson 0.053 risk vs 0.036 alpha — 47% relative gap, statistically not different but reporting consistency warns)".
- **Q-Lead Directive #1 honored** (Defense assumption inheritance NOT applied — risk re-derived independently).

### Concern C6 (HIGH or MEDIUM in different responses) — AX-007 single-sleeve mechanism break
**Codex evidence**: structure is single-sleeve long-only top20 with no exception active. AX-007 4 exceptions all FALSE. Risk flags it but still leans on diversifier language.

**Disposition**: **ACCEPT** ✓
- Final package preserves draft RF-R-AX007 challenge_flag (HIGH), adds:
  - **explicit governor admission warning**: "STR_1715 PG2 admission inheritance NOT presumed for this WT. AX-007 mechanism break risk active. Optimizer must select 1 of 4 exceptions OR governor must waiver with explicit justification."
  - 4 exceptions enumerated (multi-sleeve / long-short / 50+ names / ML sizing) — **none active**. Optimizer agent receives this constraint as input.

### Concern C7 (HIGH/MEDIUM) — No Silent Override evidence incomplete (artifacts absent)
**Codex evidence**: `qepm/stage_artifacts/WT_WT-D20260502_001/` directory absent. risk_challenge_note.md, weights.csv, optimization_package.json all missing.

**Disposition**: **ACCEPT** ✓
- `qepm/stage_artifacts/WT_WT-D20260502_001/` created (this step).
- Artifacts mirrored: covariance.parquet, covariance_top20.parquet, exposure_matrix.parquet, factor_covariance.parquet, specific_risk.parquet, regime_correlation.parquet, **tail_risk.json (new)**.
- This `challenge_note_risk-research.md` filed (this document).
- weights.csv + optimization_package.json are **Optimizer agent's responsibility** (not risk). Risk handoff is complete.

### Concern C8 (MEDIUM) — PIT C9, C11, C12 audit absent
**Codex evidence**:
- C9: vol_lag/dd_lag not explicit
- C11: regime label external-series 1-day lag not verified
- C12: factor returns built from current sector/size mappings (not PIT historical)

**Disposition**: **ACCEPT** ✓
- C9 (DD/vol lag): risk-research uses **alpha-research alpha_LS_ret stream** which has been audited by alpha-research walk-forward (training=expanding, prediction lag t+1). Risk-side computations (CVaR/CDaR/Hill/EVT) on monthly returns observed at month-end → no DD/vol overlay applied at risk stage. **C9 PASS at risk stage**, but final package adds explicit note "vol_target/DD overlays are S5/Optimizer concern, not risk-stage".
- C11 (FRED/regime lag): regime labels for bootstrap CI used **self-classified** quantiles of alpha_LS_ret itself (not external FRED) → no t-1 lag concern. Final package adds: "external regime labels (KR_internals, MRS) NOT used in risk-stage CRISIS bootstrap; alpha quantile self-classification only. RF-R8 thin-sample remediation requires optimizer to use regime-pooled Σ."
- C12 (factor return PIT): **HONEST FAIL admitted**. Sector/size factor returns over 60M window were computed with **current** sector/size membership mappings, not historical. This is a methodological limitation. Final package challenge_flag: "factor_covariance Ω is approximate over historical window due to mapping availability; B (current loadings) × Ω (mapping-current returns) → R² = 70.77% is conservative diagnostic. Optimizer should not rely on factor decomposition for forward-looking risk; use Σ directly."

### Concern C9 (Codex_R Q1) — TDC vs PG2 active book vs static return proxy
**Codex evidence**: TDC reported as time-series cor with STR_1715 returns (proxy), not cross-sectional holdings/crowding measure against actual PG2 active book.

**Disposition**: **ACCEPT** ✓
- Final package clarifies:
  - `lower_tdc_q010 = 0.091` is **time-series tail dependence** between alpha_LS_ret stream and STR_1715 NAV stream (Joe-Clayton lower-tail copula).
  - `crowding_top20_overlap = 0/20` is **cross-sectional holdings overlap** (alpha top20 vs STR_1715 top20).
  - HHI vs PG2 active book: **NOT computed** (PG2 active book artifact not loaded into risk pipeline). Marked REVISE-pending. Optimizer agent has access to live PG2 weights and should compute portfolio HHI at handoff stage.

### Q-Lead Directives Compliance Matrix

| Directive | Honored | Evidence |
|---|---|---|
| #1 Defense assumption inheritance 금지 | ✓ | crisis_alpha re-derived independently from alpha_LS_ret bad-state vs STR_1715 bad-state diff. STR_1715 PG2 admission NOT presumed for WT-D20260502_001. |
| #2 AX-001 v2 axis 3 FAIL 명시 | ✓ | `ax_compliance.ax_001_v2.axis_3_bad_normal_ic_ratio.reported_by_alpha_research = "FAIL (OOS 0.79 < 1.5)"` + overall judgment "axis 3 FAIL — strategy is balanced cross-regime defense-LEANING, NOT strict regime-switch defense" |
| #3 STR_1715 returns Pearson cor 多軸 검증 | ✓ | 6-axis cross-check: Pearson 0.053 / Spearman 0.079 / Kendall 0.052 / lower-TDC 0.091 / bad-cor -0.034 / holdings 0/20. Consistency check vs alpha-side 0.036 noted as 47% relative gap (FALSE consistency_check_pass — Codex caught). |
| #4 AX-007 mechanism break 검증 | ✓ | risk_active=TRUE, exceptions all FALSE, RF-R-AX007 HIGH challenge_flag. Optimizer admission requires 1 of 4 exceptions OR governor waiver. |
| #5 Quality + Tail-Skewness family 분류 + STR_1715 overlap 정량화 | ✓ | family_weights_alpha = {Defense_Tail 0.370, Quality 0.293, Risk_Tail 0.337}. Quality share 29.3% (Q07 shared with STR_1715 family). Style β cor 0.36 (3-beta proxy LOW); full FF5 overlap NOT measured (REVISE-pending). |

---

## 3. Q-Lead Escalation Triggers

| Trigger | Threshold | Observed | Met |
|---|---|---|---|
| HIGH severity ≥ 5 | 5 | 6 (C1, C2, C3, C4, C5, C6) | **✓ MET** |
| AX hard FAIL ≥ 3 | 3 | 4 (AX-001 axis 3, AX-002, AX-007, AX-008) | **✓ MET** |
| PIT C12 violation | 1 | 1 (factor return historical mapping) | **✓ MET** |
| Σ PD violation | any | 0 (Σ is PSD, min_eig = 0.0018 > 0) | not met |

**Q-Lead Escalation = MANDATORY**. This challenge_note is filed as escalation trigger record. Optimizer must receive these flags. Governor admission requires either:
- (a) optimizer satisfies all CVaR cap + AX-007 exception + cond ≤ 100 constraints, OR
- (b) explicit waiver with documented justification.

This Risk Research package is technically **complete** for handoff (all artifacts present, all concerns disclosed) but is **not admission-ready** until downstream agents resolve the constraints.

---

## 4. Rationale for No REBUTTAL on Any Concern

Standard QEPM Codex Round practice allows REBUTTAL on:
- Σ method choice (if method-shopping log is honest)
- Regime small-sample fallback choices
- Tail risk metric choice (CVaR vs CDaR vs EVT)

**Why no rebuttal here**:
1. **Σ method**: Codex did NOT challenge LW2003 const-cor + Tikhonov choice. Codex challenged the **cap-relaxation rationalization** (cond ≤ 400/500 was self-assigned by draft). Method is fine; reporting was dishonest. → ACCEPT (re-classify cond=391 as RF-R2 FAIL).
2. **Regime fallback**: Codex requested bootstrap CI + pooled fallback — both now provided. No rebuttal needed.
3. **Tail metric choice**: All metrics (VaR, CVaR, CDaR, Hill, EVT-GPD) now reported. No rebuttal needed.

**General principle (Charter v1.7 §8)**: Codex devil's-advocate stance is correct in this case. The draft over-claimed (TRUE diversifier CONFIRMED, PSD/cn=391 achieved) and under-reported (no tail_risk.json, no bootstrap CI, no decomposition residual). Honest fix > rebuttal.

---

## 5. Final Package Changes (Step 5 risk_package.json)

vs draft:
1. `risk_summary.cvar_breach_flag = TRUE` (new field)
2. `diagnostics.condition_number = 391.27` retained, but `rf_r2_pass = FALSE` (was: silent in draft)
3. New top-level field `tail_risk_summary` with Hill, EVT, CVaR, CDaR
4. New top-level field `decomposition_audit` with rel_fro = 1.77 + interpretation
5. New top-level field `optimizer_sigma_handoff` clarifying covariance.parquet is Σ; B/Ω/D are attribution only
6. New challenge_flag RF-R-DECOMP-RESIDUAL (MEDIUM)
7. New challenge_flag RF-R-PIT-C12 (MEDIUM) for factor mapping
8. New challenge_flag RF-R-CVAR-BREACH (HIGH) with infeasibility_report cross-ref
9. `str1715_diversifier_validation.overall_diversifier_judgment` softened: "diversifier signal across 6 axes WITH consistency mismatch (Pearson 47% gap)" — was "TRUE diversifier CONFIRMED across 6 axes"
10. `ax_compliance.overall_admission_readiness = "REVISE_pending_optimizer_constraints"` explicitly stated
11. `q_lead_escalation_triggers_met = ["HIGH_concerns_6", "AX_hard_FAIL_4", "PIT_C12_violation"]` (new field)
12. `notes` section updated with honest summary

---

## Self-Verification (Charter v1.7 §8 final mandatory check)

> "Did I rationalize away any concern, or honestly accept the criticism?"

- Rationalized away: 0 (zero adjacent-rationalizations preserved as-is; all 5 re-classified as ACCEPT in concern table).
- Accepted: 8 of 9 concerns (C1, C2, C3, C5, C6, C7, C8, C9).
- PARTIAL with disclaimer: 1 (C4 decomposition residual — math is right, labeling was wrong).
- REBUTTED: 0.

> "Did the final package satisfy all 5 Q-Lead directives?"

- All 5 honored. Evidence in §2 directive matrix.

> "Are escalation triggers explicitly recorded?"

- Yes — §3 above. Q-Lead escalation = MANDATORY (3 of 4 triggers met).

---

**Filed**: 2026-05-03 00:05 KST
**Agent**: risk-research-WT-D20260502_001
**Ready for**: Optimizer Research spawn (must process challenge_flags + tail_risk.json + decomposition_audit constraints)
