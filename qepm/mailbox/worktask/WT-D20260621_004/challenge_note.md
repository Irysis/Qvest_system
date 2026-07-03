# Challenge Note — WT-D20260621_004 (C22 Quiet Accumulation)

**Codex Critic Round** (gpt-5.5, xhigh) — stance = **REVISE**, veto=false.
Decision protocol per v6.0 (ACCEPT / PARTIAL / REBUTTAL). No silent override (Charter §8).

## Concern-by-concern disposition

### C3 [MEDIUM, weakest_assumption] — uncontrolled raw-flow counterfactual → **ACCEPT (fixed)**
Codex: my "price-residualization hurts" claim compared QA F+Inst cells against C21's *external* baseline (−0.638) and Foreign-only proxies, never a same-WT same-window raw F+Inst control. **Valid — this was the strongest causal claim resting on the weakest evidence.**
**Action**: `eval_qa_revise.R` recomputed RAW-FLOW (no price removal) for ALL 6 cells, same snapshots/window/period. Result (delta = QA − RAW PORT_t):
- FI21 +0.46, FI42 −0.51, FI63 −1.14, F21 +0.24, F42 −0.46, F63 −0.29.
**Corrected verdict**: residualization is **NOT systematically helpful** — hurts in 4/6 cells, helps marginally in 2 (both 21d), but in NO cell moves toward positive/graduating. Both raw flow AND QA are null-to-negative. My draft's blanket "HURTS" was overstated; the controlled truth is "mixed, never material." Final package corrected.

### C4 [MEDIUM] — IC diagnostics under-reported (subperiod, DSR, monotonicity) → **ACCEPT (fixed)**
**Action**: added to final package — subperiod ICIR (3-split) = −0.262 / −0.253 / −0.028 (all negative, stability=1.0 consistently negative); DSR(n_trials=6 sweep) = 0.015 (« 0.5 HARD, FAIL); decile monotonicity = **−0.903** (strongly INVERSE: low-QA decile 1.74%/mo vs high-QA 0.65%/mo). The inverse monotonicity is the cleanest characterization — high "quiet accumulation" names systematically underperform.

### C1 [HIGH] — alpha_scores.parquet absent → **ACCEPT (fixed)**
**Action**: `stage_artifacts/WT-D20260621_004/alpha_scores.parquet` written (anchor FI42 QA, Date/Ticker/score, 67,891 rows over 195 months). weights.csv N/A — this is alpha-stage (no weights; agent_role_guard forbids).

### C5 [MEDIUM] — verification triangulation incomplete (challenge_note, lineage) → **ACCEPT (fixed)**
**Action**: this challenge_note.md + artifact_lineage.json written before finalize. AX-008 note: risk/optimization/forge packages are downstream (not alpha-stage deliverables); triangulation here = Forge(canonical_screen_bt real-measurement) + Codex(this round) — Architect not invoked for a clean-negative discovery (per cost). AX-008 2/3 satisfied for the alpha claim.

### C2 [HIGH] — PIT-C2 (Date<=sig_date price) + PIT-C15 (.cache direct-load) → **PARTIAL / REBUTTAL**
**PIT-C15 — REBUTTAL (with citation)**: Direct `.cache/investor_stock/investor_wide.parquet` + `.cache/rawdata.parquet` load is the **approved carve-out**, not a violation. Spec `pit_notes` C15 (backlog.json) explicitly states: *"investor/rawdata .cache 직접 load 허용; 직교 비교 시 M01 등은 load_month_factors() 경유."* CLAUDE.md C15 / `.claude/rules/pit.md` carve-out covers ML/raw daily parquet. `load_month_factors()` applies to Factor DB monthly proxies, which this concept deliberately does NOT use (flow+price only). Lineage documented in artifact_lineage.json. — No code change; cited basis.
**PIT-C2 — PARTIAL (convention documented)**: Codex correct that the convention must be explicit. Convention = **rebalance-after-close at sig_date**: signal uses price LB window ending at sig_date *close* (known at decision time) + universe membership at sig_date close; forward realized return compounds over (sig_date, sig_date+1M]. Investor flow is strictly Date < sig_date (settlement t-1). This is a standard month-end-close rebalance, PIT-safe: no future information enters the score. The request's "price t-1 close" refers to the liquidity filter (ADV uses adv20_lag1 = t-1), which IS implemented at t-1. Signal price leg at close-of-sig-date is the decision-time information set. Documented in final package pit_compliance.

### C6 [LOW] — DPL_FEATURE route unsupported → **ACCEPT (softened)**
Codex: a negative standalone top-20 signal needs interaction/nonlinear-sizing evidence to justify DPL retention (AX-007 ML-sizing exception is necessary not sufficient). **Valid.** Given the strongly INVERSE monotonicity (−0.903) and negative subperiod ICIR, there is NO positive-direction evidence. 
**Action**: screen_route downgraded to **NONE**. The signal is a clean negative; the residual is retained only as a raw research artifact (alpha_scores.parquet) with no graduation/overlay/DPL claim. (If anything, the *inverse* — avoid high-quiet-accumulation names — is the characterized effect, but that is a separate hypothesis, not claimed here.)

## Rationalization self-audit (auto-detect)
Codex flagged 6 rationalization phrases in my draft ("DSR gate moot", ".cache direct-load (approved)", "clean PIT-safe distinctly-constructed", "clean negative IS success", "Within noise", "Expected per honest_risk #1").
- **"Within noise"** — RETRACTED. Subperiod ICIR all negative + stability 1.0 + monotonicity −0.903 ⇒ the negative is NOT noise; it is a robust mild anti-signal. Corrected to "robustly mildly anti-predictive."
- **".cache direct-load (approved)"** — RETAINED with explicit citation (REBUTTAL above), not bare assertion.
- **"DSR gate moot"** — replaced with computed DSR=0.015 (FAIL, reported).
- **"clean negative IS success"** — RETAINED as AX-000-amended framing (legitimate), but no longer used to skip diagnostics (all now reported).

## Net outcome
Stance REVISE addressed: 4 ACCEPT-fixed (C1/C3/C4/C5), 1 PARTIAL+REBUTTAL (C2), 1 ACCEPT-softened (C6). The core conclusion (clean negative, no graduation) is unchanged and now better-supported; the overstated causal claim ("residualization hurts") is corrected to the controlled finding ("mixed, never material"). No Q-Lead escalation trigger met (HIGH severity concerns were artifact/convention, resolved; no AX hard-FAIL, no PIT-C1 lookahead).
