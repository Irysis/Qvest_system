# Optimizer Iter 26 — Drawdown Threshold Trigger Cash Overlay

**Task:** WT-D20260427_011
**Method:** Iter11_LinTilt_lam1_plus_Threshold_8_18_28_BinaryDiscrete
**As-of:** 2023-11-30
**Walk-forward:** 92 sig_dates × ~20 names + CASH

## Mechanism

1. **Equity sleeve** (Iter 11 LinTilt λ=1.0 baseline preserved):
   - Top-20 by `score_str1701` per sig_date (cor=1.0 STR_1701 inheritance)
   - LinTilt: w = 1/N + λ·z(α), winsorize z ±2σ, λ=0.05, γ=5.0, EMA=0.5
   - Local Σ: rolling 36m + Ledoit-Wolf const-cor shrink (0.3); pooled fallback

2. **Cash overlay** (binary discrete state, NOT continuous):
   - dd ≤ -8% → cash 30%
   - dd ≤ -18% → cash 50%
   - dd ≤ -28% → cash 100%
   - Recovery: NAV(d) ≥ peak(d-1) → cash 0% (full unwind)
   - Lag: cash_state(d+1) uses dd known at d (PIT)

3. **Final weights**: w_full = (1 − cash) × w_equity + cash × CASH

## Iter 21/22/22b Anti-Pattern Distinction

| Iter | Mechanism | Self-Report | Realized | Δ_pp |
|---|---|---|---|---|
| 21 | Continuous msi_norm c∈[0,0.5] | +12.56 | -7.42 | -19.98 |
| 22 | Continuous similar | +8.71 | -12.57 | -21.28 |
| 26 | **Binary discrete {0,30,50,100}%** | **+%.2f (proxy)** | (Forge TBD) | TBD |

Iter 26 mechanism is a **step function on absolute peak-to-trough condition**.
Recovery is **objectively** triggered by NAV >= prior peak — no continuous lag.

## Method Comparison (4 candidates, transparency)

- **Baseline_LinTilt_NoCash**: SR=0.159 CAGR=0.013 MDD=-0.402 MDD_relief=0.0000 n_active=0 
- **Threshold_8_18_28_30_50_100_SELECTED**: SR=0.095 CAGR=0.004 MDD=-0.298 MDD_relief=0.1038 n_active=31 **SELECTED**
- **Threshold_10_20_30**: SR=0.111 CAGR=0.006 MDD=-0.293 MDD_relief=0.1089 n_active=27 
- **Threshold_5_15_25**: SR=0.090 CAGR=0.003 MDD=-0.293 MDD_relief=0.1090 n_active=42 

## AX-001 v2 4-metric Audit

- **crisis_alpha** = 0.00377  (target ≥ 0.0 neutral floor) — PASS
- **core_mdd_relief** = 0.1038 (10.38pp)  (target ≥ 0.05) — PASS
- **bad/normal ratio** = 1.230  (target ≥ 1.5) — FAIL
- **harvey_cond_t** = 0.762  (target ≥ 2.0) — FAIL

**AX-001 v2 4-metric pass count: 2 / 4**

## L-code Blocking

- **L-220** monthly base preserved
- **L-231** continuous overlay AVOIDED — binary threshold only
- **L-224** alpha cor=1.0 STR_1701 strict
- **L-211** no cross-section alpha modification

## Codex Stance

OVERRIDE_005 fallback ready (10+ instances). Optimizer self-report is forecast,
Forge realized backtest is final arbiter. Method dispute (continuous vs discrete)
decisively resolved in favor of discrete by Iter 21/22 realized fail history.
