# Weight Method Selected — WT-D20260427_002 Iter 18

## Selected: LinTilt_EMA_CVaR

### Method Definition
$$w_i \propto \text{rank}(\text{score}_i)^{\lambda_t} \times \exp(-\gamma \cdot \max(0, w_i \times \sigma_i \times 1.96 - \text{CVaR}_{\text{target}}))$$
$$w_t^{\text{final}} = \alpha_{\text{EMA}} \cdot w_t^{\text{tilt}} + (1 - \alpha_{\text{EMA}}) \cdot w_{t-1}^{\text{final}}$$

### Hyperparameters
- λ_t = 0.05 (tilt slope, winsor ±2σ)
- γ = 5.0 (CVaR penalty)
- α_EMA = 0.5 (persistence_window=2 dampening)
- weight_bounds = [0, 0.20]
- max_names = 20
- Σw = 1.0 (long-only absolute)

## Selection Rationale

### Iter 18 Mandate (b — Optimizer Track)
- Alpha base STR_1701 strict inheritance (cor=1.0 ≥ 0.95 strict L-224 v2)
- Optimizer mechanism only — alpha 변경 절대 금지
- L-226 remediation: Iter 15 V3 ERC near-EW (alpha activation 0%) → 본 Iter alpha activation 39.3%

### Selection Rule: max(net_IR) ∧ TO_PASS ∧ MDD_PASS
Among 10 method candidates compared:

| Rank | Method | net_IR | α_act% | MDD | TO | CVaR_d | Selected |
|------|--------|--------|--------|-----|----|--------|----------|
| 1 | **LinTilt_EMA_CVaR** | **0.1547** | **39.3%** | -0.402 | 5.66 | -0.0313 | ✓ |
| 2 | Conc_MVO | 0.1517 | 35.1% | -0.410 | 5.74 | -0.0324 | |
| 3 | InvVol | 0.1260 | 31.0% | -0.381 | 6.61 (FAIL) | -0.0200 | |
| 4 | RP_AlphaTilt | 0.1196 | 31.4% | -0.365 | 6.57 (FAIL) | -0.0206 | |
| 5 | CVaR_MVO_adaptive | 0.1067 | 27.4% | -0.546 (FAIL) | 5.94 | -0.0336 | |
| 6 | ERC | 0.0707 | 50.6% | -0.424 | 5.10 | -0.0287 | (alpha-tilt 부재) |
| 7 | EW_baseline | 0.0691 | 0.0% | -0.425 | 5.08 | -0.0290 | |
| 8 | HRP | 0.0384 | 20.7% | -0.466 (FAIL) | 6.92 (FAIL) | -0.0149 | |
| 9 | MaxDiv | -0.0915 | 26.7% | -0.587 (FAIL) | 6.57 (FAIL) | -0.0530 | |
| 10 | BL_posterior | -0.1582 | 33.9% | -0.652 (FAIL) | 6.23 (FAIL) | -0.0511 | |

### Why LinTilt_EMA_CVaR wins
1. **Highest net_IR among TO_PASS ∧ MDD_PASS subset**: 0.155 > Conc_MVO 0.152 > CVaR_MVO 0.107
2. **alpha_activation_rate 39.3%** (L-226 remediation) — 7~8 names with weight > EW
3. **Iter 11 STR_1701 mechanism preserved**: linear z-score tilt onto EW + winsor ±2σ + EMA(α=0.5)
4. **CVaR penalty γ=5.0**: exponential damping for per-name CVaR-excess (vs CVaR_target/N)
5. **TO=5.66 < 6.0 cap PASS** (EMA persistence equivalent to Iter 11 TOphi=8 dampening)
6. **MDD=-40.2% < 45% cap PASS**
7. **HHI=0.089 < 0.10 cap** — concentration controlled

### Why CVaR_MVO_adaptive (CVaR-aware MVO with adaptive ψ — mandate primary candidate) loses
- ψ_t = ψ_base × (CVaR_t/CVaR_target)^β over-shrinks high-vol names → portfolio over-concentrates to a few low-σ names
- MDD blows out to -54.6% (FAIL 45% cap)
- alpha_activation_rate only 27.4% (lower than LinTilt's 39.3%)
- Confirms Iter 15 finding: caps too strict → alpha activation suppressed (request.json hypothesis ψ adaptive proves insufficient at top-20 KR universe)

### Why BL_posterior (Black-Litterman informative posterior — mandate candidate 2) loses
- Equilibrium prior μ_eq = λ × Σ × w_eq dominates posterior at this thin local Σ history
- 92-date bi-monthly grid limits posterior precision
- Information ratio severely negative (-0.158); MDD -65.2% (FAIL)
- Forge would need monthly grid + longer τ tuning for BL to compete

## Infeasibility Report (R12 No Silent Override)

CVaR_d 2.5% mandate **structurally infeasible** for KR top-20 long-only universe:
- NORMAL EW base CVaR_d ≈ -2.90% (Iter 15 Risk pkg per_regime baseline)
- All TO_PASS ∧ MDD_PASS methods breach CVaR cap
- Resolution out of optimizer scope:
  - Forge cash overlay (30% NORMAL+, 50% CRISIS)
  - Governor explicit cap relaxation (3.5%)
  - Universe expansion (mandate change)

## Hard Constraint Audit

- 92 sig_dates × 20 names = 1840 weight rows ✓
- Σw=1 within 1e-3 at every sig_date ✓
- weights ∈ [0, 0.20] ✓
- long-only (no negative weights) ✓
- max_names = 20 ✓ (exactly)

## Forge Forward Mandate

**PG2 baseline to beat**: STR_1701 80% + STR_1656 20% realized SR=1.4625

**Iter 18 PG2 candidate**: V_iter18 LinTilt_EMA_CVaR weights × 80% + STR_1656 20%

**Forge decisive gate**: realized monthly NAV comparison. If PG2 blend SR > 1.4625,
Iter 18 = success (incremental SR via Optimizer mechanism only, alpha unchanged).

## Frequency Disclaimer

Iter 18 alpha panel is bi-monthly (92 dates over 16 years, per_per_year≈5.84).
Annualization √frequency suppresses SR vs monthly grid (Iter 11 LinTilt SR_net 0.6255
on monthly 12/yr). Forge will run on monthly grid for true PG2 blend evaluation.

## References

- Markowitz (1952), Lopez de Prado (2018) Adaptive Regularization
- Iter 11 STR_1701 Linear_Tilt λ=1.0 TOphi=8 (PG2 active 80%)
- Iter 15 V3 ERC near-EW L-226 — alpha activation diagnosis
- Risk pkg Iter 15 inheritance (covariance.parquet, cond=22.83)
- Black-Litterman (1992), Rockafellar-Uryasev (2000)
