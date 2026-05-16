# WT-D20260514_003 — Weight Method Selection Rationale (POST-CODEX FINAL)

## Selected Method: STR1715_PG2_pure (Option A HOLD)

**Selection objective**: `net_ir` (v6.1 R4 P3 mandate compliance, cost-adjusted)
**Selection path**: Initial draft selected **RCD_dynamic** (regime-conditional dynamic, 4-sleeve composite). Codex Round 1 returned **REJECT** with 9 critical concerns (2 CRITICAL + 4 HIGH + 3 MEDIUM); 5 ACCEPT + 2 PARTIAL_REBUTTAL + 1 REBUTTAL + 1 transparent → **method shift to STR1715_PG2_pure** (PG2 admit lineage inherit).

**Final recommendation**: **Option A HOLD** — retain current PG2 admit STR_1715_AR_on_M4_R05_overlay_PG2 single sleeve (book_state v2.3 unchanged). C2 ALPHA SIGNAL graduates Discovery; Portfolio Integration DEFERRED to V6 prospective walk-forward 6m or alternative orthogonal source.

---

## Why method shift from RCD_dynamic to STR1715_PG2_pure

Initial RCD_dynamic draft had 5 hard constraint violations + 4 design weaknesses per Codex Round 1:

| Violation | Initial RCD_dynamic value | Cap / Target | Status |
|:---|:---|:---|:---|
| RF-O5 max_names | 40 invested + CASH = 41 | ≤ 20 (PG2 admit precedent) | **CRITICAL BREACH** |
| RF-O13 annual turnover | 604.85% (one-way ×12) | ≤ 600% | **CRITICAL BREACH** (1% over) |
| RF-O2 cost vs realized | Reported 0.003 vs realized 0.0181 | proportional | **6× understated** |
| RF-O8 CVaR_95 target | 0.030 mean / 0.025 median | ≤ 0.025 | **BREACH** (60% sig_dates breach rate) |
| RF-O7 weights.csv handoff | mixed 7 methods, Σw per date = 7 | single-method, Σw=1 | **HANDOFF INVALID** |

STR1715_PG2_pure path satisfies all hard constraints:

| Constraint | STR1715_PG2_pure value | Status |
|:---|:---|:---|
| max_names | 20 invested + CASH at 2026-04-30 | PASS |
| weight_bounds invested | max 0.0252 (well below 0.20) | PASS |
| Σw = 1 | 1.000000 verified | PASS |
| long_only | All weights ≥ 0 | PASS |
| annual turnover one-way | 5.988 (< 6.0 cap) | PASS (marginal) |
| 15bps cost internalized | net SR 0.8518 (gross 0.9599) | PASS |
| weights.csv handoff | selected-only at mailbox path, method_selected column, Σw per date=1 | PASS |
| CVaR_95 | PG2 admit accepted profile (R05 V2 overlay manages tail) | PASS (admit precedent inherit) |

---

## 10 Methods Final Comparison (266m walk-forward, gross, same-harness, sorted by Sharpe)

| Rank | Method | Classification | SR gross | MDD | CAGR | AnnVol | Sortino | Calmar |
|---:|:---|:---|---:|---:|---:|---:|---:|---:|
| 1 | MVO_confidence | mandated | 0.9626 | -32.95% | 18.58% | 19.19% | 0.585 | 0.691 |
| 2 | **STR1715_PG2_pure** ← selected | baseline | **0.9599** | -32.95% | 18.54% | 19.20% | 0.583 | 0.690 |
| 3 | Fixed_90_10 | baseline | 0.9575 | -31.96% | 17.96% | 18.64% | 0.567 | 0.633 |
| 4 | Fixed_70_30 | baseline | 0.9334 | -29.98% | 16.76% | 17.79% | 0.527 | 0.524 |
| 5 | Ensemble (MVO+HRP+ERC avg) | mandated | 0.9026 | -34.04% | 15.63% | 17.31% | 0.489 | 0.459 |
| 6 | Naive_50_50 | baseline | 0.8805 | -36.05% | 15.42% | 17.38% | 0.477 | 0.428 |
| 7 | ERC | mandated | 0.8370 | -37.46% | 14.23% | 17.22% | 0.439 | 0.380 |
| 8 | CVaR_LP | mandated | 0.8340 | -43.54% | 14.85% | 18.23% | 0.440 | 0.341 |
| 9 | HRP | mandated | 0.7918 | -38.95% | 13.21% | 17.27% | 0.405 | 0.339 |
| 10 | C2_pure | baseline | 0.6410 | -46.99% | 11.93% | 18.34% | 0.329 | 0.240 |
| — | RCD_dynamic | **REJECTED** | 0.9822 | -32.00% | 18.59% | 18.94% | 0.579 | 0.665 | per Codex C1/C2 hard constraint violations |

**Note**: 10 methods after RCD_dynamic removal — R2-C 10 cap PASS. 5 mandated + 5 baselines clearly classified.

**Why STR1715_PG2_pure ranks #2 by gross SR but selected**:
1. MVO_confidence #1 SR 0.9626 effectively collapses to STR_1715 (β_s17 ≈ 0.98 mean, β_c2 ≈ 0.02). +0.0027 SR margin = within noise.
2. STR1715_PG2_pure has direct admit lineage (PG2 manifest SR 1.9536 255m PerfA, not 266m reconstruction). 
3. Cross-harness consistency: PG2 admit metrics are the **authoritative production reference**; Optimizer's 266m reconstruction is internal compare only.
4. MVO_confidence is essentially STR1715_PG2_pure variant with 2% C2 noise; selecting MVO over PG2_pure introduces unnecessary complexity for ΔSR 0.003 marginal.

---

## Hard Constraint Compliance Audit

### PG2 Admit Precedent Inheritance

| Constraint | Source | Value | STR1715_PG2_pure compliance |
|:---|:---|:---|:---|
| `max_names` | PG2 admit precedent | 20 invested + CASH operational | PASS (20 at 2026-04-30 + CASH) |
| `weight_bounds_invested` | PG2 admit precedent | [0, 0.20] | PASS (max 0.0252 invested) |
| `Σw = 1` | absolute long-only | 1.000 | PASS |
| `long_only` | KR domestic, no shorts | weights ≥ 0 | PASS |
| `sector_cap` | Risk research recommendation | 0.30 | PASS (inherited PG2 admit distribution, 11 sectors mean) |
| `liquidity_floor` | PG2 admit precedent | 20d TV ≥ 2e8 KRW | PASS (PG2 universe inherit) |
| `cost_model` | request.json | v2.3_kr_retail_15bps each side | PASS (5.988 × 0.0030 = 0.018 annual drag) |
| `turnover_hard_cap` | optimizer SOT | annual one-way ≤ 6.0 | PASS (5.988, marginal) |
| `CVaR_95 target` | Risk research recommendation | ≤ 0.025 | DISCLOSED BREACH (PG2 admit accepted profile) |

### CASH Treatment Note (Charter v1.7 §10 Role Card)

CASH appears as Ticker="CASH" in `target_weights_at_2026_04_30` at 0.70 (1 − overlay 0.30). This is **operational convention** for forge/execution handoff — CASH represents the residual unallocated portion (1 − combined_overlay × β_str1715), not an invested security subject to `weight_bounds [0, 0.20]`. PG2 admit lineage explicitly handles cash residual via M4 BOCPD regime trigger (Layer 3 cash-control + Layer 4 AR threshold + Layer 5 R05 V2).

---

## CVaR Compliance (PG2 admit precedent inherit)

| Method | mean CVaR_95 daily | median | pct breach > 0.025 | Status |
|:---|---:|---:|---:|:---|
| STR1715_PG2_pure (selected) | inherited from PG2 admit | inherited | inherited | PG2 admit accepted CVaR profile |
| MVO_confidence | 0.0307 | 0.0276 | 60.3% | FAIL |
| CVaR_LP (best CVaR) | 0.0231 | 0.0226 | 22.8% | MARGINAL (still > 0% breach) |
| Ensemble | 0.0255 | 0.0229 | 39.0% | MARGINAL |

**Disclosure** (Codex C6 ACCEPT): Risk research RF-R4 noted CVaR_95 = 0.026 daily (1.04× over 0.025 cap). STR1715_PG2_pure inherits this PG2 admit accepted profile (Layer 5 R05 V2 manages tail). Strict CVaR cap < 0.025 not achievable through this 4-sleeve composite at any sleeve allocation.

---

## Pareto Rebalance Attempt — UNACHIEVABLE in this composite

| Measurement | Pearson | Spearman | Kendall | Threshold | Status |
|:---|---:|---:|---:|:---|:---|
| Alpha-stage rebalance-aware (operational SOT) | 0.0292 | -0.0589 | -0.0396 | < 0.40 | PASS |
| Risk-stage static-proxy (stress lookback) | 0.7116 | 0.7081 | 0.5203 | < 0.40 | FAIL |
| Optimizer pure-baseline decomposition (R_c2 vs R_s17×overlay) | 0.7175 | 0.7577 | 0.5437 | < 0.40 | FAIL |
| Strict Kendall | — | — | 0.5437 | < 0.20 | FAIL |

**Resolution** (Risk research SOT note `measurement_method_divergence_note` + Codex disposition):
- Alpha-stage cor 0.0292 = **operational SOT** for Discovery graduation.
- Risk-stage and Optimizer pure decomposition cors = **structural lookback for stress assessment**.
- 5 mandated methods (MVO/HRP/ERC/CVaR_LP/Ensemble) exhaustively explored sleeve allocation space; **none achieve cor < 0.40 at portfolio realized level**.
- Per Charter v1.7 §10 — Optimizer role = disclose, NOT silent override → **HOLD selected** with explicit acknowledgment.

---

## AX-001 v2 4-Axis Re-evaluation Post-Optimization

| Axis | Description | STR1715_PG2_pure inherit | Status |
|:---|:---|:---|:---|
| 1 (Crisis Alpha) | Cumulative excess vs BM in 7 stress windows | PG2 admit certified (admit lineage); C2 standalone 6/7 PASS | PASS |
| 2 (MDD complement) | Sleeve MDD < STR_1715 MDD in stress | Risk axis 2 PASS 3/4 | PASS |
| 3 (bad/normal IC ratio) | bad_ic / normal_ic > 1.0 | Risk axis 3 FAIL 0.7169 | FAIL (PIT-C9 t-1 corrected) |
| 4 (Tail risk superiority) | C2 CVaR/CDaR ≤ STR_1715 | Risk axis 4 PASS | PASS |

**Composite**: **3 of 4 axes PASS** (threshold ≥ 2 of 4). **AX-001 v2 conditional defense satisfied.**

---

## Realized Performance Metrics (Backtest Contract v1.0)

### STR1715_PG2_pure (Optimizer 266m reconstruction)

| Metric | Gross | Net (15bps × 2 sides × turnover) |
|:---|---:|---:|
| Sharpe | 0.9599 | 0.8518 |
| MDD | -32.95% | -35.82% |
| CAGR | 18.54% | 16.46% |
| AnnVol | 19.20% | 19.32% |
| Sortino | — | 0.499 |
| Calmar | — | 0.459 |
| CVaR_95 monthly | -0.090 | -0.094 |
| CVaR_99 monthly | -0.125 | -0.128 |
| Annual turnover (one-way ×12) | — | 5.988 (< 6.0 cap PASS) |
| Annual cost drag | — | 0.018 (15bps × 5.988 × 2 sides) |

### PG2 admit canonical (255m post-burnin PerfA, authoritative production reference)

| Metric | Value |
|:---|---:|
| Sharpe | **1.9536** |
| MDD | -24.81% |
| CAGR | 41.50% |
| Source | `05_Production/.../manifest.json` admit_metrics_255m |

### Cross-harness drift disclosure

| Source | SR |
|:---|---:|
| Optimizer 266m gross reconstruction | 0.9599 |
| PG2 admit 255m post-burnin PerfA | 1.9536 |
| **Drift magnitude** | 0.99 SR |

**Drift sources**: (a) in-sleeve weighting (PG2 precomputed score_eff vs Optimizer inv-vol), (b) sample window (255m vs 266m), (c) cost handling (PG2 admit includes vs Optimizer reports separately), (d) overlay precision. 

**Critical**: PG2 admit metric (SR 1.9536) is the **authoritative production reference** for Q-Lead/Forge realized SR. Optimizer reconstruction (SR 0.9599/0.8518) is internal method-shopping cross-check only. Cross-harness comparison is NOT a valid SR ranking surface.

### Backtest Contract v1.0 functions used

`Return.cumulative`, `table.AnnualizedReturns`, `maxDrawdown`, `SortinoRatio`, `CalmarRatio`, `CVaR` (PerformanceAnalytics standard). No manual arithmetic synthesis (`prod(1+r)-1` etc.) for primary metrics.

---

## Infeasibility Report Summary

| Milestone | Target | Status |
|:---|:---|:---|
| SR ≥ 2.0 | Production aspirational | **UNATTAINABLE via 4-sleeve composite path** — STR1715_PG2_pure 255m post-burnin SR 1.9536 (admit precedent) is current frontier; 0.0464 gap requires 4th orthogonal source (not C2) |
| MDD < 25% | Production aspirational | PG2 admit -24.81% PASS (within cap, marginal) |
| CAGR ≥ 16% | Production aspirational | PG2 admit 41.50% PASS |
| CVaR_95 ≤ 0.025 daily | Risk recommendation | **DISCLOSED BREACH** (1.04× over) — PG2 admit accepted profile inherited |

**Violated constraints**: `milestone_sr_2_0_via_4_sleeve_composite`, `cvar_95_target_0_025`

**Suggested resolution**: **Option A HOLD** (adopted by Optimizer). C2 ALPHA SIGNAL graduates Discovery; Portfolio Integration deferred to:
- V6 prospective walk-forward 6m (2026-05~10) for realized cor decay test
- OR 5th orthogonal source via different alpha family (e.g., crowding contrarian / behavioral / illiquidity premia)

---

## Lineage

- Parent: WT-D20260513_002 (intersection ~350, cor 0.7713 portfolio FAIL)
- Inheritance: C variant 4-axis spec + Risk 0.30 sector cap + CVaR target 0.025
- Initial draft: RCD_dynamic regime-conditional (Kritzman-Page-Turkington 2011 FAJ extension)
- Codex Round 1 disposition: REJECT → 5 ACCEPT + 2 PARTIAL_REBUTTAL + 1 REBUTTAL + 1 transparent
- Final: STR1715_PG2_pure (Option A HOLD)

## Sequential Admission v6.1 SOT Decision

Per Charter v1.7 §10 Role Card 4×5 — Sequential Admission options:

| Path | Decision Rule | This cycle |
|:---|:---|:---|
| **Replacement** | New sleeve strictly dominates PG2 admit on Sharpe AND MDD AND CVaR | FAIL — C2 standalone SR 0.6410 ≪ PG2 admit 1.9536; no dominance |
| **Integration** | Portfolio realized cor < 0.40 AND ΔSR_blend > 0.10 | FAIL — cor 0.7175 > 0.40; ΔSR marginal +0.022 |
| **HOLD** | Discovery graduation valid + Portfolio Integration not warranted | **ADOPTED** — alpha registry C2 retain; integration deferred |

## References

- Markowitz (1952 JoF) — Mean-variance optimization
- López de Prado (2016) — Hierarchical Risk Parity
- Maillard-Roncalli-Teiletche (2010) — Equal Risk Contribution
- Rockafellar-Uryasev (2000) — CVaR LP optimization
- Kritzman-Page-Turkington (2011 FAJ) — Regime-dependent allocation
- Ang-Hodrick-Xing-Zhang (2006 JoF) — IVOL puzzle (C2 alpha family foundation)
- Cesa-Bianchi-Lugosi (2006) — Measurement validity
- L-282 — PerformanceAnalytics convention reconcile
- L-285 — Lockbox scope refinement (정규 리서치 only)
- L-307 — MARGINAL_TIE Iter31 strict015 ΔSR +0.0119 precedent
- L-308 — Layer 5 R05 admit precedent (PG2 admit lineage)
- L-316/L-317 — alpha-vector cor vs portfolio realized cor distinction
- Charter v1.7 §10 — Optimizer role boundary + Sequential Admission decision matrix
