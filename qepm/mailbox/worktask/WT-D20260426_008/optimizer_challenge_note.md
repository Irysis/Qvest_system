# Optimizer Challenge Note — WT-D20260426_008 (Track A Iter 15 V3)

**Agent**: optimizer-research
**Round**: R1 (R3 Challenge Authority + P4 Obligation, GAP-1 patch)
**Objection**: FALSE
**Targets reviewed**:
- alpha_vector (20 names, ICIR 0.31, V3 inheritance L-224 cor=0.9284)
- risk_sigma_full (20×20 BΩB+D, cond=22.83, PSD)
- risk_sigma_pooled_fallback (cond=100, T=57)
- bound_feasibility (max_names=20 × W_HI=0.20 → Σw=1 feasible)
- regime_lambda_neutral_acknowledged (M3 mutation = no-op, alpha pkg honest disclosure)
- crowding_v3_str1701_per_date_0.9319 (L-224 PASS, EXPECTED for direct upgrade)

## Decisions (no objection raised)

### 1. Alpha vector accepted as-is
V3 = STR_1701 score-level inheritance (Iter 11) + 3 mutations (slot/persistence/regime-λ).
Mutation 3 (regime λ neutral) has no economic effect — Codex critic R1 (alpha) flagged this.
Optimizer treats this as a transparency issue for Forge backtest, not optimizer-fixable.

### 2. Risk Σ binding rules executed
- BULL/NORMAL (211/240 sig_dates, 87.9%): full Σ_BΩB+D used (with rolling per-sig_date estimate from Ret_1m × 36-month window, Ledoit-Wolf shrinkage 0.3).
- CRISIS (5/240 sig_dates, 2.1%): pooled fallback Σ bound + max_w shrunk to 0.10.
- CAUTION (24/240 sig_dates, 10.0%): pooled fallback bound (T<30 mandate from risk pkg per_regime_meta), max_w 0.20 (CAUTION not in shrink list).

### 3. Method shopping log (10 candidates, R2-C compliant)
| Method | SR_net | CAGR_net | MDD | CVaR_d | TO_ann | TO_PASS | CVaR_PASS | MDD_PASS |
|---|---|---|---|---|---|---|---|---|
| **ERC** | **0.9066** | **20.97%** | **-40.4%** | **-3.08%** | **4.97** | YES | NO | YES |
| EW_baseline | 0.9061 | 21.02% | -40.5% | -3.11% | 4.93 | YES | NO | YES |
| LinTilt_alpha | 0.8512 | 20.67% | -48.5% | -3.48% | 7.25 | NO | NO | NO |
| MaxDiv | 0.8287 | 24.96% | -47.0% | -5.72% | 6.56 | NO | NO | NO |
| InvVol | 0.7662 | 20.20% | -44.8% | -2.25% | 7.85 | NO | YES | YES |
| MVO_conf_aware | 0.6991 | 18.51% | -69.5% | -4.37% | 9.15 | NO | NO | NO |
| BlackLitterman | 0.6991 | 18.51% | -69.5% | -4.37% | 9.15 | NO | NO | NO |
| CVaR_proxy | 0.6983 | 18.44% | -69.5% | -4.36% | 9.15 | NO | NO | NO |
| HRP | 0.6503 | 19.39% | -56.1% | -1.76% | 9.32 | NO | YES | NO |
| Ensemble_top3 | NA | NA | NA | NA | NA | — | — | — |

**Selection rule applied**: hierarchical (no method passes all 3 caps).
- Priority A (max_net_IR ∧ pass_to ∧ pass_mdd): ERC chosen (0.9066).
- Priority B (CVaR_d only): InvVol or HRP — both fail other caps.
- Ensemble_top3 not constructed (insufficient PASS methods).

### 4. CVaR_d 2.5% mandate — INFEASIBILITY DECLARED
**Structural diagnosis**:
- Risk pkg per-regime daily CVaR (EW top-20 base):
  - BULL: -2.63% / NORMAL: -2.90% / CAUTION: -5.70% / CRISIS: -4.30%
- NORMAL alone (127/240 sig_dates, 53%) breaches 2.5% before any concentration.
- Required σ_p / σ_EW ≤ 0.86 to comply — impossible for diversified long-only top-20 (ERC ratio ≈ 1.06).
- Only InvVol (-2.25%) passes by extreme low-vol concentration → fails TO cap.

**Resolution paths (out of optimizer scope)**:
- A. Cash overlay 30%+ at sleeve composition stage (Forge integration)
- B. Q-Lead/Governor explicit cap relaxation to 3.5% (matches NORMAL EW base + 20% buffer)
- C. Universe expansion to N=40+ (mandate change)

**Optimizer decision**: ERC selected with `infeasibility_report` emitted (R12 No Silent Override).
Forge/Governor decisive on PG2 admission; Optimizer cannot fix universe-level CVaR floor.

### 5. RF disclosures (Risk pkg forward mandate)
- **RF-R1 (MKT systematic 77.8%)**: Acknowledged. ERC concentrates equally on idiosyncratic risk; cannot reduce systematic share without sector tilts beyond top-20 hard cap.
- **RF-R7 (IC decay)**: Sub-period stability 0.667 (P1 IC=0.056 / P2 IC=0.020 / P3 IC=-0.0025). Optimizer-side: weight calibration uses cross-sectional alpha signal at sig_date — no IC time-series weighting. Forge backtest decisive on decay impact.
- **RF-CRISIS-COUPLING**: Pooled Σ binding executed on 5 CRISIS sig_dates + 24 CAUTION sig_dates (29/240, 12.1%). max_w 0.10 active in 5 CRISIS only.
- **RF-CROWD-V3-STR1701**: ERC weights are nearly EW (0.0479~0.0515), confirming "V3 80% replaces STR_1701 80%" is essentially a same-universe tilt — Forge must compare PG2(V3 80% + STR_1656 20%) vs PG2(STR_1701 80% + STR_1656 20%) on realized SR/MDD/TO.

### 6. RF-A2 (Alpha challenge) acknowledged
V3 ICIR (0.3132) < single Core ICIR (0.4147), composite advantage <5%. Optimizer cannot fix alpha quality — pass-through to Forge.

## P4 audit confirmation
All 5 review targets verified. No silent override applied. Mandate-blocked CVaR cap explicitly reported (not bypassed).
