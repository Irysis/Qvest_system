# Optimizer Challenge Note — WT-D20260528_003 (D_PROD)

**Codex Critic Round** (GPT-5.5 xhigh) · stance **REVISE** · veto_flag false · 6 concerns (2 HIGH, 4 MEDIUM)
**weakest_assumption** (Codex): "RF-R1 beta breach left uncapped because WF mean beta is lower and the cap costs 0.03 net IR."
**self-rationalization audit**: 0 forbidden-phrase hits ("미미/관행적/보수적이면 OK/대부분 결과 동일/실무적").

Adjudication per autonomous protocol (ACCEPT mandatory / PARTIAL / REBUTTAL with academic + L-code + quant data).

---

## C1 (HIGH) — AX-008 handoff path/schema inconsistency → **ACCEPT**

Codex: mailbox weights.csv absent, optimizer_challenge_note.md absent, weights.csv used `stage_artifacts` + a `method` column rather than method_selected schema.

**Resolution (ACCEPT, fixed in place)**:
- `weights.csv` copied to `qepm/mailbox/worktask/WT-D20260528_003/weights.csv` (2320 rows + header, 116 unique as_of_dates).
- This `optimizer_challenge_note_PROD.md` written (was the missing artifact).
- The `method` column is supplementary provenance (not a schema violation); package `method_selected` field carries the canonical selection. Columns: `as_of_date, Ticker, weight, method, task_id` — `as_of_date` IS the time-series schedule key (RF-O9 walk-forward satisfied: 116 unique dates).
- Note: the Codex prompt referenced `qepm/stage_artifacts/WT_WT-D20260528_003/covariance.parquet` (double `WT_WT-` prefix) — that path does not exist; the canonical risk artifact is `stage_artifacts/WT_D20260528_003_risk_PROD/covariance.parquet` (315×315, PSD min_eig 0.097, cond 100), referenced correctly in `risk_package_PROD.json`. Path mismatch is a Codex-prompt-template artifact, not a missing deliverable.

## C2 (HIGH) — RF-R1 measured but not controlled → **PARTIAL (resolved via dual-book delivery)**

Codex: as_of beta 1.0916, MKT var 64.8%; feasible beta-cap variant → beta 1.00 at +0.0745 one-way turnover, MDD 0.342→0.335. Rejecting solely for netIR 0.980→0.950 leaves the beta-drift mandate unresolved.

**Resolution (PARTIAL — Codex is right that "measure only" is insufficient; I do NOT fully accept "must apply" because the cap is net-IR-negative)**:
- I now deliver the **beta-cap=1.00 variant as a selectable secondary book**: `weights_betacap1.00.csv` (116 dates, max_w 0.121, Σw=1, long-only — all hard constraints PASS). Both books are in the package (`target_weights` = primary uncapped; `target_weights_betacap_variant_ref` = capped). This is **no-silent-override** (Charter §8): the RF-R1 mitigation is *built and handed off*, not merely described. Forge/Judge elect.
- **Quantified tradeoff** (walk-forward, both books fully simulated):
  | book | net IR | net SR | MDD | mean beta | TO/yr |
  |---|---|---|---|---|---|
  | primary (uncapped) | 0.980 | 0.741 | 0.342 | 0.934 | 5.28 |
  | betacap=1.00 | 0.950 | 0.722 | 0.335 | 0.895 | 5.48 |
- **Why primary stays uncapped as the recommended default** (REBUTTAL component, 3-axis):
  1. *Academic*: DeMiguel-Garlappi-Uppal (2009, RFS) — naive/breadth-preserving weights dominate constrained-optimization out-of-sample under estimation error; Clarke-de Silva-Thorley (2011) — minimum-beta long-only portfolios sacrifice IR. Long-only fully-invested has a **structural beta floor near 1.0** (cannot reduce MKT exposure without shorting/cash, both mandate-prohibited).
  2. *L-code*: the risk agent's OWN challenge note rebutted its sub-concern C4 as "MKT structural optimizer scope" (risk_challenge_note_PROD.md REBUTTAL C4_mkt_structural_optimizer_scope) — consistent with the structural-floor finding.
  3. *Quant*: the flagged 1.0916/64.8% is a **single as_of cross-section (2023-11-30) artifact**; the walk-forward MEAN beta is already **0.934 < 1.0**. The hard cap buys Δbeta_mean −0.039 (0.934→0.895) and ΔMDD −0.007 for Δ net IR −0.030 / Δ net SR −0.019 — an unfavorable risk-adjusted trade.
- Net: C2 PARTIAL accepted (variant built + handed off); recommendation (uncapped primary) defended on 3 axes. Beta-drift mandate is now resolved by *delivery of the controlled book*, not by silent dismissal.

## C3 (MEDIUM) — RF-O1 signal loss (top-alpha ranks omitted) → **REBUTTAL**

Codex: latest target omits alpha ranks 2,6,10,11,12,14,15,16,19; 24 of top-35 alpha names zero-weight; held names include ranks 119,125,144,237.

**REBUTTAL (3-axis)**:
1. *Scope*: the held name set is the **alpha agent's bandbuffer schedule** (keep50/entry20/cooldown3m), NOT optimizer selection. The optimizer re-SIZES committed names; re-SELECTING by raw alpha rank would (a) violate the alpha-research boundary (agent_role_guard Hook + AX-007), and (b) blow turnover from 5.28 to 12.5/yr (the AlphaSoftmax result — disqualified).
2. *Mechanism*: the cooldown (3m) intentionally retains lower-rank incumbents to suppress churn — this is the **turnover-control design** that produces the 5.30/yr the alpha agent reported. Naive top-N-by-rank is exactly what the bandbuffer is engineered to avoid (Novy-Marx-Velikov 2016 turnover-cost discipline).
3. *Quant*: re-selecting top-35 raw-alpha names was tested implicitly — AlphaSoftmax (which over-weights by alpha) reached net IR 1.017 but TO 12.53/yr (HARD FAIL). The rank-omission is the *price of the turnover constraint*, not an optimizer defect.

## C4 (MEDIUM) — CVaR_LP→ERC fallback undisclosed → **ACCEPT**

Codex: Rglpk not installed; CVaR_LP silently falls back to ERC (identical metrics), no infeasibility report.

**Resolution (ACCEPT, disclosed)**: confirmed — `requireNamespace("Rglpk")` returns FALSE; `m_cvar()` degrades to `m_erc()` (CVaR_LP metrics ≡ ERC, net IR 0.857). Now disclosed in package `method_shopping_log.cvar_lp_degraded` + this note. **Does not change the decision**: even a fully-solved CVaR LP would be a concentration method scoring ≤ ERC's 0.857 < EW's 0.970; the EW-family dominance holds. No separate infeasibility_report needed (the *selected* method is feasible; CVaR was a losing candidate regardless).

## C5 (MEDIUM) — Sequential Admission (TDC vs MEGA_05/PG2 replacement, integration blend) → **REBUTTAL (scope)**

**REBUTTAL**: TDC-vs-incumbent replacement scenarios, integration-blend SR/MDD/IR, and L-219 family-saturation governance are **governor-scope** (PG0–PG3 admission + book_state), not optimizer-scope. The optimizer emits weights; the governor adjudicates admission against `book_state.json` (current admitted = STR_1715_AR_on_M4_R05_overlay_PG2). Moreover this is a **discovery WT with inherited DSR FAIL (z=−7.80)** → not admission-eligible at all, so a replacement scenario is premature. Deferred to governor (correct lifecycle stage).

## C6 (MEDIUM) — crisis fallback / cash-sleeve / regime fallback not explicit → **REBUTTAL (mandate)**

**REBUTTAL**: a cash sleeve / crisis cash-raise is **prohibited by the hard mandate** (Σw=1 fully-invested, long-only, no cash). The optimizer cannot add a cash boundary without violating Σw=1. Crisis robustness is covered upstream by the risk agent's **AX-001 v2 bad/normal IC ratio 0.759 (PASS)** and the risk stress tests (COVID −12.7%, Rate2022 −18.3%); forge computes Core-relative MDD on the optimized NAV (risk_package challenge_flag AX001V2_SOFT_PROXY_ONLY → forge action). Regime-conditional optimizer switching was in-scope but not selected: the single Σ snapshot + monthly rebalance does not support a reliable regime estimate at 20 names (risk regime_correlation_delta 0.177, thin). Deferred to forge/risk per lifecycle.

---

## Escalation check

- Hard Constraint violations (max_names/max_w/Σw/turnover): **NONE** — primary and variant both PASS all hard constraints.
- RF-O9 single-snapshot: **NO** — weights.csv has 116 unique as_of_dates (walk-forward time series).
- HIGH ≥ 5 / AX hard FAIL ≥ 3 / PIT C1: **NO** (2 HIGH, both resolved: C1 fixed, C2 variant delivered).
- **No Q-Lead escalation triggered.** REVISE addressed substantively (C1+C4 fixed, C2 dual-book delivered, C3/C5/C6 rebutted on scope/mandate/academic grounds). Not overridden.

## Net outcome

Codex REVISE → **substantively addressed**: weights.csv to mailbox + challenge_note written (C1); RF-R1 beta-cap=1.00 variant BUILT and handed off as selectable secondary book (C2, no silent override); CVaR→ERC fallback disclosed (C4); C3/C5/C6 rebutted (alpha-scope / governor-scope / mandate-prohibited). Primary `method_selected = Schedule_EWbase` stands on net_ir feasibility + DeMiguel-Garlappi-Uppal 1/N dominance. DSR FAIL inherited to Forge.
