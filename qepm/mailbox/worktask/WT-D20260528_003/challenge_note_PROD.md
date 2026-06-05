# Challenge Note — WT-D20260528_003 D_PROD (alpha-research)

**Codex Critic Round**: GPT-5.5 + xhigh, stance = **REJECT** (8 concerns: 4 HIGH + 4 MEDIUM)
**Response file**: `codex_critic_response_alpha_PROD.json`
**Decision Protocol**: Charter §8 No Silent Override. Each concern classified ACCEPT / PARTIAL / REBUTTAL with grounded reasoning.

## Context — 도훈 mandate framing (critical)

도훈 explicit decision: send **single spec "LightGBM base + D_REFINE bandbuffer turnover 제어"** to Forge. This is **NOT a claim of graduation** — it is a forge-handoff of the best-available spec whose **DSR remains FAIL** (the known binding gate of all Cycle 2 variants). Codex's REJECT centers on the gap between the file name "PROD" and the DSR-FAIL reality. **I ACCEPT this framing concern** and re-scope the package as a `forge_handoff` artifact with DSR FAIL explicitly flagged, NOT a graduated production alpha. This resolves the core of REJECT honestly rather than overriding it.

## Auto-escalate trigger check
- HIGH severity concerns = 4 (< 5) → no escalate
- AX axiom hard FAIL = 0 → no escalate
- PIT C1 (lockbox/lookahead) violation = NONE found (walk-forward max sig_date 2023-11-30 < cutoff 2023-12-22, verified) → no escalate
- Codex REJECT + agent rebuttal ALL? NO — 4 ACCEPT + 3 PARTIAL + 1 REBUTTAL → no escalate
- **Conclusion**: no mandatory Q-Lead escalate. Resolve via spec amendment + documented rebuttal.

---

## Concern-by-concern

### C1 [HIGH] — DSR-failing alpha labeled PROD is not process-honest → **ACCEPT**
- **Fact (verified)**: DSR_proper = 3.05e-15, DSR_z = -7.80, net annual SR = 0.306. Binding graduation gate (min_dsr 0.50) = **FAIL**.
- **Resolution**: (1) `challenge_flags` now contains an explicit `DSR_FAIL_BINDING` flag (was empty — C4 also). (2) Package re-scoped `handoff_type = "forge_handoff_dsr_fail_acknowledged"`, `graduated = false`. (3) `final_stance` documents this is the 도훈-selected best-available spec, NOT a graduated alpha. The DSR FAIL is recorded in `graduation_criteria_check.min_dsr_0.50.PASS = false` and surfaced top-level.
- **No rationalization**: I do not claim DSR "is close enough" or "conservative." It FAILS. Forge/Judge inherit this gate.

### C2 [HIGH] — PIT lineage (C13/C14/C15) not established → **PARTIAL**
- **C15 (direct parquet load)**: ML carve-out for daily parquet direct load is **explicitly approved for this WT** (task brief: "C15 carve-out: ML + daily parquet 직접 load 예외 승인됨"). Citing approved carve-out, not a violation. L-164 v1.1 ML carve-out precedent.
- **C13 (raw z-score)**: target is `target_zxs` (cross-sectional z, no sign-flip / NEGATE). Z_Score_Aligned discipline holds for the label; features are raw daily-factor columns under the ML carve-out.
- **PARTIAL accept**: C14 Usable_Date and C4 fundamental-lag page-level proof are NOT separately re-attested in this package (inherited from upstream D_ML panel build). I add `pit_assertions.c14_c4_inherited_from = "WT_D20260528_003_overnight_D_ML panel build"` and flag for Judge to verify the upstream panel's PIT attestations rather than re-asserting blindly.

### C3 [HIGH] — 5-spec robustness is CAPM-only → **ACCEPT (documented scope)**
- **Fact (verified)**: `five_spec_results.json` runs CAPM only (α_annual 6.19%, t_NW 0.741); Carhart-4F / FF5 / Q5 = "KR_factor_DB_integration_required."
- **Resolution**: The single CAPM t=0.741 does NOT substitute for the IC-HAC t=4.31 — these measure different things (portfolio α vs cross-sectional signal). I do NOT conflate them. Full 5-spec multi-factor attribution requires KR SMB/HML/RMW/CMA/QMJ factor returns and is **forge/judge stage scope** (Brinson + Carhart attribution, Research Philosophy P7). Flagged in `challenge_flags` as `FIVE_SPEC_INCOMPLETE_FORGE_SCOPE`. Alpha stage delivers cross-sectional IC validity (HAC t=4.31, p<3.5e-5); portfolio multi-factor α is downstream.

### C4 [HIGH] — No Silent Override: empty challenge_flags + stale artifacts → **ACCEPT + PARTIAL**
- **ACCEPT (challenge_flags)**: was `[]` despite DSR FAIL. Now populated: DSR_FAIL_BINDING, FIVE_SPEC_INCOMPLETE_FORGE_SCOPE, LIQ_FLOOR_5E7_VS_2E8_DEFER_OPTIMIZER, AX001V2_SOFT_PROXY_ONLY.
- **PARTIAL (stale artifacts)**: I placed **fresh** canonical artifacts at `stage_artifacts/WT_D20260528_003/` (alpha_scores.parquet max date 2023-11-30, alpha_validation.json, weights_schedule.parquet) at this cycle. The v3.6 archive files remain in `qepm/mailbox/.../archive_v3_6/` (intentional history, not active). The active namespace now points to D_PROD outputs.

### C5 [MEDIUM] — Liquidity 5e7 vs 2e8 hard floor → **PARTIAL (defer to optimizer/forge)**
- **Fact**: request.json sets `liquidity_min_won_20d_avg = 50000000` (5e7); CLAUDE.md hard mandate = 2e8. The request explicitly relaxed to 5e7 for this discovery WT universe (max 500 names).
- **PARTIAL**: Final 2e8 + t-1 PIT (C10) liquidity enforcement on the **20-name traded book** is **optimizer/forge scope** (alpha emits full cross-section scores). D_ENSEMBLE `top20_liquidity_audit.csv` already audited top-20 against t-1 2e8 and passed. I flag `LIQ_FLOOR_5E7_VS_2E8_DEFER_OPTIMIZER` so optimizer/forge enforce 2e8 on the executable book. The alpha panel itself is scored over the request's 5e7 universe — not an alpha violation.

### C6 [MEDIUM] — covariance/weights absent, condition number 291.8 → **REBUTTAL (out of alpha scope)**
- **Academic/process grounding**: Common Charter principle 8 + alpha_research_init.md `<strict_prohibitions>` #1/#2: alpha-research is **forbidden** from producing covariance matrices or portfolio weights (Hook `agent_role_guard` hard-block). The `weights_schedule.parquet` I emit is a **bandbuffer candidate ranking** (signal→ranking, AX-007 ML sizing carve-out), NOT a risk-optimized weight vector.
- **L-code**: AX-007 exception #4 (ML sizing) governs the bandbuffer ranking. Covariance Σ + condition-number shrinkage (target ≤100) is **risk-research scope** (`risk_D_pipeline.R` already produced PSD Σ; cond=291.8 is a risk-stage finding for risk-research to shrink, not alpha).
- **Quantitative**: the cond=291.8 number Codex cites comes from `risk_D_pipeline.R` (risk artifact), confirming this is downstream. Alpha cannot and must not touch it. **REBUTTAL accepted on scope grounds** — I will not add covariance/weights (would trigger Hook block + Charter violation).
- **Self-rationalization check**: no "관행적/미미/보수적" used. This is a hard role-boundary, not a convenience.

### C7 [MEDIUM] — citations loose + n_features=30 understates 75-feature model → **ACCEPT**
- **Fact (verified)**: model uses **30 pruned alpha features + 45 sector dummies (drop_first) = 75 model columns** (`02_lightgbm_walkforward.py` line 71-76; cv_results n_features=75). The "30 features" label understates.
- **Resolution**: amended to `n_alpha_features = 30, n_sector_dummy_controls = 45, n_model_columns_total = 75`. Sector dummies are **neutralization controls** (industry-neutral signal), not alpha signals — disclosed precisely. References (Roll 1984, Amihud 2002, Gu-Kelly-Xiu 2020) retained as **mechanism grounding (origin, not approval)** per Charter principle 4; KR-specific mechanism is empirically tested (subperiod IC, AX-001 v2), not merely asserted.

### C8 [MEDIUM] — AX-001 v2 soft-proxy only → **PARTIAL**
- **Fact**: bad/normal IC ratio 0.759 (PASS ≥0.5) computed on **bottom-25% cross-sectional mean-return** regime (the standard KR relative-quantile crisis proxy used identically across D_ENSEMBLE + D_REFINE). Hard absolute crisis (KOSPI 1M < -5%/-10%) has **0 dates** in the 2014-2023 forward-return window (verified: bm 1M log-ret min = -4.02%) — a **data reality**, not a method shortcut.
- **PARTIAL**: I accept that Core-relative MDD mitigation (AX-001 v2 full: crisis_alpha + Core-relative MDD + bad/normal ratio) is NOT fully closed at alpha stage — Core-relative MDD requires the optimized portfolio + benchmark NAV (forge scope). The bad/normal ratio component (0.759) PASSES; the MDD-mitigation component is deferred to forge/risk. Flagged `AX001V2_SOFT_PROXY_ONLY`.

---

## Resolution summary
- **ACCEPT (4)**: C1, C3, C4, C7 → spec/documentation amendments applied (challenge_flags populated, handoff re-scoped, n_features disclosed, 5-spec scope flagged).
- **PARTIAL (3)**: C2, C5, C8 → component accepted + remainder deferred to correct downstream stage (Judge PIT re-verify / optimizer 2e8 / forge Core-relative MDD).
- **REBUTTAL (1)**: C6 → hard role-boundary (alpha cannot emit covariance/weights; Charter §8 + Hook). Grounded in Charter principle 8 + AX-007 + the cond=291.8 being a risk-stage artifact.

## Self-rationalization audit (mandatory)
grep for "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일" in my rebuttals → **0 hits**. No rationalization phrases used. The single REBUTTAL (C6) rests on a hard role-prohibition, not convenience.

## Net outcome
Codex REJECT is **substantively addressed, not overridden**: the package is finalized as a **forge_handoff with DSR FAIL explicitly acknowledged and not graduated**. This is the honest realization of 도훈's mandate (best-available spec to Forge) while respecting the binding DSR gate. The verified feature-set decision (30f over 162f) stands on its own evidence.
