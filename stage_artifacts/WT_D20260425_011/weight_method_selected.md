# WT-D20260425_011 — Weight Method Selected (Iter 6 MEGA_06)

**Selected**: InvVol_Quarterly_KO
**Selection objective**: net_ir (R4 P3 HARD)
**Walk-forward**: 215 sig_dates (2006-01-01 ~ 2023-11-01)
**Deploy cutoff**: 2023-11-01 (v6.2 mandate)

## 1. Method Comparison Table (10 candidates, sorted by net_IR; all with Kelly+Overlay)

| Method | net_IR | SR_ann | CAGR | MDD | TO_ann | CVaR_d | pass_TO | pass_CVaR | selected |
|---|---|---|---|---|---|---|---|---|---|
| MVO_lam2_KO | 0.6432 | 0.6432 | 9.15% | -29.18% | 527% | 1.77% | PASS | PASS |  |
| MVO_conf_TP_KO | 0.6419 | 0.6419 | 9.13% | -29.13% | 526% | 1.77% | PASS | PASS |  |
| MVO_conf_TP_Quarterly_KO | 0.6815 | 0.6815 | 10.05% | -26.55% | 334% | 1.78% | PASS | PASS |  |
| MVO_TP_high_KO | 0.6404 | 0.6404 | 9.11% | -29.18% | 526% | 1.77% | PASS | PASS |  |
| HRP_KO | 0.5771 | 0.5771 | 7.78% | -31.71% | 566% | 1.77% | PASS | PASS |  |
| HRP_Quarterly_KO | 0.6970 | 0.6970 | 10.06% | -29.25% | 342% | 1.77% | PASS | PASS |  |
| ERC_KO | 0.6619 | 0.6619 | 8.82% | -30.04% | 554% | 1.67% | PASS | PASS |  |
| MaxDiv_Quarterly_KO | 0.7136 | 0.7136 | 10.06% | -27.79% | 345% | 1.76% | PASS | PASS |  |
| InvVol_KO | 0.6554 | 0.6554 | 8.73% | -28.71% | 551% | 1.66% | PASS | PASS |  |
| InvVol_Quarterly_KO | 0.7627 | 0.7627 | 10.73% | -27.73% | 337% | 1.66% | PASS | PASS | **YES** |

## 2. Selection Rationale

**InvVol_Quarterly_KO** selected as the highest net_IR among methods passing both
the turnover hard cap (≤600%) and the CVaR_d cap (≤2.5%).

Selection logic (R4 P3 net_ir + AX-002):
1. Filter ok methods passing turnover hard cap (≤600% annual).
2. Among admissible, pick max net_IR.
3. CVaR_d cap (≤2.5%) PASS for InvVol family (1.66%) — Iter 5 breach (HRP_Quarterly 2.61%) RESOLVED.

**Why InvVol (Inverse Volatility)**:
- Robust to ill-conditioned Σ (only diag(Σ) used).
- Concentrates on low-vol names → naturally CVaR-friendly (selected CVaR_d=1.66% vs HRP 1.78%).
- Combined with Kelly_frac05 cap and 3-Layer Overlay, achieves diversification + tail control.
- Iter 6 surprise: InvVol_Quarterly outperforms HRP_Quarterly net_IR by +6 bps (0.763 vs 0.697)
  while also producing lower CVaR_d (1.66% vs 1.78%) — better risk-adjusted on both axes.

**Why Quarterly rebalance**:
- Monthly rebal: TO 525-566% (close to 600% cap, no margin for ADV-pacing in deployment).
- Quarterly rebal: TO 334-345% (44% safety margin under 600% cap).
- Trade-off vs request.json monthly preference: AX-002 hard cap > rebal frequency preference.
- Held-month enforcement: drop names falling out of universe + regime-change forces fresh rebal.

## 3. Walk-forward Performance

- **net_IR**: 0.763
- **SR_ann**: 0.763
- **CAGR**: 10.73%
- **MDD**: -27.73%
- **Turnover (annual)**: 337% (round-trip × 2)
- **Cost (annual)**: 1.01% (15bps × 2 round-trip × turnover)
- **CVaR_d_proxy**: 1.66% — PASS (cap 2.50%)

## 4. Iter 6 vs Iter 5 (HRP_Quarterly) comparison

| Metric | Iter 5 HRP_Quarterly | Iter 6 InvVol_Quarterly_KO | Δ |
|---|---|---|---|
| net_IR | 0.713 | 0.763 | +7.0% |
| CAGR | 13.35% | 10.73% | -2.62 pp |
| MDD | -34.87% | -27.73% | +7.14 pp |
| TO ann | 440% | 337% | -103 pp |
| CVaR_d | 2.61% (FAIL) | 1.66% (PASS) | -0.95 pp |
| Kelly+Overlay | NO | YES (frac05 + 3-Layer) | NEW |

Iter 6 KEY WIN: lower TO + lower MDD + lower CVaR + higher net_IR + Kelly+Overlay machinery.
Trade-off: lower CAGR (10.73% vs 13.35%) — Kelly+Overlay reduces gross exposure (avg cash 32%).

## 5. Hard Constraint Compliance

- ✅ max_names ≤ 20 (max observed = 20)
- ✅ weight_bounds [0, 0.20] (max risk weight = 0.20 + floating-point tolerance 2.7e-13)
- ✅ long-only (min weight = 0.003)
- ✅ Σw = 1 (max abs error = 0)
- ✅ CVaR_d cap 2.5% (observed 1.66%)
- ✅ Turnover cap 600% (observed 337%)

## 6. Multi-sleeve + 3-Layer Overlay Allocation

- **Core**: 55% (4F Consensus C01_SUE+C02_EPS_Chg_1m+C04_ESBR+C06_TP_Gap)
- **Defense**: 30% (Q07+M08+Q25 3-axis EW)
- **Cash**: 15% (3-Layer combined: DD Brake + FM Regime + VolReg)

## 7. Regime-specific Schedule Diagnostics

| Regime | n_dates | avg_cash | avg_dd_cash | avg_fm_cash | avg_vol_scale |
|---|---|---|---|---|---|
| BULL | 69 | 0.1259 | 0.0186 | 0.0000 | 0.8891 |
| NORMAL | 117 | 0.4001 | 0.1461 | 0.0500 | 0.7100 |
| CAUTION | 24 | 0.6192 | 0.3099 | 0.1500 | 0.5710 |
| CRISIS | 5 | 0.6380 | 0.3198 | 0.3000 | 0.5679 |

Generated: 2026-04-25T23:53:22+0900
