# Alternative Weight Comparison Protocol — DPL_KR_v3

**WT-D20260519_001 · optimizer-research Step 2**
**Date**: 2026-05-18
**Author**: optimizer-research agent (autonomous)
**Inherits**: `WT-D20260517_001/optimizer_comparison_protocol.md` (v1, B1-B6) — paradigm-shift baseline doctrine retain (Codex v1 C4 REBUTTAL)
**v3 extension**: 7-baseline framework (B1-B7) — added B7_DPL_v3_with_MVO_post_hoc to test "weights → MVO refinement" as separate Two-stage paradigm baseline.

---

## 0. Doctrine — Why Compare?

### 0.1 Paradigm-Shift Baseline Doctrine (Codex v1 C4 REBUTTAL inherit)

DPL paradigm = features → weights direct learning (You-Zhang 2025 RFS). Production weights are emitted by DPL only. Baselines (B1-B7) serve **post-hoc validation** purpose:

1. **Paradigm value-add proof**: Does DPL > MVO with same DPL alpha scores? (B1)
2. **Cost-aware proof**: Does DPL TO < HRP / ERC / MVO TO? (B2/B3/B4)
3. **Tail-aware proof**: Does DPL MDD ≤ CVaR_LP MDD on stress windows? (B5)
4. **Trivial paradigm rejection**: Does DPL SR > EW top-20 by DPL alpha rank? (B6)
5. **Refinement test**: Does DPL > DPL → MVO post-hoc? (B7 NEW — tests if MVO refinement on DPL output helps)

**Production weights**: DPL_v3 only (4-stage projection direct emission). Failure mode → WT reject, no baseline substitution (Codex v1 C4 REBUTTAL doctrine retain).

### 0.2 Same-harness Mandate

All baselines + DPL evaluated under:
- **Same period**: 13 walk-forward windows × 24m test = 304 test months (도훈 mandate 2026-05-19)
- **Same universe**: KR_TOP500_LIQ1E8 per sig_date (2e8 KRW 20d ADV)
- **Same cost**: 0.0015 × 2 × Σ|Δw| round-trip per rebalance (15bps one-way)
- **Same Σ**: LW identity oracle 60m rolling (risk_package canonical)
- **Same alpha source for B1/B6**: DPL_v3 ScoreHead Z-scored output (NOT separate alpha)
- **PerformanceAnalytics geometric convention**: Charter v1.5 §13 — `Return.portfolio` → `table.AnnualizedReturns` → `maxDrawdown`

### 0.3 Test Months Schedule (Extended per 도훈 mandate)

| Window | Train (60m) | Val (12m) | Test (24m) | Crisis embedded |
|---|---|---|---|---|
| 1 | 1995-01 ~ 1999-12 | 2000-01 ~ 2000-12 | 2001-01 ~ 2002-12 | Dotcom crash |
| 2 | 1997-01 ~ 2001-12 | 2002-01 ~ 2002-12 | 2003-01 ~ 2004-12 | recovery |
| 3 | 1999-01 ~ 2003-12 | 2004-01 ~ 2004-12 | 2005-01 ~ 2006-12 | calm |
| 4 | 2001-01 ~ 2005-12 | 2006-01 ~ 2006-12 | 2007-01 ~ 2008-12 | GFC |
| 5 | 2003-01 ~ 2007-12 | 2008-01 ~ 2008-12 | 2009-01 ~ 2010-12 | post-GFC |
| 6 | 2005-01 ~ 2009-12 | 2010-01 ~ 2010-12 | 2011-01 ~ 2012-12 | EU crisis |
| 7 | 2007-01 ~ 2011-12 | 2012-01 ~ 2012-12 | 2013-01 ~ 2014-12 | calm |
| 8 | 2009-01 ~ 2013-12 | 2014-01 ~ 2014-12 | 2015-01 ~ 2016-12 | China A-share |
| 9 | 2011-01 ~ 2015-12 | 2016-01 ~ 2016-12 | 2017-01 ~ 2018-12 | Vol Mageddon |
| 10 | 2013-01 ~ 2017-12 | 2018-01 ~ 2018-12 | 2019-01 ~ 2020-12 | COVID |
| 11 | 2015-01 ~ 2019-12 | 2020-01 ~ 2020-12 | 2021-01 ~ 2022-12 | Inflation 2022 |
| 12 | 2017-01 ~ 2021-12 | 2022-01 ~ 2022-12 | 2023-01 ~ 2024-12 | post-inflation |
| 13 | 2019-01 ~ 2023-12 | 2024-01 ~ 2024-12 | 2025-01 ~ 2026-04 | recent |

**Total test months**: 24m × 12 + 16m × 1 = 304 (5.85× vs v1 52m).

Crisis-explicit windows (alpha-research crisis_sample_inclusion_v3.md §3.2): W1, W4, W6, W8, W9, W10, W11 = 7 of 13 (G3' gate).

---

## 1. Baseline Framework — 7 Methods

### B1 — MVO with DPL Scores (Two-stage Paradigm)
- **μ̂**: DPL_v3 ScoreHead Z-scored s^i_t (top-20 selected by argsort)
- **Σ**: risk_package canonical (LW identity oracle 60m rolling per-sig_date)
- **Method**: `quadprog::solve.QP` standard MVO with bounds [0, 0.20], Σw = 1, long-only
- **Lambda**: ∈ {1.0, 2.0, 4.0} grid sweep
- **Purpose**: paradigm value-add proof. If `SR(DPL_v3) > SR(B1_MVO with DPL scores)` AND `MDD(DPL_v3) ≤ MDD(B1)` → paradigm value-add confirmed
- **Pkg**: `02_Infrastructure/portfolio/mean_variance_optimizer.R::mvo_weights()`

### B2 — Hierarchical Risk Parity (HRP, López de Prado 2018 Ch 16)
- **Input**: Σ correlation hierarchy from LW oracle
- **Method**: quasi-diagonalization → recursive bisection allocation
- **Top-20 selection**: by DPL_v3 ScoreHead top-20 (then HRP within)
- **Purpose**: TO benchmark + diversification baseline (HRP typically low-TO + balanced)
- **Pkg**: `02_Infrastructure/portfolio/hrp_core.R::hrp_weights()`

### B3 — Equal Risk Contribution (ERC, Maillard-Roncalli-Teïletche 2010)
- **Input**: Σ from LW oracle
- **Method**: iterative root-find s.t. all marginal risk contributions equal
- **Top-20 selection**: by DPL_v3 ScoreHead top-20
- **Purpose**: risk-parity baseline + concentration floor benchmark
- **Pkg**: direct implementation

### B4 — CVaR LP (Rockafellar-Uryasev 2000)
- **Input**: T=60m return history of top-20 by DPL_v3 score
- **α_level**: 0.05
- **Method**: `Rglpk::Rglpk_solve_LP` linear program min CVaR_5%
- **Purpose**: tail-aware baseline. If `MDD(DPL_v3) ≤ MDD(B4_CVaR_LP)` over crisis windows → DPL tail-aware competitive
- **Caveat (CF-O5-v1 inherit)**: CRISIS regime ~24/304 obs, sample bias. Forge regime-conditional bootstrap injection optional.
- **Pkg**: `02_Infrastructure/portfolio/advanced_weights.R::cvar_lp_weights()`

### B5 — Maximum Diversification (Choueifaty-Coignard 2008)
- **Input**: Σ correlation matrix
- **Method**: max `(w' σ) / sqrt(w' Σ w)` = max diversification ratio
- **Top-20 selection**: by DPL_v3 ScoreHead top-20
- **Purpose**: diversification-maximizing baseline
- **Pkg**: `02_Infrastructure/portfolio/advanced_weights.R::maxdiv_weights()`

### B6 — Equal Weight Top-20 (EW Reference)
- **Input**: DPL_v3 ScoreHead top-20 rank
- **Method**: w_i = 1/20 = 0.05 for i ∈ top-20, else 0
- **Purpose**: AX-007 #4 ML sizing exemption validity reference. HHI = 0.05 floor reference. If `SR(DPL_v3) > SR(B6_EW)` AND `HHI(DPL_v3) > 0.06` → ML sizing exemption demonstrated.

### B7 — DPL_v3 → MVO Post-hoc Refinement (NEW vs v1)
- **Input**: DPL_v3 emitted weights `w_DPL_t` as warm-start
- **Method**: Local MVO refinement around `w_DPL_t`, fixed top-20 names, perturbation bounded to `||w_new - w_DPL_t||_2 < 0.05`
- **Purpose**: tests whether MVO refinement on DPL output adds value. If yes → suggests DPL underweights risk-aware optimization (room for hybrid). If no → DPL paradigm self-sufficient.
- **Note**: NEW vs v1 — added to probe paradigm value-add depth.

---

## 2. Comparison Table Schema

For each method × walk-forward window:

| Column | Definition | Source |
|---|---|---|
| `method_name` | B1_MVO, B2_HRP, ..., B7, DPL_v3 | enum |
| `window_id` | 1-13 | enum |
| `test_months` | 24m (1-12) or 16m (13) | int |
| `gross_sr` | annualized Sharpe (gross, before cost) | PerformanceAnalytics `SharpeRatio.annualized()` |
| `net_sr` | annualized Sharpe (net of 0.0015 × 2 × TO) | PerformanceAnalytics |
| `net_ir` | (net_return - bench_return) / TE | `InformationRatio()` |
| `mdd` | max drawdown over test | `maxDrawdown()` |
| `cagr` | annualized CAGR | `Return.annualized()` |
| `turnover_annual` | Σ|Δw|_1 × (12 / n_months) | direct compute |
| `cost_realized` | 0.0015 × 2 × Σ|Δw|_1 per rebalance | direct compute |
| `hhi_mean` | mean HHI over test | `Σw_i²` per sig_date averaged |
| `hhi_sector_mean` | mean sector HHI | post-mapping |
| `cor_vs_str1715` | per-sig_date Pearson cor of alpha vs STR_1715 PG2 | post-Forge |
| `cor_vs_dpl_v3` | for baselines, cor of weights vs DPL_v3 weights | post-Forge |
| `jaccard_top10_stability` | adjacent sig_date top-10 Jaccard overlap | direct compute |

**Aggregate across windows**: weighted mean by test_months. Report median + IQR for robustness.

---

## 3. Decision Logic — Selection vs Production

### 3.1 Selection Logic (post-Forge realized)

```
selection_objective = "net_ir"   (v6.1 R4 P3 mandate)

# Step 1: Filter feasibility
candidates = [m for m in [DPL_v3, B1, ..., B7]
              if HHI(m) > 0.06 AND TO_annual(m) < 6.0 AND MDD(m) > -0.25]

# Step 2: Paradigm value-add (DPL_v3 first)
if DPL_v3 in candidates AND net_ir(DPL_v3) >= net_ir(B1):
    paradigm_value_add = True
else:
    paradigm_value_add = False  # → REJECT entire WT (Codex v1 C4 doctrine)

# Step 3: Select by net_ir (DPL_v3 only, baselines are post-hoc)
selected_method = "DPL_v3" if paradigm_value_add else None
```

### 3.2 Production Doctrine (Codex v1 C4 REBUTTAL retain)

- Production = DPL_v3 weights direct emission
- Baselines (B1-B7) = post-hoc validation only
- If DPL_v3 paradigm value-add FAIL → WT reject (Scenario C from v1)
- NO baseline substitution at production stage

### 3.3 Sequential Admission Scenarios (Codex v1 C8 inherit)

Post-Forge G2 cor measurement decides scenario:

| Scenario | Trigger | Book Mutation |
|---|---|---|
| A: 4th orthogonal source | `|cor(DPL_v3, STR_1715)| < 0.3` AND G5 PASS | 1-sleeve {STR_1715 100%} → 2-sleeve {STR_1715 75%, DPL_v3 25%} (mid-cycle blender review) |
| B: Substitution | `0.3 ≤ |cor| < 0.5` AND G5 single-replacement PASS | 1-sleeve {STR_1715 100%} → 1-sleeve {DPL_v3 100%} |
| C: Reject | `|cor| ≥ 0.5` OR G5 FAIL OR `SR(DPL_v3) < STR_1715`baseline | 1-sleeve {STR_1715 100%} retain — no admit |

**Q-Lead authority**: Scenario A blend ratio (75/25 nominal) post-Forge re-optimize via Blender agent if multiple admit candidates available. v3 cycle = single candidate, so 75/25 default if Scenario A triggers.

---

## 4. Method Shopping Log (v6.1 R2-C)

| # | Method | Selected | Rationale |
|---|---|---|---|
| 1 | DPL_v3 (Continuous softmax + STE + PAN + Partial Adjust) | YES (primary) | architecture §0 — Original DPL paradigm |
| 2 | B1 MVO with DPL scores | post-hoc | Two-stage paradigm baseline |
| 3 | B2 HRP | post-hoc | TO + diversification baseline |
| 4 | B3 ERC | post-hoc | risk-parity baseline |
| 5 | B4 CVaR LP | post-hoc | tail-aware baseline |
| 6 | B5 MaxDiv | post-hoc | diversification-max baseline |
| 7 | B6 EW top-20 | post-hoc | ML sizing exemption reference |
| 8 | B7 DPL_v3 → MVO refinement | post-hoc | paradigm depth probe (NEW) |

**candidates_tried**: 8 (under cap 10, v6.1 R2-C compliant).

**Differentiable top-K alternatives evaluated (inherit v1 + revised for v3)**:

| Alternative | v3 Verdict |
|---|---|
| Continuous softmax + STE top-K | **RETAIN (DEFAULT v3)** — primary mechanism |
| Gumbel softmax + STE | REJECT (v1 EW collapse precedent) |
| Sinkhorn balanced | REJECT (O(N²) compute prohibitive for N=500) |
| Hungarian relaxation | REJECT (combinatorial, O(N³)) |
| Sparsemax / α-entmax | PARTIAL (v3.1 ablation if continuous softmax HHI degenerate) |
| Smoothed projection (Beck-Teboulle 2009) | NEAR-EQUIVALENT (architecture-equivalent to PAN) |
| Top-K relaxation via Gumbel-rao | REJECT (v3 STE alternative was avoided to prevent v1 EW collapse) |

**Selected**: Continuous softmax + STE top-K. Rationale: 
- Compute O(N) for softmax + O(N log K) for argsort = O(N log K) total
- Deterministic at inference (no stochastic sampling)
- Differentiable backward (STE pass-through)
- Direct concentration penalty support `λ_conc · (HHI - 0.10)²`

---

## 5. Risk Model Inheritance (risk_package.json integration)

| Risk Construct | risk_package source | Optimizer usage |
|---|---|---|
| Σ 259×259 LW identity oracle | `covariance.parquet` (kappa 52.4, eig_ratio 84.7, PSD ✓) | B1/B2/B3/B5 input |
| Factor B 259×22 ridge | `exposure_betas_ridge.parquet` (canonical post-collinearity) | B5 MaxDiv σ_i |
| Specific risk D 259 | `specific_risk.parquet` | Σ decomp diagnostics |
| Tail risk CVaR/EVT | `tail_risk.json` (CVaR_95=-35.3%, ξ=2.27 heavy) | universe baseline (NOT strategy) |
| 8 stress windows | `tail_stress_protocol.json` | reference for crisis-explicit windows |
| Crowding score per factor (Acadian 2026) | `crowding_score_audit.parquet` (14 ELEVATED, 0 HIGH) | post-Forge per-DPL-weight audit |
| PG2 comparison (TDC + style cor + return cor) | `risk_summary.pg2_comparison` (TDC 0.32, style 0.965, return 0.196) | **design-phase prior** RF-R6 carry to Forge |
| Regime-conditional Σ (Crisis 24 / Normal 46 / Calm 19) | `regime_correlation.parquet` | optional B1 regime-conditioning ablation Forge |

**Constraint inheritance from risk_package §infeasibility_report**:
- CVaR_95 breach (universe baseline -35.3% vs role-prompt cap -2.5%) — **acknowledged**. **NOT auto-applied to DPL_v3 weights**. Forge cycle realized DPL CVaR will be re-measured; if also breaches → infeasibility_report at Forge stage.
- Stress dotcom severe (-90.7% universe) — universe baseline, DPL strategy will differ via concentration + top-20 + Sharpe surrogate loss.

---

## 6. Parallel Execution Plan (v6.1 R13)

```r
library(future)
library(future.apply)
n_workers <- min(7L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)

baselines <- list(
  list(name = "B1_MVO",        fn = function() mvo_weights(alpha_dpl, Sigma, lambda=2.0, bounds=c(0, 0.20))),
  list(name = "B2_HRP",        fn = function() hrp_weights(Sigma, bounds=c(0, 0.20))),
  list(name = "B3_ERC",        fn = function() erc_weights(Sigma, bounds=c(0, 0.20))),
  list(name = "B4_CVaR_LP",    fn = function() cvar_lp_weights(returns_60m, alpha_level=0.05, bounds=c(0, 0.20))),
  list(name = "B5_MaxDiv",     fn = function() maxdiv_weights(Sigma, bounds=c(0, 0.20))),
  list(name = "B6_EW_top20",   fn = function() ew_top20_weights(alpha_dpl)),
  list(name = "B7_DPL_MVO",    fn = function() local_mvo_refine(w_dpl, Sigma, perturb=0.05))
)

results <- future_lapply(baselines, function(b) {
  tryCatch(b$fn(),
           error = function(e) list(ok = FALSE, error = conditionMessage(e)))
})
plan(sequential)
```

**Forge cycle target**: ≤ 30s per sig_date for 7-baseline compute. Total for 304 sig_dates: ≤ 2h.

---

## 7. Expected Outputs (Forge cycle mandate)

| Artifact | Path | Schema |
|---|---|---|
| `optimizer_comparison.parquet` | `stage_artifacts/WT_D20260519_001/` | 304 sig_dates × 8 methods × 14 columns |
| `optimizer_comparison_summary.json` | `stage_artifacts/WT_D20260519_001/` | aggregate decision + selection_objective |
| `weight_comparison_per_sigdate.parquet` | `stage_artifacts/WT_D20260519_001/` | audit trail per-sig_date weights for all 8 methods |
| `paradigm_value_add_audit.json` | `stage_artifacts/WT_D20260519_001/` | DPL_v3 vs B1 SR/MDD comparison (paradigm doctrine) |

---

## 8. Sensitivity Audit (Optimizer scope)

### 8.1 Lambda sensitivity (B1 MVO with DPL scores)

`λ ∈ {0.5, 1.0, 2.0, 4.0}` grid → measure realized B1_SR(λ). If sensitivity > 30% across λ grid → B1 unstable, comparison less informative. Report stability.

### 8.2 LW shrinkage δ sensitivity (B1/B2/B3/B5 input)

risk_package δ = 0.23 (oracle). Ablation: δ ∈ {0.10, 0.23, 0.50}. If B1_SR(δ=0.10) >> B1_SR(δ=0.23) → δ choice matters. Risk_package δ=0.23 is canonical (do not modify).

### 8.3 STR_1715 alpha-inheritance per-sig_date

For each sig_date: `cor(DPL_v3_alpha_score_t, STR_1715_alpha_score_t)`. 
- Mean cor over 304 months → G2 metric
- Rolling 12m mean → temporal stability check
- If cor very stable around 0.5 → consider scenario B (substitution); if oscillates 0.2-0.6 → scenario A (4th source) ambiguous

---

## 9. Binding Constraints Forecast (Design-Time Expected)

| Constraint | Expected to bind? | Rationale |
|---|---|---|
| `max_names = 20` (STE top-K hard) | **ALWAYS binding** | architecture mandate |
| `weight_bounds[2] = 0.20` (PAN clip) | OFTEN binding | top-3 scores typically near 0.20 |
| `Σw = 1` (PAN L1) | ALWAYS binding | normalization |
| `long-only` (softmax > 0) | ALWAYS binding | structural |
| `TO_annual < 6.0` | SOMETIMES binding | depends on λ_to grid + α |
| Universe LIQ ≥ 2e8 | per-sig_date filter | structural |
| Sector HHI ≤ 0.30 (risk inherit) | RARELY binding | DPL family-balanced 80 features |
| Portfolio HHI ≤ 0.15 (risk inherit) | post-Forge measure | concentration penalty target 0.10 < 0.15 |

**RF-O1 binding count check**: 4 always-binding (top-K, Σw=1, long-only, LIQ) + 1 often (cap 0.20) = 5 of ~10 constraints actively bind. K/2 = 10/2 = 5 → **at threshold**. Forge cycle re-evaluate post-Forge. No alarm at design phase.

---

## 10. Conclusion

7-baseline comparison protocol established. Production = DPL_v3 only (paradigm doctrine retain). Selection objective = `net_ir`. Method shopping under cap (8 ≤ 10). All baselines use same-harness PerformanceAnalytics geometric convention + same cost + same Σ.

**Forge cycle mandate**: execute 7 baselines × 304 test months × 13 windows in parallel (future_lapply). Emit `optimizer_comparison.parquet` + `paradigm_value_add_audit.json`. Selection decision = post-Forge realized net_ir.

**v1 inheritance retain**: paradigm-shift baseline doctrine (Codex C4 REBUTTAL) + Stage 3-4 violation_rate = 0 strict + Dykstra v1.0 fallback (Codex C3 ACCEPT) + cost convention explicit 0.0015 × 2 × |Δw| per rebalance (Codex C6 ACCEPT) + sequential admission A/B/C scenarios (Codex C8 PARTIAL ACCEPT).

**v3 NEW elements**:
- B7 DPL → MVO post-hoc baseline (paradigm depth probe)
- 13 walk-forward / 304 test months (도훈 mandate 2026-05-19 extension)
- Crisis-explicit 7 windows for G3' gate
- PG2 style cor 0.965 acknowledged as design-phase prior (RF-R6) — Forge re-measure on realized DPL weights

---

**End of Alternative Weight Comparison Protocol v3**
