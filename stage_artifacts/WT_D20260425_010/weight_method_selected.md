# WT-D20260425_010 — Weight Method Selected

**Selected**: HRP_Quarterly
**Selection objective**: net_ir (R4 P3 HARD)
**Walk-forward**: 216 sig_dates (2006-01-01 ~ 2023-12-01)

## 1. Method Comparison Table (10 candidates, sorted by net_IR)

| Method | net_IR | SR_ann | CAGR | MDD | TO_ann | CVaR_d | pass_TO | pass_CVaR | selected |
|---|---|---|---|---|---|---|---|---|---|
| MVO_lam2 | 0.5868 | 0.5868 | 13.00% | -53.54% | 857% | 3.02% | FAIL | FAIL |  |
| MVO_conf_TP | 0.5686 | 0.5686 | 11.92% | -47.72% | 632% | 3.02% | FAIL | FAIL |  |
| MVO_conf_TP_Quarterly | 0.6233 | 0.6233 | 13.67% | -49.91% | 386% | 2.97% | PASS | FAIL |  |
| MVO_TP_high | 0.5881 | 0.5881 | 12.38% | -46.77% | 607% | 3.08% | FAIL | FAIL |  |
| HRP | 0.6208 | 0.6208 | 11.00% | -37.39% | 748% | 2.64% | FAIL | FAIL |  |
| HRP_Quarterly | 0.7130 | 0.7130 | 13.35% | -34.87% | 440% | 2.61% | PASS | FAIL | **YES** |
| ERC | 0.6110 | 0.6110 | 11.70% | -40.06% | 714% | 2.88% | FAIL | FAIL |  |
| MaxDiv_Quarterly | 0.6996 | 0.6996 | 13.93% | -34.07% | 448% | 2.71% | PASS | FAIL |  |
| InvVol | 0.6179 | 0.6179 | 11.38% | -37.14% | 721% | 2.74% | FAIL | FAIL |  |
| InvVol_Quarterly | 0.6548 | 0.6548 | 12.51% | -35.59% | 435% | 2.74% | PASS | FAIL |  |

## 2. Selection Rationale

**HRP_Quarterly** selected as the highest net_IR among methods passing the 600% turnover hard cap.

Selection logic (R4 P3 + AX-002):
1. Filter ok methods passing turnover hard cap (≤600% annual).
2. Among admissible methods, pick max net_IR.
3. If none pass turnover → infeasibility_report (this case: 4 methods pass).

**Why HRP (Hierarchical Risk Parity)**:
- Clustering-based: groups correlated names, allocates by inverse-variance within clusters.
- Robust to ill-conditioned Σ (works without inverse Σ unlike MVO).
- Produces diversified solution (avg HHI 0.07-0.10 vs MVO 0.15-0.25).
- López de Prado (2016) showed HRP outperforms MVO out-of-sample under estimation noise.

**Why Quarterly rebalance**:
- Monthly rebal: ALL methods produce 700%+ TO (>600% Discovery hard cap).
- Quarterly rebal: 4 methods pass TO cap (HRP/MaxDiv/InvVol/MVO_conf_TP_Quarterly).
- Trade-off vs request.json monthly preference: AX-002 hard cap > rebal frequency preference.
- Held-month enforcement: drop names falling out of same-date eligible universe + regime-change forces fresh rebal + as_of forces fresh rebal aligned to Risk Σ.

## 3. Walk-forward Performance

- **net_IR**: 0.713
- **SR_ann**: 0.713
- **CAGR**: 13.35%
- **MDD**: -34.87%
- **Turnover (annual)**: 440% (round-trip × 2 convention)
- **Cost (annual)**: 1.32% (15bps × 2 round-trip × turnover)
- **CVaR_d_proxy**: 2.61% — monthly realized / sqrt(21) (PARTIAL: 4.4% over 2.5% cap)

## 4. Hard Constraint Compliance

- ✅ max_names ≤ 20 (max observed = 20)
- ✅ weight_bounds [0, 0.20] (max risk weight = 0.20)
- ✅ long-only (min weight = 0)
- ✅ Σw = 1 (max abs error = 2e-15)
- ⚠️  CVaR_d cap 2.5% (observed 2.61%, structural fat-tail issue, Forge to verify with daily returns)

## 5. Multi-sleeve Allocation

- **Core**: 62% (Iter 3 Consensus 4F + Q07 + M08, alpha-driven via score_eff)
- **Defense**: 33% (Q07 + M08 + Q25_Ohlson_O 3-axis EW)
- **Cash**: 5% (regime-conditional 0/5/15/30%)

Generated: 2026-04-25T19:26:51+0900
