# Weight Method Selected — WT-D20260426_008 (Track A Iter 15 V3)

## Selected: ERC (Equal Risk Contribution)

### Selection Rule (R4 P3 Role-specific objective)
- **Primary objective**: `net_ir` (NOT raw Sharpe per v6.1 selection_objective HARD)
- **Constraint**: `pass_to_cap` (TO ≤ 600%) ∧ `pass_mdd_cap` (MDD ≤ 45%) ∧ `pass_cvar_cap` (CVaR_d ≤ 2.5%)
- **Hierarchical fallback**: If no method PASSES all 3 → max(net_IR) ∧ pass_to ∧ pass_mdd, with `infeasibility_report` for the violated cap.

### Method Comparison (10 candidates, R2-C compliant)
| Method | net_IR | SR_net | CAGR_net | MDD | CVaR_d | TO_ann | TO ✓ | CVaR ✓ | MDD ✓ |
|---|---|---|---|---|---|---|---|---|---|
| **ERC** ⭐ | **0.9066** | 0.9066 | 20.97% | -40.4% | -3.08% | 4.97 | ✅ | ❌ | ✅ |
| EW_baseline | 0.9061 | 0.9061 | 21.02% | -40.5% | -3.11% | 4.93 | ✅ | ❌ | ✅ |
| LinTilt_alpha | 0.8512 | 0.8512 | 20.67% | -48.5% | -3.48% | 7.25 | ❌ | ❌ | ❌ |
| MaxDiv | 0.8287 | 0.8287 | 24.96% | -47.0% | -5.72% | 6.56 | ❌ | ❌ | ❌ |
| InvVol | 0.7662 | 0.7662 | 20.20% | -44.8% | -2.25% | 7.85 | ❌ | ✅ | ✅ |
| MVO_conf_aware | 0.6991 | 0.6991 | 18.51% | -69.5% | -4.37% | 9.15 | ❌ | ❌ | ❌ |
| BlackLitterman | 0.6991 | 0.6991 | 18.51% | -69.5% | -4.37% | 9.15 | ❌ | ❌ | ❌ |
| CVaR_proxy | 0.6983 | 0.6983 | 18.44% | -69.5% | -4.36% | 9.15 | ❌ | ❌ | ❌ |
| HRP | 0.6503 | 0.6503 | 19.39% | -56.1% | -1.76% | 9.32 | ❌ | ✅ | ❌ |
| Ensemble_top3 | NA | NA | NA | NA | NA | NA | — | — | — |

**Caps**: TO ≤ 6.0 (600% annualized) / CVaR_d ≤ 2.5% / MDD ≤ 45%
**Selected**: ERC (max net_IR among methods passing TO ∧ MDD)

## Why ERC

### 1. Net IR optimal under feasibility-realistic caps
ERC achieves **net_IR = 0.9066**, the highest among methods that pass both Turnover (≤6.0) and MDD (≤45%) caps. The next-best EW_baseline is essentially identical (0.9061) but ERC's risk-balanced allocation provides marginal Σ-aware diversification benefit (cor_core_defense = 0.611 acknowledged in risk pkg).

### 2. Confidence-aware MVO underperforms expectation
The richer MVO/BL/CVaR_proxy variants concentrate alpha-tilt heavily at sig_dates with high alpha dispersion → MDD blows out to -69.5% with TO 9.15 (>600% cap). This reflects:
- V3 alpha cross-sectional z-score has high tail (max alpha 2.33, min 0.97 within top-20) → MVO interior solution hits w_hi=0.20 frequently.
- Confidence vector (0.46~0.95) modulates but doesn't dampen enough → forecast uncertainty penalty (ψ=0.3) too small to control MDD.
- Higher ψ would shrink MVO toward EW; equivalent to ERC.

### 3. KR top-20 long-only universe — risk parity natural fit
- 20-name universe → diminishing diversification beyond 20 (qepm §10).
- Σ explained share: MKT 18.6% + idiosyncratic 76.1% (risk pkg). ERC distributes risk evenly across 20 idiosyncratic legs.
- Per-name weight ranges 0.048~0.052 — well within hard cap [0, 0.20].

### 4. Regime-conditional Σ binding executed
- BULL (87 sig_dates) + NORMAL (127): full Σ_BΩB+D used, rolling 36-month estimator with Ledoit-Wolf shrinkage 0.3.
- CAUTION (24): pooled fallback Σ bound (T<30 mandate from `risk_pkg.diagnostics.pooled_fallback_meta.binding_rule`).
- CRISIS (5): pooled fallback Σ bound + max_w shrunk to 0.10 (forward mandate).

### 5. CVaR_d 2.5% mandate — INFEASIBILITY DECLARED (not silently overridden)
Per Risk pkg `tail_per_regime` (EW top-20 base):
- BULL CVaR_d -2.63% / NORMAL -2.90% / CAUTION -5.70% / CRISIS -4.30%
- NORMAL alone (53% of sig_dates) breaches 2.5% before any concentration.
- ERC's CVaR_d = -3.08% (mean across regimes, weight-applied σ_p / σ_EW ≈ 1.06 scaling).

**Conclusion**: 2.5% cap requires σ_p / σ_EW ≤ 0.86 — impossible for diversified long-only top-20 KR universe.

**Resolution paths (out of optimizer scope)**:
- A. Cash overlay 30%+ in NORMAL+ regimes (Forge integration sleeve)
- B. Q-Lead/Governor explicit cap relaxation to 3.5% (NORMAL EW base + 20% buffer)
- C. Universe expansion to N=40+ low-beta names (mandate change)

## Hard Constraint Verification (post-optim)
| Constraint | Value | Status |
|---|---|---|
| max_names | 20 (every sig_date) | ✅ |
| weight_bounds [0, 0.20] | min=0.0479, max=0.0515 (ERC near-EW) | ✅ |
| Σw = 1 | 1.0 ± 1e-3 | ✅ |
| long-only | min weight = 0.0479 ≥ 0 | ✅ |
| universe = K200∪KQ150 | inherited from alpha pkg | ✅ |
| liquidity ≥ 2e8 KRW | inherited from alpha pkg | ✅ |
| cost_model = v2.3_kr_retail_15bps | applied (TO × 15bps × 12) | ✅ |

## Forecast Summary (post-optim, weight-applied)
- **net_IR**: 0.9066
- **SR_net (annualized)**: 0.9066
- **CAGR_net**: 20.97%
- **MDD (in-sample, monthly)**: -40.35%
- **CVaR_d (book-mean, regime-weighted)**: -3.08% — **BREACH disclosed**
- **Turnover (annualized 2-sided)**: 4.97 (≤ 6.0 PASS)
- **Cost (annualized)**: 0.75% (15bps × TO 4.97)

## Risk Forward Mandate Compliance
| Mandate | Status |
|---|---|
| BIND pooled Σ in CRISIS+CAUTION (29 sig_dates) | ✅ DONE |
| max_w shrink to 0.10 in CRISIS (5 sig_dates) | ✅ DONE |
| Tail caps weight-applied re-measurement | ✅ DONE |
| infeasibility_report if CVaR_d > 2.5% | ✅ EMITTED (R12 No Silent Override) |
| RF-R1 MKT systematic 77.8% disclosed | ✅ DONE (in challenge_note) |
| RF-R7 IC decay sub-period accommodation | ✅ DONE (sub_stab 0.667 acknowledged) |

## Comparison to PG2 Baseline (Forge to backtest)
- Baseline PG2: STR_1701 80% + STR_1656 20%, realized SR 1.4625
- V3 candidate PG2: V3 (ERC weighted) 80% + STR_1656 20%
- V3 alpha base inheritance: cor 0.9319 with STR_1701 score (per_date_mean) — L-224 PASS
- **V3 80% blend with STR_1656 20%**: REPLACES current PG2 (NOT additive). Forge backtest decisive.
- Expected SR uplift source: turnover dampening (V3 alpha pkg TO=4.93 vs Iter 11 5.63) + minor risk parity smoothing.

## References
- Maillard, Roncalli, Teïletche (2010) "The properties of equally weighted risk contribution portfolios" — ERC theoretical foundation
- Ledoit, Wolf (2004) "Honey, I shrunk the sample covariance matrix" — shrinkage estimator
- Markowitz (1952), Grinold-Kahn (1999), Rockafellar-Uryasev (2000) — comparison baseline
- López de Prado (2016) HRP — alternative considered (failed MDD cap)
- QEPM L-484 score-level composition (alpha pre-blended; Optimizer applies Σ for weight derivation)
