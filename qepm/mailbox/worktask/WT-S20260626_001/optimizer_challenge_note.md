# Optimizer Challenge Note — WT-S20260626_001 (max-cash overlay combine)

**Agent**: optimizer-research · **Codex**: gpt-5.5 xhigh · **Stance**: REVISE (veto_flag=false)
**Disposition**: REVISE accepted on C1/C2/C3/C6 (concrete fixes); C4/C5 PARTIAL (documented policy + surfaced as forge/governor-owned). No Silent Override — all concerns answered below.

## Autonomous classification

| ID | Sev | Concern | Class | Action |
|----|-----|---------|-------|--------|
| C1 | HIGH | weights.csv schema (as_of_date,ticker,weight,method_selected) + mailbox copy missing | **ACCEPT** | Rewrote weights.csv with role-schema columns; wrote `qepm/mailbox/.../weights.csv` copy. |
| C2 | HIGH | package omits turnover_annual / estimated_cost / net_ir | **ACCEPT (partial)** | Computed package-native turnover + cost (below). net_ir REBUTTED as forge-authoritative (no realized return at optimizer stage). |
| C3 | HIGH | TE 5.12% from single best-overlap month; Σ overlap poor (mean 1.75 names) | **ACCEPT** | Downgraded TE to descriptive (non-decision); added overlap diagnostic + root-cause (inherited Σ fixed to 2026-05 holdings). |
| C4 | MED | CRISIS fallback not explicit; max-cash less defensive in co-firing | **PARTIAL** | Documented crisis-month policy (3 CRISIS months, min-operator behavior). Realized CVaR/MDD A/B = forge (REBUTTAL on demanding it pre-forge — sizing_only mandate). |
| C5 | MED | beta drift + sequential admission (TDC vs PG2) missing | **REBUTTAL** | beta_port requires full backtest (forge); TDC-vs-PG2 is governor PG2 admission step. Surfaced as required downstream outputs, out of optimizer scope. |
| C6 | LOW | no challenge_note | **ACCEPT** | This file. |

## C2 — package-native turnover + cost (computed, not deferred)

Delta-based v2.4 (15bps one-way), full 269-month schedule incl CASH leg:

- **One-way annual turnover = 685.3%/yr** (gate basis = engine `Turnover_Pct` annualized; hurdle_gate.R D002 cap 1100% → **PASS**, margin -414pp).
- Round-trip annual = 1370.6%/yr (cost-accounting figure, Charter ×2 convention — reported for honesty; the **1100% hurdle cap is on the one-way engine basis** per hurdle_gate.R D002 which sums per-rebalance `Turnover_Pct`).
- **Estimated annual cost = 2.06%/yr** (15bps delta v2.4).

**Critical decomposition (honesty — the turnover is NOT introduced by this WT's change):**
- Base-sleeve stock churn = **784%/yr one-way**, COMMON to both arms (inherent STR_1715 top-20 monthly re-selection; in production this is hidden because `04_holdings.csv` collapses the base sleeve to one pseudo-asset → reported turnover 0, but the 15bps churn cost is baked into STR_1715 `ret_net`).
- Cash-leg turnover: **max-cash 96.3%/yr vs incumbent product 113.1%/yr** → max-cash has *LOWER* cash-leg turnover (min is less violent than product). 
- **Net: max-cash total turnover ≤ incumbent.** The combine change does not raise turnover; it marginally lowers it. RF-O2/RF-O10 not triggered by the change.

## C3 — TE downgraded to descriptive

Inherited 18×18 LW Σ is fixed to 2026-05-01 holdings basis; it overlaps the 269-month weight schedule poorly (mean 1.75 names, 5/269 dates ≥10 overlap, 2026-06 = 4/18). The 5.12% headline is from the single best-overlap month (2026-03, 15/18). **TE is therefore descriptive context, NOT decision-grade evidence.** Realized TE is forge-authoritative. The schema-required `expected_tracking_error` field retains 5.12% (an honest ex-ante figure on the best-overlap month) but is labeled `estimated` + flagged low-confidence. Divergence-month check (2023-06): max-cash TE 1.50% > incumbent 1.27% — directionally confirms max-cash carries more exposure/TE in co-firing months (mechanism-consistent).

## C4 — CRISIS policy (documented)

Overlay schedule has 3 CRISIS months. min-operator behavior in CRISIS: β_R05 ∈ {0.30 (CRISIS&z<q20), 0.50 (CRISIS)}, β_AR ∈ {0.4,0.7,1.0}. `min(β_AR,β_R05)` in CRISIS = the deeper of the two single de-risks (e.g. β_AR=0.7, β_R05=0.3 → min 0.30 vs product 0.21). So **max-cash STILL applies a deep single de-risk in CRISIS** — it only removes the *compound* (product) extra de-risk. No new crisis cash-floor or max_w shrink added (would change >1 thing; WT mandate = single change). Realized CRISIS CVaR/MDD A/B = forge. AX-001 v2 conditional metric is evaluated on realized CRISIS/CAUTION SR by forge/judge, not at optimizer stage (Codex AX-001 FAIL flag = pre-forge expected; no realized series exists here).

## C5 — beta drift + sequential admission (out of optimizer scope, surfaced)

- `beta_port` vs KOSPI200 (overlay-OFF vs blended) requires a realized return backtest → **forge output** (`auto_regime_overlay_ab.R` A/B). Optimizer cannot compute beta_port without running the backtest (role boundary: no full backtest).
- TDC vs PG2 / MEGA_05 active book + replacement-vs-integration scenario = **governor PG2 admission** step (sequential admission TDC<0.30). Out of optimizer scope. This WT is sizing_only single-change on the EXISTING book strategy (STR_1715 = current PG2 book) — it is a *within-strategy combine swap*, not a new sleeve admission; replacement/integration framing applies at governor, not optimizer.

## Required downstream outputs (handed to forge / governor)
1. **forge**: A/B realized net_IR, SR, MDD, CVaR, co-firing-month (32) drawdown, GFC stress, beta_port (overlay-OFF vs blended) for incumbent-product vs max-cash arms. Gate = book-marginal ΔIR ≥ 0.05 + MDD non-worsening.
2. **governor**: TDC vs PG2 book, replacement-vs-integration (within-strategy swap).

## AX-008 tally
- Source 1/3 = optimizer (this). Stance: final (post-revision). Codex AX-008 FAIL is *expected* pre-forge (Forge+Judge evidence not yet present). Triangulation completes at judge.
- HIGH concerns after revision: C1 resolved, C2 resolved (turnover/cost reported + decomposed), C3 resolved (TE downgraded). No substantive AX/PIT hard FAIL introduced by optimizer. No Q-Lead escalate trigger (no hard-constraint violation: n=20≤25, w≤0.20, Σw=1, one-way TO 685%<1100%).
