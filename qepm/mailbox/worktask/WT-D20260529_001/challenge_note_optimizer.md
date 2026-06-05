# Optimizer Challenge Note — WT-D20260529_001 FLOW

**Codex Round**: gpt-5.5 xhigh. Stance = **REJECT** (devil's advocate; veto not absolute). 7 concerns.
**Disposition**: 4 ACCEPT (C1, C2, C4, C5) + 2 PARTIAL (C3, C6) + 1 ACCEPT-resolved-by-finalize (C7).
**Charter §8 No Silent Override**: each concern classified with explicit rationale. Hard-constraint concerns (C1 max_names) escalated to infeasibility_report, not silently relaxed.

---

## C1 [CRITICAL] — Blended book 39 union names > max_names 20 → **ACCEPT**

**Concern**: Selected method = STR_1715 55% + FLOW 45%; risk_package combined_n_union=39. Auditing only the FLOW sleeve hides a max_names=20 hard breach.

**Disposition: ACCEPT (mandatory, Hard Constraint).** Verified directly: STR_1715 (2026 snapshot) vs FLOW top-20 overlap = 2 names → **union 38**. The task mandate is explicit: "multi-sleeve 최종 portfolio도 20종목 이하 (N_1715 + N_FLOW ≤ 20)". A 55/45 capital split of two independent full 20-name sleeves yields a 38-name book → **violates the 20-name union mandate**.

**Resolution (no silent override)**: Two architectures examined:
- **Path A (fund-of-sleeves, AX-007 multi-sleeve exception)**: max_names=20 per sleeve; book breadth 38 is diversification. This is what the realized-return blend (0.55·R_1715 + 0.45·R_FLOW) actually represents. But it **breaches the user's explicit 20-name-union mandate**.
- **Path B (combined ≤20-name book)**: requires merging holdings into ≤20 slots (≈11 STR_1715 + ≈9 FLOW given 55/45). **Infeasible to backtest honestly**: STR_1715's full-history holdings schedule is not available in this WT (only 2026 snapshots + a realized monthly-return stream). A combined-20 return stream cannot be reconstructed without STR_1715 per-date holdings.

→ **`infeasibility_report` INFEAS-3 raised** (max_names_union_20 vs realized-return blend incompatible without STR_1715 historical holdings). FLOW sleeve weights (≤20, compliant) delivered; the 55/45 diversification quantification retained as the analytical finding under the fund-of-sleeves (Path A) framing, **explicitly flagged as exceeding the 20-name-union mandate**. Q-Lead/Forge decision required: (a) accept fund-of-sleeves book at 38 names under AX-007, or (b) obtain STR_1715 historical holdings and re-run combined-20 blend.

## C2 [CRITICAL] — FLOW weights vs covariance universe mismatch (A014820 vs A112610) → **ACCEPT (clarified)**

**Concern**: Latest FLOW weights hold A014820 / omit A112610; covariance.parquet holds A112610 / omits A014820 → A014820 has no Σ row, breaks "Σ consumed read-only" claim.

**Disposition: ACCEPT (clarify scope).** Verified: 1-name mismatch. Cause: covariance was built on the **static alpha-top-20 by raw score** (includes A112610 #20), while the SELECTED method is **EW hysteresis buffer en=50**, which carried A014820 (#22 by score) over A112610 via the rank-band retention rule. **The selected EW sleeve does NOT consume Σ for sizing** (Σ entered only the MVO/HRP/ERC/MinVar/CVaR comparison + the CVaR diagnostic, all disqualified). The "Σ read-only" claim is corrected: Σ informed the method-comparison and CVaR cap; it did not size the selected EW weights. The 1-name universe gap is a non-binding artifact for EW but **flagged for Forge**: if Forge uses Σ for any FLOW-sleeve risk metric on the final holdings, A014820 needs a Σ row (rebuild Σ on the EW-buffered holdings, not the static top-20). Documented in package `covariance_universe_note`.

## C4 [HIGH] — Method-shopping disclosure inconsistent (8 vs 11) + objective mismatch → **ACCEPT**

**Concern**: method_log candidates_tried=8 but package exposes 11 sleeve variants + 11 blend grid weights; declared objective to_adj_ret ≠ implemented two-stage (net-SR then book-IR).

**Disposition: ACCEPT.** Corrected: `candidates_tried = 11` (6 base methods {EW,MVO,HRP,ERC,MinVar,CVaR} × buffer levels reduces to 11 distinct sleeve configs evaluated). The blend grid (11 allocation weights) is a **continuous 1-D allocation sweep, not method shopping** — disclosed separately as `blend_allocation_sweep`. Objective corrected to explicit **two-stage**: Stage-1 sleeve selection = `to_adj_ret` (TO-feasible filter THEN max net-SR); Stage-2 book allocation = `book_ir` (active-management objective vs benchmark). Both net-of-cost. No raw-Sharpe-max. Documented in `selection_objective` (two_stage) + `method_log`.

## C5 [HIGH] — Turnover / cost unit inconsistency (5.51 one-way, "round-trip 11.0", cost uses 5.51) → **ACCEPT (double-count error fixed)**

**Concern**: Package says 5.51/yr one-way, round-trip 11.0/yr, but cost = 5.51 × 15bps not one-way × 15bps × 2.

**Disposition: ACCEPT — draft had a double-count error.** Definitive convention: turnover = Σ|w_new − w_old| over the **union** of holdings = counts BOTH buy and sell legs (each |Δw_i| once). Therefore **5.51/yr is already the round-trip notional** — the draft's "×2 = 11.0/yr round-trip" was a **double count** (the Σ|Δw| already includes both sides). Under the canonical round-trip convention (qvest-opt-style P6 "2-way"), **5.51 ≤ 6.0 PASS**. Annual cost = 5.51 × 0.0015 = **0.827%/yr** (each |Δw_i| traded once at 15bps) — the draft's cost figure was correct; only the "11.0 round-trip" label was wrong. This is exactly the ×2-annualization landmine the mandate warned of (Iter 3 violation). Removed the erroneous 11.0 figure; `turnover.convention = "round_trip_sum_abs_dw (both legs counted once)"`.

## C3 [HIGH] — Handoff schema incomplete; monthly carry-forward emission path unused → **PARTIAL**

**Concern**: weights.csv at canonical mailbox path + stage dirs absent; weights.csv lacks method_selected; density 0.336 while run_weights_emit.R documents a feasible monthly carry-forward path.

**Disposition: PARTIAL.**
- **ACCEPT (fix)**: weights.csv is at the canonical stage path `stage_artifacts/WT_D20260529_001_FLOW/weights.csv` (artifact-naming policy). Added `method_selected` provenance to the package; the as_of_date×Ticker×weight schema is the canonical weights.csv contract (method belongs in optimization_package.json, not per-row in weights.csv).
- **REBUTTAL (schedule density)**: monthly carry-forward emission (run_weights_emit.R) would **fabricate** intermediate monthly holdings for a sleeve whose REBAL frequency is quarterly. The FLOW signal is a slow long-horizon flow factor (alpha_package: monthly rebal TO = 10.66/yr FAIL > 6.0; quarterly = 5.93 PASS). Emitting 226 monthly carry-forward rows for a 76-date quarterly rebal would be a density-mandate-driven fabrication that **inflates the apparent schedule** while the economic rebal is quarterly. Per Charter §9, the correct response is `infeasibility_report` INFEAS-2 (density 0.336 < 0.95 because TO cap forces quarterly), NOT a synthetic monthly carry-forward. Carry-forward is acceptable for NAV computation (Forge holds the quarterly weights across intervening months), but the weights.csv **rebal schedule** is honestly 76 quarterly dates. The 226 alpha sig_dates are the SIGNAL frequency, not the REBAL frequency — these are distinct (qvest-opt-style: density mandate vs TO mandate tension for slow signals; quarterly is the honest resolution).

## C6 [MEDIUM] — Residual TDC 0.235 as binding gate not established → **PARTIAL/REBUTTAL**

**Concern**: Sequential admission relies on residual TDC 0.235 while raw cross-book lower-TDC is 0.725; not established that residual TDC is the binding gate for MDD/CVaR/crowding.

**Disposition: PARTIAL (defer to risk scope) + REBUTTAL.** TDC interpretation is **risk_package scope** (risk-research C4 ACCEPT already adjudicated: raw cross-book corr/TDC overwhelmingly shared market beta; residual cross-corr 0.24 / residual lower-TDC 0.235 is the genuine alpha-level diversification, consistent with signal cor −0.07). I do not re-define risk metrics (Hook boundary). **REBUTTAL on the optimizer-relevant point**: I did NOT rely on residual TDC for admission — I report the BOOK-LEVEL realized monthly CVaR95 (0.130 ≤ cap 0.15) and realized book MDD (39.6%) on the actual 55/45 return stream as the binding portfolio risk metrics. The raw returns correlation 0.709 is fully reflected in the book SR cap (0.71) and is NOT hidden by the residual figure — the modest SR gain (+0.09) directly evidences the high raw correlation's drag. Binding gate metrics used = realized book CVaR + MDD, not TDC.

## C7 [MEDIUM] — Governance incomplete (no challenge_note / final package / lineage; production_grade=false) → **ACCEPT (resolved by finalize)**

**Disposition: ACCEPT.** This challenge_note_optimizer.md + final optimization_package.json + lineage entry are produced in the finalize step (this resolves C7). production_grade=false is CORRECT and retained (optimizer_walk_forward_simulation basis is not PG2-admission-eligible; Forge produces admission-grade backtest) — this is honest provenance per the Hurdle Result Provenance Mandate, not a deficiency.

---

## Escalation assessment
- HIGH severity count: 3 (C3, C4, C5) — < 5 threshold.
- Hard-constraint breach: **C1 max_names_union 38 > 20** → handled via infeasibility_report INFEAS-3 (no silent relaxation). Per the auto-escalate trigger (Hard Constraint violation found), this is **flagged to Q-Lead** in the package `qlead_escalation` field for the architecture decision (fund-of-sleeves vs combined-20).
- No AX axiom hard FAIL ≥ 3. No RF-O9 single-snapshot (weights.csv = 76 as_of dates).
- **Net**: structural corrections applied (C1/C2/C4/C5); package finalized with explicit infeasibility reports + Q-Lead escalation on the 20-name architecture. Codex REJECT addressed substantively, not dismissed.
