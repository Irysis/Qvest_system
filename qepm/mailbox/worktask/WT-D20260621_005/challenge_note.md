# Challenge Note — WT-D20260621_005 (OtherCorp Strategic Accumulation Momentum)

**Codex Critic Round** (gpt-5.5, 2026-06-21T16:30): stance = **REVISE**, veto_flag = false, AX-008 = FAIL (diagnostics/artifacts incomplete).

Per Codex Round Decision Protocol (v6.0): each concern classified ACCEPT / PARTIAL / REBUTTAL with explicit grounds. Codex is devil's advocate — no veto. Self-rationalization auto-check performed (grep "미미/관행/보수적이면/대부분동일" → 0 hits in resolutions).

---

## C1 (HIGH, AX-007) — Standalone long-only translation fails → **ACCEPT (this IS the finding)**
Codex: rank_ic 0.020 < 0.04, port_t −0.52, net_sr −0.16, oos −3.94, all 27 grid cells negative → cannot graduate standalone.
**Resolution**: Fully accepted — this is not a defect, it is the faithful negative. Draft verdict was already SCREEN_ROUTE (not graduate). No spec change; the conclusion stands and is strengthened by Codex's independent confirmation. Graduation HARD 3종 (PORT_t 2.95 / oos 0.7 / calmar 0.64) all FAIL — reported as such.

## C2 (HIGH, RF-A5) — Turnover 13.59 = 1359% > 1100% hard → **PARTIAL ACCEPT**
**Resolution**: Accepted that turnover is high and exceeds the screening hard-fail if read as one-way. Grounds for nuance: `canonical_screen_bt` `traded_t = Σ|w_t − w_{t-1}|` counts **both legs** (buy+sell), so 13.59×/yr ≈ **6.8×/yr one-way** ≈ 680% — under the 1,100% one-way hard-fail but still high (KR top-20 monthly EW churn). This is moot for graduation (port_t already fails), but I now flag turnover explicitly in challenge_flags. Net-of-15bps cost is already in the −0.52 port_t (so the high turnover's cost drag is already counted, not hidden).

## C3 (HIGH, AX-008) — Missing artifacts / path inconsistency → **PARTIAL (path ACCEPT; weights/cov REBUTTAL)**
- **Path (ACCEPT)**: task referenced `stage_artifacts/WT_{id}/` (underscore); I wrote `stage_artifacts/WT-D20260621_005/` (hyphen, matching the actual WT id and mailbox dir `qepm/mailbox/worktask/WT-D20260621_005/`). Lineage now recorded via `record_package_lineage`. Draft + validation copied into mailbox. No second underscore path exists — single canonical location documented.
- **weights.csv / covariance.parquet (REBUTTAL)**: these are **optimizer/risk-stage** artifacts. `agent_role_guard` HARD-BLOCKS the alpha agent from producing covariance or weights (strict_prohibitions 1–3). Their absence is **correct alpha-stage behavior**, not a lineage failure. Producing them would be a role violation.

## C4 (HIGH, PIT-C15) — Primary reads parquet directly, not via load_month_factors → **REBUTTAL**
**Grounds (spec-sanctioned, documented exception)**:
- C15 governs **Factor DB** parquet (`.cache/factor_db/factor_db_*.parquet` via `load_month_factors()`). OtherCorp is a **NEW raw investor-flow channel that does NOT exist in Factor DB** — that is the entire premise (INV01-13 use only Foreign/Inst/Individual; zero use OtherCorp). Routing it through `load_month_factors` is impossible by construction.
- The spec explicitly addresses this (backlog `data_inputs_note`, `pit_notes` C15): "investor_wide는 별도 cache(load_investor_stock 경유)이므로 load_month_factors 비대상." Academic/process basis: python-policy §3 + pit.md C15 scope investor-flow caches as a documented carve-out distinct from factor_db direct-parquet loads.
- PIT integrity is enforced the SAME way regardless of loader: C1 (rolling frollsum align=right), C2 (d-1 shift, verified by reconstruction — acc as-of-d-1 = Σ ocn[d-40..d-1], day-d excluded), C14 (Usable_Date = trade_day+1 ≤ sig_date; signal ends d-1). Orthogonality reference factors ARE pulled via `load_month_factors` (PIT-safe direction alignment).
- I do NOT claim a blanket C15 exemption — I document a **specific, spec-pre-registered** exception for a raw channel absent from Factor DB. This is logged in `alpha_validation.json::pit_c15_exception`.

## C5 (MEDIUM, RF-A7) — Irregular dates, breadth=2 in one month → **PARTIAL ACCEPT**
**Resolution**: alpha_scores.parquet IS multi-date (142 months, 2009-04 → 2026-03, not future-dated). Honest facts now reported:
- Data starts **2009-04** (not 2005): merged investor+rawdata month-ends with sufficient OtherCorp breadth begin there; pre-2009 investor coverage is thin. Documented, not hidden.
- **Cadence gaps real**: median 33d but 52 months with gap>45d, max 93d — the investor cache has missing months. Reported as a data-quality caveat.
- **One thin month (2011-01, 2 eff names)**: genuine early-data artifact; flagged. Median breadth 320, only 1/142 months <20.
- weights.csv absent = correct (alpha-stage, see C3 rebuttal).

## C6 (MEDIUM, RF-A1/A3/A4/A5/A6) — Missing diagnostics → **ACCEPT (now computed)**
Added: subperiod_stability **1.0** (all 3 eras positive IC: 0.024/0.016/0.020); recent-3Y ICIR ratio **1.18** (<1.5, no RF-A3); monotonicity **0.733** (decile spearman, D10−D1 +0.18%/mo); top-decile illiquid share **0.3%** (no RF-A5). **Key insight**: signal is monotone across deciles but **flattens at the top** (D10≈D9≈D8) — the gradient lives in mid-deciles, which is precisely why **long-only top-20 (D10 only) has no realized edge** despite the cross-sectional rank signal. Mechanistic explanation of the AX-007 translation failure.

## C7 (LOW, AX-000) — DPL/FR routing risks rationalizing a negative → **PARTIAL ACCEPT (reframed)**
**Resolution**: Codex flag accepted. Routing language softened from assertion to **conditional candidate**: OtherCorp is an empirically-orthogonal, monotone-but-top-flat signal → a *candidate* DPL feature / FR-RCMA input **pending a conditional-value test** (does it add net SR in a multi-sleeve / regime-conditional / non-top-only consumption?). I do NOT claim standalone value. The flagged phrases ("orthogonality confirmed", "breadth did not materialize") are **empirical measurements** (corr matrix, breadth time series), not rhetoric — retained as facts but stripped of any implied graduation merit.

---

## No Silent Override statement (Charter §8)
No Codex concern was silently dismissed. C1/C6 accepted (finding + diagnostics added). C2/C3-path/C5/C7 partially accepted with revisions. C3-weights/C4 rebutted with explicit spec-text + role-boundary + PIT-mechanism grounds. AX-008 FAIL addressed: all missing diagnostics now computed; PIT-C15 documented as spec-sanctioned exception, not blanket exemption.

## Self-escalation check
HIGH-severity concerns = 4 (C1-C4). Escalate trigger is ≥5 HIGH → not triggered. AX axiom hard FAIL: only AX-007 (= the finding itself, expected). No PIT C1 lockbox/lookahead violation found. Codex stance = REVISE (not REJECT) with all-rebuttal → no auto-escalate. Q-Lead review optional; finding is a clean negative.

## Final verdict
**SCREEN_ROUTE — candidate DPL_FEATURE / FR-RCMA input, pending conditional-value test. NOT standalone graduation.** Orthogonal untapped channel confirmed (max |mean_corr| 0.153 vs INV01); no standalone long-only edge (port_t −0.52, all grid negative). Clean negative, faithfully reported (AX-000 amended). One data point in the ongoing momentum-hunt campaign.
