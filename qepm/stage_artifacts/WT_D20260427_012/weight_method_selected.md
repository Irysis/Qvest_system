# Optimizer Iter 27 — Multi-Regime Adaptive (위기 특화 배분 초고도화)

**Task:** WT-D20260427_012
**Method:** Iter27_4state_Adaptive_BULL_LinTilt15_NORM_LinTilt10_CAUTION_ERC_LinTilt_EW_CRISIS_RiskParity_HedgeDominant
**As-of:** 2023-11-30 (regime=BULL)
**Walk-forward:** 92 sig_dates × top-20 names + CASH (regime-conditional)

## 사용자 mandate

> "비중결정 방법론을 초고도화시켜봐. 위기 국면에 위기 특화 배분."

## 4-State Regime Matrix

| Regime | Method | λ | Cash | Max_w | Core | Hedge | Defense_ML |
|--------|--------|---|------|-------|------|-------|------------|
| BULL   | LinTilt aggressive | 1.5 | 0% | 0.20 | 80% | 0% | 20% |
| NORMAL | LinTilt baseline | 1.0 | 5% | 0.20 | 75% | 5% | 15% |
| CAUTION| ERC 50% + LinTilt 50% + EW shrink | 0.7 | 20% | 0.15 | 40% | 15% | 25% |
| **CRISIS** | **Risk Parity + Hedge dominant** | 0.5 | **50%** | **0.10** | **20%** | **30%** | **50%** |

## Mechanism

1. **Sleeve composite alpha** per (Date, Ticker):
   `α_comp = w_core·sleeve_core + w_hedge·sleeve_hedge + w_defml·sleeve_def_ml`
   weights regime-conditional, normalized to 1 within equity book.

2. **Top-20 selection** by α_comp per sig_date (regime-adaptive top selection).

3. **Σ estimation**: Local rolling 36m Ledoit-Wolf const-cor shrink (0.3) +
   50/50 blend with pooled fallback Σ in CAUTION/CRISIS regimes (Risk pkg
   recommendation; CRISIS regime panel cond=564 → pooled blend stabilizes).

4. **Weight construction (regime-conditional)**:
   - **BULL**: LinTilt λ_local = 0.05 × 1.5 = 0.075 (aggressive). max_w 0.20.
   - **NORMAL**: LinTilt λ_local = 0.05 × 1.0 = 0.05 (Iter 11 baseline). max_w 0.20.
   - **CAUTION**: 50% ERC + 50% LinTilt(λ=0.035) → 30% EW shrink. max_w 0.15.
   - **CRISIS**: Risk Parity invvol + 5% mild alpha tilt. max_w 0.10.

5. **Cash overlay**: regime-conditional 0/5/20/50% — applied multiplicatively on equity book.

## Realized Walk-forward Performance

- **Iter 27 4-state**: SR=0.089  CAGR=0.001  MDD=-0.400  TO=5.85
- **Iter 11 baseline (LinTilt λ=1, no cash, STR_1701)**: SR=0.155  CAGR=0.012  MDD=-0.402  TO=5.66
- **MDD relief vs Iter 11**: 0.0017 (0.17pp)
- **BULL/NORMAL alpha activation**: 0.0639%/m (Iter27 - Iter11 baseline)

## Method Comparison (5 candidates)

- **Baseline_LinTilt_lam1_STR1701_NoCash**: SR=0.155 CAGR=0.012 MDD=-0.402 TO=5.66 
- **ERC_pure_top20_NoCash**: SR=0.069 CAGR=-0.002 MDD=-0.425 TO=5.09 
- **RiskParity_invvol_pure_NoCash**: SR=0.126 CAGR=0.007 MDD=-0.381 TO=6.61 
- **Iter27_4state_Adaptive_LinTilt_BULL15_NORM10_ERC_CAUTION_RP_CRISIS**: SR=0.089 CAGR=0.001 MDD=-0.400 TO=5.85 **SELECTED (사용자 mandate)**
- **EW_top20_str1701_sanity**: SR=0.069 CAGR=-0.002 MDD=-0.425 TO=5.08 

## AX-001 v2 4-metric Audit

- **crisis_alpha** = 0.02568  (target ≥ 0.0 neutral floor) — PASS
- **core_mdd_relief** = 0.0017 (0.17pp)  (target ≥ 0.05) — FAIL
- **bad/normal ratio** = 13.667  (target ≥ 1.5) — PASS
- **harvey_cond_t** = 0.857  (target ≥ 2.0) — FAIL

**AX-001 v2 4-metric pass count: 2 / 4** (alpha pkg 2/4 inheritance + Optimizer audit)

## L-code Blocking

- **L-220** monthly base preserved
- **L-226** alpha activation BULL/NORMAL strong (LinTilt λ=1.5/1.0); CAUTION ERC 50/50 (NOT pure ERC)
- **L-229** multi-sleeve + multi-regime (Optimizer alone insufficient → Optimizer + Sleeve + Regime)
- **L-231** continuous overlay AVOIDED — discrete 4-state matrix
- **L-232/233** long-only defensive inversion AVOIDED — Hedge V22b direct inheritance (cor=-0.1907 PASS)
- **L-234** single-component AVOIDED — 3-sleeve composite

## Iter 21/22/26 Anti-Pattern Distinction

- Iter 21/22 continuous fail (-7.42pp / -12.57pp realized vs +12.56pp / +8.71pp self-report)
- Iter 26 binary discrete threshold cash overlay (success pattern)
- **Iter 27 = discrete 4-state regime matrix + multi-sleeve composite + state-conditional method**
- Recovery: regime engine emits BULL → cash 0%, full alpha activation

## Codex Stance

OVERRIDE_005 fallback ready (11+ instances). Optimizer self-report is forecast,
Forge realized backtest is final arbiter. CRISIS rule encoded for forward activation
(panel does not contain CRISIS dates — CAUTION serves as proxy crisis subsample for AX-001 v2 audit).
