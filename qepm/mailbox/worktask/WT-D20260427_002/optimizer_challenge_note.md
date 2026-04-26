# Optimizer Challenge Note — WT-D20260427_002 Iter 18

**Mandate (b)**: Optimizer alpha activation mechanism. Alpha base STR_1701 strict
inheritance (cor=1.0). Goal — PG2 blended (V_iter18 80% + STR_1656 20%) realized
SR > 1.4625 baseline through Optimizer mechanism change ONLY.

## Selected Method: LinTilt_EMA_CVaR
- Iter 11 LinTilt (proven STR_1701 mechanism) + EMA persistence + CVaR penalty
- Reasoning: max(net_IR) ∧ TO_PASS ∧ MDD_PASS subset; alpha_activation_rate 39.3%
  vs. ERC near-EW 0% baseline (L-226 remediation primary KPI).

## Method Comparison (Iter 18, 92 sig_dates × 10 methods)

| Rank | Method | net_IR | SR_net | MDD | CVaR_d | TO | α-act% | HHI | TO✓ | CVaR✓ | MDD✓ |
|------|--------|--------|--------|-----|--------|-----|--------|-----|-----|-------|------|
| 1 | LinTilt_EMA_CVaR | 0.1547 | 0.1547 | -0.4020 | -0.0313 | 5.66 | 39.3% | 0.0890 | ✓ | ✗ | ✓ |
| 2 | Conc_MVO | 0.1517 | 0.1517 | -0.4101 | -0.0324 | 5.74 | 35.1% | 0.1439 | ✓ | ✗ | ✓ |
| 3 | InvVol | 0.1260 | 0.1260 | -0.3814 | -0.0200 | 6.61 | 31.0% | 0.1757 | ✗ | ✓ | ✓ |
| 4 | RP_AlphaTilt | 0.1196 | 0.1196 | -0.3652 | -0.0206 | 6.57 | 31.4% | 0.1852 | ✗ | ✓ | ✓ |
| 5 | CVaR_MVO_adaptive | 0.1067 | 0.1067 | -0.5456 | -0.0336 | 5.94 | 27.4% | 0.1863 | ✓ | ✗ | ✗ |
| 6 | ERC | 0.0707 | 0.0707 | -0.4235 | -0.0287 | 5.10 | 50.6% | 0.0500 | ✓ | ✗ | ✓ |
| 7 | EW_baseline | 0.0691 | 0.0691 | -0.4251 | -0.0290 | 5.08 | 0.0% | 0.0500 | ✓ | ✗ | ✓ |
| 8 | HRP | 0.0384 | 0.0384 | -0.4659 | -0.0149 | 6.92 | 20.7% | 0.3522 | ✗ | ✓ | ✗ |
| 9 | MaxDiv | -0.0915 | -0.0915 | -0.5873 | -0.0530 | 6.57 | 26.7% | 0.1916 | ✗ | ✗ | ✗ |
| 10 | BL_posterior | -0.1582 | -0.1582 | -0.6520 | -0.0511 | 6.23 | 33.9% | 0.1505 | ✗ | ✗ | ✗ |

**Key empirical findings**:
- Active alpha-activation methods (LinTilt+EMA+CVaR / Conc_MVO / RP+Tilt) outperform
  passive baselines (EW / ERC / HRP / MaxDiv) on net_IR.
- BL_posterior with informative posterior **underperforms** on this 92-date
  bi-monthly grid — dominant equilibrium prior + thin local Σ history shrinks alpha
  signal toward EW with poor MDD (-65%).
- CVaR_MVO_adaptive penalty cap fails MDD (-54.6%) — confidence-scaling +
  adaptive ψ over-concentrates to a few low-σ names that under-perform out of sample.
- Concentrated MVO (top-10) close second — alpha activation on top-10 only
  raises HHI to 0.144 but misses bottom 10 names which contribute small positive alpha.

## Why LinTilt_EMA_CVaR (alpha activation focus)

1. **Iter 11 STR_1701 mechanism preserved**: linear z-score tilt onto EW with
   λ_t=0.05, winsor 2σ. EMA with prev_w (α=0.5) for persistence (Iter 11
   TOphi=8 equivalent dampening, achieves TO=5.66 < 6.0 cap).
2. **CVaR penalty (γ=5.0)**: per-name daily CVaR estimate vs CVaR_target/N
   threshold, exponential damping for CVaR-excess names. Tail control without
   over-shrinkage.
3. **alpha_activation_rate 39.3%**: 7-8 out of 20 names with weight > EW
   (vs ERC 50.6% but ERC is risk-balanced not alpha-tilted; vs EW 0%; vs Conc_MVO
   35.1%). LinTilt achieves alpha tilt with controlled TO/MDD.
4. **HHI 0.089 < 0.10 cap**: concentration disclosed but within mandate.
5. **MDD -40.2% < 45% cap**: PASS.
6. **Net_IR 0.155 — bi-monthly grid penalty disclaimer**: Iter 18 alpha panel
   has 92 dates over 16 years (~bi-monthly). Annualization by per_per_year≈5.84
   suppresses √frequency vs Iter 11 monthly (12/yr). Comparable Iter 11 LinTilt
   monthly: SR_net 0.6255. Forge will run on monthly grid for true PG2 blend.

## Infeasibility Report (R12 No Silent Override)

**CVaR_d 2.5% mandate structurally infeasible** (Iter 15 L-226 confirmed):
- KR top-20 long-only NORMAL EW base CVaR_d ≈ -2.90% before any concentration
- All TO_PASS ∧ MDD_PASS methods breach CVaR_d cap (LinTilt -3.13% / Conc -3.24%
  / ERC -2.87% / EW -2.90% / CVaR_MVO -3.36%)
- Only InvVol (-2.00%) and HRP (-1.49%) pass CVaR but fail TO cap

**Suggested resolution** (out of optimizer scope):
- Option A: Forge integration with cash overlay (30% NORMAL+, 50% CRISIS)
- Option B: Q-Lead/Governor relax CVaR_d to 3.5% (NORMAL EW base + 20% buffer)
- Option C: Universe expansion to N=40 with sector cap

## L-226 Remediation Evidence

Iter 15 V3 ERC weights ranged 0.048~0.052 (HHI=0.05, alpha_activation_rate=0%).
Iter 18 LinTilt_EMA_CVaR weights span [W_LO, W_HI=0.20]; HHI=0.089;
**alpha_activation_rate=39.3%** — alpha signal is **ACTUALLY ACTIVATED** in
weights (vs ERC near-EW limitation).

## Hard Constraint Audit (per_sig_date_audit)

- n_names: exactly 20 at every sig_date (92/92 PASS)
- Σw: 1.0 (within 1e-3 tolerance) at every sig_date
- weights ≥ 0 (long-only PASS)
- weights ≤ 0.20 (cap PASS)

## Forge Forward Mandate

**PG2 baseline to beat**: STR_1701 80% + STR_1656 20% realized SR=1.4625

**Iter 18 PG2 candidate**: V_iter18 (LinTilt_EMA_CVaR weights) 80% + STR_1656 20%

**Forge decisive gate**: realized monthly NAV comparison on lockbox-aware test
period. If PG2 blend SR > 1.4625, Iter 18 = success (incremental SR via
mechanism change only, alpha unchanged).

## Codex Round R1

Round 1 critic invocation completed (see codex_critic_response_optimizer.json).
Resolution count: 9/9 mandatory (per L-207 substitute evidence if Codex stalls,
OVERRIDE_005 fallback available).

## References

- Markowitz (1952), Black-Litterman (1992), Rockafellar-Uryasev (2000)
- Lopez de Prado (2018) Adaptive ψ regularization
- Maillard-Roncalli-Teiletche (2010) ERC; Choueifaty-Coignard (2008) MaxDiv
- Iter 11 STR_1701 LinTilt baseline (WT-D20260426_004 optimization_package)
- Iter 15 V3 ERC near-EW (L-226) — alpha activation diagnosis
- Risk pkg Iter 15 inheritance — covariance.parquet pooled fallback (cond=22.83)
