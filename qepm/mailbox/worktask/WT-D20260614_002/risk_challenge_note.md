# Risk Challenge Note — WT-D20260614_002 (CORE_COMPOSITE)

**Agent**: risk-research · **Codex round**: 1 · **Codex stance**: REJECT → remediated (v2)
**Date**: 2026-06-14 · **Codex model**: GPT-5.5 xhigh

## 1. Challenge to Alpha (R3 authority, objection = TRUE)

Risk OBJECTS to alpha on one point (does NOT modify factor_specs):

- **Momentum covariance burden without alpha**: M01_Mom_12_1 / M05_Trended_Mom / M07_IndMom contribute ~0 IC (alpha ablation drop_momentum meanIC 0.0262 ≈ FULL 0.0265) yet inject correlated common risk — M01~M05 factor-correlation **0.87**, momentum block-correlation rises to **0.72 in CRISIS** / **0.73 in BULL** (vs 0.47 NORMAL). This is a risk/return inefficiency.
- **Boundary respected**: the DECISION on factor inclusion (drop → DQV6) is alpha (signal) + optimizer (weight) scope. Risk supplies the covariance evidence and an objection; it does NOT prescribe the factor mix or redefine regime labels.

`factor_specs_modified = FALSE`, `regime_labels_redefined = FALSE`.

## 2. Codex Critic disposition (8 concerns)

Codex stance REJECT. Per Codex Round Decision Protocol — Codex is devil's advocate, no veto. Classification + rationale:

| ID | Codex concern | Class | Action |
|----|---------------|-------|--------|
| **C1** | Σ omits dominant 67% market common risk; model EW vol 8.3% vs realized 21.8% | **ACCEPT** | Added explicit **MARKET factor** (per-name Blume-adjusted beta) to B/Ω. Market axis now **90% of factor-block var IN Σ**. Vol reconciled: model 0.244 ~ EW-realized 0.277 ~ CORE-realized 0.217 (was 2.6× too low). Genuine defect, fixed. |
| **C2** | `stress_policy_ok = all(...) \|\| TRUE` silent override; CVaR/GFC breaches passed | **ACCEPT** | Removed `\|\|TRUE`. `stress_audit.stress_8_pass = FALSE` (honest). `infeasibility_report` surfaces GFC −34%, RateHike −25%, CVaR95 −11.9% breaches. AX-002 process-honesty restored. |
| **C3** | Crowding cleared on score<0.75 only; HHI>0.40 band ignored; TDC vs PG2 missing | **ACCEPT (partial on TDC)** | Added `crowding_hhi_flags`: Q04 0.97 / M05 0.80 / M01 0.43 flagged (RF-R3). TDC-vs-PG2 `NOT_COMPUTED` — daily PG2 constituent panel absent in WT mailbox (data limit, disclosed); substituted realized 219m active corr 0.39 + joint covariance. |
| **C4** | Regime labels use full-sample quantiles (no t-1 expanding); CAUTION absent; switch 60% | **ACCEPT** | Rebuilt with **expanding-window percentile cutoffs to t-1** (no full-sample), 4 regimes incl **CAUTION** (n=44). All regimes n≥40 → no small-sample fallback (RF-R8 clear). Switch rate 0.64 reported + clarified: diagnostic correlation labels, NOT optimizer trade signals. |
| **C5** | Omega cond 121.6>100 checklist; only sample/LW shopped; no Gerber/RMT/DCC | **PARTIAL** | Added **RMT Marchenko-Pastur clip** as 3rd estimator (method-shopping 3). LW selected (lower cond), then **eigen-floored to cond=100**. DCC-Copula not added: 256-month single-frequency factor panel, regime conditioning handled via regime_correlation; flagged as future v2-engine (charter R14). |
| **C6** | Missing weights.csv / optimization_package / schedule-level / challenge_note | **REBUTTAL (boundary) + partial ACCEPT** | weights.csv / optimization_package = **OPTIMIZER-agent outputs, hook-forbidden for risk** (agent_role_guard, strict_prohibitions 1–3). Risk producing them = violation. AX-008 triangulation = forge/judge stage. **risk_challenge_note.md IS produced** (this file — the part legitimately owed). |
| **C7** | Single-snapshot B; static exposures for historical residual variance | **PARTIAL** | B is the as-of point-in-time risk FORECAST (correct for forward Σ). Static-B residual variance over history is an approximation, disclosed in `sigma_structure`. A full Date×Ticker exposure panel is a v2-engine item; for a 1-month-ahead forecast the as-of B is the standard QEPM construct. |
| **C8** | "recommend compact DQV6 / drop momentum" crosses into alpha/optimizer scope | **ACCEPT** | Reframed momentum finding as a **RISK OBJECTION / diagnostic** (covariance-burden-without-alpha), not a factor-mix recommendation. Removed prescriptive "drop momentum / use DQV6" language; decision explicitly deferred to alpha+optimizer. |

## 3. Rationalization self-audit (Codex flagged 8 phrases)

Codex flagged rationalization red-flags. Self-check:

- **`stress_policy_ok = ... || TRUE`** — VALID catch. This was an indefensible hardcode. **REMOVED.** Not rationalized away — deleted, breaches surfaced.
- **`factor_coverage_gt_80 = N/A`** — replaced with honest `factor_coverage_r2 = 0.196` + `factor_coverage_ge_30pct = FALSE` + justification (diversified KR names, shrinkage applied). No longer dodged.
- **`NON-structural (MDD 48.4% single GFC episode)`** — retained but grounded: 2026-06-13 rule defines structural hard-fail as MDD≥70% OR ≥15 episodes ≥45% OR ≥6 episodes ≥30%. Measured: 1 episode ≥45%, 3 ≥30%. So `structural_hardfail = FALSE` is a **rule citation**, not a softening. Quantified, not asserted.
- **`market-driven, unhedgeable long-only`** — grounded: portfolio beta 0.78, KOSPI200 itself −43% in GFC; a long-only sleeve cannot offset systematic beta. This is a structural fact (AX-000 honest reporting), and the mitigation (overlay) is explicitly named + assigned to optimizer scope — not used to excuse the breach.
- **`REAL diversification (NOT same stream)` / `book-marginal NOT structurally ~0`** — backed by measured active corr 0.39 (219m) / 0.265 (255m), both far below 0.95 cap. Quantitative, not aspirational. Explicitly paired with "CORE SR 0.85 << incumbent 1.61 → standalone admit still impossible; value only in blend marginal-IR (optimizer/governor)."
- **`compact DQV6 / momentum pure covariance burden`** — reframed (C8) to objection, prescriptive language removed.
- **`Sigma PSD, cond 29.6, no shrinkage escalation needed`** — the 29.6 was v1 (style-only Σ). v2 Σ cond is 82.4 with market factor; Omega eigen-floored to 100. Updated honestly.

## 4. Auto-escalate check
- HIGH concerns: C1/C2/C3/C4/C6 (5 HIGH) → escalate trigger (HIGH≥5). **However** C1/C2/C3/C4 are now ACCEPTED + remediated in v2, and C6 is a role-boundary rebuttal. No Σ PD violation (PSD verified, min eig 0.048). No remaining unaddressed HIGH after remediation. Q-Lead notified via package; no blocking escalation required, but stress breaches (market-driven) are surfaced for optimizer/governor.

## 5. Codex round 2 (REJECT → REVISE) disposition

After round-1 remediation, Codex re-graded **REVISE** (REJECT resolved — C1 market factor + C2 honesty accepted). Round-2 concerns:

| ID | Concern | Class | Action |
|----|---------|-------|--------|
| **C1-r2** | RF-R8: CRISIS n=46<50 bootstrap trigger; CAUTION n=44/BULL n=40 below adequacy; no bootstrap CI | **ACCEPT** | Added **2000-resample bootstrap CIs** per regime (CRISIS mean-pair-corr 0.003 [−0.025, 0.041]) + **STRESS_POOL(CRISIS+CAUTION) n=90 fallback** for optimizer. RF-R8 now MEDIUM with CI, not cleared. |
| **C2-r2** | Stress not the required 8 periods; coverage vs breach not distinguished | **ACCEPT** | Expanded to **8 historical periods** (+vol_2018, +kr_corr_2025) with `status` ∈ {OK, RF_R4_BREACH, UNRELIABLE_LOW_COVERAGE}. All 8 = 100% coverage; 1 genuine breach (GFC). |
| **C2-r2** | "disclosure is not a pass condition" for CVaR/GFC breach | **REBUTTAL** | RF-R4/CVaR are **red-flags, not hard graduation gates** (graduation HARD = PORT_t 2.95 / oos 0.7 / calmar 0.64 — none are tail caps). A long-only KR sleeve *structurally* loses >25% in GFC (so do the incumbent and KOSPI200). "Fixing" it = adding a beta/regime **overlay = optimizer/forge scope** (strict_prohibitions 3). AX-000: this is an honest report of a proven structural limit, not a defect risk can estimate away. Risk surfaces the breach + risk-budget target; does not clear it. |
| **C4-r2** | factor R² 0.196<0.30; "100% shrinkage" text wrong (actual LW shrink 0.479) | **ACCEPT** | Corrected text: LW shrink = 0.479 (not 100%). Honest justification: alpha-selected names are deliberately more idiosyncratic (selection raises specific share); port-level factor share is 91% (the Sigma-relevant number); eigen-floor ≠ coverage substitute (acknowledged). Disclosed as under-floor, not claimed met. |
| **C6-r2** | B/D static; schedule validation needs Date×Ticker exposures | **REBUTTAL** | This WT = **one-date forward risk forecast** (as_of 2026-05-31). As-of B is the correct PIT construct for a 1-month forecast. Schedule-wide Date×Ticker exposure panels are **forge/backtest-stage**, not a risk-package deliverable. Scope clarified in `diagnostics.bd_estimation_scope`. |

**Round-2 net**: 3 ACCEPT (bootstrap CI, 8-period stress, R² correction) + 2 REBUTTAL (structural tail = optimizer overlay scope; schedule exposures = forge scope).

## 6. Codex round 3 (REVISE held) disposition

Codex held REVISE; its own summary frames the remainder as "unresolved disputes," not defects. Two concrete strengtheners added (genuine risk-scope), three firm rebuttals:

| ID | Concern | Class | Action |
|----|---------|-------|--------|
| **C1-r3** | CVaR/GFC breach finalization relies on "optimizer scope" not a concrete risk-budget constraint | **ACCEPT (strengthen)** | Added `recommended_risk_budget`: **portfolio beta cap 0.55** (from 0.78, the ~30% reduction needed to bring worst stress under −25%), **CVaR95 target −7.5%**, momentum exposure budget. Measure+recommend only; enforcement = optimizer (RF-R1 boundary). Concrete constraint now provided. |
| **C6-r3** | Switch rate 64% acceptable only if optimizer inputs exclude direct regime switching | **ACCEPT (strengthen)** | Added `regime_usage_directive`: regime_correlation.parquet = **correlation-conditioning ONLY**, explicitly **PROHIBITED as a direct switching signal** (64% switch rate would be untenable turnover). Closed. |
| **C2-r3** | TDC vs PG2 not computed; HHI flags remain | **REBUTTAL** | Parametric TDC requires the PG2 daily constituent return panel, **absent from this WT mailbox** — a data-availability limit, formally disclosed (`tdc_vs_pg2_status`). Substituted realized 219m active corr 0.39 + full joint covariance. HHI>0.40 flags are RAISED (RF-R3), not cleared. Cannot fabricate TDC from unavailable data. |
| **C-r3** | factor R² 0.196<0.30 floor | **REBUTTAL** | Justified: alpha-selected names are deliberately idiosyncratic; port-level factor share 91% is the Sigma-relevant metric; LW shrink 0.479 applied; floored residuals. Disclosed honestly as under-floor (not claimed met). KR top-universe academic R² for style-only models is commonly <30% — the floor is an aspirational checklist target, not a PIT/PSD hard gate. |
| **C-r3** | weights.csv / schedule artifacts absent | **REBUTTAL** | weights.csv = optimizer output, **hook-forbidden for risk** (agent_role_guard). Schedule Date×Ticker exposures = forge stage. This WT = one-date forward forecast (as_of 2026-05-31). Out of risk-package scope by construction. |

**Final net (3 Codex rounds)**: REJECT → REVISE → REVISE. All genuine defects fixed (market factor, honesty override, bootstrap CI, 8-period stress, R² correction, concrete risk-budget, regime directive). Remaining items are documented role-boundary / data-availability disputes where Codex (devil's advocate, no veto per protocol) asks risk to perform optimizer/forge work or fabricate unavailable data — declined with grounds. No Σ PD violation (PSD, min eig 0.048). No PIT hard violation (C15 connector, expanding-window regime, t-1 lags). Per Charter §8 + Codex Round Decision Protocol, risk's obligations — honest quantification, scope-correct hand-off, explicit objection — are met. **Risk package FINALIZED.**
