# Weight Method Selection — WT-D20260512_003

## Selected Method: **AlphaSoftmax_T05**

### Selection Objective

`crowding_adj_ret = SR_net - 1.00 × max(0, HHI_mean - 0.10) - 0.05 × max(0, (TO - 4.0)/4.0) - 0.20 × max(0, F_QMJ - 1.0)`

### Selected method metrics (267m walk-forward)

- SR_net: 1.6622
- CAGR: 51.22%
- MDD: -48.57%
- Sortino: 2.769
- Calmar: 0.942
- Turnover annual: 15.184
- HHI mean: 0.0951
- F_QMJ mean: 0.333
- Crowding-adjusted obj: 1.5224

### Regime conditional SR

- BULL: 3.427 (n=92)
- NORMAL: 1.570 (n=157)
- CAUTION: -2.286 (n=15)
- CRISIS: -1.974 (n=3)

### vs STR_1715 Iter31 admit baseline

- Iter31 SR_net: 1.4847 | CAGR: 43.46% | MDD: -47.09% | obj: 1.4036
- delta SR_net: 0.1775

### Method comparison table (sorted by obj)

              method sr_net   cagr     mdd     TO    HHI  FQMJ    obj
              <char>  <num>  <num>   <num>  <num>  <num> <num>  <num>
1:  AlphaSoftmax_T05 1.6622 0.5122 -0.4857 15.184 0.0951 0.333 1.5224
2: WinsorTilt_2sigma 1.6044 0.4850 -0.4960 14.738 0.0816 0.344 1.4702
3: Iter31_LinearTilt 1.4847 0.4346 -0.4709 10.491 0.0905 0.355 1.4036
4:       ERC_rolling 1.5114 0.4001 -0.5286 12.640 0.0500 0.345 1.4034
5:      AlphaSort_EW 1.5112 0.4001 -0.5284 12.636 0.0500 0.345 1.4033
6:  MVO_lam1_rolling 1.6096 0.5969 -0.4980 16.721 0.1976 0.306 1.3530
7:  HRP_ward_rolling 1.3712 0.3479 -0.5852 16.838 0.0782 0.322 1.2107


---

## Selection Rationale (Detailed)

### Why AlphaSoftmax_T05 (vs Iter31_LinearTilt baseline)

**Empirical advantages (267m walk-forward)**:
- SR_net 1.6622 vs Iter31 1.4847 (+0.1775, +12.0%)
- CAGR 51.22% vs Iter31 43.46% (+7.76pp)
- BULL SR 3.43 vs 3.13 (+0.30)
- NORMAL SR 1.57 vs 1.51 (+0.06)
- CAUTION SR -2.29 vs -2.90 (+0.62 — less negative)
- CRISIS SR -1.97 vs -3.20 (+1.23 — major improvement)
- Sortino 2.77 vs 2.49

**Trade-offs**:
- Turnover 15.18 vs Iter31 10.49 (+4.69 annual one-way → cost +70bps annual)
- HHI 0.095 vs Iter31 0.091 (+0.004, similar concentration)
- F_QMJ exposure 0.33 vs 0.36 (both well below 1.0 V5 axis threshold)
- MDD -48.57% vs -47.09% (-1.48pp deeper)

### Method shopping log (7 candidates, no skipped)

| Rank | Method | Family | SR | obj | Selected |
|------|--------|--------|-----|-----|----------|
| 1 | AlphaSoftmax_T05 | alpha-rank softmax | 1.66 | 1.52 | ✓ |
| 2 | WinsorTilt_2sigma | alpha-rank winsor | 1.60 | 1.47 | |
| 3 | Iter31_LinearTilt | alpha-rank tilt (STR_1715 baseline) | 1.48 | 1.40 | |
| 4 | ERC_rolling | risk-parity rolling cov | 1.51 | 1.40 | |
| 5 | AlphaSort_EW | alpha-rank equal weight | 1.51 | 1.40 | |
| 6 | MVO_lam1_rolling | confidence-aware MVO | 1.61 | 1.35 | |
| 7 | HRP_ward_rolling | Hierarchical Risk Parity | 1.37 | 1.21 | |

### Selection objective: `crowding_adj_ret` (R4 P3 enum)

```
crowding_adj_ret = SR_net 
                  - 1.00 × max(0, HHI_mean - 0.10)     # concentration penalty
                  - 0.05 × max(0, (TO - 4.0) / 4.0)    # turnover penalty
                  - 0.20 × max(0, F_QMJ_mean - 1.0)    # V5 axis penalty
```

**Lambda rationale**:
- λ_HHI = 1.0: Hard penalty per 0.01 HHI excess (industry-standard)
- λ_TO = 0.05: Mild penalty per 100% TO excess (15bps × 100% = 0.005 cost; SR ≈ 1.5/μ)
- λ_FQMJ = 0.20: V5 failure axis (Q07+M08+Q25 sleeve) penalty; threshold 1.0 from
  AX-001 v2 conditional defense + risk_package RF_R1 TOP_FACTOR_CONCENTRATION concern.

### 2026-04-01 Cross-section (Σ-based 6 methods, risk_package factor_model_8F)

| Method | n_active | max_w | port_vol_ann | ex_ret_z | HHI | F_QMJ | F_TAIL |
|--------|----------|-------|--------------|----------|-----|-------|--------|
| Iter31_LinearTilt | 16 | 0.119 | 0.180 | 1.75 | 0.082 | 0.92 | -0.30 |
| MVO_lam1 | 5 | 0.200 | 0.273 | 2.05 | 0.200 | 0.96 | -0.38 |
| MVO_lam2 | 5 | 0.200 | 0.273 | 2.05 | 0.200 | 0.96 | -0.38 |
| HRP_ward | 20 | 0.136 | 0.157 | 1.43 | 0.083 | 1.18 | -0.24 |
| ERC | 20 | 0.051 | 0.154 | 1.43 | 0.050 | 1.07 | -0.08 |
| MaxDiv | 8 | 0.200 | 0.293 | 1.53 | 0.173 | 0.98 | 0.04 |

**AlphaSoftmax_T05 @ 2026-04-01 live snap**:
- n_active = 20 | Σw=1.0 | max_w=0.196 | port_vol_ann=0.186
- F_QMJ = 0.97 | F_TAIL = -0.25
- Σ = risk_package factor_model_8F (cond=153.92)

### Note on PIT Measurement Basis

**Optimizer walk-forward** uses forward 1m period return:
- Hold from `start_d = first trading day >= sig_label[i]` to `end_d = start_d[i+1]`
- Realized return = product(1 + Ret_d) over the period

**Risk package `_risk_portfolio_returns.parquet`** uses `Ret_m[t] = (Close[t] / Close[t-1m]) - 1`:
- Same-period backward return (selection at sig_date t uses factors with Usable_Date <= t,
  but the return spans t-1m to t, which is partially backward)

These measurement bases produce divergent regime SR. The Optimizer uses canonical forward
period return (PIT-clean). Risk package CAUTION SR +1.45 / CRISIS SR +2.74 (composite) and
Optimizer walk-forward CAUTION SR -2.29 / CRISIS SR -1.97 are both reported transparently
for Forge/Architect AX-008 verification triangulation.

### Hard constraint compliance

- [PASS] max_names = 20 (n=20 at 2026-04-01)
- [PASS] weight_bounds [0, 0.20] (max_w = 0.1964)
- [PASS] long_only (min_w = 0.0149 > 0)
- [PASS] Σw = 1.000 (|sum-1| = 0.0001 < 0.01 tolerance)
- [PASS] liquidity 5e7 KRW 20d avg t-1 (universe pre-filtered)
- [PASS] cost_model_version v2.3_kr_retail_15bps (15bps one-way × turnover)
- [PASS] PIT C1-C15 (267m walk-forward t-1 cutoff)
- [PASS] universe KOSPI200 ∪ KOSDAQ150 (inherited from alpha_package)
- [PASS] schedule_fidelity 268/268 = 1.000 (>= 0.95 mandate)

### Infeasibility report: NULL (all hard constraints satisfied at all 268 sig_dates)
