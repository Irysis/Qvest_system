# WT-D20260511_001 — Weight Method Selected (Final, Post-Codex)

## Method: `5sleeve_pareto_frontier_high_20pct_primary_med_10pct_conservative`

### Description
Sleeve-level 5-sleeve allocation Pareto frontier output. Primary metric-based recommendation: **high_20pct**. Conservative alternative (Charter §8 incremental): **med_10pct**. Governor selects final admit level based on book-state risk budget.

### Pareto Frontier (Codex C4 ACCEPT — revised from single recommendation to frontier)

| Candidate | NEW weight | SR | CAGR | MDD | Sortino | Calmar | Net AR | IR | TC drag (bps) | Robustness penalty |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline_S4 | 0% | 2.001 | 20.4% | -8.09% | 2.123 | 2.364 | 0.0% | - | 0.0 | - |
| low_5pct | 5% | 2.167 | 20.8% | -6.54% | 2.341 | 2.977 | 1.5% | 0.42 | 4.17 | -0.0025 |
| med_10pct | 10% | 2.336 | 21.3% | -5.30% | 2.515 | 3.739 | 2.8% | 0.79 | 8.34 | -0.005 |
| **high_20pct** | **20%** | **2.643** | **22.2%** | **-5.21%** | **3.386** | **3.929** | **4.8%** | **1.37** | **16.68** | **-0.060** |

### Primary Recommendation: high_20pct

**Rationale (Codex C4 ACCEPT — quantification required)**:
- Net SR delta +0.638 raw / +0.578 post-robustness — Pareto-dominant on pure metric basis
- Pareto-dominant: SR > Sortino > MDD > Net AR > IR > Calmar
- Robustness penalty -0.060 SR (concentration above 15% + AX-001 v2 INCONCLUSIVE crisis discount) — accounted
- Even after penalty, dominates alternatives by +0.25 SR margin

### Conservative Alternative: med_10pct

**Rationale (Charter §8 incremental approach)**:
- Net SR delta +0.333 (post-robustness +0.328)
- AX-001 v2 INCONCLUSIVE: CI95 [0.546, 2.444] — defensive evidence borderline
- Cycle 4 first admit candidate — Asness-Frazzini practitioner 15% single-source heuristic
- L-280/281 Path C precedent: incremental admit (Hybrid 70/15/15)

### Allocation Tables

#### high_20pct (Primary)
| Sleeve | Weight | Per-Security |
|---|---|---|
| AR_on_M4 | 0.400 | 0.020 (20 × 5%) |
| TSMOM | 0.200 | 0.025 (8 × 12.5%) |
| KR_10y | 0.160 | 0.160 (1 ETF) |
| Cash | 0.040 | 0.040 (1) |
| NEW_VolSkew_3axis | 0.200 | 0.010 (20 × 5%) |
| **Σw** | **1.000** | |

#### med_10pct (Conservative)
| Sleeve | Weight | Per-Security |
|---|---|---|
| AR_on_M4 | 0.450 | 0.0225 (20 × 5%) |
| TSMOM | 0.225 | 0.0281 (8 × 12.5%) |
| KR_10y | 0.180 | 0.180 (1 ETF) |
| Cash | 0.045 | 0.045 (1) |
| NEW_VolSkew_3axis | 0.100 | 0.005 (20 × 5%) |
| **Σw** | **1.000** | |

### Hard Constraints Compliance

| Constraint | Status | Evidence |
|---|---|---|
| max_names_total | PASS_via_AX007_Exception_1 | Aggregate 50 tickers across 5 sleeves; per-sleeve ≤ 20 |
| long_only | PASS | All weights ≥ 0 |
| weight_bounds [0, 0.20] | PASS | Max per-security 0.180 (KR_10y A148070) |
| Σw = 1 | PASS | 1.0 to 1e-9 precision |
| universe KOSPI200 ∪ KOSDAQ150 | PASS | Alpha pkg filter |
| liquidity 2e8 | PASS_inherited | Alpha pkg universe filter |
| transaction_cost 15bps | PASS | v2.3_kr_retail_15bps |
| PIT C1-C15 | INHERITED | Alpha + Risk pkg compliance (Codex C7 REBUTTAL — alpha-agent domain) |

### Infeasible Constraints (explicit infeasibility_report)

| Constraint | Cap | Realized | Status |
|---|---|---|---|
| Portfolio CVaR_95 monthly | 2.5% | -3.25% (best, high_20pct) | **INFEASIBLE — structural to KR equity baseline (baseline -4.90% already breaches)** |
| Pair TDC NEW vs PG2 | 0.30 (RF-R3) | 0.438 | **BREACH — Q-Lead waiver via AX-007 Exception 1** |

**Resolution path**: Forge realized re-validation (Option A) + Q-Lead AX-007 Exception 1 waiver (Option B, L-219 precedent).

### Turnover Smoothing

| Stage | Value | Pass |
|---|---|---|
| Raw NEW sleeve one-way ann | 5.56× (556%) | - |
| Smoothing phi | 0.5 | - |
| Smoothed one-way ann | 2.78× (278%) | ≤ 3.00 PASS |
| Smoothed round-trip ann | 5.56× (556%) | ≤ 6.00 PASS (margin 44pp) |
| TC drag per 100% NEW (bps ann) | 83.4 | - |

### Codex Round

- **Initial stance**: REJECT
- **9 concerns**: 2 CRITICAL + 6 HIGH + 1 MEDIUM
- **Disposition**: 4 ACCEPT / 4 PARTIAL / 1 REBUTTAL
- **C7 REBUTTAL grounding**: PIT-C13/C14 alpha-agent domain (Charter v1.7 §8 No Silent Override — alpha challenge_note ACCEPT_TIMELINE)
- **Q-Lead escalation**: HIT (HIGH ≥ 5)
- **AX-008 triangulation**: 1.5/3 → Forge + Architect required for 2.5/3 floor
- **Challenge note**: `optimizer_challenge_note.md`

### Walk-Forward Bridge

This Discovery WT outputs **static sleeve allocation** (Pareto frontier). Walk-forward dynamic 5-sleeve framework deferred to **deployment_wt** next phase. Reference: WT-P20260509_002 DRO Wasserstein ε=0.1, extending from 4 to 5 sleeves.

### Forge Handoff

- Realized 5-sleeve CVaR re-validation with production weights (resolve risk pkg proxy disagreement -35% vs realized -4.90%)
- Ticker-level expansion: AR (STR_1715 prod), TSMOM (8 ETF basket), KR_10y (A148070), Cash, NEW (alpha top20 EW + phi=0.5)
- Walk-forward dynamic 5-sleeve extension

### Governor Decision Factors

1. Book-state risk budget (current admitted: STR_1715_AR 70 / TSMOM 15 / KR_10y 15 PG2)
2. AX-001 v2 INCONCLUSIVE evidence strength (require Forge realized cycle update)
3. TDC pair 0.438 > 0.30 cap — Q-Lead waiver via AX-007 Exception 1 (L-219)
4. CVaR cap infeasibility (structural)
5. TC drag annual 4-17bps across candidates (negligible vs SR delta)

---

**Created**: 2026-05-11 KST (revised post-Codex Round)
**Agent**: optimizer-research-WT-D20260511_001 v1.2-post-codex / Opus_4_7_1M
**Revision**: V2 — Codex Critic Round response (8/9 ACCEPT/PARTIAL, 1 REBUTTAL)
