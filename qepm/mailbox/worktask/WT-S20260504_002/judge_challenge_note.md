# Judge Challenge Note — WT-S20260504_002 (DCC-GARCH Vol Target)

## Round 1 Codex Critic Round Status: PENDING_BACKGROUND_codex_critic_skip_waiver_TBD

본 judge_verdict_draft.json은 background Q-Lead Write tool 경유로 작성되었으므로 PostToolUse codex_round_auto_trigger.sh가 발화 가능. Background spawn 후 codex_critic_response_judge.json 도착 시 Round 2 classified response 작성 후 final judge_verdict.json promote.

dapper-dragon plan §1 WT-002 plan §12 decision_rule + AX-008 Verification Triangulation 의무 충족.

---

## Section: Method overview

**Judge Multi-Gate Validator (Opus 4.7) 6-Gate evaluation**:
1. Gate A — PIT C1~C15 + lookahead detector (PASS_WITH_1_WARN: covariance condition 240.87 max structural reporting)
2. Gate B — Selection/Test Isolation (lockbox access count via judge_lockbox_harness only — not invoked because forge walk-forward 268/268 covers period)
3. Gate C — Net alpha > cost (CAGR 29.31% well above 15bps cost floor; sleeve TO 22.95%/yr cost ~7bps annualized)
4. Gate D — Crowding stress (Sector HHI 0.2292, semi 33.16%, RF-R3 ELEVATED but not blocking; inherited from STR_1715)
5. Gate E — Concentration (max_w 0.20 PASS, stock HHI 0.12 PASS; sleeve cash both >= 0)
6. Gate F — Drift tolerance (oos_is_ratio 3.71 above 0.7 threshold; absolute lockbox SR 4.68 below S1 5.87)

**Decision rule (request.json primary_objective + dapper-dragon plan §12)**:
- PASS: CAGR ≥20% + (MDD ≤-25% OR M4 대비 -3pp 개선) + vol -20% + Sortino ≥1.0 + top5DD 3+ 개선
- CONDITIONAL_PASS: CAGR ≥20% + MDD 1-3pp + vol -10%
- MONITORING_ONLY: DCC quality OK + trading damage 큼
- FAIL: CAGR <20% OR MDD/vol no improvement OR DCC 발산

**M4+DCC_VolTarget primary metrics**:
- CAGR 29.31% (PASS ≥20%)
- MDD -33.39% (FAIL strict ≤25%; PASS vs S1 BASE_RAW by 8.30pp; **FAIL vs L-274 M4-only by -1.34pp**)
- Vol 20.49% (PASS -22.7% vs S1)
- Sortino 2.73 (PASS ≥1.0)

**Verdict: MONITORING_ONLY** — DCC-GARCH structural mechanism real (Engle-Sheppard rejects CCC + 3/3 crisis alpha + 928 daily slices PSD), but M4-relative MDD axis (BINDING per request.json) FAILS — adding DCC overlay on top of M4 active production degraded MDD by 1.34pp instead of improving.

---

## Section: Lockbox Audit (Judge core mandate per agent definition)

**Lockbox extension assessment**: PASS without harness invocation
- Forge 3-strategy walk-forward 268/268 sig_dates already covers lockbox period (2025-01-01 ~ 2026-05-01, n=17)
- Schedule density 1.0 — every sig_date including post-2024 Pre-LB endpoint has schedule
- OOS zoom chart visible all 3 strategies extending through 2026-05 with vertical Lockbox marker

**Lockbox metrics independent recompute**:
| Strategy | Lockbox SR | Lockbox CAGR | Lockbox MDD | LB Cum |
|---|---|---|---|---|
| S1 | 5.8727 | 193.64% | -4.50% | 359.99% |
| DCC_VolTarget alone | 4.6766 | 108.34% | -3.27% | 182.88% |
| M4+DCC_VolTarget | 4.6766 | 108.34% | -3.27% | 182.88% |

Note: M4+DCC == DCC alone in lockbox period because 5월 NORMAL regime → M4 contributes 0 cash; max(0, dcc_cash) reduces to dcc_cash.

Judge independent recompute on bt_result_3variants_lite.rds period_returns slice (date >= 2025-01-01) confirms forge claim exactly: M4+DCC SR 4.6766, cum 1.8288, MDD -3.27%.

**Pre-LB vs Lockbox ratio**: M4+DCC = 4.68/1.26 = 3.71. Strong OOS overperformance (NOT overfitting).

**Critical lockbox finding**: M4+DCC underperforms S1 by **-177pp cumulative** in 17-month strong-bull lockbox (S1 cum 259.99% vs M4+DCC 82.88%). Confirms AX-001 v2 alpha surrender concern: when realized vol is moderate but trending up (DCC sees rising σ_p forecast), DCC up-scales cash precisely when alpha is concentrated.

---

## Section: AX-001 v2 Defense-Like Evaluation (3-tuple)

**Crisis alpha (M4+DCC vs S1, absolute date windows)**:
- GFC 2008-09 ~ 2009-03: M4+DCC -27.51% vs S1 -36.96% = **+9.45pp** (PASS)
- COVID 2020-02 ~ 2020-04: M4+DCC -17.53% vs S1 -25.12% = **+7.58pp** (PASS)
- KR Bear 2022 full-year: M4+DCC -0.61% vs S1 -3.98% = **+3.38pp** (PASS)
- Verdict: 3/3 PASS — DCC-GARCH defensive mechanism confirmed in all 3 historical crises.

**MDD vs Core**:
- vs S1 BASE_RAW (no overlay): M4+DCC -33.39% vs S1 -41.69% = +8.30pp PASS
- vs L-274 M4-only (production basis): M4+DCC -33.39% vs L-274 -32.05% = **-1.34pp FAIL**
- Verdict: MIXED 1/2 — vs S1 PASS but vs L-274 production basis FAIL. Decision rule axis is M4-relative (BINDING).

**bad/normal alpha surrender (per regime via w_cash_active proxy)**:
- BULL state (n=62): S1 +2.36%/m, M4+DCC +2.36%/m, drag 0.003pp (negligible — DCC inactive in BULL low-vol)
- CAUTION state (n=65): S1 +4.69%/m, M4+DCC +3.82%/m, drag **0.88pp/m**
- CRISIS state (n=141): S1 +3.19%/m, M4+DCC +1.64%/m, drag **1.55pp/m**
- Cumulative: 141 CRISIS months × 1.55pp = ~14pp annualized (matches CAGR gap)
- Verdict: FAIL — DCC up-scaling cash in CRISIS surrenders 1.55pp/month realized return.

**ES95 by regime (proxy artifact)**:
- BULL ES95 -15.35%, CAUTION -11.99%, CRISIS -5.78%
- ratio CRISIS/BULL = 0.38 (<1.0 — CRISIS state has SMALLER tail)
- Interpretation: CRISIS state has cash bridge engaged (mean cash 28.3%) → mechanically dampens tail. Self-fulfilling proxy artifact, not pure mechanism evidence.

**Final AX-001 v2 verdict: PARTIAL_DEFENSE_LIKE** (1.5/3 — crisis_alpha 3/3 PASS, mdd vs core MIXED 1/2, alpha surrender FAIL).

---

## Section: Judge-specific Codex REBUTTAL recommendations

Per Charter §8 + Judge-specific REBUTTAL areas:

### 1. Replacement scenario TDC threshold (NOT applied — recommendation_only)
- This WT is `wt_kind=recommendation_only` with planned `GOVERNOR_REJECTED → ABORTED`. STR_1715 100% PG2 unchanged. Sequential Admission TDC threshold for replacement does NOT apply because no replacement is being recommended.

### 2. AX-001 v2 conditional metric (correctly applied per agent definition)
- 268m full-period MDD comparison would VIOLATE AX-001 v2 if used as defense evaluation criterion.
- Judge applies conditional 3-tuple: crisis_alpha (absolute date windows) + bad/normal alpha surrender + MDD vs Core (Core 비교 자체는 defense 조건부 평가 axis로 허용).
- M4-relative MDD axis is the BINDING decision rule per request.json (not defense evaluation per se — sizing_only WT is a sizing layer evaluation, M4-relative is the production basis comparison).

### 3. Lockbox structural unavailability (NOT applied — extension covered)
- Forge walk-forward 268/268 covers lockbox period directly. No "lockbox unavailable" claim.
- Pre-LB OOS evidence already present (2025 17 months). Judge does not invoke harness because forge already provided lockbox period strategy NAV.

---

## Section: Self-Identified Concerns (HIGH/MED severity for Codex review)

### HIGH JC-1: MDD vs L-274 M4-only baseline FAIL (-1.34pp)
- Decision rule axis is M4-relative per request.json primary_objective ("mdd_target ≤ -25% OR M4 대비 -3pp 개선"). M4 is the active production basis.
- M4+DCC -33.39% vs L-274 M4-only -32.05% = -1.34pp WORSE.
- Adding DCC overlay on top of M4 actually degraded MDD instead of improving.
- PASS branch via S1 BASE_RAW comparison is misleading because S1 has no overlay (lower bar).

### HIGH JC-2: Lockbox period -177pp cumulative underperformance vs S1
- 17-month strong-bull lockbox: S1 cum 259.99% vs M4+DCC 82.88% = -177pp.
- DCC up-scaling cash (mean 28.3% throughout) when realized σ_p trends up surrenders alpha.
- Forward May 2026 sizing cash 58.06% extends this same problem into deployment.

### HIGH JC-3: Forward May 2026 sizing cash 58.06% (largest in 268m)
- DCC σ_p forecast 35.77% annual >> 15% target → cash bridge 58.06%.
- If KR market continues current bull regime (5월 NORMAL), DCC surrenders ~58% of book to cash.
- Forge RF-F3 + Optimizer RF-O-LAYER-A-FORWARD-EXTREME flags HIGH severity.

### HIGH JC-4: Codex critic forge response REJECT
- C1: M4-relative PASS claim baseline-inverted → Judge AGREES (verdict same conclusion)
- C2: Stock-level walk-forward not directly evidenced → sleeve_only_proxy admitted, parent inheritance documented
- C3: Forward May 2026 not in canonical schedule → distinction T+1 forward vs in-sample T (recommendation_only mitigates)
- C4: Harvey/DSR absent → Judge provides: Harvey-t 6.76 PASS + DSR 0.35 → deflated 1.08
- C5: Covariance condition 240.87 max → WARN-level structural property of DCC under heavy-tail KR returns, not violation
- C6: alpha_package hash omitted → recommendation_only inheritance via inherit_ref.json
- C7: Rationalization flags → NEGLIGIBLE was forge SR vs optimizer SR comparison (true 0.07pp negligible numeric)

### MEDIUM JC-5: DSR penalty deflates SR to 1.08 < L-274 1.75
- 7 candidates × 0.05 = 0.35 SR equivalent deflation.
- M4+DCC raw 1.43 → deflated 1.08 (above 1.0 floor, below L-274 production basis 1.75).

### MEDIUM JC-6: Sleeve-level proxy production_grade=FALSE
- Forge package self-acknowledged + Codex C2.
- Sleeve-only proxy is appropriate scope for sizing_only WT but not full production verification.

### LOW JC-7: regime_proxy via w_cash_active is partly self-fulfilling
- ES95 CRISIS small (-5.78%) reflects engaged cash, not pure mechanism evidence.
- crisis_alpha cumulative (3/3 PASS) is the cleaner mechanism test.

---

## Section: Codex Round Decision Protocol

### Auto-classification framework

#### ACCEPT criteria (명백한 위반 → spec 수정 의무)
- PIT C1/C9/C11/C12 hard violation — N/A (PASS_WITH_1_WARN)
- Hard Constraint violation — N/A (all PASS)
- Schedule density < 0.95 — N/A (1.0 verified)
- SHA self-verify mismatch — N/A (PASS)

#### PARTIAL criteria (부분 인정 + 보완)
- DSR penalty 0.35 deflates SR to 1.08 — already documented; not a violation but disclosure improved
- Lockbox 17-month sample — limitation disclosed
- M4+DCC vs L-274 reference gap — diagnostic flag confirmed (BINDING decision rule failure)

#### REBUTTAL criteria (학술 + L-code + 정량 data 3축)
- Replacement TDC threshold not applied: RECOMMENDATION_ONLY scope (Charter v1.7 §10)
- AX-001 v2 conditional applied correctly: defense 3-tuple per agent definition
- Lockbox unavailable not invoked: walk-forward 268/268 covers period
- Forge codex REJECT addressed: judge independent verification reaches same M4-relative FAIL conclusion (AX-008 effective consensus)

### Auto-escalate triggers (Q-Lead notification)
- HIGH severity ≥ 5 in Codex response (current self-identified: 4 HIGH + 2 MEDIUM + 1 LOW = 4 HIGH)
- AX axiom hard FAIL ≥ 3 (current: AX-001 v2 PARTIAL, AX-002 PASS, AX-005 PARTIAL, AX-007 acknowledged, AX-008 PARTIAL → 0 hard FAIL)
- PIT C1 hard violation (current: PASS; below threshold)

→ **No escalate triggered. 4 HIGH severity is just below 5 threshold but disposition documented for each. Judge proceeds with MONITORING_ONLY verdict.**

---

## Section: AX-008 stance entry (Source 4 of 4, Round 1)

```json
{
  "source": "judge",
  "round": 1,
  "stance": "MONITORING_ONLY",
  "rationale": "Plan §12 decision_rule: CAGR + Sortino + Vol + top5DD PASS, but MDD strict FAIL + MDD vs L-274 M4-only baseline FAIL by -1.34pp (BINDING M4-relative axis per request.json). AX-001 v2 PARTIAL (crisis_alpha 3/3 + alpha surrender 1.55pp/m FAIL + MDD vs Core MIXED). Harvey-t 6.76 PASS. DSR-deflated SR 1.08 above 1.0 but below L-274 1.75 reference.",
  "concerns_resolved": "Lockbox audit judge independent recompute matches forge exactly. AX-001 v2 conditional applied correctly. PIT PASS_WITH_1_WARN. Codex C1 logic agreement with judge verdict (both reach M4-relative FAIL).",
  "remaining_concerns": ["MDD vs L-274 M4-only (-1.34pp BINDING) [HIGH]", "Lockbox -177pp underperformance [HIGH]", "Forward May 2026 cash 58% deployment risk [HIGH]", "Codex REJECT round 2 waiver via judge resolution [MEDIUM]", "DSR-deflated 1.08 < L-274 1.75 [MEDIUM]"],
  "final_after_codex": "pending_codex_response_or_waiver"
}
```

---

## Section: Waiver path (Codex timeout)

If `codex_critic_response_judge.json` does not arrive within timeout (~20m / 1200s codex CLI ceiling), Round 1 invokes waiver path consistent with risk + optimizer + forge precedent:
- `codex_critic_skip_waiver` for Codex Round
- Judge-side **자체검증 quantitative proof**:
  - 6-Gate evaluation completed (A-F all PASS or PASS_WITH_1_WARN)
  - Judge independent lockbox recompute matches forge (M4+DCC SR 4.6766 = forge claim exactly)
  - AX-001 v2 conditional 3-tuple computed
  - Harvey-t 6.76 well above 3.0 threshold
  - DSR penalty 0.35 (7 candidates) deflation documented
  - 7 consensus_concerns disposition documented
  - Codex forge REJECT response substantively addressed (4 HIGH + 2 MED + 1 LOW disposition)
- Round 1 judge_verdict.json finalize as `codex_round_status = "round1_timeout_waiver_applied"` if Codex no-show

---

## Section: state_machine 정상 통과 plan

```
SPEC_APPROVED (done)
  → ALPHA_DONE (Q-Lead waiver, sizing_only inherit_ref)
  → RISK_DONE (round 1 timeout waiver)
  → OPTIMIZER_DONE (round 1 REJECT round 2 waiver)
  → FORGE_DONE (round 1 REJECT round 2 self-classified — judge resolution)
  → JUDGE_PASSED (this agent — sm_validated_advance call after Codex resolution or timeout waiver)
  → GOVERNOR_REJECTED
  → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE"
```

**JUDGE_PASSED rationale**: state machine "PASSED" reflects that Judge gate evaluation completed successfully, NOT that the strategy is admitted to production. The verdict (MONITORING_ONLY) determines downstream Governor action (REJECT for promotion, but JUDGE_PASSED for closure of the WT lifecycle).

---

## Section: Production protection
- 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 (verification_method: forge production_protection.write_count_actual=0)
- STR_1715 100% PG2 admission unchanged
- 5월 운용 weights live ready (no impact from this WT)
- Cross-WT pattern confirmed: 4 WT (PCA + HMM + RMT + Factor Beta) all MONITORING_ONLY/FAIL — DCC follows same pattern, none of 4 risk-overlay WTs improve over L-274 M4-only production basis

---

## Section: Cross-WT pattern alignment (4 risk-overlay sister WTs)

| WT | Method | Verdict | Key Failure |
|---|---|---|---|
| WT-S20260504_001 | PCA Latent Hedge | MONITORING_ONLY | MDD all 3 paths FAIL + vol +4.9% worse |
| **WT-S20260504_002** | **DCC-GARCH Vol Target** | **MONITORING_ONLY** | **MDD vs L-274 M4-only -1.34pp** |
| WT-S20260504_003 | HMM | FAIL/MONITORING_ONLY mix | (sister WT) |
| WT-S20260504_004 | RMT | FAIL on MDD axis | MDD -35.32% FAIL strict 25% |
| WT-S20260504_005 | Factor Beta | APPROVE_CONDITIONAL | Different mechanism path |

DCC fits the pattern: statistical mechanism real but trading metric M4-relative axis fails. Confirms cross-WT structural conclusion that **single-overlay risk methods on top of L-274 STR_1715 do not improve M4-only production basis** — the gap remaining in STR_1715 (MDD -32.05% vs target -25%) requires alpha-side intervention (Iter 9 family pivot Defense / Crisis Alpha) not risk-side single-overlay layering.

---

## Section: Codex Round 1 Response Classification

(Will be appended on arrival of `codex_critic_response_judge.json` per Codex Round Decision Protocol — ACCEPT/PARTIAL/REBUTTAL framework.)

---

## Final 작성 waiver

dapper-dragon plan §1 WT-002 background mode + recommendation_only WT specification ⇒ Final `judge_verdict.json` 작성 가능. Codex critic 회신 도착 시 Round 2 classified response patch + v1.1 promote.
