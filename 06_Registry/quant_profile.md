# Quant Strategy Profile — Dohoon Kim

## Core Identity
**Regime-conditional multi-factor stock picker** on KOSPI 200, with physics/information-theory factor engine.

## Factor Preferences (Priority Order)

### Classical Factors (Always Present)
| Factor | Preferred Implementation |
|--------|------------------------|
| Value | Dual-Engine: EBITDA/EV + OpProfit_Fwd/EV. B/M as fallback |
| Quality | Z(GPA) - Z(Accruals), ICR < 1 "Zombie Filter" (penalty -3.0) |
| Momentum | **Residual** Path Consistency (Sum(Resid)/SD(Resid)), 12M-1M. Never raw price momentum |
| Safety | 0.5*Z(-Beta_Shrunk) + 0.5*Z(-IdioVol). Low-Beta + Low-IVOL anomaly |
| Growth | Sustainable Growth Gap: Z(SGR) - Z(Sales_Growth_Consensus) |

### Advanced/Exotic Factors (User's Innovations)
| Factor | Math Basis |
|--------|-----------|
| Differential Entropy (Aleph) | H(X) = -integral f(x)log(f(x))dx via KDE |
| Mutual Information (MI) | KDE 2D joint distribution → information-theoretic beta |
| Schrodinger Tunneling (STP) | Non-equilibrium potential from KDE → barrier crossing probability |
| Lyapunov Chaos Index (LHI) | Phase-space reconstruction, Rosenstein's algorithm |
| Transfer Entropy (MDF) | TE(stock→BM)/TE(BM→stock) — "Maxwell's Demon Factor" |
| Boltzmann Complexity (BC) | Permutation entropy stability across multiscale coarse-graining |
| Spectral Gap (SG) | MI-based network eigenvector centrality change rate |
| Phase Transition Detector (PTD) | Forbidden ordinal pattern count change rate |
| Kalman Beta | Dynamic Linear Model via dlm — time-varying beta |
| Hurst Exponent | R/S analysis, 252-day rolling window |

## Regime Detection (MANDATORY — never static model)
- MSM (Markov-Switching Multifractal) via Rcpp — primary
- HMM (2-state Gaussian) via depmixS4 — secondary
- Physics-based: Aleph threshold → "Buddha Mode" (full cash)
- Continuous exposure E_t preferred over binary on/off

## Portfolio Construction
- **Top 20-30 stocks** (concentrated stock-picking, not broad tilt)
- HRP (Ward's + OLO + Recursive Bisection) — preferred
- Advanced: AFD-HRP (Tail Dependence + RMT Denoising)
- Inverse volatility within clusters
- ERC (Equal Risk Contribution) for asset allocation

## Risk Management
- Sector-neutralized Z-scores with Winsorization (1st-99th percentile)
- Zombie Filter (ICR < 1 → penalty)
- Holding company exclusion (regex: 홀딩스|지주)
- Liquidity filter: KOSPI bottom 20%, KOSDAQ bottom 30% removed
- Buddha Mode / Event Horizon / Big Bang regime-conditional exposure
- Worst-month audit + Placebo test (GBM fake data)

## Non-Negotiable Rules
- R only (tidyverse + data.table)
- Monthly rebalancing, T+1 execution
- KOSPI200 + KOSDAQ150 universe
- Residual decomposition BEFORE factor computation (remove market beta)
- 15-20bp transaction cost
- Benchmark: KOSPI 200 (IKS200)
- set.seed(42) for reproducibility
- KDE over histograms ("Zero Mathematical Compromise")
- Continuous measures over discrete thresholds

## Evolution Trajectory
```
DVAA (Early) → RCA V1 (Classical) → RCA V2/V3 (Advanced)
→ Fractal Aegis (Transition) → Samsara (Physics v3.1)
→ Nirvana (Physics v4.1) → Maxwell (Information Theory)
```

## Strategy Generation Guidelines
When creating new strategies for this user:
1. Start with residual decomposition — never use raw returns
2. Include at least one regime detection layer
3. Prefer information-theoretic or physics-inspired factors
4. Sector-neutralize all factor scores
5. Use concentrated portfolio (20-30 stocks)
6. Build in crisis defense mechanism (cash or safe assets)
7. Use KDE for all distribution-based computations
8. Test for robustness: rolling Sharpe, stress periods, placebo
9. Name with thematic metaphor when possible
10. Document with English headers + Korean inline comments
